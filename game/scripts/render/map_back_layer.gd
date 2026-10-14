class_name MapBackLayer
extends Node2D
## The map backgrounds of one group (non-front or front), redrawn every frame from the camera (BackMath rules).
##
## Drawn in world space: each back is placed in screen space by BackMath, then offset by the camera's top-left, so the
## layer can sit in the world between the map layers (front backs after the last layer) under the same Camera2D.

## Entries: {"anim": SpriteAnim, "pos": Vector2, "r": Vector2, "type": int, "c": Vector2, "alpha": float,
## "flip": bool, "ani": bool, "path": String}.
var backs: Array = []
## Camera centre and view size in world pixels, and seconds since the map was shown (set by MapRenderer).
var cam_center := Vector2.ZERO
var view_size := Vector2(800, 600)
var time := 0.0
## Sprites drawn by the last _draw (for tests/diagnostics).
var last_draw_count := 0


func _draw() -> void:
	last_draw_count = 0
	var origin_world := cam_center - view_size * 0.5
	for b: Dictionary in backs:
		var a: SpriteAnim = b.anim
		var f: SpriteFrame = a.frame_at(time, true) if b.ani else a.frames[0]
		if f == null or f.page == null:
			continue
		var type: int = b.type
		var size := f.region.size
		var per := BackMath.period(b.c, a.frames[0].region.size)
		var anchor := BackMath.anchor_screen(b.pos, b.r, type, cam_center, view_size, time, per)
		var tl := f.top_left(anchor, b.flip)
		var xs := BackMath.tile_starts(tl.x, per.x, size.x, view_size.x, BackMath.tiles_x(type))
		var ys := BackMath.tile_starts(tl.y, per.y, size.y, view_size.y, BackMath.tiles_y(type))
		var col := Color(1, 1, 1, float(b.alpha) * (a.alpha_at(time, true) if b.ani else f.a0))
		for y in ys:
			for x in xs:
				var dst := Rect2(origin_world + Vector2(x, y), size)
				if b.flip:
					# Mirror the copy in place (negative rect sizes do not mirror in draw_texture_rect_region).
					draw_set_transform(Vector2(2.0 * dst.position.x + size.x, 0.0), 0.0, Vector2(-1.0, 1.0))
				draw_texture_rect_region(f.page, dst, f.region, col)
				if b.flip:
					draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				last_draw_count += 1
