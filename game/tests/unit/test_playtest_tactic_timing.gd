extends TestCase
## Tactic decision points of the playtest run policy (spec #91 ticket #95): a `tactic` decide at the round start and
## at every checkpoint, triggers (HP low / critical, a boss spawn, a mob-bucket jump, a resolved card window), the
## minimum hold time with critical HP as the emergency, and the tactic telemetry.
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const BR := preload("res://tools/balance_run.gd")
const POLICY := preload("res://tools/playtest/playtest_policy.gd")
const BRAIN_LINK := preload("res://tools/playtest/brain_link.gd")
const DT := 1.0 / 60.0


## A brain that answers tactic decides through `tactic_answer` (decide -> option id) and everything else with the
## baseline, and keeps every decide it was asked.
class ScriptedBrain:
	extends "res://tools/playtest/brain_link.gd"
	var asked: Array = []
	var tactic_answer: Callable

	func ask(decide: Dictionary) -> Dictionary:
		asked.append(decide)
		var answer := String(decide.baseline.get("sensible", ""))
		if String(decide.kind) == "tactic" and tactic_answer.is_valid():
			answer = String(tactic_answer.call(decide))
		return {"id": int(decide.id), "answer": answer, "source": "test", "confidence": 0.9}

	func tactics() -> Array:
		return asked.filter(func(d: Dictionary) -> bool: return String(d.kind) == "tactic")


func _brain(answer := "kite") -> ScriptedBrain:
	var b := ScriptedBrain.new()
	b.tactic_answer = func(_d: Dictionary) -> String: return answer
	return b


## One run-loop tick, as balance_run.gd run_one does it.
func _tick(w: RunWorld, policy: POLICY) -> void:
	policy.choose(w)
	w.step(DT, policy.move(w))
	policy.observe(w, w.drain_events())


func _ticks_of(brain: ScriptedBrain) -> Array:
	return brain.tactics().map(func(d: Dictionary) -> int: return int(d.tick))


func _triggers_of(brain: ScriptedBrain) -> Array:
	return brain.tactics().map(func(d: Dictionary) -> String: return String(d.situation.tactic.trigger))


func test_round_start_asks_a_tactic_decide_with_buckets_and_allowed_tactics() -> void:
	var w := RF.quiet_world(400.0, 61)
	var brain := _brain()
	var policy := POLICY.new(brain)
	_tick(w, policy)
	var d: Dictionary = brain.tactics()[0]
	assert_eq(int(d.tick), 0)
	assert_eq(d.options.map(func(o: Dictionary) -> String: return String(o.id)),
		["kite", "aggressive", "defensive", "explore", "collect", "hold"], "every tactic, in a fixed order")
	for o: Dictionary in d.options:
		assert_true(String(o.get("desc", "")) != "", "each tactic option says what it does")
	assert_eq(String(d.baseline.sensible), "kite", "the sensible baseline always kites")
	assert_eq(String(d.situation.tactic.trigger), "start")
	assert_eq(String(d.situation.tactic.current), "kite")
	assert_true(d.situation.buckets.has("hp"), "the situation carries the buckets")


func test_checkpoints_every_eight_seconds() -> void:
	var w := RF.quiet_world(400.0, 62)
	var brain := _brain()
	var policy := POLICY.new(brain)
	for i in 60 * 20:
		_tick(w, policy)
	assert_eq(_ticks_of(brain), [0, 480, 960], "start, then every 8 s of run time")
	assert_eq(_triggers_of(brain), ["start", "checkpoint", "checkpoint"])


func test_checkpoint_interval_is_a_parameter() -> void:
	var w := RF.quiet_world(400.0, 62)
	var brain := _brain()
	var policy := POLICY.new(brain)
	policy.tactic_params.checkpoint_s = 5.0
	for i in 60 * 11:
		_tick(w, policy)
	assert_eq(_ticks_of(brain), [0, 300, 600])


func test_the_answer_sets_the_tactic_and_is_recorded() -> void:
	var w := RF.quiet_world(400.0, 63)
	var policy := POLICY.new(_brain("hold"))
	assert_eq(policy.tactic, "kite", "a round starts kiting")
	for i in 60:
		_tick(w, policy)
	assert_eq(policy.tactic, "hold")
	var t: Dictionary = policy.tactic_summary()
	assert_eq(int(t.switches), 1)
	assert_eq(t.log[0].from, "kite")
	assert_eq(t.log[0].to, "hold")
	assert_eq(t.log[0].trigger, "start")
	assert_near(float(t.seconds.hold), 1.0, 1e-6, "one second held")
	assert_near(float(t.shares.hold), 1.0, 1e-6)


