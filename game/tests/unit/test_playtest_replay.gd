extends TestCase
## Replay fingerprints and tier chains of the agent playtest driver (spec #91, ticket #98), on synthetic worlds with
## seeded RNG and fixed dt: the fingerprint carries the job and a hash of the per-second timeline sampled on the
## timeline's own cadence, reproduces for a seed and changes with it; a tier chain continues decision ids across
## rounds, keeps per-round records and sums ticks, and tags its timeline rows with the tier.
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const BR := preload("res://tools/balance_run.gd")
const POLICY := preload("res://tools/playtest/playtest_policy.gd")
const BRAIN_LINK := preload("res://tools/playtest/brain_link.gd")
const TIMELINE := preload("res://tools/playtest/playtest_timeline.gd")
const FINGERPRINT := preload("res://tools/playtest/playtest_fingerprint.gd")
const CHAIN := preload("res://tools/playtest/playtest_chain.gd")


## One builtin-brain round of a quiet synthetic world: {fingerprint, samples, rows}.
func _round(seed_value: int, cap := 20.0) -> Dictionary:
	var data := RF.quiet_data()
	data.balance.run_time_cap = cap
	data.stages.stages.quiet.keyframes = [{"t": 0, "rate": 3, "max_alive": 6, "pool": {"100100": 1}}]
	var setup := RF.setup("quiet", seed_value, data)
	var w := RunWorld.new(setup)
	var policy := POLICY.new(BRAIN_LINK.new(), seed_value)
	var fp := FINGERPRINT.new()
	var timeline := TIMELINE.new(policy)
	policy.observers.append(fp.observe)
	policy.observers.append(timeline.observe)
	var record := BR.run_one(w, policy, seed_value, -1.0, 60.0, 0, policy.observe)
	return {"fingerprint": FINGERPRINT.of_round(policy, w, record, fp), "samples": fp.samples, "rows": timeline.rows}


func test_fingerprint_carries_job_and_a_timeline_hash_and_reproduces_for_a_seed() -> void:
	var a := _round(11)
	var b := _round(11)
	var fp: Dictionary = a.fingerprint
	for k: String in ["ticks", "state", "time", "level", "job", "kills", "cards_taken", "answers_sha256", "timeline_sha256"]:
		assert_true(fp.has(k), "fingerprint field " + k)
	assert_eq(String(fp.timeline_sha256).length(), 64, "a sha256 hex digest")
	assert_eq(int(fp.ticks), 1200, "20 s at 60 ticks per second")
	assert_eq(JSON.stringify(a.fingerprint), JSON.stringify(b.fingerprint), "same seed, same fingerprint")
	var c := _round(12)
	assert_ne(String(c.fingerprint.timeline_sha256), String(fp.timeline_sha256), "another seed moves the player differently")


func test_the_timeline_hash_samples_exactly_the_timeline_rows() -> void:
	var r := _round(11)
	assert_eq(int(r.samples), int(r.rows), "one hashed sample per timeline.jsonl row")
	assert_eq(int(r.samples), 20)


func _chain_setups() -> Array:
	var data := RF.quiet_data()
	data.stages.stages.quiet.duration = 2.0
	data.stages.stages.quiet.keyframes = [{"t": 0, "rate": 10, "max_alive": 20, "pool": {"100100": 1}}]
	data.balance.run_time_cap = 3.0
	var setups := [RF.setup("quiet", 0, data), RF.setup("quiet", 0, data)]
	setups[0].character = DataRepo.load_json("res://tests/fixtures/characters/lv35_magician_2nd.json")
	return setups


func test_a_chain_continues_decision_ids_across_rounds_and_keeps_round_records() -> void:
	var rows: Array = []
	var chain := CHAIN.new(BRAIN_LINK.new(), {}, Callable(), func(line: String) -> void: rows.append(line))
	var configured: Array = []
	chain.policy_setup = func(p: Object) -> void: configured.append(p)
	var result := chain.play(_chain_setups(), 2026)
	assert_eq(configured.size(), 2, "the policy setup hook runs once per round")
	var record: Dictionary = result.record
	assert_eq(record.rounds.size(), 2, "a CLEARED tier 1 feeds tier 2")
	assert_eq(String(record.policy), "playtest")
	var ids: Array = result.decisions.map(func(d: Dictionary) -> int: return int(d.id))
	var expected: Array = range(1, ids.size() + 1)
	assert_eq(ids, expected, "decision ids run 1, 2, 3... over both rounds")
	assert_true(chain.policies[1].decisions.size() > 0, "the second round asked decisions too")
	assert_eq(int(chain.policies[1].decisions[0].id), chain.policies[0].decisions.size() + 1)
	assert_eq(String(record.state), String(record.rounds[1].state), "the outcome is the last round's")
	assert_eq(int(record.level), int(record.rounds[1].level))
	assert_eq(record.cards_taken.size(), record.rounds[0].cards_taken.size() + record.rounds[1].cards_taken.size())
	assert_true(record.rounds[0].has("tactics") and record.rounds[1].has("tactics"), "tactic telemetry per round")
	assert_true(record.has("tactics"), "and combined for the report")
	var fp: Dictionary = result.fingerprint
	assert_eq(fp.rounds.size(), 2)
	assert_eq(int(fp.ticks), int(fp.rounds[0].ticks) + int(fp.rounds[1].ticks), "ticks sum over the rounds")
	assert_eq(String(fp.timeline_sha256).length(), 64)
	var again := CHAIN.new(BRAIN_LINK.new()).play(_chain_setups(), 2026)
	assert_eq(JSON.stringify(again.fingerprint), JSON.stringify(fp), "a chain reproduces")
	assert_true(rows.size() >= 2)
	assert_eq(int(JSON.parse_string(rows[0]).tier), 1)
	assert_eq(int(JSON.parse_string(rows[rows.size() - 1]).tier), 2, "timeline rows carry their tier")
	assert_true(String(rows[0]).contains("\"hp\":"), "rows keep the timeline's integer fields")


## #99: a chain's hits.jsonl lines carry their round's tier, like its timeline rows.
func test_chain_hit_lines_carry_their_tier() -> void:
	var hits: Array = []
	var chain := CHAIN.new(BRAIN_LINK.new())
	chain.write_hits = func(line: String) -> void: hits.append(line)
	chain.play(_chain_setups(), 2026)
	hits.clear()
	var w := RunWorld.new(_chain_setups()[1])
	chain.timelines[1].observe(w, [{"type": "player_hit", "damage": 5, "miss": false, "max_hp": 50, "source_kind": "touch",
		"boss": false, "mob_id": 100100}])
	assert_eq(hits.size(), 1)
	var hit: Dictionary = JSON.parse_string(hits[0])
	assert_eq(int(hit.tier), 2)
	assert_eq(String(hit.source), "touch")
