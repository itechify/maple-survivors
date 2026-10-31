extends TestCase
## Corsair's Homing Beacon (spec #384 C8, ticket #392): a 148 -> 380% parrot shot that marks one monster (the all-element mark,
## C7 #391), with the Bullseye rarity bonus. Fixed 1/60 s ticks, seeded RNG; the Skill.wz levels are the synthetic fixture table
## unless a test says "real cache" (those call require_cache() and SKIP without it).

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const CF := preload("res://tests/fixtures/corsair_fixtures.gd")
const DT := 1.0 / 60.0
const KEY := "homing_beacon"


## A quiet round of a Corsair holding a pistol with only the Beacon learned at `rank_value`, mobs frozen and tiny.
func _world(rank_value := 1, p_seed := 392) -> RunWorld:
	var data := RF.quiet_data()
	var setup := RF.with_basic_attack(RF.setup("quiet", p_seed, data))
	setup.equipment_info.merge({CF.PISTOL: {"incPAD": 20, "attackSpeed": 6, "tuc": 7}}, true)
	for action: String in ["shoot1", "shoot2", "homing"]:
		setup.body_img[action] = {"0": {"delay": 100.0}, "1": {"delay": 100.0}}
	setup.skill_imgs["521"] = {"skill": {"5211006": {"level": CF.beacon_levels()}}}
	setup["job"] = 522
	var w := RunWorld.new(setup)
	RF.place_player(w, 400)
	if w.weapon_id() != CF.PISTOL:
		w.wear_new_item(CF.PISTOL)
	for mk: MobKind in w.mob_kinds:
		mk.hitbox = Rect2(-20, -50, 40, 50)
		mk.move_speed = 0
	w.god = true
	w.loadout.ranks.clear()
	w.loadout.order.clear()
	assert_true(w.learn_skill(KEY), "the Beacon is learnable by a Corsair")
	w.loadout.set_rank(KEY, rank_value)
	w.refresh_player_stats()
	w.drain_events()
	return w


## Damage x100 on the Beacon so rounding cannot hide the mark's ratio in a whole-number hit.
func _heavy(w: RunWorld) -> void:
	w.loadout.add_skill_mod(KEY, "damage", "mul", 100.0)


func _mob(w: RunWorld, dx: float, hp := 100000.0) -> int:
	var slot := RF.put_mob(w, 1110100, w.player.pos.x + dx, 190, hp)
	w.swarm.alpha[slot] = 1.0
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	return slot


func _run(w: RunWorld, ticks: int) -> void:
	for tick in ticks:
		w.step(DT, MoveInput.new())


func _marked(w: RunWorld, slot: int) -> bool:
	return w.swarm.status_time(slot, MobSwarm.ALL_WEAK) > 0.0


## The damage of one hit of the Beacon's own stats on `slot` with the RNG put back first, so two calls differ only by the mark.
func _hit_damage(w: RunWorld, slot: int, rng_state: int) -> int:
	w.rng.state = rng_state
	w.drain_events()
	w.hit_mob(slot, w.loadout.stats(KEY), -1)
	var damage := -1
	for e: Dictionary in w.drain_events():
		if e.type == "mob_hit":
			damage = int(e.damage)
	return damage


# --- the definition ----------------------------------------------------------------------------------------------------

func test_the_beacon_is_a_marking_parrot_shot_with_the_specs_numbers() -> void:
	var w := _world()
	var d := w.book.def(KEY)
	assert_eq(int(d.skill_id), 5211006)
	assert_eq(String(d.book), "521")
	assert_eq(int(d.job), 521)
	assert_eq(String(d.slot), "active")
	assert_false(d.has("weapon_families"), "a weapon gates nothing")
	assert_false(d.has("ranks"), "the default 30-level table")
	assert_eq(w.book.max_rank(KEY), 8)
	var st := w.loadout.stats(KEY)
	assert_eq(String(st.cast_rule), "nearest")
	assert_eq([st.range, st.speed, st.radius, st.pierce, st.count], [350.0, 500.0, 10.0, 0, 1])
	assert_eq(String(st.damage_type), "physical")
	assert_eq(String(st.element), "")
	assert_eq(String(d.action), "homing")
	assert_false(bool(d.get("ammo_shot", false)), "the parrot is the Beacon's own ball, not the ammo")
	assert_eq(String(st.ball), "Skill.wz/521.img/skill/5211006/ball")
	assert_eq(String(st.hit), "Skill.wz/521.img/skill/5211006/hit/0")
	assert_eq(String(d.effect), "Skill.wz/521.img/skill/5211006/effect")
	assert_eq(String(d.sounds.use), "Sound.wz/Skill.img/5211006/Use")
	assert_eq(String(d.sounds.hit), "Sound.wz/Skill.img/5211006/Hit")
	assert_eq(String(d.on_hit.status), "all_weak")
	assert_near(float(d.on_hit.duration), 8.0)
	assert_eq(String(d.on_hit.cue), "Skill.wz/521.img/skill/5211006/mob")
	assert_near(float(st.mark_time), 8.0)
	assert_near(float(st.mark_mult), 1.5)
	assert_near(float(st.mark_boss_mult), 1.25)


