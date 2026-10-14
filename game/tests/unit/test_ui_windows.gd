extends TestCase
## LevelUpWindow, JobAdvanceWindow and PauseMenu: the signals they emit for keys and mouse clicks, the input delay,
## missing icons, the all-unavailable job dialog and the instructor choice. Works with or without the asset cache
## (windows without art keep their layout and input).

const CARDS := [
	{"id": "a", "kind": "skill_new", "skill": "energy_bolt", "name": "Energy Bolt", "desc": "Learn Energy Bolt.",
		"icon": "Skill.wz/200.img/skill/2001004/icon", "rank": 1, "max_rank": 1},
	{"id": "b", "kind": "stat", "skill": "", "name": "No Icon", "desc": "A card with an empty icon path.",
		"icon": "", "rank": 2, "max_rank": 5},
	{"id": "c", "kind": "passive", "skill": "", "name": "Missing Icon", "desc": "An icon path that is not cached.",
		"icon": "Skill.wz/999.img/skill/9999999/icon", "rank": 5, "max_rank": 5},
]
const JOB8 := [
	{"job_id": 200, "name": "Magician", "available": true, "reason": ""},
	{"job_id": 100, "name": "Warrior", "available": false, "reason": "Lv. 10"},
	{"job_id": 300, "name": "Bowman", "available": false, "reason": "Lv. 10"},
	{"job_id": 400, "name": "Thief", "available": false, "reason": "Lv. 10"},
	{"job_id": 500, "name": "Pirate", "available": false, "reason": "Lv. 10"},
]
const JOB30 := [
	{"job_id": 210, "name": "Wizard (Fire, Poison)", "available": false, "reason": "Phase 2"},
	{"job_id": 220, "name": "Wizard (Ice, Lightning)", "available": false, "reason": "Not yet available"},
	{"job_id": 230, "name": "Cleric", "available": false, "reason": "Not yet available"},
]

var _nodes: Array[Node] = []
var _got: Array = []


func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.free()
	_nodes.clear()
	_got.clear()


func _add(w: MapleWindow) -> MapleWindow:
	w.transition_seconds = 0.0
	w.input_delay = 0.0
	# The runner's _ready is running, so the root is busy; the runner (current scene) accepts children.
	(Engine.get_main_loop() as SceneTree).current_scene.add_child(w)
	_nodes.append(w)
	return w


static func key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = true
	return e


static func click(at: Vector2, pressed: bool = false) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = at
	return e


func _record(v: Variant = null) -> void:
	_got.append(v)


# --- LevelUpWindow -----------------------------------------------------------------------------------------------

func test_level_up_digit_keys_pick_cards() -> void:
	var w := _add(LevelUpWindow.new()) as LevelUpWindow
	w.card_chosen.connect(_record)
	w.open(CARDS, 8)
	assert_true(w.is_open() and w.visible, "open")
	assert_eq(w.focus, 0, "first card focused")
	assert_true(w.handle_input(key(KEY_2)), "digit used")
	assert_eq(_got, ["b"], "key 2 -> second card")
	assert_false(w.is_open(), "closed after the pick")
	assert_false(w.visible, "hidden (no transition in tests)")
	assert_false(w.choose(0), "no pick while closed")
	assert_eq(_got.size(), 1)


func test_level_up_arrows_and_enter() -> void:
	var w := _add(LevelUpWindow.new()) as LevelUpWindow
	w.card_chosen.connect(_record)
	w.open(CARDS, 12)
	w.handle_input(key(KEY_DOWN))
	w.handle_input(key(KEY_DOWN))
	assert_eq(w.focus, 2)
	w.handle_input(key(KEY_DOWN))
	assert_eq(w.focus, 0, "wraps")
	w.handle_input(key(KEY_UP))
	assert_eq(w.focus, 2, "wraps up")
	assert_eq(_got.size(), 0, "moving the focus picks nothing")
	w.handle_input(key(KEY_KP_ENTER))
	assert_eq(_got, ["c"], "Enter picks the focused card")


