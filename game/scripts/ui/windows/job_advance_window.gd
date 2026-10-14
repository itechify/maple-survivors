class_name JobAdvanceWindow
extends MapleWindow
## The job advancement dialog (docs/ARCHITECTURE.md 4.4.2 `job_advance_pending`, GAME_DESIGN section 9), drawn as the
## classic v83 NPC dialog UIWindow.img/UtilDlgEx: `t`, `c` repeated, `s`; the job instructor (Npc.wz/<id>.img/stand,
## animated) stands in the grey left panel over the `bar` name tag (name from String.wz/Npc.img/<id>/name); the text
## is on the right in the NPC voice, the jobs are an option list (blue text, `dot0` bullets, `dot1` on the focused one).
##
## Instructor: the branch of the first available option (Warrior 1022000 Dances with Balrog, Magician 1032001 Grendel
## the Really Old, Bowman 1012100 Athena Pierce, Thief 1052001 Dark Lord, Pirate 1090000 Kyrin); with nothing
## available the branch of the current job; Beginners with nothing available meet the Maple Administrator 9010000.
##
## Options: available jobs are selectable; unavailable ones are grey with their reason ("Lv. 10", "Not in this build");
## "Not now." and the END CHAT button (UtilDlgEx/BtClose) call `declined`. With no available option the dialog only
## says so and shows OK (UtilDlgEx/BtOK), which declines.
##
## Timing contract for the run scene: `declined` is emitted at once. After a job is picked the dialog shows a one-line
## confirmation and `job_chosen` is emitted when the dialog closes: after `confirm_seconds`, or earlier on any key or
## click. So the next window (the level-up choice) never opens under the confirmation.
## Keys: Up/Down + Enter, digits 1-9 pick the n-th entry, Esc = END CHAT (or OK).

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

## Seconds the confirmation line stays before the dialog closes by itself (0 = close at once).
var confirm_seconds := CONFIRM_SECONDS
## The job_advance_pending options ({job_id, name, available, reason}).
var options: Array = []
var level := 0
var current_job_id := 0
## The instructor NPC shown.
var npc_id := ADMIN
## Entries in display order: {"kind": "job"|"decline", "job_id", "text", "available", "reason"}.
var entries: Array[Dictionary] = []
## Focused entry index (-1 = none).
var focus := -1
## "choose" (list shown) or "confirm" (a job was picked, waiting to close).
var state := "choose"
## The dialog text (wrapped lines are computed from it).
var body := ""

var _lines: PackedStringArray = []
var _picked := -1
var _confirm_t := 0.0
var _npc: WzImage
var _bt_close: WzButton
var _bt_ok: WzButton
var _options_y := 0.0


func _init() -> void:
	super._init()
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


## Opens the dialog for the options of a job_advance_pending event.
func open(p_options: Array, p_level: int, p_current_job_id: int) -> void:
	options = p_options.duplicate(true)
	level = p_level
	current_job_id = p_current_job_id
	npc_id = instructor_for(options, current_job_id)
	state = "choose"
	_picked = -1
	_confirm_t = 0.0
	entries.clear()
	for o: Variant in options:
		if not (o is Dictionary):
			continue
		var d: Dictionary = o
		entries.append({"kind": "job", "job_id": int(d.get("job_id", 0)), "text": String(d.get("name", "")),
			"available": bool(d.get("available", false)), "reason": String(d.get("reason", ""))})
	if any_available():
		entries.append({"kind": "decline", "job_id": -1, "text": "Not now.", "available": true, "reason": ""})
	focus = _next_selectable(-1, 1)
	body = intro_text(npc_id, options, level)
	_npc.path = "Npc.wz/%07d.img/stand" % npc_id
	_build_layout()
	_show_window()


## True when at least one option can be taken.
func any_available() -> bool:
	for e in entries:
		if e.kind == "job" and e.available:
			return true
	return false