func test_the_beacon_waits_ten_seconds_between_casts() -> void:
	var w := _world()
	_mob(w, 100)
	w.runner.step(DT, w)
	assert_eq(w.runner.casts, 1)
	assert_near(float(w.runner.cooldowns[KEY]), 10.0 - DT, 0.001)
	w.runner.step(DT, w)
	assert_eq(w.runner.casts, 1, "not ready again")


# --- the mark ----------------------------------------------------------------------------------------------------------

func test_the_shot_marks_what_it_hits_for_eight_seconds() -> void:
	var w := _world()
	var m := _mob(w, 100)
	var bystander := _mob(w, 160)
	assert_false(_marked(w, m))
	w.runner.step(DT, w)
	_run(w, 30) # 100 px at 500 px/s is 0.2 s of flight
	assert_true(_marked(w, m), "the nearest monster carries the mark")
	assert_false(_marked(w, bystander), "one target: only the monster hit")
	assert_true(w.swarm.status_time(m, MobSwarm.ALL_WEAK) > 7.5, "about eight seconds left")
	assert_eq(w.swarm.element_multiplier(m, ""), MobSwarm.MARK_MULT)
	_run(w, 60 * 9)
	assert_false(_marked(w, m), "the mark ends after its eight seconds")
	assert_eq(w.swarm.element_multiplier(m, ""), 1.0)


func test_a_later_hit_by_any_skill_deals_one_and_a_half_times_the_damage() -> void:
	var w := _world(8)
	_heavy(w)
	var m := _mob(w, 100)
	var twin := _mob(w, 140)
	var state := w.rng.state
	var plain := _hit_damage(w, twin, state)
	assert_true(plain > 0)
	w.swarm.apply_status(m, "all_weak", {"time": 8.0, "mult": 1.5, "boss_mult": 1.25}, w.events)
	var marked := _hit_damage(w, m, state)
	assert_eq(marked, roundi(plain * 1.5), "x1.5 on the same roll")


func test_a_boss_is_marked_too_at_one_and_a_quarter() -> void:
	var w := _world(8)
	_heavy(w)
	var boss := _mob(w, 100)
	var twin := _mob(w, 140)
	for slot: int in [boss, twin]:
		w.swarm.mob_kind(slot).boss = true
	var state := w.rng.state
	var plain := _hit_damage(w, twin, state)
	w.runner.step(DT, w)
	_run(w, 30)
	assert_true(_marked(w, boss), "a boss takes the mark")
	assert_eq(w.swarm.element_multiplier(boss, ""), MobSwarm.MARK_BOSS_MULT)
	assert_eq(_hit_damage(w, boss, state), roundi(plain * 1.25), "x1.25 on a boss")


func test_a_second_beacon_refreshes_the_mark_and_prefers_the_marked_monster() -> void:
	var w := _world()
	var far := _mob(w, 300)
	var near := _mob(w, -120) # on the other side: a shot stops at the first monster on its line
	assert_true(w.swarm.apply_status(far, "all_weak", {"time": 2.0, "mult": 1.5, "boss_mult": 1.25}, w.events), "a mark from elsewhere")
	w.runner.step(DT, w)
	_run(w, 60) # 300 px at 500 px/s is 0.6 s
	assert_true(w.swarm.status_time(far, MobSwarm.ALL_WEAK) > 7.0, "the Beacon went for the marked monster and refreshed it to eight seconds")
	assert_false(_marked(w, near), "the nearer monster was passed over")
	assert_eq(w.swarm.element_multiplier(far, ""), MobSwarm.MARK_MULT, "refreshing never stacks to x2.25")
	# A second shot at the same monster: still one multiplier.
	w.runner.cooldowns[KEY] = 0.0
	w.runner.step(DT, w)
	_run(w, 60)
	assert_eq(w.swarm.element_multiplier(far, ""), MobSwarm.MARK_MULT)


