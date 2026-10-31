extends TestCase
## The `--hub --job=522` test kit (spec #384, C14 #398): the Corsair's fixture, its gun ATT scroll stacks and the spare
## equipment it can wear. Corsair ships `playable: true` (C15 #399); the job-error test also checks the state a patch turns off.

const COR_FIXTURE := "res://tests/fixtures/characters/corsair_t2.json"
const CF := preload("res://tests/fixtures/corsair_fixtures.gd")
const UNPLAYABLE := CF.UNPLAYABLE
const SPARE := [1002001, 1492001, 1082002, 1040010]
const GUN_SCROLLS := [2044900, 2044901, 2044902, 2044903, 2044904]


func after_each() -> void:
	DataRepo.patch = {}


## Item info as WZ would give it for the spare pieces.
func _loader() -> Callable:
	var imgs := {}
	for spec: Array in [[1002001, {"tuc": 5, "incPDD": 3}], [1492001, {"tuc": 7, "incPAD": 18}], [1082002, {"tuc": 5, "incPDD": 1}],
			[1040010, {"tuc": 7, "incPDD": 4}], [1040002, {"tuc": 7, "incPDD": 3}], [1060002, {"tuc": 7, "incPDD": 2}],
			[1072001, {"tuc": 5, "incPDD": 2}], [1492000, {"tuc": 7, "incPAD": 13}]]:
		imgs[AvatarRenderer.part_img_path(spec[0])] = {"info": spec[1]}
	return func(path: String) -> Dictionary: return imgs.get(path, {})


## A fresh Lv1 Corsair (522, the Pistol) as the creation screen makes it; the kit only reads its job.
func _corsair() -> Dictionary:
	return SceneFlow.new_character({}, 522, _loader())


func test_hub_job_522_picks_the_corsair_fixture_and_an_explicit_character_wins() -> void:
	assert_eq(HubTestKit.parse_args(PackedStringArray(["--hub", "--job=522"])),
		{"job": 522, "character": COR_FIXTURE, "mesos": 500000})
	assert_eq(HubTestKit.parse_args(PackedStringArray(["--hub", "--job=522", "--character=/x/y.json"])).character, "/x/y.json")
	assert_eq(HubTestKit.parse_args(PackedStringArray(["--hub", "--job=212"])).character, "res://tests/fixtures/characters/fp_arch_mage.json", "F/P is unchanged")
	assert_eq(HubTestKit.parse_args(PackedStringArray(["--hub", "--job=312"])).character, "res://tests/fixtures/characters/bowmaster_t2.json", "so is Bowmaster")


func test_the_corsair_kit_scrolls_are_the_five_gun_att_scrolls_within_the_use_tab() -> void:
	var character := HubTestKit.apply(_corsair(), 500000, _loader())
	var held: Array = character.scrolls.keys().map(func(k: String) -> int: return int(k))
	held.sort()
	var families: Dictionary = DataRepo.load_split("scrolls").families
	var want: Array = []
	for id: Variant in families["gun"]["ATT"].values():
		want.append(int(id))
	want.sort()
	assert_eq(want, GUN_SCROLLS, "scrolls/pirate.json holds exactly these gun ATT scrolls")
	assert_eq(held, want, "every rate of the gun ATT scroll, independent of the kit file")
	assert_true(character.scrolls.size() <= Shop.use_stack_limit(), "the stacks fit the Use tab")
	assert_eq(character.job_id, 522, "the rest of the character is untouched")
	assert_eq(CharacterSnapshot.validation_error(character), "")
	for count: Variant in character.scrolls.values():
		assert_eq(int(count), HubTestKit.SCROLL_COUNT)
	for id: int in held:
		assert_false(id in (families["knuckle"]["ATT"].values() as Array).map(func(v: Variant) -> int: return int(v)), "no knuckle scroll: %d" % id)


func test_the_corsair_kit_equipment_holds_a_second_pistol_a_hat_gloves_and_a_top() -> void:
	var character := HubTestKit.apply(_corsair(), 500000, _loader())
	assert_eq(character.equipment.inventory.map(func(e: Dictionary) -> int: return int(e.id)), SPARE)
	assert_eq(WeaponInfo.family(1492001), "gun", "the spare weapon is a gun, the family a Corsair wields")
	assert_true("gun" in DataRepo.load_all().jobs_survivor.jobs["522"].weapon_families)
	if not require_cache():
		return
	var lib := AssetLibrary.get_default()
	for id: int in SPARE:
		var img := lib.img(AvatarRenderer.part_img_path(id))
		assert_true(img != null, "%d is in the cache" % id)
		if img != null:
			assert_eq(Equipment.requirement_error(img.root.get("info", {}), {"job_id": 522}), "", "a Corsair can wear %d" % id)


func test_other_jobs_kits_are_unchanged() -> void:
	assert_eq(HubTestKit.kit_equipment(212), [1002001, 1382001, 1082002, 1040004])
	assert_eq(HubTestKit.kit_equipment(112), [1002001, 1402000, 1082002, 1040010])
	assert_eq(HubTestKit.kit_equipment(312), [1002001, 1452051, 1082002, 1040008])
	assert_eq(HubTestKit.fallback_item(212), 1382001)
	assert_eq(HubTestKit.fallback_item(112), 1302009)
	assert_eq(HubTestKit.fallback_item(312), 1452007)


func test_the_flow_driver_fallback_item_is_a_gun_a_corsair_can_hold() -> void:
	var item := HubTestKit.fallback_item(522)
	assert_eq(item, 1492006, "the Lv40 gun")
	assert_eq(WeaponInfo.family(item), "gun")
	if not require_cache():
		return
	var img := AssetLibrary.get_default().img(AvatarRenderer.part_img_path(item))
	assert_true(img != null)
	if img != null:
		assert_eq(int(img.root.info.reqLevel), 40, "above Lv1: the driver wears it to show a requirement-bearing item")
		assert_eq(Equipment.requirement_error(img.root.get("info", {}), {"job_id": 522}), "")


func test_hub_job_errors_name_the_mismatch_or_the_unplayable_job() -> void:
	var fixture: Dictionary = DataRepo.load_json(COR_FIXTURE)
	fixture.erase("_doc")
	var fp: Dictionary = DataRepo.load_json("res://tests/fixtures/characters/fp_arch_mage.json")
	fp.erase("_doc")
	var data := DataRepo.load_all()
	var shipped := JobTree.from_data(data.jobs, data.jobs_survivor)
	DataRepo.patch = UNPLAYABLE.duplicate(true)
	var off := DataRepo.jobs(DataRepo.load_all())
	assert_true(HubTestKit.job_error({"job": 522}, fixture, off).contains("not playable"), "a patch can turn 522 off")
	DataRepo.patch = {}
	var mirrored := shipped
	assert_eq(HubTestKit.job_error({"job": 522}, fixture, mirrored), "")
	assert_true(HubTestKit.job_error({"job": 522}, fp, mirrored).contains("does not match"))
	assert_true(HubTestKit.job_error({"job": 212}, fixture, mirrored).contains("does not match"))
