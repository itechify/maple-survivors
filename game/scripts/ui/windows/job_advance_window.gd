class_name JobAdvanceWindow
extends MapleWindow
## The job advancement dialog (docs/ARCHITECTURE.md 4.4.2 `job_advance_pending`, GAME_DESIGN section 9), drawn as the
## classic v83 NPC dialog UIWindow.img/UtilDlgEx: `t`, `c` repeated, `s`; the job instructor (Npc.wz/<id>.img/stand,
## animated) stands in the grey left panel over the `bar` name tag (name from String.wz/Npc.img/<id>/name); the text
## is on the right in the NPC voice, the choices are an option list (blue text, `dot0` bullets, `dot1` on the focused one).
##
## Two pages (spec #226). Page 1 ("choose") has a generic intro and one entry per job plus "Not now."; a job with
## several weapon families (`paths` of the option, in page order, JobTree.advancements) opens page 2 ("weapon"),
## "Which weapon would you like to specialize in?", one row per family with the weapon it gives and a "Cancel." row
## that returns to page 1 (Esc and the Prev button do the same; neither declines). A job with no or one family (the
## Magicians, the single-family branches) goes straight to the confirmation. `picked_path` is the chosen family's id
## ("" for a job without a page).
##
## Speakers: page 2 and the confirmation are the chosen job's instructor (Warrior 1022000 Dances with Balrog, Magician
## 1032001 Grendel the Really Old, Bowman 1012100 Athena Pierce, Thief 1052001 Dark Lord, Pirate 1090000 Kyrin). Page 1
## has the line's instructor when every option belongs to one line (Lv 30); across lines (Lv 10) it has no portrait,
## text only (tier C: no single instructor speaks for every job). With nothing available the dialog is spoken by the
## current job's instructor, or the Maple Administrator 9010000 for a Beginner.
##
## Options: available jobs are selectable; unavailable ones are grey with their reason ("Lv. 10", "Not in this build");
## "Not now." and the END CHAT button (UtilDlgEx/BtClose) call `declined`. With no available option the dialog only
## says so and shows OK (UtilDlgEx/BtOK), which declines.
##
## Timing contract for the run scene: `declined` is emitted at once. After a job is picked the dialog shows a one-line
## confirmation and `job_chosen` is emitted when the dialog closes: after `confirm_seconds`, or earlier on any key or
## click. So the next window (the level-up choice) never opens under the confirmation.
## Keys: Up/Down + Enter, digits 1-9 pick the n-th entry, Esc = END CHAT on page 1, Cancel on page 2 (or OK).

## Emitted when the dialog closes after a job was picked.
signal job_chosen(job_id: int)
## Emitted when the player declines ("Not now.", END CHAT, or OK when nothing is available).
signal declined()

const DLG := "UI.wz/UIWindow.img/UtilDlgEx/"
const DLG_W := 529.0
const TOP_H := 28.0
const MID_H := 20.0
const BOTTOM_H := 58.0
## Text area (white part of the dialog) and the grey NPC panel, measured from the v83 pieces.
const TEXT_X := 162.0
const TEXT_W := 334.0
const TEXT_Y := 24.0
const NPC_X := 78.0
## Bottom button strip of `s`: buttons are 18 px tall in rows 28..52.
const BUTTON_DY := 32.0
const OPTION_H := 17.0
## NPC ids: branch -> instructor; fallback.
const INSTRUCTORS := {100: 1022000, 200: 1032001, 300: 1012100, 400: 1052001, 500: 1090000}
const ADMIN := 9010000
## Confirmation time before job_chosen is emitted (s). tier C: ours.
const CONFIRM_SECONDS := 1.8
## What the instructor asks on the weapon page. tier C: ours (the v83 job NPCs do not ask this).
const WEAPON_TEXT := "Which weapon would you like to specialize in? I will hand you one to start with, so choose the one you want to fight with."

## Window states (`state`) and entry kinds (`entries[i].kind`); the strings are what tests and the flow driver read.
const STATE_CHOOSE := "choose"
const STATE_WEAPON := "weapon"
const STATE_CONFIRM := "confirm"
const STATE_DONE := "done"
const KIND_JOB := "job"
const KIND_DECLINE := "decline"
const KIND_PATH := "path"
const KIND_BACK := "back"

