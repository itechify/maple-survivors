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
## The Lv 10 list as JobTree.advancements returns it: one entry per job, `paths` in page order (decision 2 of spec #226).
const LV10 := [
	{"job_id": 100, "name": "Warrior", "available": true, "reason": "", "paths": [
		{"id": "sword", "label": "Sword", "item_id": 1302077, "family": "sword"},
		{"id": "spear", "label": "Spear", "item_id": 1432000, "family": "spear"},
		{"id": "blunt", "label": "Blunt Weapon", "item_id": 1322006, "family": "blunt"}]},
	{"job_id": 200, "name": "Magician", "available": true, "reason": "", "paths": []},
	{"job_id": 300, "name": "Bowman", "available": true, "reason": "", "paths": [
		{"id": "bow", "label": "Bow", "item_id": 1452051, "family": "bow"},
		{"id": "crossbow", "label": "Crossbow", "item_id": 1462001, "family": "crossbow"}]},
	{"job_id": 400, "name": "Thief", "available": true, "reason": "", "paths": [
		{"id": "claw", "label": "Claw", "item_id": 1472061, "family": "claw"},
		{"id": "dagger", "label": "Dagger", "item_id": 1332063, "family": "dagger"}]},
	{"job_id": 500, "name": "Pirate", "available": true, "reason": "", "paths": [
		{"id": "knuckle", "label": "Knuckle", "item_id": 1482000, "family": "knuckle"},
		{"id": "gun", "label": "Gun", "item_id": 1492000, "family": "gun"}]},
]
## A sword Warrior's Lv 30 list (the held family first on each page) and a Bowman's (single-family branches: no page).
const LV30_WARRIOR := [
	{"job_id": 110, "name": "Fighter", "available": true, "reason": "", "paths": [
		{"id": "sword", "label": "Sword", "item_id": 1302008, "family": "sword"},
		{"id": "axe", "label": "Axe", "item_id": 1312005, "family": "axe"}]},
	{"job_id": 120, "name": "Page", "available": true, "reason": "", "paths": [
		{"id": "sword", "label": "Sword", "item_id": 1302008, "family": "sword"},
		{"id": "blunt", "label": "Blunt Weapon", "item_id": 1322014, "family": "blunt"}]},
	{"job_id": 130, "name": "Spearman", "available": true, "reason": "", "paths": [
		{"id": "spear", "label": "Spear", "item_id": 1432002, "family": "spear"},
		{"id": "polearm", "label": "Polearm", "item_id": 1442001, "family": "polearm"}]},
]
const LV30_BOWMAN := [
	{"job_id": 310, "name": "Hunter", "available": true, "reason": "", "paths": [
		{"id": "bow", "label": "Bow", "item_id": 1452005, "family": "bow"}]},
	{"job_id": 320, "name": "Crossbowman", "available": true, "reason": "", "paths": [
		{"id": "crossbow", "label": "Crossbow", "item_id": 1462000, "family": "crossbow"}]},
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
		"fixdamage": {"before": 10, "after": 25}}}
	assert_eq(LevelUpWindow.change_lines(card), PackedStringArray([
		"Magic ATT: 20 → 28", "Mastery: 15% → 25%", "Damage: 10 → 25"]),
		"all canonical changes have a readable label and before/after values")
	assert_eq(LevelUpWindow.change_lines({"kind": "stat", "desc": "Speed +6."}), PackedStringArray(),
		"ordinary cards have no fabricated skill values")
	var x_change := {"x": {"before": 4, "after": 8}}
	assert_eq(LevelUpWindow.change_lines({"skill_changes": x_change, "skill_effect_stat": "hp"}),
		PackedStringArray(["HP / pulse: 4 → 8"]), "a healing buff's x is HP per pulse (skills.json buff.stat hp)")
	assert_eq(LevelUpWindow.change_lines({"skill_changes": x_change, "skill_effect_stat": "other"}),
		PackedStringArray(["Effect: 4 → 8"]), "any other stat's x shows as a plain effect value")
	assert_eq(LevelUpWindow.change_lines({"skill_changes": {"speed": {"before": 10, "after": 15}}}),
		PackedStringArray(["Speed: 10 → 15"]), "Nimble Feet speed has a readable line")


func test_rank_preview_uses_the_space_for_values_that_change() -> void:
	assert_eq(LevelUpWindow.change_lines({"skill_changes": {"hpCon": {"before": 6, "after": 6},
		"time": {"before": 30, "after": 30}, "fixdamage": {"before": 10, "after": 25}}}),
		PackedStringArray(["Damage: 10 → 25"]), "unchanged cost and duration do not crowd out the offered gain")


