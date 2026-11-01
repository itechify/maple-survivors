extends TestCase
## Bowmaster's Inferno (spec #332, ticket B9 #341): a fire arrow that blasts six monsters and sets each on fire. Fixed 1/60 s
## ticks, seeded RNG; the Skill.wz levels are the synthetic fixture table (endpoints recorded from v83) unless a test says
## "real cache" (those call require_cache() and SKIP without it).

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const BOW := 1452051


## A quiet round of a Bowmaster holding a bow, Inferno learned at `rank_value`, mobs frozen and tiny.
func _world(rank_value := 1, p_seed := 341) -> RunWorld:
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["312"]["playable"] = true # in this test's data only: its pool cards exist (B12 ships the flip)
	var setup := RF.with_basic_attack(RF.setup("quiet", p_seed, data))
	setup.equipment_info.merge({BOW: {"incPAD": 28, "attackSpeed": 6, "tuc": 7}}, true)
	for action: String in ["shoot1", "shoot2"]:
		setup.body_img[action] = {"0": {"delay": 100.0}, "1": {"delay": 100.0}}
	setup["job"] = 312
	var w := RunWorld.new(setup)
	RF.place_player(w, 400)
	if w.weapon_id() != BOW:
		w.wear_new_item(BOW)
	for mk: MobKind in w.mob_kinds:
		mk.hitbox = Rect2(-20, -50, 40, 50)
		mk.move_speed = 0
	w.god = true
	w.loadout.ranks.clear() # not the start skill (Arrow Blow): only Inferno casts
	w.loadout.order.clear()
	assert_true(w.learn_skill("inferno"), "inferno is learnable by a Bowmaster")
	w.loadout.set_rank("inferno", rank_value)
	w.refresh_player_stats()
	w.drain_events()
	return w


func _mob(w: RunWorld, dx: float, hp := 100000.0) -> int:
	var slot := RF.put_mob(w, 1110100, w.player.pos.x + dx, 190, hp)
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	return slot


func _run(w: RunWorld, ticks: int) -> void:
	for tick in ticks:
		w.step(DT, MoveInput.new())


func _hits(w: RunWorld) -> Array:
	return w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "mob_hit" and e.skill == "inferno")


## The first mob_hit of the cast itself (the arrow's blast), not a burn pulse.
func _blast_hits(events: Array) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return e.type == "mob_hit" and e.skill == "inferno" and e.hit_visual != "")


func _burning(w: RunWorld, slots: Array) -> Array:
	return slots.filter(func(s: int) -> bool: return w.swarm.status_time(s, MobSwarm.BURN) > 0.0)


# --- the definition ----------------------------------------------------------------------------------------------------

func test_inferno_is_a_fire_arrow_with_the_specs_shot_numbers() -> void:
	var w := _world()
	var d := w.book.def("inferno")
	assert_eq(int(d.skill_id), 3111003)
	assert_eq(String(d.slot), "active")
	assert_false(d.has("weapon_families"), "a weapon gates nothing")
	assert_false(d.has("ranks"), "the default rank table")
	assert_eq(w.book.max_rank("inferno"), 8)
	var st := w.loadout.stats("inferno")
	assert_eq(String(st.element), "f")
	assert_eq(String(st.cast_rule), "nearest")
	assert_eq([st.range, st.speed, st.radius, st.pierce, st.count], [350.0, 600.0, 8.0, 0, 1])
	assert_eq(String(st.damage_type), "physical")
	assert_eq(String(w.book.def("inferno").on_hit.status), "burn")
	assert_false(bool(d.get("ammo_shot", false)), "Inferno shoots its own fire ball, not the ammo")
	assert_eq(String(st.ball), "Skill.wz/311.img/skill/3111003/ball")
	assert_eq(String(st.hit), "Skill.wz/311.img/skill/3111003/hit/0")
	assert_eq(String(d.sounds.use), "Sound.wz/Skill.img/3111003/Use")
	assert_eq(String(d.sounds.hit), "Sound.wz/Skill.img/3111003/Hit")


func test_inferno_waits_three_seconds_between_casts() -> void:
	var w := _world()
	_mob(w, 100)
	w.runner.step(DT, w)
	assert_eq(w.runner.casts, 1)
	assert_near(float(w.runner.cooldowns.inferno), 3.0 - DT, 0.001)
	w.runner.step(DT, w)
	assert_eq(w.runner.casts, 1, "not ready again")


# --- the burn by rank ----------------------------------------------------------------------------------------------------

