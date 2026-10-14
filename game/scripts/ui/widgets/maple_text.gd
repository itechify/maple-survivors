class_name MapleText
extends Label
## MapleStory-style text: the system font (Arial, then Tahoma, then Dotum) without antialiasing at v83 sizes (11-12 px),
## and the v83 UI colours. No fonts are shipped (GAME_DESIGN section 10).
##
## Two ways to use it:
##   - as a node: `MapleText.new("Hello", MapleText.SIZE, MapleText.NPC_TEXT)` (a Label with the font applied);
##   - from a `_draw()`: `MapleText.draw(self, pos, "Hello", MapleText.WHITE)` (pos = top-left of the line box) and
##     `MapleText.wrap(text, width)` for word-wrapped lines.
##
## Colours (tier C, picked to match v83 screenshots): NPC dialog body black, NPC option blue (#b), unavailable grey,
## system yellow (#FFFF00, the "+N EXP" colour), notice white.

const SIZE := 12
const SMALL := 11
## Line height for SIZE / SMALL text.
const LINE := 15
const LINE_SMALL := 13

const WHITE := Color(1, 1, 1)
const BLACK := Color(0, 0, 0)
## NPC dialog body text.
const NPC_TEXT := Color(0, 0, 0)
## NPC dialog option text (#b).
const NPC_BLUE := Color8(0, 0, 255)
## NPC dialog purple (#d), used for names.
const NPC_PURPLE := Color8(128, 0, 128)
## NPC dialog red (#r).
const NPC_RED := Color8(255, 0, 0)
## Unavailable / disabled text.
const GREY := Color8(136, 136, 136)
## System messages and highlights.
const YELLOW := Color8(255, 255, 0)
## Orange used for "NEW" and rank-up text in the skill window.
const ORANGE := Color8(255, 153, 0)
## Dark blue shadow behind white text on the light-blue SkillUp panel.
const PANEL_SHADOW := Color8(34, 85, 136)

static var _fonts: Dictionary = {}


## A Label preset with the Maple font, size and colour (bold = weight 700).
func _init(p_text: String = "", p_size: int = SIZE, p_color: Color = BLACK, bold: bool = false) -> void:
	text = p_text
	add_theme_font_override("font", font(bold))
	add_theme_font_size_override("font_size", p_size)
	add_theme_color_override("font_color", p_color)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## The system font (cached per weight): Arial, Tahoma, Dotum; no antialiasing, no subpixel positioning.
static func font(bold: bool = false) -> SystemFont:
	var key := 700 if bold else 400
	if _fonts.has(key):
		return _fonts[key]
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Arial", "Tahoma", "Dotum"])
	f.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	f.hinting = TextServer.HINTING_NORMAL
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	f.font_weight = key
	_fonts[key] = f
	return f


## Width in px of one line of text.
static func width(s: String, size: int = SIZE, bold: bool = false) -> float:
	if s == "":
		return 0.0
	return font(bold).get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


## Baseline offset from the top of a line box of `size` px text.
static func ascent(size: int = SIZE, bold: bool = false) -> float:
	return font(bold).get_ascent(size)


## Draws one line with its line box top-left at `p` (whole pixels). `outline` > 0 draws an outline in `outline_color`
## first (the HUD style for text over the map); `shadow` draws a 1 px drop shadow instead.
static func draw(ci: CanvasItem, p: Vector2, s: String, color: Color = BLACK, size: int = SIZE, bold: bool = false,
		outline: int = 0, outline_color: Color = Color(0, 0, 0, 0.9), shadow: bool = false) -> void:
	if s == "":
		return
	var f := font(bold)
	var base := Vector2(floorf(p.x), floorf(p.y) + roundf(f.get_ascent(size)))
	if outline > 0:
		ci.draw_string_outline(f, base, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline, outline_color)
	elif shadow:
		ci.draw_string(f, base + Vector2(1, 1), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline_color)
	ci.draw_string(f, base, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


## Draws a line centred horizontally in [x, x + w] with its line box top at y.
static func draw_centered(ci: CanvasItem, x: float, y: float, w: float, s: String, color: Color = BLACK,
		size: int = SIZE, bold: bool = false, outline: int = 0, outline_color: Color = Color(0, 0, 0, 0.9),
		shadow: bool = false) -> void:
	draw(ci, Vector2(x + floorf((w - width(s, size, bold)) * 0.5), y), s, color, size, bold, outline, outline_color,
		shadow)


## Word-wraps `s` to lines no wider than `max_w` px (explicit "\n" breaks are kept; a single word wider than the
## line is put on its own line).
static func wrap(s: String, max_w: float, size: int = SIZE, bold: bool = false) -> PackedStringArray:
	var out: PackedStringArray = []
	for para in s.split("\n"):
		var line := ""
		for word in para.split(" ", false):
			var cand := word if line == "" else line + " " + word
			if line != "" and width(cand, size, bold) > max_w:
				out.append(line)
				line = word
			else:
				line = cand
		out.append(line)
	return out


## `s` shortened with "..." so that it fits in `max_w` px.
static func ellipsize(s: String, max_w: float, size: int = SIZE, bold: bool = false) -> String:
	if width(s, size, bold) <= max_w:
		return s
	var t := s
	while t.length() > 1 and width(t + "...", size, bold) > max_w:
		t = t.substr(0, t.length() - 1)
	return t.strip_edges() + "..."
