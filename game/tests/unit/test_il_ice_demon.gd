extends TestCase
## I/L Ice Demon and Element Composition (spec #319, ticket I7 #326): seeded fixed-tick casts at the RunWorld boundary.
## Skill.wz books are synthetic here (the WZ box and the 2/4/6 target ranks); the real-cache test at the end checks the
## mapped levels of all eight ranks against the shipped book.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const MOB := 1110100
const CASTER_X := 200.0


## Skill.wz-shaped levels: Ice Demon's canonical box (-300,-100)..(-15,0), `mobCount` 2 / 4 / 6 at levels 4 / 15 / 30, `time` 10 -> 15.
func _ice_demon_levels() -> Dictionary:
	var levels := {}
	for lv in range(1, 31):
		levels[str(lv)] = {"mad": 40.0 + 2.0 * lv, "mobCount": 2.0 if lv < 15 else 4.0 if lv < 30 else 6.0,
			"time": 10.0 if lv < 30 else 15.0, "x": 1.0, "lt": {"$v": [-300, -100]}, "rb": {"$v": [-15, 0]}}
	return levels


## Element Composition: `mad` 80 -> 140 and a freeze `time` with no `prop` at all (the WZ node has none).
func _composition_levels() -> Dictionary:
	var levels := {}
	for lv in range(1, 31):
		levels[str(lv)] = {"mad": 80.0 + 2.0 * lv, "time": 1.0 if lv < 30 else 2.0, "x": 1.0}
	return levels


func _world(key: String, p_seed := 326) -> RunWorld:
	var setup := RF.setup("quiet", p_seed, RF.quiet_data())
	setup.skill_imgs["222"] = {"skill": {"2221003": {"level": _ice_demon_levels()}}}
	setup.skill_imgs["221"] = {"skill": {"2211006": {"level": _composition_levels()}}}
	var w := RunWorld.new(setup)
	RF.place_player(w, CASTER_X)
	w.loadout.order.clear()
	w.learn_skill(key)
	w.loadout.set_caster(100.0, 0.0, 30)
	w.god = true
	return w


func _mob(w: RunWorld, x: float, elements: Dictionary = {}, codes: Dictionary = {}, mob_id := MOB) -> int:
	var m := RF.put_mob(w, mob_id, x, 195, 100000.0)
	w.swarm.hp[m] = 100000
	w.swarm.max_hp[m] = 100000
	w.swarm.mob_kind(m).move_speed = 0.0
	w.swarm.mob_kind(m).elements = elements
	w.swarm.mob_kind(m).element_codes = codes
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	return m


func _cast(w: RunWorld) -> void:
	w.drain_events()
	w.runner.step(DT, w)


func _tick(w: RunWorld, seconds: float) -> void:
	w.loadout.order.clear()
	for tick in ceili(seconds / DT):
		w.step(DT, MoveInput.new())


func _hurt(w: RunWorld, m: int) -> bool:
	return w.swarm.hp[m] < 100000


# --- Ice Demon -----------------------------------------------------------------------------------

func test_ice_demon_strikes_a_forward_box_on_the_side_the_caster_faces() -> void:
	for facing: int in [-1, 1]:
		var w := _world("ice_demon")
		w.player.facing = facing
		var ahead := _mob(w, CASTER_X + facing * 150.0)
		var behind := _mob(w, CASTER_X - facing * 150.0)
		var too_far := _mob(w, CASTER_X + facing * 340.0)
		_cast(w)
		assert_true(_hurt(w, ahead), "facing %d: the monster in the box" % facing)
		assert_false(_hurt(w, behind), "facing %d: nothing behind the caster" % facing)
		assert_false(_hurt(w, too_far), "facing %d: the box ends 300 px out" % facing)


func test_ice_demon_target_cap_follows_the_rank() -> void:
	for pair: Array in [[1, 2], [4, 4], [8, 6]]:
		var w := _world("ice_demon")
		w.player.facing = -1
		w.loadout.set_rank("ice_demon", int(pair[0]))
		var slots := []
		for k in 8:
			slots.append(_mob(w, CASTER_X - 60.0 - 25.0 * k))
		_cast(w)
		var hurt := slots.filter(func(s: int) -> bool: return _hurt(w, s))
		assert_eq(hurt.size(), int(pair[1]), "rank %d strikes %d monsters" % [pair[0], pair[1]])


