class_name ProjectileRenderer
extends Node2D
## Draws projectiles from ProjectileSystem-like arrays (docs/ARCHITECTURE.md 4.4.3): `active generation x y vx vy visual rotate`,
## with `visual_paths[visual]` the WZ path of the looping animation (e.g. Skill.wz/000.img/skill/0001000/level/1/ball).
##
## Each slot keeps its own animation clock (restarted on a new spawn generation or visual). WZ projectile
## art faces left: a shot moving right is mirrored. With `rotate` set for the slot, the sprite is also turned to the
## velocity direction (around its origin).

## Asset source; defaults to the "Assets" autoload.
var library: AssetLibrary

var _pool: SpritePool
var _age: PackedFloat32Array = []
var _was_active: PackedByteArray = []
var _was_visual: PackedInt32Array = []
var _was_generation := PackedInt64Array()
var _anims: Dictionary = {}


func _ready() -> void:
	_ensure_pool()


## Draws every active projectile; `dt` advances the per-slot animation clocks.
func update_from(proj: Object, visual_paths: Array, dt: float) -> void:
	_ensure_pool()
	var active: PackedByteArray = proj.active
	var xs: PackedFloat32Array = proj.x
	var ys: PackedFloat32Array = proj.y
	var vxs: PackedFloat32Array = proj.vx
	var vys: PackedFloat32Array = proj.vy
	var vis: PackedInt32Array = proj.visual
	var rot_v: Variant = proj.get("rotate")
	# Synthetic draw sources may omit identity; both production projectile pools always supply it.
	var generations: Variant = proj.get("generation")
	var n := active.size()
	_pool.ensure(n)
	if _age.size() < n:
		var old := _age.size()
		_age.resize(n)
		_was_active.resize(n)
		_was_visual.resize(n)
		_was_generation.resize(n)
		for i in range(old, n):
			_was_visual[i] = -1
	for i in n:
		if active[i] == 0:
			_was_active[i] = 0
			_pool.hide(i)
			continue
		var generation := int(generations[i]) if generations is PackedInt64Array else 0
		if _was_active[i] == 0 or _was_visual[i] != vis[i] or _was_generation[i] != generation:
			_age[i] = 0.0
			_was_active[i] = 1
			_was_visual[i] = vis[i]
			_was_generation[i] = generation
		else:
			_age[i] += dt
		var a := _anim(visual_paths, vis[i])
		if a == null:
			_pool.hide(i)
			continue
		var f := a.frame_at(_age[i], true)
		var flip := vxs[i] > 0.0
		var rot := 0.0
		if _rotates(rot_v, i):
			rot = rotation_for(Vector2(vxs[i], vys[i]))
		_pool.show(i, f, Vector2(roundf(xs[i]), roundf(ys[i])), flip, a.alpha_at(_age[i], true), rot)
	_pool.hide_from(n)


## Rotation (radians) that turns left-facing art (mirrored when moving right) to point along `v`.
static func rotation_for(v: Vector2) -> float:
	if v == Vector2.ZERO:
		return 0.0
	if v.x > 0.0:
		return v.angle()
	return (-v).angle()


## Number of slots drawn.
func visible_count() -> int:
	return _pool.shown_count() if _pool != null else 0


func _rotates(rot_v: Variant, i: int) -> bool:
	if rot_v is bool:
		return rot_v
	if rot_v is PackedByteArray or rot_v is PackedInt32Array or rot_v is Array:
		return i < rot_v.size() and bool(rot_v[i])
	return false


func _anim(paths: Array, v: int) -> SpriteAnim:
	if v < 0 or v >= paths.size():
		return null
	var p := str(paths[v])
	if not _anims.has(p):
		var lib := _lib()
		_anims[p] = lib.anim(p) if lib != null else null
	var a: SpriteAnim = _anims[p]
	return null if a == null or a.is_empty() else a


func _ensure_pool() -> void:
	if _pool == null:
		_pool = SpritePool.new(get_canvas_item())


func _lib() -> AssetLibrary:
	if library == null:
		library = AssetLibrary.get_default()
	return library
