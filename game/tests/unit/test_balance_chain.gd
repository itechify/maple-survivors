extends TestCase
## Deterministic headless round chains through the public balance harness, without menu scenes or saves.
const BR := preload("res://tools/balance_run.gd")
const RF := preload("res://tests/fixtures/run_fixtures.gd")


func test_round_seeds_preserve_first_round_and_derive_later_rounds() -> void:
	assert_eq(BR.round_seed(2026, 0), 2026, "step 1 retains the existing one-off round stream")
	assert_ne(BR.round_seed(2026, 1), BR.round_seed(1, 1))
	assert_ne(BR.round_seed(2026, 1), BR.round_seed(2026, 2))
	assert_eq(BR.attempt_seed(2026, 3, 0), BR.round_seed(2026, 3), "a first attempt keeps the round seed")
	assert_ne(BR.attempt_seed(2026, 3, 1), BR.round_seed(2026, 3), "a replay draws its own stream")
	assert_ne(BR.attempt_seed(2026, 3, 1), BR.attempt_seed(2026, 3, 2))


func test_chain_replays_records_and_carries_every_character_field_after_clear() -> void:
	var data := RF.quiet_data()
	data.stages.stages.quiet.duration = 2.0
	data.stages.stages.quiet.keyframes = [{"t": 0, "rate": 10, "max_alive": 20, "pool": {"100100": 1}}]
	data.balance.run_time_cap = 3.0
	var setups := [RF.setup("quiet", 0, data), RF.setup("quiet", 0, data)]
	setups[0].character = DataRepo.load_json("res://tests/fixtures/characters/fp_arch_mage.json")
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
	assert_eq(a.rounds[1].start_character.job_id, 212)
	assert_eq(a.rounds[0].start_character.cleared_regions, ["ellinia", "henesys", "kerning", "perion"],
		"the fixture starts with the first four regions cleared (Sleepywood open)")
	assert_eq(a.rounds[1].start_character.cleared_regions, a.rounds[0].start_character.cleared_regions,
		"the synthetic stage is outside the progression: its clear adds no region")


## Two quiet rounds whose carried character is a Magician with 200,000 mesos and a spare wand (synthetic item info).
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
	character.job_id = 200
	character.mesos = 200000
	character.equipment.worn.weapon = Equipment.create(1372005, setups[0].equipment_info[1372005])
	character.equipment.inventory.append(Equipment.create(1372008, setups[0].equipment_info[1372008]))
	setups[0].character = character
	return setups


func test_the_chain_visits_the_shops_between_rounds_and_records_it() -> void:
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
	assert_false(a.rounds[1].has("shop"), "no visit after the last round")
	assert_eq(a.rounds[1].equipment_worn.weapon, 1372005)
	assert_true(a.rounds[0].has("equips_worn"))
	var summary: Dictionary = BR.aggregate([a])
	assert_eq(summary.steps["1"].shop.spent.median, 175000.0)
	assert_false(summary.steps["2"].has("shop"))
	assert_true(BR.describe(a).contains("shop: mesos"), "the readable record shows the visit")
	assert_true(BR.describe_metrics(summary).contains("shop spent per visit"))


func test_a_chain_without_a_clear_never_reaches_the_shop() -> void:
	var setups := _shopping_setups()
	setups[0].data.balance.run_time_cap = 0.05
	var record: Dictionary = BR.run_chain(setups, "random", 1)
	assert_eq(record.rounds.size(), 1)
	assert_false(record.rounds[0].has("shop"))


func test_timeout_does_not_feed_a_later_step() -> void:
	var data := RF.quiet_data()
	data.balance.run_time_cap = 0.05
	var setup := RF.setup("quiet", 0, data)
	var record: Dictionary = BR.run_chain([setup, setup], "bot", 1)
	assert_eq(record.rounds.size(), 1)
	assert_eq(record.rounds[0].state, "TIMEOUT")
	assert_eq(record.rounds[0].character, {}, "a cap is never a cleared character")


func test_chain_records_name_stage_step_and_attempt() -> void:
	var a: Dictionary = BR.run_chain(_shopping_setups(), "bot", 2026)
	assert_eq(a.mode, "chain")
	assert_eq(a.chain, 2)
	assert_eq(a.retries, 0)
	assert_eq(a.stages, ["quiet", "quiet"])
	assert_true(a.chain_cleared)
	for index in 2:
		assert_eq(a.rounds[index].stage, "quiet")
		assert_eq(a.rounds[index].step, index + 1)
		assert_eq(a.rounds[index].attempt, 1)
		assert_eq(a.rounds[index].state, "CLEARED")


