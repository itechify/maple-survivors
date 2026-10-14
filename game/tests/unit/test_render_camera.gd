extends TestCase
## CameraRig follow math: 58% anchor, dead zone + exponential smoothing, bounds clamp/centring, whole pixels.


func test_desired_center_puts_target_at_58_percent() -> void:
	var view := Vector2(800, 600)
	var c := CameraRig.desired_center(Vector2(100, 200), view)
	assert_eq(c, Vector2(100, 200 - 48))
	var screen_y := view.y * 0.5 + (200.0 - c.y)
	assert_near(screen_y / view.y, 0.58, 1e-6)
	assert_eq(CameraRig.desired_center(Vector2(5, 5), view, 0.5), Vector2(5, 5), "anchor 0.5 = centred")


func test_follow_dead_zone_and_smoothing() -> void:
	var cur := Vector2(0, 0)
	assert_eq(CameraRig.follow(cur, Vector2(8, -8), 1.0 / 60.0, 6.0, 8.0), cur, "inside the dead zone: no move")
	var k := 1.0 - exp(-6.0 / 60.0)
	var moved := CameraRig.follow(cur, Vector2(108, 0), 1.0 / 60.0, 6.0, 8.0)
	assert_near(moved.x, 100.0 * k, 1e-4, "only the excess beyond the dead zone decays")
	assert_eq(moved.y, 0.0)
	var p := cur
	for i in 600:
		p = CameraRig.follow(p, Vector2(-300, 50), 1.0 / 60.0, 6.0, 8.0)
	assert_near(p.x, -292.0, 0.01, "settles at the dead-zone edge")
	assert_near(p.y, 42.0, 0.01)


func test_clamp_and_centre() -> void:
	var b := Rect2(-530, -1278, 2317, 1832)
	var view := Vector2(800, 600)
	assert_eq(CameraRig.clamp_center(Vector2(-1000, 0), b, view), Vector2(-130, 0), "left edge")
	assert_eq(CameraRig.clamp_center(Vector2(5000, 5000), b, view), Vector2(1387, 254), "right/bottom edge")
	var narrow := Rect2(0, 0, 500, 2000)
	assert_eq(CameraRig.clamp_center(Vector2(999, 300), narrow, view).x, 250.0, "narrower than the view: centred")
	assert_eq(CameraRig.clamp_center(Vector2(7, 7), Rect2(), view), Vector2(7, 7), "no bounds")
	var wide := Vector2(1720, 720)
	assert_eq(CameraRig.clamp_center(Vector2(-1000, 0), b, wide).x, -530.0 + 860.0, "wider view")


func test_pixel_center() -> void:
	var c := CameraRig.pixel_center(Vector2(10.4, 20.6), Vector2(800, 600))
	assert_eq(c, Vector2(10, 21))
	var odd := CameraRig.pixel_center(Vector2(10.0, 20.0), Vector2(683, 384))
	var tl := odd - Vector2(683, 384) * 0.5
	assert_eq(tl, tl.round(), "top-left on a whole pixel for odd view sizes")


func test_view_rect_is_what_the_camera_shows() -> void:
	var rig := CameraRig.new()
	rig.target_pos = Vector2(100.4, 200)
	rig.update_camera(1.0 / 60.0)
	var r := rig.view_rect()
	assert_eq(r.size, Vector2(800, 600), "outside the tree: the 800x600 base view")
	assert_eq(r.position, Vector2(-300, -148), "feet at 58%: centre (100, 152), top-left on whole pixels")
	assert_eq(r.position, r.position.round())
	rig.free()
