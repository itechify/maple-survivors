extends TestCase
## The `--hub --job=132` kit (spec #348, D10 #358): the Dark Knight fixture, spear and pole arm ATT scrolls read from
## scrolls/warrior.json, spare equipment a Dark Knight can wear, and the flow driver's fallback item. The kit lives in
## jobs/dark_knight.json `hub_kit` and HubTestKit resolves it through JobTree.lineage_value.

const FIXTURE := "res://tests/fixtures/characters/dark_knight_t2.json"
const SPARE := [1002001, 1442000, 1082002, 1040010]


func _loader() -> Callable:
	var imgs := {}
	for spec: Array in [[1002001, {"tuc": 5, "incPDD": 3}], [1442000, {"tuc": 7, "incPAD": 32}], [1082002, {"tuc": 5, "incPDD": 1}],
			[1040010, {"tuc": 7, "incPDD": 4}], [1040002, {"tuc": 7, "incPDD": 3}], [1060002, {"tuc": 7, "incPDD": 2}],
			[1072001, {"tuc": 5, "incPDD": 2}], [1432000, {"tuc": 7, "incPAD": 32}]]:
		imgs[AvatarRenderer.part_img_path(spec[0])] = {"info": spec[1]}
	return func(path: String) -> Dictionary: return imgs.get(path, {})


## A fresh Lv1 Dark Knight (132, the plain Spear) as the creation screen makes it; the kit only reads its job.
func _knight() -> Dictionary:
	return SceneFlow.new_character({}, 132, _loader())


func test_the_job_flag_picks_the_dark_knight_fixture_from_its_line_file() -> void:
	assert_eq(HubTestKit.parse_args(PackedStringArray(["--hub", "--job=132"])),
		{"job": 132, "character": FIXTURE, "mesos": 500000})
	assert_eq(HubTestKit.parse_args(PackedStringArray(["--hub", "--job=132", "--character=/x/y.json"])).character, "/x/y.json")
	assert_eq(HubTestKit.parse_args(PackedStringArray(["--hub", "--job=212"])).character, "res://tests/fixtures/characters/fp_arch_mage.json")


func test_the_kit_scrolls_are_exactly_every_rate_of_the_spear_and_pole_arm_att_families() -> void:
	var held := HubTestKit.kit_scrolls(132)
	held.sort()
	var families: Dictionary = DataRepo.load_split("scrolls").families
	var att := []
	for family: String in ["spear", "polearm"]:
		for id: Variant in families[family].ATT.values():
			att.append(int(id))
	att.sort()
	assert_eq(held, att, "independent of the kit file: the ATT scrolls of the two families a Dark Knight wields")
	assert_eq(att, [2044300, 2044301, 2044302, 2044304, 2044305, 2044400, 2044401, 2044402, 2044404, 2044405])
	var character := HubTestKit.apply(_knight(), 500000, _loader())
	var stacks: Array = character.scrolls.keys().map(func(k: String) -> int: return int(k))
	stacks.sort()
	assert_eq(stacks, att)
	assert_true(character.scrolls.size() <= Shop.use_stack_limit(), "the stacks fit the Use tab")
	assert_eq(character.job_id, 132, "the rest of the character is untouched")
	assert_eq(CharacterSnapshot.validation_error(character), "")


func test_the_kit_equipment_is_what_a_dark_knight_can_wear() -> void:
	assert_eq(HubTestKit.kit_equipment(132), SPARE)
	var character := HubTestKit.apply(_knight(), 500000, _loader())
	assert_eq(character.equipment.inventory.map(func(e: Dictionary) -> int: return int(e.id)), SPARE)
	var families: Array = DataRepo.load_all().jobs_survivor.jobs["132"].weapon_families
	assert_true(WeaponInfo.family(1442000) in families, "the spare weapon is a pole arm")
	assert_true(WeaponInfo.family(HubTestKit.fallback_item(132)) in families, "and so is the fallback item")
	if not require_cache():
		return
	var lib := AssetLibrary.get_default()
	for id: int in SPARE + [HubTestKit.fallback_item(132)]:
		var img := lib.img(AvatarRenderer.part_img_path(id))
		assert_true(img != null, "%d is in the cache" % id)
		if img != null:
			assert_eq(Equipment.requirement_error(img.root.get("info", {}), {"job_id": 132}), "", "a Dark Knight can wear %d" % id)


func test_the_fallback_item_is_a_level_forty_spear() -> void:
	assert_eq(HubTestKit.fallback_item(132), 1432005)
	assert_eq(WeaponInfo.family(1432005), "spear")
	if not require_cache():
		return
	var img := AssetLibrary.get_default().img(AvatarRenderer.part_img_path(1432005))
	assert_true(img != null)
	if img != null:
		assert_eq(int(img.root.info.reqLevel), 40, "above Lv1: the flow driver wears it to check the requirement rules")


func test_other_jobs_kits_are_unchanged() -> void:
	assert_eq(HubTestKit.kit_equipment(212), [1002001, 1382001, 1082002, 1040004])
	assert_eq(HubTestKit.kit_equipment(112), [1002001, 1402000, 1082002, 1040010])
	assert_eq(HubTestKit.fallback_item(112), 1302009)


func test_hub_job_errors_for_a_mismatched_character_and_a_disabled_job() -> void:
	var jobs := DataRepo.jobs(DataRepo.load_all())
	var knight := _knight()
	assert_eq(HubTestKit.job_error({"job": 132}, knight, jobs), "")
	assert_true(HubTestKit.job_error({"job": 212}, knight, jobs).contains("does not match the character's job 132"))
	var mage := SceneFlow.new_character({}, 212, _loader())
	assert_true(HubTestKit.job_error({"job": 132}, mage, jobs).contains("does not match the character's job 212"))
	DataRepo.patch = {"jobs_survivor": {"jobs": {"132": {"playable": false}}}}
	var disabled := DataRepo.jobs(DataRepo.load_all())
	DataRepo.patch = {}
	assert_true(HubTestKit.job_error({"job": 132}, knight, disabled).contains("not playable"))
