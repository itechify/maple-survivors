class_name MobAttacks
extends RefCounted
## Canonical Mob.wz attacks (`attackN`: area 0, targeted direct 1, ball 2 and, for scheduled bosses only, the
## area-warning columns 3 and 4) for every mob that lists them
## (docs/ARCHITECTURE.md 4.4.1, GLOSSARY "Mob attack"). The static half is the windup/impact code BossAttacks shares:
## admission against the canonical range, the pending windup, effect/impact/hit phases at effectAfter/attackAfter and
## the hit through RunWorld.take_hit. The instance half runs ordinary (non-boss) mobs: per-slot waits in packed arrays,
## a pending windup per slot (checked against the swarm identity), `mob_attack` events and `source_kind`
## "mob_attack" hits, so #88 can route them apart from boss "attack"/"projectile" hits. Damage is the canonical
## MADamage/PADamage, unscaled like contact damage, times balance.mob_attacks' optional per-mob dmg_mult.

## tier C (#460): the dedicated RNG stream (RunWorld.area_rng, id 20) that picks which columns of an area-warning
## attack strike; no other roll shares it.
const AREA_STREAM := 20
## tier C: ordinary-mob attack interval when balance.mob_attacks has neither a per-mob nor a default value.
const DEFAULT_INTERVAL := 5.0
## tier C: the golden-ratio fraction that staggers each mob's first wait (see first_wait).
const STAGGER_STEP := 0.6180339887498949
## Float tolerance for sim-time comparisons (waits and windup timestamps); numeric, not a gameplay value.
const EPS := 1e-6

var _rules: Dictionary = {}
## Per kind index: 1 when ordinary copies of it may attack (it lists a type 0/1/2 attackN and is no scheduled boss).
var _kind_attacks := PackedByteArray()
## Per kind index: its attack stance names in canonical order (attack1, attack2, ...).
var _kind_names: Array[PackedStringArray] = []
var _kind_interval := PackedFloat64Array()
var _kind_mult := PackedFloat64Array()
var _any := false
## Per slot: seconds of eligible (fully visible, on-screen) time left before the next attack may start; NAN = unset.
var _wait := PackedFloat64Array()
## slot -> pending windup (the shared pending shape plus "identity").
var _pending := {}


func _init(world: RunWorld = null) -> void:
	if world == null:
		return
	_rules = world.balance.get("mob_attacks", {})
	var boss_ids := boss_kind_ids(world)
	for k in world.mob_kinds.size():
		var kind: MobKind = world.mob_kinds[k]
		var names := attack_names(world.mob_img(kind.id))
		# Scheduled-boss kinds attack through BossAttacks; slots are checked again with world.mob_boss.
		var ok := not names.is_empty() and not boss_ids.has(kind.id)
		_kind_attacks.append(1 if ok else 0)
		_kind_names.append(names)
		var entry: Dictionary = _rules.get("mobs", {}).get(str(kind.id), {})
		_kind_interval.append(float(entry.get("interval", _rules.get("default_interval", DEFAULT_INTERVAL))))
		_kind_mult.append(float(entry.get("dmg_mult", 1.0)))
		_any = _any or ok


## The `attackN` stances of a Mob.wz img whose info type is 0, 1 or 2, in canonical (numeric) order.
static func attack_names(img: Dictionary) -> PackedStringArray:
	var numbers := PackedInt32Array()
	for key: Variant in img:
		var name := String(key)
		if name.begins_with("attack") and name.substr(6).is_valid_int():
			var info: Variant = img[key].get("info", {}) if img[key] is Dictionary else {}
			if info is Dictionary and int(info.get("type", -1)) in [0, 1, 2]:
				numbers.append(int(name.substr(6)))
	numbers.sort()
	var out := PackedStringArray()
	for n in numbers:
		out.append("attack%d" % n)
	return out


