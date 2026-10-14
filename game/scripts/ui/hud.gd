class_name Hud
extends CanvasLayer
## In-run HUD: the v83 status bar (UI.wz/StatusBar.img) at the bottom, survival timer at the top centre, kill count at
## the top right, owned skills with ranks at the top left.
##
## Status bar: `base/backgrnd` (800x71) centred at the bottom of the (possibly wider, aspect "expand") view, its
## horizontally uniform middle column stretched over the extra width; `base/backgrnd2` (the LV box, name box, chat
## strip and gauge box overlay) on top at the same left edge. Gauges: `gauge/bar` (HP red, MP blue, EXP yellow) with the
## empty part covered by `gauge/gray`, then `gauge/graduation`; numbers "[cur/max]" with `number/*` digits. Level with
## Basic.img/LevelNo digits; job and character name in the system font without antialiasing. Pixel positions inside the
## bar come from measuring the v83 art (gauge box, fills); button positions are not in the data (tier C layout).
##
## System messages (GAME_DESIGN section 5: "+N EXP" in MapleStory's yellow system-message style): push_message() /
## show_exp() add a line above the left end of the status bar, newest at the bottom; a line lives MSG_LIFE s and fades
## over its last MSG_FADE s, at most MSG_MAX lines (the oldest drops off). The magnet collects many drops per second, so
## callers should sum a tick's EXP (PickupSystem.step's return value) into one show_exp() rather than one per drop.
##
## API: update(player_state, run_info). player_state: hp, mp, max_hp, max_mp, exp, level, job_id (RunWorld
## player_state). run_info: time (s), kills, name, job_name, exp_next (EXP needed for the next level), skills
## ([{"icon": WZ canvas path, "rank": int}]), optional time_limit (s; shows the time left instead of the time spent).

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
## tier C: decorative buttons (normal state) on the right of the bar.
const BUTTONS := [["BtShop", Vector2(571, 36)], ["BtNPT", Vector2(625, 36)], ["BtMenu", Vector2(679, 36)],
	["BtShort", Vector2(733, 36)]]
const KEYS := [["EquipKey", Vector2(600, 8)], ["InvenKey", Vector2(628, 8)], ["StatKey", Vector2(656, 8)],
	["SkillKey", Vector2(684, 8)], ["KeySet", Vector2(712, 8)], ["QuickSlot", Vector2(740, 8)]]
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

## Asset source; defaults to the "Assets" autoload.
var library: AssetLibrary
## Last values given to update().
var player_state: Dictionary = {}
var run_info: Dictionary = {}
## The Arial/Tahoma system font used for text (no antialiasing), and its bold variant for the top counters.
var font: SystemFont
var bold_font: SystemFont

var _canvas: Node2D
var _frames: Dictionary = {}
## System message lines, oldest first: {"text", "color", "age"}.
var _messages: Array[Dictionary] = []


func _ready() -> void:
	layer = 10
	font = make_font()
	bold_font = make_font(700)
	_canvas = Node2D.new()
	_canvas.name = "HudCanvas"
	add_child(_canvas)
	_canvas.draw.connect(_draw_hud)
	get_viewport().size_changed.connect(_canvas.queue_redraw)


## Stores the new values and redraws.
func update(p_player_state: Dictionary, p_run_info: Dictionary) -> void:
	player_state = p_player_state
	run_info = p_run_info
	if _canvas != null:
		_canvas.queue_redraw()


## Adds a system message line (yellow by default).
func push_message(text: String, color: Color = SYSTEM_YELLOW) -> void:
	_messages.append({"text": text, "color": color, "age": 0.0})
	while _messages.size() > MSG_MAX:
		_messages.pop_front()
	if _canvas != null:
		_canvas.queue_redraw()


## Shows "+N EXP" (GAME_DESIGN section 5); nothing for n <= 0.
func show_exp(n: int) -> void:
	if n > 0:
		push_message("+%d EXP" % n)