func test_invalid_tactic_answer_keeps_the_baseline() -> void:
	var w := RF.quiet_world(400.0, 64)
	var policy := POLICY.new(_brain("fly"))
	_tick(w, policy)
	assert_eq(policy.tactic, "kite")
	assert_eq(String(policy.decisions[0].source), "baseline")


func test_hp_low_waits_for_the_hold_time() -> void:
	var w := RF.quiet_world(400.0, 65)
	var brain := _brain("hold")
	var policy := POLICY.new(brain)
	for i in 60:
		_tick(w, policy)
	w.player_state.hp = int(w.player_state.max_hp * 0.4)
	for i in 300:
		_tick(w, policy)
	assert_eq(_ticks_of(brain), [0, 240], "HP low 1 s after a switch is answered when the 4 s hold ends")
	assert_eq(_triggers_of(brain), ["start", "hp_low"])


func test_critical_hp_is_an_emergency() -> void:
	var w := RF.quiet_world(400.0, 66)
	var brain := _brain("hold")
	var policy := POLICY.new(brain)
	for i in 60:
		_tick(w, policy)
	w.player_state.hp = int(w.player_state.max_hp * 0.1)
	_tick(w, policy)
	assert_eq(_ticks_of(brain), [0, 60], "critical HP is asked at once, inside the hold")
	assert_eq(_triggers_of(brain), ["start", "hp_critical"])


func test_hp_low_after_a_kept_tactic_is_asked_at_once() -> void:
	var w := RF.quiet_world(400.0, 67)
	var brain := _brain("kite")
	var policy := POLICY.new(brain)
	for i in 60:
		_tick(w, policy)
	w.player_state.hp = int(w.player_state.max_hp * 0.4)
	_tick(w, policy)
	assert_eq(_triggers_of(brain), ["start", "hp_low"], "no switch happened, so there is nothing to hold")


func test_a_mob_bucket_jump_of_two_steps_triggers() -> void:
	var w := RF.quiet_world(400.0, 68)
	var brain := _brain()
	var policy := POLICY.new(brain)
	_tick(w, policy)
	RF.put_mob(w, 100100, 460.0)
	_tick(w, policy)
	assert_eq(_triggers_of(brain), ["start"], "none -> few is one step")
	for x: float in [480.0, 500.0, 520.0]:
		RF.put_mob(w, 100100, x)
	_tick(w, policy)
	assert_eq(_triggers_of(brain), ["start", "crowd"], "none (at the last decision) -> crowd is two steps")


func test_a_boss_spawn_triggers() -> void:
	var w := RF.quiet_world(400.0, 69)
	var brain := _brain()
	var policy := POLICY.new(brain)
	_tick(w, policy)
	policy.observe(w, [{"type": "boss_spawned", "boss_index": 0, "mob": 0, "mob_id": 100100,
		"pos": Vector2.ZERO, "time": w.time}])
	_tick(w, policy)
	assert_eq(_triggers_of(brain), ["start", "boss"])


func test_a_resolved_card_window_triggers() -> void:
	var w := RF.quiet_world(400.0, 70)
	var brain := _brain()
	var policy := POLICY.new(brain)
	_tick(w, policy)
	w.pending_bonus_choices = 1
	w.step(DT, MoveInput.new())
	assert_eq(w.state, RunWorld.CHOOSING_UPGRADE, "fixture: a card window is open")
	_tick(w, policy)
	assert_eq(_triggers_of(brain), ["start", "card"])


func test_every_kite_answer_plays_exactly_the_bot_run() -> void:
	var data := RF.quiet_data()
	data.stages.stages.quiet.keyframes = [{"t": 0, "rate": 10, "max_alive": 20, "pool": {"100100": 1}}]
	data.balance.run_time_cap = 40.0
	var a: Dictionary = BR.run_one(RunWorld.new(RF.setup("quiet", 71, data)), "bot", 71)
	var brain := _brain("kite")
	var policy := POLICY.new(brain)
	var b: Dictionary = BR.run_one(RunWorld.new(RF.setup("quiet", 71, data)), policy, 71)
	assert_true(int(a.spawned) > 0, "the run had mobs")
	assert_true(brain.tactics().size() >= 5, "tactic decisions were asked through the round")
	assert_eq(JSON.stringify(b), JSON.stringify(a), "all-kite tactics play the bot run byte for byte")
	assert_near(float(policy.tactic_summary().shares.kite), 1.0, 1e-6)