## tier C: a mob's first wait is 50-100% of its interval, by the golden-ratio fraction of its swarm identity, so mobs
## spawned on one tick (consecutive identities) spread evenly over that half interval (distinct values; a burst larger
## than about interval x 60 / 2 mobs must still share fixed ticks). Waits count only while the mob can act on screen,
## so this staggers mobs that walk into view together as well; it guarantees nothing for mobs that already waited.
static func first_wait(interval: float, identity: int) -> float:
	return interval * (0.5 + 0.5 * fposmod(float(identity) * STAGGER_STEP, 1.0))


## Grows the per-slot waits with the swarm; new slots are unset.
func resize(capacity: int) -> void:
	var old := _wait.size()
	if old >= capacity:
		return
	_wait.resize(capacity)
	for slot in range(old, capacity):
		_wait[slot] = NAN


## A new mob in the slot starts with its own first wait and no windup.
func reset_slot(slot: int) -> void:
	if slot < _wait.size():
		_wait[slot] = NAN
	_pending.erase(slot)


## A relocated mob keeps its wait but loses a windup in progress (its captured box no longer matches).
func move_slot(from: int, to: int) -> void:
	_pending.erase(from)
	_pending.erase(to)
	if from == to or from >= _wait.size() or to >= _wait.size():
		return
	_wait[to] = _wait[from]
	_wait[from] = NAN


## Seconds of eligible time until slot's next attack may start (NAN before its first eligible tick).
func wait_left(slot: int) -> float:
	return _wait[slot] if slot < _wait.size() else NAN


## Cancels an ordinary mob's pending attack before impact, releasing its stance but preserving its next-attack wait.
## An attack already at impact (including a launched ball) is never undone.
func interrupt(world: RunWorld, slot: int) -> void:
	var pending: Dictionary = _pending.get(slot, {})
	if pending.is_empty() or bool(pending.impact_done) or not world.swarm.is_live(slot) \
			or world.swarm.identity[slot] != int(pending.identity):
		return
	_pending.erase(slot)
	world.mob_actions.reset_slot(slot)


## Advances pending windups, then starts the next attack of every ordinary mob that is ready, grounded, fully
## visible, on screen, not busy and has the character in an attack's canonical range.
func step(world: RunWorld, dt: float) -> void:
	if not _any:
		return
	var swarm := world.swarm
	for slot: int in _pending.keys():
		var pending: Dictionary = _pending[slot]
		if not swarm.is_live(slot) or swarm.identity[slot] != int(pending.identity):
			_pending.erase(slot)
			continue
		if service(pending, world):
			_pending.erase(slot)
	# Hidden (#194): no ordinary mob starts an attack (waits do not run down either); windups already begun still play
	# out their phases but land nothing (_impact).
	if world.state != RunWorld.PLAYING or world.is_hidden():
		return
	var now := world.time
	var view := world.view
	# Hot loop over every slot: packed arrays read through locals, cheapest rejections first.
	var active := swarm.active
	var kinds := swarm.kind
	var boss := world.mob_boss
	var alpha := swarm.alpha
	var status := swarm.status_left
	var xs := swarm.x
	var ys := swarm.y
	var view_pos := view.position
	var view_end := view.end
	for slot in swarm.capacity():
		if active[slot] == 0 or _kind_attacks[kinds[slot]] == 0 or boss[slot] >= 0:
			continue
		# MobSwarm.can_act and Rect2.has_point(swarm.pos(slot)), inlined: this loop runs for every attacker on screen.
		if alpha[slot] < 1.0 or status[slot * MobSwarm.STATUS_COUNT + MobSwarm.FREEZE] > 0.0 \
				or status[slot * MobSwarm.STATUS_COUNT + MobSwarm.STUN] > 0.0:
			continue
		if xs[slot] < view_pos.x or ys[slot] < view_pos.y or xs[slot] >= view_end.x or ys[slot] >= view_end.y:
			continue
		var k := swarm.kind[slot]
		var interval := _kind_interval[k]
		var wait := _wait[slot]
		if is_nan(wait):
			wait = first_wait(interval, swarm.identity[slot])
		wait = maxf(0.0, wait - dt)
		_wait[slot] = wait
		if wait > EPS or _pending.has(slot) or swarm.fh[slot] < 0 or world.mob_actions.busy(slot, now):
			continue
		var img := world.mob_img(swarm.mob_kind(slot).id)
		for attack: String in _kind_names[k]:
			var pending := plan(world, slot, img, attack, -1, _kind_mult[k])
			if pending.is_empty():
				continue
			pending["identity"] = swarm.identity[slot]
			pending["elite"] = world.mob_elite[slot] != 0
			world.mob_actions.begin(slot, attack, float(pending.duration), int(pending.facing), now)
			_wait[slot] = interval
			_pending[slot] = pending
			emit(pending, "start", world)
			if service(pending, world):
				_pending.erase(slot)
			break


