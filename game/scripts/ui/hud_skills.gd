class_name HudSkills
extends HudWidget
## Owned skill icons and ranks, supplied independently by RunScene. A cooling skill is covered by a dark overlay that
## clears clockwise from 12 o'clock (one polygon per icon); a ready skill waiting for MP is tinted blue.

## tier C: eight 24 px icons per row keep fifteen skills left of the timer and boss bars at 800 px.
const ICON_SIZE := 24
const COLUMNS := 8
## Below this remaining fraction the sweep is not drawn (a sliver too thin to triangulate or see).
const SWEEP_MIN := 0.002
## Icon corners (half-size units) clockwise from 12 o'clock: top-right, bottom-right, bottom-left, top-left.
const CORNERS: Array[Vector2] = [Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1)]
## tier C: the cooldown overlay's darkness, and the blue modulation of a ready skill waiting for MP (it replaced
## Teleport's grey can't-afford tint so every skill shows the same cue).
const SWEEP_COLOR := Color(0, 0, 0, 0.6)
const MP_WAIT_TINT := Color(0.35, 0.5, 1.0)

## Reused overlay polygon (sweep_polygon resizes it in place).
var _sweep := PackedVector2Array()


## Fills `out` with the dark cooldown overlay of an icon in `rect`: with fraction f = remaining / total left, a wedge
## of f x 360 degrees from the centre, clipped to the icon and ending at 12 o'clock, so the overlay clears clockwise
## from 12 o'clock. Empty when ready, before any cast (total <= 0) or below SWEEP_MIN; the whole rect when full.
## `out` is reused (resized in place) so the draw loop allocates no new array.
static func sweep_polygon(remaining: float, total: float, rect: Rect2, out: PackedVector2Array) -> void:
	var f := clampf(remaining / total, 0.0, 1.0) if total > 0.0 else 0.0
	if f < SWEEP_MIN:
		out.resize(0)
		return
	if f >= 1.0 - SWEEP_MIN:
		out.resize(4)
		out[0] = rect.position
		out[1] = Vector2(rect.end.x, rect.position.y)
		out[2] = rect.end
		out[3] = Vector2(rect.position.x, rect.end.y)
		return
	var c := rect.get_center()
	var h := rect.size * 0.5
	var start := (1.0 - f) * TAU
	out.resize(7)
	out[0] = c
	out[1] = _edge_point(c, h, start)
	var n := 2
	for corner: Vector2 in CORNERS:
		if fposmod(atan2(corner.x * h.x, -corner.y * h.y), TAU) > start + 1e-5:
			out[n] = c + corner * h
			n += 1
	out[n] = Vector2(c.x, rect.position.y)
	out.resize(n + 1)


## Where the ray from `c` at clockwise-from-12 angle `a` leaves a box of half size `h`.
static func _edge_point(c: Vector2, h: Vector2, a: float) -> Vector2:
	var d := Vector2(sin(a), -cos(a))
	var t := INF
	if absf(d.x) > 1e-9:
		t = h.x / absf(d.x)
	if absf(d.y) > 1e-9:
		t = minf(t, h.y / absf(d.y))
	return c + d * t


func _draw() -> void:
	var i := 0
	for s: Variant in run_info.get("skills", []):
		if not (s is Dictionary):
			continue
		var p := Vector2(8 + (i % COLUMNS) * (ICON_SIZE + SKILL_GAP), 8 + (i / COLUMNS) * (ICON_SIZE + SKILL_GAP))
		var icon := _frame(str(s.get("icon", "")))
		if icon != null:
			var rect := Rect2(p, Vector2(ICON_SIZE, ICON_SIZE))
			var tint := MP_WAIT_TINT if bool(s.get("mp_short", false)) else Color.WHITE
			draw_texture_rect_region(icon.page, rect, icon.region, tint)
			sweep_polygon(float(s.get("cooldown_left", 0.0)), float(s.get("cooldown_total", 0.0)), rect, _sweep)
			if not _sweep.is_empty():
				draw_colored_polygon(_sweep, SWEEP_COLOR)
			_rank(p + Vector2(ICON_SIZE, ICON_SIZE), int(s.get("rank", 0)))
		_text(p + Vector2(1, 10), String(s.get("key_label", "")), Color.WHITE, 10)
		i += 1
