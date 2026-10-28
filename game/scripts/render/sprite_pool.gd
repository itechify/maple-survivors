class_name SpritePool
extends RefCounted
## A growable pool of RenderingServer canvas items, one per slot, each showing one SpriteFrame (no Nodes per sprite).
##
## A slot's item is re-recorded only when its frame changes; position, mirroring, rotation and alpha are item
## transforms/modulates, so a moving swarm costs two cheap RenderingServer calls per sprite per frame. Mirroring is a
## scale of -1 around the anchor, so mirrored sprites stay on whole pixels. Items are children of `parent` (a
## CanvasItem RID) and draw in slot order. Owners pass their own get_canvas_item(): that RID exists from the node's
## construction to its deletion (not just while it is in the tree), so a pool survives the owner being reparented and
## is freed when the owner frees it (NOTIFICATION_PREDELETE below) - owners must not free it in _exit_tree.

var parent: RID
var items: Array[RID] = []

var _frames: Array = []
var _pos: PackedVector2Array = []
var _flip: PackedByteArray = []
var _rot: PackedFloat32Array = []
var _alpha: PackedFloat32Array = []
var _tint := PackedColorArray()
var _shown: PackedByteArray = []


func _init(p_parent: RID = RID()) -> void:
	parent = p_parent


func _notification(what: int) -> void:
	# Inline: a RefCounted cannot call its own script methods while being deleted.
	if what == NOTIFICATION_PREDELETE:
		for ci in items:
			RenderingServer.free_rid(ci)
		items.clear()


## Number of slots allocated.
func size() -> int:
	return items.size()


## Grows the pool to at least `n` slots (new slots start hidden).
func ensure(n: int) -> void:
	var old := items.size()
	if n <= old:
		return
	items.resize(n)
	_frames.resize(n)
	_pos.resize(n)
	_flip.resize(n)
	_rot.resize(n)
	_alpha.resize(n)
	_tint.resize(n)
	_shown.resize(n)
	for i in range(old, n):
		var ci := RenderingServer.canvas_item_create()
		RenderingServer.canvas_item_set_parent(ci, parent)
		RenderingServer.canvas_item_set_visible(ci, false)
		items[i] = ci
		_frames[i] = null
		_pos[i] = Vector2(INF, INF)
		_flip[i] = 0
		_rot[i] = 0.0
		_alpha[i] = -1.0
		_shown[i] = 0


## Shows slot `i` with frame `f` anchored at `pos` (whole pixels expected), mirrored when `flip`.
func show(i: int, f: SpriteFrame, pos: Vector2, flip: bool, alpha: float = 1.0, rot: float = 0.0,
		tint: Color = Color.WHITE) -> void:
	var ci := items[i]
	if _frames[i] != f:
		_frames[i] = f
		RenderingServer.canvas_item_clear(ci)
		if f.page != null:
			RenderingServer.canvas_item_add_texture_rect_region(ci, Rect2(-f.origin, f.region.size), f.page.get_rid(),
				f.region)
	var fl := 1 if flip else 0
	if _pos[i] != pos or _flip[i] != fl or _rot[i] != rot:
		_pos[i] = pos
		_flip[i] = fl
		_rot[i] = rot
		RenderingServer.canvas_item_set_transform(ci, Transform2D(rot, Vector2(-1.0 if flip else 1.0, 1.0), 0.0, pos))
	if _alpha[i] != alpha or _tint[i] != tint:
		_alpha[i] = alpha
		_tint[i] = tint
		RenderingServer.canvas_item_set_modulate(ci, Color(tint, tint.a * alpha))
	if _shown[i] == 0:
		_shown[i] = 1
		RenderingServer.canvas_item_set_visible(ci, true)


## Hides slot `i`.
func hide(i: int) -> void:
	if i < items.size() and _shown[i] == 1:
		_shown[i] = 0
		RenderingServer.canvas_item_set_visible(items[i], false)


## The tint slot `i` was last shown with (white before its first show).
func tint_of(i: int) -> Color:
	return _tint[i] if i < _tint.size() else Color.WHITE


## True when slot `i` is visible.
func is_shown(i: int) -> bool:
	return i < items.size() and _shown[i] == 1


## Number of visible slots.
func shown_count() -> int:
	var n := 0
	for s in _shown:
		n += s
	return n


## Hides every slot from `from` on.
func hide_from(from: int) -> void:
	for i in range(from, items.size()):
		hide(i)


## Frees every canvas item.
func free_all() -> void:
	for ci in items:
		RenderingServer.free_rid(ci)
	items.clear()
	_frames.clear()
	_pos.clear()
	_flip.clear()
	_rot.clear()
	_alpha.clear()
	_tint.clear()
	_shown.clear()
