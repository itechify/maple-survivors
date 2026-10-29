extends TestCase
## Buccaneer Energy Orb (B7 #419, spec #412 BU-4, BU-16): the second finisher on the Energy Charge bar. The crowd nova (`range_around`
## 200 px, `min_targets` 2, 2 -> 6 mobs by rank), its damage by rank, spend and keep, one bar shared with Energy Drain, the arbitration
## between the two finishers with real data, the art placement and what every rarity bonus changes. Synthetic WZ-shaped books 511
## (Drain) and 512 (`book_node`, the real values at the eight mapped levels 4/8/12/15/19/23/27/30), seeded RNG, fixed 1/60 ticks; the
## last test reads the real asset cache and SKIPs without it (a SKIP proves nothing).
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const KNUCKLE := 1482000
const MOB := 1110100
const BASE := "Skill.wz/512.img/skill/5121002/"
const LEVELS := [4, 8, 12, 15, 19, 23, 27, 30]
## Energy Orb at the eight mapped levels (tier A, Skill.wz 5121002): damage % and mobCount; `range` is 200 at every level.
const DAMAGE := [360, 440, 530, 590, 670, 760, 840, 900]
const MOBS := [2, 3, 3, 4, 5, 5, 6, 6]
const TIERS := ["rare", "epic", "unique", "legendary"]
const SKILL := "energy_orb"


## The 512 fixture book: Orb's real damage and mobCount at the eight mapped levels, `range` 200 (and no box) everywhere, a filler row
## elsewhere. Static so the rarity audit can merge it into its own book 512.
static func book_node() -> Dictionary:
	return preload("res://tests/fixtures/buccaneer_orb_book.gd").book_node()


## Book 511 with just enough Energy Drain (the canonical box, one mob, the real rank-1 numbers) for the arbitration tests.
static func _drain_book() -> Dictionary:
	return preload("res://tests/fixtures/buccaneer_orb_book.gd")._drain_book()


## A Buccaneer (job 512 flipped playable) at x = 400 on the flat quiet map, facing right, with `keys` learned (Orb by default).
func _world(keys := [SKILL], pad := 17) -> RunWorld:
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["512"]["playable"] = true
	var setup := RF.with_basic_attack(RF.setup("quiet", 419, data))
	setup.skill_imgs = RF.skill_imgs()
	setup.skill_imgs["511"] = _drain_book()
	setup.skill_imgs["512"] = book_node()
	var w := RunWorld.new(setup)
	w.set_job(512)
	w.loadout.ranks.clear()
	w.loadout.order.clear()
	RF.place_player(w, 400)
	w.equipment.worn.weapon = Equipment.create(KNUCKLE, {"incPAD": pad})
	w.refresh_player_stats()
	for mk: MobKind in w.mob_kinds:
		mk.hitbox = Rect2(-5, -10, 10, 10)
		mk.move_speed = 0.0
	for key: String in keys:
		w.learn_skill(key)
	return w


## A mob `dx` px from the player (positive = the facing side), with `hp` hit points.
func _mob(w: RunWorld, dx: float, hp := 1000000) -> int:
	var m := RF.put_mob(w, MOB, 400.0 + dx * w.player.facing, 190, 10000)
	w.swarm.hp[m] = hp
	w.swarm.max_hp[m] = hp
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	return m


func _fill(w: RunWorld, n := 10) -> void:
	w.meter.value = 0
	for i in n:
		w.meter.gain("cast_landed", w.events)


func _step(w: RunWorld) -> Array:
	w.drain_events()
	w.runner.step(DT, w)
	return w.drain_events()


func _hits(events: Array) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return e.type == "mob_hit")


func _on_cooldown(w: RunWorld, key: String) -> bool:
	return float(w.runner.cooldowns.get(key, 0.0)) > 0.0


## Ranks `key` up to `rank` (the loadout starts at rank 1).
func _rank(w: RunWorld, rank: int, key := SKILL) -> void:
	w.loadout.ranks[key] = rank


# --- catalog and data --------------------------------------------------------------------------------------------

