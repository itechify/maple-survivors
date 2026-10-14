extends TestCase
## Shared boss action timing through a seeded world: a stance holds grounded movement/facing and expires by sim time.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0


func test_boss_action_holds_movement_and_facing_for_its_declared_duration() -> void:
	var data := RF.quiet_data()
	data.balance.player.skills = []
	data.stages.stages.quiet.bosses = [{"mob_id": 6130101, "time": 0.5}]
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
	data.balance.player.skills = []
	data.stages.stages.quiet.bosses = [{"mob_id": 6130101, "time": 0.5}]
	var w := RunWorld.new(RF.setup("quiet", 2305, data))
	w.god = true
	for tick in 60:
		w.step(DT, MoveInput.new())
	w.bosses.begin_action(0, "attack1", 6.0, -1, w.time)
	for tick in 330:
		w.step(DT, MoveInput.new())
	assert_eq(w.bosses.records[0].teleports, 0, "a windup is deliberate standing, not a pursuit stall")
	assert_false(w.bosses.records[0].fading)
