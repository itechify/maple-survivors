extends TestCase
## Original v83 facts for #241's six later maps. Missing map imgs SKIP individually (s237 predates them).


func test_pig_beach_excludes_iron_hook() -> void:
	_assert_pool(104010001, {"pool_from_life": true, "exclude": [4090000]}, {1210100: 10.0, 1210101: 11.0})


func test_blue_mushroom_forest_pool() -> void:
	_assert_pool(100030001, {"pool_from_life": true}, {2220100: 15.0, 2110200: 8.0})


func test_forest_of_wisdom_pool() -> void:
	_assert_pool(100040100, {"pool_from_life": true}, {210100: 40.0})


func test_forest_of_evil_pool() -> void:
	_assert_pool(100040105, {"pool_from_life": true}, {4230101: 9.0, 5300100: 21.0})


func test_drake_area_pool() -> void:
	_assert_pool(105090310, {"pool_from_life": true}, {6230600: 21.0, 4230100: 5.0, 5130100: 17.0})


func test_cursed_sanctuary_uses_entrance_iv_pool() -> void:
	# tier C: owner #241 uses Sanctuary Entrance IV's canonical weights instead of Jr. Balrog's life entry.
	_assert_pool(105090900, {"pool": {"4230100": 5, "7130100": 2, "7130101": 5}},
		{4230100: 5.0, 7130100: 2.0, 7130101: 5.0})


func _assert_pool(map_id: int, entry: Dictionary, expected: Dictionary) -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	lib.open()
	var path := DataRepo.map_img_path(map_id)
	var img := lib.img(path)
	if img == null:
		skip("map img not imported: %s" % path)
		lib.free()
		return
	var pool := StagePools.resolve(entry, img.root)
	print("  map %d resolved pool: %s" % [map_id, pool])
	assert_eq(pool, expected, "original v83 spawn counts (owner override for Sanctuary)")
	if map_id == 104010001:
		assert_has(StagePools.resolve({"pool_from_life": true}, img.root), 4090000, "Iron Hook exists before exclusion")
	for id: int in pool:
		assert_true(lib.img("Mob.wz/%07d.img" % id) != null, "pool mob %d is imported" % id)
	lib.free()