func test_catalog_orb_is_an_eight_rank_crowd_finisher_with_a_unit_word_and_no_projectile() -> void:
	var w := _world()
	var def := w.book.def(SKILL)
	assert_eq(int(def.skill_id), 5121002)
	assert_eq(String(def.book), "512")
	assert_eq(int(def.job), 512)
	assert_eq(String(def.cast.rule), "range_around")
	assert_eq(int(def.cast.min_targets), 2)
	assert_eq(def.meter, {"role": "finisher", "min": 10.0, "spend": "all", "damage_per_unit": 0.12, "unit": "energy"})
	assert_eq(float(def.cooldown), 1.0, "the finisher floor")
	assert_eq(String(def.action), "eorb")
	assert_eq(float(def.action_time), 0.8)
	assert_eq(String(def.ball), "", "a nova: the single-frame ball is not drawn")
	assert_eq(String(def.hit), BASE + "hit/0")
	assert_eq(String(def.effect), BASE + "effect")
	assert_false(def.has("ranks"), "the default level-30 rank table")
	assert_eq(w.book.rank_table(SKILL).map(func(v: Variant) -> int: return int(v)), LEVELS)
	assert_eq((def.sounds as Dictionary).keys(), ["use", "hit"])
	assert_eq(String(def.sounds.use), "Sound.wz/Skill.img/5121002/Use")
	assert_eq(String(def.sounds.hit), "Sound.wz/Skill.img/5121002/Hit")


func test_effect0_plays_behind_the_avatar_at_the_cast_position() -> void:
	var def := _world().book.def(SKILL)
	var visuals: Array = def.cast_visuals
	assert_eq(visuals.size(), 1)
	assert_eq(String(visuals[0].path), BASE + "effect0")
	assert_eq(float(visuals[0].x), 0.0)
	assert_true(bool(visuals[0].get("facing", false)), "authored facing left, flipped for a right-facing caster")


func test_damage_and_mob_count_by_rank_come_from_the_canonical_levels() -> void:
	var w := _world()
	for rank in range(1, 9):
		_rank(w, rank)
		var st := w.loadout.stats(SKILL)
		assert_near(st.damage_pct, DAMAGE[rank - 1] / 100.0, 0.0001, "rank %d damage" % rank)
		assert_eq(st.mob_count, MOBS[rank - 1], "rank %d targets" % rank)
		assert_near(float(st.range), 200.0, 0.001, "rank %d range" % rank)
	_rank(w, 1)
	assert_near(w.loadout.stats(SKILL).damage_pct, 3.6, 0.0001)
	_rank(w, 4)
	assert_near(w.loadout.stats(SKILL).damage_pct, 5.9, 0.0001)
	_rank(w, 8)
	assert_near(w.loadout.stats(SKILL).damage_pct, 9.0, 0.0001)


# --- admission: two monsters, 200 px, 2 -> 6 ----------------------------------------------------------------------

func test_a_lone_monster_does_not_admit_orb_and_two_do() -> void:
	var w := _world()
	_mob(w, 100)
	_fill(w)
	assert_eq(_hits(_step(w)).size(), 0, "one monster: no cast")
	assert_false(_on_cooldown(w, SKILL))
	assert_eq(w.meter.value, 10, "nothing spent")
	_mob(w, -60)
	var hits := _hits(_step(w))
	assert_eq(hits.size(), 2, "two monsters: both struck")
	assert_true(_on_cooldown(w, SKILL))


func test_the_nova_reaches_200_px_around_the_body_on_both_sides_and_not_beyond() -> void:
	var w := _world()
	var near_a := _mob(w, 150)
	var near_b := _mob(w, -150)
	_mob(w, 260)
	_fill(w)
	var struck := _hits(_step(w)).map(func(e: Dictionary) -> int: return int(e.mob))
	struck.sort()
	var want := [near_a, near_b]
	want.sort()
	assert_eq(struck, want, "the 260 px mob is outside the range")
	# Two mobs where one is out of range: no admission at all.
	var lone := _world()
	_mob(lone, 150)
	_mob(lone, 260)
	_fill(lone)
	assert_eq(_hits(_step(lone)).size(), 0)


func test_the_target_cap_is_two_at_rank_one_and_six_at_rank_eight() -> void:
	for rank in [1, 4, 8]:
		var w := _world()
		_rank(w, rank)
		for i in 9:
			_mob(w, 40.0 + i * 12.0)
		_fill(w)
		assert_eq(_hits(_step(w)).size(), MOBS[rank - 1], "rank %d" % rank)


