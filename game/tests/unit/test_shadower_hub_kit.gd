extends TestCase
## The `--hub --job=422` test kit (spec #425, SH13 #438): the Shadower's fixture, its dagger ATT scroll stacks and the spare
## equipment it can wear. Shadower is playable since SH14 #439; the job-error test uses the data seam
## (`DataRepo.patch`) as the "unplayable" mirror.

const FIXTURE := "res://tests/fixtures/characters/shadower_t2.json"
const UNPLAYABLE := {"jobs_survivor": {"jobs": {"422": {"playable": false}}}}
const SPARE := [1002001, 1332000, 1082002, 1040031]
const DAGGER_SCROLLS := [2043300, 2043301, 2043302, 2043304, 2043305]


func after_each() -> void:
	DataRepo.patch = {}


## Item info as WZ would give it for the spare pieces.
func _loader() -> Callable:
	var imgs := {}
	for spec: Array in [[1002001, {"tuc": 5, "incPDD": 3}], [1332000, {"tuc": 7, "incPAD": 27}], [1082002, {"tuc": 5, "incPDD": 1}],
			[1040031, {"tuc": 7, "incPDD": 4}], [1040002, {"tuc": 7, "incPDD": 3}], [1060002, {"tuc": 7, "incPDD": 2}],
			[1072001, {"tuc": 5, "incPDD": 2}], [1332005, {"tuc": 7, "incPAD": 20}]]:
		imgs[AvatarRenderer.part_img_path(spec[0])] = {"info": spec[1]}
	return func(path: String) -> Dictionary: return imgs.get(path, {})


## A fresh Lv1 Shadower (422, the Razor) as the creation screen makes it; the kit only reads its job.
func _shadower() -> Dictionary:
	return SceneFlow.new_character({}, 422, _loader())


func test_hub_job_422_picks_the_shadower_fixture_and_an_explicit_character_wins() -> void:
	assert_eq(HubTestKit.parse_args(PackedStringArray(["--hub", "--job=422"])),
		{"job": 422, "character": FIXTURE, "mesos": 500000})
	assert_eq(HubTestKit.parse_args(PackedStringArray(["--hub", "--job=422", "--character=/x/y.json"])).character, "/x/y.json")
	assert_eq(HubTestKit.parse_args(PackedStringArray(["--hub", "--job=212"])).character, "res://tests/fixtures/characters/fp_arch_mage.json", "F/P is unchanged")
	assert_eq(HubTestKit.parse_args(PackedStringArray(["--hub", "--job=412"])).character, "res://tests/fixtures/characters/night_lord_t2.json", "so is Night Lord")


func test_the_shadower_kit_scrolls_are_the_five_dagger_att_scrolls_within_the_use_tab() -> void:
	var character := HubTestKit.apply(_shadower(), 500000, _loader())
	var held: Array = character.scrolls.keys().map(func(k: String) -> int: return int(k))
	held.sort()
	var families: Dictionary = DataRepo.load_split("scrolls").families
	var want: Array = []
	for id: Variant in families["dagger"]["ATT"].values():
		want.append(int(id))
	want.sort()
	assert_eq(want, DAGGER_SCROLLS, "scrolls/thief.json holds exactly these dagger ATT scrolls")
	assert_eq(held, want, "every rate of the dagger ATT scroll, independent of the kit file")
	assert_true(character.scrolls.size() <= Shop.use_stack_limit(), "the stacks fit the Use tab")
	assert_eq(character.job_id, 422, "the rest of the character is untouched")
	assert_eq(CharacterSnapshot.validation_error(character), "")
	for count: Variant in character.scrolls.values():
		assert_eq(int(count), HubTestKit.SCROLL_COUNT)
	for id: int in held:
		assert_false(id in (families["claw"]["ATT"].values() as Array).map(func(v: Variant) -> int: return int(v)), "no claw scroll: %d" % id)


func test_the_shadower_kit_equipment_holds_a_second_dagger_a_hat_gloves_and_a_top() -> void:
	var character := HubTestKit.apply(_shadower(), 500000, _loader())
	assert_eq(character.equipment.inventory.map(func(e: Dictionary) -> int: return int(e.id)), SPARE)
	assert_eq(WeaponInfo.family(1332000), "dagger", "the spare weapon is a dagger, the family a Shadower wields")
	assert_true("dagger" in DataRepo.load_all().jobs_survivor.jobs["422"].weapon_families)
	if not require_cache():
		return
	var lib := AssetLibrary.get_default()
	for id: int in SPARE:
		var img := lib.img(AvatarRenderer.part_img_path(id))
		assert_true(img != null, "%d is in the cache" % id)
		if img != null:
			assert_eq(Equipment.requirement_error(img.root.get("info", {}), {"job_id": 422}), "", "a Shadower can wear %d" % id)


func test_other_jobs_kits_are_unchanged() -> void:
	assert_eq(HubTestKit.kit_equipment(212), [1002001, 1382001, 1082002, 1040004])
	assert_eq(HubTestKit.kit_equipment(112), [1002001, 1402000, 1082002, 1040010])
	assert_eq(HubTestKit.kit_equipment(412), [1002001, 1472001, 1082002, 1040031])
	assert_eq(HubTestKit.fallback_item(212), 1382001)
	assert_eq(HubTestKit.fallback_item(412), 1472014)


func test_the_flow_driver_fallback_item_is_a_dagger_a_shadower_can_hold() -> void:
	var item := HubTestKit.fallback_item(422)
	assert_eq(item, 1332011, "the Lv40 dagger")
	assert_eq(WeaponInfo.family(item), "dagger")
	if not require_cache():
		return
	var img := AssetLibrary.get_default().img(AvatarRenderer.part_img_path(item))
	assert_true(img != null)
	if img != null:
		assert_eq(int(img.root.info.reqLevel), 40, "above Lv1: the driver wears it to show a requirement-bearing item")
		assert_eq(Equipment.requirement_error(img.root.get("info", {}), {"job_id": 422}), "")


func test_hub_job_errors_name_the_mismatch_or_the_unplayable_job() -> void:
	var fixture: Dictionary = DataRepo.load_json(FIXTURE)
	fixture.erase("_doc")
	var fp: Dictionary = DataRepo.load_json("res://tests/fixtures/characters/fp_arch_mage.json")
	fp.erase("_doc")
	var data := DataRepo.load_all()
	var shipped := JobTree.from_data(data.jobs, data.jobs_survivor)
	assert_eq(HubTestKit.job_error({"job": 422}, fixture, shipped), "", "422 is playable (SH14)")
	assert_true(HubTestKit.job_error({"job": 422}, fp, shipped).contains("does not match"))
	assert_true(HubTestKit.job_error({"job": 212}, fixture, shipped).contains("does not match"))
	DataRepo.patch = UNPLAYABLE.duplicate(true)
	var mirror := DataRepo.jobs(DataRepo.load_all())
	assert_true(HubTestKit.job_error({"job": 422}, fixture, mirror).contains("not playable"), "refused through the unplayable mirror")
