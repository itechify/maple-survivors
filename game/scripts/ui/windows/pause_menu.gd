class_name PauseMenu
extends MapleWindow
## The pause window: the v83 blue notice box Basic.img/YesNo3 (`t`, `c` repeated, `s`) with the two choices as an
## option list (`dot0` bullets, `dot1` and yellow on the focused one) and the orange OK / CANCEL buttons
## (Basic.img/BtOK2, BtCancel2) in its grey strip: OK takes the focused choice, CANCEL resumes.
##
## Choices: 1 Resume, 2 Key Config, 3 Options, 4 Quit to stage select. Keys: Esc (the "pause" action) resumes, the
## digits take a choice, Up/Down + Enter. `resumed` / `quit_requested` are emitted at once (the window then fades out);
## Key Config and Options emit `window_requested(id)` (a WindowStack id) and the menu stays open under that window.

## Emitted when the player resumes the run.
signal resumed()
## Emitted when the player quits to the stage select.
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
const CHOICES := ["Resume", "Key Config", "Options", "Quit to stage select"]
## WindowStack ids of the choices that open an in-run window (index -> id).
const WINDOW_CHOICES := {1: "key_config", 2: "options"}

## Focused choice (CHOICES index).
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
	_options_y = TEXT_Y + MapleText.LINE + 7.0
	var content := _options_y + CHOICES.size() * OPTION_H + 2.0
	var n := TiledFrame.center_count(content - 8.0 + BOTTOM_H, TOP_H, MID_H, BOTTOM_H)
	panel_size = Vector2(BOX_W, TiledFrame.frame_height(n, TOP_H, MID_H, BOTTOM_H))


## Opens the menu with "Resume" focused.
func open() -> void:
	focus = 0
	_show_window()


## Takes choice `i` (CHOICES); `click` plays the UI click (the WzButtons play their own). False when closed or out
## of range.
func activate(i: int, click: bool = true) -> bool:
	if not _open or i < 0 or i >= CHOICES.size():
		return false
	if click:
		UiArt.play_sound(UiArt.SND_CLICK)
	if WINDOW_CHOICES.has(i):
		window_requested.emit(String(WINDOW_CHOICES[i]))
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


func handle_input(event: InputEvent) -> bool:
	if not _open:
		return false
	if MapleWindow.is_cancel(event):
		activate(0)
		return true
	var d := MapleWindow.digit_of(event)
	if d >= 1 and d <= CHOICES.size():
		activate(d - 1)
		return true
	var step := MapleWindow.vertical_step(event)
	if step != 0:
		_set_focus((focus + step + CHOICES.size()) % CHOICES.size())
		return true
	if MapleWindow.is_confirm(event):
		activate(focus)
		return true
	return event is InputEventKey and (event as InputEventKey).pressed


func _panel_gui_input(event: InputEvent, local: Vector2) -> void:
	var hit := -1
	for i in CHOICES.size():
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
	MapleText.draw(ci, Vector2(TEXT_X, TEXT_Y), "The game is paused.", MapleText.WHITE, MapleText.SIZE, true, 0,
		Color8(17, 85, 153), true)
	var dot0 := UiArt.frame("UI.wz/UIWindow.img/UtilDlgEx/dot0")
	var dot1 := UiArt.frame("UI.wz/UIWindow.img/UtilDlgEx/dot1")
	for i in CHOICES.size():
		var y := _options_y + i * OPTION_H
		var dot := dot1 if i == focus else dot0
		if dot != null:
			UiArt.blit(ci, dot, Vector2(TEXT_X + 2.0, y + 5.0))
		var col := MapleText.YELLOW if i == focus else MapleText.WHITE
		MapleText.draw(ci, Vector2(TEXT_X + 12.0, y), "%d. %s" % [i + 1, CHOICES[i]], col, MapleText.SIZE, i == focus,
			0, Color8(17, 85, 153), true)
