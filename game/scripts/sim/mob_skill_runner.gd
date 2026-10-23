class_name MobSkillRunner
extends RefCounted
## Canonical scheduled-boss skills (MobSkill 100/110/112/113/114/126/140/200) and their timed status state
## (docs/ARCHITECTURE.md 4.4.3, docs/GAME_DESIGN.md 4.3): no files, nodes or canonical-stat mutation.

## Original Skill.wz/MobSkill.img ids of the skills this runner casts.
const SKILL_ATTACK_UP := 100
const SKILL_ATTACK_UP_AREA := 110
const SKILL_PDD_UP_AREA := 112
const SKILL_MDD_UP_AREA := 113
const SKILL_HEAL_AREA := 114
const SKILL_SLOW := 126
const SKILL_WEAPON_IMMUNITY := 140
const SKILL_SUMMON := StageRoster.SUMMON_SKILL
## Every MobSkill id `step` can cast; a boss's other listed skills are skipped.
const SUPPORTED := [SKILL_SLOW, SKILL_SUMMON, SKILL_PDD_UP_AREA, SKILL_MDD_UP_AREA, SKILL_HEAL_AREA,
	SKILL_WEAPON_IMMUNITY, SKILL_ATTACK_UP, SKILL_ATTACK_UP_AREA]
## tier C: Attack Up (100/110) multiplies the weapon attack of the buffed mobs by this while it lasts (spec #253). The
## v83 x115 is not read: whether it is flat or a percentage is unverified. balance.mob_skills.attack_up_mult sets it.
const DEFAULT_ATTACK_UP_MULT := 1.15

var _images: Dictionary
var _tables: Dictionary
var _enabled: Array
var _ready := {}
var _slow_until := 0.0
var _slow_factor := 1.0
var _slow_visual := ""
var _pdd := PackedFloat32Array()
var _mdd := PackedFloat32Array()
var _pdd_until := PackedFloat64Array()
var _mdd_until := PackedFloat64Array()
var _weapon_until := PackedFloat64Array()
var _weapon_visual := PackedStringArray()
var _pending_heals: Array[Dictionary] = []
var _attack_up_mult := DEFAULT_ATTACK_UP_MULT
var _attack_until := PackedFloat64Array()


func _init(setup: Dictionary, rules: Dictionary = {}) -> void:
	_images = setup.get("mob_imgs", {})
	_tables = setup.get("mob_skill_img", {})
	for id: Variant in rules.get("enabled_ids", []):
		_enabled.append(int(id))
	_attack_up_mult = float(rules.get("attack_up_mult", DEFAULT_ATTACK_UP_MULT))


## Current movement multiplier from the area's timed slow.
func speed_multiplier(now: float) -> float:
	return _slow_factor if now < _slow_until - 1e-9 else 1.0


## Public presentation state for the player's active slow; empty after expiration.
func slow_state(now: float) -> Dictionary:
	return {"skill_id": SKILL_SLOW, "remaining": _slow_until - now, "multiplier": _slow_factor, "visual": _slow_visual} if now < _slow_until - 1e-9 else {}


