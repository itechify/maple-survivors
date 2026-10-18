class_name MobProjectileSystem
extends RefCounted
## Monster balls as pooled struct-of-arrays; swept player collision resolves through RunWorld.take_hit.

## tier C: projectile contact radius when WZ ball art has no collision box; survivor data may override it.
const DEFAULT_RADIUS := 8.0
var active := PackedByteArray()
var x := PackedFloat32Array()
var y := PackedFloat32Array()
var vx := PackedFloat32Array()
var vy := PackedFloat32Array()
var visual := PackedInt32Array()
var rotate := PackedByteArray()
var range_left := PackedFloat32Array()
var radius := PackedFloat32Array()
var mob := PackedInt32Array()
var mob_id := PackedInt32Array()
var damage := PackedFloat32Array()
var multiplier := PackedFloat32Array()
var accuracy := PackedFloat32Array()
var magic := PackedByteArray()
var element := PackedStringArray()
var hit_visual := PackedStringArray()
var source_pos := PackedVector2Array()
## 1 for an ordinary (non-boss) mob's ball: its hit is a "mob_attack" (elite-scaled like contact), not a boss "projectile".
var ordinary := PackedByteArray()
var elite := PackedByteArray()
var _free := PackedInt32Array()
var _hi := 0
var _count := 0


func _init(capacity: int = 32) -> void:
	_grow(maxi(1, capacity))


## Number of balls still in flight.
func active_count() -> int:
	return _count


## Adds a ball spec containing pos/velocity/range and its captured canonical damage/source metadata.
func spawn(spec: Dictionary) -> int:
	if _free.is_empty():
		_grow(active.size() * 2)
	var slot := _free[_free.size() - 1]
	_free.resize(_free.size() - 1)
	active[slot] = 1
	x[slot] = spec.pos.x
	y[slot] = spec.pos.y
	vx[slot] = spec.velocity.x
	vy[slot] = spec.velocity.y
	visual[slot] = int(spec.visual)
	range_left[slot] = float(spec.range)
	radius[slot] = float(spec.get("radius", DEFAULT_RADIUS))
	mob[slot] = int(spec.mob)
	mob_id[slot] = int(spec.mob_id)
	damage[slot] = float(spec.damage)
	multiplier[slot] = float(spec.multiplier)
	accuracy[slot] = float(spec.accuracy)
	magic[slot] = 1 if bool(spec.magic) else 0
	element[slot] = String(spec.element)
	hit_visual[slot] = String(spec.hit)
	source_pos[slot] = spec.source_pos
	ordinary[slot] = 1 if bool(spec.get("ordinary", false)) else 0
	elite[slot] = 1 if bool(spec.get("elite", false)) else 0
	_count += 1
	_hi = maxi(_hi, slot + 1)
	return slot


## Advances flight within its remaining range; the first swept body contact consumes the ball even on MISS, except
## that an ordinary ball is not consumed while the player's hit window blocks it (boss balls ignore the window).
func step(dt: float, world: RunWorld) -> void:
	for slot in _hi:
		if active[slot] == 0:
			continue
		var from := Vector2(x[slot], y[slot])
		var velocity := Vector2(vx[slot], vy[slot])
		var distance := minf(velocity.length() * dt, range_left[slot])
		var to := from + velocity.normalized() * distance
		var box := Rect2(world.player.pos + world.body.position, world.body.size).grow(radius[slot])
		var enter := ProjectileSystem.segment_enter(from.x, from.y, to.x, to.y, box)
		x[slot] = to.x
		y[slot] = to.y
		range_left[slot] = maxf(0.0, range_left[slot] - distance)
		var source := {}
		if enter >= 0.0:
			source = {"mob": mob[slot], "mob_id": mob_id[slot], "accuracy": accuracy[slot],
				"dmg_mult": multiplier[slot], "boss": true, "source_kind": "projectile"}
			if ordinary[slot] != 0:
				source.boss = false
				source.source_kind = "mob_attack"
				source["elite"] = elite[slot] != 0
		# tier C (spec #88): an ordinary ball the hit window turns away is neither a hit nor used up; it flies on and
		# can still land once the window ends (also from inside the body box: the sweep then enters at t = 0).
		if enter >= 0.0 and not world.hit_window_blocks(source):
			world.take_hit(damage[slot], magic[slot] != 0, element[slot], source_pos[slot], source)
			world.emit("mob_projectile_hit", {"proj": slot, "mob": mob[slot], "mob_id": mob_id[slot],
				"pos": from.lerp(to, enter), "hit": hit_visual[slot], "facing": 1 if vx[slot] > 0.0 else -1,
				"time": world.time})
			despawn(slot)
		elif range_left[slot] <= 1e-6:
			despawn(slot)


## Returns a projectile slot to the pool.
func despawn(slot: int) -> void:
	if slot < 0 or slot >= active.size() or active[slot] == 0:
		return
	active[slot] = 0
	_free.append(slot)
	_count -= 1


func _grow(size: int) -> void:
	var old := active.size()
	for property: String in ["active", "x", "y", "vx", "vy", "visual", "rotate", "range_left", "radius",
		"mob", "mob_id", "damage", "multiplier", "accuracy", "magic", "element", "hit_visual", "source_pos",
		"ordinary", "elite"]:
		var array: Variant = get(property)
		array.resize(size)
		set(property, array)
	for slot in range(size - 1, old - 1, -1):
		_free.append(slot)
