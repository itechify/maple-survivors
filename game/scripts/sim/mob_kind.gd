class_name MobKind
extends RefCounted
## One mob type: canonical stats from `Mob.wz/<id>.img/info` (tier A, used as-is), the animation timing the sim needs,
## and survivor overrides from `data/survivor/mobs.json` (applied as multipliers, never edited into the WZ numbers).
##
## Overrides read (all optional): `name` (String.wz name, looked up outside the sim), `hp_mult`, `speed_mult`,
## `can_jump` (bool), `exp_item` (EXP pickup item id), `hit_time` (s).

## Move speed in px/s = (speed stat + 100) x this. tier C: HeavenClient's terminal mob speed;
## using the same conversion for canonical flySpeed is our tier C interpretation.
const SPEED_SCALE := 0.625
## Hit stun. tier C: HeavenClient (30 ticks x 8 ms).
const DEFAULT_HIT_TIME := 0.24
## Delay of a frame without `delay`. tier C: HeavenClient.
const DEFAULT_FRAME_DELAY := 0.1
## Death time when the img has no `die1`. tier C: ours.
const DEFAULT_DIE_TIME := 0.5
## Body box when no frame has lt/rb. tier C: ours.
const DEFAULT_HITBOX := Rect2(-20, -40, 40, 40)

var id := 0
var name := ""
var level := 1
## Canonical maxHP x hp_mult (rounded, at least 1).
var max_hp := 1
var exp := 0
var pad := 0
var pdd := 0
var mad := 0
var mdd := 0
var acc := 0
var eva := 0
## Canonical `speed` / `flySpeed` stats.
var speed_stat := 0
var fly_speed_stat := 0
## Horizontal speed in px/s: (stat + 100) x 0.625 x speed_mult (flySpeed for flying mobs when present).
var move_speed := 0.0
## Has a `jump` stance (or the override says so): may take NavGraph jump edges.
var can_jump := false
## Has a `fly` stance: ignores footholds.
var flies := false
## Body box relative to the feet when facing left (WZ default), from move/0 (else stand/0, fly/0) lt/rb.
var hitbox := DEFAULT_HITBOX
## Seconds of the death animation (sum of die1 delays) and of the hit stun.
var die_time := DEFAULT_DIE_TIME
var hit_time := DEFAULT_HIT_TIME
## Damage at or above this pushes the mob back.
var pushed := 1
var body_attack := false
var undead := false
var elem_attr := ""
## Survivor EXP pickup item id (0 = none set).
var exp_item := 0


## Builds a kind from a mob img root (cache JSON, `info/link` already followed by the loader).
static func from_wz(mob_img: Dictionary, p_id: int, overrides: Dictionary = {}) -> MobKind:
	var k := MobKind.new()
	var info: Dictionary = mob_img.get("info", {}) if mob_img.get("info") is Dictionary else {}
	k.id = p_id
	k.name = String(overrides.get("name", ""))
	k.level = int(info.get("level", 1))
	k.max_hp = maxi(1, int(round(float(info.get("maxHP", 1)) * float(overrides.get("hp_mult", 1.0)))))
	k.exp = int(info.get("exp", 0))
	k.pad = int(info.get("PADamage", 0))
	k.pdd = int(info.get("PDDamage", 0))
	k.mad = int(info.get("MADamage", 0))
	k.mdd = int(info.get("MDDamage", 0))
	k.acc = int(info.get("acc", 0))
	k.eva = int(info.get("eva", 0))
	k.speed_stat = int(info.get("speed", 0))
	k.fly_speed_stat = int(info.get("flySpeed", 0))
	k.pushed = int(info.get("pushed", 1))
	k.body_attack = int(info.get("bodyAttack", 0)) != 0
	k.undead = int(info.get("undead", 0)) != 0
	k.elem_attr = String(info.get("elemAttr", ""))
	k.flies = mob_img.get("fly") is Dictionary
	k.can_jump = bool(overrides.get("can_jump", mob_img.get("jump") is Dictionary))
	var stat := k.fly_speed_stat if k.flies and info.has("flySpeed") else k.speed_stat
	k.move_speed = maxf(0.0, (stat + 100) * SPEED_SCALE * float(overrides.get("speed_mult", 1.0)))
	k.hitbox = _hitbox(mob_img)
	k.die_time = stance_time(mob_img.get("die1"), DEFAULT_DIE_TIME)
	k.hit_time = float(overrides.get("hit_time", DEFAULT_HIT_TIME))
	k.exp_item = int(overrides.get("exp_item", 0))
	return k


## Total duration in seconds of a stance node: the sum of its numbered frames' delays (missing delay = 100 ms).
## Non-frame children (e.g. `zigzag`) are ignored; `fallback` when there is no frame.
static func stance_time(stance: Variant, fallback: float) -> float:
	if not (stance is Dictionary):
		return fallback
	var total := 0.0
	var frames := 0
	for key: String in stance:
		var fr: Variant = stance[key]
		if not key.is_valid_int() or not (fr is Dictionary):
			continue
		frames += 1
		var d: Variant = fr.get("delay")
		if typeof(d) == TYPE_FLOAT or typeof(d) == TYPE_INT:
			total += absf(float(d)) / 1000.0
		else:
			total += DEFAULT_FRAME_DELAY
	return total if frames > 0 else fallback


## Body box in world space for a mob at (x, y) facing -1 (left) or 1 (right, mirrored).
func hitbox_at(x: float, y: float, facing: int) -> Rect2:
	if facing > 0:
		return Rect2(x - hitbox.end.x, y + hitbox.position.y, hitbox.size.x, hitbox.size.y)
	return Rect2(x + hitbox.position.x, y + hitbox.position.y, hitbox.size.x, hitbox.size.y)


static func _hitbox(mob_img: Dictionary) -> Rect2:
	for stance_name: String in ["move", "stand", "fly"]:
		var st: Variant = mob_img.get(stance_name)
		if not (st is Dictionary):
			continue
		var fr: Variant = st.get("0")
		if not (fr is Dictionary):
			continue
		var lt: Variant = _vec(fr.get("lt"))
		var rb: Variant = _vec(fr.get("rb"))
		if lt != null and rb != null:
			return Rect2(lt, rb - lt).abs()
	return DEFAULT_HITBOX


static func _vec(v: Variant) -> Variant:
	if v is Dictionary and v.get("$v") is Array and v["$v"].size() >= 2:
		return Vector2(float(v["$v"][0]), float(v["$v"][1]))
	if v is Vector2:
		return v
	return null