## Seconds the confirmation line stays before the dialog closes by itself (0 = close at once).
var confirm_seconds := CONFIRM_SECONDS
## The job_advance_pending options ({job_id, name, available, reason, paths: [{id, label, item_id, family}]}).
var options: Array = []
var level := 0
var current_job_id := 0
## The instructor NPC shown (0 = none: text only).
var npc_id := ADMIN
## Entries of the page shown, in display order. Page 1: {"kind": KIND_JOB|KIND_DECLINE, job_id, text, available, reason, paths}.
## Weapon page: {"kind": KIND_PATH|KIND_BACK}; a path is {job_id, path, text (the family), item_id, detail (the weapon's
## name), available}, "back" is "Cancel.".
var entries: Array[Dictionary] = []
## Focused entry index (-1 = none).
var focus := -1
## "choose" (page 1, the jobs), "weapon" (page 2, the families of the picked job) or "confirm" (a job was picked,
## waiting to close).
var state := STATE_CHOOSE
## The weapon path of the picked entry ("" for a job without a weapon page); read it when job_chosen fires.
var picked_path := ""
## The dialog text (wrapped lines are computed from it).
var body := ""

var _lines: PackedStringArray = []
var _job_entries: Array[Dictionary] = []
var _list_npc := 0
var _list_body := ""
var _weapon_job := -1
var _picked := -1
var _confirm_t := 0.0
var _npc: WzImage
var _bt_close: WzButton
var _bt_ok: WzButton
var _bt_prev: WzButton
var _options_y := 0.0


func _init() -> void:
	super._init()
	window_hotkeys = true
	name = "JobAdvanceWindow"
	panel_size = Vector2(DLG_W, 246)
	_npc = WzImage.new()
	_npc.name = "Npc"
	panel.add_child(_npc)
	_bt_close = WzButton.new(DLG + "BtClose")
	_bt_close.name = "EndChat"
	_bt_close.fallback_size = Vector2(85, 18)
	_bt_close.pressed.connect(decline)
	panel.add_child(_bt_close)
	_bt_ok = WzButton.new(DLG + "BtOK")
	_bt_ok.name = "OK"
	_bt_ok.pressed.connect(decline)
	panel.add_child(_bt_ok)
	_bt_prev = WzButton.new(DLG + "BtPrev")
	_bt_prev.name = "Prev"
	_bt_prev.fallback_size = Vector2(50, 18)
	_bt_prev.pressed.connect(go_back)
	panel.add_child(_bt_prev)


## Opens the dialog for the options of a job_advance_pending event.
func open(p_options: Array, p_level: int, p_current_job_id: int) -> void:
	options = p_options.duplicate(true)
	level = p_level
	current_job_id = p_current_job_id
	_picked = -1
	picked_path = ""
	_weapon_job = -1
	_confirm_t = 0.0
	_job_entries.clear()
	for o: Variant in options:
		if not (o is Dictionary):
			continue
		var d: Dictionary = o
		_job_entries.append({"kind": KIND_JOB, "job_id": int(d.get("job_id", 0)), "path": "",
			"text": String(d.get("name", "")), "available": bool(d.get("available", false)),
			"reason": String(d.get("reason", "")), "paths": JobTree.clean_paths(d.get("paths", []))})
	if any_available():
		_job_entries.append({"kind": KIND_DECLINE, "job_id": -1, "path": "", "text": "Not now.", "available": true,
			"reason": "", "paths": []})
	_list_npc = list_speaker(options, current_job_id)
	_list_body = intro_text(_list_npc, options, level)
	_show_list(-1)
	_show_window()


## True when at least one job on page 1 can be taken.
func any_available() -> bool:
	for e in _job_entries:
		if e.kind == KIND_JOB and e.available:
			return true
	return false


## Picks entry `i` of the page shown: "Not now." declines, a job with several families opens the weapon page, any other
## job (or a family) enters the confirmation (job_chosen follows when the dialog closes), "Cancel." goes back.
## False when the entry is not selectable.
func select(i: int) -> bool:
	if not _open or not listing() or i < 0 or i >= entries.size() or not entries[i].available:
		return false
	var e: Dictionary = entries[i]
	match String(e.kind):
		KIND_DECLINE:
			decline()
		KIND_BACK:
			go_back()
		KIND_JOB:
			if (e.paths as Array).size() >= 2:
				UiArt.play_sound(UiArt.SND_CLICK)
				_show_weapons(i)
			else:
				_confirm(i, int(e.job_id), "", String(e.text))
		KIND_PATH:
			_confirm(i, int(e.job_id), String(e.path), _job_name(int(e.job_id)))
	return true


## True while a page with entries is shown (page 1 or the weapon page).
func listing() -> bool:
	return state == STATE_CHOOSE or state == STATE_WEAPON


