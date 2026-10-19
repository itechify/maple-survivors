class_name DropConfirm
extends UiWindow
## The v83 YesNo box (UI.wz/Basic.img/YesNo `backgrnd` with BtYes / BtNo) the Item window opens before an item is
## discarded (#108). It sits on top of the window stack like any in-run window (the run stays held; Esc closes it as
## the front window, which is No), is not draggable and reports Yes through `confirmed`.
##
##   var c := DropConfirm.new(DropConfirm.DROP_QUESTION)
##   c.confirmed.connect(...)
##   stack.open(c)

## Emitted once when Yes is taken (before the box closes).
signal confirmed()

const ART := "UI.wz/Basic.img/YesNo/backgrnd"
const BT_YES := "UI.wz/Basic.img/BtYes"
const BT_NO := "UI.wz/Basic.img/BtNo"
## v83 YesNo backgrnd size.
const WINDOW_SIZE := Vector2(264, 132)
## tier C (ours; the v83 client's exact wording is unverified): the question before an item is destroyed.
const DROP_QUESTION := "Are you sure you want to drop this item?"
## tier C (ours, measured on the v83 art): the text plate and the two button recesses.
const TEXT_RECT := Rect2(22, 34, 220, 50)
const YES_POS := Vector2(58, 90)
const NO_POS := Vector2(136, 90)

## The question shown.
var message := ""

var _bt_yes: WzButton
var _bt_no: WzButton


func _init(p_message: String = DROP_QUESTION) -> void:
	super._init()
	name = "DropConfirm"
	window_id = "drop_confirm"
	draggable = false
	size = WINDOW_SIZE
	message = p_message
	_bt_yes = WzButton.new(BT_YES)
	_bt_yes.name = "Yes"
	_bt_yes.fallback_size = Vector2(65, 24)
	_bt_yes.label = "" if _bt_yes.has_art() else "YES"
	_bt_yes.position = YES_POS
	_bt_yes.pressed.connect(accept)
	add_child(_bt_yes)
	_bt_no = WzButton.new(BT_NO)
	_bt_no.name = "No"
	_bt_no.fallback_size = Vector2(65, 24)
	_bt_no.label = "" if _bt_no.has_art() else "NO"
	_bt_no.position = NO_POS
	_bt_no.pressed.connect(cancel)
	add_child(_bt_no)


## Yes: tells the opener, then closes.
func accept() -> void:
	confirmed.emit()
	request_close()


## No (also Esc through the stack): closes without telling anyone.
func cancel() -> void:
	request_close()


## Enter is Yes while the box is in front.
func handle_key(event: InputEvent) -> bool:
	if MapleWindow.is_confirm(event):
		accept()
		return true
	return false


func _draw() -> void:
	var bg := UiArt.frame(ART)
	if bg != null:
		UiArt.blit(self, bg, Vector2.ZERO)
	else:
		draw_rect(Rect2(Vector2.ZERO, size), Color8(214, 214, 214))
		PixelDraw.outline(self, Rect2(Vector2.ZERO, size), Color8(99, 147, 183))
	var lines := MapleText.wrap(message, TEXT_RECT.size.x, MapleText.SIZE)
	var y := TEXT_RECT.position.y + floorf((TEXT_RECT.size.y - lines.size() * MapleText.LINE) * 0.5)
	for line in lines:
		MapleText.draw_centered(self, TEXT_RECT.position.x, y, TEXT_RECT.size.x, line, MapleText.BLACK, MapleText.SIZE)
		y += MapleText.LINE