func test_ice_demon_marks_survivors_fire_weak_and_fire_damage_is_x1_5() -> void:
	var w := _world("ice_demon")
	w.player.facing = -1
	var m := _mob(w, CASTER_X - 120.0)
	assert_near(w.swarm.element_multiplier(m, "f"), 1.0)
	_cast(w)
	assert_true(w.swarm.status_time(m, MobSwarm.FIRE_WEAK) > 0.0)
	assert_near(w.swarm.element_multiplier(m, "f"), 1.5, 1e-6, "a synthetic fire hit now deals x1.5")
	assert_near(w.swarm.element_multiplier(m, "i"), 1.0, 1e-6, "ice is untouched")
	assert_near(w.swarm.element_multiplier(m, "fs"), 1.25, 1e-6, "F/P's composition meets the mark")
	assert_near(w.swarm.element_multiplier(m, "il"), 1.0, 1e-6, "the I/L composition does not")


func test_the_mark_lasts_the_canonical_time_and_expires() -> void:
	var w := _world("ice_demon")
	w.player.facing = -1
	w.loadout.set_rank("ice_demon", 1)
	var m := _mob(w, CASTER_X - 120.0)
	_cast(w)
	assert_between(w.swarm.status_time(m, MobSwarm.FIRE_WEAK), 9.9, 10.0, "WZ `time` 10 at the rank-1 level")
	_tick(w, 9.5)
	assert_near(w.swarm.element_multiplier(m, "f"), 1.5)
	_tick(w, 1.0)
	assert_near(w.swarm.element_multiplier(m, "f"), 1.0)


func test_the_top_rank_mark_lasts_fifteen_seconds() -> void:
	var w := _world("ice_demon")
	w.player.facing = -1
	w.loadout.set_rank("ice_demon", 8)
	var m := _mob(w, CASTER_X - 120.0)
	_cast(w)
	assert_between(w.swarm.status_time(m, MobSwarm.FIRE_WEAK), 14.9, 15.0)


func test_bosses_take_the_damage_and_reject_the_mark() -> void:
	var w := _world("ice_demon")
	w.player.facing = -1
	var boss := _mob(w, CASTER_X - 120.0)
	w.swarm.mob_kind(boss).boss = true
	var plain := _mob(w, CASTER_X - 160.0, {}, {}, 100100) # another kind: `boss` is a MobKind flag
	_cast(w)
	assert_true(_hurt(w, boss), "the boss still takes the hit")
	assert_eq(w.swarm.status_time(boss, MobSwarm.FIRE_WEAK), 0.0)
	assert_true(w.swarm.status_time(plain, MobSwarm.FIRE_WEAK) > 0.0)


func test_an_ice_immune_monster_takes_no_damage_and_so_no_mark() -> void:
	# Existing behaviour (I3 note): on_hit runs only for a damaging hit, and Ice Demon's damage is ice.
	var w := _world("ice_demon")
	w.player.facing = -1
	var m := _mob(w, CASTER_X - 120.0, {"I": 0.0})
	_cast(w)
	assert_false(_hurt(w, m))
	assert_eq(w.swarm.status_time(m, MobSwarm.FIRE_WEAK), 0.0)


func test_ice_demon_casts_with_the_fallback_stance_and_does_not_need_a_target_beyond_the_box() -> void:
	var w := _world("ice_demon")
	w.player.facing = -1
	_mob(w, CASTER_X + 100.0)
	_cast(w)
	assert_eq(w.runner.casts, 0, "a monster behind the caster is not a target")
	var st := w.loadout.stats("ice_demon")
	assert_eq(String(st.action), "magic3")
	assert_eq(String(st.element), "i")
	assert_eq(String(st.cast_rule), "box")
	assert_near(float(w.book.def("ice_demon").cooldown), 2.0)


# --- Element Composition (I/L) -------------------------------------------------------------------

func test_composition_fires_one_projectile_and_freezes_without_a_chance_roll() -> void:
	var w := _world("element_composition_il")
	var m := _mob(w, CASTER_X + 150.0)
	_cast(w)
	assert_eq(w.runner.casts, 1)
	assert_eq(w.projectiles.active.count(1), 1, "one shot")
	_tick(w, 1.0)
	assert_true(_hurt(w, m))
	assert_true(w.swarm.status_time(m, MobSwarm.FREEZE) > 0.0, "frozen")


func test_composition_freeze_draws_no_random_number() -> void:
	# Same seed, a freezable mob against one the freeze rejects (a boss): the damage rolls are the only draws, so the
	# stream ends in the same state whether or not the freeze was applied.
	var states := []
	var frozen := []
	for boss: bool in [false, true]:
		var w := _world("element_composition_il")
		var m := _mob(w, CASTER_X + 150.0)
		w.swarm.mob_kind(m).boss = boss
		_cast(w)
		_tick(w, 1.0)
		states.append(w.rng.state)
		frozen.append(w.swarm.status_time(m, MobSwarm.FREEZE) > 0.0)
	assert_eq(frozen, [true, false])
	assert_eq(states[0], states[1], "applying the freeze consumed no random number")