func test_level_up_space_and_escape_do_not_pick() -> void:
	var w := _add(LevelUpWindow.new()) as LevelUpWindow
	w.card_chosen.connect(_record)
	w.open(CARDS, 3)
	w.handle_input(key(KEY_SPACE))
	w.handle_input(key(KEY_ESCAPE))
	w.handle_input(key(KEY_4))
	assert_eq(_got.size(), 0, "Space (jump), Esc and an out-of-range digit never pick")
	assert_true(w.is_open())


func test_level_up_mouse_hover_and_click() -> void:
	var w := _add(LevelUpWindow.new()) as LevelUpWindow
	w.card_chosen.connect(_record)
	w.open(CARDS, 5)
	var r := w.card_rect(1)
	assert_true(r.size.x > 100.0 and r.size.y >= LevelUpWindow.ROW_H, "card block rect %s" % r)
	var move := InputEventMouseMotion.new()
	move.position = r.get_center()
	w._gui_input(move)
	assert_eq(w.focus, 1, "hover focuses")
	w._gui_input(click(r.get_center(), true))
	assert_eq(_got.size(), 0, "press alone does not pick")
	w._gui_input(click(r.get_center(), false))
	assert_eq(_got, ["b"], "release picks the hovered card")


func test_level_up_input_delay_blocks_keys() -> void:
	var w := _add(LevelUpWindow.new()) as LevelUpWindow
	w.input_delay = 5.0
	w.card_chosen.connect(_record)
	w.open(CARDS, 5)
	w._input(key(KEY_1))
	assert_eq(_got.size(), 0, "keys are ignored right after open")
	w._process(6.0)
	w._input(key(KEY_1))
	assert_eq(_got, ["a"], "after the delay the key picks")


func test_level_up_reopen_and_missing_icons() -> void:
	var w := _add(LevelUpWindow.new()) as LevelUpWindow
	w.card_chosen.connect(_record)
	w.open(CARDS, 5)
	w.choose(0)
	w.open([CARDS[1], CARDS[2]], 6)
	assert_true(w.is_open(), "a queued level-up reopens the window")
	assert_eq(w.cards.size(), 2)
	assert_eq(w.level, 6)
	assert_eq(w._blocks.size(), 2, "a block per card, icons or not")
	assert_true(w.panel_size.y >= LevelUpWindow.ART_SIZE.y)
	# "" and uncached icons fall back to the neutral icon base (or null without a cache), never an error.
	assert_eq(UiArt.frame(""), null)
	var lib := UiArt.lib()
	var misses := lib.missing.size() if lib != null else 0
	assert_eq(UiArt.frame(String(CARDS[2].icon)), null, "uncached icon")
	if lib != null:
		assert_eq(lib.missing.size(), misses, "optional art lookups do not record misses")
	var fb := UiArt.icon_or_fallback("")
	if lib != null and lib.has_cache():
		assert_true(fb != null, "fallback icon %s in the cache" % UiArt.FALLBACK_ICON)
		assert_eq(fb.path, UiArt.FALLBACK_ICON)
	w.handle_input(key(KEY_2))
	assert_eq(_got, ["a", "c"])


func test_level_up_rank_text() -> void:
	assert_eq(LevelUpWindow.rank_text({"kind": "skill_new", "rank": 1, "max_rank": 1}), "NEW")
	assert_eq(LevelUpWindow.rank_text({"kind": "stat", "rank": 1, "max_rank": 5}), "NEW")
	assert_eq(LevelUpWindow.rank_text({"kind": "skill_mod", "rank": 2, "max_rank": 4}), "Lv. 1 → 2")
	assert_eq(LevelUpWindow.rank_text({"kind": "skill_rank", "rank": 5, "max_rank": 5}), "Lv. 4 → 5  MAX")
	assert_eq(LevelUpWindow.rank_text({"kind": "filler", "rank": 3, "max_rank": 0}), "")
	# skill_rank cards show the skill's canonical level change, not the card's own rank (Stronger Snails: the second
	# card takes Three Snails from level 2 to 3; Energy Bolt rank 2 is level 5).
	assert_eq(LevelUpWindow.rank_text({"kind": "skill_rank", "rank": 2, "max_rank": 2, "skill_level": 2,
		"skill_level_next": 3}), "Skill Lv. 2 → 3  MAX")
	assert_eq(LevelUpWindow.rank_text({"kind": "skill_rank", "rank": 1, "max_rank": 5, "skill_level": 1,
		"skill_level_next": 5}), "Skill Lv. 1 → 5")


