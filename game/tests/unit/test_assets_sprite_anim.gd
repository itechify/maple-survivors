extends TestCase
## SpriteAnim/SpriteFrame from synthetic cache nodes: frame order, default delay, a0/a1 rules, frame_at timing.

const AF := preload("res://tests/fixtures/asset_fixtures.gd")


func _img() -> WzImg:
	var root := AF.write_cache()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(root.path_join("Test.wz/Sprite.img.json")))
	return WzImg.new("Test.wz/Sprite.img", parsed, root)


func test_frames_delays_and_default() -> void:
	var w := _img()
	var a := SpriteAnim.from_node(w.node("anim"), w, "Test.wz/Sprite.img/anim", "anim")
	assert_eq(a.frame_count(), 3)
	assert_near(a.frames[0].delay_s, 0.2)
	assert_near(a.frames[1].delay_s, 0.1, 1e-6, "missing delay -> 100 ms (tier C)")
	assert_near(a.frames[2].delay_s, 0.3)
	assert_near(a.total, 0.6)
	assert_near(a.frames[1].start, 0.2)
	assert_eq(a.frames[0].origin, Vector2(2, 4))
	assert_eq(a.frames[0].region, Rect2(0, 0, 4, 4))
	assert_eq(a.frames[0].vec("head"), Vector2(0, -3), "extras keep other children")
	assert_false(a.frames[0].extras.has("delay"), "frame keys are not extras")
	assert_true(a.frames[0].page != null, "page texture resolved")


func test_frame_texture_is_the_canvas_not_the_page() -> void:
	# ASSET_PIPELINE section 6: a frame's `texture` is usable directly in a TextureRect/Sprite2D.
	var w := _img()
	var a := SpriteAnim.from_node(w.node("anim"), w, "Test.wz/Sprite.img/anim", "anim")
	var f := a.frames[1]
	assert_true(f.texture is AtlasTexture, "per-canvas AtlasTexture")
	var at := f.texture as AtlasTexture
	assert_true(at.atlas == f.page, "on the shared page")
	assert_eq(at.region, Rect2(5, 0, 4, 4), "the canvas region")
	assert_eq(f.texture.get_size(), Vector2(4, 4), "canvas size, not the 32x8 page")
	assert_true(f.texture == f.atlas(), "created once")
	var img := f.texture.get_image()
	assert_eq(img.get_size(), Vector2i(4, 4))
	assert_eq(img.get_pixel(1, 1), AF.COLORS[1], "pixels of block 1")
	assert_eq(SpriteFrame.new().texture, null, "no page -> null")


func test_negative_and_zero_delay() -> void:
	var w := _img()
	var a := SpriteAnim.from_node(w.node("negative"), w)
	assert_near(a.frames[0].delay_s, 0.9, 1e-6, "negative delay used by magnitude")
	assert_near(a.frames[1].delay_s, 0.1, 1e-6, "zero delay -> default")


func test_alpha_rules() -> void:
	var w := _img()
	var a := SpriteAnim.from_node(w.node("anim"), w)
	assert_near(a.frames[0].a0, 1.0)
	assert_near(a.frames[0].a1, 1.0, 1e-6, "no a0/a1 -> opaque")
	assert_near(a.frames[2].a0, 1.0)
	assert_near(a.frames[2].a1, 0.0)
	assert_near(a.frames[2].alpha_at(0.15), 0.5, 1e-6, "linear ramp half way")
	assert_near(a.alpha_at(0.3 + 0.15, false), 0.5, 1e-6, "anim-level alpha in frame 2")
	var out := SpriteAnim.from_node(w.node("fadeOut"), w)
	assert_near(out.frames[0].a0, 100.0 / 255.0)
	assert_near(out.frames[0].a1, 155.0 / 255.0, 1e-6, "only a0 -> a1 = 255 - a0")
	var into := SpriteAnim.from_node(w.node("fadeIn"), w)
	assert_near(into.frames[0].a0, 200.0 / 255.0, 1e-6, "only a1 -> a0 = 255 - a1")
	assert_near(into.frames[0].a1, 55.0 / 255.0)


func test_frame_at_loop_and_hold() -> void:
	var w := _img()
	var a := SpriteAnim.from_node(w.node("anim"), w)
	assert_eq(a.index_at(0.0, true), 0)
	assert_eq(a.index_at(0.199, true), 0)
	assert_eq(a.index_at(0.2, true), 1)
	assert_eq(a.index_at(0.35, true), 2)
	assert_eq(a.index_at(0.65, true), 0, "loops after 0.6 s")
	assert_eq(a.index_at(0.85, true), 1)
	assert_eq(a.index_at(0.85, false), 2, "one-shot holds the last frame")
	assert_eq(a.index_at(-1.0, false), 0)
	assert_true(a.frame_at(0.25, true) == a.frames[1])
	assert_true(a.finished(0.6))
	assert_false(a.finished(0.59))


func test_single_canvas_and_uol_frames() -> void:
	var w := _img()
	var s := SpriteAnim.from_node(w.node("single"), w)
	assert_eq(s.frame_count(), 1, "a canvas node is a one-frame animation")
	assert_eq(s.frames[0].z, 5.0)
	assert_eq(s.frames[0].top_left(Vector2(10, 10)), Vector2(8, 8), "pos - origin")
	assert_eq(s.frames[0].top_left(Vector2(10, 10), true), Vector2(8, 8), "flip mirrors around the anchor: x - (w - ox)")
	var u := SpriteAnim.from_node(w.node("uolAnim"), w, "Test.wz/Sprite.img/uolAnim", "uolAnim")
	assert_eq(u.frame_count(), 2, "frame given as a UOL is followed")
	assert_eq(u.frames[0].region, Rect2(0, 0, 4, 4))
	var empty := SpriteAnim.from_node(w.node("info"), w)
	assert_true(empty.is_empty())
	assert_eq(empty.frame_at(0.0, true), null)


func test_numeric_string_delays_read_like_numbers() -> void:
	# Some WZ canvases store the delay as a string ("200": Spear Crusher's effect1-3, the pig mobs); it is the same ms value.
	assert_near(SpriteAnim.delay_seconds("200"), 0.2)
	assert_near(SpriteAnim.delay_seconds("-120"), 0.12, 1e-6, "a negative string is used by magnitude")
	assert_near(SpriteAnim.delay_seconds(" 150 "), 0.15, 1e-6, "surrounding blanks are ignored")
	assert_near(SpriteAnim.delay_seconds(200), 0.2)
	assert_near(SpriteAnim.delay_seconds("0"), 0.1, 1e-6, "a zero string is the default like zero")
	assert_near(SpriteAnim.delay_seconds(""), 0.1, 1e-6, "an empty string is the default")
	assert_near(SpriteAnim.delay_seconds("fast"), 0.1, 1e-6, "text that is not a number is the default")
	assert_near(SpriteAnim.delay_seconds(null), 0.1, 1e-6, "missing is the default")