func test_every_previewed_field_has_a_label() -> void:
	for field: String in UpgradePool.PREVIEW_FIELDS + UpgradePool.PASSIVE_PREVIEW_KEYS:
		if field != "x":
			assert_true(LevelUpWindow.FIELD_LABELS.has(field), "label for previewed field %s" % field)


# --- JobAdvanceWindow --------------------------------------------------------------------------------------------

func test_job_window_pick_magician_after_confirmation() -> void:
	var w := _add(JobAdvanceWindow.new()) as JobAdvanceWindow
	w.job_chosen.connect(_record)
	w.declined.connect(_record.bind("declined"))
	w.open(JOB8, 8, 0)
	assert_eq(w.npc_id, 0, "a list across branches has no portrait")
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


func _texts(w: JobAdvanceWindow) -> Array:
	return w.entries.map(func(e: Dictionary) -> String: return e.text)


func test_job_window_page_one_has_one_entry_per_job() -> void:
	var w := _add(JobAdvanceWindow.new()) as JobAdvanceWindow
	w.open(LV10, 10, 0)
	assert_eq(w.state, "choose")
	assert_eq(_texts(w), ["Warrior", "Magician", "Bowman", "Thief", "Pirate", "Not now."], "each job once, then Not now")
	assert_false(w.body.to_lower().contains("canonical"), "no developer wording")
	assert_false(w.body.contains("Dark Lord"), "the intro does not name one instructor")
	assert_eq(w.npc_id, 0, "Lv 10: no single instructor speaks for every job, so no portrait (tier C)")
	assert_false((w.get_node("Panel/Npc") as WzImage).visible, "no NPC portrait on the Lv 10 list")


func test_job_window_weapon_page_for_a_multi_family_job() -> void:
	var w := _add(JobAdvanceWindow.new()) as JobAdvanceWindow
	w.confirm_seconds = 0.0
	w.job_chosen.connect(_record)
	w.declined.connect(_record.bind("declined"))
	w.open(LV10, 10, 0)
	w.handle_input(key(KEY_4))
	assert_eq(w.state, "weapon", "Thief has two families: the weapon page follows")
	assert_eq(_got.size(), 0, "nothing is chosen yet")
	assert_eq(w.npc_id, 1052001, "the Thief's instructor (the Dark Lord) speaks")
	assert_eq((w.get_node("Panel/Npc") as WzImage).path, "Npc.wz/1052001.img/stand")
	assert_true((w.get_node("Panel/Npc") as WzImage).visible)
	assert_true(w.body.contains("Which weapon would you like to specialize in?"), w.body)
	assert_eq(_texts(w), ["Claw", "Dagger", "Cancel."], "families in page order, then Cancel")
	assert_eq(w.focus, 0, "the first family is focused")
	w.handle_input(key(KEY_2))
	assert_eq(_got, [400], "choosing Dagger takes the job")
	assert_eq(w.picked_path, "dagger")


func test_job_window_weapon_page_follows_the_given_order() -> void:
	var w := _add(JobAdvanceWindow.new()) as JobAdvanceWindow
	w.confirm_seconds = 0.0
	w.job_chosen.connect(_record)
	w.open(LV30_WARRIOR, 30, 100)
	assert_eq(_texts(w), ["Fighter", "Page", "Spearman", "Not now."])
	assert_eq(w.npc_id, 1022000, "Lv 30: every child shares the line's instructor")
	w.handle_input(key(KEY_2))
	assert_eq(w.state, "weapon")
	assert_eq(_texts(w), ["Sword", "Blunt Weapon", "Cancel."], "Page: Sword listed first")
	assert_eq(w.focus, 0)
	w.handle_input(key(KEY_ENTER))
	assert_eq(_got, [120])
	assert_eq(w.picked_path, "sword")


func test_job_window_three_families_know_their_weapons() -> void:
	var w := _add(JobAdvanceWindow.new()) as JobAdvanceWindow
	w.open(LV10, 10, 0)
	w.select(0)
	assert_eq(_texts(w), ["Sword", "Spear", "Blunt Weapon", "Cancel."])
	assert_eq(w.npc_id, 1022000)
	assert_eq(int(w.entries[1].item_id), 1432000, "each row knows the weapon it gives")
	assert_eq(String(w.entries[1].path), "spear")
	w.handle_input(key(KEY_DOWN))
	w.handle_input(key(KEY_DOWN))
	assert_eq(w.focus, 2)
	w.handle_input(key(KEY_DOWN))
	assert_eq(w.focus, 3, "Cancel is reachable by keys")