## Picks entry `i`: a job enters the confirmation (job_chosen follows when the dialog closes), "Not now." declines.
## False when the entry is not selectable.
func select(i: int) -> bool:
	if not _open or state != "choose" or i < 0 or i >= entries.size() or not entries[i].available:
		return false
	if entries[i].kind == "decline":
		decline()
		return true
	_picked = int(entries[i].job_id)
	focus = i
	state = "confirm"
	_confirm_t = 0.0
	body = confirm_text(npc_id, String(entries[i].text))
	UiArt.play_sound(UiArt.SND_CLICK)
	_build_layout()
	if confirm_seconds <= 0.0:
		finish()
	return true


## Ends the confirmation: closes the dialog and emits job_chosen (no-op outside the confirmation).
func finish() -> void:
	if state != "confirm" or _picked < 0:
		return
	var job := _picked
	_picked = -1
	state = "done"
	_hide_window()
	job_chosen.emit(job)


## Declines (END CHAT, "Not now.", OK with nothing available): closes and emits declined.
func decline() -> void:
	if not _open or state != "choose":
		return
	state = "done"
	_hide_window()
	declined.emit()


## The instructor NPC id for a set of options (see the class doc).
@warning_ignore("integer_division")
static func instructor_for(p_options: Array, p_current_job_id: int) -> int:
	for o: Variant in p_options:
		if o is Dictionary and bool(o.get("available", false)):
			return INSTRUCTORS.get(branch_of(int(o.get("job_id", 0))), ADMIN)
	return INSTRUCTORS.get(branch_of(p_current_job_id), ADMIN)


## The first-job branch of a job id (210 -> 200, 0 -> 0).
@warning_ignore("integer_division")
static func branch_of(job_id: int) -> int:
	return 0 if job_id < 100 else (job_id / 100) * 100


## The NPC's words when the dialog opens.
static func intro_text(p_npc: int, p_options: Array, p_level: int) -> String:
	var first := ""
	var second_job := false
	for o: Variant in p_options:
		if o is Dictionary:
			if int(o.get("job_id", 0)) % 100 != 0:
				second_job = true
			if first == "" and bool(o.get("available", false)):
				first = String(o.get("name", ""))
	if first == "":
		match p_npc:
			1032001:
				return "Hmm... you have grown much wiser since we last met. But the next path of magic is not open to you yet. Come back to me later, young one."
			ADMIN:
				return "Hello there! You have reached Lv. %d. There is no new job for you to take right now, so keep training!" % p_level
		return "You have grown stronger... but the road ahead is not open yet. Come back to me later."
	if p_npc == ADMIN:
		return "Hello there! You have reached Lv. %d, so a new path is open to you. Which job would you like?" % p_level
	if second_job:
		return "You have come a long way. The time has come for your 2nd job advancement. Which path will you walk?"
	match p_npc:
		1032001:
			return "So you want to become a %s? Hmm... I can see the spark of magic in your eyes. Magic is not something you can learn in a day, but you have come far on your own. Choose your path, young one." % first
		1022000:
			return "So you want to become a %s? Strength and courage are all it takes. Choose your path." % first
		1012100:
			return "So you want to become a %s? Keen eyes and a steady hand will serve you well. Choose your path." % first
		1052001:
			return "So you want to become a %s? Hmph. Only the quick survive in the shadows. Choose your path." % first
		1090000:
			return "Ahoy! So you want to become a %s? The sea always has room for one more. Choose your path." % first
	return "So you want to become a %s? Choose your path." % first


## The one-line confirmation after a job is picked.
static func confirm_text(p_npc: int, job_name: String) -> String:
	if p_npc == 1032001:
		return "You are now a %s! Use your new power wisely..." % job_name
	return "You are now a %s! Congratulations!" % job_name