func test_level_up_notice_names_only_skills() -> void:
	var snails := {"kind": "skill_rank", "skill": "three_snails", "name": "Stronger Snails", "skill_name": "Three Snails"}
	assert_true(LevelUpWindow.names_a_skill(snails), "a skill level-up fits the sentence")
	assert_eq(LevelUpWindow.notice_name(snails), "Three Snails", "the box names the skill, not the card")
	assert_true(LevelUpWindow.names_a_skill({"kind": "skill_new", "skill": "magic_claw", "name": "Magic Claw"}))
	for kind: String in ["skill_mod", "stat", "passive", "filler"]:
		assert_false(LevelUpWindow.names_a_skill({"kind": kind, "skill": "three_snails" if kind == "skill_mod" else "",
			"name": "x"}), "%s: no 'raised your ___ skill' sentence" % kind)


# --- JobAdvanceWindow --------------------------------------------------------------------------------------------

func test_job_window_pick_magician_after_confirmation() -> void:
	var w := _add(JobAdvanceWindow.new()) as JobAdvanceWindow
	w.job_chosen.connect(_record)
	w.declined.connect(_record.bind("declined"))
	w.open(JOB8, 8, 0)
	assert_eq(w.npc_id, 1032001, "Grendel for the Magician branch")
	assert_eq(w.entries.size(), 6, "5 jobs + Not now")
	assert_eq(String(w.entries[5].kind), "decline")
	assert_eq(w.focus, 0, "Magician focused")
	assert_true(w.any_available())
	w.handle_input(key(KEY_2))
	assert_eq(_got.size(), 0, "a locked job cannot be picked")
	assert_eq(w.state, "choose")
	w.handle_input(key(KEY_ENTER))
	assert_eq(w.state, "confirm", "the confirmation line shows")
	assert_true(w.body.begins_with("You are now a Magician"), w.body)
	assert_eq(_got.size(), 0, "job_chosen waits for the dialog to close")
	assert_true(w.is_open())
	w.handle_input(key(KEY_A))
	assert_eq(_got, [200], "any key closes the confirmation and emits job_chosen")
	assert_false(w.is_open())


func test_job_window_confirmation_times_out_and_mouse() -> void:
	var w := _add(JobAdvanceWindow.new()) as JobAdvanceWindow
	w.confirm_seconds = 1.0
	w.job_chosen.connect(_record)
	w.open(JOB8, 10, 0)
	var r := w.entry_rect(0)
	assert_true(r.size.y > 0.0, "entry rect")
	var move := InputEventMouseMotion.new()
	move.position = w.entry_rect(5).get_center()
	w._gui_input(move)
	assert_eq(w.focus, 5, "hover focuses Not now")
	move.position = w.entry_rect(1).get_center()
	w._gui_input(move)
	assert_eq(w.focus, 5, "hovering a locked job does not focus it")
	w._gui_input(click(r.get_center()))
	assert_eq(w.state, "confirm", "click on Magician")
	w._process(0.5)
	assert_eq(_got.size(), 0)
	w._process(0.6)
	assert_eq(_got, [200], "closes after confirm_seconds")


func test_job_window_navigation_skips_locked_and_declines() -> void:
	var w := _add(JobAdvanceWindow.new()) as JobAdvanceWindow
	w.confirm_seconds = 0.0
	w.job_chosen.connect(_record)
	w.declined.connect(_record.bind("declined"))
	w.open(JOB8, 8, 0)
	w.handle_input(key(KEY_DOWN))
	assert_eq(w.focus, 5, "Down skips the locked jobs to Not now")
	w.handle_input(key(KEY_DOWN))
	assert_eq(w.focus, 0, "wraps to Magician")
	w.handle_input(key(KEY_UP))
	w.handle_input(key(KEY_ENTER))
	assert_eq(_got, ["declined"], "Not now declines")
	w.open(JOB8, 9, 0)
	w.handle_input(key(KEY_ESCAPE))
	assert_eq(_got, ["declined", "declined"], "Esc = END CHAT")
	w.open(JOB8, 9, 0)
	w.handle_input(key(KEY_6))
	assert_eq(_got.size(), 3, "digit 6 = Not now")
	w.open(JOB8, 9, 0)
	w.handle_input(key(KEY_1))
	assert_eq(_got[3], 200, "confirm_seconds 0: job_chosen at once")


