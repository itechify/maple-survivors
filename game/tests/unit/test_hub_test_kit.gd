extends TestCase
## The tool-only `--hub` flag (HubTestKit + SceneFlow.start_hub): flag parsing, the throwaway save, the test kit added to
## the character (mesos, scroll stacks, spare equipment) and format-1 migration. Saves go to TestCase.test_dir(); the
## real user://save.json must stay untouched.

const FIXTURE := "res://tests/fixtures/characters/lv35_magician_2nd.json"
## Every rate (100, 60, 10, dark 70, dark 30) of wand Magic Att., hat INT, top DEF and gloves Magic Att. (scrolls.json).
const KIT_SCROLL_IDS := [2043700, 2043701, 2043702, 2043704, 2043705, 2040024, 2040025, 2040026, 2040012, 2040013,
	2040400, 2040401, 2040402, 2040404, 2040405, 2040818, 2040817, 2040816, 2040814, 2040815]

var work_dir := TestCase.test_dir("hub_kit")
var _nodes: Array[Node] = []


func before_each() -> void:
	TestCase.remove_tree(work_dir)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(work_dir))


func after_each() -> void:
	for node in _nodes:
		if is_instance_valid(node):
			node.queue_free()
	_nodes.clear()


## Item info as WZ would give it: a hat, a wand, gloves and a top with their upgrade slots and prices.
func _loader() -> Callable:
	var imgs := {}
	for spec: Array in [[1002001, {"tuc": 5, "incPDD": 3, "price": 1000}], [1382001, {"tuc": 7, "incMAD": 17, "price": 2000}],
			[1082002, {"tuc": 5, "incPDD": 1, "price": 500}], [1040004, {"tuc": 7, "incPDD": 4, "price": 300}],
			[1040002, {"tuc": 7, "incPDD": 3}], [1060002, {"tuc": 7, "incPDD": 2}], [1072001, {"tuc": 5, "incPDD": 2}],
			[1372005, {"tuc": 7, "incMAD": 23, "incPAD": 15}], [1302000, {"tuc": 7, "incPAD": 17}]]:
		imgs[AvatarRenderer.part_img_path(spec[0])] = {"info": spec[1]}
	return func(path: String) -> Dictionary: return imgs.get(path, {})


func _fixture() -> Dictionary:
	var out: Dictionary = DataRepo.load_json(FIXTURE)
	out.erase("_doc")
	return out


func test_without_the_hub_flag_nothing_is_requested() -> void:
	assert_eq(HubTestKit.parse_args(PackedStringArray(["--run=henesys_hg1", "--seed=3"])), {})
	assert_eq(HubTestKit.parse_args(PackedStringArray()), {})


func test_hub_flag_defaults_to_the_fixture_and_500000_mesos() -> void:
	assert_eq(HubTestKit.parse_args(PackedStringArray(["--hub"])),
		{"character": FIXTURE, "mesos": 500000})
	assert_eq(HubTestKit.parse_args(PackedStringArray(["--hub=1", "--vsync=off"])),
		{"character": FIXTURE, "mesos": 500000})


func test_hub_flag_takes_a_character_path_and_a_mesos_amount() -> void:
	assert_eq(HubTestKit.parse_args(PackedStringArray(["--hub", "--character=C:/a b/c.json", "--mesos=1234"])),
		{"character": "C:/a b/c.json", "mesos": 1234})
	assert_eq(HubTestKit.parse_args(PackedStringArray(["--hub", "--mesos=0"])).mesos, 0)
	assert_eq(HubTestKit.parse_args(PackedStringArray(["--hub", "--mesos=lots"])).mesos, 500000, "a bad amount keeps the default")
	assert_eq(HubTestKit.parse_args(PackedStringArray(["--hub", "--mesos=-5"])).mesos, 0, "never negative")


func test_the_kit_sets_mesos_and_leaves_the_character_valid() -> void:
	var character := HubTestKit.apply(_fixture(), 500000, _loader())
	assert_eq(character.mesos, 500000)
	assert_eq(CharacterSnapshot.validation_error(character), "")
	assert_eq(HubTestKit.apply(_fixture(), 77, _loader()).mesos, 77)
	assert_eq(character.level, 38, "the rest of the character is untouched")
	assert_eq(character.equipment.worn.weapon.id, 1372005)


func test_the_kit_holds_every_rate_of_the_main_families_within_the_use_tab() -> void:
	var character := HubTestKit.apply(_fixture(), 500000, _loader())
	var held: Array = character.scrolls.keys().map(func(k: String) -> int: return int(k))
	held.sort()
	var want := KIT_SCROLL_IDS.duplicate()
	want.sort()
	assert_eq(held, want)
	for id: int in KIT_SCROLL_IDS:
		assert_true(int(character.scrolls[str(id)]) >= 5, "%d is stocked" % id)
	assert_true(character.scrolls.size() <= Shop.use_stack_limit(character.potions),
		"the stacks fit the Use tab beside the potion stacks")
	var ids := Scrolls.ids(DataRepo.load_json("res://data/survivor/scrolls.json"))
	for id: int in KIT_SCROLL_IDS:
		assert_true(id in ids, "%d is a scroll of scrolls.json" % id)


func test_the_kit_keeps_scrolls_the_character_already_has_and_never_overfills_the_use_tab() -> void:
	var base := _fixture()
	base.scrolls = {"2040000": 3}
	var character := HubTestKit.apply(base, 1, _loader())
	assert_eq(character.scrolls["2040000"], 3, "an existing stack stays")
	assert_true(character.scrolls.size() <= Shop.use_stack_limit(character.potions))
	assert_eq(CharacterSnapshot.validation_error(character), "")


