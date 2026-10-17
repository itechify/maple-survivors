extends TestCase
## Personality parameters on the game side (spec #91 ticket #97): PlaytestPolicy.configure takes the driver params of
## a personality (tools/playtest/personalities/<name>.json through the Node CLI): allowed tactics, the default tactic,
## checkpoint and hold times, and the motor layer. The sensible params (kite only, no noise) must play exactly the
## BotInput round; the Node test pins tools/playtest/personalities/sensible.json to the same SENSIBLE dictionary.
## Tactic decides also show the last switches; card options carry BotInput's score, the card's stat and role.
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const BR := preload("res://tools/balance_run.gd")
const POLICY := preload("res://tools/playtest/playtest_policy.gd")
const BRAIN_LINK := preload("res://tools/playtest/brain_link.gd")
const DT := 1.0 / 60.0

## sensible.json's driver params (tools/playtest/test/personality.test.ts asserts the file resolves to exactly this).
const SENSIBLE := {"name": "sensible", "tactics": {"allowed": ["kite"], "default": "kite", "checkpoint_s": 8, "hold_s": 4},
	"motor": {"reaction_delay_ticks": 0, "mistake_rate": 0, "potion_hp_fraction": null, "potion_mp_fraction": null}}


## Answers tactic decides through `pick` (decide -> id) and everything else with the baseline; keeps every decide.
class ScriptedBrain:
	extends "res://tools/playtest/brain_link.gd"
	var asked: Array = []
	var pick: Callable

	func ask(decide: Dictionary) -> Dictionary:
		asked.append(decide)
		var answer := String(decide.baseline.get("sensible", ""))
		if String(decide.kind) == "tactic" and pick.is_valid():
			answer = String(pick.call(decide))
		return {"id": int(decide.id), "answer": answer, "source": "test", "confidence": 0.9}

	func of_kind(kind: String) -> Array:
		return asked.filter(func(d: Dictionary) -> bool: return String(d.kind) == kind)


func _tick(w: RunWorld, policy: POLICY) -> void:
	policy.choose(w)
	w.step(DT, policy.move(w))
	policy.observe(w, w.drain_events())


func test_sensible_params_play_exactly_the_bot_run_and_ask_no_tactic() -> void:
	var data := RF.quiet_data()
	data.stages.stages.quiet.keyframes = [{"t": 0, "rate": 10, "max_alive": 20, "pool": {"100100": 1}}]
	data.balance.run_time_cap = 40.0
	var a: Dictionary = BR.run_one(RunWorld.new(RF.setup("quiet", 71, data)), "bot", 71)
	var brain := ScriptedBrain.new()
	var policy := POLICY.new(brain, 71)
	policy.configure(SENSIBLE)
	var b: Dictionary = BR.run_one(RunWorld.new(RF.setup("quiet", 71, data)), policy, 71)
	assert_true(int(a.spawned) > 0, "the run had mobs")
	assert_eq(JSON.stringify(b), JSON.stringify(a), "the sensible personality plays the bot run byte for byte")
	assert_eq(brain.of_kind("tactic").size(), 0, "one allowed tactic: nothing to decide")
	assert_near(float(policy.tactic_summary().shares.kite), 1.0, 1e-6)
	assert_eq(int(policy.motor.summary().delayed_ticks) + int(policy.motor.summary().bursts), 0)


## A real round of `stage` from the asset cache, capped at `cap` seconds.
func _real_world(stage: String, seed_value: int, cap: float) -> RunWorld:
	var data := DataRepo.load_all()
	data.balance["run_time_cap"] = cap
	var root := AssetCachePaths.resolve_cache_root()
	var missing := PackedStringArray()
	var setup := DataRepo.build_setup(data, stage, 0, Vector2(800, 600),
		func(p: String) -> Dictionary: return BR._json(root, p),
		func(id: int) -> Dictionary: return BR._json(root, "Mob.wz/%07d.img" % id), missing)
	setup.seed = seed_value
	return RunWorld.new(setup)


