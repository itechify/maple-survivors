class_name BackMath
extends RefCounted
## Placement math for map backgrounds (`back/N`: x, y, rx, ry, type, cx, cy, a, f, front, ani), pure and static.
##
## Rules (docs/research/prior-art.md section 3; WzComparerR2, HeavenClient, NoLifeStory and MapleNecrocer agree):
## - type 0 none, 1 tile X, 2 tile Y, 3 tile both, 4 tile X + scroll X, 5 tile Y + scroll Y, 6 both + scroll X,
##   7 both + scroll Y.
## - Parallax: screen = pos + cam_center * r / 100 + view / 2 per axis (r = 0: fixed to the screen, r = -100: fixed to
##   the world). Positions are floored before drawing.
## - Auto-scroll axis (types 4-7): screen = pos + r * 5 px/s * t + view / 2 (tier B: 3 reimplementations agree on 5 px/s;
##   no camera term on that axis is our reading of "auto-scroll X, parallax Y"; it is tiled, so only the phase differs).
## - Tile period: cx / cy, or the canvas size when 0. Copies cover the whole view.
## Screen coordinates have (0, 0) at the view's top-left.

## tier B: auto-scroll speed per rx/ry unit, px/s.
const SCROLL_PX_PER_UNIT := 5.0


## True when the type tiles horizontally.
static func tiles_x(type: int) -> bool:
	return type == 1 or type == 3 or type == 4 or type == 6 or type == 7


## True when the type tiles vertically.
static func tiles_y(type: int) -> bool:
	return type == 2 or type == 3 or type == 5 or type == 6 or type == 7


## True when the type scrolls horizontally on its own.
static func scrolls_x(type: int) -> bool:
	return type == 4 or type == 6


## True when the type scrolls vertically on its own.
static func scrolls_y(type: int) -> bool:
	return type == 5 or type == 7


## Tile period: cx/cy when set, else the canvas size.
static func period(c: Vector2, canvas_size: Vector2) -> Vector2:
	return Vector2(c.x if c.x > 0.0 else canvas_size.x, c.y if c.y > 0.0 else canvas_size.y)


## Screen position of the back's anchor (where the canvas origin goes), floored to whole pixels.
## `r` = (rx, ry); `t` = seconds since the map was shown; `per` = tile period (keeps the scroll offset small).
static func anchor_screen(pos: Vector2, r: Vector2, type: int, cam_center: Vector2, view: Vector2, t: float,
		per: Vector2 = Vector2.ZERO) -> Vector2:
	var x: float
	var y: float
	if scrolls_x(type):
		x = pos.x + _wrap(r.x * SCROLL_PX_PER_UNIT * t, per.x) + view.x * 0.5
	else:
		x = pos.x + cam_center.x * r.x / 100.0 + view.x * 0.5
	if scrolls_y(type):
		y = pos.y + _wrap(r.y * SCROLL_PX_PER_UNIT * t, per.y) + view.y * 0.5
	else:
		y = pos.y + cam_center.y * r.y / 100.0 + view.y * 0.5
	return Vector2(floorf(x), floorf(y))


## Leading edges of the copies along one axis that intersect [0, view_len): `first` is copy 0's edge, `size` the
## canvas extent on that axis. Untiled: just `first` (when visible).
static func tile_starts(first: float, per: float, size: float, view_len: float, tiled: bool) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if not tiled or per <= 0.0:
		if first < view_len and first + size > 0.0:
			out.append(first)
		return out
	var k0 := floori((-size - first) / per) + 1
	var s := first + k0 * per
	var guard := 0
	while s < view_len and guard < 4096:
		out.append(s)
		s += per
		guard += 1
	return out


static func _wrap(v: float, per: float) -> float:
	return fposmod(v, per) if per > 0.0 else v
