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


## #99: rows also carry the kill count, EXP drops on the map, drops above the player and the HP potion stock, which
## the minute-pacing and movement evaluations bucket in the CLI.
func test_rows_carry_kills_drops_and_potions() -> void:
	var data := RF.quiet_data()
	data.stages.stages.quiet.keyframes = [{"t": 0, "rate": 10, "max_alive": 20, "pool": {"100100": 1}}]
	data.balance.run_time_cap = 3.0
	var lines: PackedStringArray = []
	var policy := POLICY.new()
	var timeline := TIMELINE.new(policy, func(line: String) -> void: lines.append(line))
	policy.observers.append(timeline.observe)
	var w := RunWorld.new(RF.setup("quiet", 9, data))
	BR.run_one(w, policy, 9, -1.0, 60.0, 0, policy.observe)
	var last: Dictionary = JSON.parse_string(lines[lines.size() - 1])
	for key: String in ["kills", "drops", "drops_above", "potions_hp"]:
		assert_has(last, key, "row has " + key)
	assert_eq(int(last.kills), w.kills)
	assert_eq(int(last.drops), w.pickups.exp_count())
	assert_eq(int(last.potions_hp), int(w.potions.stock.hp.count))


## #99: every hit that lands (not a miss) becomes one hits.jsonl line as it happens, with its source kind, boss flag
## and whole-hit fraction of the HP pool, so the death-fairness facts see the hits of the round's last partial second.
func test_hits_writer_gets_one_line_per_landed_hit() -> void:
	var data := RF.quiet_data()
	data.balance.run_time_cap = 1.0
	var w := RunWorld.new(RF.setup("quiet", 9, data))
	var hits: PackedStringArray = []
	var timeline := TIMELINE.new(null, Callable(), func(line: String) -> void: hits.append(line))
	w.step(1.0 / 60.0, MoveInput.new())
	timeline.observe(w, [
		{"type": "player_hit", "damage": 30, "miss": false, "boss": true, "mob_id": 2220000, "max_hp": 120,
			"source_kind": "touch"},
		{"type": "player_hit", "damage": 0, "miss": true, "boss": false, "mob_id": 100100, "max_hp": 120,
			"source_kind": "touch"},
		{"type": "level_up", "level": 2}])
	assert_eq(hits.size(), 1, "the miss and other events write nothing")
	assert_eq(timeline.rows, 0, "hits never count as timeline rows (the fingerprint samples rows)")
	var hit: Dictionary = JSON.parse_string(hits[0])
	assert_eq(int(hit.damage), 30)
	assert_eq(int(hit.max_hp), 120)
	assert_near(float(hit.fraction), 0.25, 0.001)
	assert_eq(String(hit.source), "touch")
	assert_true(bool(hit.boss))
	assert_eq(int(hit.mob_id), 2220000)
	assert_eq(int(hit.tick), 1)