## One quiet stage per step, the second one lethal (a mob that kills at once) and so never cleared.
func _lethal_setups(retries_loot: bool) -> Array:
	var data := RF.quiet_data()
	data.stages.stages.quiet.duration = 2.0
	data.stages.stages.quiet.keyframes = [{"t": 0, "rate": 10, "max_alive": 20, "pool": {"100100": 1}}]
	data.balance.run_time_cap = 3.0
	var first := RF.setup("quiet", 0, data)
	var second := RF.setup("quiet", 0, data)
	second.data = data.duplicate(true)
	second.data.balance.run_time_cap = 0.05 # the second step never clears: TIMEOUT
	if retries_loot:
		first.character = RunWorld.new(first).character_snapshot()
		first.character.mesos = 4321
	return [first, second]


func test_only_a_cleared_round_feeds_the_next_step_and_retries_stop_at_k() -> void:
	var none: Dictionary = BR.run_chain(_lethal_setups(false), "bot", 5)
	assert_eq(none.rounds.size(), 2, "step 1 clears, step 2 times out, and retries 0 ends the chain there")
	assert_eq(none.rounds[1].step, 2)
	assert_eq(none.rounds[1].state, "TIMEOUT")
	assert_false(none.chain_cleared)
	assert_eq(none.rounds[1].start_character, none.rounds[0].character, "only the CLEARED round was fed forward")
	var two: Dictionary = BR.run_chain(_lethal_setups(false), "bot", 5, -1.0, 60.0, 2)
	assert_eq(two.rounds.size(), 4, "step 1 once, then step 2 three times (the first try and K = 2 replays)")
	var steps: Array = two.rounds.map(func(r: Dictionary) -> int: return int(r.step))
	var attempts: Array = two.rounds.map(func(r: Dictionary) -> int: return int(r.attempt))
	assert_eq(steps, [1, 2, 2, 2])
	assert_eq(attempts, [1, 1, 2, 3])
	assert_eq(two.retries, 2)
	assert_false(two.chain_cleared)
	var seeds: Array = two.rounds.map(func(r: Dictionary) -> int: return int(r.seed))
	assert_eq(seeds, [BR.attempt_seed(5, 0, 0), BR.attempt_seed(5, 1, 0), BR.attempt_seed(5, 1, 1),
		BR.attempt_seed(5, 1, 2)])
	assert_eq(JSON.stringify(two), JSON.stringify(BR.run_chain(_lethal_setups(false), "bot", 5, -1.0, 60.0, 2)),
		"a chain with retries reproduces byte for byte")


func test_a_retry_replays_with_the_character_the_failed_round_returned() -> void:
	var setups := _lethal_setups(true)
	var record: Dictionary = BR.run_chain(setups, "bot", 9, -1.0, 60.0, 1)
	assert_eq(record.rounds.size(), 3)
	var failed: Dictionary = record.rounds[1]
	assert_eq(failed.state, "TIMEOUT")
	assert_eq(failed.character, {}, "a failed round reports no cleared character")
	assert_true(failed.has("shop"), "a replay passes through the Free Market like a clear does")
	var replay: Dictionary = record.rounds[2]
	assert_eq(replay.step, 2)
	assert_eq(replay.attempt, 2)
	assert_eq(replay.start_character.mesos, failed.shop.mesos_after, "the failed round's mesos and gear carry over")
	assert_true(int(replay.start_character.mesos) >= 4321, "nothing the character held was lost")
	assert_eq(replay.start_character.cleared_regions, record.rounds[0].character.cleared_regions,
		"a failed round adds no region")
	assert_false(record.rounds[2].has("shop"), "the last attempt has no visit")


func test_retries_are_unused_when_every_step_clears() -> void:
	var data := RF.quiet_data()
	data.stages.stages.quiet.duration = 2.0
	data.stages.stages.quiet.keyframes = [{"t": 0, "rate": 10, "max_alive": 20, "pool": {"100100": 1}}]
	data.balance.run_time_cap = 3.0
	var setups := [RF.setup("quiet", 0, data), RF.setup("quiet", 0, data), RF.setup("quiet", 0, data)]
	var record: Dictionary = BR.run_chain(setups, "bot", 3, -1.0, 60.0, 1)
	assert_eq(record.rounds.size(), 3, "every step clears at once: no replay is used")
	assert_true(record.chain_cleared)
	var steps: Array = record.rounds.map(func(r: Dictionary) -> int: return int(r.step))
	assert_eq(steps, [1, 2, 3])


