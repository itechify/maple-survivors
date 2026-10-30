class_name GroundHazards
extends RefCounted
## The timed ground hazards bosses leave on the map (poison mist, MobSkill 131, spec #448 B4) as a pooled
## struct-of-arrays: a world-space box, the time it ends and what it does to a character standing in it. No nodes and no
## clock of its own; `step` reads the world's time. Cleared on map transfer and at the round's end (RunWorld).

## Effect of a hazard on a character inside it (the 131 level's `elemAttr`): ice (I) slows, poison (S) poisons.
const NONE := 0
const ICE := 1
const POISON := 2
const EPS := 1e-9

var active := PackedByteArray()
## Draw identity: increments on every spawn, including reuse of a slot between presentation frames.
var generation := PackedInt64Array()
## The hazard's box in world pixels (x, y of the top-left corner, and its size).
var x := PackedFloat32Array()
var y := PackedFloat32Array()
var w := PackedFloat32Array()
var h := PackedFloat32Array()
var born := PackedFloat64Array()
var until := PackedFloat64Array()
var effect := PackedByteArray()
## Poison HP per second (the level's `x`) for a poison hazard.
var strength := PackedFloat32Array()
var mob := PackedInt32Array()
var mob_id := PackedInt32Array()
## WZ path of the level's `affected` art, shown over the character when the hazard first takes hold of it.
var affected := PackedStringArray()
## WZ path of the level's `tile` node: its children "0".."N-1" are the mist's puff animations.
var tile_path := PackedStringArray()
var tile_count := PackedInt32Array()
## Hazards cast this round (counted at cast) and the seconds hazards have been alive (summed per tick, so one cleared
## early counts what it lived): kept by `clear`, read by the round record.
var cast_count := 0
var seconds := 0.0
var _free := PackedInt32Array()
var _hi := 0
var _count := 0


func _init(capacity: int = 4) -> void:
	_grow(maxi(1, capacity))


## Number of slots the pool holds (its size grows only when every slot is live).
func capacity() -> int:
	return active.size()


## Number of live hazards.
func active_count() -> int:
	return _count


## Element code of the 131 level's `elemAttr` ("I" ice, "S" poison, anything else none).
static func element_of(elem_attr: Variant) -> int:
	match String(elem_attr):
		"I":
			return ICE
		"S":
			return POISON
	return NONE


## Places a hazard from `spec`: rect (Rect2, world px), born, until, effect (ICE/POISON/NONE), strength, mob, mob_id,
## affected, tile_path and tile_count. Returns its slot.
func spawn(spec: Dictionary) -> int:
	if _free.is_empty():
		_grow(active.size() * 2)
	var slot := _free[_free.size() - 1]
	_free.resize(_free.size() - 1)
	var rect: Rect2 = spec.rect
	active[slot] = 1
	generation[slot] += 1
	x[slot] = rect.position.x
	y[slot] = rect.position.y
	w[slot] = rect.size.x
	h[slot] = rect.size.y
	born[slot] = float(spec.born)
	until[slot] = float(spec.until)
	effect[slot] = int(spec.get("effect", NONE))
	strength[slot] = float(spec.get("strength", 0.0))
	mob[slot] = int(spec.get("mob", -1))
	mob_id[slot] = int(spec.get("mob_id", 0))
	affected[slot] = String(spec.get("affected", ""))
	tile_path[slot] = String(spec.get("tile_path", ""))
	tile_count[slot] = int(spec.get("tile_count", 0))
	_count += 1
	_hi = maxi(_hi, slot + 1)
	cast_count += 1
	return slot


## The box of hazard `slot` in world pixels.
func rect(slot: int) -> Rect2:
	return Rect2(x[slot], y[slot], w[slot], h[slot])


## Whether hazard `slot` is live at `now`.
func is_live(slot: int, now: float) -> bool:
	return slot >= 0 and slot < _hi and active[slot] != 0 and now < until[slot] - EPS


## Ends every hazard at `world.time`, then applies each live one to the character standing in it (a Hidden character
## is skipped, as for boss skills aimed at it; "standing in it" is the character's body box overlapping the hazard's box): ice refreshes Slow, poison applies Poison.
func step(dt: float, world: RunWorld) -> void:
	var hidden := world.is_hidden()
	var body := world.player_box()
	for slot in _hi:
		if active[slot] == 0:
			continue
		if world.time >= until[slot] - EPS:
			_release(slot)
			continue
		seconds += dt
		if hidden or effect[slot] == NONE or not rect(slot).intersects(body):
			continue
		world.mob_skills.touch_hazard(world, int(effect[slot]), float(strength[slot]), int(mob[slot]),
			int(mob_id[slot]), String(affected[slot]))


## Removes every hazard (map transfer, the round's end); the cast and seconds counters stay.
func clear() -> void:
	for slot in _hi:
		if active[slot] != 0:
			_release(slot)


func _release(slot: int) -> void:
	active[slot] = 0
	_free.append(slot)
	_count -= 1


func _grow(capacity: int) -> void:
	var old := active.size()
	active.resize(capacity)
	generation.resize(capacity)
	x.resize(capacity)
	y.resize(capacity)
	w.resize(capacity)
	h.resize(capacity)
	born.resize(capacity)
	until.resize(capacity)
	effect.resize(capacity)
	strength.resize(capacity)
	mob.resize(capacity)
	mob_id.resize(capacity)
	affected.resize(capacity)
	tile_path.resize(capacity)
	tile_count.resize(capacity)
	# New slots join the free list in descending order, so the lowest index is reused first.
	for slot in range(capacity - 1, old - 1, -1):
		_free.append(slot)
