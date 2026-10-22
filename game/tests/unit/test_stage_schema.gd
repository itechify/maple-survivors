extends TestCase
## Region data and its public setup/boss projection, using synthetic img loaders.


func test_regions_have_three_ordered_maps_and_relative_bosses() -> void:
	var errors := PackedStringArray()
	var file: Dictionary = DataRepo.load_all(DataRepo.DATA_ROOT, errors).stages
	assert_eq(errors, PackedStringArray())
	assert_eq(file.tiers, [["henesys", "ellinia"], ["sleepywood"]])
	var expected := {
		"henesys": [104040000, 104010001, 100030001],
		"ellinia": [101010100, 100040100, 100040105],
		"sleepywood": [105050400, 105090310, 105090900],
	}
	for key: String in expected:
		assert_has(file.stages, key)
		if not file.stages.has(key):
			continue
		var stage: Dictionary = file.stages[key]
		assert_false(stage.has("map_id"))
		assert_false(stage.has("bosses"))
		assert_eq(stage.get("map_seconds"), 300)
		assert_eq(stage.get("maps", []).size(), 3)
		for i in stage.get("maps", []).size():
			assert_eq(stage.maps[i].map_id, expected[key][i])
			assert_eq(stage.maps[i].boss.time, 300)


func test_stage_api_projects_absolute_bosses_and_keeps_copies_detached() -> void:
	var data := DataRepo.load_all()
	var stage: Dictionary = data.stages.stages.henesys
	var bosses: Array = DataRepo.stage_bosses(stage)
	assert_eq(bosses.size(), 3)
	assert_eq(bosses[0].time, 300)
	assert_eq(bosses[1].time, 600)
	assert_eq(bosses[2].time, 900)
	assert_eq(bosses[1].map_time, 300)
	assert_eq(bosses[1].map_index, 1)
	bosses[1].attacks.append("synthetic")
	assert_eq(stage.maps[1].boss.attacks, ["attack1"])
	assert_eq(DataRepo.stage_maps(data, "henesys"), stage.maps)


func test_setup_loads_aligned_maps_and_records_absent_maps() -> void:
	var data := DataRepo.load_all()
	var missing := PackedStringArray()
	var setup := DataRepo.build_setup(data, "henesys", 7, Vector2(800, 600),
		func(path: String) -> Dictionary:
			return {"synthetic": path} if path == DataRepo.map_img_path(104040000) else {},
		func(_id: int) -> Dictionary: return {}, missing)
	assert_eq(setup.map_imgs.size(), 3)
	assert_eq(setup.map_img, {"synthetic": DataRepo.map_img_path(104040000)})
	assert_eq(setup.map_imgs[1], {})
	assert_eq(setup.map_imgs[2], {})
	assert_has(missing, DataRepo.map_img_path(104010001))
	assert_has(missing, DataRepo.map_img_path(100030001))


func test_missing_or_empty_map_lists_report_validation_errors() -> void:
	var data := DataRepo.load_all()
	data.stages.stages.henesys.erase("maps")
	data.stages.stages.ellinia.maps = []
	var errors := DataRepo.stage_map_errors(data.stages)
	assert_eq(errors.size(), 2)
	assert_true(errors[0].contains("henesys") and errors[0].contains("maps"))
	assert_true(errors[1].contains("ellinia") and errors[1].contains("maps"))


func test_legacy_keys_resolve_in_public_stage_and_flag_entry_points() -> void:
	var expected := {"henesys_hg1": "henesys", "tree_that_grew_1": "ellinia", "dark_cave": "sleepywood"}
	var data := DataRepo.load_all()
	for old: String in expected:
		assert_eq(DataRepo.canonical_stage_key(old), expected[old])
		assert_eq(DataRepo.stage_maps(data, old), DataRepo.stage_maps(data, expected[old]))
		assert_eq(SceneFlow.parse_run_args(["--run=" + old]).run, expected[old])
		assert_eq(SceneFlow.parse_flags(["--stage=" + old]).stage, expected[old])
	assert_eq(DataRepo.canonical_stage_key("synthetic"), "synthetic")


func test_owner_opening_and_map_pool_declarations_are_loaded_as_plain_data() -> void:
	var data := DataRepo.load_all()
	var henesys: Dictionary = data.stages.stages.henesys
	assert_eq(henesys.keyframes.slice(0, 4).map(func(frame: Dictionary) -> Array:
		return [frame.t, frame.rate, frame.max_alive]),
		[[0.0, 0.25, 6.0], [120.0, 0.55, 11.0], [180.0, 0.75, 15.0], [240.0, 1.0, 20.0]])
	assert_eq(henesys.maps[0].pool, "curve")
	assert_eq(henesys.maps[1].pool_from_life, true)
	assert_eq(henesys.maps[1].exclude, [4090000.0])
	assert_eq(data.stages.stages.sleepywood.maps[2].pool, {"4230100": 5.0, "7130100": 2.0, "7130101": 5.0})
	assert_has(DataRepo.stage_mob_ids(data, "sleepywood"), 4230100)