func test_chain_report_groups_by_step_with_attempts_per_clear() -> void:
	var cleared_1 := {"step": 1, "attempt": 1, "stage": "henesys", "state": "CLEARED", "level": 38, "time": 950.0}
	var died_2 := {"step": 2, "attempt": 1, "stage": "ellinia", "state": "DEAD", "level": 30, "time": 600.0}
	var cleared_2 := {"step": 2, "attempt": 2, "stage": "ellinia", "state": "CLEARED", "level": 41, "time": 990.0}
	var died_3 := {"step": 3, "attempt": 1, "stage": "perion", "state": "DEAD", "level": 61, "time": 780.0,
		"start_character": {"format": 3}, "lv70_reached": false,
		"boss_fights": [{"mob_id": 8130100, "status": "not_spawned"}]}
	var stages := ["henesys", "ellinia", "perion"]
	var failed := {"step": 1, "attempt": 1, "stage": "henesys", "state": "DEAD", "level": 10, "time": 320.0}
	var summary: Dictionary = BR.aggregate([
		{"mode": "chain", "chain": 3, "retries": 1, "stages": stages, "rounds": [cleared_1, died_2, cleared_2, died_3]},
		{"mode": "chain", "chain": 3, "retries": 1, "stages": stages, "rounds": [failed]}])
	assert_eq(summary.chain, 3)
	assert_eq(summary.chain_clears, 0)
	assert_eq(summary.steps["1"].runs, 2)
	assert_eq(summary.steps["1"].clears, 1)
	assert_eq(summary.steps["1"].attempts_per_clear, 2.0)
	assert_eq(summary.steps["2"].runs, 2, "two attempts of one chain; the chain that died at step 1 never reached it")
	assert_eq(summary.steps["2"].runs_reached, 1)
	assert_eq(summary.steps["2"].runs_cleared, 1)
	assert_eq(summary.steps["2"].attempts_per_clear, 2.0)
	assert_eq(summary.steps["2"].death_seconds.median, 600.0)
	assert_eq(summary.steps["2"].stage, "ellinia")
	assert_eq(summary.steps["3"].runs, 1)
	assert_eq(summary.steps["3"].clears, 0)
	assert_eq(summary.steps["3"].attempts_per_clear, null)
	assert_eq(summary.steps["3"].boss_fights["8130100"].not_spawned, 1)
	assert_false(summary.steps["3"].has("start_level"), "every round starts at Lv1 (ADR 0006): no start level to report")
	assert_eq(summary.steps["3"].end_level.median, 61.0)
	var text: String = BR.describe_metrics(summary)
	assert_true(text.contains("SUMMARY chain of 3 steps (retries 1): 0/2 runs cleared every step"))
	assert_true(text.contains("SUMMARY step 2 (ellinia): 2 started, 1 cleared"))
	assert_true(text.contains("attempts per clear 2.00; chains reaching the step 1, clearing it 1"))
	assert_true(text.contains("attempts per clear none"))
	var whole: Dictionary = BR.aggregate([{"mode": "chain", "chain": 1, "retries": 0, "stages": ["henesys"],
		"rounds": [cleared_1]}])
	assert_eq(whole.chain_clears, 1)
	var fixture_summary: Dictionary = BR.aggregate([died_3, {"step": 3, "state": "TIMEOUT", "level": 70,
		"start_character": {"format": 3}, "lv70_reached": true}])
	assert_eq(fixture_summary.lv70_reached, 1)
	assert_true(BR.describe_metrics(fixture_summary).contains("Lv70 reached 1/2"))


func test_chain_cli_follows_the_progression_and_replays_round_records() -> void:
	if not require_cache():
		return
	# Short, empty encounters exercise the real CLI/cache/clear boundary without a fifteen-minute combat test.
	var data := DataRepo.load_all()
	var path := _short_patch(data)
	var args := ["--chain=3", "--stage=ellinia", "--seed=2026", "--cap=1", "--patch=" + path]
	var a := _cli(args)
	var legacy_args := args.duplicate()
	legacy_args[1] = "--stage=tree_that_grew_1"
	var b := _cli(legacy_args)
	assert_eq(a.status, 0)
	assert_eq(a.record, b.record)
	assert_eq(a.record.get("mode", ""), "chain")
	if a.record.get("mode", "") != "chain":
		return
	var expected: Array = data.stages.progression.slice(1, 4)
	assert_eq(a.record.stages, expected, "the chain starts at --stage and follows the progression order")
	assert_eq(a.record.rounds.size(), 3)
	for index in 3:
		var record: Dictionary = a.record.rounds[index]
		assert_eq(record.stage, expected[index])
		assert_eq(int(record.step), index + 1)
		assert_eq(int(record.attempt), 1)
		assert_eq(int(record.seed), BR.round_seed(2026, index))
		assert_eq(record.state, "CLEARED")
		assert_eq(record.warnings, [])
		assert_eq(record.missing, [])
		assert_eq(record.get("map_times", []), [0.0])
		assert_eq(int(record.get("ended_map", {}).get("index", -1)), 0)
		assert_eq(int(record.get("ended_map", {}).get("id", 0)),
			int(data.stages.stages[record.stage].maps[0].map_id))
		if index > 0:
			assert_eq(record.start_character, a.record.rounds[index - 1].character)
	assert_eq(a.record.rounds[2].character.cleared_regions, ["ellinia", "kerning", "perion"],
		"each clear adds its region to the carried character")
	assert_true(a.record.chain_cleared)
	assert_eq(a.status, b.status)


