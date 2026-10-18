class_name TitleButton
extends BaseButton
## A title-screen button in the Maple Survivors key art's palette (game/assets/branding/title.png): a gold bevel
## frame with clipped pixel corners around a blood-red fill (PRIMARY, Start) or dark stone fill (SECONDARY, the rest),
## and a bold cream label with a dark outline. Drawn from code, so it needs no WZ art. Hover brightens it, pressed
## darkens it and drops the label 1 px; the v83 BtMouseOver / BtMouseClick sounds play like on a WzButton.
## Clicks fire on release. Keyboard focus is off (the title screen handles Enter and Esc itself).

enum Style { PRIMARY, SECONDARY }

## tier C: ours, picked from the key art (logo gold, moon red, castle stone).
const OUTLINE := Color8(28, 6, 6)
const GOLD_LIGHT := Color8(240, 200, 120)
const GOLD_DARK := Color8(138, 90, 36)
const GOLD_HOVER := Color8(255, 226, 150)
const INNER := Color8(52, 10, 10)
const TEXT := Color8(255, 241, 220)
const TEXT_OUTLINE := Color8(60, 6, 6)
const SHADOW := Color(0, 0, 0, 0.45)
## Fill gradients (top, bottom) per style and state.
const RED := [Color8(217, 58, 43), Color8(125, 16, 16)]
const RED_HOVER := [Color8(240, 82, 58), Color8(156, 26, 20)]
const RED_PRESSED := [Color8(150, 28, 22), Color8(96, 10, 10)]
const STONE := [Color8(58, 40, 44), Color8(26, 17, 19)]
const STONE_HOVER := [Color8(122, 30, 26), Color8(60, 12, 12)]
const STONE_PRESSED := [Color8(40, 26, 28), Color8(18, 11, 12)]
## Horizontal padding around the label and the button heights (tier C: ours).
const PAD := 14.0
const PRIMARY_HEIGHT := 34.0
const SECONDARY_HEIGHT := 24.0
const PRIMARY_TEXT := 17
const SECONDARY_TEXT := 13

var label := ""
var style := Style.SECONDARY
## Play the v83 hover / click sounds.
var sounds := true


func _init(p_label: String = "", p_style: Style = Style.SECONDARY, min_width: float = 0.0) -> void:
	label = p_label
	style = p_style
	focus_mode = Control.FOCUS_NONE
	var text_size := _text_size()
	var w := ceilf(MapleText.width(label, text_size, true) + 2.0 * PAD)
	size = Vector2(maxf(w, min_width), PRIMARY_HEIGHT if style == Style.PRIMARY else SECONDARY_HEIGHT)
	custom_minimum_size = size
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(queue_redraw)
	button_down.connect(queue_redraw)
	pressed.connect(_on_pressed)
	button_up.connect(queue_redraw)


## "pressed", "hover" or "normal".
func state_name() -> String:
	match get_draw_mode():
		DRAW_PRESSED, DRAW_HOVER_PRESSED:
			return "pressed"
		DRAW_HOVER:
			return "hover"
	return "normal"


func _draw() -> void:
	var s := state_name()
	var w := size.x
	var h := size.y
	# A soft drop shadow, the outline with clipped corners, then the bevel (light top/left, dark bottom/right), the
	# inner line and the fill.
	if s != "pressed":
		draw_rect(Rect2(2, h, w - 3, 2), SHADOW)
	draw_rect(Rect2(1, 0, w - 2, h), OUTLINE)
	draw_rect(Rect2(0, 1, w, h - 2), OUTLINE)
	var light := GOLD_HOVER if s == "hover" else GOLD_LIGHT
	draw_rect(Rect2(2, 1, w - 4, h - 2), GOLD_DARK)
	draw_rect(Rect2(1, 2, w - 2, h - 4), GOLD_DARK)
	draw_rect(Rect2(2, 1, w - 4, 1), light)
	draw_rect(Rect2(1, 2, 1, h - 4), light)
	draw_rect(Rect2(3, 3, w - 6, h - 6), INNER)
	var fill: Array = _fill(s)
	var inner := Rect2(4, 4, w - 8, h - 8)
	var rows := int(inner.size.y)
	for i in rows:
		var t := float(i) / maxf(1.0, rows - 1)
		draw_rect(Rect2(inner.position.x, inner.position.y + i, inner.size.x, 1), (fill[0] as Color).lerp(fill[1], t))
	if s != "pressed":
		draw_rect(Rect2(inner.position.x, inner.position.y, inner.size.x, 1), (fill[0] as Color).lightened(0.25))
	var ts := _text_size()
	var line := MapleText.font(true).get_height(ts)
	var dy := 1.0 if s == "pressed" else 0.0
	MapleText.draw_centered(self, 0, floorf((h - line) * 0.5) + dy, w, label, TEXT, ts, true, 3, TEXT_OUTLINE)


func _fill(s: String) -> Array:
	if style == Style.PRIMARY:
		return RED_PRESSED if s == "pressed" else (RED_HOVER if s == "hover" else RED)
	return STONE_PRESSED if s == "pressed" else (STONE_HOVER if s == "hover" else STONE)


func _text_size() -> int:
	return PRIMARY_TEXT if style == Style.PRIMARY else SECONDARY_TEXT


func _on_mouse_entered() -> void:
	queue_redraw()
	if sounds:
		UiArt.play_sound(UiArt.SND_OVER)


func _on_pressed() -> void:
	queue_redraw()
	if sounds:
		UiArt.play_sound(UiArt.SND_CLICK)
