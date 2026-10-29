class_name ChainBoltRenderer
extends Node2D
## The bolt art of the chain cast rule (`skill_chain` event, ChainCast): per segment of the polyline, one WZ ball
## animation stretched along the segment and rotated to its angle, played once. The variants (the skill's `chain.ball`
## paths, three for Chain Lightning) cycle along the chain. One pooled RenderingServer canvas item per live segment, no
## Nodes per bolt.
##
## Tier C (ours): the frame is stretched on its own x axis from the segment's start to its end and centred on the
## line; its WZ origin is ignored, so art drawn pointing left or right looks the same.

var _items: Array[RID] = []
var _anim: Array = []
var _t := PackedFloat32Array()
var _from := PackedVector2Array()
var _to := PackedVector2Array()
var _active := PackedByteArray()
var _shown: Array = []
var _free: PackedInt32Array = []


## The polyline `points` as segments: [{from, to, length, angle, variant}] with the variant index cycling over
## `variants` (at least 1). Zero-length segments are dropped.
static func segments(points: PackedVector2Array, variants: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in range(1, points.size()):
		var delta := points[i] - points[i - 1]
		if delta.length() < 0.5:
			continue
		out.append({"from": points[i - 1], "to": points[i], "length": delta.length(), "angle": delta.angle(),
			"variant": out.size() % maxi(1, variants)})
	return out


## The canvas transform that stretches a frame of `size` (drawn from its left edge, centred vertically) from
## `from` to `to`.
static func segment_transform(from: Vector2, to: Vector2, size: Vector2) -> Transform2D:
	var delta := to - from
	return Transform2D(delta.angle(), Vector2(delta.length() / maxf(size.x, 1.0), 1.0), 0.0, from)


## Starts a bolt along `points` using the animations `anims` (SpriteAnim, one per variant). Returns how many segments
## were started.
func play(points: PackedVector2Array, anims: Array) -> int:
	var started := 0
	if anims.is_empty():
		return 0
	for seg: Dictionary in segments(points, anims.size()):
		var anim: SpriteAnim = anims[int(seg.variant)]
		if anim == null or anim.is_empty():
			continue
		var i := _alloc()
		_anim[i] = anim
		_t[i] = 0.0
		_from[i] = seg.from
		_to[i] = seg.to
		_active[i] = 1
		_show_segment(i)
		started += 1
	return started


## Advances every bolt by `dt` seconds and frees the ones that played out.
func advance(dt: float) -> void:
	for i in _active.size():
		if _active[i] == 0:
			continue
		_t[i] += dt
		if (_anim[i] as SpriteAnim).finished(_t[i]):
			_release(i)
		else:
			_show_segment(i)


## Number of segments playing.
func active_count() -> int:
	var n := 0
	for a in _active:
		n += a
	return n


## Stops every bolt.
func clear() -> void:
	for i in _active.size():
		if _active[i] == 1:
			_release(i)


func _process(delta: float) -> void:
	advance(delta)


func _exit_tree() -> void:
	for ci in _items:
		RenderingServer.free_rid(ci)
	_items.clear()


func _show_segment(i: int) -> void:
	var anim: SpriteAnim = _anim[i]
	var frame := anim.frame_at(_t[i], false)
	var ci := _items[i]
	if _shown[i] != frame:
		_shown[i] = frame
		RenderingServer.canvas_item_clear(ci)
		if frame.page != null:
			RenderingServer.canvas_item_add_texture_rect_region(ci,
				Rect2(Vector2(0.0, -frame.region.size.y * 0.5), frame.region.size), frame.page.get_rid(), frame.region)
	var size := frame.region.size if frame.region.size.x > 0.0 else Vector2.ONE
	RenderingServer.canvas_item_set_transform(ci, segment_transform(_from[i], _to[i], size))
	RenderingServer.canvas_item_set_modulate(ci, Color(1.0, 1.0, 1.0, anim.alpha_at(_t[i], false)))
	RenderingServer.canvas_item_set_visible(ci, true)


func _alloc() -> int:
	if not _free.is_empty():
		var j := _free[_free.size() - 1]
		_free.resize(_free.size() - 1)
		return j
	var ci := RenderingServer.canvas_item_create()
	RenderingServer.canvas_item_set_parent(ci, get_canvas_item())
	RenderingServer.canvas_item_set_visible(ci, false)
	_items.append(ci)
	_anim.append(null)
	_t.append(0.0)
	_from.append(Vector2.ZERO)
	_to.append(Vector2.ZERO)
	_active.append(0)
	_shown.append(null)
	return _items.size() - 1


func _release(i: int) -> void:
	_active[i] = 0
	_anim[i] = null
	_shown[i] = null
	RenderingServer.canvas_item_set_visible(_items[i], false)
	_free.append(i)