func test_the_mark_makes_a_nearest_rule_skill_prefer_the_marked_monster() -> void:
	var w := _world()
	var near := _mob(w, 120)
	var marked := _mob(w, 300)
	assert_true(w.swarm.apply_status(marked, "all_weak", {"time": 8.0, "mult": 1.5, "boss_mult": 1.25}, w.events))
	assert_eq(w.runner._find_targets(w, w.player.pos, 350.0, 1), 1)
	assert_eq(w.runner._tgt[0], marked)
	assert_true(near != marked)


# --- Bullseye ---------------------------------------------------------------------------------------------------------

func test_bullseye_lengthens_and_strengthens_the_stored_mark() -> void:
	var w := _world()
	w.loadout.add_skill_mod(KEY, "mark_power", "add", 0.25)
	w.loadout.add_skill_mod(KEY, "mark_time", "mul", 1.5)
	var st := w.loadout.stats(KEY)
	assert_near(float(st.mark_time), 12.0)
	assert_near(float(st.mark_mult), 1.75)
	assert_near(float(st.mark_boss_mult), 1.5)
	var m := _mob(w, 100)
	w.runner.step(DT, w)
	_run(w, 30)
	assert_true(w.swarm.status_time(m, MobSwarm.ALL_WEAK) > 11.5, "twelve seconds")
	assert_eq(w.swarm.element_multiplier(m, ""), 1.75)


# --- rarity ------------------------------------------------------------------------------------------------------------

func test_the_four_rarity_lists_are_the_specs_and_legendary_shares_the_uniques_counter() -> void:
	var w := _world()
	var b: Dictionary = w.book.def(KEY).rarity_bonuses
	for tier in ["rare", "epic", "unique", "legendary"]:
		assert_eq(b[tier].size(), 1, tier)
		assert_false(b[tier][0].effects.is_empty(), tier)
	assert_eq([b.rare[0].id, b.rare[0].text], ["gun_mastery", "Gun Mastery"])
	assert_eq([b.rare[0].effects[0].stat, b.rare[0].effects[0].op, b.rare[0].effects[0].value], ["damage", "mul", 1.2])
	assert_eq([b.epic[0].id, b.epic[0].text], ["booster", "Gun Booster"])
	assert_eq([b.epic[0].effects[0].stat, b.epic[0].effects[0].op, b.epic[0].effects[0].value], ["cooldown", "mul", 0.88])
	assert_eq([b.unique[0].id, b.unique[0].text], ["bullseye", "Bullseye"])
	assert_eq(b.unique[0].effects.size(), 2)
	assert_eq([b.unique[0].effects[0].stat, b.unique[0].effects[0].op, b.unique[0].effects[0].value], ["mark_power", "add", 0.25])
	assert_eq([b.unique[0].effects[1].stat, b.unique[0].effects[1].op, b.unique[0].effects[1].value], ["mark_time", "mul", 1.5])
	assert_eq(b.legendary[0].id, b.unique[0].id, "Legendary shares the Unique's repeat counter")
	assert_eq(b.legendary[0].effects.size(), 3)
	assert_eq(b.legendary[0].effects.slice(0, 2), b.unique[0].effects)
	assert_eq([b.legendary[0].effects[2].stat, b.legendary[0].effects[2].op, b.legendary[0].effects[2].value], ["damage", "mul", 1.2])


