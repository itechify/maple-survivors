class_name FlashTrail
extends Node2D
## The ghost trail of a Flash Jump (M14, GAME_DESIGN 7.94.2): a few translucent copies of the avatar's current frame left
## along the path of the flash, fading out. Flash Jump's WZ node has no art, so this is drawn by code from the avatar's own
## parts (tier C: ours). Presentation only; the path and the copies' points come from FlashJump.trail.

## One live ghost: {parts: Array, pos: Vector2, facing: int, alpha: float, age: float}.
var _ghosts: Array[Dictionary] = []


## Leaves the ghosts of a flash from `from` to `to`, drawn from `parts` (AvatarRenderer.current_parts()) mirrored for `facing`.
func spawn(parts: Array, facing: int, from: Vector2, to: Vector2) -> void:
	for g: Dictionary in FlashJump.trail(from, to):
		_ghosts.append({"parts": parts, "pos": (g.pos as Vector2).round(), "facing": facing, "alpha": float(g.alpha), "age": 0.0})
	set_process(true)
	queue_redraw()


## Ghosts still showing.
func count() -> int:
	return _ghosts.size()


func _ready() -> void:
	set_process(false)


func _process(delta: float) -> void:
	var kept: Array[Dictionary] = []
	for g: Dictionary in _ghosts:
		g.age = float(g.age) + delta
		if float(g.age) < FlashJump.TRAIL_TIME:
			kept.append(g)
	_ghosts = kept
	if _ghosts.is_empty():
		set_process(false)
	queue_redraw()


func _draw() -> void:
	for g: Dictionary in _ghosts:
		var a := float(g.alpha) * (1.0 - float(g.age) / FlashJump.TRAIL_TIME)
		draw_set_transform(g.pos, 0.0, Vector2(-1, 1) if int(g.facing) > 0 else Vector2.ONE)
		for p: Dictionary in g.parts:
			var f: SpriteFrame = p.frame
			if f.page == null:
				continue
			draw_texture_rect_region(f.page, Rect2(p.pos - f.origin, f.region.size), f.region, Color(1, 1, 1, a))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
