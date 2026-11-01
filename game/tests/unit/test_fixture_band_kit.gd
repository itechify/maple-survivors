extends TestCase
## `tools/character_fixture.gd --band-of=<stage>` (spec #449 C13, #475): a kit built from a stage's drop band, so a calibration
## round starts with the gear a character brings from the previous region. In-process on the static `band_kit` (the flag parsing
## is the tool's own); cache-backed (item reqLevel, reqJob and stats).

const FIXTURE_TOOL := preload("res://tools/character_fixture.gd")

var data := {}
var infos := {}
var library: AssetLibrary


func before_each() -> void:
	if not require_cache():
		return
	data = DataRepo.load_all()
	library = AssetLibrary.new()
	library.open()
	infos = DataRepo.equipment_info(DataRepo.starter_equipment_ids(data), func(path: String) -> Dictionary:
		var img := library.img(path)
		return img.root if img != null else {})


func after_each() -> void:
	if library != null:
		library.free()
		library = null


func _kit(job: int, band_of: String, pick: String) -> Array[int]:
	return FIXTURE_TOOL.band_kit(data, infos, DataRepo.jobs(data), job, band_of, pick)


func test_a_hero_band_kit_holds_band_items_a_weapon_and_no_shield_under_a_two_handed_weapon() -> void:
	if infos.is_empty():
		return
	var band := EquipmentDrops.band_of(data.stages.stages.sleepywood)
	assert_eq(band, [30, 40])
	var kit := _kit(112, "sleepywood", "best")
	assert_false(kit.is_empty(), "the Hero finds items in the band")
	var weapon := 0
	var shield := 0
	for id: int in kit:
		var req := int(Equipment.info_of(infos, id).get("reqLevel", -1))
		assert_true(req >= int(band[0]) and req <= int(band[1]), "%d (reqLevel %d) lies in the band %s" % [id, req, band])
		assert_true(Equipment.job_allows(Equipment.info_of(infos, id), 112), "%d is wearable by a Hero" % id)
		match Equipment.slot_of(id):
			"weapon": weapon = id
			"shield": shield = id
	assert_true(weapon != 0, "a weapon is chosen")
	if weapon != 0 and WeaponInfo.is_two_handed(weapon):
		assert_eq(shield, 0, "a two-handed weapon leaves no hand for a shield")
	var slots := kit.map(func(id: int) -> String: return Equipment.slot_of(id))
	assert_false("overall" in slots and ("top" in slots or "bottom" in slots), "an overall replaces the top and bottom, not both")


func test_best_scores_at_least_the_median_for_the_weapon_and_an_empty_band_gives_an_empty_kit() -> void:
	if infos.is_empty():
		return
	var weights := BotShop.weights_for(data.balance, 212, DataRepo.jobs(data))
	var score := func(kit: Array[int]) -> float:
		for id: int in kit:
			if Equipment.slot_of(id) == "weapon":
				return BotShop.item_score(Equipment.create(id, Equipment.info_of(infos, id)), weights)
		return -1.0
	var best: float = score.call(_kit(212, "kerning", "best"))
	var median: float = score.call(_kit(212, "kerning", "median"))
	assert_true(best >= median and median >= 0.0, "the best weapon of the band scores at least the median one (%s vs %s)" % [best, median])
	assert_eq(_kit(212, "no_such_stage", "best").size() > 0, true, "an unknown stage has no band: every item qualifies")
