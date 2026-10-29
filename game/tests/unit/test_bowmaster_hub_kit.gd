extends TestCase
## The `--hub --job=312` test kit (spec #332, B12 #344): the Bowmaster's fixture, its bow ATT / DEX scroll stacks and the spare
## equipment it can wear. Bowmaster ships `playable: false` until B13; the job-error tests mirror the flip with `DataRepo.patch`.

const BOW_FIXTURE := "res://tests/fixtures/characters/bowmaster_t2.json"
const PLAYABLE := {"jobs_survivor": {"jobs": {"312": {"playable": true}}}}
const SPARE := [1002001, 1452051, 1082002, 1040008]


func after_each() -> void:
	DataRepo.patch = {}


## Item info as WZ would give it for the spare pieces.
func _loader() -> Callable:
	var imgs := {}
	for spec: Array in [[1002001, {"tuc": 5, "incPDD": 3}], [1452051, {"tuc": 7, "incPAD": 28}], [1082002, {"tuc": 5, "incPDD": 1}],
			[1040008, {"tuc": 7, "incPDD": 4}], [1040002, {"tuc": 7, "incPDD": 3}], [1060002, {"tuc": 7, "incPDD": 2}],
			[1072001, {"tuc": 5, "incPDD": 2}], [1452002, {"tuc": 7, "incPAD": 25}]]:
		imgs[AvatarRenderer.part_img_path(spec[0])] = {"info": spec[1]}
	return func(path: String) -> Dictionary: return imgs.get(path, {})


## A fresh Lv1 Bowmaster (312, the War Bow) as the creation screen makes it; the kit only reads its job.
func _bowmaster() -> Dictionary:
	return SceneFlow.new_character({}, 312, _loader())


func test_hub_job_312_picks_the_bowmaster_fixture_and_an_explicit_character_wins() -> void:
	assert_eq(HubTestKit.parse_args(PackedStringArray(["--hub", "--job=312"])),
		{"job": 312, "character": BOW_FIXTURE, "mesos": 500000})
	assert_eq(HubTestKit.parse_args(PackedStringArray(["--hub", "--job=312", "--character=/x/y.json"])).character, "/x/y.json")
	assert_eq(HubTestKit.parse_args(PackedStringArray(["--hub", "--job=212"])).character, "res://tests/fixtures/characters/fp_arch_mage.json", "F/P is unchanged")
	assert_eq(HubTestKit.parse_args(PackedStringArray(["--hub", "--job=112"])).character, "res://tests/fixtures/characters/hero_t2.json", "so is Hero")


func test_the_bowmaster_kit_scrolls_are_bow_gloves_shoes_att_and_hat_dex_within_the_use_tab() -> void:
	var character := HubTestKit.apply(_bowmaster(), 500000, _loader())
	var held: Array = character.scrolls.keys().map(func(k: String) -> int: return int(k))
	held.sort()
	var families: Dictionary = DataRepo.load_split("scrolls").families
	var want := []
	for entry: Array in [["bow", "ATT"], ["gloves", "ATT"], ["shoes", "ATT"], ["hat", "DEX"]]:
		for id: Variant in families[entry[0]][entry[1]].values():
			want.append(int(id))
	want.sort()
	assert_eq(held, want, "every rate of the four scroll lines a Bowmaster's gear takes")
	for id: int in [2044500, 2044501, 2044502, 2044504, 2044505]:
		assert_true(id in held, "bow ATT scroll %d" % id)
	assert_true(character.scrolls.size() <= Shop.use_stack_limit(), "the stacks fit the Use tab")
	assert_eq(character.job_id, 312, "the rest of the character is untouched")
	assert_eq(CharacterSnapshot.validation_error(character), "")
	for count: Variant in character.scrolls.values():
		assert_eq(int(count), HubTestKit.SCROLL_COUNT)


func test_the_bowmaster_kit_equipment_holds_a_bow_a_hat_gloves_and_a_top() -> void:
	var character := HubTestKit.apply(_bowmaster(), 500000, _loader())
	assert_eq(character.equipment.inventory.map(func(e: Dictionary) -> int: return int(e.id)), SPARE)
	assert_eq(WeaponInfo.family(1452051), "bow", "the spare weapon is a bow, a family a Bowmaster can wield")
	assert_true("bow" in DataRepo.load_all().jobs_survivor.jobs["312"].weapon_families)
	if not require_cache():
		return
	var lib := AssetLibrary.get_default()
	for id: int in SPARE:
		var img := lib.img(AvatarRenderer.part_img_path(id))
		assert_true(img != null, "%d is in the cache" % id)
		if img != null:
			assert_eq(Equipment.requirement_error(img.root.get("info", {}), {"job_id": 312}), "", "a Bowmaster can wear %d" % id)


func test_other_jobs_kits_are_unchanged() -> void:
	assert_eq(HubTestKit.kit_equipment(212), [1002001, 1382001, 1082002, 1040004])
	assert_eq(HubTestKit.kit_equipment(112), [1002001, 1402000, 1082002, 1040010])
	assert_eq(HubTestKit.fallback_item(212), 1382001)
	assert_eq(HubTestKit.fallback_item(112), 1302009)


func test_the_flow_driver_fallback_item_is_a_bow_a_bowmaster_can_hold() -> void:
	var item := HubTestKit.fallback_item(312)
	assert_eq(item, 1452007, "the Lv40 Composite Bow")
	assert_eq(WeaponInfo.family(item), "bow")
	if not require_cache():
		return
	var img := AssetLibrary.get_default().img(AvatarRenderer.part_img_path(item))
	assert_true(img != null)
	if img != null:
		assert_eq(int(img.root.info.reqLevel), 40, "above Lv1: the driver wears it to show a requirement-bearing item")
		assert_eq(Equipment.requirement_error(img.root.get("info", {}), {"job_id": 312}), "")


func test_hub_job_errors_name_the_mismatch_or_the_unplayable_job() -> void:
	var fixture: Dictionary = DataRepo.load_json(BOW_FIXTURE)
	fixture.erase("_doc")
	var fp: Dictionary = DataRepo.load_json("res://tests/fixtures/characters/fp_arch_mage.json")
	fp.erase("_doc")
	var data := DataRepo.load_all()
	var shipped := JobTree.from_data(data.jobs, data.jobs_survivor)
	assert_true(HubTestKit.job_error({"job": 312}, fixture, shipped).contains("not playable"), "shipped Bowmaster is unplayable until B13")
	DataRepo.patch = PLAYABLE.duplicate(true)
	var data2 := DataRepo.load_all()
	var mirrored := JobTree.from_data(data2.jobs, data2.jobs_survivor)
	assert_eq(HubTestKit.job_error({"job": 312}, fixture, mirrored), "")
	assert_true(HubTestKit.job_error({"job": 312}, fp, mirrored).contains("does not match"), "a Bowmaster request with an F/P character")
	assert_true(HubTestKit.job_error({"job": 212}, fixture, mirrored).contains("does not match"), "and the other way round")
