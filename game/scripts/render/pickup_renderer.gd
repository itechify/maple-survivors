class_name PickupRenderer
extends Node2D
## Draws EXP drops from PickupSystem-like arrays (docs/ARCHITECTURE.md 4.4.3): `active x y item_id`, using the item's
## Item.wz/<Type>/<id/10000>.img/<8-digit id>/info/iconRaw, with a gentle bob.
##
## Anchor: the icon is centred on x with its bottom on y (the drop rests on the ground). The canvas origin of iconRaw is
## an inventory-slot anchor (e.g. (-4, 27)), so it is not used here (tier C, our choice). Bob: BOB_PX up and down over
## BOB_PERIOD seconds, phase-shifted per slot (tier C).

## tier C: bob amplitude in px and period in seconds.
const BOB_PX := 2.0
const BOB_PERIOD := 1.2

## Asset source; defaults to the "Assets" autoload.
var library: AssetLibrary
## Seconds since creation (drives the bob).
var time := 0.0

var _pool: SpritePool
var _icons: Dictionary = {}


func _ready() -> void:
	_ensure_pool()


## Draws every active pickup; `dt` advances the bob.
func update_from(pickups: Object, dt: float) -> void:
	_ensure_pool()
	time += dt
	var active: PackedByteArray = pickups.active
	var xs: PackedFloat32Array = pickups.x
	var ys: PackedFloat32Array = pickups.y
	var ids: PackedInt32Array = pickups.item_id
	var n := active.size()
	_pool.ensure(n)
	for i in n:
		if active[i] == 0:
			_pool.hide(i)
			continue
		var f := icon(ids[i])
		if f == null:
			_pool.hide(i)
			continue
		var p := Vector2(roundf(xs[i]), roundf(ys[i]) + bob_offset(time, i))
		_pool.show(i, f, p + anchor_offset(f), false)
	_pool.hide_from(n)


## Vertical bob (whole px, <= 0 = up) of slot `i` at time `t`.
static func bob_offset(t: float, i: int) -> float:
	return roundf(-BOB_PX * (0.5 + 0.5 * sin(TAU * t / BOB_PERIOD + float(i) * 0.7)))


## Offset from the drop point to where the frame's origin must go so the icon is centred with its bottom on the point.
static func anchor_offset(f: SpriteFrame) -> Vector2:
	var s := f.region.size
	return Vector2(f.origin.x - floorf(s.x * 0.5), f.origin.y - s.y)


## The icon frame of an item (cached; null when missing).
func icon(item_id: int) -> SpriteFrame:
	if not _icons.has(item_id):
		var lib := _lib()
		_icons[item_id] = lib.frame(AssetLibrary.item_icon_path(item_id)) if lib != null else null
	return _icons[item_id]


## Number of slots drawn.
func visible_count() -> int:
	return _pool.shown_count() if _pool != null else 0


func _ensure_pool() -> void:
	if _pool == null:
		_pool = SpritePool.new(get_canvas_item())


func _lib() -> AssetLibrary:
	if library == null:
		library = AssetLibrary.get_default()
	return library
