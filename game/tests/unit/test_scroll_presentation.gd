extends TestCase
## The scroll result presentation (#110) against the real asset cache (SKIP without it): a scroll_used event plays
## Effect.wz/BasicEff.img/Enchant Success or Failure over the character in a layer that is not frozen with the held
## world, and nothing is missing from the cache (the effect, the sounds, a scroll's icon and name).

const DT := 1.0 / 60.0

var lib: AssetLibrary
var scene: RunScene


func before_each() -> void:
	lib = AssetLibrary.new()
	lib.open()


func after_each() -> void:
	if scene != null and is_instance_valid(scene):
		scene.free()
	scene = null
	lib.free()


func _make() -> RunScene:
	var s: RunScene = (load(RunScene.SCENE_PATH) as PackedScene).instantiate()
	s.library = lib
	s.configure("henesys", 5, {"use_flow": false})
	var tree := Engine.get_main_loop() as SceneTree
	(tree.current_scene if tree.current_scene != null else tree.root).add_child(s)
	return s


func test_result_paths_follow_the_ticket() -> void:
	assert_eq(EnchantFx.anim_path("success"), "Effect.wz/BasicEff.img/Enchant/Success")
	assert_eq(EnchantFx.anim_path("failure"), "Effect.wz/BasicEff.img/Enchant/Failure")
	assert_eq(EnchantFx.anim_path("destroyed"), "Effect.wz/BasicEff.img/Enchant/Failure")
	assert_eq(EnchantFx.sound_path("success"), "Sound.wz/Game.img/EnchantSuccess")
	assert_eq(EnchantFx.sound_path("failure"), "Sound.wz/Game.img/EnchantFailure")
	assert_eq(EnchantFx.sound_path("destroyed"), "Sound.wz/Game.img/EnchantFailure")


func test_every_result_plays_its_real_wz_animation_and_sound() -> void:
	if not require_cache():
		return
	var fx := EnchantFx.new()
	fx.renderer.library = lib
	var root := (Engine.get_main_loop() as SceneTree).current_scene
	root.add_child(fx)
	for result: String in ["success", "failure", "destroyed"]:
		assert_true(fx.play(result, Vector2(100, 100)) >= 0, "%s animation exists in the cache" % result)
		assert_true(lib.sound(EnchantFx.sound_path(result)) != null, "%s sound exists" % result)
	assert_eq(fx.renderer.active_count(), 3)
	fx.renderer.advance(3.0)
	assert_eq(fx.renderer.active_count(), 0, "the effects end")
	fx.free()


func test_a_scroll_used_event_shows_the_effect_over_the_held_run() -> void:
	if not require_cache():
		return
	scene = _make()
	scene.advance_frame(DT)
	scene.world.grant_scrolls(2040400, 3)
	scene.world.equipment.worn.top.slots = 3
	scene.world.drain_events()
	assert_eq(scene.world.use_scroll(2040400, "top"), "")
	scene.handle_events(scene.world.drain_events())
	assert_eq(scene.enchant.renderer.active_count(), 1, "the Enchant effect plays")
	scene._freeze(true)
	assert_false(scene.world_root.is_ancestor_of(scene.enchant), "the effect is not under the frozen world")
	assert_true(scene.enchant.renderer.can_process(), "and keeps animating while the windows hold the run")
	scene.enchant.renderer.advance(3.0)
	assert_eq(scene.enchant.renderer.active_count(), 0)
	scene.handle_events([{"type": "scroll_used", "result": "destroyed", "scroll_id": 2040400, "slot": "top",
		"item_id": 1040002}])
	assert_eq(scene.enchant.renderer.active_count(), 1, "a destroyed item shows the failure effect too")
	assert_eq(lib.missing.size(), 0, "library misses %s" % [lib.missing])
	assert_eq(scene.setup_missing.size(), 0, "setup misses %s" % [scene.setup_missing])


func test_scrolls_have_icons_and_names_in_the_cache() -> void:
	if not require_cache():
		return
	for id: int in [2043700, 2040512, 2040818, 2043705]:
		assert_true(UiArt.icon_or_fallback(InventoryModel.icon_path(id)) != null, "icon %d" % id)
		var frame := lib.frame(InventoryModel.icon_path(id))
		assert_true(frame != null and frame.page != null, "real icon of %d" % id)
		var name_node: Variant = lib.find(InventoryModel.name_path(id))
		assert_true(name_node is String and String(name_node) != "", "name of %d" % id)
		var desc_node: Variant = lib.find(InventoryModel.desc_path(id))
		assert_true(desc_node is String and String(desc_node) != "", "description of %d" % id)
