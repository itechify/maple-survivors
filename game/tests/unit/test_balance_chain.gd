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


## Two quiet rounds whose carried character is a Lv 10 Magician with 200,000 mesos and a spare wand (synthetic item info).
func _shopping_setups() -> Array:
	var data := RF.quiet_data()
	data.stages.stages.quiet.duration = 2.0
	data.stages.stages.quiet.keyframes = [{"t": 0, "rate": 10, "max_alive": 20, "pool": {"100100": 1}}]
	data.balance.run_time_cap = 3.0
	var setups := []
	for i in 2:
		var setup := RF.setup("quiet", 0, data)
		setup.equipment_info = {
			1040002: {"incPDD": 3, "tuc": 7, "price": 50}, 1060002: {"incPDD": 2, "tuc": 7, "price": 40},
			1072001: {"incPDD": 2, "tuc": 5, "price": 30}, 1302000: {"incPAD": 17, "tuc": 7, "price": 100},
			1372005: {"reqJob": 2, "reqLevel": 8, "incPAD": 15, "incMAD": 23, "tuc": 7, "price": 1000},
			1372008: {"reqJob": 2, "reqLevel": 8, "incMAD": 10, "tuc": 7, "price": 700}}
		setup.scroll_info = {2043700: {"incMAD": 1, "success": 100, "price": 1},
			2043701: {"incMAD": 2, "incINT": 1, "success": 60, "price": 1},
			2040400: {"incPDD": 1, "success": 100, "price": 1}, 2040600: {"incPDD": 1, "success": 100, "price": 1},
			2040700: {"incDEX": 1, "success": 100, "price": 1}}
		setups.append(setup)
	var character := RunWorld.new(setups[0]).character_snapshot()
	character.level = 10
	character.job_id = 200
	character.mesos = 200000
	character.equipment.worn.weapon = Equipment.create(1372005, setups[0].equipment_info[1372005])
	character.equipment.inventory.append(Equipment.create(1372008, setups[0].equipment_info[1372008]))
	setups[0].character = character
	return setups


func test_the_chain_visits_the_shops_between_tiers_and_records_it() -> void:
	var a: Dictionary = BR.run_chain(_shopping_setups(), "bot", 2026)
	var b: Dictionary = BR.run_chain(_shopping_setups(), "bot", 2026)
	assert_eq(JSON.stringify(a), JSON.stringify(b), "same seed, same purchases and scroll results")
	assert_eq(a.rounds.size(), 2)
	var shop: Dictionary = a.rounds[0].shop
	assert_eq(shop.sold, 1, "the worse wand is sold")
	assert_true(int(shop.mesos_before) >= 200000, "the carried mesos plus what the round picked up")
	assert_eq(shop.bought, 3, "200,700: two 70,000 wand scrolls and one 35,000 armour scroll")
	assert_eq(shop.used, 3)
	assert_eq(shop.succeeded + shop.failed, 3)
	assert_eq(shop.spent, 175000)
	var carried: Dictionary = a.rounds[1].start_character
	assert_eq(carried.mesos, shop.mesos_after)
	assert_eq(carried.equipment.worn.weapon.slots, 5, "two upgrade slots of the wand were used")
	assert_eq(carried.equipment.inventory, [], "the spare wand was sold")
	assert_false(a.rounds[1].has("shop"), "no visit after the last tier")
	assert_eq(a.rounds[1].equipment_worn.weapon, 1372005)
	assert_true(a.rounds[0].has("equips_worn"))
	var summary: Dictionary = BR.aggregate([a])
	assert_eq(summary.tiers["1"].shop.spent.median, 175000.0)
	assert_false(summary.tiers["2"].has("shop"))
	assert_true(BR.describe(a).contains("shop: mesos"), "the readable record shows the visit")
	assert_true(BR.describe_metrics(summary).contains("shop spent per visit"))


func test_a_chain_without_a_clear_never_reaches_the_shop() -> void:
	var setups := _shopping_setups()
	setups[0].data.balance.run_time_cap = 0.05
	var record: Dictionary = BR.run_chain(setups, "random", 1)
	assert_eq(record.rounds.size(), 1)
	assert_false(record.rounds[0].has("shop"))


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
			stages[stage] = {"duration": 0.05, "maps": [{"map_id": data.stages.stages[stage].maps[0].map_id, "boss": {}}]}
	var path := ProjectSettings.globalize_path(test_dir("chain patch.json"))
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"stages": {"stages": stages}}))
	file.close()
	var args := ["--tier=2", "--stage=ellinia", "--seed=2026", "--cap=1", "--patch=" + path]
	var a := _cli(args)
	var legacy_args := args.duplicate()
	legacy_args[1] = "--stage=tree_that_grew_1"
	var b := _cli(legacy_args)
	assert_eq(a.status, 0)
	assert_eq(a.record, b.record)
	assert_eq(a.record.get("mode", ""), "chain")
	if a.record.get("mode", "") != "chain":
		return
	assert_eq(a.record.rounds.size(), 2)
	assert_eq(a.record.rounds[0].stage, "ellinia")
	assert_eq(a.record.rounds[1].stage, "sleepywood")
	assert_eq(int(a.record.rounds[1].seed), BR.round_seed(2026, 1))
	assert_eq(a.record.rounds[1].start_character, a.record.rounds[0].character)
	for record: Dictionary in a.record.rounds:
		assert_eq(record.state, "CLEARED")
		assert_eq(record.warnings, [])
		assert_eq(record.missing, [])
		assert_eq(record.get("map_times", []), [0.0])
		assert_eq(int(record.get("ended_map", {}).get("index", -1)), 0)
		assert_eq(int(record.get("ended_map", {}).get("id", 0)),
			int(data.stages.stages[record.stage].maps[0].map_id))
	assert_eq(a.status, b.status)


func test_character_cli_accepts_new_and_legacy_stage_keys_with_map_records() -> void:
	if not require_cache():
		return
	var character := ProjectSettings.globalize_path("res://tests/fixtures/characters/lv35_magician_2nd.json")
	var a := _cli(["--stage=sleepywood", "--seed=1", "--cap=0.05", "--character=" + character])
	var b := _cli(["--stage=dark_cave", "--seed=1", "--cap=0.05", "--character=" + character])
	assert_eq(a.status, 0)
	assert_eq(b.status, 0)
	assert_eq(a.record, b.record, "legacy one-off flags produce the same canonical record")
	assert_eq(a.record.get("stage", ""), "sleepywood")
	assert_eq(a.record.get("map_times", []), [0.0])
	assert_eq(a.record.get("ended_map", {}), {"index": 0.0, "id": 105050400.0})


func test_chain_cli_rejects_incompatible_or_invalid_options() -> void:
	for args: Array in [["--tier=0"], ["--tier=no"], ["--tier=3"], ["--tier=2", "--stage=sleepywood"],
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
