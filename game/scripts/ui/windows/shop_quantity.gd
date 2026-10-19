class_name ShopQuantity
extends UiWindow
## The v83 "How many are you willing to buy / sell?" box (#111): the YesNo background (UI.wz/Basic.img/YesNo) with a
## number field under the question and Yes / No (BtYes / BtNo). Type digits (the first digit replaces the shown 1),
## Backspace, Up / Down or the wheel change the number, Enter or Yes confirms with `confirmed(count)`, Esc (through the
## stack, as the front window) or No closes without telling anyone. The count stays within 1 .. `max_count`.
##
##   var q := ShopQuantity.new("How many are you willing to buy?", 99)
##   q.confirmed.connect(func(count: int) -> void: ...)
##   stack.open(q)

## Emitted once with the chosen count when Yes or Enter is taken (before the box closes).
signal confirmed(count: int)

const ART := "UI.wz/Basic.img/YesNo/backgrnd"
const BT_YES := "UI.wz/Basic.img/BtYes"
const BT_NO := "UI.wz/Basic.img/BtNo"
## v83 YesNo backgrnd size.
const WINDOW_SIZE := Vector2(264, 132)
## tier C (ours, measured on the v83 art): the question line, the number field and the two button recesses.
const TEXT_RECT := Rect2(22, 30, 220, 30)
const FIELD := Rect2(92, 60, 80, 17)
const YES_POS := Vector2(58, 90)
const NO_POS := Vector2(136, 90)
## tier C (ours): most digits typed into the field.
const MAX_DIGITS := 3

## The question shown.
var message := ""
## The largest count the field takes.
var max_count := 1
## The number in the field.
var count := 1

var _fresh := true
var _bt_yes: WzButton
var _bt_no: WzButton


func _init(p_message: String = "", p_max: int = 1, p_count: int = 1) -> void:
	super._init()
	name = "ShopQuantity"
	window_id = "shop_quantity"
	draggable = false
	size = WINDOW_SIZE
	message = p_message
	max_count = maxi(1, p_max)
	count = clampi(p_count, 1, max_count)
	_bt_yes = _button("Yes", BT_YES, "YES", YES_POS, accept)
	_bt_no = _button("No", BT_NO, "NO", NO_POS, cancel)


func _button(p_name: String, art: String, fallback: String, at: Vector2, action: Callable) -> WzButton:
	var b := WzButton.new(art)
	b.name = p_name
	b.fallback_size = Vector2(65, 24)
	b.label = "" if b.has_art() else fallback
	b.position = at
	b.pressed.connect(action)
	add_child(b)
	return b


## Changes the count by `delta` within 1 .. max_count.
func step(delta: int) -> void:
	set_count(count + delta)


## Sets the count (clamped).
func set_count(value: int) -> void:
	count = clampi(value, 1, max_count)
	_fresh = false
	queue_redraw()


## Yes: tells the opener the count, then closes.
func accept() -> void:
	confirmed.emit(count)
	request_close()


## No: closes without telling anyone.
func cancel() -> void:
	request_close()


## Types a digit: the first one replaces the shown number, then it appends (up to MAX_DIGITS, never above max_count).
func type_digit(d: int) -> void:
	var text := str(d) if _fresh else str(count) + str(d)
	if text.length() > MAX_DIGITS:
		return
	_fresh = false
	count = clampi(int(text), 1, max_count) if int(text) > 0 else 1
	queue_redraw()


## Backspace: drops the last digit (the field shows 1 at the least).
func backspace() -> void:
	var text := str(count)
	count = maxi(1, int(text.substr(0, text.length() - 1))) if text.length() > 1 else 1
	_fresh = false
	queue_redraw()


func handle_key(event: InputEvent) -> bool:
	if MapleWindow.is_confirm(event):
		accept()
		return true
	var k := event as InputEventKey
	if k == null or not k.pressed:
		return false
	var code := k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
	if code >= KEY_0 and code <= KEY_9:
		type_digit(code - KEY_0)
		return true
	if code >= KEY_KP_0 and code <= KEY_KP_9:
		type_digit(code - KEY_KP_0)
		return true
	if code == KEY_BACKSPACE:
		backspace()
		return true
	if code == KEY_UP:
		step(1)
		return true
	if code == KEY_DOWN:
		step(-1)
		return true
	return false


func _window_gui_input(event: InputEvent, _local: Vector2) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed:
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			step(1)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			step(-1)


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
	draw_rect(FIELD, Color.WHITE)
	PixelDraw.outline(self, FIELD, Color8(119, 136, 153))
	var shown := str(count)
	MapleText.draw(self, Vector2(FIELD.end.x - 4.0 - MapleText.width(shown, MapleText.SMALL), FIELD.position.y + 2.0),
		shown, MapleText.BLACK, MapleText.SMALL)
