class_name MapDrawList
extends Node2D
## A run of map sprites (tiles, objs, portals) drawn in order by one canvas item.
##
## A static run is recorded once in _draw() (its command list is cached by the renderer); an animated run holds one
## animated sprite and redraws only when its frame (or its a0/a1 alpha ramp) changes. MapRenderer splits each layer
## into such runs so the WZ draw order is kept exactly while static parts are never re-recorded.

## Entries: {"anim": SpriteAnim, "pos": Vector2, "flip": bool}.
var items: Array = []
## True when the run holds an animated sprite.
var animated := false
## Seconds since the map was shown (animated runs).
var time := 0.0

var _shown := -1


## Appends a sprite drawn with its origin at `pos` (mirrored around it when `flip`).
func add(anim: SpriteAnim, pos: Vector2, flip: bool) -> void:
	items.append({"anim": anim, "pos": pos, "flip": flip})


## Advances an animated run; requests a redraw only when the visible frame or its alpha changes.
func advance(dt: float) -> void:
	if not animated or items.is_empty():
		return
	time += dt
	var a: SpriteAnim = items[0].anim
	var i := a.index_at(time, true)
	var f := a.frames[i]
	if i != _shown or f.a0 != f.a1:
		_shown = i
		queue_redraw()


func _draw() -> void:
	for it: Dictionary in items:
		var a: SpriteAnim = it.anim
		var f: SpriteFrame
		var alpha := 1.0
		if animated:
			f = a.frame_at(time, true)
			alpha = a.alpha_at(time, true)
		else:
			f = a.frames[0]
			alpha = f.a0
		if f == null or f.page == null:
			continue
		draw_frame(self, f, it.pos, it.flip, Color(1, 1, 1, alpha))


## Draws a frame with its origin at `pos` on `ci`; mirrored around `pos.x` when `flip` (a draw transform: negative
## rect sizes do not mirror in draw_texture_rect_region).
static func draw_frame(ci: CanvasItem, f: SpriteFrame, pos: Vector2, flip: bool, col: Color = Color.WHITE) -> void:
	if flip:
		ci.draw_set_transform(Vector2(2.0 * pos.x, 0.0), 0.0, Vector2(-1.0, 1.0))
	ci.draw_texture_rect_region(f.page, Rect2(pos - f.origin, f.region.size), f.region, col)
	if flip:
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
