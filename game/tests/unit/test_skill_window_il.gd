extends TestCase
## The Skill window for an I/L Arch Mage (222; spec #319, I11 #330): the tabs follow the job's lineage (Magician 200, Wizard 220,
## Mage 221, Arch Mage 222, after the Common tab), each listing the pool skills of its book the game implements, and Teleport sits on
## the 220 tab where Skill.wz keeps it. The model tests use the I6 tests' synthetic books and the canonical job names (no cache);
## the RunScene test (a `test_run_windows`-style world, SKIP without the cache) drives the real window through its hotkeys.
## Skills of a book whose ticket has not merged (Chain Lightning, Blizzard, Big Bang) are inert, so the 222 tab holds only Ifrit
## today; the tests list a tab's rows from the defined pool and widen with it.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const BOLTS := preload("res://tests/unit/test_il_bolts.gd")
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
	var w: RunWorld = BOLTS.new()._round({}, 330)
	return SkillWindowModel.new(w.book, w.upgrades, w.loadout, w.jobs, 222, SkillText.new(w.book, {}))


static func _tab_names(m: SkillWindowModel) -> Array:
	return m.tabs.map(func(t: Dictionary) -> String: return String(t.name))


static func _row_keys(tab: Dictionary) -> Array:
	return tab.rows.map(func(r: Dictionary) -> String: return String(r.key))


func test_tabs_follow_the_lineage_200_220_221_222_after_common() -> void:
	var m := _model()
	assert_eq(_tab_names(m), ["Common", "Magician", "Wizard (Ice, Lightning)", "Mage (Ice, Lightning)", "Arch Mage (Ice, Lightning)"])
	assert_eq(m.tabs.map(func(t: Dictionary) -> int: return int(t.job_id)), [0, 200, 220, 221, 222])
	assert_eq(m.tabs.map(func(t: Dictionary) -> int: return int(t.tier)), [0, 1, 2, 3, 4], "glyphs 0, I, II, III, IV")
	for t: Dictionary in m.tabs.slice(1):
		assert_eq(t.book_icon, "Skill.wz/%d.img/info/icon" % int(t.job_id))


## The rows of `tab` that are among `keys` (the skills of the I6 tickets, whatever later tickets add to the tab).
static func _among(tab: Dictionary, keys: Array) -> Array:
	return _row_keys(tab).filter(func(k: String) -> bool: return k in keys)


func test_each_tab_lists_the_pool_skills_of_its_book_with_teleport_first_on_220() -> void:
	var m := _model()
	var w: RunWorld = BOLTS.new()._round({}, 330)
	assert_eq(_among(m.tabs[1], ["energy_bolt", "magic_claw"]), ["energy_bolt", "magic_claw"], "the shared 200 bolts, in v83 skill id order")
	var l220 := _row_keys(m.tabs[2])
	assert_eq(l220.slice(0, 3), ["teleport_il", "cold_beam", "thunder_bolt"],
		"Teleport (2201002) sorts before Cold Beam (2201004) and Thunder Bolt (2201005): it is a learned row of the 220 tab")
	var l221 := _among(m.tabs[3], ["ice_strike", "thunder_spear"])
	assert_eq(l221, ["ice_strike", "thunder_spear"], "the 221 tab: Ice Strike 2211002, then Thunder Spear 2211003")
	# Every defined pool skill of a book is on its tab, in skill id order, and nothing else is (Teleport aside).
	for t: Dictionary in m.tabs.slice(1):
		var want: Array = []
		for key: String in w.jobs.skill_pool(222) + ["teleport_il"]:
			if w.book.has(key) and int(w.book.def(key).job) == int(t.job_id):
				want.append(key)
		want.sort_custom(func(a: String, b: String) -> bool: return w.book.skill_id(a) < w.book.skill_id(b))
		assert_eq(_row_keys(t), want, "the %s tab lists its book's implemented pool skills" % t.name)
	var teleport: Dictionary = m.tabs[2].rows[0]
	assert_true(teleport.learned and int(teleport.level) >= 1, "Teleport is learned from Lv1")
	assert_eq(teleport.skill_id, 2201002)
	var cold: Dictionary = m.tabs[2].rows[1]
	assert_true(cold.learned, "Cold Beam is the starting skill")
	assert_false(m.tabs[2].rows[2].learned, "Thunder Bolt is offered, not learned: greyed at 0")
	assert_eq(m.tabs[2].rows[2].icon_disabled, "Skill.wz/220.img/skill/2201005/iconDisabled")


func test_no_row_of_another_jobs_line_leaks_in_and_every_row_is_a_pool_skill_or_teleport() -> void:
	var m := _model()
	var w: RunWorld = BOLTS.new()._round({}, 330)
	var allowed: Array = w.jobs.skill_pool(222) + ["teleport_il"]
	for t: Dictionary in m.tabs.slice(1):
		for r: Dictionary in t.rows:
			assert_true(String(r.key) in allowed, "%s is an I/L skill" % r.key)
			assert_eq(int(w.book.def(String(r.key)).job), int(t.job_id), "%s sits on its own book's tab" % r.key)
	assert_false(String(m.tabs[0].rows[0].key).is_empty(), "the Common tab keeps the nine passives")
	assert_eq(m.tabs[0].rows.size(), 9)


func test_the_tooltip_of_an_il_skill_reads_the_numbers_of_its_rank() -> void:
	var m := _model()
	var tip := m.skill_tooltip("cold_beam")
	assert_eq(tip.key, "cold_beam")
	assert_true(int(tip.level) >= 1)
	assert_true(tip.cooldown > 0.0, "an active skill shows its cooldown")
	assert_true(int(tip.next_level) > int(tip.level), "and the next rank's level")


func test_a_222_run_opens_the_skill_window_on_the_arch_mage_tab_and_teleport_is_on_220() -> void:
	if not require_cache():
		return
	DataRepo.patch = {"jobs_survivor": {"jobs": {"222": {"playable": true}}}}
	var s: RunScene = (load(RunScene.SCENE_PATH) as PackedScene).instantiate()
	s.library = lib
	s.configure("henesys", 13, {"use_flow": false, "autoplay": true, "autopick": true, "job": 222})
	var tree := Engine.get_main_loop() as SceneTree
	(tree.current_scene if tree.current_scene != null else tree.root).add_child(s)
	scene = s
	for i in 10:
		scene.advance_frame(DT)
	var w := scene.world
	assert_eq(w.job_id(), 222)
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
		["Common", "Magician", "Wizard (Ice, Lightning)", "Mage (Ice, Lightning)", "Arch Mage (Ice, Lightning)"])
	assert_eq(sw.tab, 4, "on the current job's tab (the fourth job, the fifth tab)")
	scene.handle_hotkey(_key(KEY_3))
	assert_eq(sw.tab, 2, "3 is the Wizard (Ice, Lightning) tab")
	var rows: Array = sw.rows().map(func(r: Dictionary) -> String: return String(r.key))
	assert_true("teleport_il" in rows and "cold_beam" in rows, "Teleport and Cold Beam are on the 220 tab: %s" % [rows])
	assert_true(rows.find("teleport_il") < rows.find("cold_beam"), "Teleport's row comes first (skill id order)")
	scene.handle_hotkey(_key(KEY_5))
	assert_eq(sw.tab, 4, "5 is the fourth-job tab")
	scene.handle_hotkey(_key(KEY_ESCAPE))
	assert_false(scene.ui_windows.has_windows(), "Esc closed it")