func test_job_window_nothing_available_ok_declines() -> void:
	var w := _add(JobAdvanceWindow.new()) as JobAdvanceWindow
	w.job_chosen.connect(_record)
	w.declined.connect(_record.bind("declined"))
	w.open(JOB30, 30, 200)
	assert_false(w.any_available())
	assert_eq(w.entries.size(), 3, "no Not now entry when nothing is available")
	assert_eq(w.npc_id, 1032001, "the current job's instructor")
	assert_eq(w.focus, -1)
	assert_true(w._bt_ok.visible, "OK shown")
	assert_false(w._bt_close.visible, "END CHAT hidden")
	w.handle_input(key(KEY_1))
	w.handle_input(key(KEY_DOWN))
	assert_eq(_got.size(), 0, "nothing selectable")
	w._bt_ok.pressed.emit()
	assert_eq(_got, ["declined"], "OK declines")
	w.open(JOB30, 31, 200)
	w.handle_input(key(KEY_ENTER))
	assert_eq(_got, ["declined", "declined"], "Enter = OK")


func test_job_window_instructors() -> void:
	assert_eq(JobAdvanceWindow.instructor_for(JOB8, 0), 1032001)
	assert_eq(JobAdvanceWindow.instructor_for(JOB30, 200), 1032001)
	assert_eq(JobAdvanceWindow.instructor_for(JOB30, 0), 9010000, "Beginner with nothing available")
	assert_eq(JobAdvanceWindow.instructor_for([{"job_id": 300, "available": true}], 0), 1012100)
	assert_eq(JobAdvanceWindow.instructor_for([{"job_id": 100, "available": true}], 0), 1022000)
	assert_eq(JobAdvanceWindow.instructor_for([{"job_id": 420, "available": true}], 400), 1052001)
	assert_eq(JobAdvanceWindow.instructor_for([{"job_id": 510, "available": false}], 500), 1090000)
	assert_eq(JobAdvanceWindow.branch_of(232), 200)
	assert_eq(JobAdvanceWindow.branch_of(0), 0)
	assert_true(JobAdvanceWindow.intro_text(1032001, JOB8, 8).begins_with("So you want to become a Magician?"))
	assert_true(JobAdvanceWindow.intro_text(9010000, JOB30, 30).contains("Lv. 30"))


# --- PauseMenu ---------------------------------------------------------------------------------------------------

func test_pause_menu_keys() -> void:
	var w := _add(PauseMenu.new()) as PauseMenu
	w.resumed.connect(_record.bind("resumed"))
	w.quit_requested.connect(_record.bind("quit"))
	w.open()
	w.handle_input(key(KEY_ESCAPE))
	assert_eq(_got, ["resumed"], "Esc resumes")
	assert_false(w.is_open())
	w.open()
	w.handle_input(key(KEY_2))
	assert_eq(_got, ["resumed", "quit"], "2 quits")
	w.open()
	w.handle_input(key(KEY_DOWN))
	assert_eq(w.focus, 1)
	w.handle_input(key(KEY_ENTER))
	assert_eq(_got[2], "quit", "Down + Enter quits")
	w.open()
	assert_eq(w.focus, 0, "open focuses Resume")
	w.handle_input(key(KEY_ENTER))
	assert_eq(_got[3], "resumed")


func test_pause_menu_mouse_and_buttons() -> void:
	var w := _add(PauseMenu.new()) as PauseMenu
	w.resumed.connect(_record.bind("resumed"))
	w.quit_requested.connect(_record.bind("quit"))
	w.open()
	w._gui_input(click(w.choice_rect(1).get_center()))
	assert_eq(_got, ["quit"], "click on Quit")
	w.open()
	w._bt_cancel.pressed.emit()
	assert_eq(_got, ["quit", "resumed"], "CANCEL resumes")
	w.open()
	w.focus = 1
	w._bt_ok.pressed.emit()
	assert_eq(_got[2], "quit", "OK takes the focused choice")
