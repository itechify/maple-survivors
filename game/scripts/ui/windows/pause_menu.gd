class_name PauseMenu
extends MapleWindow
## The pause window: the v83 blue notice box Basic.img/YesNo3 (`t`, `c` repeated, `s`) with its choices as an
## option list (`dot0` bullets, `dot1` and yellow on the focused one) and the orange OK / CANCEL buttons
## (Basic.img/BtOK2, BtCancel2) in its grey strip: OK takes the focused choice, CANCEL resumes.
##
## Choices: 1 Resume, 2 Key Config, 3 Options, 4 Quit round. Keys: Esc (the "pause" action) resumes, the digits take a
## choice, Up/Down + Enter. Quit round first shows the exact round-loss warning; 4/Enter again confirms and emits
## quit_requested. Mouse choices and OK/CANCEL follow the same confirmation path. Key Config and Options emit
## `window_requested(id)` (a WindowStack id) and the menu stays open under that window. In `boundary_mode` (the Free
## Market) the menu is 1 Resume, 2 Save & quit, with no warning.

## Emitted when the player resumes the run.
signal resumed()
## Emitted after the player confirms Quit round (or picks Save & quit at a boundary).
signal quit_requested()
## Emitted when the player picks Key Config ("key_config") or Options ("options"); the menu stays open.
signal window_requested(id: String)

const BOX := "UI.wz/Basic.img/YesNo3/"
const BOX_W := 266.0
const TOP_H := 21.0
const MID_H := 20.0
const BOTTOM_H := 55.0
## Blue plate text area and the grey button strip of `s` (measured from the v83 pieces).
const TEXT_X := 20.0
const TEXT_Y := 17.0
const BUTTON_DY := 24.0
const OPTION_H := 17.0
const CHOICES := ["Resume", "Key Config", "Options", "Quit round"]
## WindowStack ids of the choices that open an in-run window (index -> id).
const WINDOW_CHOICES := {1: "key_config", 2: "options"}
## The Free Market's menu: the hub hosts no in-run windows (tier C: owner #32).
const BOUNDARY_CHOICES := ["Resume", "Save & quit"]
## Hub boundaries save safely without a round-loss confirmation (tier C: owner #32).
var boundary_mode := false
## tier C: owner #32 round-boundary warning, verbatim.
const QUIT_WARNING := "You'll lose this round's progress. Continue later to restart the round from its beginning."
var confirming_quit := false

## Focused choice (index into choices()).
var focus := 0

var _bt_ok: WzButton
var _bt_cancel: WzButton
var _options_y := 0.0


func _init() -> void:
	super._init()
	name = "PauseMenu"
	_bt_ok = WzButton.new("UI.wz/Basic.img/BtOK2")
	_bt_ok.name = "OK"
	_bt_ok.fallback_size = Vector2(47, 18)
	_bt_ok.pressed.connect(func() -> void: activate(focus, false))
	panel.add_child(_bt_ok)
	_bt_cancel = WzButton.new("UI.wz/Basic.img/BtCancel2")
	_bt_cancel.name = "Cancel"
	_bt_cancel.fallback_size = Vector2(47, 18)
	_bt_cancel.pressed.connect(func() -> void: activate(0, false))
	panel.add_child(_bt_cancel)
	_size_content()


func _size_content() -> void:
	var lines := MapleText.wrap(QUIT_WARNING, BOX_W - 2.0 * TEXT_X, MapleText.SIZE, true) if confirming_quit else PackedStringArray(["The game is paused."])
	_options_y = TEXT_Y + lines.size() * MapleText.LINE + 7.0
	var content := _options_y + choices().size() * OPTION_H + 2.0
	var n := TiledFrame.center_count(content - 8.0 + BOTTOM_H, TOP_H, MID_H, BOTTOM_H)
	panel_size = Vector2(BOX_W, TiledFrame.frame_height(n, TOP_H, MID_H, BOTTOM_H))


## The listed choices: CHOICES in a round, BOUNDARY_CHOICES in boundary_mode.
func choices() -> Array:
	return BOUNDARY_CHOICES if boundary_mode else CHOICES


## Opens the menu with "Resume" focused.
func open() -> void:
	confirming_quit = false
	_size_content()
	focus = 0
	_show_window()