## Cancel on the weapon page: back to the job list with that job focused (no-op elsewhere).
func go_back() -> void:
	if not _open or state != STATE_WEAPON:
		return
	var idx := -1
	for i in _job_entries.size():
		if _job_entries[i].kind == KIND_JOB and int(_job_entries[i].job_id) == _weapon_job:
			idx = i
	UiArt.play_sound(UiArt.SND_CLICK)
	_show_list(idx)


## Ends the confirmation: closes the dialog and emits job_chosen (no-op outside the confirmation).
func finish() -> void:
	if state != STATE_CONFIRM or _picked < 0:
		return
	var job := _picked
	_picked = -1
	state = STATE_DONE
	_hide_window()
	job_chosen.emit(job)


## Declines (END CHAT, "Not now.", OK with nothing available): closes and emits declined.
func decline() -> void:
	if not _open or state != STATE_CHOOSE:
		return
	state = STATE_DONE
	_hide_window()
	declined.emit()


## The instructor NPC id for a set of options (see the class doc): the branch of the first available option; with
## nothing available the branch of the current job.
@warning_ignore("integer_division")
static func instructor_for(p_options: Array, p_current_job_id: int) -> int:
	for o: Variant in p_options:
		if o is Dictionary and bool(o.get("available", false)):
			return INSTRUCTORS.get(branch_of(int(o.get("job_id", 0))), ADMIN)
	return INSTRUCTORS.get(branch_of(p_current_job_id), ADMIN)


## Who speaks page 1: the line's instructor when every option is one line's job (Lv 30), nobody (0) when the options
## span several lines (Lv 10; tier C), and with nothing available the current job's instructor or the Administrator.
static func list_speaker(p_options: Array, p_current_job_id: int) -> int:
	var branches := {}
	var any := false
	for o: Variant in p_options:
		if o is Dictionary:
			branches[branch_of(int(o.get("job_id", 0)))] = true
			any = any or bool(o.get("available", false))
	if not any:
		return instructor_for([], p_current_job_id)
	if branches.size() == 1:
		return INSTRUCTORS.get(int(branches.keys()[0]), ADMIN)
	return 0


## The first-job branch of a job id (210 -> 200, 0 -> 0).
@warning_ignore("integer_division")
static func branch_of(job_id: int) -> int:
	return 0 if job_id < 100 else (job_id / 100) * 100


## The words of page 1: a generic introduction when a job can be taken (no instructor-specific wording, tier C), the
## instructor's "not yet" when none can.
static func intro_text(p_npc: int, p_options: Array, p_level: int) -> String:
	var any := false
	var second_job := false
	for o: Variant in p_options:
		if o is Dictionary:
			if int(o.get("job_id", 0)) % 100 != 0:
				second_job = true
			any = any or bool(o.get("available", false))
	if not any:
		match p_npc:
			1032001:
				return "Hmm... you have grown much wiser since we last met. But the next path of magic is not open to you yet. Come back to me later, young one."
			ADMIN:
				return "Hello there! You have reached Lv. %d. There is no new job for you to take right now, so keep training!" % p_level
		return "You have grown stronger... but the road ahead is not open yet. Come back to me later."
	if second_job:
		return "You have come a long way. The time has come for your 2nd job advancement. Which path will you walk?"
	return "You have reached Lv. %d, so a path of your own is open to you. Which job would you like to take? Choose carefully." % p_level


## The one-line confirmation after a job is picked.
static func confirm_text(p_npc: int, job_name: String) -> String:
	# Current job names that begin with a vowel also begin with a vowel sound.
	var article := "an" if job_name.strip_edges().left(1).to_lower() in ["a", "e", "i", "o", "u"] else "a"
	if p_npc == 1032001:
		return "You are now %s %s! Use your new power wisely..." % [article, job_name]
	return "You are now %s %s! Congratulations!" % [article, job_name]


func handle_input(event: InputEvent) -> bool:
	if not _open:
		return false
	if state == STATE_CONFIRM:
		if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
			finish()
			return true
		return false
	if state == STATE_CHOOSE and not any_available():
		if MapleWindow.is_confirm(event) or MapleWindow.is_cancel(event):
			UiArt.play_sound(UiArt.SND_CLICK)
			decline()
			return true
		return event is InputEventKey and (event as InputEventKey).pressed
	if MapleWindow.is_cancel(event):
		if state == STATE_WEAPON:
			go_back()
		else:
			UiArt.play_sound(UiArt.SND_CLICK)
			decline()
		return true
	var d := MapleWindow.digit_of(event)
	if d >= 1:
		select(d - 1)
		return true
	var step := MapleWindow.vertical_step(event)
	if step != 0:
		set_focus(_next_selectable(focus, step))
		return true
	if MapleWindow.is_confirm(event):
		select(focus)
		return true
	return event is InputEventKey and (event as InputEventKey).pressed


