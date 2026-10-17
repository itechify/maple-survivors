class_name ShopNotice
extends UiWindow
## The v83 notice box (UI.wz/Basic.img/Notice `backgrnd` with BtOK) a shop opens over itself to say why a purchase or
## sale was refused (#111). Not draggable; Enter, OK or Esc (through the stack, as the front window) close it.
##
##   stack.open(ShopNotice.new("You do not have enough mesos."))

const ART := "UI.wz/Basic.img/Notice/backgrnd"
const BT_OK := "UI.wz/Basic.img/BtOK"
## v83 Notice backgrnd size.
const WINDOW_SIZE := Vector2(264, 132)
## tier C (ours, measured on the v83 art, same plate as the YesNo box): the text plate and the OK recess.
const TEXT_RECT := Rect2(22, 34, 220, 50)
const OK_POS := Vector2(99, 90)

## The message shown.
var message := ""

var _bt_ok: WzButton


func _init(p_message: String = "") -> void:
	super._init()
	name = "ShopNotice"
	window_id = "shop_notice"
	draggable = false
	size = WINDOW_SIZE
	message = p_message
	_bt_ok = WzButton.new(BT_OK)
	_bt_ok.name = "Ok"
	_bt_ok.fallback_size = Vector2(65, 24)
	_bt_ok.label = "" if _bt_ok.has_art() else "OK"
	_bt_ok.position = OK_POS
	_bt_ok.pressed.connect(request_close)
	add_child(_bt_ok)


## Enter closes the box while it is in front.
func handle_key(event: InputEvent) -> bool:
	if MapleWindow.is_confirm(event):
		request_close()
		return true
	return false


func _draw() -> void:
	var bg := UiArt.frame(ART)
	if bg != null:
		UiArt.blit(self, bg, Vector2.ZERO)
	else:
		draw_rect(Rect2(Vector2.ZERO, size), Color8(214, 214, 214))
		draw_rect(Rect2(Vector2.ZERO, size), Color8(99, 147, 183), false)
	var lines := MapleText.wrap(message, TEXT_RECT.size.x, MapleText.SIZE)
	var y := TEXT_RECT.position.y + floorf((TEXT_RECT.size.y - lines.size() * MapleText.LINE) * 0.5)
	for line in lines:
		MapleText.draw_centered(self, TEXT_RECT.position.x, y, TEXT_RECT.size.x, line, MapleText.BLACK, MapleText.SIZE)
		y += MapleText.LINE