## The pending windup of `attack` by the mob in `slot` when the character is admitted by its canonical range, else {}.
## `boss_index` >= 0 marks a scheduled boss (boss_attack events, "attack"/"projectile" hits).
static func plan(world: RunWorld, slot: int, img: Dictionary, attack: String, boss_index: int,
		dmg_mult: float) -> Dictionary:
	var swarm := world.swarm
	var stance: Dictionary = img.get(attack, {})
	var info: Dictionary = stance.get("info", {})
	var type := int(info.get("type", -1))
	if type not in [0, 1, 2, 3, 4] or world.is_hidden():
		return {}
	var id := swarm.mob_kind(slot).id
	var pos := swarm.pos(slot)
	var facing := 1 if world.player.pos.x > pos.x else -1
	var area := area_at(info.get("range", {}), pos, facing)
	var range_data: Dictionary = info.get("range", {})
	# tier C (#460): types 3 and 4 share one path; the strip of columns is admitted when the character's body touches it.
	var strip: Array[Rect2] = []
	if type >= 3:
		strip = area_columns(range_data, pos, facing)
		if strip.is_empty():
			return {}
		area = strip[0]
		for column in strip:
			area = area.merge(column)
		if not area.intersects(world.player_box(), true):
			return {}
	var travel := float(range_data.get("r", 0.0))
	var offset := vec(range_data.get("sp", {}))
	if facing > 0:
		offset.x = -offset.x
	if type == 2:
		area = Rect2(pos - Vector2.ONE * travel, Vector2.ONE * travel * 2.0)
	# tier C: type 1 admits the character's body centre within r of the mirrored sp, then locks it.
	# Later-client CMob descriptions suggest targeted direct damage; v83 admission details are unverified.
	if type == 1 and world.player_body_center().distance_to(pos + offset) > travel:
		return {}
	if (type == 0 and not area.intersects(world.player_box(), true)) \
			or (type == 2 and world.player.pos.distance_to(pos) > travel):
		return {}
	var now := world.time
	var after := maxf(0.0, float(info.get("attackAfter", 0.0)) / 1000.0)
	var effect_after := maxf(0.0, float(info.get("effectAfter", 0.0)) / 1000.0)
	var magic := int(info.get("magic", 0)) != 0 or (info.has("MADamage") and not info.has("PADamage"))
	var kind := swarm.mob_kind(slot)
	var damage := float(info.get("MADamage" if magic else "PADamage", kind.mad if magic else kind.pad))
	var out := {"boss_index": boss_index, "mob": slot, "mob_id": id, "attack": attack,
		"type": type, "range": travel, "bullet_speed": float(info.get("bulletSpeed", 0.0)),
		"spawn_offset": vec(range_data.get("sp", {})),
		"ball": "Mob.wz/%07d.img/%s/info/ball" % [id, attack],
		"hit": "Mob.wz/%07d.img/%s/info/hit" % [id, attack] if info.has("hit") else "",
		"pos": pos, "facing": facing, "area": area, "impact_time": now + after,
		"effect_time": now + effect_after, "effect_done": false, "impact_done": false, "damage": damage,
		"magic": magic, "element": String(info.get("elemAttr", "")),
		"jump_attack": int(info.get("jumpAttack", 0)) != 0,
		"dmg_mult": dmg_mult,
		"effect": "Mob.wz/%07d.img/%s/info/effect" % [id, attack] if info.has("effect") else "",
		"sound": attack_sound(id, attack),
		"duration": maxf(after, MobKind.stance_time(stance, after))}
	if type >= 3:
		var picked := pick_columns(world.area_rng, strip, int(range_data.get("attackCount", 1)),
			world.player_body_center().x)
		var columns: Array[Rect2] = []
		var anchors := PackedVector2Array()
		for index in picked:
			columns.append(strip[index])
			anchors.append(Vector2(strip[index].get_center().x, strip[index].end.y))
		out["columns"] = columns
		out["anchors"] = anchors
		out["column_size"] = strip[0].size
		out["warning"] = "Mob.wz/%07d.img/%s/info/areaWarning" % [id, attack] if info.has("areaWarning") else ""
	return out