## Top-left of entry `i`'s line in window coordinates (empty when out of range or not listed).
func entry_rect(i: int) -> Rect2:
	if not listing() or i < 0 or i >= entries.size():
		return Rect2()
	return Rect2(panel.position + Vector2(TEXT_X, _options_y + i * OPTION_H), Vector2(TEXT_W, OPTION_H))


func _process(delta: float) -> void:
	super._process(delta)
	if state == STATE_CONFIRM and _open:
		_confirm_t += delta
		if _confirm_t >= confirm_seconds:
			finish()


func _panel_gui_input(event: InputEvent, local: Vector2) -> void:
	if state == STATE_CONFIRM:
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
			finish()
		return
	if not listing() or (state == STATE_CHOOSE and not any_available()):
		return
	var hit := -1
	var off := Vector2(TEXT_X, _options_y)
	for i in entries.size():
		if Rect2(off + Vector2(0, i * OPTION_H), Vector2(TEXT_W, OPTION_H)).has_point(local):
			hit = i
			break
	if hit < 0 or not entries[hit].available:
		return
	if event is InputEventMouseMotion:
		set_focus(hit)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			select(hit)


func _job_name(job_id: int) -> String:
	for e in _job_entries:
		if e.kind == KIND_JOB and int(e.job_id) == job_id:
			return String(e.text)
	return ""


## Shows page 1 with entry `focus_idx` focused (-1: the first selectable one).
func _show_list(focus_idx: int) -> void:
	state = STATE_CHOOSE
	_weapon_job = -1
	entries = _job_entries.duplicate()
	focus = focus_idx if focus_idx >= 0 else _next_selectable(-1, 1)
	body = _list_body
	_set_speaker(_list_npc)
	_build_layout()


## Shows the weapon page of job entry `i`: its families in the given order, then Cancel.
func _show_weapons(i: int) -> void:
	var job: Dictionary = entries[i]
	_weapon_job = int(job.job_id)
	state = STATE_WEAPON
	var rows: Array[Dictionary] = []
	for p: Dictionary in job.paths:
		var item := weapon_name(int(p.item_id))
		rows.append({"kind": KIND_PATH, "job_id": _weapon_job, "path": String(p.id), "text": String(p.label),
			"item_id": int(p.item_id), "detail": "" if item.to_lower() == String(p.label).to_lower() else item,
			"available": true, "reason": ""})
	rows.append({"kind": KIND_BACK, "job_id": _weapon_job, "path": "", "text": "Cancel.", "item_id": 0, "detail": "",
		"available": true, "reason": ""})
	entries = rows
	focus = 0
	body = WEAPON_TEXT
	_set_speaker(instructor_for([], _weapon_job))
	_build_layout()


## Enters the confirmation for the chosen job (and family) spoken by that job's instructor.
func _confirm(i: int, job_id: int, path: String, job_name: String) -> void:
	_picked = job_id
	picked_path = path
	focus = i
	state = STATE_CONFIRM
	_confirm_t = 0.0
	_set_speaker(instructor_for([], job_id))
	body = confirm_text(npc_id, job_name)
	UiArt.play_sound(UiArt.SND_CLICK)
	_build_layout()
	if confirm_seconds <= 0.0:
		finish()


func _set_speaker(p_npc: int) -> void:
	npc_id = p_npc
	_npc.visible = p_npc != 0
	_npc.path = "Npc.wz/%07d.img/stand" % p_npc if p_npc != 0 else ""


## The item's v83 name from String.wz ("" without the asset cache).
static func weapon_name(item_id: int) -> String:
	return UiArt.text(InventoryModel.name_path(item_id)) if item_id > 0 else ""


## Moves the focus to entry `i` (ignored for -1 or the current one).
func set_focus(i: int) -> void:
	if i != focus and i >= 0:
		focus = i
		UiArt.play_sound(UiArt.SND_OVER)
		panel.queue_redraw()


func _next_selectable(from: int, step: int) -> int:
	var n := entries.size()
	if n == 0:
		return -1
	var i := from
	for _k in n:
		i = (i + step + n) % n if i >= 0 else (0 if step > 0 else n - 1)
		if entries[i].available:
			return i
	return -1


