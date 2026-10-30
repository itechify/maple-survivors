extends TestCase
## Presentation of the boss statuses of #458: the Darkness 121 overlay's geometry, fade and gradient, and (with the asset cache)
## the `affected` art above the character for each status through RunScene.
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0

var lib: AssetLibrary
var scene: RunScene


func after_each() -> void:
	if scene != null:
		scene.free()
		scene = null
	if lib != null:
		lib.free()
		lib = null


func _area(rects: Array[Rect2]) -> float:
	var sum := 0.0
	for r in rects:
		sum += r.get_area()
	return sum


## The flat rects and the gradient square tile the screen exactly, whether the lit circle is inside it, at a corner or off it.
func test_flat_rects_and_gradient_square_tile_the_screen() -> void:
	var view := Vector2(800, 600)
	for center in [Vector2(400, 300), Vector2(60, 40), Vector2(790, 590), Vector2(-500, 300), Vector2(400, 900)]:
		var rects := DarknessOverlay.flat_rects(view, center)
		var square := DarknessOverlay.lit_square(center).intersection(Rect2(Vector2.ZERO, view))
		var square_area := maxf(0.0, square.size.x) * maxf(0.0, square.size.y) if square.has_area() else 0.0
		assert_near(_area(rects) + square_area, view.x * view.y, 0.01, "tiles the view at %s" % center)
		for r in rects:
			assert_false(r.intersects(square, false) and square_area > 0.0 and r.get_area() > 0.0 and r.intersection(square).has_area(),
				"flat rect does not overlap the gradient at %s" % center)
	var centred := DarknessOverlay.flat_rects(view, Vector2(400, 300))
	assert_eq(centred.size(), 4, "a lit square inside the view leaves four rects")


## The lit circle is clear in the middle and reaches the full dimming at its outer radius; the texture is that gradient.
func test_gradient_is_clear_at_the_avatar_and_dim_at_the_edge() -> void:
	assert_eq(DarknessOverlay.alpha_at(0.0), 0.0)
	assert_eq(DarknessOverlay.alpha_at(DarknessOverlay.LIT_RADIUS), 0.0)
	assert_eq(DarknessOverlay.alpha_at(DarknessOverlay.DIM_RADIUS), DarknessOverlay.DIM_ALPHA)
	var mid := DarknessOverlay.alpha_at((DarknessOverlay.LIT_RADIUS + DarknessOverlay.DIM_RADIUS) * 0.5)
	assert_true(mid > 0.0 and mid < DarknessOverlay.DIM_ALPHA, "soft edge")
	var image := DarknessOverlay.make_image()
	var half := DarknessOverlay.TEXTURE_SIZE / 2
	assert_eq(image.get_pixel(half, half).a, 0.0, "clear at the centre")
	assert_near(image.get_pixel(0, half).a, DarknessOverlay.DIM_ALPHA, 0.02, "fully dim at the square's edge")
	assert_near(image.get_pixel(0, 0).a, DarknessOverlay.DIM_ALPHA, 0.001, "and in its corners, matching the flat rects")


## The overlay is hidden until the status is active, fades in at its speed, follows the centre and fades out.
func test_overlay_fades_in_and_out_and_follows_the_avatar() -> void:
	var o := DarknessOverlay.new()
	var view := Vector2(800, 600)
	o.update(false, Vector2(100, 100), view, DT)
	assert_false(o.visible, "hidden with no status")
	o.update(true, Vector2(100, 100), view, DT)
	assert_true(o.visible)
	assert_near(o.strength, DarknessOverlay.FADE_SPEED * DT, 1e-6)
	for tick in 60:
		o.update(true, Vector2(300 + tick, 200), view, DT)
	assert_eq(o.strength, 1.0)
	assert_eq(o.center, Vector2(359, 200), "the lit circle follows")
	for tick in 60:
		o.update(false, o.center, view, DT)
	assert_eq(o.strength, 0.0)
	assert_false(o.visible, "hidden again after the fade")
	o.free()


## Through RunScene: each status loops its level's `affected` art while it lasts and stops with it; Darkness also dims the
## screen. Needs the asset cache.
func test_each_status_shows_its_art_and_darkness_dims_the_screen() -> void:
	if not require_cache():
		return
	lib = AssetLibrary.new()
	lib.open()
	var sfx := (Engine.get_main_loop() as SceneTree).root.get_node("Sfx") as AudioService
	var previous_library := sfx.library
	sfx.library = lib
	scene = (load(RunScene.SCENE_PATH) as PackedScene).instantiate()
	scene.library = lib
	var options := {"use_flow": false}
	scene.configure("henesys", 22, options)
	(Engine.get_main_loop() as SceneTree).current_scene.add_child(scene)
	var data := scene.data.duplicate(true)
	data.balance.bosses.teleport_stall = 10000.0
	RF.set_bosses(data.stages.stages.henesys, [{"mob_id": 2220000, "time": 0.0}])
	for keyframe: Dictionary in data.stages.stages.henesys.keyframes:
		keyframe.rate = 0
		keyframe.max_alive = 0
	var setup := DataRepo.build_setup(data, "henesys", 22, Vector2(800, 600),
		func(p: String) -> Dictionary: return lib.img(p).root if lib.img(p) != null else {}, lib.mob_root)
	scene.world = RunWorld.new(setup)
	var w := scene.world
	w.god = true
	for i in 5:
		scene.advance_frame(DT)
	var levels := {121: 1, 122: 10, 124: 1, 128: 7, 132: 2}
	for id: int in levels:
		var path := "Skill.wz/MobSkill.img/%d/level/%d/affected" % [id, levels[id]]
		assert_true(lib.anim(path).frames.size() > 0, "%d has cached affected art" % id)
		w.mob_skills.statuses.apply(id, w.time, 2.0, {"visual": path, "boss_index": 0}, false)
		scene._on_boss_skill({"mob": 0, "mob_id": 2220000, "skill_id": id, "level": levels[id], "pos": Vector2.ZERO,
			"facing": 1, "action": "skill1", "duration": 2.0, "effect": "", "player_effect": path, "targets": [],
			"recipient_effect": "", "summon_effect": ""})
		scene.advance_frame(DT)
		assert_true(scene._status_fx.has(id), "%d: art placed above the character" % id)
		assert_true(scene.fx.active_count() >= 1)
		w.mob_skills.statuses.clear(id)
		scene.advance_frame(DT)
		assert_false(scene._status_fx.has(id), "%d: art removed with the status" % id)
	assert_false(scene.darkness.visible, "no dimming without Darkness")
	w.mob_skills.statuses.apply(121, w.time, 5.0, {"visual": ""}, false)
	for i in 30:
		scene.advance_frame(DT)
	assert_true(scene.darkness.visible and scene.darkness.strength > 0.9, "Darkness dims the screen")
	var body := scene.avatar.get_global_transform_with_canvas().origin - Vector2(0.0, w.cast_height)
	assert_near(scene.darkness.center.distance_to(body), 0.0, 2.0, "the lit circle is on the avatar")
	assert_eq(scene.darkness.get_parent().layer, RunScene.DARKNESS_LAYER)
	assert_true(scene.darkness.get_parent().layer < scene.hud.layer, "below the HUD")
	w.mob_skills.statuses.clear(121)
	for i in 40:
		scene.advance_frame(DT)
	assert_false(scene.darkness.visible, "gone after the status")
	assert_eq(lib.missing, PackedStringArray(), "no missing art")
	sfx.library = previous_library
