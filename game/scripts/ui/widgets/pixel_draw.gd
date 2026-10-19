class_name PixelDraw
extends RefCounted
## Pixel-art drawing helpers for the window-resolution canvas (#224, docs/ARCHITECTURE.md "Fonts and sharp text").
## The window draws canvas items at its own pixel size (stretch mode canvas_items) so text is sharp; two kinds of
## primitive would then look different from the old 800x600 render, and these helpers draw them as that render did:
##   - a 1 px outline (`draw_rect(r, c, false)`) became one window pixel thin: outline() fills the logical pixels the
##     old thin lines lit;
##   - a texture drawn smaller than its art (nearest) sampled the art at window pixels: blit_scaled() copies the art
##     texels the 800x600 render picked, as unscaled runs, so the icon is the same at any scale.


## The rects (whole logical pixels) a 1 px `draw_rect(r, c, false)` lit in the 800x600 render (measured with GL
## compatibility, tier A for this engine): the top edge one row above `r`, the left edge one column left of it, the
## right and bottom edges inside it. The rects do not overlap (a translucent colour blends once per pixel).
static func outline_rects(r: Rect2) -> Array[Rect2]:
	var p := r.position.floor()
	var s := r.size.floor()
	return [
		Rect2(p.x, p.y - 1.0, s.x, 1.0),
		Rect2(p.x - 1.0, p.y, 1.0, s.y - 1.0),
		Rect2(p.x + s.x - 1.0, p.y, 1.0, s.y - 1.0),
		Rect2(p.x - 1.0, p.y + s.y - 1.0, s.x + 1.0, 1.0),
	]


## Draws a 1 logical px outline of `r` like the old `draw_rect(r, color, false)`.
static func outline(ci: CanvasItem, r: Rect2, color: Color) -> void:
	for e in outline_rects(r):
		ci.draw_rect(e, color)


## A nearest downscale of `src` texels to `dst` pixels as runs [dst_start, src_start, length, ...]: pixel i samples
## texel floor((i + 0.5) * src / dst), the texel the GPU picks; consecutive texels form one run.
static func nearest_runs(src: int, dst: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	if src <= 0 or dst <= 0:
		return out
	for i in dst:
		var t := int(floor((i + 0.5) * float(src) / float(dst)))
		var n := out.size()
		if n > 0 and out[n - 3] + out[n - 1] == i and out[n - 2] + out[n - 1] == t:
			out[n - 1] += 1
		else:
			out.append_array([i, t, 1])
	return out


## Draws `region` of `tex` into `rect` (whole logical px) with nearest sampling as the 800x600 render did: a
## downscaled icon picks the same texels at any window scale. Same size is a single plain blit.
static func blit_scaled(ci: CanvasItem, tex: Texture2D, rect: Rect2, region: Rect2, modulate: Color = Color.WHITE) -> void:
	var p := rect.position.floor()
	var cols := nearest_runs(int(region.size.x), int(rect.size.x))
	var rows := nearest_runs(int(region.size.y), int(rect.size.y))
	for j in range(0, rows.size(), 3):
		for i in range(0, cols.size(), 3):
			ci.draw_texture_rect_region(tex, Rect2(p.x + cols[i], p.y + rows[j], cols[i + 2], rows[j + 2]),
				Rect2(region.position.x + cols[i + 1], region.position.y + rows[j + 1], cols[i + 2], rows[j + 2]),
				modulate)