func test_composition_definition_has_no_chance_field_and_checks_ice_resistance_only() -> void:
	var def: Dictionary = _world("element_composition_il").book.def("element_composition_il")
	assert_eq(String(def.on_hit.status), "freeze")
	assert_false(def.on_hit.has("chance_field"))
	assert_eq(String(def.on_hit.element), "i")
	assert_eq(String(def.element), "il")


func test_composition_rejects_bosses_and_ice_immune_monsters_but_not_lightning_immune_ones() -> void:
	var cases := {"boss": [true, {}, {}, false], "ice immune": [false, {"I": 0.0}, {"I": "1"}, false],
		"lightning immune": [false, {"L": 0.0}, {"L": "1"}, true]}
	for label: String in cases:
		var c: Array = cases[label]
		var w := _world("element_composition_il")
		var m := _mob(w, CASTER_X + 150.0, c[1], c[2])
		w.swarm.mob_kind(m).boss = c[0]
		_cast(w)
		_tick(w, 1.0)
		assert_true(_hurt(w, m), "%s still takes damage" % label)
		assert_eq(w.swarm.status_time(m, MobSwarm.FREEZE) > 0.0, c[3], label)


func test_composition_uses_the_mean_of_ice_and_lightning_multipliers() -> void:
	var w := _world("element_composition_il")
	var m := _mob(w, CASTER_X + 150.0, {"I": 1.5, "L": 0.0})
	assert_near(w.swarm.element_multiplier(m, "il"), 0.75, 1e-6, "(1.5 + 0.0) / 2")
	var plain := _mob(w, CASTER_X + 200.0)
	assert_near(w.swarm.element_multiplier(plain, "il"), 1.0)
	# And through a real hit: an ice-weak, lightning-immune mob takes 0.75 of what a neutral one takes.
	var dealt := []
	for elements: Dictionary in [{}, {"I": 1.5, "L": 0.0}]:
		var v := _world("element_composition_il")
		var target := _mob(v, CASTER_X + 150.0, elements)
		_cast(v)
		_tick(v, 1.0)
		dealt.append(100000 - v.swarm.hp[target])
	assert_true(dealt[1] > 0 and dealt[0] > 0)
	assert_near(float(dealt[1]) / float(dealt[0]), 0.75, 0.02)


# --- Real cache ----------------------------------------------------------------------------------

func test_cached_ranks_map_to_the_wz_levels_and_art_and_sounds_resolve() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	assert_true(lib.open())
	var imgs := {}
	for book: String in ["221", "222"]:
		imgs[book] = lib.img("Skill.wz/%s.img" % book).root
	var book := SkillBook.from_data(DataRepo.load_all().skills, imgs)
	var levels := [4, 8, 12, 15, 19, 23, 27, 30]
	for key: String in ["ice_demon", "element_composition_il"]:
		var lo := Loadout.new(book)
		assert_true(lo.add_skill(key))
		assert_eq(book.max_rank(key), 8)
		for rank in range(1, 9):
			lo.set_rank(key, rank)
			assert_eq(int(lo.stats(key).level), levels[rank - 1], "%s rank %d" % [key, rank])
		lo.set_rank(key, 1)
		var first: Dictionary = lo.stats(key)
		lo.set_rank(key, 8)
		var last: Dictionary = lo.stats(key)
		if key == "ice_demon":
			assert_eq(int(first.mob_count), 2)
			assert_eq(int(last.mob_count), 6)
			assert_eq(book.canonical(key, 4, "time"), 10.0)
			assert_eq(book.canonical(key, 30, "time"), 15.0)
			assert_eq(book.canonical(key, 30, "mad"), 100.0)
			assert_eq(book.canonical(key, 4, "mad"), 48.0)
			assert_eq(first.box, Rect2(-300, -100, 285, 100))
			assert_eq(last.box, Rect2(-300, -100, 285, 100))
		else:
			assert_eq(book.canonical(key, 4, "mad"), 90.0)
			assert_eq(book.canonical(key, 30, "mad"), 140.0)
			assert_eq(book.canonical(key, 4, "time"), 1.0)
			assert_eq(book.canonical(key, 30, "time"), 2.0)
			assert_eq(book.canonical(key, 30, "prop"), 0.0, "the WZ node has no prop")
		var d := book.def(key)
		for path: String in [d.effect, d.ball, d.hit]:
			if path != "":
				assert_true(lib.anim(path).frames.size() > 0, path)
		for path: String in d.sounds.values():
			if path != "":
				assert_true(lib.sound(path) != null, path)
	assert_true(lib.missing.is_empty(), str(lib.missing))
	lib.free()