func test_the_kit_adds_spare_equipment_with_plain_wz_stats() -> void:
	var character := HubTestKit.apply(_fixture(), 500000, _loader())
	var inventory: Array = character.equipment.inventory
	assert_eq(inventory.map(func(e: Dictionary) -> int: return int(e.id)), [1002001, 1382001, 1082002, 1040004])
	assert_eq(inventory[0], {"id": 1002001, "stats": {"incPDD": 3}, "slots": 5, "scrolls": 0})
	assert_eq(inventory[1], {"id": 1382001, "stats": {"incMAD": 17}, "slots": 7, "scrolls": 0})


func test_a_format_1_character_file_migrates_before_the_kit() -> void:
	var v1 := {"format": 1, "job_id": 210, "level": 38, "exp": 3389, "beginner_weapon": 0,
		"look": {"equips": [1040002, 1060002, 1072001]}}
	var fixture := _fixture()
	for key: String in fixture:
		if not v1.has(key) and key not in ["equipment", "scrolls", "mesos", "format", "look"]:
			v1[key] = fixture[key]
	var path := work_dir.path_join("v1.json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(v1))
	file.close()
	var loaded := HubTestKit.load_character(path, _loader())
	assert_eq(loaded.error, "")
	assert_eq(int(loaded.character.format), CharacterSnapshot.FORMAT)
	assert_eq(Equipment.worn_ids(loaded.character.equipment.worn).size(), 4, "the old outfit is worn as equipment")
	var character := HubTestKit.apply(loaded.character, 500000, _loader())
	assert_eq(CharacterSnapshot.validation_error(character), "")
	assert_eq(character.equipment.inventory.size(), 4)


func test_load_character_reports_a_missing_or_broken_file() -> void:
	assert_true(String(HubTestKit.load_character(work_dir.path_join("nope.json"), _loader()).error).contains("nope.json"))
	var path := work_dir.path_join("bad.json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("{\"format\": 2}")
	file.close()
	assert_false(String(HubTestKit.load_character(path, _loader()).error).is_empty())
	var fixture := HubTestKit.load_character(FIXTURE, _loader())
	assert_eq(fixture.error, "")
	assert_false(fixture.character.has("_doc"), "the provenance note is not part of the character")


func test_the_tool_save_is_not_the_real_save_and_starts_fresh_every_time() -> void:
	assert_true(HubTestKit.SAVE_PATH != SaveData.PATH)
	assert_true(HubTestKit.SAVE_PATH.begins_with("user://") and HubTestKit.SAVE_PATH.contains("tool"))
	var path := work_dir.path_join("tool_hub.json")
	var first := HubTestKit.fresh_save(path)
	assert_eq(first.path, path)
	assert_eq(first.create_slot(_snapshot()), 0)
	assert_true(FileAccess.file_exists(path))
	var second := HubTestKit.fresh_save(path)
	assert_eq(second.slot(0), {}, "a new launch never sees the last one")
	assert_true(second.history.is_empty() and second.best.is_empty())


func test_start_hub_enters_the_free_market_through_a_throwaway_slot_and_spares_the_real_save() -> void:
	var real_before := FileAccess.get_file_as_bytes(SaveData.PATH)
	var real_existed := FileAccess.file_exists(SaveData.PATH)
	var flow := _flow()
	var path := work_dir.path_join("tool_hub.json")
	flow.start_hub({"character": FIXTURE, "mesos": 321000}, path)
	assert_eq(flow.current_name, "free_market")
	assert_eq(flow.save.path, path)
	assert_eq(flow.active_slot, 0)
	var boundary := SaveData.new(path).slot(0)
	assert_eq(boundary.phase, "free_market")
	assert_eq(int(boundary.tier), 1, "out00 opens the second tier's map select, as after a real clear")
	assert_eq(boundary.character.mesos, 321000)
	assert_eq(boundary.character.scrolls.size(), KIT_SCROLL_IDS.size())
	assert_eq(boundary.character.equipment.inventory.size(), 4)
	assert_eq(FileAccess.file_exists(SaveData.PATH), real_existed, "the real save was not created or removed")
	if real_existed:
		assert_eq(FileAccess.get_file_as_bytes(SaveData.PATH), real_before, "the real save is byte for byte the same")
	flow.save_and_quit()
	assert_eq(flow.current_name, "character_select", "Save & quit works against the throwaway save")
	assert_eq(SaveData.new(path).slot(0).name, boundary.name)


func test_start_hub_with_an_unreadable_character_shows_the_error_screen() -> void:
	var flow := _flow()
	flow.start_hub({"character": work_dir.path_join("nope.json"), "mesos": 1}, work_dir.path_join("tool_hub.json"))
	assert_eq(flow.current_name, "error")


func test_the_npc_chat_hint_only_appears_when_the_action_has_no_key() -> void:
	assert_eq(HubTestKit.npc_chat_hint([InputEventKey.new()]), "")
	var hint := HubTestKit.npc_chat_hint([])
	assert_true(hint.contains("double-click") and hint.contains("Key Config"))
	assert_false(hint.contains("\n"), "one console line")


func _snapshot() -> Dictionary:
	return {"name": "HubTester", "created": "2026-01-01T00:00:00", "character": _fixture(), "tier": 1,
		"phase": "free_market", "rounds_played": 1, "tiers_cleared": 1}


func _flow() -> SceneFlow:
	var flow := SceneFlow.new()
	_nodes.append(flow)
	flow.deferred_swaps = false
	var host := Node.new()
	(Engine.get_main_loop() as SceneTree).current_scene.add_child(host)
	_nodes.append(host)
	flow.host = host
	return flow
