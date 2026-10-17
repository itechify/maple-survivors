class_name MobSkillRunner
extends RefCounted
## Canonical scheduled-boss skills (MobSkill 112/113/114/126/140/200), ordinary mobs' Seal (120, #76) and their timed
## status state (docs/ARCHITECTURE.md 4.4.1 and 4.4.3, docs/GAME_DESIGN.md 4.3): no files, nodes or canonical-stat
## mutation. Ordinary (non-boss) mobs keep per-slot cast waits in packed arrays, like MobAttacks; every other skill
## they list (Jr. Boogie's Curse 124) is skipped and leaves no state or event.

## Original Skill.wz/MobSkill.img ids of the skills this runner casts.
const SKILL_PDD_UP_AREA := 112
const SKILL_MDD_UP_AREA := 113
const SKILL_HEAL_AREA := 114
const SKILL_SLOW := 126
const SKILL_WEAPON_IMMUNITY := 140
const SKILL_SUMMON := StageRoster.SUMMON_SKILL
const SKILL_SEAL := 120
## Every MobSkill id `step` can cast; a boss's other listed skills are skipped.
const SUPPORTED := [SKILL_SLOW, SKILL_SUMMON, SKILL_PDD_UP_AREA, SKILL_MDD_UP_AREA, SKILL_HEAL_AREA,
	SKILL_WEAPON_IMMUNITY]
## The only MobSkill ids an ordinary (non-boss) mob casts (`step_ordinary`, #76).
const ORDINARY_SUPPORTED := [SKILL_SEAL]
## tier C: balance.mob_skills.seal fallbacks. While sealed every skill cooldown takes cooldown_multiplier times as long
## (Seal is not a silence); the canonical time/interval/prop are scaled by the other three.
const SEAL_DEFAULTS := {"cooldown_multiplier": 2.0, "duration_mult": 1.0, "interval_mult": 1.0, "prop_mult": 1.0}

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
var _seal_rules := SEAL_DEFAULTS.duplicate()
var _seal_until := 0.0
var _seal_level := 0
var _seal_visual := ""
## Per kind index: the ordinary casts it lists [{id, level, action, spec}] (ORDINARY_SUPPORTED only).
var _kind_casts: Array[Array] = []
var _any_ordinary := false
## Per slot: seconds of eligible (fully visible, on-screen) time before the next ordinary cast; NAN = unset.
var _skill_wait := PackedFloat64Array()


func _init(setup: Dictionary, rules: Dictionary = {}) -> void:
	_images = setup.get("mob_imgs", {})
	_tables = setup.get("mob_skill_img", {})
	for id: Variant in rules.get("enabled_ids", []):
		_enabled.append(int(id))
	_seal_rules.merge(rules.get("seal", {}), true)


## Reads which mob kinds of `world` list an ordinary-supported skill with canonical data. Scheduled-boss kinds cast
## through step() and are skipped here; their slots are excluded again with world.mob_boss.
func bind_ordinary(world: RunWorld) -> void:
	var boss_ids := {}
	for entry: Dictionary in world.stage.get("bosses", []):
		boss_ids[int(entry.get("mob_id", 0))] = true
	_kind_casts.clear()
	for k in world.mob_kinds.size():
		var kind: MobKind = world.mob_kinds[k]
		var casts: Array = []
		var image: Dictionary = _images.get(kind.id, _images.get(str(kind.id), {}))
		if not boss_ids.has(kind.id):
			for entry: Dictionary in image.get("info", {}).get("skill", {}).values():
				var id := int(entry.skill)
				var level := int(entry.level)
				var spec: Dictionary = _tables.get(str(id), {}).get("level", {}).get(str(level), {})
				if id in ORDINARY_SUPPORTED and not spec.is_empty():
					casts.append({"id": id, "level": level, "action": "skill%d" % int(entry.get("action", 1)),
						"spec": spec})
		_kind_casts.append(casts)
		_any_ordinary = _any_ordinary or not casts.is_empty()


## Public presentation state of the character's Seal (#76); empty when not sealed. multiplier = how many times as
## long every skill cooldown takes; visual = the canonical affected animation; icon = its first frame (tier C: v83
## has no Seal status icon).
func seal_state(now: float) -> Dictionary:
	if not sealed(now):
		return {}
	return {"skill_id": SKILL_SEAL, "level": _seal_level, "remaining": _seal_until - now,
		"multiplier": float(_seal_rules.cooldown_multiplier), "visual": _seal_visual, "icon": _seal_visual + "/0"}