## World-space canonical attack range, mirrored horizontally when the mob faces right.
static func area_at(range_data: Dictionary, pos: Vector2, facing: int) -> Rect2:
	var lt := vec(range_data.get("lt", {}))
	var rb := vec(range_data.get("rb", {}))
	var rect := Rect2(lt, rb - lt).abs()
	if facing > 0:
		rect.position.x = -rect.end.x
	rect.position += pos
	return rect


## The `areaCount` columns of an area-warning attack (types 3 and 4) in world space, in index order from `start`:
## column k is the `lt`/`rb` box shifted by k box widths along x, and the whole strip is mirrored when the mob faces right
## (tier C reading: the data names the geometry, not the layout, docs/research/v83-mob-skills-ii.md).
static func area_columns(range_data: Dictionary, pos: Vector2, facing: int) -> Array[Rect2]:
	var out: Array[Rect2] = []
	var box := Rect2(vec(range_data.get("lt", {})), vec(range_data.get("rb", {})) - vec(range_data.get("lt", {}))).abs()
	if box.size.x <= 0.0 or box.size.y <= 0.0:
		return out
	var start := int(range_data.get("start", 0))
	for k in maxi(0, int(range_data.get("areaCount", 0))):
		var column := Rect2(box.position + Vector2(box.size.x * float(start + k), 0.0), box.size)
		if facing > 0:
			column.position.x = -column.end.x
		column.position += pos
		out.append(column)
	return out


## Which columns of an area-warning attack strike (tier C, RNG stream 20): `count` distinct column indices, always
## including the column holding world x `target_x` when it lies in the strip, the rest drawn in one partial shuffle on
## `rng`. Returned ascending; `count` is clamped to the strip.
static func pick_columns(rng: RandomNumberGenerator, columns: Array[Rect2], count: int, target_x: float) -> PackedInt32Array:
	var total := columns.size()
	var order := PackedInt32Array()
	order.resize(total)
	for i in total:
		order[i] = i
	var want := clampi(count, 1, maxi(1, total))
	var fixed := 0
	for i in total:
		if target_x >= columns[i].position.x and target_x < columns[i].end.x:
			order[i] = 0
			order[0] = i
			fixed = 1
			break
	for i in range(fixed, want):
		var j := rng.randi_range(i, total - 1)
		var held := order[i]
		order[i] = order[j]
		order[j] = held
	var picked := order.slice(0, want)
	picked.sort()
	return picked


## Runs a pending windup's due effect and impact phases; true once both are done.
static func service(pending: Dictionary, world: RunWorld) -> bool:
	if not bool(pending.effect_done) and world.time >= float(pending.effect_time) - EPS:
		pending.effect_done = true
		emit(pending, "effect", world)
	if not bool(pending.impact_done) and world.time >= float(pending.impact_time) - EPS:
		pending.impact_done = true
		_impact(pending, world)
	# WZ may put effectAfter after attackAfter (Jr. Balrog attack3: 500/400 ms).
	return bool(pending.effect_done) and bool(pending.impact_done)