## The resolved stat each tier changes, before and after applying its card.
func test_every_rarity_bonus_changes_a_resolved_stat() -> void:
	var expect := {
		"rare": {"damage_min": 1.2, "damage_max": 1.2},
		"epic": {"cooldown": 0.88},
		"unique": {"mark_mult": 1.75, "mark_time": 12.0, "mark_boss_mult": 1.5},
		"legendary": {"damage_min": 1.2, "damage_max": 1.2, "mark_mult": 1.75, "mark_time": 12.0, "mark_boss_mult": 1.5},
	}
	for tier: String in expect:
		var w := _world(8)
		var before := w.loadout.stats(KEY)
		var card := w.upgrades.choice_card(KEY + "_rank", w, tier)
		assert_false(card.is_empty(), "%s: a rank card exists at rank 8" % tier)
		assert_false(card.get("rarity_bonus", {}).is_empty(), "%s offers a bonus" % tier)
		w.upgrades.apply(card.id, w, tier)
		var after := w.loadout.stats(KEY)
		for stat: String in expect[tier]:
			var want: float = float(expect[tier][stat])
			var base: float = float(before[stat])
			var got: float = float(after[stat])
			if stat in ["damage_min", "damage_max", "cooldown"]:
				assert_near(got, base * want, 0.0001, "%s: %s" % [tier, stat])
			else:
				assert_near(got, want, 0.0001, "%s: %s" % [tier, stat])


func test_the_pool_offers_a_new_card_for_the_beacon() -> void:
	var w := _world()
	assert_false(w.upgrades.card(KEY + "_new").is_empty())


# --- real cache: all eight ranks against Skill.wz ----------------------------------------------------------------------

func test_real_cache_all_eight_ranks_map_to_the_skill_wz_levels() -> void:
	if not require_cache_img("Skill.wz/521.img"):
		return
	var lib := AssetLibrary.new()
	var img := lib.img("Skill.wz/521.img")
	assert_true(img != null, "Skill.wz/521.img is in the cache")
	if img == null:
		lib.free()
		return
	var book := SkillBook.from_data(DataRepo.load_all().skills, {"521": img.root})
	var lo := Loadout.new(book)
	lo.weapon_family = "gun"
	var node: Dictionary = img.root.skill["5211006"]
	assert_false(node.has("elemAttr"), "no element")
	assert_eq(book.max_level(KEY), 30)
	assert_eq(book.max_rank(KEY), 8)
	var mapped := [4, 8, 12, 15, 19, 23, 27, 30] # ceil(rank x 30 / 8)
	for rank_value in range(1, 9):
		var lv: int = mapped[rank_value - 1]
		assert_eq(book.canonical_level(KEY, rank_value), lv, "rank %d" % rank_value)
		var level: Dictionary = node.level[str(lv)]
		var st := lo.stats(KEY, rank_value)
		var label := "rank %d (level %d)" % [rank_value, lv]
		assert_near(st.damage_pct, float(level.damage) / 100.0, 0.000001, label)
		assert_eq(st.range, float(level.range), label)
		assert_eq(st.range, 350.0, label)
		assert_false(level.has("time") or level.has("x"), "%s: the mark's length is not in the WZ" % label)
		assert_near(float(st.mark_time), 8.0, 0.000001, label)
		assert_near(float(st.mark_mult), 1.5, 0.000001, label)
		assert_eq(st.count, 1, label)
	# The spec's worked rank values (rank 1 / 4 / 8), as literals.
	for i in 3:
		assert_near(lo.stats(KEY, [1, 4, 8][i]).damage_pct, [1.72, 2.60, 3.80][i], 0.000001)
	# Art and sounds resolve; the mark loop is a real animation.
	for suffix: String in ["icon", "iconDisabled", "iconMouseOver"]:
		assert_true(lib.frame(book.wz_path(KEY) + "/" + suffix) != null, suffix)
	assert_eq(lib.anim(String(book.def(KEY).ball)).frame_count(), 4, "the four-frame parrot")
	assert_eq(lib.anim(String(book.def(KEY).effect)).frame_count(), 6, "effect: six frames")
	assert_eq(lib.anim(String(book.def(KEY).on_hit.cue)).frame_count(), 5, "mob: the five-frame mark loop")
	assert_true(lib.anim(book.visual(KEY, "hit", 1, 1)).frame_count() == 5, "hit/0 has five frames")
	for sound: String in book.def(KEY).sounds.values():
		assert_true(lib.sound(sound) != null, "sound %s" % sound)
	assert_eq(Array(lib.missing), [])
	lib.free()