func test_chain_cli_defaults_to_the_first_region_and_accepts_retries() -> void:
	if not require_cache():
		return
	var data := DataRepo.load_all()
	var a := _cli(["--chain=2", "--retries=1", "--seed=7", "--patch=" + _short_patch(data)])
	assert_eq(a.status, 0)
	assert_eq(a.record.get("stages", []), data.stages.progression.slice(0, 2))
	assert_eq(int(a.record.get("retries", -1)), 1)
	assert_eq(a.record.get("rounds", []).size(), 2, "both regions clear first time: no replay is used")


func _short_patch(data: Dictionary) -> String:
	var stages := {}
	for stage: String in data.stages.progression:
		stages[stage] = {"duration": 0.05, "maps": [{"map_id": data.stages.stages[stage].maps[0].map_id, "boss": {}}]}
	var path := ProjectSettings.globalize_path(test_dir("chain patch.json"))
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"stages": {"stages": stages}}))
	file.close()
	return path


func test_character_cli_accepts_new_and_legacy_stage_keys_with_map_records() -> void:
	if not require_cache():
		return
	var character := ProjectSettings.globalize_path("res://tests/fixtures/characters/fp_arch_mage.json")
	var a := _cli(["--stage=sleepywood", "--seed=1", "--cap=0.05", "--character=" + character])
	var b := _cli(["--stage=dark_cave", "--seed=1", "--cap=0.05", "--character=" + character])
	assert_eq(a.status, 0)
	assert_eq(b.status, 0)
	assert_eq(a.record, b.record, "legacy one-off flags produce the same canonical record")
	assert_eq(a.record.get("stage", ""), "sleepywood")
	assert_eq(a.record.get("map_times", []), [0.0])
	assert_eq(a.record.get("ended_map", {}), {"index": 0.0, "id": 105050400.0})


func test_chain_cli_rejects_incompatible_or_invalid_options() -> void:
	var progression: Array = DataRepo.load_all().stages.progression
	var size: int = progression.size()
	for args: Array in [["--chain=0"], ["--chain=no"], ["--chain=%d" % (size + 1)], ["--chain=2", "--stage=%s" % progression[-1]],
			["--chain=%d" % size, "--stage=ellinia"],
			["--chain=2", "--policy=camper_henesys_top"], ["--chain=2", "--retries=-1"], ["--chain=2", "--retries=x"],
			["--retries=1"], ["--tier=2"], ["--tier=2", "--chain=2"]]:
		var result := _cli(args)
		assert_eq(result.status, 2, str(args))
		assert_eq(result.record, {}, "invalid configuration must not emit a usable record")


func test_chain_cli_starts_from_a_character_file() -> void:
	if not require_cache():
		return
	var character := ProjectSettings.globalize_path("res://tests/fixtures/characters/fp_arch_mage.json")
	var result := _cli(["--stage=sleepywood", "--chain=1", "--seed=1", "--cap=0.05", "--character=" + character])
	assert_eq(result.status, 0, str(result.output))
	var round: Dictionary = result.record.rounds[0]
	assert_eq(int(round.start_character.equipment.worn.weapon.id), 1382002, "the chain's first round starts from the file's staff")
	assert_eq(round.stage, "sleepywood")
	var bare := _cli(["--stage=sleepywood", "--chain=1", "--seed=1", "--cap=0.05"])
	assert_ne(int(bare.record.rounds[0].start_character.equipment.worn.weapon.id), 1382002, "without the file a fresh character")


func test_the_tier_flag_fails_and_names_chain() -> void:
	var result := _cli(["--tier=2"])
	assert_eq(result.status, 2)
	assert_true(String(result.output).contains("--chain"), "the message names --chain")


func _cli(args: Array) -> Dictionary:
	var output: Array = []
	var status := OS.execute(OS.get_executable_path(), ["--headless", "--path",
		ProjectSettings.globalize_path("res://"), "--script", "res://tools/balance_run.gd", "--", "--cap=0.1"] + args, output, true)
	var record := {}
	for line: String in "\n".join(output).split("\n"):
		if line.begins_with("BALANCE "):
			record = JSON.parse_string(line.substr(8))
	return {"status": status, "record": record, "output": "\n".join(output)}
