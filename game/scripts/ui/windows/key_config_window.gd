class_name KeyConfigWindow
extends UiWindow
## The v83 keyboard window (Menu -> Key Config, or the pause menu): UI.wz/UIWindow.img/KeyConfig `backgrnd` (the
## keyboard above, a tray of 3 x 18 icon slots below) with the bindable actions' icons on their keys and in the tray.
##
##   KeyConfigWindow.new(Settings)   # edits a KeyBindings draft of the settings' bindings; OK saves it into them
##
## Mouse: drag an icon from the tray (a source: it stays there) or from a key onto another key to bind it there (from
## a key it moves); the key's previous action loses it (a key holds one action; an action may sit on several keys).
## A drop on a fixed key (movement per the movement setting, Esc, the card keys 1-3; tinted and captioned) does
## nothing. Dragging an icon off the keyboard (onto the tray or out of the window) unbinds it; a click outlines a key.
## BtDelete (its v83 art reads CLEAR ALL) unbinds every bindable action in the draft. BtDefault puts the project defaults into the draft (KeyBindings.reset_defaults),
## BtOK saves and applies the draft (KeyBindings.apply_to -> Settings.set_bindings) and closes, BtCancel / BtClose / Esc
## close without saving. Tab, Scroll Lock and the Windows / menu keys are no drop targets (v83 bakes its own functions
## on Tab and Scroll Lock into the art). Hovering an icon names its action.
##
## Icons: tier A v83 KeyConfig icons for jump (53 JUMP), Equip (0 EQUIPMENT), Item (1 ITEMS), Stat (2 ABILITY, the
## v83 Stat window key) and Skill (3 SKILL); the potions show Red / Blue Potion (Item.wz 2000000 / 2000003) and
## Teleport the F/P Teleport skill icon (tier C). Without the cache the window keeps its layout and draws plain keys
## and lettered boxes.

## Emitted after OK saved the draft.
signal saved()

const ART := "UI.wz/UIWindow.img/KeyConfig/"
const ART_SIZE := Vector2(629, 373)
## Action -> icon path (see the class doc) and tooltip name.
const ICONS := {"jump": ART + "icon/53", "drink_hp": "Item.wz/Consume/0200.img/02000000/info/icon",
	"drink_mp": "Item.wz/Consume/0200.img/02000003/info/icon", "teleport": "Skill.wz/210.img/skill/2101002/icon",
	"equip_window": ART + "icon/0", "item_window": ART + "icon/1", "stat_window": ART + "icon/2",
	"skill_window": ART + "icon/3"}
const NAMES := {"jump": "Jump", "drink_hp": "HP Potion", "drink_mp": "MP Potion", "teleport": "Teleport",
	"equip_window": "Equip", "item_window": "Item", "stat_window": "Stat", "skill_window": "Skill"}
