extends TestCase
## Bowmaster Skill window integration: real hotkeys, all four lineage tabs and Common; cache required.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0

var lib: AssetLibrary
var scene: RunScene


func before_each() -> void:
	lib = AssetLibrary.new()
	lib.open()


func after_each() -> void:
	DataRepo.patch = {}
	if scene != null and is_instance_valid(scene):
		scene.free()
	scene = null
	lib.free()


static func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = true
	return e


func test_bowmaster_run_opens_lineage_tabs_and_common_through_hotkeys() -> void:
	if not require_cache():
		return
	var s: RunScene = (load(RunScene.SCENE_PATH) as PackedScene).instantiate()
	s.library = lib
	s.configure("henesys", 13, {"use_flow": false, "autoplay": true, "autopick": true, "job": 312})
	var tree := Engine.get_main_loop() as SceneTree
	(tree.current_scene if tree.current_scene != null else tree.root).add_child(s)
	scene = s
	for i in 10:
		scene.advance_frame(DT)
	var w := scene.world
	assert_eq(w.job_id(), 312)
	var t := w.time
	assert_true(scene.handle_hotkey(_key(KEY_K)), "K is the Skill hotkey")
	var sw := scene.ui_windows.top() as SkillWindow
	assert_true(sw != null, "the Skill window opened")
	if sw == null:
		return
	for i in 10:
		scene.advance_frame(DT)
	assert_eq(w.time, t, "no sim ticks while it is open")
	assert_eq(sw.model.tabs.map(func(tab: Dictionary) -> String: return String(tab.name)),
		["Common", "Bowman", "Hunter", "Ranger", "Bowmaster"])
	assert_eq(sw.tab, 4, "on the current job's tab (the fourth job, the fifth tab)")
	for i in 5:
		scene.handle_hotkey(_key(KEY_1 + i))
		assert_eq(sw.tab, i)
		assert_true(sw.rows().size() > 0, "every lineage tab has rows")
	scene.handle_hotkey(_key(KEY_1))
	assert_eq(sw.rows().size(), 9, "Common contains nine passives")
	scene.handle_hotkey(_key(KEY_ESCAPE))
	assert_false(scene.ui_windows.has_windows(), "Esc closed it")
