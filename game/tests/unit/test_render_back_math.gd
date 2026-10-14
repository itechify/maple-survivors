extends TestCase
## Background placement math (BackMath): tiling by type, parallax, auto-scroll, tile coverage.


func test_tiling_and_scroll_by_type() -> void:
	var tx := [false, true, false, true, true, false, true, true]
	var ty := [false, false, true, true, false, true, true, true]
	var sx := [false, false, false, false, true, false, true, false]
	var sy := [false, false, false, false, false, true, false, true]
	for t in 8:
		assert_eq(BackMath.tiles_x(t), tx[t], "tiles_x type %d" % t)
		assert_eq(BackMath.tiles_y(t), ty[t], "tiles_y type %d" % t)
		assert_eq(BackMath.scrolls_x(t), sx[t], "scrolls_x type %d" % t)
		assert_eq(BackMath.scrolls_y(t), sy[t], "scrolls_y type %d" % t)


func test_parallax_screen_and_world_locked() -> void:
	var view := Vector2(800, 600)
	var cam := Vector2(1000, 500)
	var pos := Vector2(10, 20)
	assert_eq(BackMath.anchor_screen(pos, Vector2(0, 0), 0, cam, view, 0.0), Vector2(410, 320), "r = 0: fixed on screen")
	assert_eq(BackMath.anchor_screen(pos, Vector2(-100, -100), 0, cam, view, 0.0), Vector2(-590, -180),
		"r = -100: fixed in the world (pos - cam + view/2)")
	assert_eq(BackMath.anchor_screen(pos, Vector2(-50, 0), 0, cam, view, 0.0), Vector2(-90, 320), "half speed")
	assert_eq(BackMath.anchor_screen(pos, Vector2(-5, 0), 0, Vector2(1001, 0), view, 0.0), Vector2(359, 320),
		"floored: 10 - 50.05 + 400")
	# Moving the camera by d moves an r layer on screen by d * r / 100.
	var a := BackMath.anchor_screen(pos, Vector2(-8, -8), 1, Vector2(0, 0), view, 0.0)
	var b := BackMath.anchor_screen(pos, Vector2(-8, -8), 1, Vector2(100, 200), view, 0.0)
	assert_eq(b - a, Vector2(-8, -16))


func test_auto_scroll() -> void:
	var view := Vector2(800, 600)
	var pos := Vector2(10, 20)
	# type 4: x scrolls at rx * 5 px/s with no camera term (wrapped by the period), y is parallax.
	var p := BackMath.anchor_screen(pos, Vector2(-5, -10), 4, Vector2(300, 100), view, 2.0, Vector2(100, 50))
	assert_eq(p, Vector2(10 + 50 + 400, 20 - 10 + 300), "x: fposmod(-50, 100) = 50; y: 100 * -10 / 100")
	var q := BackMath.anchor_screen(pos, Vector2(-5, -10), 4, Vector2(300, 100), view, 2.1, Vector2(100, 50))
	assert_eq(q.x - p.x, -3.0, "moves left 25 px/s for rx = -5 (0.1 s: 460 -> floor(457.5))")
	# type 7: y scrolls at ry * 5, x is parallax.
	var r := BackMath.anchor_screen(pos, Vector2(-10, 3), 7, Vector2(100, 999), view, 1.0)
	assert_eq(r, Vector2(10 - 10 + 400, 20 + 15 + 300))
	assert_eq(BackMath.SCROLL_PX_PER_UNIT, 5.0, "tier B constant")


func test_period_defaults_to_canvas() -> void:
	assert_eq(BackMath.period(Vector2(0, 0), Vector2(256, 128)), Vector2(256, 128))
	assert_eq(BackMath.period(Vector2(400, 0), Vector2(256, 128)), Vector2(400, 128))


func test_tile_starts_cover_the_view() -> void:
	assert_eq(BackMath.tile_starts(-30, 100, 120, 300, true), PackedFloat32Array([-30, 70, 170, 270]))
	assert_eq(BackMath.tile_starts(250, 100, 50, 300, true), PackedFloat32Array([50, 150, 250]),
		"copies to the left of the anchor are included, the one ending exactly at 0 is not")
	assert_eq(BackMath.tile_starts(-1000, 256, 256, 800, true), PackedFloat32Array([-232, 24, 280, 536, 792]),
		"800 px with 256 px tiles: partial copies at both ends")
	var starts := BackMath.tile_starts(-12345.0, 548.0, 300.0, 1720.0, true)
	assert_true(starts[0] + 300.0 > 0.0 and starts[0] <= 0.0 + 548.0, "first copy reaches into the view")
	assert_true(starts[starts.size() - 1] < 1720.0 and starts[starts.size() - 1] + 548.0 >= 1720.0, "last copy")
	assert_eq(BackMath.tile_starts(900, 100, 50, 800, false), PackedFloat32Array(), "untiled and off-screen")
	assert_eq(BackMath.tile_starts(-10, 100, 50, 800, false), PackedFloat32Array([-10]), "untiled, visible")
