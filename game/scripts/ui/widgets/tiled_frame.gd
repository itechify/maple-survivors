class_name TiledFrame
extends RefCounted
## Stretchable MapleStory window frames built by repeating WZ pieces, never by scaling them.
##
## Vertical frames come in two shapes in v83 UI.wz:
##   - separate canvases `t` / `c` / `s` (top, centre repeated N times, bottom): UIWindow.img/UtilDlgEx (the NPC
##     dialog), Basic.img/Notice3, YesNo3 ...: `draw_v(ci, pos, top, centre, bottom, height)`;
##   - one canvas whose middle rows are uniform (UIWindow.img/SkillUp/backgrd rows 169-179):
##     `draw_v_slices(ci, pos, frame, top_h, mid_y, mid_h, height)` repeats rows [mid_y, mid_y + mid_h) between the
##     canvas's own top `top_h` rows and its rows from mid_y + mid_h to the end.
## Horizontal 3-slices of one canvas (UIWindow.img/Skill/skill0, a 141 px skill row with a 36 px icon slot, widened by
## repeating one uniform column): `draw_h_slices(ci, pos, frame, left_w, mid_x, width)`.
## `nine_slice()` draws a 9-piece frame (UIWindow.img/EventWindow/backgrnd top|center|bottom x left|center|right).

## Number of centre pieces needed so that top + n * centre + bottom >= height (at least 0).
static func center_count(height: float, top_h: float, center_h: float, bottom_h: float) -> int:
	if center_h <= 0.0:
		return 0
	return maxi(0, ceili((height - top_h - bottom_h) / center_h))


## Height of a t/c/s frame with `n` centre pieces.
static func frame_height(n: int, top_h: float, center_h: float, bottom_h: float) -> float:
	return top_h + n * center_h + bottom_h


## Draws top, `center_count()` centre pieces and bottom from `pos`; returns the drawn height (>= height, rounded up
## to whole centre pieces like the client's dialogs).
static func draw_v(ci: CanvasItem, pos: Vector2, top: SpriteFrame, center: SpriteFrame, bottom: SpriteFrame,
		height: float) -> float:
	if top == null or center == null or bottom == null:
		return 0.0
	var th := top.region.size.y
	var ch := center.region.size.y
	var n := center_count(height, th, ch, bottom.region.size.y)
	UiArt.blit(ci, top, pos)
	var y := pos.y + th
	for i in n:
		UiArt.blit(ci, center, Vector2(pos.x, y))
		y += ch
	UiArt.blit(ci, bottom, Vector2(pos.x, y))
	return y + bottom.region.size.y - pos.y


## One canvas stretched vertically to exactly `height`: rows [0, top_h) at the top, rows [mid_y, mid_y + mid_h)
## repeated (the last repeat cut), then rows [mid_y + mid_h, end) at the bottom (`top_h` <= mid_y). A height below
## top_h + bottom draws just the top and the bottom.
static func draw_v_slices(ci: CanvasItem, pos: Vector2, f: SpriteFrame, top_h: float, mid_y: float, mid_h: float,
		height: float, col: Color = Color.WHITE) -> void:
	if f == null:
		return
	var w := f.region.size.x
	var bottom_y := mid_y + mid_h
	var bottom_h := f.region.size.y - bottom_y
	UiArt.blit_part(ci, f, Rect2(0, 0, w, top_h), pos, Vector2.ZERO, col)
	var y := top_h
	var end := maxf(top_h, height - bottom_h)
	while y < end and mid_h > 0.0:
		var h := minf(mid_h, end - y)
		UiArt.blit_part(ci, f, Rect2(0, mid_y, w, h), pos + Vector2(0, y), Vector2.ZERO, col)
		y += h
	UiArt.blit_part(ci, f, Rect2(0, bottom_y, w, bottom_h), pos + Vector2(0, end), Vector2.ZERO, col)


## One canvas widened to `width`: columns [0, left_w) as they are, then column `mid_x` (1 px) repeated to the end and
## the canvas's last column as the right edge.
static func draw_h_slices(ci: CanvasItem, pos: Vector2, f: SpriteFrame, left_w: float, mid_x: float, width: float,
		col: Color = Color.WHITE) -> void:
	if f == null:
		return
	var h := f.region.size.y
	var w := f.region.size.x
	UiArt.blit_part(ci, f, Rect2(0, 0, left_w, h), pos, Vector2.ZERO, col)
	var fill := width - left_w - 1.0
	if fill > 0.0:
		UiArt.blit_part(ci, f, Rect2(mid_x, 0, 1, h), pos + Vector2(left_w, 0), Vector2(fill, h), col)
	UiArt.blit_part(ci, f, Rect2(w - 1, 0, 1, h), pos + Vector2(width - 1.0, 0), Vector2.ZERO, col)


## A 9-piece frame: `base` holds top/center/bottom, each with left/center/right canvases (EventWindow/backgrnd). The
## centre pieces are repeated (1-px-wide/tall uniform pieces may be stretched) to fill `rect`.
static func nine_slice(ci: CanvasItem, base: String, rect: Rect2, col: Color = Color.WHITE) -> void:
	var tl := UiArt.frame(base + "/top/left")
	var tc := UiArt.frame(base + "/top/center")
	var tr := UiArt.frame(base + "/top/right")
	var ml := UiArt.frame(base + "/center/left")
	var mc := UiArt.frame(base + "/center/center")
	var mr := UiArt.frame(base + "/center/right")
	var bl := UiArt.frame(base + "/bottom/left")
	var bc := UiArt.frame(base + "/bottom/center")
	var br := UiArt.frame(base + "/bottom/right")
	if tl == null or mc == null or br == null or tc == null or tr == null or ml == null or mr == null or bl == null \
			or bc == null:
		return
	var x0 := rect.position.x
	var y0 := rect.position.y
	var x1 := rect.end.x - tr.region.size.x
	var y1 := rect.end.y - bl.region.size.y
	var lw := tl.region.size.x
	var th := tl.region.size.y
	_tile(ci, tc, Rect2(x0 + lw, y0, x1 - x0 - lw, tc.region.size.y), col)
	_tile(ci, ml, Rect2(x0, y0 + th, ml.region.size.x, y1 - y0 - th), col)
	_tile(ci, mc, Rect2(x0 + lw, y0 + th, x1 - x0 - lw, y1 - y0 - th), col)
	_tile(ci, mr, Rect2(x1, y0 + th, mr.region.size.x, y1 - y0 - th), col)
	_tile(ci, bc, Rect2(x0 + lw, y1, x1 - x0 - lw, bc.region.size.y), col)
	UiArt.blit(ci, tl, Vector2(x0, y0), col)
	UiArt.blit(ci, tr, Vector2(x1, y0), col)
	UiArt.blit(ci, bl, Vector2(x0, y1), col)
	UiArt.blit(ci, br, Vector2(x1, y1), col)


## Repeats a canvas over `r` (cut at the right and bottom edges).
static func _tile(ci: CanvasItem, f: SpriteFrame, r: Rect2, col: Color) -> void:
	var w := f.region.size.x
	var h := f.region.size.y
	if w <= 0.0 or h <= 0.0 or r.size.x <= 0.0 or r.size.y <= 0.0:
		return
	var y := 0.0
	while y < r.size.y:
		var ph := minf(h, r.size.y - y)
		var x := 0.0
		while x < r.size.x:
			var pw := minf(w, r.size.x - x)
			UiArt.blit_part(ci, f, Rect2(0, 0, pw, ph), r.position + Vector2(x, y), Vector2.ZERO, col)
			x += pw
		y += ph