func handle_input(event: InputEvent) -> bool:
	if not _open:
		return false
	if state == "confirm":
		if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
			finish()
			return true
		return false
	if not any_available():
		if MapleWindow.is_confirm(event) or MapleWindow.is_cancel(event):
			UiArt.play_sound(UiArt.SND_CLICK)
			decline()
			return true
		return event is InputEventKey and (event as InputEventKey).pressed
	if MapleWindow.is_cancel(event):
		UiArt.play_sound(UiArt.SND_CLICK)
		decline()
		return true
	var d := MapleWindow.digit_of(event)
	if d >= 1:
		select(d - 1)
		return true
	var step := MapleWindow.vertical_step(event)
	if step != 0:
		_set_focus(_next_selectable(focus, step))
		return true
	if MapleWindow.is_confirm(event):
		select(focus)
		return true
	return event is InputEventKey and (event as InputEventKey).pressed


## Top-left of entry `i`'s line in window coordinates (empty when out of range or not listed).
func entry_rect(i: int) -> Rect2:
	if state != "choose" or i < 0 or i >= entries.size():
		return Rect2()
	return Rect2(panel.position + Vector2(TEXT_X, _options_y + i * OPTION_H), Vector2(TEXT_W, OPTION_H))


func _process(delta: float) -> void:
	super._process(delta)
	if state == "confirm" and _open:
		_confirm_t += delta
		if _confirm_t >= confirm_seconds:
			finish()


func _panel_gui_input(event: InputEvent, local: Vector2) -> void:
	if state == "confirm":
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
			finish()
		return
	if state != "choose" or not any_available():
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
		_set_focus(hit)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			select(hit)


func _set_focus(i: int) -> void:
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
	var content_bottom := _options_y + (entries.size() * OPTION_H if state == "choose" else 0.0)
	var npc_h := 150.0
	var f := _npc.current_frame()
	if f != null:
		npc_h = maxf(80.0, f.origin.y)
	# The NPC stands on the name bar at the bottom of the grey panel: s top - 7 is the bar, feet 2 px above it.
	var need_s_top := maxf(content_bottom - 2.0, npc_h + 18.0)
	if state != "choose":
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
	_bt_ok.position = Vector2(DLG_W - 13.0 - _bt_ok.size.x, s_top + BUTTON_DY)
	var choosing := state == "choose"
	_bt_close.visible = choosing and any_available()
	_bt_ok.visible = choosing and not any_available()


func _draw_panel(ci: Control) -> void:
	_layout_children()
	var h := TiledFrame.draw_v(ci, Vector2.ZERO, UiArt.frame(DLG + "t"), UiArt.frame(DLG + "c"),
		UiArt.frame(DLG + "s"), panel_size.y)
	if h <= 0.0:
		ci.draw_rect(Rect2(Vector2.ZERO, panel_size), Color8(238, 238, 238))
	var s_top := panel_size.y - BOTTOM_H
	var bar := UiArt.frame(DLG + "bar")
	var bar_pos := Vector2(NPC_X - 60.0, s_top - 7.0)
	UiArt.blit(ci, bar, bar_pos)
	var npc_name := UiArt.text("String.wz/Npc.img/%d/name" % npc_id)
	var bold := MapleText.width(npc_name, MapleText.SMALL, true) <= 115.0
	MapleText.draw_centered(ci, bar_pos.x, bar_pos.y + 3.0, 121.0, MapleText.ellipsize(npc_name, 117.0, MapleText.SMALL,
		bold), MapleText.WHITE, MapleText.SMALL, bold)
	var y := TEXT_Y
	for line in _lines:
		MapleText.draw(ci, Vector2(TEXT_X, y), line, MapleText.NPC_TEXT)
		y += MapleText.LINE
	if state != "choose":
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
		if not e.available and String(e.reason) != "":
			t += "  (%s)" % e.reason
		MapleText.draw(ci, Vector2(TEXT_X + 12.0, ey), t, col, MapleText.SIZE, i == focus)