func test_the_burn_share_and_time_follow_the_spec_ranks() -> void:
	var w := _world()
	# rank 1 / 4 / 8 are WZ levels 4 / 15 / 30: x 24 / 35 / 50 percent for 5 / 5 / 10 s (the fixture's damage column is linear
	# 50..150, so 0.60 / 0.98 / 1.50 here; the real cache test checks v83's 65 / 112 / 150).
	var expected := {1: [24.0, 5.0, 0.60], 4: [35.0, 5.0, 0.98], 8: [50.0, 10.0, 1.5]}
	for rank_value: int in expected:
		var st := w.loadout.stats("inferno", rank_value)
		var row: Array = expected[rank_value]
		assert_near(float(st.burn_share), row[0], 0.001, "rank %d share" % rank_value)
		assert_near(float(st.burn_time), row[1], 0.001, "rank %d time" % rank_value)
		assert_near(float(st.damage_pct), row[2], 0.005, "rank %d damage" % rank_value)
		var mean := (float(st.damage_min) + float(st.damage_max)) * 0.5
		assert_eq(int(st.burn_pulse), roundi(mean * row[0] / 100.0), "rank %d pulse" % rank_value)


func test_every_blast_target_burns_with_the_right_pulse_and_time() -> void:
	for rank_value in [1, 8]:
		var w := _world(rank_value)
		var st := w.loadout.stats("inferno")
		var slots: Array[int] = []
		for dx in [80, 100, 120, 140, 160, 180, 200]:
			slots.append(_mob(w, dx))
		w.runner.step(DT, w)
		_run(w, 40)
		var burning := _burning(w, slots)
		assert_eq(burning.size(), 6, "rank %d: the six struck monsters burn, the seventh is outside the cap" % rank_value)
		assert_false(slots[6] in burning)
		for s: int in burning:
			assert_true(w.swarm.status_time(s, MobSwarm.BURN) > float(st.burn_time) - 1.0, "the level's `time`")
		var hp := {}
		for s: int in burning:
			hp[s] = w.swarm.hp[s]
		_run(w, 62)
		for s: int in burning:
			assert_eq(hp[s] - w.swarm.hp[s], int(st.burn_pulse), "rank %d: one pulse of the cast's snapshot per second" % rank_value)


func test_a_burning_monster_takes_a_pulse_every_second_for_the_whole_time() -> void:
	var w := _world(8)
	var slot := _mob(w, 100)
	var st := w.loadout.stats("inferno")
	w.runner.step(DT, w)
	_run(w, 40)
	w.runner.cooldowns["inferno"] = 1.0e9 # one cast: a recast would refresh the burn
	var start := w.swarm.hp[slot]
	_run(w, 60 * 12)
	var pulses := _hits(w).filter(func(e: Dictionary) -> bool: return e.hit_visual == "")
	assert_eq(pulses.size(), 10, "ten seconds of burn at rank 8 (a pulse a second)")
	assert_eq(start - w.swarm.hp[slot], 10 * int(st.burn_pulse))


func _kind_with_fire(w: RunWorld, digit: String) -> int:
	var img := RF.mob_img(1110100)
	img.info["elemAttr"] = "F" + digit
	w.mob_kinds.append(MobKind.from_wz(img, 1110100))
	return w.mob_kinds.size() - 1


func test_bosses_and_fire_immune_or_strong_monsters_do_not_burn() -> void:
	var w := _world(1)
	var boss := RF.put_mob(w, 2220000, w.player.pos.x + 90, 190, 100000)
	var immune := _mob(w, 120)
	w.swarm.kind[immune] = _kind_with_fire(w, "1")
	var strong := _mob(w, 135)
	w.swarm.kind[strong] = _kind_with_fire(w, "2")
	var ordinary := _mob(w, 150)
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	w.runner.step(DT, w)
	_run(w, 40)
	assert_true(w.swarm.hp[strong] < w.swarm.max_hp[strong], "fixture: the monsters are inside the blast (a strong one takes half)")
	assert_eq(w.swarm.status_time(boss, MobSwarm.BURN), 0.0, "a canonical boss resists")
	assert_eq(w.swarm.status_time(immune, MobSwarm.BURN), 0.0, "an F1 (fire immune) monster resists")
	assert_eq(w.swarm.status_time(strong, MobSwarm.BURN), 0.0, "an F2 (fire strong) monster resists")
	assert_true(w.swarm.status_time(ordinary, MobSwarm.BURN) > 0.0, "an ordinary monster burns")