## tier C (ours, measured on the v83 backgrnd): key rows as [top, bottom, codes, x edges]; key i spans
## [edges[i], edges[i + 1]); code 0 = a key that is no drop target. Left / right Alt, Ctrl and Shift share one physical
## keycode (Godot tells them apart by location only), so both keys of a pair show the same icon.
const ROWS := [
	[27, 58, [KEY_ESCAPE], [13, 44]],
	[27, 58, [KEY_F1, KEY_F2, KEY_F3, KEY_F4], [80, 113, 147, 181, 215]],
	[27, 58, [KEY_F5, KEY_F6, KEY_F7, KEY_F8], [224, 257, 291, 325, 359]],
	[27, 58, [KEY_F9, KEY_F10, KEY_F11, KEY_F12], [368, 401, 435, 469, 503]],
	[27, 58, [KEY_PRINT, 0, KEY_PAUSE], [512, 545, 579, 613]],
	[66, 97, [KEY_QUOTELEFT, KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9, KEY_0, KEY_MINUS,
		KEY_EQUAL, KEY_BACKSPACE], [12, 45, 79, 113, 147, 181, 215, 249, 283, 317, 351, 385, 419, 453, 503]],
	[66, 97, [KEY_INSERT, KEY_HOME, KEY_PAGEUP], [512, 545, 579, 613]],
	[98, 130, [0, KEY_Q, KEY_W, KEY_E, KEY_R, KEY_T, KEY_Y, KEY_U, KEY_I, KEY_O, KEY_P, KEY_BRACKETLEFT,
		KEY_BRACKETRIGHT, KEY_BACKSLASH], [12, 61, 95, 129, 163, 197, 231, 265, 299, 333, 367, 401, 435, 469, 503]],
	[98, 130, [KEY_DELETE, KEY_END, KEY_PAGEDOWN], [512, 545, 579, 613]],
	[130, 163, [KEY_CAPSLOCK, KEY_A, KEY_S, KEY_D, KEY_F, KEY_G, KEY_H, KEY_J, KEY_K, KEY_L, KEY_SEMICOLON,
		KEY_APOSTROPHE, KEY_ENTER], [12, 78, 112, 146, 180, 214, 248, 282, 316, 350, 384, 418, 452, 503]],
	[163, 196, [KEY_SHIFT, KEY_Z, KEY_X, KEY_C, KEY_V, KEY_B, KEY_N, KEY_M, KEY_COMMA, KEY_PERIOD, KEY_SLASH,
		KEY_SHIFT], [12, 95, 129, 163, 197, 231, 265, 299, 333, 367, 401, 435, 503]],
	[163, 196, [KEY_UP], [546, 579]],
	[196, 229, [KEY_CTRL, 0, KEY_ALT, KEY_SPACE, KEY_ALT, 0, KEY_CTRL], [12, 60, 110, 163, 333, 389, 445, 503]],
	[196, 229, [KEY_LEFT, KEY_DOWN, KEY_RIGHT], [512, 545, 579, 613]],
]
## tier C (measured): the tray's first slot, slot pitch and the icon slot size.
const TRAY_POS := Vector2(8, 267)
const TRAY_PITCH := 34.0
const SLOT := Vector2(32, 32)
## tier C (ours): buttons in the grey strip between the keyboard and the tray (y 233-258), Close on the title bar.
const BUTTON_Y := 237.0
const DEFAULT_POS := Vector2(10, BUTTON_Y)
const DELETE_POS := Vector2(74, BUTTON_Y)
const OK_POS := Vector2(521, BUTTON_Y)
const CANCEL_POS := Vector2(572, BUTTON_Y)
const CLOSE_POS := Vector2(611, 6)
## Fixed keys' tint (the art's own pink for v83's fixed keys) and the selected key's outline.
const FIXED_TINT := Color8(187, 136, 170, 190)
const SELECT_COLOR := Color8(255, 170, 0)

## The settings OK saves into.
var settings: GameSettings
## The bindings being edited.
var draft: KeyBindings
## The outlined key (the last one clicked or dropped on), -1 = none.
var selected_key := -1

var _key_rects: Dictionary = {}
var _drag_action := ""
var _drag_from := -1
var _mouse := Vector2(-1, -1)
var _bt_ok: WzButton
var _bt_cancel: WzButton
var _bt_default: WzButton
var _bt_delete: WzButton
var _bt_close: WzButton


