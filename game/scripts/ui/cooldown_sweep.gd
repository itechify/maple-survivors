class_name CooldownSweep
extends RefCounted
## Shared clockwise cooldown overlay for skill icons and potion quick-slot cells. Callers retain their step state
## and reuse their polygon buffer.

## tier C: below this remaining fraction the sweep is not drawn (a sliver too thin to triangulate or see).
const SWEEP_MIN := 0.002
## tier C: the sweep moves in steps of 1/SWEEP_STEPS of the cooldown (96 = one step per pixel of a 24 px icon's
## edge): smooth to the eye, and a long cooldown does not redraw the widget every frame.
const SWEEP_STEPS := 96
## Icon corners (half-size units) clockwise from 12 o'clock: top-right, bottom-right, bottom-left, top-left.
const CORNERS: Array[Vector2] = [Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1)]
## tier C: the cooldown overlay darkness.
const SWEEP_COLOR := Color(0, 0, 0, 0.6)


## The sweep step of an icon `remaining` of `total` seconds from ready: 0 when ready, before any cast or below
## SWEEP_MIN; SWEEP_STEPS when the overlay is full.
static func sweep_step(remaining: float, total: float) -> int:
	var f := clampf(remaining / total, 0.0, 1.0) if total > 0.0 else 0.0
	if f < SWEEP_MIN:
		return 0
	return clampi(ceili(f * SWEEP_STEPS), 1, SWEEP_STEPS)


## Fills `out` with the dark cooldown overlay of an icon in `rect`: with fraction f = remaining / total left, a wedge
## of f x 360 degrees from the centre, clipped to the icon and ending at 12 o'clock, so the overlay clears clockwise
## from 12 o'clock. Empty when ready, before any cast (total <= 0) or below SWEEP_MIN; the whole rect when full.
## `out` is the caller's reused array (resized in place), so the draw loop builds no new array per icon.
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


## Draws the overlay of a quantized step, reusing the caller's polygon buffer.
static func draw_overlay(canvas: CanvasItem, step: int, rect: Rect2, out: PackedVector2Array) -> void:
	sweep_polygon(float(step), float(SWEEP_STEPS), rect, out)
	if not out.is_empty():
		canvas.draw_colored_polygon(out, SWEEP_COLOR)
