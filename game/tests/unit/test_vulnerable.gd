extends TestCase
## The vulnerability status table (spec #319 M4, ticket #322): ice_weak and fire_weak as timed x1.5 marks, and element
## compositions (`fs`, `il`) resolved as the mean of their constituents' live multipliers. Synthetic inputs, fixed dt.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const ELEMENT_LETTERS := ["F", "I", "L", "S", "H"]
const MULTIPLIERS := [0.0, 0.5, 1.0, 1.5]


func _world() -> RunWorld:
	var w := RF.quiet_world()
	w.loadout.order.clear()
	return w


func _tick(w: RunWorld, ticks: int) -> void:
	for tick in ticks:
		w.step(DT, MoveInput.new())


func _mob(w: RunWorld, elements: Dictionary = {}) -> int:
	var m := RF.put_mob(w, 1110100, 250.0, 195, 100000.0)
	w.swarm.hp[m] = 100000
	w.swarm.max_hp[m] = 100000
	w.swarm.mob_kind(m).move_speed = 0.0
	w.swarm.mob_kind(m).elements = elements
	return m


## The pre-#322 formula, kept here as the oracle for the identity table.
func _old_multiplier(swarm: MobSwarm, i: int, element: String) -> float:
	var mk := swarm.mob_kind(i)
	if element.to_lower() == "fs":
		return (mk.element_multiplier("f") + mk.element_multiplier("s")) * 0.5
	if element.to_lower() == "i" and swarm.status_time(i, MobSwarm.ICE_WEAK) > 0.0:
		return 1.5
	return mk.element_multiplier(element)


func test_table_names_the_element_each_timer_makes_weak() -> void:
	assert_eq(MobSwarm.VULNERABLE[MobSwarm.ICE_WEAK], "i")
	assert_eq(MobSwarm.VULNERABLE[MobSwarm.FIRE_WEAK], "f")
	assert_eq(MobSwarm.FIRE_WEAK, 6)
	assert_eq(MobSwarm.STATUS_COUNT, 7)
	assert_eq(MobSwarm.STATUS_NAMES.size(), MobSwarm.STATUS_COUNT)
	assert_eq(MobSwarm.STATUS_ELEMENTS.size(), MobSwarm.STATUS_COUNT)
	assert_eq(MobSwarm.STATUS_NAMES[MobSwarm.FIRE_WEAK], "fire_weak")


func test_fire_weak_makes_fire_x1_5_for_its_time_and_expires_with_the_event() -> void:
	var w := _world()
	var m := _mob(w)
	assert_near(w.swarm.element_multiplier(m, "f"), 1.0)
	w.drain_events()
	assert_true(w.swarm.apply_status(m, "fire_weak", {"time": 1.0, "element": ""}, w.events))
	var applied := w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "mob_status_applied")
	assert_eq(applied.size(), 1)
	assert_eq(applied[0].status, "fire_weak")
	assert_near(w.swarm.element_multiplier(m, "f"), 1.5)
	assert_near(w.swarm.element_multiplier(m, "F"), 1.5)
	assert_near(w.swarm.element_multiplier(m, "i"), 1.0, 1e-6, "only fire is marked")
	_tick(w, 59)
	assert_near(w.swarm.element_multiplier(m, "f"), 1.5, 1e-6, "still weak before the time is up")
	_tick(w, 3)
	assert_near(w.swarm.element_multiplier(m, "f"), 1.0)
	var expired := w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "mob_status_expired")
	assert_eq(expired.size(), 1)
	assert_eq(expired[0].status, "fire_weak")


func test_fire_weak_and_ice_weak_are_independent_on_one_mob() -> void:
	var w := _world()
	var m := _mob(w)
	assert_true(w.swarm.apply_status(m, "ice_weak", {"time": 1.0}, w.events))
	assert_near(w.swarm.element_multiplier(m, "f"), 1.0, 1e-6, "ice_weak leaves fire alone")
	assert_true(w.swarm.apply_status(m, "fire_weak", {"time": 3.0}, w.events))
	assert_near(w.swarm.element_multiplier(m, "f"), 1.5)
	assert_near(w.swarm.element_multiplier(m, "i"), 1.5)
	_tick(w, 62)
	assert_near(w.swarm.status_time(m, MobSwarm.ICE_WEAK), 0.0)
	assert_near(w.swarm.element_multiplier(m, "i"), 1.0, 1e-6, "ice mark expired first")
	assert_near(w.swarm.element_multiplier(m, "f"), 1.5, 1e-6, "fire mark runs on")


func test_fire_weak_refreshes_without_stacking() -> void:
	var w := _world()
	var m := _mob(w)
	w.swarm.apply_status(m, "fire_weak", {"time": 2.0}, w.events)
	_tick(w, 60)
	assert_true(w.swarm.apply_status(m, "fire_weak", {"time": 2.0}, w.events))
	assert_near(w.swarm.status_time(m, MobSwarm.FIRE_WEAK), 2.0, 1e-6, "refreshed to the new time, not summed")
	assert_near(w.swarm.element_multiplier(m, "f"), 1.5, 1e-6, "never x2.25")


func test_bosses_and_steady_slots_reject_fire_weak() -> void:
	var w := _world()
	var boss := _mob(w)
	w.swarm.mob_kind(boss).boss = true
	assert_false(w.swarm.apply_status(boss, "fire_weak", {"time": 4.0}, w.events))
	assert_false(w.swarm.accepts_status(boss, "fire_weak", {"element": ""}))
	assert_near(w.swarm.element_multiplier(boss, "f"), 1.0)
	var steady := _mob(w)
	w.swarm.steady[steady] = 1
	assert_false(w.swarm.apply_status(steady, "fire_weak", {"time": 4.0}, w.events))