func _init(p_settings: GameSettings = null) -> void:
	super._init()
	name = "KeyConfigWindow"
	window_id = "key_config"
	size = ART_SIZE
	settings = p_settings
	draft = KeyBindings.from_settings(settings) if settings != null else KeyBindings.new()
	if settings != null:
		settings.changed.connect(_on_settings_changed)
	for row: Array in ROWS:
		var codes: Array = row[2]
		var edges: Array = row[3]
		for i in codes.size():
			var code := int(codes[i])
			if code == 0:
				continue
			var r := Rect2(float(edges[i]), float(row[0]), float(edges[i + 1]) - float(edges[i]),
				float(row[1]) - float(row[0]))
			if not _key_rects.has(code):
				_key_rects[code] = []
			(_key_rects[code] as Array).append(r)
	_bt_default = _button("BtDefault", "Default", Vector2(60, 18), DEFAULT_POS, restore_defaults)
	_bt_delete = _button("BtDelete", "Clear All", Vector2(77, 18), DELETE_POS, clear_all)
	_bt_ok = _button("BtOK", "OK", Vector2(47, 18), OK_POS, ok)
	_bt_cancel = _button("BtCancel", "Cancel", Vector2(47, 18), CANCEL_POS, cancel)
	_bt_close = _button("BtClose", "x", Vector2(12, 12), CLOSE_POS, cancel)


## The first local rect of key `code` (Rect2() when the keyboard has no such drop target).
func key_rect(code: int) -> Rect2:
	var rects: Array = _key_rects.get(code, [])
	return rects[0] if not rects.is_empty() else Rect2()


## The key under local point `p`, or -1.
func key_at(p: Vector2) -> int:
	for code: int in _key_rects:
		for r: Rect2 in _key_rects[code]:
			if r.has_point(p):
				return code
	return -1


## The local rect of `action`'s tray slot (Rect2() for an action that is not bindable).
func tray_rect(action: String) -> Rect2:
	var i := KeyBindings.BINDABLE.find(action)
	if i < 0:
		return Rect2()
	return Rect2(TRAY_POS + Vector2(i * TRAY_PITCH, 0), SLOT)


## True when `code` is fixed under the draft's movement set.
func is_fixed_key(code: int) -> bool:
	return draft.is_fixed(code)


## BtOK: saves and applies the draft, then closes.
func ok() -> void:
	if settings != null:
		draft.apply_to(settings)
	saved.emit()
	request_close()


## BtCancel / BtClose: closes without saving.
func cancel() -> void:
	request_close()


## BtDefault: the project defaults into the draft (saved only by OK).
func restore_defaults() -> void:
	draft.reset_defaults()
	selected_key = -1
	queue_redraw()


## BtDelete (CLEAR ALL): every bindable action off the keyboard (saved only by OK).
func clear_all() -> void:
	for a: String in KeyBindings.BINDABLE:
		draft.keys[a] = PackedInt32Array()
	selected_key = -1
	queue_redraw()


func _button(art: String, label: String, fallback: Vector2, at: Vector2, on_press: Callable) -> WzButton:
	var b := WzButton.new(ART + art)
	b.name = label
	b.fallback_size = fallback
	if not b.has_art():
		b.label = label
	b.position = at
	b.pressed.connect(on_press)
	add_child(b)
	return b


func _on_settings_changed() -> void:
	if settings.movement_keys != draft.movement:
		draft.set_movement(settings.movement_keys)
		queue_redraw()


func _tray_action_at(p: Vector2) -> String:
	for a: String in KeyBindings.BINDABLE:
		if tray_rect(a).has_point(p):
			return a
	return ""


func _window_gui_input(event: InputEvent, local: Vector2) -> void:
	if event is InputEventMouseMotion:
		_mouse = local
		queue_redraw()
		return
	var mb := event as InputEventMouseButton
	if mb == null or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if mb.pressed:
		_press(local)
	elif _drag_action != "":
		_drop(local)


func _press(local: Vector2) -> void:
	_drag_action = ""
	_drag_from = -1
	var code := key_at(local)
	if code >= 0:
		var a := draft.action_on(code)
		selected_key = code if a != "" else -1
		if a != "":
			_drag_action = a
			_drag_from = code
	else:
		_drag_action = _tray_action_at(local)
	queue_redraw()


