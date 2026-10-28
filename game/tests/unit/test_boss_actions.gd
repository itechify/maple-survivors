extends TestCase
## Shared boss action timing through a seeded world: a stance holds grounded movement/facing and expires by sim time.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0


func test_boss_action_holds_movement_and_facing_for_its_declared_duration() -> void:
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["212"]["start_skills"] = []
	RF.set_bosses(data.stages.stages.quiet, [{"mob_id": 6130101, "time": 0.5}])
	var w := RunWorld.new(RF.setup("quiet", 2301, data))
	w.god = true
	for tick in 60:
		w.step(DT, MoveInput.new())
	var slot := int(w.bosses.records[0].slot)
	var anchor := Vector2(w.swarm.x[slot], w.swarm.y[slot])
	assert_true(w.bosses.can_act(0, w.time))
	w.bosses.begin_action(0, "attack1", 1.85, -1, w.time)
	for tick in 30:
		w.step(DT, MoveInput.new())
	assert_eq(Vector2(w.swarm.x[slot], w.swarm.y[slot]), anchor, "windup holds its grounded anchor")
	assert_eq(w.swarm.facing[slot], -1, "action keeps its captured facing")
	assert_false(w.bosses.can_act(0, w.time), "skills and attacks share one busy gate")
	var snapshot: Dictionary = w.bosses.action_snapshot(w.swarm)
	assert_eq(snapshot.actions[slot], "attack1")
	assert_near(float(snapshot.times[slot]), 0.5, DT)
	for tick in 82:
		w.step(DT, MoveInput.new())
	assert_true(w.bosses.can_act(0, w.time))
	assert_eq(w.bosses.action_snapshot(w.swarm).actions[slot], "", "normal movement/animation resume after the stance")


func test_an_authored_action_hold_does_not_count_as_failed_pursuit_for_teleport() -> void:
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["212"]["start_skills"] = []
	RF.set_bosses(data.stages.stages.quiet, [{"mob_id": 6130101, "time": 0.5}])
	var w := RunWorld.new(RF.setup("quiet", 2305, data))
	w.god = true
	for tick in 60:
		w.step(DT, MoveInput.new())
	w.bosses.begin_action(0, "attack1", 6.0, -1, w.time)
	for tick in 330:
		w.step(DT, MoveInput.new())
	assert_eq(w.bosses.records[0].teleports, 0, "a windup is deliberate standing, not a pursuit stall")
	assert_false(w.bosses.records[0].fading)


func test_action_view_is_borrowed_and_refreshes_without_replacing_the_pool() -> void:
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["212"]["start_skills"] = []
	RF.set_bosses(data.stages.stages.quiet, [{"mob_id": 6130101, "time": 0.5}])
	var w := RunWorld.new(RF.setup("quiet", 2306, data))
	w.god = true
	var view := w.bosses.action_snapshot(w.swarm)
	for tick in 60:
		w.step(DT, MoveInput.new())
	var slot := int(w.bosses.records[0].slot)
	w.bosses.begin_action(0, "attack1", 0.1, -1, w.time)
	var refreshed := w.bosses.action_snapshot(w.swarm)
	assert_true(is_same(view, refreshed), "callers borrow the persistent action view")
	assert_eq(view.actions[slot], "attack1", "a retained view observes the current refresh")
	w.step(DT, MoveInput.new())
	assert_near(float(view.times[slot]), DT, 1e-6)
	for tick in 6:
		w.step(DT, MoveInput.new())
	assert_eq(view.actions[slot], "", "expiry clears the borrowed slot")
	assert_eq(view.times[slot], 0.0)
	assert_eq(view.facings[slot], 0)
	w.bosses.begin_action(0, "skill1", 5.0, 1, w.time)
	w.bosses.action_snapshot(w.swarm)
	assert_eq(view.actions[slot], "skill1")
	w.bosses.mark_dead(0, slot, w.player.pos, w)
	w.bosses.action_snapshot(w.swarm)
	assert_eq(view.actions[slot], "", "death clears a live action immediately on refresh")
	assert_eq(view.times[slot], 0.0)
	assert_eq(view.facings[slot], 0)


func test_action_view_tracks_relocation_growth_death_and_fresh_slot_reuse() -> void:
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["212"]["start_skills"] = []
	RF.set_bosses(data.stages.stages.quiet, [{"mob_id": 6130101, "time": 0.5}])
	var w := RunWorld.new(RF.setup("quiet", 2307, data))
	w.god = true
	for tick in 60:
		w.step(DT, MoveInput.new())
	var slot := int(w.bosses.records[0].slot)
	w.bosses.begin_action(0, "attack1", 5.0, -1, w.time)
	var view := w.bosses.action_snapshot(w.swarm)
	var moved := w.relocate_mob(slot, Vector2(600, 200), w.fhm.find_below(600, 190))
	w.bosses.action_snapshot(w.swarm)
	assert_eq(view.actions[moved], "attack1", "relocation preserves the boss action and logical identity")
	var old_capacity := w.swarm.capacity()
	for index in old_capacity:
		RF.put_mob(w, 100100, 700, 190)
	w.bosses.action_snapshot(w.swarm)
	assert_true(view.actions.size() > old_capacity, "borrowed buffers follow swarm growth")
	assert_eq(view.actions[moved], "attack1")
	assert_eq(view.actions[view.actions.size()-1], "", "new slots start without overrides")
	# Immediate pool replacement must not inherit a still-scheduled boss's stance.
	w.swarm.despawn(moved)
	var fresh := RF.put_mob(w, 6130101, 600, 190)
	assert_eq(fresh, moved, "fixture reuses the same slot and kind with a fresh identity")
	w.bosses.action_snapshot(w.swarm)
	assert_eq(view.actions[fresh], "", "a new entity never inherits the previous boss action")
	assert_eq(view.times[fresh], 0.0)
	assert_eq(view.facings[fresh], 0)
	w.bosses.mark_dead(0, moved, Vector2(600, 200), w)
	w.bosses.action_snapshot(w.swarm)
	assert_eq(view.actions[fresh], "", "death keeps the reused slot clear")
