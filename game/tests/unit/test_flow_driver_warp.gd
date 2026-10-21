extends TestCase
## The diagnostic flow warp must deliver terminal events emitted by answers as well as combat ticks.

const RF := preload("res://tests/fixtures/run_fixtures.gd")


class CapturingRun extends RunScene:
	var received: Array = []

	func handle_events(events: Array) -> void:
		received.append_array(events)

	func _apply_look() -> void:
		pass

	func _present(_delta: float) -> void:
		pass

	func build_summary() -> Dictionary:
		return {"cleared": world.state == RunWorld.CLEARED}


class HeadlessDriver extends "res://scenes/debug/flow_driver.gd":
	func _shot(_step: String, _settle_seconds := 0.35) -> void:
		pass

	func _collect_missing(_node: Node) -> void:
		pass


func test_diagnostic_warp_delivers_clear_from_final_answer_with_and_without_swept_levels() -> void:
	for sweep in [false, true]:
		var w := RF.quiet_world(400.0, 71)
		w.balance.player.skills = []
		w.loadout.order.clear()
		w.bosses = BossDirector.new([{"mob_id": 2220000, "time": 0.0}])
		w.bosses.records[0].dead = true
		w.pending_bonus_choices = 1
		w._advance_queue()
		if sweep:
			w.pickups.spawn(Vector2(1300, -500), w.progression.exp_to_next(), 4000000, w.player.pos)
		w.drain_events()
		var run := CapturingRun.new()
		run.world = w
		var flow := SceneFlow.new()
		flow.current = run
		var driver := HeadlessDriver.new()
		driver.flow = flow
		# This fixture needs no job pages, tick yields or screenshot awaits, so the real warp completes synchronously.
		driver._warp_round()
		assert_eq(w.state, RunWorld.CLEARED)
		assert_eq(w.time, 0.0, "the final answer clears without another combat tick")
		assert_eq(w.progression.level, 2 if sweep else 1)
		assert_eq(run.received.filter(func(e: Dictionary) -> bool: return e.type == "stage_cleared").size(), 1,
			"the choice-generated clear reaches RunScene presentation exactly once (sweep=%s)" % sweep)
		assert_false(run.received.any(func(e: Dictionary) -> bool: return e.type == "choice_pending"),
			"answered warp cards must not reopen over the clear presentation")
		assert_true(run.is_processing(), "presentation resumes after the diagnostic warp")
		driver.free()
		flow.free()
		run.free()
