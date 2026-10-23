extends TestCase
## Region data and its public setup/boss projection, using synthetic img loaders.


func test_regions_have_three_ordered_maps_and_relative_bosses() -> void:
	var errors := PackedStringArray()
	var file: Dictionary = DataRepo.load_all(DataRepo.DATA_ROOT, errors).stages
	assert_eq(errors, PackedStringArray())
	assert_eq(file.tiers, [["henesys", "ellinia", "perion", "kerning"], ["sleepywood"]])
	var expected := {
		"henesys": [104040000, 104010001, 100030001],
		"ellinia": [101010100, 100040100, 100040105],
		"perion": [102010000, 101030404, 106000101],
		"kerning": [103010000, 103000101, 107000000],
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


## Spec #253: Perion and Kerning City schedule Mano/Stumpy/Iron Hook and King Slime/Shade/Dyle, map 1 on a curve pool
## and maps 2 and 3 on their own v83 life lists without exclusions (the v83 lists have no timed or hidden entries).
func test_perion_and_kerning_boss_order_and_pool_rules() -> void:
	var stages: Dictionary = DataRepo.load_all().stages.stages
	var bosses := {"perion": [2220000, 3220000, 4090000], "kerning": [9300003, 5090000, 6220000]}
	for key: String in bosses:
		var maps: Array = stages[key].maps
		assert_eq(maps.map(func(e: Dictionary) -> int: return int(e.boss.mob_id)), bosses[key], "%s bosses" % key)
		assert_eq(maps[0].get("pool"), "curve", "%s map 1 uses the curve pool" % key)
		for i in [1, 2]:
			assert_eq(maps[i].get("pool_from_life"), true, "%s map %d uses its life list" % [key, i + 1])
			assert_false(maps[i].has("exclude"), "%s map %d excludes nothing" % [key, i + 1])
	var attacks := {2220000: [], 3220000: ["attack1", "attack2"], 4090000: [], 9300003: ["attack1"], 5090000: [],
		6220000: []}
	for key: String in bosses:
		for entry: Dictionary in DataRepo.stage_bosses(stages[key]):
			assert_eq(Array(entry.get("attacks", [])), attacks[int(entry.mob_id)], "%d attacks" % int(entry.mob_id))
			if not entry.get("attacks", []).is_empty():
				assert_eq(float(entry.attack_interval), 8.0, "%d attacks every 8 s" % int(entry.mob_id))
	assert_eq(stages.kerning.maps[1].boss.get("skill_intervals"), {"129": 15.0}, "one Banish per 15 s (spec #253)")


## Spec #253: both new regions run Henesys's numeric curve (rate, alive cap, HP, speed, bursts, elites and the
## post-duration slopes), sampled every 5 s through boss overtime; only the pools differ.
func test_perion_and_kerning_copy_the_henesys_curve() -> void:
	var stages: Dictionary = DataRepo.load_all().stages.stages
	var henesys := SpawnDirector.create(stages.henesys, {})
	for key: String in ["perion", "kerning"]:
		var stage: Dictionary = stages[key]
		for field: String in ["duration", "hard_cap", "map_seconds", "exp_mult", "post_duration_slope", "bursts",
				"elites"]:
			assert_eq(stage.get(field), stages.henesys.get(field), "%s %s" % [key, field])
		assert_false(stage.has("spawn"), "%s: Henesys has no spawn overrides" % key)
		var d := SpawnDirector.create(stage, {})
		for step in range(0, 241):
			var t := step * 5.0
			for field: String in ["rate", "max_alive", "hp", "speed"]:
				assert_near(d.value_at(field, t), henesys.value_at(field, t), 1e-6, "%s %s at %.0f s" % [key, field, t])
			assert_eq(d.burst_count_at(t), henesys.burst_count_at(t), "%s burst size at %.0f s" % [key, t])
			assert_near(d.elite_interval_at(t), henesys.elite_interval_at(t), 1e-6,
				"%s elite interval at %.0f s" % [key, t])


## Spec #253: map 1 opens with two of its own life mobs, adds a third at 2:00 and changes again at 3:30
## (Perion: Dark Stump becomes the most common; Kerning City: Octopus joins).
func test_perion_and_kerning_map_1_pools_follow_the_owner_schedule() -> void:
	var stages: Dictionary = DataRepo.load_all().stages.stages
	var identity := {}
	for id: int in [130100, 130101, 1110101, 210100, 1210102, 1120100]:
		identity[id] = id
	var want := {
		"perion": [[0.0, [130100, 130101]], [119.0, [130100, 130101]], [120.0, [130100, 130101, 1110101]],
			[209.0, [130100, 130101, 1110101]], [210.0, [130100, 130101, 1110101]],
			[299.0, [130100, 130101, 1110101]]],
		"kerning": [[0.0, [130101, 210100]], [119.0, [130101, 210100]], [120.0, [130101, 210100, 1210102]],
			[209.0, [130101, 210100, 1210102]], [210.0, [130101, 210100, 1210102, 1120100]],
			[299.0, [130101, 210100, 1210102, 1120100]]],
	}
	for key: String in want:
		var d := SpawnDirector.create(stages[key], identity)
		for row: Array in want[key]:
			var kinds := Array(d.pool_at(row[0]).get("kinds", PackedInt32Array()))
			kinds.sort()
			var expected: Array = row[1].duplicate()
			expected.sort()
			assert_eq(kinds, expected, "%s pool at %.0f s" % [key, row[0]])
			for id: int in kinds:
				assert_true(stages[key].original_life.has(str(id)), "%s: pool mob %d lives on map 1 in v83" % [key, id])
	var perion := SpawnDirector.create(stages.perion, identity)
	assert_true(_share(perion.pool_at(210.0), 1110101) > _share(perion.pool_at(209.0), 1110101) + 0.2,
		"Perion 3:30: weights shift toward Dark Stump")
	for id: int in [130100, 130101]:
		assert_true(_share(perion.pool_at(210.0), 1110101) > _share(perion.pool_at(210.0), id),
			"Perion: Dark Stump is the most common after 3:30")


## Spec #253 (lead decision): a boss entry may override a mob skill's WZ interval with `skill_intervals`
## {"<skill id>": seconds}; the shipped data validates and malformed overrides are reported.
func test_skill_interval_overrides_validate() -> void:
	var data := DataRepo.load_all()
	assert_eq(DataRepo.stage_map_errors(data.stages), PackedStringArray(), "the shipped Shade override is valid")
	for bad: Variant in [{"129": 0}, {"129": -3}, {"banish": 15}, {"129": "15"}, [15]]:
		var broken: Dictionary = data.stages.duplicate(true)
		broken.stages.kerning.maps[1].boss["skill_intervals"] = bad
		var errors := DataRepo.stage_map_errors(broken)
		assert_eq(errors.size(), 1, "%s is rejected: %s" % [bad, errors])
		if errors.size() == 1:
			assert_true(errors[0].contains("kerning") and errors[0].contains("skill_intervals"), errors[0])


## Weight share of mob `id` in a parsed SpawnDirector pool (0 when absent).
func _share(pool: Dictionary, id: int) -> float:
	var kinds: PackedInt32Array = pool.get("kinds", PackedInt32Array())
	var weights: PackedFloat32Array = pool.get("weights", PackedFloat32Array())
	var total := 0.0
	var own := 0.0
	for i in kinds.size():
		total += weights[i]
		if kinds[i] == id:
			own += weights[i]
	return own / total if total > 0.0 else 0.0