func test_sensible_params_play_exactly_the_bot_run_on_the_real_map() -> void:
	# Needs the real asset cache; a SKIP proves nothing about the identity.
	if not require_cache():
		return
	var a: Dictionary = BR.run_one(_real_world("henesys_hg1", 2026, 150.0), "bot", 2026)
	var policy := POLICY.new(BRAIN_LINK.new(), 2026)
	policy.configure(SENSIBLE)
	var b: Dictionary = BR.run_one(_real_world("henesys_hg1", 2026, 150.0), policy, 2026)
	assert_true(int(a.kills) > 0 and a.cards_taken.size() > 0, "the real round had kills and card windows")
	assert_eq(JSON.stringify(b), JSON.stringify(a), "the sensible personality plays the real bot round byte for byte")


func test_configure_sets_allowed_tactics_default_and_timing() -> void:
	var w := RF.quiet_world(400.0, 61)
	var brain := ScriptedBrain.new()
	brain.pick = func(d: Dictionary) -> String: return String(d.situation.tactic.current)
	var policy := POLICY.new(brain, 61)
	policy.configure({"tactics": {"allowed": ["explore", "kite"], "default": "explore", "checkpoint_s": 10, "hold_s": 6},
		"motor": {"reaction_delay_ticks": 0, "mistake_rate": 0, "potion_hp_fraction": null, "potion_mp_fraction": null}})
	assert_eq(policy.tactic, "explore", "the round starts on the personality's default")
	for i in 60 * 21:
		_tick(w, policy)
	var asked := brain.of_kind("tactic")
	assert_eq(asked[0].options.map(func(o: Dictionary) -> String: return String(o.id)), ["explore", "kite"])
	assert_eq(String(asked[0].situation.tactic.current), "explore")
	assert_eq(asked.map(func(d: Dictionary) -> int: return int(d.tick)), [0, 600, 1200], "a checkpoint every 10 s")


func test_motor_params_reach_the_players_input() -> void:
	var w := RF.quiet_world(400.0, 62)
	var policy := POLICY.new(ScriptedBrain.new(), 62)
	policy.configure({"tactics": SENSIBLE.tactics, "motor": {"reaction_delay_ticks": 6, "mistake_rate": 2.0,
		"potion_hp_fraction": 0.3, "potion_mp_fraction": null}})
	for i in 60 * 20:
		_tick(w, policy)
	var s: Dictionary = policy.motor.summary()
	assert_true(int(s.bursts) > 0, "mistake bursts happened")
	assert_eq(s.params.reaction_delay_ticks, 6)
	assert_eq(s.params.potion_hp_fraction, 0.3)


func test_a_tactic_decide_shows_the_last_switches() -> void:
	var w := RF.quiet_world(400.0, 63)
	var brain := ScriptedBrain.new()
	var answers := ["explore", "collect", "kite", "hold", "kite"]
	brain.pick = func(d: Dictionary) -> String: return answers[mini(brain.of_kind("tactic").size() - 1, answers.size() - 1)]
	var policy := POLICY.new(brain, 63)
	for i in 60 * 33:
		_tick(w, policy)
	var last: Dictionary = brain.of_kind("tactic")[4]
	var recent: Array = last.situation.tactic.recent
	assert_eq(recent.map(func(r: Dictionary) -> String: return "%s>%s" % [r.from, r.to]),
		["explore>collect", "collect>kite", "kite>hold"], "the last three switches, oldest first")
	assert_true(recent[0].has("time") and recent[0].has("trigger"))


func test_card_options_carry_botinput_score_stat_and_role() -> void:
	var w := RF.quiet_world(400.0, 43)
	w.pending_bonus_choices = 1
	w.step(DT, MoveInput.new())
	assert_eq(w.state, RunWorld.CHOOSING_UPGRADE, "fixture: a card window is open")
	var brain := ScriptedBrain.new()
	POLICY.new(brain, 43).choose(w)
	var d: Dictionary = brain.of_kind("card")[0]
	for o: Dictionary in d.options:
		assert_true(o.has("sensible_score") and o.has("stat") and o.has("role"), "card %s is tagged" % o.id)
		assert_true(String(o.role) in ["attack", "support", "none"])
	var snails: Array = d.options.filter(func(o: Dictionary) -> bool: return String(o.get("skill", "")) == "three_snails")
	for o: Dictionary in snails:
		assert_eq(String(o.role), "attack", "Three Snails is an attack skill")
