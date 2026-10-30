class_name FxRenderer
extends Node2D
## Pooled one-shot WZ animations (skill hits, LevelUp, JobChanged, the death tombstone) on RenderingServer items.
##
## `play("Effect.wz/BasicEff.img/LevelUp", pos)` shows the animation once with its WZ delays and a0/a1 alpha, anchored
## by origin at `pos` (mirrored when `flip`), optionally following a node (its position + `offset` every frame), and
## frees the slot when it ends (or holds the last frame with `hold`). `play_tomb(pos)` drops Effect.wz/Tomb.img/fall
## from TOMB_HEIGHT px above onto `pos`, then plays `land` and stays until cleared. With `behind` set, animations whose
## WZ `z` is negative (BasicEff.img/JobChanged) are forwarded to that renderer, placed before the character in the tree
## (the returned slot id then belongs to `behind`).
##
## The pooled canvas items are children of this node's own canvas item, which lives as long as the node: effects keep
## playing when the node moves between containers (remove_child/add_child, reparent()) and are freed with the node.

const TOMB_FALL := "Effect.wz/Tomb.img/fall"
const TOMB_LAND := "Effect.wz/Tomb.img/land"
## tier C: the tombstone starts this far above the character and lands after the fall animation's duration.
const TOMB_HEIGHT := 300.0

## Asset source; defaults to the "Assets" autoload.
var library: AssetLibrary
## Optional renderer placed behind the character: animations whose WZ `z` is negative (JobChanged) play there.
var behind: FxRenderer

var _pool: SpritePool
var _anim: Array = []
var _t: PackedFloat32Array = []
var _pos: PackedVector2Array = []
var _offset: PackedVector2Array = []
var _flip: PackedByteArray = []
var _rotation := PackedFloat32Array()
var _hold: PackedByteArray = []
var _active: PackedByteArray = []
var _follow: Array = []
## 0 = normal, 1 = tomb falling, 2 = tomb landed, 3 = repeating status art.
var _mode: PackedByteArray = []
var _repeat_left := PackedFloat32Array()
## Playback speed of each slot (1 = the WZ delays); see fit().
var _rate := PackedFloat32Array()
var _free: PackedInt32Array = []


func _ready() -> void:
	_ensure_pool()


## Plays the animation at a WZ path. Returns the slot id, or -1 when the animation is missing.
func play(path: String, pos: Vector2, flip: bool = false, follow: Node2D = null, offset: Vector2 = Vector2.ZERO,
		hold: bool = false, delay: float = 0.0) -> int:
	var lib := _lib()
	var a := lib.anim(path) if lib != null else null
	if a == null or a.is_empty():
		return -1
	return play_anim(a, pos, flip, follow, offset, hold, delay)


## Plays cast art after a presentation delay; the hidden pooled slot still follows its owner during the wait.
func play_delayed(path: String, delay: float, pos: Vector2, flip: bool = false, follow: Node2D = null,
		offset: Vector2 = Vector2.ZERO) -> int:
	return play(path, pos, flip, follow, offset, false, delay)


## Plays the animation at a WZ path as if it had started `start` seconds ago (Dragon Strike's pillars, whose WZ timing counts from
## the cast). Returns the slot id (of the `behind` renderer for a negative-z animation), or -1 when the animation is missing.
func play_from(path: String, pos: Vector2, flip: bool, start: float) -> int:
	var lib := _lib()
	var a := lib.anim(path) if lib != null else null
	if a == null or a.is_empty():
		return -1
	return play_anim(a, pos, flip, null, Vector2.ZERO, false, 0.0, start)


## Plays an already resolved animation (see play()).
func play_anim(a: SpriteAnim, pos: Vector2, flip: bool = false, follow: Node2D = null, offset: Vector2 = Vector2.ZERO,
		hold: bool = false, delay: float = 0.0, start: float = 0.0) -> int:
	if behind != null and behind != self and a.z != null and int(a.z) < 0:
		return behind.play_anim(a, pos, flip, follow, offset, hold, delay, start)
	_ensure_pool()
	var i := _alloc()
	_anim[i] = a
	_t[i] = start - maxf(0.0, delay)
	_pos[i] = pos
	_offset[i] = offset
	_flip[i] = 1 if flip else 0
	_rotation[i] = 0.0
	_hold[i] = 1 if hold else 0
	_follow[i] = weakref(follow) if follow != null else null
	_mode[i] = 0
	_rate[i] = 1.0
	_active[i] = 1
	_draw_slot(i)
	return i


## Drops the tombstone onto `pos` (fall, then land, then stays). Returns the slot id or -1.
func play_tomb(pos: Vector2) -> int:
	var lib := _lib()
	var a := lib.anim(TOMB_FALL) if lib != null else null
	if a == null or a.is_empty():
		return -1
	var i := play_anim(a, pos, false, null, Vector2.ZERO, true)
	_mode[i] = 1
	_draw_slot(i)
	return i