func test_fire_weak_overrides_fire_immunity_and_resistance() -> void:
	for base: float in [0.0, 0.5]:
		var w := _world()
		var m := _mob(w, {"F": base})
		assert_near(w.swarm.element_multiplier(m, "f"), base)
		# Mob.wz digit 1/2 would reject an element-bearing status; the mark carries no element, like ice_weak.
		w.swarm.mob_kind(m).element_codes = {"F": "1" if base == 0.0 else "2"}
		assert_true(w.swarm.apply_status(m, "fire_weak", {"time": 3.0, "element": ""}, w.events))
		assert_near(w.swarm.element_multiplier(m, "f"), 1.5, 1e-6, "mark beats multiplier %s" % base)


func test_il_is_the_mean_of_live_ice_and_lightning_and_ice_weak_raises_it() -> void:
	var w := _world()
	var m := _mob(w, {"I": 0.5, "L": 1.5})
	assert_near(w.swarm.element_multiplier(m, "il"), 1.0)
	assert_near(w.swarm.element_multiplier(m, "IL"), 1.0)
	w.swarm.apply_status(m, "ice_weak", {"time": 3.0}, w.events)
	assert_near(w.swarm.element_multiplier(m, "il"), 1.5, 1e-6, "mean of the live ice (1.5) and lightning (1.5)")
	var immune := _mob(w, {"I": 0.0, "L": 1.0})
	assert_near(w.swarm.element_multiplier(immune, "il"), 0.5)
	w.swarm.apply_status(immune, "ice_weak", {"time": 3.0}, w.events)
	assert_near(w.swarm.element_multiplier(immune, "il"), 1.25, 1e-6, "ice mark overrides immunity inside a mean")
	w.swarm.apply_status(immune, "fire_weak", {"time": 3.0}, w.events)
	assert_near(w.swarm.element_multiplier(immune, "il"), 1.25, 1e-6, "fire mark is not a constituent of il")


func test_fs_unchanged_without_marks_and_fire_weak_raises_its_fire_half() -> void:
	var w := _world()
	var m := _mob(w, {"F": 1.5, "S": 0.5})
	assert_near(w.swarm.element_multiplier(m, "fs"), 1.0)
	w.swarm.apply_status(m, "ice_weak", {"time": 3.0}, w.events)
	assert_near(w.swarm.element_multiplier(m, "fs"), 1.0, 1e-6, "an ice mark does not touch fs")
	var n := _mob(w, {"F": 0.5, "S": 0.5})
	w.swarm.apply_status(n, "fire_weak", {"time": 3.0}, w.events)
	assert_near(w.swarm.element_multiplier(n, "fs"), 1.0, 1e-6, "(1.5 + 0.5) / 2")


func test_element_multiplier_is_bit_identical_to_the_old_formula_without_fire_weak() -> void:
	var w := _world()
	var m := _mob(w)
	var checked := 0
	for ice_weak: bool in [false, true]:
		w.swarm.status_left[m * MobSwarm.STATUS_COUNT + MobSwarm.ICE_WEAK] = 5.0 if ice_weak else 0.0
		for f: float in MULTIPLIERS:
			for i: float in MULTIPLIERS:
				for l: float in [0.0, 1.0, 1.5]:
					for s: float in MULTIPLIERS:
						for h: float in [0.5, 1.0, 1.5]:
							w.swarm.mob_kind(m).elements = {"F": f, "I": i, "L": l, "S": s, "H": h}
							for element: String in ["f", "i", "l", "s", "h", "fs", "FS", "I", "", "x"]:
								var got := w.swarm.element_multiplier(m, element)
								var want := _old_multiplier(w.swarm, m, element)
								if got != want:
									fail("%s ice_weak=%s elements F%s I%s L%s S%s H%s: %s != %s" % [
										element, ice_weak, f, i, l, s, h, got, want])
									return
								checked += 1
	assert_true(checked > 10000, "table covered %d combinations" % checked)


func test_fire_weak_applied_by_a_skill_on_hit_marks_the_survivor() -> void:
	var data := RF.quiet_data()
	data.skills.skills.fire_demon.on_hit = {"status": "fire_weak", "element": ""}
	var setup := RF.setup("quiet", 322, data)
	setup.skill_imgs["212"] = {"skill": {}}
	var levels := {}
	for lv in range(1, 31):
		levels[str(lv)] = {"mad": 120.0, "mobCount": 6.0, "attackCount": 1.0, "time": 4.0, "prop": 100.0,
			"lt": {"$v": [-200, -150]}, "rb": {"$v": [200, 150]}}
	setup.skill_imgs["212"].skill["2121003"] = {"level": levels}
	var w := RunWorld.new(setup)
	RF.place_player(w, 200)
	w.loadout.order.clear()
	w.learn_skill("fire_demon")
	w.loadout.set_caster(100.0, 0.0, 30)
	var m := _mob(w)
	w.swarm.mob_kind(m).elements = {"F": 0.5}
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	w.runner.step(DT, w)
	assert_true(w.swarm.status_time(m, MobSwarm.FIRE_WEAK) > 0.0)
	assert_near(w.swarm.status_time(m, MobSwarm.ICE_WEAK), 0.0)
	assert_near(w.swarm.element_multiplier(m, "f"), 1.5)