func test_each_struck_monster_takes_one_line_and_a_full_bar_multiplies_the_damage() -> void:
	var w := _world()
	_rank(w, 8)
	var mobs := []
	for i in 3:
		mobs.append(_mob(w, 40.0 + i * 20.0))
	_fill(w)
	var base := w.runner.stats_of(w, SKILL)
	var cast := w.meter.begin_cast(w, SKILL, base)
	# +3% per held energy (1.3) times 1 + 10 spent x 0.12 (2.2) on the 900 % line.
	assert_near(float(cast.damage_max) / float(base.damage_max), 1.3 * 2.2, 0.001)
	assert_eq(cast.meter_spent, 10)
	_fill(w)
	var hit_mobs := _hits(_step(w)).map(func(e: Dictionary) -> int: return int(e.mob))
	hit_mobs.sort()
	assert_eq(hit_mobs, mobs, "one line on each of the three")


# --- spend and keep, one bar for both finishers ------------------------------------------------------------------

func test_orb_spends_all_the_energy_and_a_cast_earns_none() -> void:
	var w := _world()
	_mob(w, 80)
	_mob(w, -80)
	_fill(w, 9)
	assert_eq(_hits(_step(w)).size(), 0, "nine energy: below the minimum of ten")
	_fill(w, 10)
	_step(w)
	assert_eq(w.meter.value, 0, "all spent and the finisher earned nothing")


func test_orb_with_energy_charge_keeps_two_energy_after_the_cast() -> void:
	var w := _world()
	w.loadout.add_skill_mod(SKILL, "meter_keep", "add", 2.0)
	_mob(w, 80)
	_mob(w, -80)
	_fill(w)
	_step(w)
	assert_eq(w.meter.value, 2)


func test_a_cast_of_either_finisher_resets_the_one_shared_bar() -> void:
	var drain := _world(["energy_drain"])
	_mob(drain, 100)
	_fill(drain)
	_step(drain)
	assert_eq(drain.meter.value, 0)
	var orb := _world(["energy_drain", SKILL])
	_mob(orb, 80)
	_mob(orb, -80)
	_fill(orb)
	_step(orb)
	assert_eq(orb.meter.value, 0)
	assert_true(_on_cooldown(orb, SKILL))
	assert_false(_on_cooldown(orb, "energy_drain"), "Drain waits for the bar to refill")


func test_the_orb_cooldown_is_one_second_and_a_full_bar_again_casts_it_again() -> void:
	var w := _world()
	_mob(w, 80)
	_mob(w, -80)
	_fill(w)
	_step(w)
	assert_near(float(w.runner.cooldowns[SKILL]), 1.0, 0.05)
	# The bar is full again at once; the second volley waits for the cooldown (60 ticks) and then lands on both.
	_fill(w)
	var volleys := []
	for tick in 90:
		w.step(DT, MoveInput.new())
		var n := _hits(w.drain_events()).size()
		if n > 0:
			volleys.append([tick, n])
	assert_eq(volleys.size(), 1, str(volleys))
	assert_eq(volleys[0][1], 2)
	assert_true(volleys[0][0] >= 58 and volleys[0][0] <= 62, "after one second: %s" % str(volleys))


# --- arbitration with real data ---------------------------------------------------------------------------------

func _both() -> RunWorld:
	return _world(["energy_drain", SKILL])


func test_a_single_scheduled_boss_as_the_only_target_picks_drain() -> void:
	var w := _both()
	var boss := _mob(w, 100)
	w.mob_boss[boss] = 0
	_fill(w)
	_step(w)
	assert_true(_on_cooldown(w, "energy_drain"), "Drain strikes the boss")
	assert_false(_on_cooldown(w, SKILL))
	assert_eq(w.meter.value, 0)


func test_two_or_more_targets_pick_orb() -> void:
	for count in [2, 3, 5]:
		var w := _both()
		for i in count:
			_mob(w, 60.0 + i * 15.0)
		_fill(w)
		_step(w)
		assert_true(_on_cooldown(w, SKILL), "%d targets: Orb" % count)
		assert_false(_on_cooldown(w, "energy_drain"), "%d targets: not Drain" % count)


func test_a_lone_ordinary_monster_picks_drain_because_orb_needs_two() -> void:
	var w := _both()
	_mob(w, 100)
	_fill(w)
	_step(w)
	assert_true(_on_cooldown(w, "energy_drain"))
	assert_false(_on_cooldown(w, SKILL))