static func _impact(pending: Dictionary, world: RunWorld) -> void:
	if not bool(pending.magic):
		# Threaten (#183) and Attack Up (#255) apply at impact, for strikes and balls alike, before the source's dmg_mult.
		pending.damage = world.mob_weapon_attack(int(pending.mob), float(pending.damage))
	else:
		# Magic Attack Up (101/111, #457) multiplies the magic attacks of its recipients at impact, the same way.
		pending.damage = world.mob_magic_attack(int(pending.mob), float(pending.damage))
	emit(pending, "impact", world)
	if int(pending.type) >= 3:
		_strike_columns(pending, world)
		return
	# Hidden (#194): an attack winding up when the character vanished lands nothing and launches no ball.
	if world.is_hidden():
		return
	if int(pending.type) == 2:
		_launch_ball(pending, world)
		return
	# tier C: the lore jump-slam dodge uses the player's grounded state at impact, not at windup.
	var targeted := int(pending.type) == 1
	var can_hit := targeted or not bool(pending.jump_attack) or world.player.fh >= 0
	# tier C: a locked type-1 strike follows the character, including airborne/escaped targets, at attackAfter.
	if can_hit and (targeted or (pending.area as Rect2).intersects(world.player_box(), true)):
		var kind := world.swarm.mob_kind(int(pending.mob))
		var source := _source(pending, kind.acc)
		# tier C: the hit window turns an ordinary attack away before it lands, as it turns away an ordinary ball
		# (spec #144): no damage, no player_hit and no hit art. A rolled MISS is not blocked and keeps its art.
		if world.hit_window_blocks(source):
			return
		world.take_hit(float(pending.damage), bool(pending.magic), pending.element, pending.pos, source)
		if String(pending.hit) != "":
			emit(pending, "hit", world)


## An area-warning attack's impact: every picked column plays its hit art, and the character takes one hit when its
## body is inside any picked column (tier C: once per attack, never per column; a Hidden character is struck by nothing).
static func _strike_columns(pending: Dictionary, world: RunWorld) -> void:
	emit_area(pending, "strike", world)
	if world.is_hidden() or (bool(pending.jump_attack) and world.player.fh < 0):
		return
	var body := world.player_box()
	for column: Rect2 in pending.columns:
		if not column.intersects(body, true):
			continue
		var source := _source(pending, world.swarm.mob_kind(int(pending.mob)).acc)
		if not world.hit_window_blocks(source):
			world.take_hit(float(pending.damage), bool(pending.magic), pending.element, pending.pos, source)
		return


## take_hit source of a pending attack: bosses keep "attack"; ordinary mobs are "mob_attack" and, like their contact
## damage, scaled by the stage's elite multiplier when they spawned elite (tier C).
static func _source(pending: Dictionary, accuracy: float) -> Dictionary:
	if int(pending.boss_index) >= 0:
		return {"mob": int(pending.mob), "mob_id": int(pending.mob_id), "boss": true,
			"boss_index": int(pending.boss_index), "accuracy": accuracy, "dmg_mult": float(pending.dmg_mult), "source_kind": "attack"}
	return {"mob": int(pending.mob), "mob_id": int(pending.mob_id), "boss": false, "elite": bool(pending.elite),
		"accuracy": accuracy, "dmg_mult": float(pending.dmg_mult), "source_kind": "mob_attack"}