## Takes choice `i` (choices()); `click` plays the UI click (the WzButtons play their own). False when closed or out
## of range.
func activate(i: int, click: bool = true) -> bool:
	var quit := choices().size() - 1
	if not _open or i < 0 or i > quit:
		return false
	if click:
		UiArt.play_sound(UiArt.SND_CLICK)
	if not boundary_mode and WINDOW_CHOICES.has(i):
		window_requested.emit(String(WINDOW_CHOICES[i]))
		return true
	if i == quit and not boundary_mode and not confirming_quit:
		confirming_quit = true
		focus = quit
		_size_content()
		panel.queue_redraw()
		return true
	_hide_window()
	if i == 0:
		resumed.emit()
	else:
		quit_requested.emit()
	return true


## Window-coordinate rect of choice `i`.
func choice_rect(i: int) -> Rect2:
	return Rect2(panel.position + Vector2(TEXT_X, _options_y + i * OPTION_H), Vector2(BOX_W - 2.0 * TEXT_X, OPTION_H))


## Handles pause choices and quit confirmation while the window is open.
func handle_input(event: InputEvent) -> bool:
	if not _open:
		return false
	if MapleWindow.is_cancel(event):
		activate(0)
		return true
	var n := choices().size()
	var d := MapleWindow.digit_of(event)
	if d >= 1 and d <= n:
		activate(d - 1)
		return true
	var step := MapleWindow.vertical_step(event)
	if step != 0:
		_set_focus((focus + step + n) % n)
		return true
	if MapleWindow.is_confirm(event):
		activate(focus)
		return true
	return event is InputEventKey and (event as InputEventKey).pressed


func _panel_gui_input(event: InputEvent, local: Vector2) -> void:
	var hit := -1
	for i in choices().size():
		if Rect2(Vector2(TEXT_X, _options_y + i * OPTION_H), Vector2(BOX_W - 2.0 * TEXT_X, OPTION_H)).has_point(local):
			hit = i
	if hit < 0:
		return
	if event is InputEventMouseMotion:
		_set_focus(hit)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			activate(hit)


func _set_focus(i: int) -> void:
	if i != focus:
		focus = i
		UiArt.play_sound(UiArt.SND_OVER)
		panel.queue_redraw()


func _layout_children() -> void:
	if _bt_ok == null:
		return
	var y := panel_size.y - BOTTOM_H + BUTTON_DY
	_bt_cancel.position = Vector2(BOX_W - 14.0 - _bt_cancel.size.x, y)
	_bt_ok.position = Vector2(_bt_cancel.position.x - 4.0 - _bt_ok.size.x, y)


func _draw_panel(ci: Control) -> void:
	var h := TiledFrame.draw_v(ci, Vector2.ZERO, UiArt.frame(BOX + "t"), UiArt.frame(BOX + "c"), UiArt.frame(BOX + "s"),
		panel_size.y)
	if h <= 0.0:
		ci.draw_rect(Rect2(Vector2.ZERO, panel_size), Color8(68, 136, 187))
	var lines := MapleText.wrap(QUIT_WARNING, BOX_W - 2.0 * TEXT_X, MapleText.SIZE, true) if confirming_quit else PackedStringArray(["The game is paused."])
	for i in lines.size():
		MapleText.draw(ci, Vector2(TEXT_X, TEXT_Y + i * MapleText.LINE), lines[i], MapleText.WHITE, MapleText.SIZE, true, 0,
			Color8(17, 85, 153), true)
	var dot0 := UiArt.frame("UI.wz/UIWindow.img/UtilDlgEx/dot0")
	var dot1 := UiArt.frame("UI.wz/UIWindow.img/UtilDlgEx/dot1")
	var listed := choices()
	for i in listed.size():
		var y := _options_y + i * OPTION_H
		var dot := dot1 if i == focus else dot0
		if dot != null:
			UiArt.blit(ci, dot, Vector2(TEXT_X + 2.0, y + 5.0))
		var col := MapleText.YELLOW if i == focus else MapleText.WHITE
		MapleText.draw(ci, Vector2(TEXT_X + 12.0, y), "%d. %s" % [i + 1, listed[i]], col, MapleText.SIZE, i == focus,
			0, Color8(17, 85, 153), true)