func _drop(local: Vector2) -> void:
	var action := _drag_action
	var from := _drag_from
	_drag_action = ""
	_drag_from = -1
	var to := key_at(local)
	if to >= 0:
		if to != from and draft.bind(action, to):
			if from >= 0:
				draft.unbind(from)
			selected_key = to
			UiArt.play_sound(UiArt.SND_CLICK)
	elif from >= 0:
		draft.unbind(from)
		selected_key = -1
	queue_redraw()


func _draw() -> void:
	var bg := UiArt.frame(ART + "backgrnd")
	if bg != null:
		UiArt.blit(self, bg, Vector2.ZERO)
	else:
		_draw_plain()
	var fixed := draft.fixed_keys()
	for code: int in fixed:
		if code == KEY_ESCAPE and bg != null:
			continue # the art already shows Esc as the (pink) menu key
		for r: Rect2 in _key_rects.get(code, []):
			draw_rect(r.grow(-2.0), FIXED_TINT)
			MapleText.draw_centered(self, r.position.x, r.end.y - 14.0, r.size.x, String(fixed[code]), MapleText.WHITE,
				9, true)
	for code: int in _key_rects:
		var a := draft.action_on(code)
		if a == "" or (code == _drag_from and _drag_action != ""):
			continue
		for r: Rect2 in _key_rects[code]:
			_draw_icon(a, r)
	if selected_key >= 0:
		for r: Rect2 in _key_rects.get(selected_key, []):
			draw_rect(r.grow(-1.0), SELECT_COLOR, false, 2.0)
	for a: String in KeyBindings.BINDABLE:
		_draw_icon(a, tray_rect(a))
	if _drag_action != "":
		_draw_icon(_drag_action, Rect2(_mouse - SLOT * 0.5, SLOT), Color(1, 1, 1, 0.8))
	else:
		_draw_tooltip()


func _draw_icon(action: String, r: Rect2, col: Color = Color.WHITE) -> void:
	var f := UiArt.frame(String(ICONS[action]))
	if f != null:
		UiArt.blit_icon(self, f, r.position, r.size, col)
		return
	var box := Rect2(r.position + ((r.size - SLOT) * 0.5).floor(), SLOT).grow(-2.0)
	draw_rect(box, Color8(204, 85, 136, int(col.a * 255.0)))
	MapleText.draw_centered(self, box.position.x, box.position.y + 8.0, box.size.x, String(NAMES[action]).left(4),
		MapleText.WHITE, 9, true)


func _draw_tooltip() -> void:
	var code := key_at(_mouse)
	var a := draft.action_on(code) if code >= 0 else _tray_action_at(_mouse)
	if a == "":
		return
	var text := String(NAMES[a])
	var w := MapleText.width(text, MapleText.SMALL) + 8.0
	var at := (_mouse + Vector2(12, 14)).min(size - Vector2(w, 16))
	draw_rect(Rect2(at, Vector2(w, 16)), Color8(17, 34, 51, 230))
	MapleText.draw(self, at + Vector2(4, 1), text, MapleText.WHITE, MapleText.SMALL)


## Without the cache: a plain panel with lettered keys and empty tray slots.
func _draw_plain() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color8(220, 228, 240))
	draw_rect(Rect2(Vector2.ZERO, size), Color8(99, 147, 183), false)
	MapleText.draw(self, Vector2(8, 4), "KEYBOARD SETTING", MapleText.BLACK, MapleText.SMALL, true)
	for code: int in _key_rects:
		for r: Rect2 in _key_rects[code]:
			draw_rect(r.grow(-1.0), Color.WHITE)
			draw_rect(r.grow(-1.0), Color8(90, 90, 90), false)
			MapleText.draw(self, r.position + Vector2(3, 1), KeyBindings.key_name(code).left(5), MapleText.GREY, 9)
	for i in 18 * 3:
		@warning_ignore("integer_division")
		var p := TRAY_POS + Vector2((i % 18) * TRAY_PITCH, (i / 18) * TRAY_PITCH)
		draw_rect(Rect2(p, SLOT), Color8(200, 200, 200))
