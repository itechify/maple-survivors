extends TestCase
## The headless run loop's injectable run policy and per-tick observer (balance_run.gd run_one / run_chain, #92).
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const BR := preload("res://tools/balance_run.gd")
const RUN_POLICY := preload("res://tools/run_policy.gd")
const DT := 1.0 / 60.0


## A custom policy: takes the last card offered, walks right, and counts what the loop asked of it.
class LastCardWalker extends "res://tools/run_policy.gd":
	var windows := 0
	var moves := 0
	var taken: Array = []

	func choose(w: RunWorld) -> void:
		while w.state == RunWorld.CHOOSING_UPGRADE:
			windows += 1
			var id := String(w.pending_cards[w.pending_cards.size() - 1].id)
			taken.append(id)
			take_card(w, id)

	func move(_w: RunWorld) -> MoveInput:
		moves += 1
		var input := MoveInput.new()
		input.right = true
		return input


func test_custom_policy_answers_windows_and_moves_every_tick() -> void:
	var data := RF.quiet_data()
	data.balance.run_time_cap = 0.5
	var w := RunWorld.new(RF.setup("quiet", 43, data))
	RF.place_player(w, 400)
	w.pending_bonus_choices = 2
	var x0 := w.player.pos.x
	var policy := LastCardWalker.new()
	var r: Dictionary = BR.run_one(w, policy, 43)
	assert_eq(policy.windows, 2, "both queued boss windows go to the injected policy")
	assert_eq(policy.moves, 30, "one move per fixed tick of the 0.5 s cap")
	assert_true(w.player.pos.x > x0, "the policy's input drove the player")
	assert_eq(r.cards_taken.size(), 2, "cards taken through take_card reach the record")
	for i in r.cards_taken.size():
		assert_true(String(r.cards_taken[i]).ends_with(":" + String(policy.taken[i])))
	assert_eq(r.state, "TIMEOUT")


func test_observer_sees_every_tick_and_its_events_before_the_record_folds_them() -> void:
	var data := RF.quiet_data()
	data.balance.player.skills = []
	data.balance.run_time_cap = 1.0
	var w := RunWorld.new(RF.setup("quiet", 27, data))
	RF.place_player(w, 400)
	RF.change_job_bare(w, 200)
	w.learn_skill("magic_guard")
	var seen := {"ticks": 0, "casts": []}
	var observer := func(_world: RunWorld, events: Array) -> void:
		seen.ticks += 1
		for e: Dictionary in events:
			if String(e.type) == "buff_cast":
				seen.casts.append([seen.ticks, String(e.skill)])
	var r: Dictionary = BR.run_one(w, "bot", 27, -1.0, 60.0, 0, observer)
	assert_eq(seen.ticks, 60, "one call per fixed tick of the 1 s cap")
	assert_eq(seen.casts, [[1, "magic_guard"]], "the first tick's Magic Guard cast reaches the observer on that tick")
	assert_eq(r.buff_casts.size(), 1, "the record still folds the events the observer saw")


func test_named_policy_object_reproduces_the_named_record() -> void:
	for policy_name: String in ["bot", "random", "first"]:
		var data := RF.quiet_data()
		data.stages.stages.quiet.keyframes = [{"t": 0, "rate": 10, "max_alive": 20, "pool": {"100100": 1}}]
		data.balance.run_time_cap = 20.0
		var a: Dictionary = BR.run_one(RunWorld.new(RF.setup("quiet", 9, data)), policy_name, 9)
		var b: Dictionary = BR.run_one(RunWorld.new(RF.setup("quiet", 9, data)), RUN_POLICY.new(policy_name, 9), 9)
		assert_true(int(a.spawned) > 0, "%s: the run had mobs to fight" % policy_name)
		assert_eq(JSON.stringify(b), JSON.stringify(a), "%s: an injected policy object plays the same run" % policy_name)


func test_chain_builds_one_policy_per_round_from_a_factory() -> void:
	var data := RF.quiet_data()
	data.stages.stages.quiet.duration = 2.0
	data.stages.stages.quiet.keyframes = [{"t": 0, "rate": 10, "max_alive": 20, "pool": {"100100": 1}}]
	data.balance.run_time_cap = 3.0
	var setups := [RF.setup("quiet", 0, data), RF.setup("quiet", 0, data)]
	setups[0].character = DataRepo.load_json("res://tests/fixtures/characters/lv35_magician_2nd.json")
	var made: Array = []
	var factory := func(tier_index: int, seed_value: int) -> RefCounted:
		made.append([tier_index, seed_value])
		return RUN_POLICY.new("random", seed_value)
	var a: Dictionary = BR.run_chain(setups, factory, 2026)
	var b: Dictionary = BR.run_chain(setups, "random", 2026)
	assert_eq(made, [[0, 2026], [1, BR.round_seed(2026, 1)]], "one policy per round, seeded by the round seed")
	assert_eq(JSON.stringify(a), JSON.stringify(b), "factory-built named policies reproduce the named chain")
