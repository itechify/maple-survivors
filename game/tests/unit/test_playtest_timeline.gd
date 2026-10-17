extends TestCase
## The agent playtest's per-second telemetry (game/tools/playtest/playtest_timeline.gd, spec #91, ticket #96): one
## timeline.jsonl row per run second with HP / MP / level / EXP, mobs alive and near, bosses, position, platform,
## tactic and state. Synthetic world, seeded, fixed dt.
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const BR := preload("res://tools/balance_run.gd")
const POLICY := preload("res://tools/playtest/playtest_policy.gd")
const TIMELINE := preload("res://tools/playtest/playtest_timeline.gd")


func test_one_row_per_run_second_through_the_run_loop() -> void:
	var data := RF.quiet_data()
	data.stages.stages.quiet.keyframes = [{"t": 0, "rate": 10, "max_alive": 20, "pool": {"100100": 1}}]
	data.balance.run_time_cap = 5.0
	var lines: PackedStringArray = []
	var policy := POLICY.new()
	var timeline := TIMELINE.new(policy, func(line: String) -> void: lines.append(line))
	policy.observers.append(timeline.observe)
	var w := RunWorld.new(RF.setup("quiet", 9, data))
	BR.run_one(w, policy, 9, -1.0, 60.0, 0, policy.observe)
	assert_eq(lines.size(), 5, "5 s of run time, one row each")
	var rows: Array = Array(lines).map(func(l: String) -> Dictionary: return JSON.parse_string(l))
	assert_eq(rows.map(func(r: Dictionary) -> int: return int(r.tick)), [60, 120, 180, 240, 300])
	assert_eq(rows.map(func(r: Dictionary) -> float: return float(r.time)), [1.0, 2.0, 3.0, 4.0, 5.0])
	var last: Dictionary = rows[4]
	for key: String in ["hp", "max_hp", "mp", "max_mp", "level", "exp", "alive", "near", "bosses", "x", "y", "platform",
			"tactic", "state"]:
		assert_has(last, key, "row has " + key)
	assert_eq(int(last.alive), w.swarm.alive_count(), "mobs alive at the last second")
	assert_true(int(last.alive) > 0, "fixture: the stage spawned mobs")
	assert_eq(String(last.tactic), "kite")
	assert_eq(String(last.state), "PLAYING")
	assert_near(float(last.x), w.player.pos.x, 0.1)