## Whether the character is sealed at `now`.
func sealed(now: float) -> bool:
	return now < _seal_until - 1e-9


## Skill cooldown countdown rate: exactly 1.0, or 1 / seal.cooldown_multiplier while sealed (tier C).
func cooldown_rate(now: float) -> float:
	if not sealed(now):
		return 1.0
	return 1.0 / maxf(1.0, float(_seal_rules.cooldown_multiplier))


## Ordinary mobs' casts: a mob that can act on screen counts its wait down; once ready, not busy and with the
## character's feet inside a listed skill's canonical box (mirrored by facing), it casts it: the action stance, the
## caster effect and one prop roll on world.mob_skill_rng (rolled only here). A winning Seal roll seals the character
## until the later of its current end and now + time x duration_mult (tier C: a recast extends, never stacks).
func step_ordinary(world: RunWorld, dt: float) -> void:
	if not _any_ordinary or world.state != RunWorld.PLAYING:
		return
	var swarm := world.swarm
	var now := world.time
	var view := world.view
	var interval_mult := float(_seal_rules.interval_mult)
	for slot in swarm.capacity():
		if swarm.active[slot] == 0 or world.mob_boss[slot] >= 0:
			continue
		var casts: Array = _kind_casts[swarm.kind[slot]]
		if casts.is_empty() or not swarm.can_act(slot) or not view.has_point(swarm.pos(slot)):
			continue
		var wait := _skill_wait[slot]
		if is_nan(wait):
			# tier C: the first cast waits 50-100% of the canonical interval (MobAttacks.first_wait stagger).
			wait = MobAttacks.first_wait(float(casts[0].spec.get("interval", 0.0)) * interval_mult,
				swarm.identity[slot])
		wait = maxf(0.0, wait - dt)
		_skill_wait[slot] = wait
		if wait > 1e-6 or world.mob_actions.busy(slot, now):
			continue
		var pos := swarm.pos(slot)
		var facing := int(swarm.facing[slot])
		for cast: Dictionary in casts:
			var spec: Dictionary = cast.spec
			if not _area(spec, pos, facing).has_point(world.player.pos):
				continue
			var id := int(cast.id)
			var level := int(cast.level)
			var mob_id := swarm.mob_kind(slot).id
			var prop := float(spec.get("prop", 100.0)) * float(_seal_rules.prop_mult)
			var applied := world.mob_skill_rng.randf() * 100.0 < prop
			_skill_wait[slot] = float(spec.get("interval", 0.0)) * interval_mult
			var path := "Skill.wz/MobSkill.img/%d/level/%d" % [id, level]
			var action := String(cast.action)
			world.mob_actions.begin(slot, action, MobKind.stance_time(world.mob_img(mob_id).get(action), 0.0),
				facing, now)
			world.emit("mob_skill", {"mob": slot, "mob_id": mob_id, "skill_id": id, "level": level, "pos": pos,
				"facing": facing, "action": action, "effect": path + "/effect" if spec.has("effect") else "",
				"applied": applied})
			if applied and id == SKILL_SEAL:
				_seal_until = maxf(_seal_until, now + float(spec.get("time", 0.0)) * float(_seal_rules.duration_mult))
				_seal_level = level
				_seal_visual = path + "/affected"
				world.emit("player_status_applied", {"status": "seal", "skill_id": id, "level": level,
					"remaining": _seal_until - now, "mob": slot, "mob_id": mob_id, "visual": _seal_visual})
			break


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
	var old := _skill_wait.size()
	if old < capacity:
		_skill_wait.resize(capacity)
		for slot in range(old, capacity):
			_skill_wait[slot] = NAN


## A new mob in a reused slot starts without the previous occupant's defense statuses or cast wait.
func reset_slot(slot: int) -> void:
	_pdd[slot] = 0
	_mdd[slot] = 0
	_pdd_until[slot] = 0
	_mdd_until[slot] = 0
	_weapon_until[slot] = 0
	_weapon_visual[slot] = ""
	if slot < _skill_wait.size():
		_skill_wait[slot] = NAN


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
	_skill_wait[to] = _skill_wait[from]
	reset_slot(from)


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
