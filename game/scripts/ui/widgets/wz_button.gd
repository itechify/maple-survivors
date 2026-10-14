class_name WzButton
extends BaseButton
## A MapleStory button drawn from a WZ button node: `<base>/normal/0`, `mouseOver/<n>`, `pressed/0`, `disabled/0` and
## the optional `keyFocused/<n>` (drawn instead of normal while the button has the keyboard highlight). Every state may
## animate (several numbered canvases, WZ delays). Every state canvas is drawn with its origin where the normal
## canvas's origin is (normal top-left = the button's 0, 0), so keyFocused frames with origin (1, 1) grow one pixel
## around the normal art like the client, and centre-origin buttons (Login.img/BtOk) line up too.
##
##   var ok := WzButton.new("UI.wz/UIWindow.img/UtilDlgEx/BtYes")
##   ok.pressed.connect(_on_yes)
##
## Sounds (Sound.wz/UI.img): BtMouseOver when the mouse enters an enabled button, BtMouseClick when it is pressed.
## Clicks fire on release (BaseButton default). Keyboard focus is off by default (windows drive their keys
## themselves; `ui_accept` would also fire on Space, the jump key); `key_focused` shows the keyFocused art.
## `label` draws text centred over the art (for art without baked text). Plate mode (set_plate): the art is widened to
## a given width from its text-free left columns (columns [0, plate_left) as they are, column plate_left repeated, the
## last column as the right edge), so a small wooden button of the client can carry our own `label` instead of its
## baked words. Without the cache the button keeps its size (`fallback_size`) and draws a plain box with the label,
## so layouts and tests still work.

const STATES := ["normal", "mouseOver", "pressed", "disabled", "keyFocused"]

## WZ path of the button node.
@export var base_path := "":
	set(v):
		base_path = v
		_reload()
## Optional text drawn centred on the button.
@export var label := "":
	set(v):
		label = v
		queue_redraw()
## Label colour (disabled buttons draw it grey).
@export var label_color := MapleText.BLACK
## Size used when the art is missing.
@export var fallback_size := Vector2(46, 18)
## Play the UI sounds.
@export var sounds := true
## Label outline width and colour (0 = none).
var label_outline := 0
var label_outline_color := Color(0, 0, 0, 0.9)
## Plate mode width (0 = off) and the first column repeated to widen the art (see the class doc).
var plate_width := 0.0
var plate_left := 0.0
## Show the keyFocused art (keyboard highlight driven by the owning window).
var key_focused := false:
	set(v):
		key_focused = v
		queue_redraw()

var _anims: Dictionary = {}
var _origin := Vector2.ZERO
var _t := 0.0
var _last_state := ""


func _init(p_base: String = "", p_label: String = "") -> void:
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_ARROW
	label = p_label
	base_path = p_base
	mouse_entered.connect(_on_mouse_entered)
	pressed.connect(_on_pressed)
	mouse_exited.connect(queue_redraw)
	button_down.connect(queue_redraw)
	button_up.connect(queue_redraw)


## Plate mode: draws the art `width` px wide from its columns [0, left) and column `left` repeated (its baked words
## are left out) and resizes the button to it.
func set_plate(width: float, left: float) -> void:
	plate_width = width
	plate_left = left
	_reload()


## True when at least the normal state's art was found.
func has_art() -> bool:
	return _anims.has("normal")


## The state name drawn now: disabled, pressed, mouseOver, keyFocused or normal.
func state_name() -> String:
	if disabled:
		return "disabled"
	match get_draw_mode():
		DRAW_PRESSED, DRAW_HOVER_PRESSED:
			return "pressed"
		DRAW_HOVER:
			return "mouseOver"
	if key_focused and _anims.has("keyFocused"):
		return "keyFocused"
	return "normal"


func _process(delta: float) -> void:
	var s := state_name()
	if s != _last_state:
		_last_state = s
		_t = 0.0
		queue_redraw()
		return
	var a: SpriteAnim = _anims.get(s)
	if a != null and a.frame_count() > 1:
		var before := a.index_at(_t, true)
		_t += delta
		if a.index_at(_t, true) != before:
			queue_redraw()


func _draw() -> void:
	var s := state_name()
	var a: SpriteAnim = _anims.get(s, _anims.get("normal"))
	if a != null and plate_width > 0.0:
		TiledFrame.draw_h_slices(self, Vector2.ZERO, a.frame_at(_t, true), plate_left, plate_left, plate_width)
	elif a != null:
		UiArt.blit_origin(self, a.frame_at(_t, true), _origin)
	elif not has_art():
		draw_rect(Rect2(Vector2.ZERO, size), Color8(238, 136, 51) if s != "disabled" else Color8(170, 170, 170))
		draw_rect(Rect2(Vector2.ZERO, size), Color8(120, 60, 20), false)
	if label != "":
		var col := label_color if s != "disabled" else MapleText.GREY
		var dy := 1.0 if s == "pressed" else 0.0
		MapleText.draw_centered(self, 0, floorf((size.y - MapleText.LINE) * 0.5) + dy, size.x, label, col,
			MapleText.SMALL, true, label_outline, label_outline_color)


func _reload() -> void:
	_anims.clear()
	for s: String in STATES:
		var a := UiArt.anim(base_path + "/" + s) if base_path != "" else null
		if a != null and not a.is_empty():
			_anims[s] = a
	var n: SpriteAnim = _anims.get("normal")
	var sz := fallback_size
	_origin = Vector2.ZERO
	if n != null:
		sz = n.frames[0].region.size
		_origin = n.frames[0].origin
		if plate_width > 0.0:
			sz.x = plate_width
			_origin = Vector2.ZERO
	custom_minimum_size = sz
	size = sz
	queue_redraw()


func _on_mouse_entered() -> void:
	queue_redraw()
	if sounds and not disabled:
		UiArt.play_sound(UiArt.SND_OVER)


func _on_pressed() -> void:
	if sounds:
		UiArt.play_sound(UiArt.SND_CLICK)
