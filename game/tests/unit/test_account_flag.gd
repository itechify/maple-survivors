extends TestCase
## The tool account file (--account=<abs JSON>) and how it reaches the round setup in single rounds, tier chains and
## --run (spec #34, ticket #116). An omitted flag is an empty account and changes nothing.

const BR := preload("res://tools/balance_run.gd")
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const ACCOUNT := {"owned": [1000001, 1070001, 5000001, 1812002], "cash": {"hat": 1000001, "shoes": 1070001},
	"pet": 5000001, "alert": {"hp": 0.5, "mp": 0.25}, "nx": 99999}


func _write(name: String, value: Variant) -> String:
	var path := ProjectSettings.globalize_path(test_dir(name))
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(value))
	file.close()
	return path


func test_validation_accepts_the_documented_shape_and_rejects_bad_files() -> void:
	assert_eq(AccountFile.validation_error(ACCOUNT), "")
	assert_eq(AccountFile.validation_error({}), "", "an empty account file is an empty account")
	assert_eq(AccountFile.validation_error({"alert": {"hp": 0.3, "mp": 7}}), "", "an old MP ALERT is tolerated, not checked")
	assert_eq(AccountFile.validation_error(JSON.parse_string(JSON.stringify(ACCOUNT))), "", "JSON floats")
	for bad: Variant in [[], "x", {"owned": 5}, {"owned": ["a"]}, {"owned": [0]}, {"owned": [1.5]},
			{"cash": {"hat": "x"}}, {"cash": {"crown": 1000001}}, {"pet": -1}, {"pet": "x"},
			{"alert": 5}, {"alert": {"hp": 2.0}}, {"alert": {"hp": -0.1}}, {"alert": {"hp": "x"}}]:
		assert_ne(AccountFile.validation_error(bad), "", "rejects %s" % [bad])


func test_load_reports_missing_and_invalid_files() -> void:
	var errors := PackedStringArray()
	assert_eq(AccountFile.load_file("", errors), {})
	assert_eq(errors.size(), 1)
	errors.clear()
	assert_eq(AccountFile.load_file(_write("bad account.json", {"owned": "no"}), errors), {})
	assert_eq(errors.size(), 1)
	assert_true(errors[0].contains("bad account.json"))
	errors.clear()
	var loaded := AccountFile.load_file(_write("good account.json", ACCOUNT), errors)
	assert_eq(errors, PackedStringArray())
	assert_eq(loaded.owned, [1000001, 1070001, 5000001, 1812002])
	assert_eq(loaded.cash, {"hat": 1000001, "shoes": 1070001})
	assert_eq(loaded.pet, 5000001)
	assert_eq(loaded.alert, {"hp": 0.5}, "an old file's MP ALERT is read and dropped (no MP, ADR 0006)")
	assert_false(loaded.has("nx"), "nx is ignored: tool rounds never credit NX")


func test_apply_puts_account_alert_and_worn_items_on_the_round_setup() -> void:
	var data := RF.quiet_data()
	var setup := RF.setup("quiet", 5, data)
	AccountFile.apply(setup, AccountFile.normalized(ACCOUNT))
	assert_eq(setup.account, {"owned": [1000001, 1070001, 5000001, 1812002]})
	assert_eq(setup.alert, {"hp": 0.5})
	assert_eq(setup.character.cash, {"hat": 1000001, "shoes": 1070001}, "a fresh character wears the account's items")
	assert_eq(setup.character.pet, 5000001)
	var w := RunWorld.new(setup)
	assert_eq(w.player_state.fortune, 19.0, "hat 10 + shoes 9")
	assert_eq(w.pet, 5000001)
	assert_eq(w.alert, {"hp": 0.5})
	assert_eq(w.warnings.size(), 0)
	var other := RF.setup("quiet", 5, data)
	assert_false(other.has("character"), "applying to one setup leaves other setups alone")


func test_apply_overrides_a_carried_characters_cash_only_when_the_file_names_it() -> void:
	var data := RF.quiet_data()
	var carried := RunWorld.new(RF.setup("quiet", 1, data)).character_snapshot()
	carried.cash = {"face": 1010001}
	carried.level = 12
	var setup := RF.setup("quiet", 1, data)
	setup.character = carried
	AccountFile.apply(setup, AccountFile.normalized({"owned": [1010001, 1000001]}))
	assert_eq(setup.character.cash, {"face": 1010001}, "no cash key in the file: the character keeps its own")
	AccountFile.apply(setup, AccountFile.normalized({"owned": [1000001], "cash": {"hat": 1000001}}))
	assert_eq(setup.character.cash, {"hat": 1000001}, "a cash key replaces the worn items")
	assert_eq(int(setup.character.level), 12, "and nothing else about the character changes")
	AccountFile.apply(setup, AccountFile.normalized({"cash": {}}))
	assert_false(setup.character.has("cash"), "an empty cash object takes everything off")
	assert_eq(setup.account, {"owned": []})


func test_balance_run_applies_the_account_to_every_prepared_setup() -> void:
	var data := RF.quiet_data()
	var setups := [RF.setup("quiet", 0, data), RF.setup("quiet", 0, data)]
	BR.apply_account(setups, AccountFile.normalized(ACCOUNT))
	for setup: Dictionary in setups:
		assert_eq(setup.account.owned, [1000001, 1070001, 5000001, 1812002])
		assert_eq(setup.alert, {"hp": 0.5})
	assert_eq(setups[0].character.cash, {"hat": 1000001, "shoes": 1070001})
	assert_false(setups[1].has("character"), "later tiers get the character carried from the clear")
	data.stages.stages.quiet.duration = 1.0
	data.balance.run_time_cap = 3.0
	var chain: Dictionary = BR.run_chain(setups, "bot", 7)
	assert_eq(chain.rounds.size(), 2)
	assert_eq(chain.rounds[0].start_character.cash, {"hat": 1000001, "shoes": 1070001})
	assert_eq(chain.rounds[1].start_character.cash, {"hat": 1000001, "shoes": 1070001}, "carried through the tier")
	assert_eq(chain.rounds[1].start_character.pet, 5000001)
	for round_record: Dictionary in chain.rounds:
		assert_eq(round_record.warnings, [], "owned items raise no warning in any tier")