func test_the_fire_element_multiplier_applies_to_the_blast_hit() -> void:
	var damages := {}
	for digit in ["0", "3"]:
		var w := _world(1)
		var img := RF.mob_img(1110100)
		img.info["elemAttr"] = "F" + digit
		w.mob_kinds[int(w.kind_of_id[1110100])] = MobKind.from_wz(img, 1110100)
		w.loadout.add_player_mod("damage", "mul", 100.0) # the fixture mob's defence would floor both hits at 1
		w.refresh_player_stats()
		_mob(w, 100)
		w.runner.step(DT, w)
		var hits: Array = []
		for tick in 40:
			w.step(DT, MoveInput.new())
			hits.append_array(_blast_hits(w.drain_events()))
		assert_eq(hits.size(), 1)
		damages[digit] = int(hits[0].damage)
	assert_true(damages["3"] > damages["0"], "a fire-weak monster takes more from the blast: %s" % [damages])


func test_burn_damage_scales_the_pulse_and_not_the_blast() -> void:
	var w := _world(1)
	var plain := w.loadout.stats("inferno")
	w.loadout.add_skill_mod("inferno", "burn_damage", "mul", 1.5)
	var hellfire := w.loadout.stats("inferno")
	assert_eq(int(hellfire.burn_pulse), roundi(float(plain.burn_pulse) * 1.5))
	assert_eq(hellfire.damage_min, plain.damage_min, "the arrow itself is unchanged")
	assert_eq(hellfire.damage_pct, plain.damage_pct)


# --- rarity bonuses ---------------------------------------------------------------------------------------------------

func test_the_catalog_lists_the_specs_inferno_bonuses() -> void:
	var bonuses: Dictionary = DataRepo.load_all().skills.skills.inferno.rarity_bonuses
	var want := {
		"rare": ["bow_mastery", "Bow Mastery", "damage", "mul", 1.2],
		"epic": ["hellfire", "Hellfire", "burn_damage", "mul", 1.5],
		"unique": ["spreading_fire", "Spreading Fire", "blast_targets", "add", 2.0],
	}
	for tier: String in want:
		assert_eq(bonuses[tier].size(), 1, tier)
		var entry: Dictionary = bonuses[tier][0]
		var row: Array = want[tier]
		assert_eq([String(entry.id), String(entry.text)], [row[0], row[1]], tier)
		assert_eq(entry.effects.size(), 1)
		assert_eq([String(entry.effects[0].stat), String(entry.effects[0].op), float(entry.effects[0].value)], [row[2], row[3], row[4]])
	var legendary: Dictionary = bonuses.legendary[0]
	assert_eq(String(legendary.id), "spreading_fire", "Legendary shares the Unique's repeat counter")
	assert_eq(legendary.effects.size(), 2)
	assert_eq([String(legendary.effects[0].stat), float(legendary.effects[0].value)], ["blast_targets", 2.0])
	assert_eq([String(legendary.effects[1].stat), String(legendary.effects[1].op), float(legendary.effects[1].value)], ["damage", "mul", 1.2])


func test_a_rare_or_better_card_adds_one_rank_plus_its_bonus() -> void:
	for tier: String in ["rare", "epic", "unique", "legendary"]:
		var a := _world()
		var b := _world()
		var c := a.upgrades.choice_card("inferno_rank", a, tier)
		assert_false(c.get("rarity_bonus", {}).is_empty(), "%s offers a bonus" % tier)
		a.upgrades.apply("inferno_rank", a, tier)
		b.upgrades.apply("inferno_rank", b, tier)
		assert_eq(a.loadout.rank("inferno"), 2, "%s: exactly one rank on top" % tier)
		assert_eq(a.loadout.skill_mods.get("inferno", {}), b.loadout.skill_mods.get("inferno", {}))
		assert_false(a.loadout.skill_mods.get("inferno", {}).is_empty(), "%s: the bonus is applied" % tier)


func test_hellfire_makes_the_burning_hurt_more_in_play() -> void:
	var totals := []
	var pulses := []
	for with_bonus in [false, true]:
		var w := _world(1)
		if with_bonus:
			w.loadout.add_skill_mod("inferno", "burn_damage", "mul", 1.5)
		pulses.append(int(w.loadout.stats("inferno").burn_pulse))
		_mob(w, 100)
		w.runner.step(DT, w)
		w.runner.cooldowns["inferno"] = 1.0e9 # one cast: a recast would refresh the burn
		_run(w, 40 + 60 * 6)
		totals.append(w.swarm.burn_dealt)
	assert_eq(totals, [5 * pulses[0], 5 * pulses[1]], "five pulses of the rank-1 burn, each with its snapshot")
	assert_true(totals[1] > totals[0], "burn dealt %s" % [totals])


