extends TestCase
## The `--hub --job=412` test kit (spec #383, NL11 #410): the Night Lord's fixture, its claw ATT scroll stacks and the spare
## equipment it can wear. Night Lord ships `playable: false` until NL12, so the kit is built through the data seam
## (`DataRepo.patch` making 412 playable), and the job-error test checks both the unplayable and the mirrored states.

const NL_FIXTURE := "res://tests/fixtures/characters/night_lord_t2.json"
const PLAYABLE := {"jobs_survivor": {"jobs": {"412": {"playable": true}}}}
const SPARE := [1002001, 1472001, 1082002, 1040031]
const CLAW_SCROLLS := [2044700, 2044701, 2044702, 2044704, 2044705]


func after_each() -> void:
	DataRepo.patch = {}


## Item info as WZ would give it for the spare pieces.
func _loader() -> Callable:
	var imgs := {}
	for spec: Array in [[1002001, {"tuc": 5, "incPDD": 3}], [1472001, {"tuc": 7, "incPAD": 12}], [1082002, {"tuc": 5, "incPDD": 1}],
			[1040031, {"tuc": 7, "incPDD": 4}], [1040002, {"tuc": 7, "incPDD": 3}], [1060002, {"tuc": 7, "incPDD": 2}],
			[1072001, {"tuc": 5, "incPDD": 2}], [1472000, {"tuc": 7, "incPAD": 10}]]:
		imgs[AvatarRenderer.part_img_path(spec[0])] = {"info": spec[1]}
	return func(path: String) -> Dictionary: return imgs.get(path, {})


## A fresh Lv1 Night Lord (412, the Garnier) as the creation screen makes it; the kit only reads its job.
func _night_lord() -> Dictionary:
	return SceneFlow.new_character({}, 412, _loader())


func test_hub_job_412_picks_the_night_lord_fixture_and_an_explicit_character_wins() -> void:
	assert_eq(HubTestKit.parse_args(PackedStringArray(["--hub", "--job=412"])),
		{"job": 412, "character": NL_FIXTURE, "mesos": 500000})
	assert_eq(HubTestKit.parse_args(PackedStringArray(["--hub", "--job=412", "--character=/x/y.json"])).character, "/x/y.json")
	assert_eq(HubTestKit.parse_args(PackedStringArray(["--hub", "--job=212"])).character, "res://tests/fixtures/characters/fp_arch_mage.json", "F/P is unchanged")
	assert_eq(HubTestKit.parse_args(PackedStringArray(["--hub", "--job=312"])).character, "res://tests/fixtures/characters/bowmaster_t2.json", "so is Bowmaster")


func test_the_night_lord_kit_scrolls_are_the_five_claw_att_scrolls_within_the_use_tab() -> void:
	DataRepo.patch = PLAYABLE.duplicate(true)
	var character := HubTestKit.apply(_night_lord(), 500000, _loader())
	var held: Array = character.scrolls.keys().map(func(k: String) -> int: return int(k))
	held.sort()
	var families: Dictionary = DataRepo.load_split("scrolls").families
	var want: Array = []
	for id: Variant in families["claw"]["ATT"].values():
		want.append(int(id))
	want.sort()
	assert_eq(want, CLAW_SCROLLS, "scrolls/thief.json holds exactly these claw ATT scrolls")
	assert_eq(held, want, "every rate of the claw ATT scroll, independent of the kit file")
	assert_true(character.scrolls.size() <= Shop.use_stack_limit(), "the stacks fit the Use tab")
	assert_eq(character.job_id, 412, "the rest of the character is untouched")
	assert_eq(CharacterSnapshot.validation_error(character), "")
	for count: Variant in character.scrolls.values():
		assert_eq(int(count), HubTestKit.SCROLL_COUNT)
	for id: int in held:
		assert_false(id in (families["dagger"]["ATT"].values() as Array).map(func(v: Variant) -> int: return int(v)), "no dagger scroll: %d" % id)


func test_the_night_lord_kit_equipment_holds_a_second_claw_a_hat_gloves_and_a_top() -> void:
	DataRepo.patch = PLAYABLE.duplicate(true)
	var character := HubTestKit.apply(_night_lord(), 500000, _loader())
	assert_eq(character.equipment.inventory.map(func(e: Dictionary) -> int: return int(e.id)), SPARE)
	assert_eq(WeaponInfo.family(1472001), "claw", "the spare weapon is a claw, the family a Night Lord wields")
	assert_true("claw" in DataRepo.load_all().jobs_survivor.jobs["412"].weapon_families)
	if not require_cache():
		return
	var lib := AssetLibrary.get_default()
	for id: int in SPARE:
		var img := lib.img(AvatarRenderer.part_img_path(id))
		assert_true(img != null, "%d is in the cache" % id)
		if img != null:
			assert_eq(Equipment.requirement_error(img.root.get("info", {}), {"job_id": 412}), "", "a Night Lord can wear %d" % id)


func test_other_jobs_kits_are_unchanged() -> void:
	assert_eq(HubTestKit.kit_equipment(212), [1002001, 1382001, 1082002, 1040004])
	assert_eq(HubTestKit.kit_equipment(112), [1002001, 1402000, 1082002, 1040010])
	assert_eq(HubTestKit.kit_equipment(312), [1002001, 1452051, 1082002, 1040008])
	assert_eq(HubTestKit.fallback_item(212), 1382001)
	assert_eq(HubTestKit.fallback_item(112), 1302009)
	assert_eq(HubTestKit.fallback_item(312), 1452007)


func test_the_flow_driver_fallback_item_is_a_claw_a_night_lord_can_hold() -> void:
	var item := HubTestKit.fallback_item(412)
	assert_eq(item, 1472014, "the Lv40 claw")
	assert_eq(WeaponInfo.family(item), "claw")
	if not require_cache():
		return
	var img := AssetLibrary.get_default().img(AvatarRenderer.part_img_path(item))
	assert_true(img != null)
	if img != null:
		assert_eq(int(img.root.info.reqLevel), 40, "above Lv1: the driver wears it to show a requirement-bearing item")
		assert_eq(Equipment.requirement_error(img.root.get("info", {}), {"job_id": 412}), "")


func test_hub_job_errors_name_the_mismatch_or_the_unplayable_job() -> void:
	var fixture: Dictionary = DataRepo.load_json(NL_FIXTURE)
	fixture.erase("_doc")
	var fp: Dictionary = DataRepo.load_json("res://tests/fixtures/characters/fp_arch_mage.json")
	fp.erase("_doc")
	var data := DataRepo.load_all()
	var shipped := JobTree.from_data(data.jobs, data.jobs_survivor)
	assert_true(HubTestKit.job_error({"job": 412}, fixture, shipped).contains("not playable"), "412 ships unplayable until NL12")
	DataRepo.patch = PLAYABLE.duplicate(true)
	var mirrored := DataRepo.jobs(DataRepo.load_all())
	assert_eq(HubTestKit.job_error({"job": 412}, fixture, mirrored), "")
	assert_true(HubTestKit.job_error({"job": 412}, fp, mirrored).contains("does not match"))
	assert_true(HubTestKit.job_error({"job": 212}, fixture, mirrored).contains("does not match"))
