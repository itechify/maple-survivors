class_name CameraRig
extends Camera2D
## Follow camera: exponential smoothing with a dead zone, the target at 58% of the view height, clamped to the map
## bounds (MapBounds), whole-pixel positions (docs/GAME_DESIGN.md section 11, all tier C: ours).
##
## The view size is read live from the viewport, so a wider window (stretch aspect "expand") shows more of the map.
## When the map is narrower (or shorter) than the view, the camera centres on the bounds on that axis.
## Process order: runs after the target moves (priority 5) and before MapRenderer (priority 10).

## tier C: smoothing rate 1/s (fraction of the remaining offset closed per second ~ 1 - e^-6).
const SMOOTHING := 6.0
## tier C: the camera does not move while the target is within this many px of the desired centre (per axis).
const DEAD_ZONE := 8.0
## tier C: the target's feet sit at this fraction of the view height.
const ANCHOR_Y := 0.58

## Node to follow (its global_position); when null, `target_pos` is used.
var target: Node2D
var target_pos := Vector2.ZERO
## Camera limits in world pixels; an empty rect means unclamped.
var bounds := Rect2()
## Where the target sits vertically, as a fraction of the view height (0.5 = centred, e.g. for a free camera).
var anchor_y := ANCHOR_Y
## Jump straight to the target on the next update (no smoothing).
var snap_next := true

var _pos := Vector2.ZERO


func _init() -> void:
	process_priority = 5
	anchor_mode = Camera2D.ANCHOR_MODE_DRAG_CENTER
	position_smoothing_enabled = false


func _process(delta: float) -> void:
	update_camera(delta)


## Moves the camera for a frame of `delta` seconds and applies the whole-pixel position immediately.
func update_camera(delta: float) -> void:
	var view := view_size()
	var t := target.global_position if target != null else target_pos
	var desired := desired_center(t, view, anchor_y)
	if snap_next:
		_pos = desired
		snap_next = false
	else:
		_pos = follow(_pos, desired, delta, SMOOTHING, DEAD_ZONE)
	_pos = clamp_center(_pos, bounds, view)
	global_position = pixel_center(_pos, view)
	force_update_scroll()


## Teleports the camera onto a point (next update snaps).
func snap_to(p: Vector2) -> void:
	target_pos = p
	snap_next = true


## The logical view size (800x600, or wider/taller with aspect "expand").
func view_size() -> Vector2:
	if not is_inside_tree():
		return Vector2(800, 600)
	return get_viewport().get_visible_rect().size / zoom


## The world rect shown this frame (top-left on whole pixels). It is not RunWorld.view: the sim keeps a player-centred
## rect for its spawn rule, while the camera puts the feet at ANCHOR_Y and lags behind (about 0.08 x the view height
## lower, plus the smoothing lag); integration can compare the two with this.
func view_rect() -> Rect2:
	var v := view_size()
	return Rect2(global_position - v * 0.5, v)


## Camera centre that puts the target's feet at ANCHOR_Y of the view height.
static func desired_center(target_feet: Vector2, view: Vector2, anchor: float = ANCHOR_Y) -> Vector2:
	return target_feet + Vector2(0.0, (0.5 - anchor) * view.y)


## One smoothing step per axis: inside the dead zone nothing moves; outside, the excess decays at `rate`/s.
static func follow(cur: Vector2, desired: Vector2, dt: float, rate: float, dead: float) -> Vector2:
	var k := 1.0 - exp(-rate * dt)
	var out := cur
	for axis in 2:
		var d := desired[axis] - cur[axis]
		if absf(d) > dead:
			out[axis] = cur[axis] + (d - signf(d) * dead) * k
	return out


## Clamps a centre so the view stays inside `bounds`; centres on an axis where the bounds are smaller than the view.
static func clamp_center(c: Vector2, b: Rect2, view: Vector2) -> Vector2:
	if b.size.x <= 0.0 or b.size.y <= 0.0:
		return c
	var out := c
	for axis in 2:
		var lo := b.position[axis] + view[axis] * 0.5
		var hi := b.end[axis] - view[axis] * 0.5
		out[axis] = (b.position[axis] + b.end[axis]) * 0.5 if lo >= hi else clampf(c[axis], lo, hi)
	return out


## The centre whose view top-left is on a whole pixel (so every sprite lands on the pixel grid).
static func pixel_center(c: Vector2, view: Vector2) -> Vector2:
	return (c - view * 0.5).round() + view * 0.5
