extends TestCase
## The `--hub --job=322` test kit (spec #360, MS10 #370): the Marksman's fixture, its crossbow ATT / gloves / shoes / hat scroll
## stacks and the spare equipment it can wear. Marksman is playable (MS11 #371); the kit reads only the job entry's `hub_kit`, and an
## explicit `playable: false` patch tests the refusal.

const MARKSMAN_FIXTURE := "res://tests/fixtures/characters/marksman_t2.json"
const DISABLED := {"jobs_survivor": {"jobs": {"322": {"playable": false}}}}
const SPARE := [1002001, 1462002, 1082002, 1040008]


func after_each() -> void:
	DataRepo.patch = {}


## Item info as WZ would give it for the spare pieces.
func _loader() -> Callable:
	var imgs := {}
	for spec: Array in [[1002001, {"tuc": 5, "incPDD": 3}], [1462002, {"tuc": 7, "incPAD": 34}], [1082002, {"tuc": 5, "incPDD": 1}],
			[1040008, {"tuc": 7, "incPDD": 4}], [1040002, {"tuc": 7, "incPDD": 3}], [1060002, {"tuc": 7, "incPDD": 2}],
			[1072001, {"tuc": 5, "incPDD": 2}], [1462001, {"tuc": 7, "incPAD": 29}]]:
		imgs[AvatarRenderer.part_img_path(spec[0])] = {"info": spec[1]}
	return func(path: String) -> Dictionary: return imgs.get(path, {})


## A fresh Lv1 Marksman (322, the Crossbow) as the creation screen makes it; the kit only reads its job.
func _marksman() -> Dictionary:
	return SceneFlow.new_character({}, 322, _loader())


func test_hub_job_322_picks_the_marksman_fixture_and_an_explicit_character_wins() -> void:
	assert_eq(HubTestKit.parse_args(PackedStringArray(["--hub", "--job=322"])),
		{"job": 322, "character": MARKSMAN_FIXTURE, "mesos": 500000})
	assert_eq(HubTestKit.parse_args(PackedStringArray(["--hub", "--job=322", "--character=/x/y.json"])).character, "/x/y.json")
	assert_eq(HubTestKit.parse_args(PackedStringArray(["--hub", "--job=212"])).character, "res://tests/fixtures/characters/fp_arch_mage.json", "F/P is unchanged")
	assert_eq(HubTestKit.parse_args(PackedStringArray(["--hub", "--job=312"])).character, "res://tests/fixtures/characters/bowmaster_t2.json", "so is Bowmaster")


func test_the_marksman_kit_scrolls_are_crossbow_gloves_shoes_att_and_hat_dex_within_the_use_tab() -> void:
	var character := HubTestKit.apply(_marksman(), 500000, _loader())
	var held: Array = character.scrolls.keys().map(func(k: String) -> int: return int(k))
	held.sort()
	var families: Dictionary = DataRepo.load_split("scrolls").families
	var want := []
	for entry: Array in [["crossbow", "ATT"], ["gloves", "ATT"], ["shoes", "ATT"], ["hat", "DEX"]]:
		for id: Variant in families[entry[0]][entry[1]].values():
			want.append(int(id))
	want.sort()
	assert_eq(held, want, "every rate of the four scroll lines a Marksman's gear takes")
	for id: int in [2044600, 2044601, 2044602, 2044604, 2044605]:
		assert_true(id in held, "crossbow ATT scroll %d" % id)
	for id: int in [2044500, 2044501, 2044502, 2044504, 2044505]:
		assert_false(id in held, "bow ATT scroll %d belongs to Bowmaster" % id)
	assert_true(character.scrolls.size() <= Shop.use_stack_limit(), "the stacks fit the Use tab")
	assert_eq(character.job_id, 322, "the rest of the character is untouched")
	assert_eq(CharacterSnapshot.validation_error(character), "")
	for count: Variant in character.scrolls.values():
		assert_eq(int(count), HubTestKit.SCROLL_COUNT)


func test_the_marksman_kit_equipment_holds_a_crossbow_a_hat_gloves_and_a_top() -> void:
	var character := HubTestKit.apply(_marksman(), 500000, _loader())
	assert_eq(character.equipment.inventory.map(func(e: Dictionary) -> int: return int(e.id)), SPARE)
	assert_eq(WeaponInfo.family(1462002), "crossbow", "the spare weapon is a crossbow, a family a Marksman can wield")
	assert_true("crossbow" in DataRepo.load_all().jobs_survivor.jobs["322"].weapon_families)
	if not require_cache():
		return
	var lib := AssetLibrary.get_default()
	for id: int in SPARE:
		var img := lib.img(AvatarRenderer.part_img_path(id))
		assert_true(img != null, "%d is in the cache" % id)
		if img != null:
			assert_eq(Equipment.requirement_error(img.root.get("info", {}), {"job_id": 322}), "", "a Marksman can wear %d" % id)


func test_other_jobs_kits_are_unchanged() -> void:
	assert_eq(HubTestKit.kit_equipment(212), [1002001, 1382001, 1082002, 1040004])
	assert_eq(HubTestKit.kit_equipment(112), [1002001, 1402000, 1082002, 1040010])
	assert_eq(HubTestKit.kit_equipment(312), [1002001, 1452051, 1082002, 1040008])
	assert_eq(HubTestKit.fallback_item(212), 1382001)
	assert_eq(HubTestKit.fallback_item(112), 1302009)
	assert_eq(HubTestKit.fallback_item(312), 1452007)


func test_the_flow_driver_fallback_item_is_a_crossbow_a_marksman_can_hold() -> void:
	var item := HubTestKit.fallback_item(322)
	assert_eq(item, 1462006, "the Lv42 crossbow")
	assert_eq(WeaponInfo.family(item), "crossbow")
	if not require_cache():
		return
	var img := AssetLibrary.get_default().img(AvatarRenderer.part_img_path(item))
	assert_true(img != null)
	if img != null:
		assert_eq(int(img.root.info.reqLevel), 42, "above Lv1: the driver wears it to show a requirement-bearing item")
		assert_eq(Equipment.requirement_error(img.root.get("info", {}), {"job_id": 322}), "")


func test_hub_job_errors_name_the_mismatch_or_the_disabled_job() -> void:
	var fixture: Dictionary = DataRepo.load_json(MARKSMAN_FIXTURE)
	fixture.erase("_doc")
	var fp: Dictionary = DataRepo.load_json("res://tests/fixtures/characters/fp_arch_mage.json")
	fp.erase("_doc")
	var data := DataRepo.load_all()
	var shipped := JobTree.from_data(data.jobs, data.jobs_survivor)
	assert_eq(HubTestKit.job_error({"job": 322}, fixture, shipped), "", "322 ships playable")
	assert_true(HubTestKit.job_error({"job": 322}, fp, shipped).contains("does not match"))
	assert_true(HubTestKit.job_error({"job": 212}, fixture, shipped).contains("does not match"))
	DataRepo.patch = DISABLED.duplicate(true)
	var disabled := DataRepo.jobs(DataRepo.load_all())
	assert_true(HubTestKit.job_error({"job": 322}, fixture, disabled).contains("not playable"))
