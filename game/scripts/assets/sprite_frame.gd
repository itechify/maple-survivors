class_name SpriteFrame
extends RefCounted
## One frame of a WZ animation: an atlas region plus the canvas properties the renderers need.
##
## Drawing rule (all WZ sprites): the canvas is drawn with its `origin` on the anchor point, i.e. top-left at
## `pos - origin`; mirrored sprites flip around the anchor (top-left at `pos.x - (w - origin.x)`).

## The atlas page holding the canvas (shared by every frame of the img, so draws batch). Batched and RenderingServer
## drawing uses `page` + `region` (draw_texture_rect_region, canvas_item_add_texture_rect_region).
var page: Texture2D
## Pixel region of the canvas inside `page`.
var region := Rect2()
## The frame's own texture: an AtlasTexture of `region` on `page` (created on first use; null without a page), for
## Node-based drawing (Sprite2D, TextureRect, draw_texture). Never pass it with `region` as a source rect: an
## AtlasTexture reads source rects relative to its own region.
var texture: Texture2D:
	get:
		return atlas()
## Canvas origin: the anchor point inside the canvas.
var origin := Vector2.ZERO
## Frame duration in seconds.
var delay_s := 0.1
## Start/end alpha 0..1 of the frame (WZ `a0`/`a1`), interpolated over the frame.
var a0 := 1.0
var a1 := 1.0
## WZ `z` (int for maps/effects, a zmap name for character parts); null when absent.
var z: Variant = null
## Every other child of the canvas node (head, lt, rb, map, foothold, ...), raw cache JSON.
var extras: Dictionary = {}
## Time at which this frame starts inside its animation.
var start := 0.0
## WZ path of the canvas, for diagnostics.
var path := ""

var _atlas: AtlasTexture


## Canvas size in pixels.
func size() -> Vector2:
	return region.size


## Alpha 0..1 at `local_t` seconds into the frame (linear a0 -> a1).
func alpha_at(local_t: float) -> float:
	if a0 == a1 or delay_s <= 0.0:
		return a0
	return lerpf(a0, a1, clampf(local_t / delay_s, 0.0, 1.0))


## A vector child (`head`, `lt`, `rb`, ...) or `fallback`.
func vec(key: String, fallback: Vector2 = Vector2.ZERO) -> Vector2:
	return WzImg.vec(extras.get(key), fallback)


## Top-left corner of the canvas when its origin sits at `pos` (mirrored around `pos` when `flip`).
func top_left(pos: Vector2, flip: bool = false) -> Vector2:
	if flip:
		return Vector2(pos.x - (region.size.x - origin.x), pos.y - origin.y)
	return pos - origin


## An AtlasTexture view of the frame for Node-based drawing (created on first use; also `texture`).
func atlas() -> AtlasTexture:
	if _atlas == null and page != null:
		_atlas = AtlasTexture.new()
		_atlas.atlas = page
		_atlas.region = region
		_atlas.filter_clip = true
	return _atlas
