class_name MobReflect
extends RefCounted
## Per-slot timed boss Reflect state of MobSkill 143 (physical hits), 144 (magic hits) and 145 (both), and the damage a
## reflected hit does to the character (docs/GAME_DESIGN.md "Constants and provenance", spec #448 B6, ticket #461).
## Plain data: no files, nodes or RNG. Every array is indexed by mob slot and follows the swarm's resize / reset / move
## hooks, like MobBuffs.

## Which damage types a reflect covers (bit mask).
const PHYSICAL := 1
const MAGIC := 2
## tier C (#461): balance.mob_skills.reflect {damage_mult, cap_mult, rate} defaults. `damage_mult` is k and `cap_mult` is c
## in `min(damage x x/10000 x k, y x c)`; `rate` is the seconds between two reflects that hurt the character.
const DEFAULT_DAMAGE_MULT := 1.0
const DEFAULT_CAP_MULT := 0.03
const DEFAULT_RATE := 0.5

var damage_mult := DEFAULT_DAMAGE_MULT
var cap_mult := DEFAULT_CAP_MULT
var rate := DEFAULT_RATE

var _until := PackedFloat64Array()
var _mask := PackedByteArray()
## tier C: x is read as basis points (10000 = 100% of the hit), y as the cap of one reflect.
var _fraction := PackedFloat32Array()
var _cap := PackedFloat32Array()
var _visual := PackedStringArray()
var _skill := PackedInt32Array()
## Sim time of the last reflect that was allowed to hurt the character.
var _last := PackedFloat64Array()
## The latest end time ever set: lets a caller skip all work while no reflect can be live.
var _latest := 0.0


func _init(rules: Dictionary = {}) -> void:
	damage_mult = float(rules.get("damage_mult", DEFAULT_DAMAGE_MULT))
	cap_mult = float(rules.get("cap_mult", DEFAULT_CAP_MULT))
	rate = float(rules.get("rate", DEFAULT_RATE))


## Grows the pools without changing existing reflects.
func resize(capacity: int) -> void:
	var old := _until.size()
	_until.resize(capacity)
	_mask.resize(capacity)
	_fraction.resize(capacity)
	_cap.resize(capacity)
	_visual.resize(capacity)
	_skill.resize(capacity)
	_last.resize(capacity)
	for slot in range(old, capacity):
		_last[slot] = -INF


## A new mob in a reused slot starts clean.
func reset_slot(slot: int) -> void:
	_until[slot] = 0
	_mask[slot] = 0
	_fraction[slot] = 0
	_cap[slot] = 0
	_visual[slot] = ""
	_skill[slot] = 0
	_last[slot] = -INF


## Carries the reflect of `from` to `to` (a relocation) and cleans `from`.
func move_slot(from: int, to: int) -> void:
	if from == to:
		return
	_until[to] = _until[from]
	_mask[to] = _mask[from]
	_fraction[to] = _fraction[from]
	_cap[to] = _cap[from]
	_visual[to] = _visual[from]
	_skill[to] = _skill[from]
	_last[to] = _last[from]
	reset_slot(from)


## The damage types MobSkill `id` reflects: 143 physical, 144 magic, 145 both.
static func mask_of(id: int) -> int:
	return PHYSICAL if id == 143 else (MAGIC if id == 144 else PHYSICAL | MAGIC)


## Reflect `id` on `slot` until `until` with the cast level's `x` (basis points) and `y` (cap); a recast replaces it.
func start(slot: int, id: int, x: float, y: float, until: float, visual: String) -> void:
	_until[slot] = until
	_mask[slot] = mask_of(id)
	_fraction[slot] = x / 10000.0
	_cap[slot] = y
	_visual[slot] = visual
	_skill[slot] = id
	_latest = maxf(_latest, until)


## Whether any reflect may be live at `now` (false means every slot is free of it).
func any_active(now: float) -> bool:
	return now < _latest - 1e-9


## Whether `slot` reflects hits of the given damage type at `now`.
func reflects(slot: int, magic: bool, now: float) -> bool:
	if slot < 0 or slot >= _until.size() or now >= _until[slot] - 1e-9:
		return false
	return (int(_mask[slot]) & (MAGIC if magic else PHYSICAL)) != 0


## Whether `slot` reflects anything at `now`.
func active(slot: int, now: float) -> bool:
	return slot >= 0 and slot < _until.size() and now < _until[slot] - 1e-9


## Resolves a hit of `damage` that `slot` reflects: -1 when it does not reflect that type now, else the whole HP the
## character loses, `min(damage x x/10000 x k, y x c)`, or 0 when the last reflect that hurt was less than `rate` s ago.
func hit(slot: int, magic: bool, damage: float, now: float) -> int:
	if not reflects(slot, magic, now):
		return -1
	if now < _last[slot] + rate - 1e-9:
		return 0
	_last[slot] = now
	var amount := minf(damage * _fraction[slot] * damage_mult, _cap[slot] * cap_mult)
	# tier C: a reflect of any positive damage costs at least 1 HP, so a weak hit is never reflected for free.
	return maxi(1, roundi(amount)) if amount > 0.0 else 0


## Detached presentation state of an active reflect ({skill_id, remaining, visual, physical, magic}), empty otherwise.
func state(slot: int, now: float) -> Dictionary:
	if not active(slot, now):
		return {}
	return {"skill_id": _skill[slot], "remaining": _until[slot] - now, "visual": _visual[slot],
		"physical": (int(_mask[slot]) & PHYSICAL) != 0, "magic": (int(_mask[slot]) & MAGIC) != 0}