## The message lines on screen, oldest first: [{"text", "color", "alpha"}].
func messages() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for m in _messages:
		out.append({"text": m.text, "color": m.color, "alpha": message_alpha(float(m.age))})
	return out


## Alpha of a message `age` s old: 1, then a linear fade over the last MSG_FADE s of MSG_LIFE.
static func message_alpha(age: float) -> float:
	return clampf((MSG_LIFE - age) / MSG_FADE, 0.0, 1.0)


## Ages the system messages by `dt` seconds and drops expired ones (redraws only while there are any).
func advance_messages(dt: float) -> void:
	if _messages.is_empty():
		return
	for m in _messages:
		m.age = float(m.age) + dt
	while not _messages.is_empty() and float(_messages[0].age) >= MSG_LIFE:
		_messages.pop_front()
	if _canvas != null:
		_canvas.queue_redraw()


func _process(delta: float) -> void:
	advance_messages(delta)


## The HUD font: system Arial (Tahoma fallback), no antialiasing, no subpixel positioning.
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


func _draw_hud() -> void:
	var view := _canvas.get_viewport_rect().size
	var o := bar_origin(view)
	_draw_bar(o, view)
	_draw_gauges(o + GAUGE_POS)
	_draw_level(o)
	_draw_top(view)
	_draw_messages(o)


func _draw_messages(o: Vector2) -> void:
	var y := o.y - MSG_INSET.y
	for i in range(_messages.size() - 1, -1, -1):
		var m: Dictionary = _messages[i]
		var a := message_alpha(float(m.age))
		var c: Color = m.color
		c.a *= a
		_text(Vector2(o.x + MSG_INSET.x, y), str(m.text), c, FONT_SIZE, null, a)
		y -= MSG_LINE


func _draw_bar(o: Vector2, view: Vector2) -> void:
	var bg := _frame(SB + "base/backgrnd")
	if bg != null:
		var col := Rect2(bg.region.position + Vector2(BAR_W / 2.0, 0), Vector2(1, bg.region.size.y))
		_canvas.draw_texture_rect_region(bg.page, Rect2(0, o.y, view.x, BAR_H), col)
		_blit(bg, o)
	_blit(_frame(SB + "base/backgrnd2"), o)
	for b: Array in BUTTONS:
		_blit(_frame(SB + b[0] + "/normal/0"), o + b[1])
	for k: Array in KEYS:
		_blit(_frame(SB + k[0] + "/normal/0"), o + k[1])


func _draw_gauges(g: Vector2) -> void:
	var bar := _frame(SB + "gauge/bar")
	if bar == null:
		return
	_blit(bar, g)
	var hp := float(player_state.get("hp", 0))
	var max_hp := float(player_state.get("max_hp", 0))
	var mp := float(player_state.get("mp", 0))
	var max_mp := float(player_state.get("max_mp", 0))
	var exp_v := float(player_state.get("exp", 0))
	var exp_next := float(run_info.get("exp_next", 0))
	_gray(g, HP_FILL, fill_width(hp, max_hp, HP_FILL.y))
	_gray(g, MP_FILL, fill_width(mp, max_mp, MP_FILL.y))
	_gray(g, EXP_FILL, fill_width(exp_v, exp_next, EXP_FILL.y))
	_blit(_frame(SB + "gauge/graduation"), g)
	_number_text(g + Vector2(HP_TEXT_X, TEXT_Y), "[%d/%d]" % [int(hp), int(max_hp)])
	_number_text(g + Vector2(MP_TEXT_X, TEXT_Y), "[%d/%d]" % [int(mp), int(max_mp)])
	var pct := 0 if exp_next <= 0.0 else int(floorf(100.0 * clampf(exp_v / exp_next, 0.0, 1.0)))
	_number_text(g + Vector2(EXP_TEXT_X, TEXT_Y), "%d[%d%%]" % [int(exp_v), pct])