func test_cli_single_round_chain_and_errors() -> void:
	if not require_cache():
		return
	var path := _write("tool account.json", ACCOUNT)
	var single := _cli(["--stage=henesys", "--seed=2", "--account=" + path])
	assert_eq(single.status, 0)
	assert_eq(single.record.get("account", ""), "tool account.json", "the record names the account file")
	assert_eq(CharacterSnapshot.integers(single.record.start_character.cash), {"hat": 1000001, "shoes": 1070001})
	assert_eq(single.record.start_character.pet, 5000001)
	assert_eq(single.record.warnings, [])
	var plain := _cli(["--stage=henesys", "--seed=2"])
	assert_false(plain.record.has("account"), "no flag, no account key")
	assert_false(plain.record.start_character.has("cash"))
	var unowned := _write("unowned account.json", {"owned": [], "cash": {"hat": 1000001}})
	var warned := _cli(["--stage=henesys", "--seed=2", "--account=" + unowned])
	assert_eq(warned.record.warnings.size(), 1)
	assert_true(String(warned.record.warnings[0]).contains("not owned"))
	var missing := _cli(["--stage=henesys", "--seed=2", "--account=" + path + ".nope"])
	assert_eq(missing.status, 1)
	assert_eq(missing.record, {})
	var data := DataRepo.load_all()
	var stages := {}
	for tier: Array in data.stages.tiers:
		for stage: String in tier:
			stages[stage] = {"duration": 0.05, "maps": [{"map_id": data.stages.stages[stage].maps[0].map_id, "boss": {}}]}
	var patch := _write("chain patch.json", {"stages": {"stages": stages}})
	var chain := _cli(["--tier=2", "--stage=ellinia", "--seed=2026", "--cap=1", "--patch=" + patch,
		"--account=" + path])
	assert_eq(chain.status, 0)
	assert_eq(chain.record.get("account", ""), "tool account.json")
	assert_eq(chain.record.rounds.size(), 2)
	for round_record: Dictionary in chain.record.rounds:
		assert_eq(CharacterSnapshot.integers(round_record.start_character.cash), {"hat": 1000001, "shoes": 1070001})
		assert_eq(round_record.warnings, [])


func test_run_options_carry_the_account_flag_into_the_run_scene() -> void:
	var parsed := SceneFlow.parse_run_args(PackedStringArray(["--run=henesys", "--seed=3",
		"--account=C:/some dir/acct.json"]))
	assert_eq(parsed.options.account, "C:/some dir/acct.json", "--run passes the path through as an option")
	var options := RunScene.account_from_options({"account": _write("run account.json", ACCOUNT)})
	assert_eq(options.errors, PackedStringArray())
	assert_eq(options.account.owned, [1000001, 1070001, 5000001, 1812002])
	assert_eq(options.name, "run account.json")
	var carried := RunScene.account_from_options({"account": AccountFile.normalized(ACCOUNT)})
	assert_eq(carried.errors, PackedStringArray())
	assert_eq(carried.name, "")
	assert_eq(RunScene.account_from_options({}).account, {})
	var bad := RunScene.account_from_options({"account": "C:/no/such/account.json"})
	assert_eq(bad.errors.size(), 1)


func _cli(args: Array) -> Dictionary:
	var output: Array = []
	var status := OS.execute(OS.get_executable_path(), ["--headless", "--path",
		ProjectSettings.globalize_path("res://"), "--script", "res://tools/balance_run.gd", "--", "--cap=0.1"] + args, output, true)
	var record := {}
	for line: String in "\n".join(output).split("\n"):
		if line.begins_with("BALANCE "):
			record = JSON.parse_string(line.substr(8))
	return {"status": status, "record": record}


func test_committed_fixture_accounts_load_and_wear_what_they_say() -> void:
	# #126: the two full accounts used by the regression smoke and the dressed playtest.
	var pet_errors := PackedStringArray()
	var full_pet := AccountFile.load_file(ProjectSettings.globalize_path("res://tests/fixtures/accounts/full_pet.json"), pet_errors)
	assert_eq(pet_errors, PackedStringArray())
	assert_eq(full_pet.pet, 5000000)
	assert_eq(full_pet.owned.size(), 6, "the pet and its five upgrades")
	var errors := PackedStringArray()
	var dressed := AccountFile.load_file(ProjectSettings.globalize_path("res://tests/fixtures/accounts/full_cash_pet.json"), errors)
	assert_eq(errors, PackedStringArray())
	assert_eq(dressed.cash.size(), 11, "a cash item in every slot")
	var data := DataRepo.load_all()
	var setup := RF.setup("quiet", 5, RF.quiet_data())
	AccountFile.apply(setup, dressed)
	var catalog := CashCatalog.from_data(data)
	var resolved := catalog.resolve(setup.character.cash, setup.character.pet, setup.account.owned)
	assert_eq(resolved.worn.size(), 11, "the catalog accepts every worn item: %s" % [resolved.worn])
	assert_eq(resolved.pet, 5000000)