static func _launch_ball(pending: Dictionary, world: RunWorld) -> void:
	var offset: Vector2 = pending.spawn_offset
	if int(pending.facing) > 0:
		offset.x = -offset.x
	var pos: Vector2 = pending.pos + offset
	var target := world.player_body_center()
	# tier C: adopt the reference's r*600/bulletSpeed ms interpretation; WZ speed/range fields are unchanged.
	var speed := float(pending.bullet_speed) * 1000.0 / 600.0
	if speed <= 0.0:
		speed = float(world.balance.get("mob_projectiles", {}).get("default_speed", BossAttacks.DEFAULT_BALL_SPEED))
	var velocity := (target - pos).normalized() * speed
	var kind := world.swarm.mob_kind(int(pending.mob))
	var spec := {"pos": pos, "velocity": velocity, "range": float(pending.range),
		"visual": world.visual_index(pending.ball), "radius": float(world.balance.get("mob_projectiles", {}).get("radius", MobProjectileSystem.DEFAULT_RADIUS)),
		"mob": int(pending.mob), "mob_id": int(pending.mob_id), "damage": float(pending.damage),
		"multiplier": float(pending.dmg_mult), "accuracy": kind.acc, "magic": bool(pending.magic),
		"element": String(pending.element), "hit": String(pending.hit), "source_pos": pending.pos}
	spec["boss_index"] = int(pending.boss_index)
	if int(pending.boss_index) < 0:
		spec["ordinary"] = true
		spec["elite"] = bool(pending.elite)
	var slot := world.mob_projectiles.spawn(spec)
	world.emit("mob_projectile_spawned", {"proj": slot, "mob": int(pending.mob), "mob_id": int(pending.mob_id),
		"pos": pos, "velocity": velocity, "range": float(pending.range), "speed": speed,
		"ball": String(pending.ball), "hit": String(pending.hit), "time": world.time})


## Emits a phase of a pending attack: `boss_attack` for a scheduled boss, `mob_attack` for an ordinary mob.
static func emit(pending: Dictionary, phase: String, world: RunWorld) -> void:
	if phase == "start" and int(pending.type) >= 3:
		emit_area(pending, "warning", world)
	var boss := int(pending.boss_index) >= 0
	var fields := {"boss_index": int(pending.boss_index)} if boss else {}
	fields.merge({"mob": int(pending.mob),
		"mob_id": int(pending.mob_id), "attack": String(pending.attack), "phase": phase,
		"pos": world.player.pos if phase == "hit" else pending.pos, "facing": int(pending.facing), "area": pending.area,
		"time": world.time, "impact_time": float(pending.impact_time),
		"effect": String(pending.hit if phase == "hit" else pending.effect), "sound": String(pending.sound)})
	world.emit("boss_attack" if boss else "mob_attack", fields)


## One `area_attack` event for all picked columns at once: phase "warning" (attack start, `art` is areaWarning) or
## "strike" (impact, `art` is hit). The renderer places one pooled animation per anchor (the bottom centre of a column).
static func emit_area(pending: Dictionary, phase: String, world: RunWorld) -> void:
	world.emit("area_attack", {"boss_index": int(pending.boss_index), "mob": int(pending.mob),
		"mob_id": int(pending.mob_id), "attack": String(pending.attack), "phase": phase,
		"anchors": pending.anchors, "size": pending.column_size, "facing": int(pending.facing),
		"art": String(pending.warning if phase == "warning" else pending.hit),
		"time": world.time, "impact_time": float(pending.impact_time)})


## The `{mob_id: true}` set of the stage's scheduled boss kinds (they attack through BossAttacks).
static func boss_kind_ids(world: RunWorld) -> Dictionary:
	var ids := {}
	for entry: Dictionary in DataRepo.stage_bosses(world.stage):
		ids[int(entry.get("mob_id", 0))] = true
		if entry.has("final_form"):
			ids[int(entry.final_form)] = true
	return ids


## The WZ sound path of mob `id`'s attack stance (`attack1` -> `Sound.wz/Mob.img/<id>/Attack1`).
static func attack_sound(id: int, attack: String) -> String:
	return "Sound.wz/Mob.img/%07d/%s" % [id, attack.left(1).to_upper() + attack.substr(1)]


## Reads a WZ `{"$v": [x, y]}` vector (or a Vector2); ZERO for anything else.
static func vec(value: Variant) -> Vector2:
	if value is Vector2:
		return value
	if value is Dictionary and value.get("$v") is Array and value["$v"].size() >= 2:
		return Vector2(float(value["$v"][0]), float(value["$v"][1]))
	return Vector2.ZERO