## Repeats an animation in a pooled slot for seconds; INF lets a sim-owned status stop it explicitly.
func play_repeating(path: String, pos: Vector2, seconds: float, flip: bool = false, follow: Node2D = null,
		offset: Vector2 = Vector2.ZERO) -> int:
	var lib := _lib()
	var anim := lib.anim(path) if lib != null else null
	if anim == null or anim.is_empty() or seconds <= 0.0:
		return -1
	if behind != null and behind != self and anim.z != null and int(anim.z) < 0:
		return behind.play_repeating(path,pos,seconds,flip,follow,offset)
	var slot := play_anim(anim,pos,flip,follow,offset)
	_mode[slot] = 3
	_repeat_left[slot] = seconds
	return slot


## Speeds slot `i` up or down so that one pass of its animation takes `seconds` (the burst skills' wind-up art).
func fit(i: int, seconds: float) -> void:
	if i >= 0 and i < _active.size() and _active[i] == 1 and seconds > 0.0 and _anim[i] != null:
		_rate[i] = maxf(0.01, float((_anim[i] as SpriteAnim).total) / seconds)


## Playback speed of slot `i` (1 unless fit() changed it).
func rate_of(i: int) -> float:
	return _rate[i] if i >= 0 and i < _rate.size() else 1.0


## Stops one effect.
func stop(i: int) -> void:
	if i >= 0 and i < _active.size() and _active[i] == 1:
		_release(i)


## Moves and optionally turns an active pooled effect at a simulation-owned anchor, without an entity Node.
func place(i: int, pos: Vector2, rotation: float = 0.0) -> void:
	if i >= 0 and i < _active.size() and _active[i] == 1:
		_pos[i] = pos
		_rotation[i] = rotation
		_draw_slot(i)


## Stops every effect.
func clear() -> void:
	for i in _active.size():
		if _active[i] == 1:
			_release(i)


## Number of playing (or held) effects.
func active_count() -> int:
	var n := 0
	for a in _active:
		n += a
	return n


func _process(delta: float) -> void:
	advance(delta)


## Advances every effect by `dt` seconds.
func advance(dt: float) -> void:
	for i in _active.size():
		if _active[i] == 0:
			continue
		if _mode[i] == 3:
			_repeat_left[i] -= dt
			if _repeat_left[i] <= 1e-9:
				_release(i)
				continue
		_t[i] += dt * _rate[i]
		var a: SpriteAnim = _anim[i]
		if _mode[i] == 1 and _t[i] >= a.total:
			var land := _lib().anim(TOMB_LAND) if _lib() != null else null
			if land != null and not land.is_empty():
				_anim[i] = land
			_t[i] = 0.0
			_mode[i] = 2
		elif _mode[i] == 0 and _hold[i] == 0 and a.finished(_t[i]):
			_release(i)
			continue
		_draw_slot(i)


## Current anchor of a slot (follow target + offset, or the fixed position; tomb fall included).
func slot_position(i: int) -> Vector2:
	var p := _pos[i]
	var wr: Variant = _follow[i]
	if wr is WeakRef:
		var n: Variant = (wr as WeakRef).get_ref()
		if n is Node2D and (n as Node2D).is_inside_tree():
			p = to_local((n as Node2D).global_position) + _offset[i]
	if _mode[i] == 1:
		var a: SpriteAnim = _anim[i]
		var k := clampf(_t[i] / maxf(a.total, 0.001), 0.0, 1.0)
		p.y -= TOMB_HEIGHT * (1.0 - k * k)
	return p


func _draw_slot(i: int) -> void:
	_ensure_pool()
	_pool.ensure(i + 1)
	if _t[i] < 0.0:
		_pool.hide(i)
		return
	var a: SpriteAnim = _anim[i]
	var loop := _mode[i] in [1,3]
	var f := a.frame_at(_t[i], loop)
	var pos := slot_position(i).round()
	_pool.show(i, f, pos, _flip[i] == 1, a.alpha_at(_t[i], loop), _rotation[i])


func _alloc() -> int:
	_ensure_pool()
	if not _free.is_empty():
		var j := _free[_free.size() - 1]
		_free.resize(_free.size() - 1)
		_pool.ensure(j + 1)
		return j
	var i := _active.size()
	_anim.append(null)
	_t.append(0.0)
	_pos.append(Vector2.ZERO)
	_offset.append(Vector2.ZERO)
	_flip.append(0)
	_rotation.append(0.0)
	_hold.append(0)
	_active.append(0)
	_follow.append(null)
	_mode.append(0)
	_repeat_left.append(0.0)
	_rate.append(1.0)
	_pool.ensure(i + 1)
	return i


func _release(i: int) -> void:
	_active[i] = 0
	_anim[i] = null
	_follow[i] = null
	_pool.hide(i)
	_free.append(i)


func _ensure_pool() -> void:
	if _pool == null:
		_pool = SpritePool.new(get_canvas_item())


func _lib() -> AssetLibrary:
	if library == null:
		library = AssetLibrary.get_default()
	return library
