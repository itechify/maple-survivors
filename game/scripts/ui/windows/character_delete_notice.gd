extends MapleWindow
## Character deletion confirmation using the same v83 YesNo3 notice and buttons as PauseMenu.

signal confirmed()

## tier A: YesNo3 canvas sizes and grey-strip button placement, shared with PauseMenu.
const BOX := "UI.wz/Basic.img/YesNo3/"
const WIDTH := 266.0
const TEXT_AT := Vector2(20, 17)
var text := ""
var _ok: WzButton
var _cancel: WzButton


func _init() -> void:
	super._init()
	name = "DeleteNotice"
	_ok = WzButton.new("UI.wz/Basic.img/BtOK2")
	_ok.name = "ConfirmDelete"
	_ok.pressed.connect(func() -> void: accept())
	panel.add_child(_ok)
	_cancel = WzButton.new("UI.wz/Basic.img/BtCancel2")
	_cancel.name = "CancelDelete"
	_cancel.pressed.connect(cancel)
	panel.add_child(_cancel)


## Shows the exact character name and explains that deleting ends its run.
func open(character_name: String) -> void:
	text = "Delete %s? This ends the run and adds it to run history." % character_name # tier C: survivor deletion wording.
	var lines := MapleText.wrap(text, WIDTH - 2 * TEXT_AT.x, MapleText.SIZE, true)
	panel_size = Vector2(WIDTH, TiledFrame.frame_height(TiledFrame.center_count(
		TEXT_AT.y + lines.size() * MapleText.LINE + 55, 21, 20, 55), 21, 20, 55))
	_show_window()


## Closes without modifying the save.
func cancel() -> void:
	_hide_window()


## Confirms once, after the notice closes.
func accept() -> void:
	if is_open():
		_hide_window(func() -> void: confirmed.emit())


func handle_input(event: InputEvent) -> bool:
	if not is_open():
		return false
	if is_cancel(event):
		cancel()
	elif is_confirm(event):
		accept()
	return event is InputEventKey


func _layout_children() -> void:
	if _cancel == null:
		return
	_cancel.position = Vector2(WIDTH - 14 - _cancel.size.x, panel_size.y - 31)
	_ok.position = _cancel.position - Vector2(_ok.size.x + 4, 0)


func _draw_panel(ci: Control) -> void:
	TiledFrame.draw_v(ci, Vector2.ZERO, UiArt.frame(BOX + "t"), UiArt.frame(BOX + "c"), UiArt.frame(BOX + "s"), panel_size.y)
	var lines := MapleText.wrap(text, WIDTH - 2 * TEXT_AT.x, MapleText.SIZE, true)
	for i in lines.size():
		MapleText.draw(ci, TEXT_AT + Vector2(0, i * MapleText.LINE), lines[i], MapleText.WHITE, MapleText.SIZE, true)
