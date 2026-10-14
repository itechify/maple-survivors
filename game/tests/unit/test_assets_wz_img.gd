extends TestCase
## WzImg tree access on a synthetic cache: node lookup, $canvas -> region/page, $uol following.

const AF := preload("res://tests/fixtures/asset_fixtures.gd")


func _img() -> WzImg:
	var root := AF.write_cache()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(root.path_join("Test.wz/Sprite.img.json")))
	return WzImg.new("Test.wz/Sprite.img", parsed, root)


func test_node_lookup() -> void:
	var w := _img()
	assert_eq(w.pages, PackedStringArray(["Test.wz/Sprite.img.0.png"]))
	assert_eq(w.node("info/speed"), -65.0, "numbers parse as float")
	assert_eq(w.node("info/name"), "sprite")
	assert_true(w.node("anim") is Dictionary)
	assert_eq(w.node("anim/0/delay"), 200.0)
	assert_eq(w.node("anim/9"), null, "missing child")
	assert_eq(w.node("info/speed/deeper"), null, "walking into a leaf")
	assert_eq(w.node(""), w.root, "empty path is the root")


func test_canvas_region_and_page() -> void:
	var w := _img()
	var c: Dictionary = w.node("anim/2")
	assert_true(WzImg.is_canvas(c))
	assert_false(WzImg.is_canvas(w.node("anim")))
	assert_eq(WzImg.region(c), Rect2(10, 0, 4, 4))
	assert_eq(WzImg.page_of(c), 0)
	assert_eq(WzImg.vec(c.origin), Vector2(0, 0))
	assert_eq(WzImg.vec(w.node("anim/0/head")), Vector2(0, -3))
	assert_eq(WzImg.vec(null, Vector2(7, 8)), Vector2(7, 8), "fallback")
	# The region really addresses block 2 of the generated page.
	var page := Image.load_from_file(w.cache_root.path_join(w.pages[0]))
	var r := WzImg.region(c)
	assert_eq(page.get_pixel(int(r.position.x) + 1, int(r.position.y) + 1), AF.COLORS[2], "block 2 colour")
	var tex := w.texture(c)
	assert_true(tex != null, "AtlasTexture created")
	if tex != null:
		assert_eq(tex.region, Rect2(10, 0, 4, 4))
		assert_true(w.texture(c) == tex, "cached")
		assert_true(tex.atlas == w.page_texture(0), "atlas page shared")
	assert_eq(w.page_texture(5), null, "out-of-range page")


func test_uol_follow() -> void:
	var w := _img()
	assert_eq(WzImg.region(w.node("alias")), Rect2(5, 0, 4, 4), "sibling UOL -> anim/1")
	assert_eq(WzImg.region(w.node("group/ref")), Rect2(10, 0, 4, 4), "'..' UOL -> anim/2")
	assert_eq(WzImg.region(w.node("group/chain")), Rect2(10, 0, 4, 4), "UOL to a UOL")
	assert_eq(w.node("group/ref/delay"), 300.0, "UOL followed mid-path")
	assert_eq(WzImg.region(w.node("uolAnim/0")), Rect2(0, 0, 4, 4), "frame UOL")
	assert_eq(w.node("broken"), null, "'..' above the root")


func test_uol_cycle_stops() -> void:
	var tree := {"a": {"$uol": "b"}, "b": {"$uol": "a"}}
	assert_eq(WzImg.resolve(tree, "a"), null)