func test_a_boss_among_a_crowd_is_the_boss_strike_for_drain_only_when_it_is_drains_single_target() -> void:
	# Drain's box counts one monster (mobCount 1) and bosses come first, so a scheduled boss in front keeps Drain ahead of the crowd Orb.
	var w := _both()
	var boss := _mob(w, 100)
	w.mob_boss[boss] = 0
	for i in 3:
		_mob(w, -50.0 - i * 15.0)
	_fill(w)
	_step(w)
	assert_true(_on_cooldown(w, "energy_drain"), "a boss in Drain's box: the boss strike")
	assert_false(_on_cooldown(w, SKILL))


func test_owning_only_one_finisher_fires_that_one_when_its_own_rule_admits() -> void:
	var only_orb := _world([SKILL])
	_mob(only_orb, 100)
	_fill(only_orb)
	_step(only_orb)
	assert_false(_on_cooldown(only_orb, SKILL), "a lone monster: Orb alone waits")
	_mob(only_orb, -100)
	_step(only_orb)
	assert_true(_on_cooldown(only_orb, SKILL), "a second one: Orb alone fires")
	var only_drain := _world(["energy_drain"])
	_mob(only_drain, 100)
	_mob(only_drain, -100)
	_fill(only_drain)
	_step(only_drain)
	assert_true(_on_cooldown(only_drain, "energy_drain"), "the second mob is behind Drain's box: it strikes the front one")
	assert_eq(only_drain.meter.value, 0)


func test_the_arbitration_is_deterministic_over_a_seeded_minute() -> void:
	var traces := []
	for run in 2:
		var w := _both()
		var trace := []
		for t in 3600:
			if t % 120 == 0:
				for m in w.swarm.capacity():
					w.swarm.active[m] = 0
				var n := 1 + (t / 120) % 4
				for i in n:
					_mob(w, 50.0 + i * 20.0)
				_fill(w)
			w.step(DT, MoveInput.new())
			for ev: Dictionary in w.drain_events():
				if ev.type == "mob_hit":
					trace.append([t, int(ev.mob), int(ev.damage)])
		traces.append(trace)
	assert_true(traces[0].size() > 0)
	assert_eq(traces[0], traces[1])


# --- rarity bonuses -----------------------------------------------------------------------------------------------

func test_the_four_rarity_lists_have_the_spec_effects() -> void:
	var b: Dictionary = _world().book.def(SKILL).rarity_bonuses
	assert_eq(b.keys(), TIERS)
	assert_eq(b.rare.map(func(x: Dictionary) -> String: return x.id), ["mastery"])
	assert_eq(b.epic.map(func(x: Dictionary) -> String: return x.id), ["wide_orb"])
	assert_eq(b.unique.map(func(x: Dictionary) -> String: return x.id), ["energy_charge"])
	assert_eq(b.legendary.map(func(x: Dictionary) -> String: return x.id), ["energy_charge"], "shares the Unique's id and counter")
	assert_eq(b.epic[0].text, "Wide Orb")
	assert_eq(b.rare[0].effects, [{"stat": "damage", "op": "mul", "value": 1.2}])
	assert_eq(b.epic[0].effects, [{"stat": "area", "op": "mul", "value": 1.2}])
	assert_eq(b.unique[0].effects, [{"stat": "meter_keep", "op": "add", "value": 2.0}])
	assert_eq(b.legendary[0].effects, [{"stat": "meter_keep", "op": "add", "value": 2.0}, {"stat": "damage", "op": "mul", "value": 1.2}])


func test_wide_orb_widens_the_range_from_200_to_240_px() -> void:
	var w := _world()
	assert_near(float(w.loadout.stats(SKILL).range), 200.0, 0.001)
	w.loadout.add_skill_mod(SKILL, "area", "mul", 1.2)
	assert_near(float(w.loadout.stats(SKILL).range), 240.0, 0.001)
	# A mob 225 px away: outside 200, inside 240.
	for wide in [false, true]:
		var t := _world()
		if wide:
			t.loadout.add_skill_mod(SKILL, "area", "mul", 1.2)
		_mob(t, 40)
		_mob(t, 225)
		_fill(t)
		assert_eq(_hits(_step(t)).size(), 2 if wide else 0, "wide %s" % wide)


