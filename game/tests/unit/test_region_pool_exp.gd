extends TestCase
## Spec #449 C14 (#476), from the Zipangu review (#500): the ordinary monsters of every region from step 6 pay close to the
## level curve's EXP at their own level (tests/region_checks.gd). Cache-backed: SKIPs without the asset cache.

const RC := preload("res://tests/region_checks.gd")


func test_the_checked_regions_are_the_progression_from_step_six() -> void:
	var data := DataRepo.load_all()
	var keys: Array = data.stages.progression.slice(RC.EXP_CHECK_FROM_STEP - 1)
	assert_eq(keys.size(), 11, "Ludibrium to the Temple of Time")
	assert_eq(keys[0], "ludibrium")
	assert_eq(keys[-1], "temple_of_time")


func test_pool_mobs_of_every_region_pay_close_to_the_level_curves_exp() -> void:
	if not require_cache():
		return
	var data := DataRepo.load_all()
	var lib := AssetLibrary.new()
	lib.open()
	for key: String in data.stages.progression.slice(RC.EXP_CHECK_FROM_STEP - 1):
		var ids := RC.ordinary_mob_ids(data, lib, key)
		if ids.is_empty():
			skip("%s: a map img is not imported" % key)
			continue
		assert_eq(RC.exp_ratio_errors(data, lib, key), PackedStringArray(), "%s: ordinary mobs near the EXP curve" % key)
	lib.free()


func test_neighbours_of_a_region_in_a_progression() -> void:
	assert_eq(RC.neighbours(["a", "b", "c"], "b"), ["a", "c"])
	assert_eq(RC.neighbours(["a", "b", "c"], "a"), ["", "b"])
	assert_eq(RC.neighbours(["a", "b", "c"], "c"), ["b", ""])
	assert_eq(RC.neighbours(["a", "b"], "z"), [])