func _gray(g: Vector2, fill: Vector2, filled: float) -> void:
	var gray := _frame(SB + "gauge/gray")
	if gray == null or filled >= fill.y:
		return
	var x := g.x + fill.x + filled
	_canvas.draw_texture_rect_region(gray.page, Rect2(x, g.y + FILL_Y, fill.y - filled, FILL_H), gray.region)


func _number_text(p: Vector2, text: String) -> void:
	var x := p.x
	for i in text.length():
		var ch := text[i]
		var key: String = {"[": "Lbracket", "]": "Rbracket", "/": "slash", "%": "percent"}.get(ch, ch)
		var f := _frame(SB + "number/" + key)
		if f == null:
			continue
		var dy := 0.0 if (ch == "[" or ch == "]") else 1.0
		_blit(f, Vector2(x, p.y + dy))
		x += f.region.size.x + 1.0


func _draw_level(o: Vector2) -> void:
	var lv := str(int(player_state.get("level", 1)))
	var x := o.x + LEVEL_POS.x
	for i in lv.length():
		var f := _frame("UI.wz/Basic.img/LevelNo/" + lv[i])
		if f == null:
			continue
		_blit(f, Vector2(x, o.y + LEVEL_POS.y))
		x += f.region.size.x
	_text(o + JOB_POS, str(run_info.get("job_name", "")), Color(1, 1, 1))
	_text(o + NAME_POS, str(run_info.get("name", "")), Color(1, 1, 1))


func _draw_top(view: Vector2) -> void:
	var t := float(run_info.get("time", 0.0))
	if run_info.has("time_limit"):
		t = maxf(0.0, float(run_info.time_limit) - t)
	var big := FONT_SIZE + 8
	var ts := format_time(t)
	var tw := bold_font.get_string_size(ts, HORIZONTAL_ALIGNMENT_LEFT, -1, big).x
	_text(Vector2(floorf((view.x - tw) * 0.5), 28), ts, Color(1, 1, 1), big, bold_font)
	var ks := "KILLS %d" % int(run_info.get("kills", 0))
	var kw := bold_font.get_string_size(ks, HORIZONTAL_ALIGNMENT_LEFT, -1, big).x
	_text(Vector2(view.x - kw - 12, 28), ks, Color(1, 0.86, 0.3), big, bold_font)
	var x := 8.0
	for s: Variant in run_info.get("skills", []):
		if not (s is Dictionary):
			continue
		var icon := _frame(str(s.get("icon", "")))
		if icon != null:
			_blit(icon, Vector2(x, 8))
			_rank(Vector2(x + SKILL_ICON, 8 + SKILL_ICON), int(s.get("rank", 0)))
		x += SKILL_ICON + SKILL_GAP


## Rank digits (Basic.img/ItemNo, the inventory count font) right-aligned at the icon's bottom-right corner.
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


func _text(p: Vector2, s: String, col: Color, size: int = FONT_SIZE, f: Font = null, alpha: float = 1.0) -> void:
	if f == null:
		f = font
	if s == "" or f == null:
		return
	_canvas.draw_string_outline(f, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 3 if size > FONT_SIZE else 2,
		Color(0, 0, 0, 0.9 * alpha))
	_canvas.draw_string(f, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


## Draws a canvas with its top-left at `p` (UI canvases have origin 0,0 or none).
func _blit(f: SpriteFrame, p: Vector2) -> void:
	if f == null or f.page == null:
		return
	_canvas.draw_texture_rect_region(f.page, Rect2(p.floor(), f.region.size), f.region)


func _frame(path: String) -> SpriteFrame:
	if _frames.has(path):
		return _frames[path]
	var lib := _lib()
	var f: SpriteFrame = null
	if lib != null and path != "":
		var n: Variant = lib.find(path)
		if WzImg.is_canvas(n):
			f = lib.frame(path)
	_frames[path] = f
	return f


func _lib() -> AssetLibrary:
	if library == null:
		library = AssetLibrary.get_default()
	return library
