extends TestCase
## Deterministic headless round chains through the public balance harness, without menu scenes or saves.
const BR := preload("res://tools/balance_run.gd")
const RF := preload("res://tests/fixtures/run_fixtures.gd")


func test_round_seeds_preserve_first_round_and_derive_later_rounds() -> void:
	assert_eq(BR.round_seed(2026, 0), 2026, "tier 1 retains the existing one-off round stream")
	assert_ne(BR.round_seed(2026, 1), BR.round_seed(1, 1))
	assert_ne(BR.round_seed(2026, 1), BR.round_seed(2026, 2))


func test_chain_replays_records_and_carries_every_character_field_after_clear() -> void:
	var data := RF.quiet_data()
	data.stages.stages.quiet.duration = 2.0
	data.stages.stages.quiet.keyframes = [{"t": 0, "rate": 10, "max_alive": 20, "pool": {"100100": 1}}]
	data.balance.run_time_cap = 3.0
	var setups := [RF.setup("quiet", 0, data), RF.setup("quiet", 0, data)]
	setups[0].character = DataRepo.load_json("res://tests/fixtures/characters/lv35_magician_2nd.json")
	var a: Dictionary = BR.run_chain(setups, "random", 2026)
	var b: Dictionary = BR.run_chain(setups, "random", 2026)
	assert_eq(JSON.stringify(a), JSON.stringify(b), "whole chain records reproduce byte for byte")
	assert_eq(a.rounds.size(), 2)
	assert_eq(a.rounds[0].state, "CLEARED")
	assert_eq(a.rounds[1].state, "CLEARED")
	assert_true(int(a.rounds[0].spawned) > 0, "replay includes seeded spawn and movement decisions")
	assert_eq(a.rounds[1].start_character, a.rounds[0].character, "only the real boundary snapshot is carried")
	assert_eq(a.rounds[0].seed, 2026)
	assert_eq(a.rounds[1].seed, BR.round_seed(2026, 1))
	assert_false(setups[1].has("character"), "reusing prepared setups cannot leak an earlier chain's character")
	assert_eq(a.rounds[1].start_character.level, 38)
	assert_eq(a.rounds[1].start_character.job_id, 210)


func test_timeout_does_not_feed_a_later_tier() -> void:
	var data := RF.quiet_data()
	data.balance.run_time_cap = 0.05
	var setup := RF.setup("quiet", 0, data)
	var record: Dictionary = BR.run_chain([setup, setup], "bot", 1)
	assert_eq(record.rounds.size(), 1)
	assert_eq(record.rounds[0].state, "TIMEOUT")
	assert_eq(record.rounds[0].character, {}, "a cap is never a cleared character")


func test_tier2_report_counts_only_started_rounds_and_exposes_small_feed_sample() -> void:
	var tier1 := {"tier": 1, "state": "CLEARED", "level": 38, "time": 950.0}
	var tier2 := {"tier": 2, "state": "DEAD", "level": 61, "time": 780.0,
		"start_character": {"level": 38}, "lv70_reached": false,
		"boss_fights": [{"mob_id": 8130100, "status": "not_spawned"}]}
	var failed := {"tier": 1, "state": "DEAD", "level": 10, "time": 320.0}
	var summary: Dictionary = BR.aggregate([
		{"mode": "chain", "target_tier": 2, "rounds": [tier1, tier2]},
		{"mode": "chain", "target_tier": 2, "rounds": [failed]}])
	assert_eq(summary.tier1_clears, 1)
	assert_eq(summary.tiers["2"].runs, 1, "tier-1 death is excluded from tier-2 denominator")
	assert_eq(summary.tiers["2"].outcomes.DEAD, 1)
	assert_eq(summary.tiers["2"].start_level.median, 38.0)
	assert_eq(summary.tiers["2"].end_level.median, 61.0)
	assert_eq(summary.tiers["2"].lv70_reached, 0)
	assert_eq(summary.tiers["2"].boss_fights["8130100"].not_spawned, 1)
	var text: String = BR.describe_metrics(summary)
	assert_true(text.contains("tier-1 clears feeding tier 2: 1/2"))
	assert_true(text.contains("SUMMARY tier 2: 1 started, 0 cleared"))
	assert_true(text.contains("Lv70 reached 0/1"))
	var empty: Dictionary = BR.aggregate([{"mode": "chain", "target_tier": 2, "rounds": [failed]}])
	assert_eq(empty.tiers["2"].runs, 0)
	assert_eq(empty.tiers["2"].start_level.count, 0)
	assert_true(BR.describe_metrics(empty).contains("SUMMARY tier 2: 0 started, 0 cleared"))
	var fixture_summary: Dictionary = BR.aggregate([tier2, {"tier": 2, "state": "TIMEOUT", "level": 70,
		"start_character": {"level": 38}, "lv70_reached": true}])
	assert_eq(fixture_summary.lv70_reached, 1)
	assert_true(BR.describe_metrics(fixture_summary).contains("Lv70 reached 1/2"))


func test_chain_cli_reads_tiers_and_replays_both_round_records() -> void:
	if not require_cache():
		return
	# Short, empty encounters exercise the real CLI/cache/clear boundary without a fifteen-minute combat test.
	var data := DataRepo.load_all()
	var stages := {}
	for tier: Array in data.stages.tiers:
		for stage: String in tier:
			stages[stage] = {"duration": 0.05, "bosses": []}
	var path := ProjectSettings.globalize_path(test_dir("chain patch.json"))
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"stages": {"stages": stages}}))
	file.close()
	var args := ["--tier=2", "--stage=tree_that_grew_1", "--seed=2026", "--cap=1", "--patch=" + path]
	var a := _cli(args)
	var b := _cli(args)
	assert_eq(a.status, 0)
	assert_eq(a.record, b.record)
	assert_eq(a.record.get("mode", ""), "chain")
	if a.record.get("mode", "") != "chain":
		return
	assert_eq(a.record.rounds.size(), 2)
	assert_eq(a.record.rounds[0].stage, "tree_that_grew_1")
	assert_eq(a.record.rounds[1].stage, "dark_cave")
	assert_eq(int(a.record.rounds[1].seed), BR.round_seed(2026, 1))
	assert_eq(a.record.rounds[1].start_character, a.record.rounds[0].character)
	for record: Dictionary in a.record.rounds:
		assert_eq(record.state, "CLEARED")
		assert_eq(record.warnings, [])
		assert_eq(record.missing, [])
	assert_eq(a.status, b.status)


func test_chain_cli_rejects_incompatible_or_invalid_options() -> void:
	for args: Array in [["--tier=0"], ["--tier=no"], ["--tier=3"], ["--tier=2", "--stage=dark_cave"],
			["--tier=2", "--character=anything.json"], ["--tier=2", "--policy=camper_henesys_top"]]:
		var result := _cli(args)
		assert_eq(result.status, 2, str(args))
		assert_eq(result.record, {}, "invalid configuration must not emit a usable record")


func _cli(args: Array) -> Dictionary:
	var output: Array = []
	var status := OS.execute(OS.get_executable_path(), ["--headless", "--path",
		ProjectSettings.globalize_path("res://"), "--script", "res://tools/balance_run.gd", "--", "--cap=0.1"] + args, output, true)
	var record := {}
	for line: String in "\n".join(output).split("\n"):
		if line.begins_with("BALANCE "):
			record = JSON.parse_string(line.substr(8))
	return {"status": status, "record": record}
