extends TestCase
## The Skill window for a Bishop (232; spec #372, BS9 #381; the Bishop copy of test_skill_window_il): the tabs follow the job's
## lineage (Magician 200, Cleric 230, Priest 231, Bishop 232, after the Common tab), each listing the pool skills of its book the
## game implements, and Teleport sits first on the 230 tab where Skill.wz keeps it (2301001, ahead of Heal 2301002 and Holy Arrow
## 2301005). The model tests use the synthetic books of the Bishop bot test and the canonical job names (no cache); the RunScene
## test (SKIP without the cache) drives the real window through its hotkeys. Skills of a book whose ticket has not merged
## (Resurrection, BS8) are inert, so the tests list a tab's rows from the defined pool and widen with it.

const BOT := preload("res://tests/unit/test_bishop_bot.gd")
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


func _model() -> SkillWindowModel:
	var w: RunWorld = BOT.new()._world()
	return SkillWindowModel.new(w.book, w.upgrades, w.loadout, w.jobs, 232, SkillText.new(w.book, {}))


static func _tab_names(m: SkillWindowModel) -> Array:
	return m.tabs.map(func(t: Dictionary) -> String: return String(t.name))


static func _row_keys(tab: Dictionary) -> Array:
	return tab.rows.map(func(r: Dictionary) -> String: return String(r.key))


func test_tabs_follow_the_lineage_200_230_231_232_after_common() -> void:
	var m := _model()
	assert_eq(_tab_names(m), ["Common", "Magician", "Cleric", "Priest", "Bishop"])
	assert_eq(m.tabs.map(func(t: Dictionary) -> int: return int(t.job_id)), [0, 200, 230, 231, 232])
	assert_eq(m.tabs.map(func(t: Dictionary) -> int: return int(t.tier)), [0, 1, 2, 3, 4], "glyphs 0, I, II, III, IV")
	for t: Dictionary in m.tabs.slice(1):
		assert_eq(t.book_icon, "Skill.wz/%d.img/info/icon" % int(t.job_id))


func test_each_tab_lists_the_pool_skills_of_its_book_with_teleport_first_on_230() -> void:
	var m := _model()
	var w: RunWorld = BOT.new()._world()
	assert_eq(_row_keys(m.tabs[1]), ["magic_claw"], "the 200 tab: Magic Claw (Energy Bolt is not in the Bishop pool)")
	var l230 := _row_keys(m.tabs[2])
	assert_eq(l230.slice(0, 3), ["teleport_cleric", "heal", "holy_arrow"],
		"Teleport (2301001) sorts before Heal (2301002) and Holy Arrow (2301005): it is a learned row of the 230 tab")
	assert_eq(_row_keys(m.tabs[3]).slice(0, 1), ["shining_ray"], "the 231 tab starts with Shining Ray 2311004 (Holy Symbol is the Common tab's EXP passive; Summon Dragon follows from BS7)")
	for t: Dictionary in m.tabs.slice(1):
		var want: Array = []
		for key: String in w.jobs.skill_pool(232) + ["teleport_cleric"]:
			if w.book.has(key) and int(w.book.def(key).job) == int(t.job_id):
				want.append(key)
		want.sort_custom(func(a: String, b: String) -> bool: return w.book.skill_id(a) < w.book.skill_id(b))
		assert_eq(_row_keys(t), want, "the %s tab lists its book's implemented pool skills" % t.name)
	var teleport: Dictionary = m.tabs[2].rows[0]
	assert_true(teleport.learned and int(teleport.level) >= 1, "Teleport is learned from Lv1")
	assert_eq(teleport.skill_id, 2301001)
	var arrow: Dictionary = m.tabs[2].rows[2]
	assert_true(arrow.learned, "Holy Arrow is the starting skill")
	var heal: Dictionary = m.tabs[2].rows[1]
	assert_false(heal.learned, "Heal is offered, not learned: greyed at 0")
	assert_eq(heal.icon_disabled, "Skill.wz/230.img/skill/2301002/iconDisabled")


func test_no_row_of_another_jobs_line_leaks_in_and_every_row_is_a_pool_skill_or_teleport() -> void:
	var m := _model()
	var w: RunWorld = BOT.new()._world()
	var allowed: Array = w.jobs.skill_pool(232) + ["teleport_cleric"]
	for t: Dictionary in m.tabs.slice(1):
		for r: Dictionary in t.rows:
			assert_true(String(r.key) in allowed, "%s is a Bishop skill" % r.key)
			assert_eq(int(w.book.def(String(r.key)).job), int(t.job_id), "%s sits on its own book's tab" % r.key)
	assert_false(String(m.tabs[0].rows[0].key).is_empty(), "the Common tab keeps the nine passives")
	assert_eq(m.tabs[0].rows.size(), 9)


func test_the_tooltip_of_a_bishop_skill_reads_the_numbers_of_its_rank() -> void:
	var m := _model()
	var tip := m.skill_tooltip("holy_arrow")
	assert_eq(tip.key, "holy_arrow")
	assert_true(int(tip.level) >= 1)
	assert_true(tip.cooldown > 0.0, "an active skill shows its cooldown")
	assert_true(int(tip.next_level) > int(tip.level), "and the next rank's level")


func test_a_232_run_opens_the_skill_window_on_the_bishop_tab_and_teleport_is_on_230() -> void:
	if not require_cache():
		return
	DataRepo.patch = {"jobs_survivor": {"jobs": {"232": {"playable": true}}}}
	var s: RunScene = (load(RunScene.SCENE_PATH) as PackedScene).instantiate()
	s.library = lib
	s.configure("henesys", 13, {"use_flow": false, "autoplay": true, "autopick": true, "job": 232})
	var tree := Engine.get_main_loop() as SceneTree
	(tree.current_scene if tree.current_scene != null else tree.root).add_child(s)
	scene = s
	for i in 10:
		scene.advance_frame(DT)
	var w := scene.world
	assert_eq(w.job_id(), 232)
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
		["Common", "Magician", "Cleric", "Priest", "Bishop"])
	assert_eq(sw.tab, 4, "on the current job's tab (the fourth job, the fifth tab)")
	scene.handle_hotkey(_key(KEY_3))
	assert_eq(sw.tab, 2, "3 is the Cleric tab")
	var rows: Array = sw.rows().map(func(r: Dictionary) -> String: return String(r.key))
	assert_true("teleport_cleric" in rows and "holy_arrow" in rows, "Teleport and Holy Arrow are on the 230 tab: %s" % [rows])
	assert_eq(rows[0], "teleport_cleric", "Teleport's row comes first (skill id order)")
	scene.handle_hotkey(_key(KEY_5))
	assert_eq(sw.tab, 4, "5 is the fourth-job tab")
	scene.handle_hotkey(_key(KEY_ESCAPE))
	assert_false(scene.ui_windows.has_windows(), "Esc closed it")