## Casts one ready canonical skill per boss after its own HP gate and stance availability.
func step(world: RunWorld) -> void:
	_resolve_heals(world)
	var swarm := world.swarm
	var now := world.time
	for record: Dictionary in world.bosses.records:
		var slot := int(record.slot)
		if not swarm.can_act(slot) or not int(record.mob_id) in _enabled:
			continue
		var index := int(record.boss_index)
		if world.mob_boss[slot] != index or not world.bosses.can_act(index, now):
			continue
		var image: Dictionary = _images.get(int(record.mob_id), _images.get(str(int(record.mob_id)), {}))
		for entry: Dictionary in image.get("info", {}).get("skill", {}).values():
			var id := int(entry.skill)
			var level := int(entry.level)
			var spec: Dictionary = _tables.get(str(id), {}).get("level", {}).get(str(level), {})
			if spec.is_empty() or id not in SUPPORTED:
				continue
			# Hidden (#194): a skill aimed at the character (Slow) is not cast while it is Hidden.
			if id == SKILL_SLOW and world.is_hidden():
				continue
			var key := "%d/%d/%d" % [index, id, level]
			# tier C: a skill first becomes ready one canonical interval after the boss arrives (never on the arrival
			# tick), then one interval after each cast; WZ has the interval, not when the first use may happen.
			var ready := float(_ready.get(key, float(record.spawn_time) + float(spec.get("interval", 0.0))))
			if now < ready - 1e-9 or float(swarm.hp[slot]) * 100.0 > float(swarm.max_hp[slot]) * float(spec.get("hp", 100.0)):
				# tier C: an omitted hp field permits casting at full health.
				continue
			if id == SKILL_SUMMON and world.summoned_alive(index) >= int(spec.get("limit", 0)):
				continue
			var pos := swarm.pos(slot)
			var facing := int(swarm.facing[slot])
			var duration := float(spec.get("time", 0.0))
			var path := "Skill.wz/MobSkill.img/%d/level/%d" % [id, level]
			var affected := ""
			if id == SKILL_SLOW and _area(spec, pos, facing).has_point(world.player.pos):
				# tier C: x is retained percent of upgraded speed (x80 means 20% slower).
				_slow_factor = clampf(float(spec.get("x", 100.0)) / 100.0, 0.0, 1.0)
				_slow_until = now + duration
				_slow_visual = path + "/affected"
				affected = _slow_visual
			var targets: Array = []
			if id == SKILL_SUMMON:
				var available := maxi(0, int(spec.get("limit", 0)) - world.summoned_alive(index))
				targets = Array(world.spawn_offspring(slot, swarm.x[slot], StageRoster.list_ids(spec), index, available))
			elif id in [SKILL_PDD_UP_AREA, SKILL_MDD_UP_AREA]:
				targets = _buff(swarm, _area(spec, pos, facing), id, spec, now + duration)
			elif id == SKILL_ATTACK_UP:
				targets = _attack_up([slot], now + duration)
			elif id == SKILL_ATTACK_UP_AREA:
				targets = _attack_up(Array(swarm.live_in_rect(_area(spec, pos, facing))), now + duration)
			elif id == SKILL_HEAL_AREA:
				_pending_heals.append({"index": index, "level": level, "spec": spec,
					"due": now + float(entry.get("effectAfter", 0.0)) / 1000.0})
			elif id == SKILL_WEAPON_IMMUNITY:
				# tier C: weapon immunity is a timed self status; WZ verifies its gate and duration.
				_weapon_until[slot] = now + duration
				_weapon_visual[slot] = path + "/mob"
				targets = [slot]
			_ready[key] = now + float(spec.get("interval", 0.0))
			var action := "skill%d" % int(entry.get("action", 1))
			world.bosses.begin_action(index, action, MobKind.stance_time(image.get(action), 0.0), facing, now)
			world.refresh_player_speed()
			world.emit("boss_skill", {"mob": slot, "mob_id": int(record.mob_id), "skill_id": id, "level": level,
				"pos": pos, "facing": facing, "action": action, "duration": duration,
				"effect": path + ("/effect" if spec.has("effect") else "/mob0") if spec.has("effect") or (id == SKILL_HEAL_AREA and spec.has("mob0")) else "", "player_effect": affected, "targets": targets,
				"recipient_effect": path + "/mob0" if spec.has("mob0") else "",
				"summon_effect": "Effect.wz/Summon.img/%d" % int(spec.summonEffect) if id == SKILL_SUMMON and spec.has("summonEffect") else ""})
			break
	# Resolve newly queued effectAfter0 heals in the same tick, after the cast event; delayed entries remain queued.
	_resolve_heals(world)


func _resolve_heals(world: RunWorld) -> void:
	var swarm := world.swarm
	var waiting: Array[Dictionary] = []
	for pending: Dictionary in _pending_heals:
		var record: Dictionary = world.bosses.records[int(pending.index)]
		var source := int(record.slot)
		if bool(record.dead) or source < 0 or not swarm.is_live(source):
			continue
		if world.time < float(pending.due) - 1e-6:
			waiting.append(pending)
			continue
		var spec: Dictionary = pending.spec
		# tier C: the canonical x is the HP restored to each mob in the area (the spec's "canonical amount"); y is
		# unused (its role in the v83 client is unverified). No random roll.
		var amount := maxi(0, int(spec.get("x", 0)))
		for slot in swarm.live_in_rect(_area(spec, swarm.pos(source), swarm.facing[source])):
			var restored := mini(amount, swarm.max_hp[slot] - swarm.hp[slot])
			if restored <= 0:
				continue
			swarm.hp[slot] += restored
			world.emit("mob_healed", {"mob": slot, "mob_id": swarm.mob_kind(slot).id,
				"skill_id": SKILL_HEAL_AREA, "level": int(pending.level), "amount": restored,
				"pos": swarm.pos(slot), "time": world.time})
	_pending_heals = waiting


func _area(spec: Dictionary, pos: Vector2, facing: int) -> Rect2:
	var lt: Array = spec.get("lt", {"$v": [0, 0]})["$v"]
	var rb: Array = spec.get("rb", {"$v": [0, 0]})["$v"]
	var box := Rect2(Vector2(float(lt[0]), float(lt[1])), Vector2(float(rb[0])-float(lt[0]), float(rb[1])-float(lt[1]))).abs()
	if facing > 0:
		box.position.x = -box.end.x
	box.position += pos
	return box


## Number of this encounter's still-living summoned slots (RunWorld.summoned_alive).
func summoned_alive(world: RunWorld, owner: int) -> int:
	return world.summoned_alive(owner)


## Grows the per-slot timed status pool without changing existing statuses.
func resize(capacity: int) -> void:
	_pdd.resize(capacity)
	_mdd.resize(capacity)
	_pdd_until.resize(capacity)
	_mdd_until.resize(capacity)
	_weapon_until.resize(capacity)
	_weapon_visual.resize(capacity)
	_attack_until.resize(capacity)