func test_job_window_skips_the_weapon_page_without_families() -> void:
	var w := _add(JobAdvanceWindow.new()) as JobAdvanceWindow
	w.confirm_seconds = 0.0
	w.job_chosen.connect(_record)
	w.open(LV10, 10, 0)
	w.handle_input(key(KEY_2))
	assert_eq(_got, [200], "the Magician goes straight through")
	assert_eq(w.picked_path, "", "no path for a job without families")
	w.open(LV30_BOWMAN, 30, 300)
	w.handle_input(key(KEY_1))
	assert_eq(_got, [200, 310], "a single-family branch has no weapon page either")
	assert_eq(w.picked_path, "", "picked_path is only set when a family was chosen")


func test_job_window_confirmation_after_the_weapon_page_is_the_instructors() -> void:
	var w := _add(JobAdvanceWindow.new()) as JobAdvanceWindow
	w.confirm_seconds = 60.0
	w.job_chosen.connect(_record)
	w.open(LV10, 10, 0)
	w.select(3)
	w.select(0)
	assert_eq(w.state, "confirm")
	assert_eq(w.npc_id, 1052001, "the chosen job's instructor")
	assert_true(w.body.begins_with("You are now a Thief!"), w.body)
	assert_eq(_got.size(), 0)
	w.finish()
	assert_eq(_got, [400])
	assert_eq(w.picked_path, "claw")


func test_job_window_cancel_on_the_weapon_page_returns_to_the_list() -> void:
	var w := _add(JobAdvanceWindow.new()) as JobAdvanceWindow
	w.confirm_seconds = 0.0
	w.job_chosen.connect(_record)
	w.declined.connect(_record.bind("declined"))
	w.open(LV10, 10, 0)
	var page_one := w.body
	w.select(3)
	assert_eq(w.state, "weapon")
	w.handle_input(key(KEY_ESCAPE))
	assert_eq(w.state, "choose", "Esc = Cancel goes back, it does not decline")
	assert_true(w.is_open())
	assert_eq(_got.size(), 0, "no signal")
	assert_eq(w.entries.size(), 6, "the job list is back")
	assert_eq(w.focus, 3, "the Thief entry stays focused")
	assert_eq(w.body, page_one)
	assert_eq(w.npc_id, 0, "the list is spoken without a portrait again")
	# The Cancel entry (digit and click) does the same, and another job can be taken afterwards.
	w.select(3)
	w.handle_input(key(KEY_3))
	assert_eq(w.state, "choose", "digit 3 = Cancel on the Thief's page")
	w.select(2)
	w._gui_input(click(w.entry_rect(2).get_center()))
	assert_eq(w.state, "choose", "clicking Cancel")
	assert_eq(_got.size(), 0)
	w.select(2)
	w.select(1)
	assert_eq(_got, [300], "after cancelling, the player can still take a job")
	assert_eq(w.picked_path, "crossbow")


## The window over the shipped job tree: one entry per job, and the weapon pages in the tree's page order.
func test_job_window_over_the_shipped_job_tree() -> void:
	var data := DataRepo.load_all()
	var jobs := JobTree.from_data(data.jobs, data.jobs_survivor)
	var w := _add(JobAdvanceWindow.new()) as JobAdvanceWindow
	w.open(jobs.advancements(0, 10), 10, 0)
	assert_eq(_texts(w).size(), 6, "five jobs and Not now.")
	for t: String in ["Warrior", "Magician", "Bowman", "Thief", "Pirate", "Not now."]:
		assert_true(_texts(w).has(t), t)
	assert_eq(_texts(w).filter(func(t: String) -> bool: return t.begins_with("Thief")).size(), 1, "Thief once")
	var expected := {"Warrior": ["Sword", "Spear", "Blunt Weapon"], "Bowman": ["Bow", "Crossbow"],
		"Thief": ["Claw", "Dagger"], "Pirate": ["Knuckle", "Gun"]}
	for job_name: String in expected:
		w.open(jobs.advancements(0, 10), 10, 0)
		w.select(_texts(w).find(job_name))
		assert_eq(w.state, "weapon", job_name)
		assert_eq(_texts(w).slice(0, -1), expected[job_name], "%s families in page order" % job_name)
	w.open(jobs.advancements(0, 10), 10, 0)
	w.select(_texts(w).find("Magician"))
	assert_eq(w.state, "confirm", "the Magician has no weapon page")
	# Lv 30: the held family leads the Page's list.
	w.open(jobs.advancements(100, 30, "blunt"), 30, 100)
	w.select(_texts(w).find("Page"))
	assert_eq(_texts(w).slice(0, -1), ["Blunt Weapon", "Sword"], "a blunt Warrior sees Blunt first")
	w.open(jobs.advancements(100, 30, "sword"), 30, 100)
	w.select(_texts(w).find("Page"))
	assert_eq(_texts(w).slice(0, -1), ["Sword", "Blunt Weapon"], "a sword Warrior sees Sword first")
	for first_job: int in [300, 400, 500]:
		w.open(jobs.advancements(first_job, 30), 30, first_job)
		for i in w.entries.size() - 1:
			w.select(i)
			assert_eq(w.state, "confirm", "single-family branches skip the weapon page")
			w.open(jobs.advancements(first_job, 30), 30, first_job)


