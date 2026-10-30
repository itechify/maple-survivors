extends TestCase
## `--hub --job=512` (spec #412, B11 #423): the Buccaneer fixture, the knuckle ATT and ACC scroll stacks, the spare gear and the
## flow driver's diagnostic item, all read from `jobs/buccaneer.json` `hub_kit` through `HubTestKit` / `JobTree.lineage_value`.

const FIXTURE := "res://tests/fixtures/characters/buccaneer_t2.json"
const KNUCKLE := 1482000


## Item info as WZ would give it for the creation outfit and the kit's spare gear (synthetic, no cache).
func _loader() -> Callable:
	var imgs := {}
	for spec: Array in [[1002001, {"tuc": 5, "incPDD": 3, "price": 1000}], [1482001, {"tuc": 7, "incPAD": 22, "price": 2000}],
			[1082002, {"tuc": 5, "incPDD": 1, "price": 500}], [1040010, {"tuc": 7, "incPDD": 3, "price": 300}],
			[1040002, {"tuc": 7, "incPDD": 3}], [1060002, {"tuc": 7, "incPDD": 2}], [1072001, {"tuc": 5, "incPDD": 2}],
			[KNUCKLE, {"tuc": 7, "incPAD": 18}]]:
		imgs[AvatarRenderer.part_img_path(spec[0])] = {"info": spec[1]}
	return func(path: String) -> Dictionary: return imgs.get(path, {})


func _buccaneer() -> Dictionary:
	return SceneFlow.new_character({}, 512, _loader())


## Every id of the knuckle ATT and ACC families in scrolls/pirate.json, read independently of the kit file.
func _knuckle_scroll_ids() -> Array:
	var families: Dictionary = DataRepo.load_json("res://data/survivor/scrolls/pirate.json").families.knuckle
	var ids: Array = []
	for kind: String in ["ATT", "ACC"]:
		assert_true(families.has(kind), "pirate.json has knuckle %s" % kind)
		for id: Variant in (families[kind] as Dictionary).values():
			ids.append(int(id))
	ids.sort()
	return ids


func test_the_job_flag_picks_the_buccaneer_fixture_from_the_line_file() -> void:
	assert_eq(HubTestKit.parse_args(PackedStringArray(["--hub", "--job=512"])), {"job": 512, "character": FIXTURE, "mesos": 500000})
	assert_eq(HubTestKit.parse_args(PackedStringArray(["--hub", "--job=512", "--character=/x/y.json"])).character, "/x/y.json",
		"an explicit --character wins")
	assert_eq(HubTestKit.parse_args(PackedStringArray(["--hub"])).character, "res://tests/fixtures/characters/fp_arch_mage.json",
		"without --job the default job's fixture is still F/P")


func test_the_scroll_stacks_are_every_rate_of_the_knuckle_att_and_acc_families() -> void:
	var held: Array = HubTestKit.apply(_buccaneer(), 500000, _loader()).scrolls.keys().map(func(k: String) -> int: return int(k))
	held.sort()
	assert_eq(held, _knuckle_scroll_ids(), "ten stacks: ATT and ACC at 100/60/10 and dark 70/30")
	var kit: Array = HubTestKit.kit_scrolls(512)
	kit.sort()
	assert_eq(kit, _knuckle_scroll_ids())
	var stacks: Dictionary = HubTestKit.apply(_buccaneer(), 1, _loader()).scrolls
	for id: Variant in held:
		assert_eq(int(stacks[str(id)]), HubTestKit.SCROLL_COUNT, "%d: one stack of ten" % int(id))


func test_the_spare_gear_and_the_fallback_item_are_a_knuckler_and_pirate_wearable_armour() -> void:
	assert_eq(HubTestKit.kit_equipment(512), [1002001, 1482001, 1082002, 1040010])
	assert_eq(HubTestKit.fallback_item(512), 1482006)
	var character := HubTestKit.apply(_buccaneer(), 500000, _loader())
	assert_eq(character.job_id, 512, "the rest of the character is untouched")
	assert_eq(character.mesos, 500000)
	assert_eq(character.tiers_unlocked, SceneFlow.tiers().size(), "every tier unlocked")
	assert_eq(CharacterSnapshot.validation_error(character), "")
	var spare: Array = character.equipment.inventory.map(func(i: Dictionary) -> int: return int(i.id))
	for id: int in [1002001, 1482001, 1082002, 1040010]:
		assert_true(id in spare, "%d is in the Equip tab" % id)


func test_the_spare_gear_and_fallback_are_wearable_by_a_buccaneer() -> void:
	if not require_cache():
		return
	var families: Array = DataRepo.load_all().jobs_survivor.jobs["512"].weapon_families
	for id: int in [1482001, HubTestKit.fallback_item(512)]:
		assert_true(WeaponInfo.family(id) in families, "%d is a Buccaneer weapon family" % id)
	var lib := AssetLibrary.get_default()
	for id: int in HubTestKit.kit_equipment(512) + [HubTestKit.fallback_item(512)]:
		var img := lib.img(AvatarRenderer.part_img_path(id))
		assert_true(img != null, "%d is in the cache" % id)
		if img != null:
			assert_eq(Equipment.requirement_error(img.root.get("info", {}), {"job_id": 512}), "", "a Buccaneer can wear %d" % id)


func test_the_fixture_exists_and_is_a_buccaneer() -> void:
	var loaded := HubTestKit.load_character(FIXTURE, _loader())
	assert_eq(loaded.error, "")
	if loaded.error == "":
		assert_eq(int(loaded.character.job_id), 512)


func test_other_jobs_kits_are_unchanged() -> void:
	assert_eq(HubTestKit.kit_equipment(212), [1002001, 1382001, 1082002, 1040004])
	assert_eq(HubTestKit.kit_equipment(112), [1002001, 1402000, 1082002, 1040010])
	assert_ne(HubTestKit.kit_scrolls(512), HubTestKit.kit_scrolls(212))
	assert_eq(HubTestKit.fallback_item(212), 1382001)


func test_hub_job_errors_name_the_mismatch_or_the_unplayable_job() -> void:
	var data := DataRepo.load_all()
	var jobs := JobTree.from_data(data.jobs, data.jobs_survivor)
	var fp: Dictionary = DataRepo.load_json("res://tests/fixtures/characters/fp_arch_mage.json")
	assert_eq(HubTestKit.job_error({"job": 512}, _buccaneer(), jobs), "", "shipped Buccaneer is playable")
	assert_true(HubTestKit.job_error({"job": 512}, fp, jobs).contains("does not match"), "a Buccaneer request with an F/P character")
	assert_true(HubTestKit.job_error({"job": 212}, _buccaneer(), jobs).contains("does not match"), "and the other way round")
	DataRepo.patch = {"jobs_survivor": {"jobs": {"512": {"playable": false}}}}
	var mirrored := DataRepo.load_all()
	var disabled := JobTree.from_data(mirrored.jobs, mirrored.jobs_survivor)
	DataRepo.patch = {}
	assert_true(HubTestKit.job_error({"job": 512}, _buccaneer(), disabled).contains("not playable"))
