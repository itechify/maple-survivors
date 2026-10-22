extends TestCase
## Per-map ordinary mob pools: canonical life counts, owner exclusions and explicit overrides (#245).

const RF := preload("res://tests/fixtures/run_fixtures.gd")


func test_life_pool_counts_visible_mobs_and_applies_exclusions() -> void:
	# Cache JSON: life is a keyed object, ids are padded strings, numeric fields parse as floats.
	var img := {"life": {
		"0": {"type": "m", "id": "01210100", "hide": 0.0},
		"1": {"type": "m", "id": "1210100"},
		"2": {"type": "m", "id": "01210101", "hide": 0.0},
		"3": {"type": "m", "id": "01210101", "hide": 1.0},
		"4": {"type": "n", "id": "1210100"},
		"5": {"type": "m", "id": "4090000", "hide": 0.0},
	}}
	assert_eq(StagePools.resolve({"pool_from_life": true, "exclude": [4090000.0]}, img),
		{1210100: 2.0, 1210101: 1.0})


func test_explicit_sanctuary_pool_overrides_the_life_list_and_curve_is_unresolved() -> void:
	var img := {"life": {"0": {"type": "m", "id": "8130100"}}}
	var entry := {"pool": {"4230100": 5, "7130100": 2, "7130101": 5}}
	assert_eq(StagePools.resolve(entry, img), {4230100: 5.0, 7130100: 2.0, 7130101: 5.0})
	assert_eq(StagePools.resolve({"pool": "curve"}, img), {})
	assert_eq(StagePools.resolve({"pool_from_life": true}, {}), {})


func test_preload_ids_cover_all_resolved_map_pools_once_in_order() -> void:
	var stage := {"maps": [
		{"pool": "curve"}, {"pool_from_life": true, "exclude": [4090000]},
		{"pool": {"7130101": 5, "1210100": 1}},
	]}
	var imgs := [{}, {"life": {
		"0": {"type": "m", "id": "1210101"}, "1": {"type": "m", "id": "1210101"},
		"2": {"type": "m", "id": "4090000"}, "3": {"type": "m", "id": "1210100"},
	}}]
	assert_eq(StagePools.stage_pool_ids(stage, imgs), [1210100, 1210101, 7130101])
	assert_eq(StagePools.stage_pool_ids({}, imgs), [])


func test_curve_map_holds_its_last_pool_before_the_next_map_boundary() -> void:
	var stage := {"map_seconds": 300, "maps": [{"pool": "curve"}, {"pool": "curve"}],
		"keyframes": [
			{"t": 0, "pool": {"100100": 1}, "rate": 1},
			{"t": 240, "pool": {"100101": 2}, "rate": 2},
			{"t": 300, "pool": {"1210100": 3}, "rate": 4},
			{"t": 600, "pool": {"210100": 4}, "rate": 8},
		]}
	var d := SpawnDirector.create(stage, {100100: 0, 100101: 1, 1210100: 2, 210100: 3})
	assert_eq(d.pool_at(450.0).kinds, PackedInt32Array([1]), "map 1 excludes t >= 300")
	assert_near(d.rate_at(450.0), 6.0, 1e-6, "later keyframes still drive pacing")
	assert_eq(d.pool_at(0.0).kinds, PackedInt32Array([0]), "opening still progresses")
	# Legacy stages keep their pool progression even after 5:00.
	stage.erase("maps")
	var legacy := SpawnDirector.create(stage, {100100: 0, 100101: 1, 1210100: 2, 210100: 3})
	assert_eq(legacy.pool_at(450.0).kinds, PackedInt32Array([2]))


