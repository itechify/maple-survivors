extends TestCase
## LevelUpWindow and PauseMenu: the signals they emit for keys and mouse clicks, the input delay and missing icons (the
## job advancement window went with job advancement, #284). Works with or without the asset cache
## (windows without art keep their layout and input).

const CARDS := [
	{"id": "a", "kind": "skill_new", "skill": "energy_bolt", "name": "Energy Bolt", "desc": "Learn Energy Bolt.",
		"icon": "Skill.wz/200.img/skill/2001004/icon", "rank": 1, "max_rank": 1},
	{"id": "b", "kind": "stat", "skill": "", "name": "No Icon", "desc": "A card with an empty icon path.",
		"icon": "", "rank": 2, "max_rank": 5},
	{"id": "c", "kind": "passive", "skill": "", "name": "Missing Icon", "desc": "An icon path that is not cached.",
		"icon": "Skill.wz/999.img/skill/9999999/icon", "rank": 5, "max_rank": 5},
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
	# Learning starts at skill level 1, so the nineteenth rank-card pick reaches the canonical level-20 cap.
	assert_eq(LevelUpWindow.rank_text({"kind": "skill_rank", "rank": 19, "max_rank": 20, "skill_level": 19,
		"skill_level_next": 20}), "Skill Lv. 19 → 20  MAX")
	assert_eq(LevelUpWindow.rank_text({"kind": "skill_rank", "rank": 1, "max_rank": 20, "skill_level": 1,
		"skill_level_next": 2}), "Skill Lv. 1 → 2")


func test_tiered_cards_show_the_offered_skill_level_and_consumed_steps() -> void:
	assert_eq(LevelUpWindow.rank_text({"kind": "skill_new", "tier": "legendary", "magnitude": 5,
		"rank_before": 0, "rank": 1, "max_rank": 1, "skill_level": 0, "skill_level_next": 5}),
		"NEW  Skill Lv. 5", "the learn card's one consumed step is not its starting skill level")
	assert_eq(LevelUpWindow.rank_text({"kind": "skill_rank", "tier": "unique", "magnitude": 5,
		"rank_before": 3, "rank": 8, "max_rank": 20, "skill_level": 4, "skill_level_next": 9}),
		"Skill Lv. 4 → 9", "rank previews use the final canonical skill level")
	assert_eq(LevelUpWindow.rank_text({"kind": "skill_mod", "tier": "unique", "magnitude": 3,
		"rank_before": 1, "rank": 4, "max_rank": 4}), "Lv. 1 → 4  MAX", "three modifier steps, not one")
	assert_eq(LevelUpWindow.rank_text({"kind": "stat", "tier": "epic", "magnitude": 2,
		"rank_before": 0, "rank": 2, "max_rank": 4}), "Lv. 0 → 2", "a first multi-step pick starts at zero")


func test_high_tier_window_plays_one_cached_cue_per_open_including_boss_rewards() -> void:
	if not require_cache():
		return
	var sfx := (Engine.get_main_loop() as SceneTree).root.get_node("Sfx") as AudioService
	var lib := AssetLibrary.get_default()
	var cue := lib.sound("Sound.wz/Game.img/mCardGet")
	assert_true(cue != null and cue.get_length() > 0.0, "the selected v83 cue is decoded from the real cache")
	for child in sfx.get_children():
		if child is AudioStreamPlayer:
			(child as AudioStreamPlayer).stop()
	var offered: Array = CARDS.duplicate(true)
	offered[0]["tier"] = "unique"
	offered[1]["tier"] = "legendary"
	var w := _add(LevelUpWindow.new()) as LevelUpWindow
	w.open(offered, 8)
	assert_eq(_playing_streams(sfx, cue), 1, "two high-tier cards produce one offer cue")
	w.set_focus(1)
	w.handle_input(key(KEY_2))
	assert_eq(_playing_streams(sfx, cue), 1, "hovering and choosing do not replay the offer cue")
	w.open(CARDS, 9)
	assert_eq(_playing_streams(sfx, cue), 1, "ordinary offers have only their existing level-up sound")
	w.open(offered, 9, true)
	assert_eq(_playing_streams(sfx, cue), 2, "a new boss reward window plays the same cue once")
	assert_eq(lib.missing.size(), 0, "the exact cue and UI audio lookups are present")
	for child in sfx.get_children():
		if child is AudioStreamPlayer:
			(child as AudioStreamPlayer).stop()


func _playing_streams(sfx: AudioService, stream: AudioStream) -> int:
	var count := 0
	for child in sfx.get_children():
		if child is AudioStreamPlayer and (child as AudioStreamPlayer).stream == stream and (child as AudioStreamPlayer).playing:
			count += 1
	return count


func test_dense_tiered_choices_fit_the_view_and_keep_the_mouse_targets() -> void:
	var cards: Array = CARDS.duplicate(true)
	for i in cards.size():
		cards[i]["tier"] = ["normal", "rare", "epic"][i]
		cards[i]["desc"] = "A stronger skill with higher attack, lower cost and a longer effect. Keep every canonical before and after value visible."
		cards[i]["skill_changes"] = {"mad": {"before": 20, "after": 28}, "mastery": {"before": 15, "after": 25},
			"mpCon": {"before": 6, "after": 9}, "time": {"before": 4, "after": 8}, "speed": {"before": 10, "after": 15}}
	var w := _add(LevelUpWindow.new()) as LevelUpWindow
	w.set_anchors_preset(Control.PRESET_TOP_LEFT)
	w.size = Vector2(800, 600)
	w.card_chosen.connect(_record)
	w.open(cards, 12)
	assert_true(w.panel_origin().y >= 0.0, "the gained-level header stays inside the 600px view")
	assert_true(w.panel_origin().y + w.panel_size.y <= 600.0, "the full last choice stays visible")
	for i in cards.size():
		assert_eq(w.cards[i].skill_changes, cards[i].skill_changes, "dense layout preserves every canonical preview")
		assert_true(w.card_rect(i).end.y <= 600.0, "all three mouse targets remain on screen")
	w._gui_input(click(w.card_rect(2).get_center()))
	assert_eq(_got, ["c"], "the expanded third card is selectable with the mouse")


func test_level_up_card_details_show_canonical_rank_changes() -> void:
	var card := {"kind": "skill_rank", "desc": "Rank up Energy Bolt.", "skill_changes": {
		"mad": {"before": 20, "after": 28}, "mastery": {"before": 15, "after": 25},
		"mpCon": {"before": 6, "after": 9}, "fixdamage": {"before": 10, "after": 25}}}
	assert_eq(LevelUpWindow.change_lines(card), PackedStringArray([
		"Magic ATT: 20 → 28", "Mastery: 15% → 25%", "MP cost: 6 → 9", "Damage: 10 → 25"]),
		"all canonical changes have a readable label and before/after values")
	assert_eq(LevelUpWindow.change_lines({"kind": "stat", "desc": "Speed +6."}), PackedStringArray(),
		"ordinary cards have no fabricated skill values")
	var x_change := {"x": {"before": 4, "after": 8}}
	assert_eq(LevelUpWindow.change_lines({"skill_changes": x_change, "skill_effect_stat": "hp"}),
		PackedStringArray(["HP / pulse: 4 → 8"]), "a healing buff's x is HP per pulse (skills.json buff.stat hp)")
	assert_eq(LevelUpWindow.change_lines({"skill_changes": x_change, "skill_effect_stat": "mp_guard"}),
		PackedStringArray(["MP absorption: 4% → 8%"]), "Magic Guard's x is the percent MP absorbs")
	assert_eq(LevelUpWindow.change_lines({"skill_changes": {"speed": {"before": 10, "after": 15},
		Loadout.MAX_MP_PERCENT: {"before": 2, "after": 4}}}), PackedStringArray(["Speed: 10 → 15", "Max MP: 2% → 4%"]),
		"Nimble Feet speed and the Improved MaxMP Increase percentage have readable lines")


func test_rank_preview_uses_the_space_for_values_that_change() -> void:
	assert_eq(LevelUpWindow.change_lines({"skill_changes": {"mpCon": {"before": 6, "after": 6},
		"time": {"before": 30, "after": 30}, "fixdamage": {"before": 10, "after": 25}}}),
		PackedStringArray(["Damage: 10 → 25"]), "unchanged cost and duration do not crowd out the offered gain")


func test_every_previewed_field_has_a_label() -> void:
	for field: String in UpgradePool.PREVIEW_FIELDS + UpgradePool.PASSIVE_PREVIEW_KEYS:
		if field != "x":
			assert_true(LevelUpWindow.FIELD_LABELS.has(field), "label for previewed field %s" % field)


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
	w.handle_input(key(KEY_4))
	assert_eq(_got, ["resumed"], "Quit round requires confirmation")
	assert_true(w.is_open())
	w.handle_input(key(KEY_4))
	assert_eq(_got, ["resumed", "quit"], "confirmed Quit round")
	w.open()
	w.handle_input(key(KEY_UP))
	assert_eq(w.focus, 3, "Up from Resume wraps to Quit")
	w.handle_input(key(KEY_ENTER))
	w.handle_input(key(KEY_ENTER))
	assert_eq(_got[2], "quit", "Up + Enter confirms quit")
	w.open()
	assert_eq(w.focus, 0, "open focuses Resume")
	w.handle_input(key(KEY_ENTER))
	assert_eq(_got[3], "resumed")


func test_pause_menu_mouse_and_buttons() -> void:
	var w := _add(PauseMenu.new()) as PauseMenu
	w.resumed.connect(_record.bind("resumed"))
	w.quit_requested.connect(_record.bind("quit"))
	w.open()
	w._gui_input(click(w.choice_rect(3).get_center()))
	assert_eq(_got, [], "click on Quit asks first")
	w._gui_input(click(w.choice_rect(3).get_center()))
	assert_eq(_got, ["quit"], "click on confirmation")
	w.open()
	w._bt_cancel.pressed.emit()
	assert_eq(_got, ["quit", "resumed"], "CANCEL resumes")
	w.open()
	w.focus = 3
	w._bt_ok.pressed.emit()
	w._bt_ok.pressed.emit()
	assert_eq(_got[2], "quit", "OK confirms the focused choice")


func test_pause_menu_opens_key_config_and_options_and_stays_open() -> void:
	var w := _add(PauseMenu.new()) as PauseMenu
	w.window_requested.connect(_record)
	w.resumed.connect(_record.bind("resumed"))
	w.open()
	assert_eq(PauseMenu.CHOICES, ["Resume", "Key Config", "Options", "Quit round"])
	w.handle_input(key(KEY_2))
	assert_eq(_got, ["key_config"], "2: Key Config")
	assert_true(w.is_open(), "the pause menu stays open under the window")
	w._gui_input(click(w.choice_rect(2).get_center()))
	assert_eq(_got, ["key_config", "options"], "click: Options")
	assert_true(w.is_open())
	w.handle_input(key(KEY_ESCAPE))
	assert_eq(_got[2], "resumed")


func test_boundary_pause_menu_lists_only_resume_and_save_and_quit() -> void:
	var w := _add(PauseMenu.new()) as PauseMenu
	w.boundary_mode = true
	w.window_requested.connect(_record)
	w.quit_requested.connect(_record.bind("quit"))
	w.open()
	assert_eq(w.choices(), ["Resume", "Save & quit"])
	w.handle_input(key(KEY_3))
	assert_eq(_got, [], "the hub has no Options choice")
	w.handle_input(key(KEY_UP))
	assert_eq(w.focus, 1, "Up from Resume wraps to Save & quit")
	w.handle_input(key(KEY_2))
	assert_eq(_got, ["quit"], "Save & quit needs no confirmation")
