class_name HudWidget
extends Control
## The one base of every run HUD widget (status bar, counters, skills, messages, potion quickslot, buff row, boss bar):
## its own state snapshot, the HUD fonts and the shared WZ drawing helpers (_frame, _blit, _blit_rect, _text, _rank).
## Widgets never take mouse input.
const SB := "UI.wz/StatusBar.img/"
const BAR_W := 800
const BAR_H := 71
## Gauge art position inside the bar (gauge box x 209..562, y 36..69 of backgrnd2).
const GAUGE_POS := Vector2(216, 37)
## Fill spans inside gauge/bar (x from, width) and the fill rows.
const HP_FILL := Vector2(2, 105)
const MP_FILL := Vector2(110, 105)
const EXP_FILL := Vector2(223, 115)
const FILL_Y := 15.0
const FILL_H := 14.0
## Number text positions inside the gauge (right of the HP/MP/EXP labels, label row).
const HP_TEXT_X := 18.0
const MP_TEXT_X := 129.0
const EXP_TEXT_X := 246.0
const TEXT_Y := 3.0
## Level digits, job and name text inside the bar.
const LEVEL_POS := Vector2(36, 46)
const JOB_POS := Vector2(84, 50)
const NAME_POS := Vector2(84, 64)
const FONT_SIZE := 12
const SKILL_ICON := 32
const SKILL_GAP := 4
## tier C: system message colour (yellow), lifetime, fade, line count, line height and inset above the bar's left end.
const SYSTEM_YELLOW := Color(1.0, 1.0, 0.0)
const MSG_LIFE := 4.0
const MSG_FADE := 0.5
const MSG_MAX := 6
const MSG_LINE := 14.0
const MSG_INSET := Vector2(8, 6)

var library: AssetLibrary
var player_state: Dictionary = {}
var run_info: Dictionary = {}
var font: SystemFont
var bold_font: SystemFont
var _frames: Dictionary = {}


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	font = make_font()
	bold_font = make_font(700)
	get_viewport().size_changed.connect(queue_redraw)

## Receives only presentation state from RunScene and queues this widget's redraw.
func update(p_player_state: Dictionary, p_run_info: Dictionary) -> void:
	player_state = p_player_state
	run_info = p_run_info
	queue_redraw()

## Creates the pixel-aligned system font used by every HUD widget.
static func make_font(weight: int = 400) -> SystemFont:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Arial", "Tahoma"])
	f.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	f.hinting = TextServer.HINTING_NORMAL
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	f.font_weight = weight
	return f


## Top-left of the 800 px status bar in a view of `view` size.

static func bar_origin(view: Vector2) -> Vector2:
	return Vector2(floorf((view.x - BAR_W) * 0.5), view.y - BAR_H)


## Width in px of the filled part of a gauge (0 when max <= 0).

static func fill_width(cur: float, max_v: float, full: float) -> float:
	if max_v <= 0.0:
		return 0.0
	return floorf(full * clampf(cur / max_v, 0.0, 1.0))


## "MM:SS" for a number of seconds.
@warning_ignore("integer_division")

static func format_time(seconds: float) -> String:
	var s := maxi(0, int(seconds))
	return "%02d:%02d" % [s / 60, s % 60]

## Linear message fade over the last MSG_FADE seconds of its lifetime.
static func message_alpha(age: float) -> float:
	return clampf((MSG_LIFE - age) / MSG_FADE, 0.0, 1.0)


## Outlined HUD text (default `font`); the outline colour (default 90% black) fades with `alpha`.
func _text(p: Vector2, s: String, col: Color, size: int = FONT_SIZE, f: Font = null, alpha: float = 1.0,
		outline: Color = Color(0, 0, 0, 0.9), width: float = -1) -> void:
	if f == null:
		f = font
	if s == "" or f == null:
		return
	draw_string_outline(f, p, s, HORIZONTAL_ALIGNMENT_LEFT, width, size, 3 if size > FONT_SIZE else 2,
		Color(outline.r, outline.g, outline.b, outline.a * alpha))
	draw_string(f, p, s, HORIZONTAL_ALIGNMENT_LEFT, width, size, col)


## Draws a canvas with its top-left at `p` (UI canvases have origin 0,0 or none).

func _blit(f: SpriteFrame, p: Vector2) -> void:
	if f == null or f.page == null:
		return
	draw_texture_rect_region(f.page, Rect2(p.floor(), f.region.size), f.region)


## Draws a canvas stretched into `rect`.
func _blit_rect(f: SpriteFrame, rect: Rect2) -> void:
	if f == null or f.page == null:
		return
	draw_texture_rect_region(f.page, rect, f.region)


## A cached UI canvas; null when absent. Optional art is looked up quietly; `report_missing` records an absent
## canvas in the library's `missing` list (art that must exist: boss bars, potion and buff icons).
func _frame(path: String, report_missing: bool = false) -> SpriteFrame:
	if _frames.has(path):
		return _frames[path]
	var lib := _lib()
	var f: SpriteFrame = null
	if lib != null and path != "":
		if report_missing:
			f = lib.frame(path)
		elif WzImg.is_canvas(lib.find(path)):
			f = lib.frame(path)
	_frames[path] = f
	return f

func _lib() -> AssetLibrary:
	if library == null:
		library = AssetLibrary.get_default()
	return library

## Draws a rank/count in the original ItemNo font at an icon's bottom-right corner.
func _rank(br: Vector2, rank: int) -> void:
	if rank <= 0:
		return
	var s := str(rank)
	var frames: Array = []
	var w := 0.0
	for i in s.length():
		var f := _frame("UI.wz/Basic.img/ItemNo/" + s[i])
		if f != null:
			frames.append(f)
			w += f.region.size.x
	var x := br.x - w
	for f: SpriteFrame in frames:
		_blit(f, Vector2(x, br.y - f.region.size.y))
		x += f.region.size.x