func test_spreading_fire_burns_two_more_monsters() -> void:
	var counts := []
	for with_bonus in [false, true]:
		var w := _world(1)
		if with_bonus:
			w.loadout.add_skill_mod("inferno", "blast_targets", "add", 2.0)
		var slots: Array[int] = []
		for k in 10:
			slots.append(_mob(w, 20 + 12 * k))
		w.runner.step(DT, w)
		_run(w, 40)
		counts.append(_burning(w, slots).size())
	assert_eq(counts, [6, 8])


# --- presentation --------------------------------------------------------------------------------------------------------

func test_the_text_states_the_blast_and_the_burn() -> void:
	var w := _world(1)
	var line := SkillText.new(w.book).level_line("inferno", 1, w.loadout.stats("inferno"))
	assert_true(line.contains("Burns for 5 s, 24% of base damage per second"), line)


func test_inferno_configures_a_burn_cue_the_scene_can_read() -> void:
	var on_hit: Dictionary = _world().book.def("inferno").on_hit
	assert_true(String(on_hit.cue).begins_with("Skill.wz/311.img/skill/3111003/tile/"), String(on_hit.cue))
	assert_eq(String(on_hit.pulse_field), "x")
	assert_eq(String(on_hit.duration_field), "time")
	assert_false(on_hit.has("chance_field"), "always burns")


# --- real cache: all eight ranks against Skill.wz ----------------------------------------------------------------------

func test_real_cache_all_eight_ranks_map_to_the_skill_wz_levels() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	var img := lib.img("Skill.wz/311.img")
	assert_true(img != null, "Skill.wz/311.img is in the cache")
	if img == null:
		lib.free()
		return
	var book := SkillBook.from_data(DataRepo.load_all().skills, {"311": img.root})
	var lo := Loadout.new(book)
	lo.weapon_family = "bow"
	var node: Dictionary = img.root.skill["3111003"]
	assert_eq(String(node.elemAttr), "f")
	assert_eq(int(node.weapon), 45, "bow")
	assert_eq(book.max_level("inferno"), 30)
	assert_eq(book.max_rank("inferno"), 8)
	var mapped := [4, 8, 12, 15, 19, 23, 27, 30] # ceil(rank x 30 / 8)
	for rank_value in range(1, 9):
		var lv: int = mapped[rank_value - 1]
		assert_eq(book.canonical_level("inferno", rank_value), lv, "rank %d" % rank_value)
		var level: Dictionary = node.level[str(lv)]
		var st := lo.stats("inferno", rank_value)
		var label := "rank %d (level %d)" % [rank_value, lv]
		assert_near(st.damage_pct, float(level.damage) / 100.0, 0.000001, label)
		assert_near(float(st.burn_share), float(level.x), 0.000001, label)
		assert_near(float(st.burn_time), float(level.time), 0.000001, label)
		assert_eq(st.blast_targets, int(level.mobCount), label)
		assert_eq(st.blast_targets, 6, label)
		assert_false(level.has("prop"), "%s: no chance field, the burn always applies" % label)
		var lt: Array = level.lt["$v"]
		var rb: Array = level.rb["$v"]
		assert_eq(st.box, Rect2(float(lt[0]), float(lt[1]), float(rb[0]) - float(lt[0]), float(rb[1]) - float(lt[1])), label)
		assert_eq(String(st.element), "f", label)
	# The spec's worked rank values (rank 1 / 4 / 8), as literals.
	for i in 3:
		var st := lo.stats("inferno", [1, 4, 8][i])
		assert_near(st.damage_pct, [0.65, 1.12, 1.50][i], 0.000001)
		assert_near(float(st.burn_share), [24.0, 35.0, 50.0][i], 0.000001)
		assert_near(float(st.burn_time), [5.0, 5.0, 10.0][i], 0.000001)
	assert_eq(lo.stats("inferno", 1).box, Rect2(-130, -100, 260, 200))
	assert_eq(lo.stats("inferno", 8).box, Rect2(-150, -100, 300, 200))
	# Art and sounds resolve, and the burning monster's cue is a real animation.
	for suffix: String in ["icon", "iconDisabled", "iconMouseOver"]:
		assert_true(lib.frame(book.wz_path("inferno") + "/" + suffix) != null, suffix)
	assert_eq(lib.anim(String(book.def("inferno").ball)).frame_count(), 3, "its own three-frame ball")
	assert_true(lib.anim(book.visual("inferno", "hit", 1, 1)).frame_count() == 5, "hit/0 has five frames")
	assert_eq(lib.anim(String(book.def("inferno").on_hit.cue)).frame_count(), 6, "tile/2: six frames of tall flame")
	for sound: String in book.def("inferno").sounds.values():
		assert_true(lib.sound(sound) != null, "sound %s" % sound)
	assert_eq(Array(lib.missing), [])
	lib.free()