func _build_layout() -> void:
	_lines = MapleText.wrap(body, TEXT_W, MapleText.SIZE)
	var text_h := _lines.size() * MapleText.LINE
	_options_y = TEXT_Y + text_h + 10.0
	var content_bottom := _options_y + (entries.size() * OPTION_H if listing() else 0.0)
	var npc_h := 150.0
	var f := _npc.current_frame()
	if f != null:
		npc_h = maxf(80.0, f.origin.y)
	if npc_id == 0:
		npc_h = 0.0
	# The NPC stands on the name bar at the bottom of the grey panel: s top - 7 is the bar, feet 2 px above it.
	var need_s_top := maxf(content_bottom - 2.0, npc_h + 18.0)
	if npc_id == 0:
		need_s_top = maxf(content_bottom - 2.0, 100.0)
	if state == STATE_CONFIRM:
		need_s_top = maxf(need_s_top, panel_size.y - BOTTOM_H)
	var n := TiledFrame.center_count(need_s_top + BOTTOM_H, TOP_H, MID_H, BOTTOM_H)
	panel_size = Vector2(DLG_W, TiledFrame.frame_height(n, TOP_H, MID_H, BOTTOM_H))
	panel.queue_redraw()


func _layout_children() -> void:
	if _npc == null:
		return
	var s_top := panel_size.y - BOTTOM_H
	_npc.position = Vector2.ZERO
	_npc.anchor = Vector2(NPC_X, s_top - 9.0)
	_bt_close.position = Vector2(13, s_top + BUTTON_DY)
	_bt_prev.position = Vector2(13, s_top + BUTTON_DY)
	_bt_ok.position = Vector2(DLG_W - 13.0 - _bt_ok.size.x, s_top + BUTTON_DY)
	var page_one := state == STATE_CHOOSE
	_bt_close.visible = page_one and any_available()
	_bt_prev.visible = state == STATE_WEAPON
	_bt_ok.visible = page_one and not any_available()


func _draw_panel(ci: Control) -> void:
	_layout_children()
	var h := TiledFrame.draw_v(ci, Vector2.ZERO, UiArt.frame(DLG + "t"), UiArt.frame(DLG + "c"),
		UiArt.frame(DLG + "s"), panel_size.y)
	if h <= 0.0:
		ci.draw_rect(Rect2(Vector2.ZERO, panel_size), Color8(238, 238, 238))
	var s_top := panel_size.y - BOTTOM_H
	if npc_id != 0:
		var bar := UiArt.frame(DLG + "bar")
		var bar_pos := Vector2(NPC_X - 60.0, s_top - 7.0)
		UiArt.blit(ci, bar, bar_pos)
		var npc_name := UiArt.text("String.wz/Npc.img/%d/name" % npc_id)
		var bold := MapleText.width(npc_name, MapleText.SMALL, true) <= 115.0
		MapleText.draw_centered(ci, bar_pos.x, bar_pos.y + 3.0, 121.0, MapleText.ellipsize(npc_name, 117.0,
			MapleText.SMALL, bold), MapleText.WHITE, MapleText.SMALL, bold)
	var y := TEXT_Y
	for line in _lines:
		MapleText.draw(ci, Vector2(TEXT_X, y), line, MapleText.NPC_TEXT)
		y += MapleText.LINE
	if not listing():
		return
	var dot0 := UiArt.frame(DLG + "dot0")
	var dot1 := UiArt.frame(DLG + "dot1")
	for i in entries.size():
		var e: Dictionary = entries[i]
		var ey := _options_y + i * OPTION_H
		var col := MapleText.NPC_BLUE if e.available else MapleText.GREY
		var dot := dot1 if i == focus else dot0
		if dot != null:
			UiArt.blit(ci, dot, Vector2(TEXT_X + 2.0, ey + 5.0))
		var t := String(e.text)
		if not e.available and String(e.get("reason", "")) != "":
			t += "  (%s)" % e.reason
		MapleText.draw(ci, Vector2(TEXT_X + 12.0, ey), t, col, MapleText.SIZE, i == focus)
		var detail := String(e.get("detail", ""))
		if detail != "":
			var dx := MapleText.width(t, MapleText.SIZE, i == focus) + 8.0
			MapleText.draw(ci, Vector2(TEXT_X + 12.0 + dx, ey), "(%s)" % detail, MapleText.NPC_TEXT)