func test_active_map_pool_replaces_curve_and_drops_unavailable_kinds() -> void:
	var stage := {"maps": [{"pool": "curve"}, {"pool_from_life": true}, {"pool": "curve"}],
		"map_seconds": 300, "keyframes": [
			{"t": 0, "pool": {"100100": 1}}, {"t": 300, "pool": {"100101": 1}},
			{"t": 900, "pool": {"210100": 1}},
		]}
	var d := SpawnDirector.create(stage, {100100: 0, 100101: 1, 1210100: 2, 210100: 3})
	d.map_pools = [{}, {1210100: 7.0, 4090000: 10.0, 100100: 0.0}, {}]
	d.map_index = 1
	assert_eq(d.pool_at(450.0).kinds, PackedInt32Array([2]))
	assert_eq(d.pool_at(450.0).weights, PackedFloat32Array([7.0]))
	var rng := RandomNumberGenerator.new()
	rng.seed = 245
	assert_eq(d.pick_kind(450.0, rng), 2)
	d.map_index = 2
	assert_eq(d.pool_at(1000.0).kinds, PackedInt32Array([1]), "map 3 curve excludes t >= 900")


func test_world_uses_the_active_map_pool_for_ordinary_burst_and_elite_spawns() -> void:
	var data := RF.quiet_data()
	var stage: Dictionary = data.stages.stages.quiet
	stage.keyframes = [{"t": 0, "pool": {"100100": 1}, "rate": 60, "max_alive": 10}]
	stage.maps = [{"pool": "curve"}, {"pool_from_life": true}]
	stage.map_seconds = 300
	stage.bursts = {"first": 0, "every": 60, "count_min": 3, "count_max": 3}
	stage.elites = {"first": 0, "every": 60, "hp_mult": 8}
	var setup := RF.setup("quiet", 245, data)
	setup.map_img = RF.map_from_segments([{"x1": 0, "y1": 0, "x2": 6000, "y2": 0}])
	setup.map_imgs = [setup.map_img, {"life": {"0": {"type": "m", "id": "100101"}}}]
	var w := RunWorld.new(setup)
	w.director.map_index = 1
	w.time = 450.0
	RF.place_player(w, 3000.0, -5.0)
	w.drain_events()
	w.director.step(1.0 / 60.0, w)
	var spawned: Array = []
	for e: Dictionary in w.drain_events():
		if e.type == "mob_spawned":
			spawned.append([int(e.mob_id), bool(e.elite)])
	assert_eq(spawned, [[100101, false], [100101, false], [100101, false], [100101, false], [100101, true]],
		"one ordinary, three burst mobs and one elite, all from map 2")
	assert_true(w.warnings.is_empty(), str(w.warnings))


func test_data_repo_preloads_life_pool_ids_without_changing_legacy_rosters() -> void:
	var data := {"stages": {"stages": {"pools": {
		"keyframes": [{"t": 0, "pool": {"100100": 1}}],
		"maps": [{"pool": "curve"}, {"pool_from_life": true, "exclude": [4090000]}],
	}}}}
	var imgs := [{}, {"life": {"0": {"type": "m", "id": "1210101"},
		"1": {"type": "m", "id": "4090000"}}}]
	assert_eq(DataRepo.stage_mob_ids(data, "pools", {}, {}, imgs), PackedInt32Array([100100, 1210101]))
	data.stages.stages.pools.erase("maps")
	assert_eq(DataRepo.stage_mob_ids(data, "pools", {}, {}, imgs), PackedInt32Array([100100]))


func test_setup_preloads_life_mobs_from_every_map_before_the_round() -> void:
	var data := RF.quiet_data()
	data.stages.stages.quiet.maps = [
		{"map_id": 1, "pool": "curve"}, {"map_id": 2, "pool_from_life": true},
	]
	var setup := DataRepo.build_setup(data, "quiet", 245, Vector2(800, 600),
		func(path: String) -> Dictionary:
			if path == DataRepo.map_img_path(2):
				return {"life": {"0": {"type": "m", "id": "1210101"}}}
			return {},
		func(_id: int) -> Dictionary: return {"info": {}})
	assert_has(setup.mob_imgs, 1210101, "a life-only mob on map 2 is loaded up front")