func test_job_window_weapon_rows_name_the_weapon() -> void:
	if not require_cache():
		return
	var w := _add(JobAdvanceWindow.new()) as JobAdvanceWindow
	w.open(LV10, 10, 0)
	w.select(3)
	assert_eq(String(w.entries[0].detail), "Beginner Thief Wrist Guard", "the claw's v83 name")
	assert_eq(String(w.entries[1].detail), "Beginner Thief's short sword")
	w.go_back()
	w.select(0)
	assert_eq(String(w.entries[1].detail), "", "a name equal to the family is not repeated (Spear)")
	assert_eq(String(w.entries[0].detail), "Beginner Warrior's sword")


func test_job_window_not_now_still_defers_with_families_listed() -> void:
	var w := _add(JobAdvanceWindow.new()) as JobAdvanceWindow
	w.job_chosen.connect(_record)
	w.declined.connect(_record.bind("declined"))
	w.open(LV10, 10, 0)
	w.handle_input(key(KEY_6))
	assert_eq(_got, ["declined"], "Not now.")
	w.open(LV10, 10, 0)
	w.handle_input(key(KEY_ESCAPE))
	assert_eq(_got, ["declined", "declined"], "Esc on the list = END CHAT")


func test_job_window_weapon_page_mouse() -> void:
	var w := _add(JobAdvanceWindow.new()) as JobAdvanceWindow
	w.confirm_seconds = 0.0
	w.job_chosen.connect(_record)
	w.open(LV10, 10, 0)
	w._gui_input(click(w.entry_rect(4).get_center()))
	assert_eq(w.state, "weapon", "click on Pirate")
	var move := InputEventMouseMotion.new()
	move.position = w.entry_rect(1).get_center()
	w._gui_input(move)
	assert_eq(w.focus, 1, "hover focuses Gun")
	w._gui_input(click(w.entry_rect(1).get_center()))
	assert_eq(_got, [500])
	assert_eq(w.picked_path, "gun")


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


## Confirmation switches from the opening instructor to the selected job's portrait and name.
func test_job_confirmation_uses_the_selected_jobs_instructor() -> void:
	var choices := [
		{"job_id": 100, "name": "Warrior", "available": true},
		{"job_id": 200, "name": "Magician", "available": true},
		{"job_id": 300, "name": "Bowman", "available": true},
		{"job_id": 400, "name": "Thief - Claw", "available": true},
		{"job_id": 500, "name": "Pirate - Knuckle", "available": true},
	]
	var instructors := [1022000, 1032001, 1012100, 1052001, 1090000]
	var w := _add(JobAdvanceWindow.new()) as JobAdvanceWindow
	w.confirm_seconds = 60.0
	for i in choices.size():
		w.open(choices, 10, 0)
		assert_eq(w.npc_id, 0, "opening list: no portrait across branches")
		assert_true(w.select(i))
		assert_eq(w.npc_id, instructors[i], "selected job supplies the name tag")
		assert_eq((w.get_node("Panel/Npc") as WzImage).path,
			"Npc.wz/%07d.img/stand" % instructors[i], "selected job supplies the portrait")
		w.finish()


## Vowel-sound job names use "an" in both instructor confirmation variants.
func test_job_confirmation_uses_the_job_names_article() -> void:
	for npc in [1052001, 1032001, 1090000]:
		for job_name: String in ["Assassin", "Archer", "Ice Wizard"]:
			assert_true(JobAdvanceWindow.confirm_text(npc, job_name).begins_with("You are now an " + job_name + "!"))
		for job_name: String in ["Bandit", "Thief - Claw", "Pirate - Knuckle", "Magician"]:
			assert_true(JobAdvanceWindow.confirm_text(npc, job_name).begins_with("You are now a " + job_name + "!"))


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
	assert_false(JobAdvanceWindow.intro_text(0, JOB8, 8).contains("Magician?"), "the list intro is generic")
	assert_true(JobAdvanceWindow.intro_text(0, LV10, 10).contains("Lv. 10"))
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
