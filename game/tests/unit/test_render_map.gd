extends TestCase
## MapRenderer on the synthetic map 777: draw order inside a layer, static/animated runs, actor containers,
## backgrounds split into back/front, missing sprites recorded.

const AF := preload("res://tests/fixtures/asset_fixtures.gd")

var lib: AssetLibrary
var map: MapRenderer


func before_each() -> void:
	lib = AssetLibrary.new()
	lib.open(AF.write_cache())
	map = MapRenderer.new()
	map.library = lib
	map.show_portals = false


func after_each() -> void:
	map.free()
	lib.free()


func test_layer_items_order() -> void:
	var items := map.layer_items(AF.map_img(), 0)
	var order: PackedStringArray = []
	for it: Dictionary in items:
		order.append("%s%d" % [it.kind, it.index])
	assert_eq(order, PackedStringArray(["obj1", "obj2", "obj0", "tile1", "tile0"]),
		"objs by (z, index), then tiles by (canvas z, index)")
	assert_true(items[1].flip, "f = 1 kept")
	assert_eq(items[3].path, "Map.wz/Tile/testTile.img/edU/0")
	assert_eq(items[0].path, "Map.wz/Obj/testObj.img/a/b/anim")
	assert_true(MapRenderer.is_animated(items[0].anim))
	assert_false(MapRenderer.is_animated(items[1].anim))


func test_build_runs_actor_layers_and_missing() -> void:
	assert_true(map.load_map(AF.MAP_ID))
	assert_eq(map.stats.objs, 3, "the missing obj is not counted")
	assert_eq(map.stats.tiles, 2)
	assert_eq(map.stats.animated, 1)
	assert_eq(map.stats.backs, 1)
	assert_eq(map.stats.fronts, 1)
	assert_eq(map.missing, PackedStringArray(["Map.wz/Obj/testObj.img/a/b/missing"]))
	var layer0: Node = map.get_node("Layer0")
	assert_eq(layer0.get_child_count(), 3, "animated run, static run, actors")
	assert_true(layer0.get_child(0) is MapDrawList and (layer0.get_child(0) as MapDrawList).animated)
	assert_eq((layer0.get_child(1) as MapDrawList).items.size(), 4, "obj2, obj0, tile1, tile0 in one static run")
	assert_true(layer0.get_child(2) == map.actor_layer(0), "actors drawn after the layer's tiles")
	var names: PackedStringArray = []
	for c in map.get_children():
		names.append(c.name)
	assert_eq(names, PackedStringArray(["Backs", "Layer0", "Layer1", "Layer2", "Layer3", "Layer4", "Layer5", "Layer6",
		"Layer7", "Fronts"]), "backs, layers 0-7, fronts")
	assert_eq(map.bounds, Rect2(-200, -200, 400, 300), "MapBounds: miniMap rect")


func test_backs_resolved() -> void:
	var backs := map.resolve_backs(AF.map_img())
	assert_eq(backs.size(), 2)
	assert_eq(backs[0].path, "Map.wz/Back/testBack.img/back/0")
	assert_eq(backs[0].type, 3)
	assert_false(backs[0].front)
	assert_eq(backs[1].path, "Map.wz/Back/testBack.img/ani/1", "ani = 1 uses the ani node")
	assert_true(backs[1].ani and backs[1].front and backs[1].flip)
	assert_near(backs[1].alpha, 128.0 / 255.0)
	assert_eq(backs[1].anim.frame_count(), 2)


func test_animated_run_advances() -> void:
	map.load_map(AF.MAP_ID)
	var run: MapDrawList = map.get_node("Layer0").get_child(0)
	run.advance(0.05)
	assert_eq(run.items[0].anim.index_at(run.time, true), 0)
	run.advance(0.06)
	assert_eq(run.items[0].anim.index_at(run.time, true), 1, "second frame after 100 ms")


func test_hidden_portal_sparkles_animate_on_a_synthetic_map() -> void:
	var root := AF.map_img()
	root.portal = {
		"0": {"pn": "hidden", "pt": 10.0, "x": 40.0, "y": 0.0},
		"1": {"pn": "exit", "pt": 2.0, "x": 70.0, "y": 0.0},
		"2": {"pn": "invisible", "pt": 1.0, "x": 90.0, "y": 0.0},
	}
	var art := {"$pages": [AF.PAGE], "portal": {"game": {
		"ph": {"default": {"portalContinue": {
			"0": {"$canvas": [0, 0, 0, 4, 4], "origin": {"$v": [2, 4]}, "delay": 100},
			"1": {"$canvas": [0, 5, 0, 4, 4], "origin": {"$v": [2, 4]}, "delay": 100},
		}}},
		"pv": {"0": {"$canvas": [0, 10, 0, 4, 4], "origin": {"$v": [2, 4]}}},
	}}}
	var f := FileAccess.open(lib.root.path_join("Map.wz/MapHelper.img.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(art))
	f.close()
	map.show_portals = true
	map.build(root)
	assert_eq(map.stats.portals, 2, "visible exit and hidden sparkle; type 1 remains invisible")
	var draws := map.get_node("Portals").get_children()
	assert_eq(draws.size(), 2)
	var sparkle: MapDrawList = draws[0]
	assert_eq(sparkle.items[0].pos, Vector2(40, 0), "sparkle drawn at the portal point")
	assert_true(sparkle.items[0].anim.frames[0].page != null, "synthetic sparkle has a drawable atlas")
	map.advance(0.11)
	assert_eq(sparkle.items[0].anim.index_at(sparkle.time, true), 1, "sparkle advances to its second frame")