func test_mastery_and_legendary_raise_the_damage_and_energy_charge_keeps_two() -> void:
	var plain := _world().loadout.stats(SKILL)
	var w := _world()
	for bonus: Dictionary in w.book.def(SKILL).rarity_bonuses.rare:
		for e: Dictionary in bonus.effects:
			w.loadout.add_skill_mod(SKILL, String(e.stat), String(e.op), float(e.value))
	assert_near(float(w.loadout.stats(SKILL).damage_max), float(plain.damage_max) * 1.2, float(plain.damage_max) * 0.01)
	var legend := _world()
	for bonus: Dictionary in legend.book.def(SKILL).rarity_bonuses.legendary:
		for e: Dictionary in bonus.effects:
			legend.loadout.add_skill_mod(SKILL, String(e.stat), String(e.op), float(e.value))
	assert_eq(int(legend.loadout.stats(SKILL).meter_keep), 2)
	assert_near(float(legend.loadout.stats(SKILL).damage_max), float(plain.damage_max) * 1.2, float(plain.damage_max) * 0.01)


func test_the_cards_say_energy_and_apply_the_bonuses() -> void:
	for tier: String in TIERS:
		var w := _world()
		var card := w.upgrades.choice_card("energy_orb_rank", w, tier)
		var before := w.loadout.stats(SKILL)
		w.upgrades.apply(card.id, w, tier)
		var after := w.loadout.stats(SKILL)
		match tier:
			"rare":
				assert_true(float(after.damage_max) > float(before.damage_max))
			"epic":
				assert_true(float(after.range) > float(before.range))
			_:
				assert_eq(int(after.meter_keep), 2)
				assert_true("Keeps 2 energy" in String(card.desc), String(card.desc))
				assert_false("orbs" in String(card.desc), String(card.desc))
	var kept := _world()
	kept.loadout.add_skill_mod(SKILL, "meter_keep", "add", 2)
	var line := SkillText.new(kept.book).level_line(SKILL, 1, kept.loadout.stats(SKILL))
	assert_true("Needs 10 energy" in line and "Keeps 2 energy" in line, line)
	assert_false("orbs" in line, line)


# --- real cache --------------------------------------------------------------------------------------------------

func test_real_cache_orb_numbers_at_all_eight_ranks_and_its_art_nodes() -> void:
	if not require_cache():
		return
	var library := AssetLibrary.get_default()
	var img := library.img("Skill.wz/512.img")
	assert_true(img != null, "book 512 imported (cache-413 or any cache built after the Buccaneer fragment)")
	if img == null:
		return
	var root: Dictionary = img.root
	var b := SkillBook.from_data(DataRepo.load_all().skills, {"512": root})
	var lo := Loadout.new(b)
	lo.add_skill(SKILL)
	assert_eq(b.rank_table(SKILL).map(func(v: Variant) -> int: return int(v)), LEVELS)
	for rank in range(1, 9):
		var row: Dictionary = root.skill["5121002"].level[str(LEVELS[rank - 1])]
		lo.ranks[SKILL] = rank
		var st := lo.stats(SKILL)
		assert_eq(int(row.damage), DAMAGE[rank - 1], "rank %d WZ damage" % rank)
		assert_near(st.damage_pct, DAMAGE[rank - 1] / 100.0, 0.0001, "rank %d damage" % rank)
		assert_eq(int(row.mobCount), MOBS[rank - 1], "rank %d WZ mobCount" % rank)
		assert_eq(st.mob_count, MOBS[rank - 1])
		assert_eq(int(row.range), 200, "rank %d WZ range" % rank)
		assert_near(float(st.range), 200.0, 0.001)
		assert_false(row.has("lt"), "no box in the node")
	var node: Dictionary = root.skill["5121002"]
	assert_eq((node.action as Dictionary)["0"], "eorb")
	for path: String in ["effect", "effect0", "hit/0", "ball"]:
		assert_true(library.find_anim(BASE + path) != null, path)
	assert_eq(library.find_anim(BASE + "effect").frame_count(), 13)
	assert_eq(library.find_anim(BASE + "effect0").frame_count(), 6)
	assert_eq(library.find_anim(BASE + "hit/0").frame_count(), 7)
	assert_eq(library.find_anim(BASE + "ball").frame_count(), 1)
	assert_true(library.sound("Sound.wz/Skill.img/5121002/Use") != null, "Orb Use")
	assert_true(library.sound("Sound.wz/Skill.img/5121002/Hit") != null, "Orb Hit")
	assert_true(library.missing.is_empty(), str(library.missing))
