class_name WzImage
extends Control
## A Control that draws one WZ canvas, or plays a WZ animation, from the asset cache.
##
## The canvas origin is put on `anchor` (control-local px). With the default anchor (-1, -1) the anchor is the canvas's
## own origin, i.e. the canvas top-left sits at the control's (0, 0) and the control's minimum size is the canvas size
## (UI art). For sprites positioned by their origin (an NPC's feet, a mob's feet) set `anchor` to where the origin
## goes. `path` may be a canvas ("UI.wz/Login.img/Title/MSTitle") or an animation node ("Npc.wz/1032001.img/stand");
## animations loop with their WZ delays and a0/a1 alpha when `playing`.
##
##   var npc := WzImage.new("Npc.wz/1032001.img/stand", Vector2(65, 160))

## WZ path of the canvas or animation node.
@export var path := "":
	set(v):
		path = v
		_reload()
## Where the canvas origin is drawn (control-local); (-1, -1) = the canvas origin itself (top-left at 0, 0).
@export var anchor := Vector2(-1, -1):
	set(v):
		anchor = v
		queue_redraw()
## Mirror around the anchor.
@export var flip := false:
	set(v):
		flip = v
		queue_redraw()
## Advance the animation.
@export var playing := true

var _anim: SpriteAnim
var _t := 0.0
var _shown := -1


func _init(p_path: String = "", p_anchor: Vector2 = Vector2(-1, -1)) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor = p_anchor
	path = p_path


## True when the art was found in the cache.
func has_art() -> bool:
	return _anim != null and not _anim.is_empty()


## The frame currently drawn (null without art).
func current_frame() -> SpriteFrame:
	if not has_art():
		return null
	return _anim.frame_at(_t, true)


func _process(delta: float) -> void:
	if not playing or not has_art() or _anim.frame_count() <= 1:
		return
	_t += delta
	var i := _anim.index_at(_t, true)
	var f := _anim.frames[i]
	if i != _shown or f.a0 != f.a1:
		_shown = i
		queue_redraw()


func _draw() -> void:
	var f := current_frame()
	if f == null:
		return
	var a := _anim.alpha_at(_t, true) if _anim.frame_count() > 1 else 1.0
	var at := f.origin if anchor == Vector2(-1, -1) else anchor
	UiArt.blit_origin(self, f, at, flip, Color(1, 1, 1, a))


func _reload() -> void:
	_anim = null
	_t = 0.0
	_shown = -1
	if path != "":
		var f := UiArt.frame(path)
		if f != null:
			_anim = SpriteAnim.new()
			_anim.frames.append(f)
			_anim.total = f.delay_s
		else:
			_anim = UiArt.anim(path)
	var first := current_frame()
	custom_minimum_size = first.region.size if first != null and anchor == Vector2(-1, -1) else Vector2.ZERO
	queue_redraw()