## A new mob in a reused slot starts without the previous occupant's defense and attack statuses.
func reset_slot(slot: int) -> void:
	_pdd[slot] = 0
	_mdd[slot] = 0
	_pdd_until[slot] = 0
	_mdd_until[slot] = 0
	_weapon_until[slot] = 0
	_weapon_visual[slot] = ""
	_attack_until[slot] = 0


## Transfers timed statuses with a relocation; a later reuse of the former slot gets no stale state.
func move_slot(from: int, to: int) -> void:
	if from == to:
		return
	_pdd[to] = _pdd[from]
	_mdd[to] = _mdd[from]
	_pdd_until[to] = _pdd_until[from]
	_mdd_until[to] = _mdd_until[from]
	_weapon_until[to] = _weapon_until[from]
	_weapon_visual[to] = _weapon_visual[from]
	_attack_until[to] = _attack_until[from]
	reset_slot(from)


## For every slot below `n` whose `active` entry is set, writes its live magic defense into `mdd` (`kind_mdd[kind[slot]]`,
## the kind's canonical MDD, plus defense_bonus(slot, true, now)) and 1/0 into `physical` (physical_hit_allowed); other
## slots keep what they held. Optional canonical PDD and output arrays include physical defense in the same pass
## (spec #151). The same numbers as the per-slot calls in one pass (issue #146).
func fill_live_defense(active: PackedByteArray, kind: PackedInt32Array, kind_mdd: PackedFloat64Array, n: int,
		now: float, mdd: PackedFloat32Array, physical: PackedByteArray,
		kind_pdd: PackedFloat64Array = PackedFloat64Array(), pdd: PackedFloat32Array = PackedFloat32Array()) -> void:
	var buffed := _pdd.size()
	var immune := _weapon_until.size()
	for slot in n:
		if active[slot] == 0:
			continue
		var bonus := 0.0
		if slot < buffed:
			bonus = _mdd[slot] if now < _mdd_until[slot] - 1e-9 else 0.0
		mdd[slot] = kind_mdd[kind[slot]] + bonus
		if not pdd.is_empty():
			var physical_bonus := _pdd[slot] if slot < buffed and now < _pdd_until[slot] - 1e-9 else 0.0
			pdd[slot] = kind_pdd[kind[slot]] + physical_bonus
		physical[slot] = 1 if slot >= immune or now >= _weapon_until[slot] - 1e-9 else 0


## Live weapon immunity at this impact tick; magic damage remains allowed.
func physical_hit_allowed(slot: int, now: float) -> bool:
	return slot < 0 or slot >= _weapon_until.size() or now >= _weapon_until[slot] - 1e-9


## Detached active mob-icon presentation state, empty after status expiry or slot reset.
func immunity_state(slot: int, now: float) -> Dictionary:
	return {} if physical_hit_allowed(slot, now) else {"remaining": _weapon_until[slot] - now, "visual": _weapon_visual[slot]}


## Live flat defense addition at this slot; canonical MobKind stats are never edited.
func defense_bonus(slot: int, magic: bool, now: float) -> float:
	if slot < 0 or slot >= _pdd.size():
		return 0.0
	return (_mdd[slot] if now < _mdd_until[slot] - 1e-9 else 0.0) if magic else (_pdd[slot] if now < _pdd_until[slot] - 1e-9 else 0.0)


## MobSkill 112/113 are v83 area buffs: every living mob inside the canonical area (ordinary mobs included) gets the
## flat defense until `until`; returns the recipient slots.
func _buff(swarm: MobSwarm, area: Rect2, id: int, spec: Dictionary, until: float) -> Array:
	var targets: Array = []
	for slot in swarm.live_in_rect(area):
		targets.append(slot)
		# tier C: x is a flat defense addition; WZ verifies x85, not the original client's arithmetic.
		if id == SKILL_MDD_UP_AREA:
			_mdd[slot] = float(spec.get("x", 0.0))
			_mdd_until[slot] = until
		else:
			_pdd[slot] = float(spec.get("x", 0.0))
			_pdd_until[slot] = until
	return targets


## Live Attack Up multiplier of the mob in `slot`: balance.mob_skills.attack_up_mult while MobSkill 100/110 lasts, else 1.
## Touch damage and physical attackN impacts multiply their weapon attack by it, after a Threaten cut and before the
## boss/elite source multipliers (RunWorld._player_hit, MobAttacks); magic attacks are unchanged.
func attack_multiplier(slot: int, now: float) -> float:
	if slot < 0 or slot >= _attack_until.size() or now >= _attack_until[slot] - 1e-9:
		return 1.0
	return _attack_up_mult


## MobSkill 100 buffs the caster and 110 every living mob inside its canonical area (ordinary mobs included, like
## 112/113) until `until`; a recast refreshes the end time and never stacks. Returns the recipient slots.
func _attack_up(slots: Array, until: float) -> Array:
	for slot: int in slots:
		_attack_until[slot] = until
	return slots
