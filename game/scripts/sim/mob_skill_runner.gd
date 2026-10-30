class_name MobSkillRunner
extends RefCounted
## Canonical scheduled-boss skills (MobSkill 100/110/112/113/114/123/126/129/140/200) and their timed status state
## (docs/ARCHITECTURE.md 4.4.3, docs/GAME_DESIGN.md 4.3): no files, nodes or canonical-stat mutation.

## Original Skill.wz/MobSkill.img ids of the skills this runner casts.
const SKILL_ATTACK_UP := 100
const SKILL_ATTACK_UP_AREA := 110
const SKILL_PDD_UP_AREA := 112
const SKILL_MDD_UP_AREA := 113
const SKILL_HEAL_AREA := 114
const SKILL_STUN := 123
const SKILL_POISON := 125
const SKILL_SLOW := 126
const SKILL_BANISH := 129
const SKILL_MIST := 131
const SKILL_WEAPON_IMMUNITY := 140
const SKILL_SUMMON := StageRoster.SUMMON_SKILL
## Every MobSkill id `step` can cast; a boss's other listed skills are skipped.
const SUPPORTED := [SKILL_SLOW, SKILL_SUMMON, SKILL_PDD_UP_AREA, SKILL_MDD_UP_AREA, SKILL_HEAL_AREA,
	SKILL_WEAPON_IMMUNITY, SKILL_ATTACK_UP, SKILL_ATTACK_UP_AREA, SKILL_BANISH, SKILL_STUN,
	SKILL_POISON, SKILL_MIST]
## tier C: Attack Up (100/110) multiplies the weapon attack of the buffed mobs by this while it lasts (spec #253). The
## v83 x115 is not read: whether it is flat or a percentage is unverified. balance.mob_skills.attack_up_mult sets it.
const DEFAULT_ATTACK_UP_MULT := 1.15
## tier C (#459): the poison mist's effect on a character inside it, balance.mob_skills.mist (see mist_rule): ice keeps
## Slow at slow_x percent of speed (the 126 levels' x80) refreshed for slow_seconds each tick, poison applies Poison for
## poison_seconds at the level's x capped at poison_x_max HP per second (the largest x any 125 level has).
const DEFAULT_MIST := {"slow_x": 80.0, "slow_seconds": 1.0, "poison_seconds": 10.0, "poison_x_max": 300.0}

var _images: Dictionary
var _tables: Dictionary
var _enabled: Array
var _ready := {}
## The character's timed statuses (Slow, Stun) and their lockout floor.
var statuses: PlayerStatuses
var _pdd := PackedFloat32Array()
var _mdd := PackedFloat32Array()
var _pdd_until := PackedFloat64Array()
var _mdd_until := PackedFloat64Array()
var _weapon_until := PackedFloat64Array()
var _weapon_visual := PackedStringArray()
var _pending_heals: Array[Dictionary] = []
var _attack_up_mult := DEFAULT_ATTACK_UP_MULT
var _attack_until := PackedFloat64Array()
var _mist_rules := {}


func _init(setup: Dictionary, rules: Dictionary = {}) -> void:
	_images = setup.get("mob_imgs", {})
	_tables = setup.get("mob_skill_img", {})
	for id: Variant in rules.get("enabled_ids", []):
		_enabled.append(int(id))
	_attack_up_mult = float(rules.get("attack_up_mult", DEFAULT_ATTACK_UP_MULT))
	statuses = PlayerStatuses.new(rules.get("status_lockout", {}))
	_mist_rules = rules.get("mist", {})


## Current movement multiplier from the area's timed slow.
func speed_multiplier(now: float) -> float:
	return float(statuses.field(SKILL_SLOW, now, "multiplier", 1.0))


## Public presentation state for the player's active slow; empty after expiration.
func slow_state(now: float) -> Dictionary:
	return statuses.state(SKILL_SLOW, now)


## Whether the player is stunned at this simulation time.
func is_stunned(now: float) -> bool:
	return statuses.is_active(SKILL_STUN, now)


## Detached presentation state for the timed player Stun ({} when not stunned).
func stun_state(now: float) -> Dictionary:
	return statuses.state(SKILL_STUN, now)


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
			# Hidden (#194): a skill aimed at the character (Slow, Banish, Stun, Poison, the mist) is not cast while it is Hidden.
			if id in [SKILL_SLOW, SKILL_BANISH, SKILL_STUN, SKILL_POISON, SKILL_MIST] and world.is_hidden():
				continue
			var key := "%d/%d/%d" % [index, id, level]
			var interval := world.bosses.skill_interval(index, id, float(spec.get("interval", 0.0)))
			# tier C: a skill first becomes ready one interval after the boss arrives (never on the arrival tick), then
			# one interval after each cast; WZ has the interval, not when the first use may happen.
			# A final form (#456) schedules from the swap (`form_time`), not from the shell's arrival.
			var ready := float(_ready.get(key, float(record.get("form_time", record.spawn_time)) + interval))
			if now < ready - 1e-9 or float(swarm.hp[slot]) * 100.0 > float(swarm.max_hp[slot]) * float(spec.get("hp", 100.0)):
				# tier C: an omitted hp field permits casting at full health.
				continue
			if id == SKILL_SUMMON and world.summoned_alive(index) >= int(spec.get("limit", 0)):
				continue
			var pos := swarm.pos(slot)
			var facing := int(swarm.facing[slot])
			# tier C (#256): Banish is only cast with the character inside its canonical area (prop 100, so no roll; the
			# one character is its only target whatever `count` says); a miss never spends its cooldown.
			if id == SKILL_BANISH and not _area(spec, pos, facing).has_point(world.player.pos):
				continue
			var duration := float(spec.get("time", 0.0))
			var path := "Skill.wz/MobSkill.img/%d/level/%d" % [id, level]
			var affected := ""
			if id == SKILL_SLOW and _area(spec, pos, facing).has_point(world.player.pos):
				# tier C: x is retained percent of upgraded speed (x80 means 20% slower).
				# Slow has no lockout: a recast while it lasts overwrites it, as before the shared seam.
				statuses.apply(SKILL_SLOW, now, duration, {"multiplier": clampf(float(spec.get("x", 100.0)) / 100.0, 0.0, 1.0),
					"visual": path + "/affected"}, false)
				affected = path + "/affected"
			if id == SKILL_STUN and _area(spec, pos, facing).has_point(world.player.pos) \
					and _roll_status(world, id, spec) and statuses.apply(id, now, duration, {"visual": path + "/affected"}):
				affected = path + "/affected"
			if id == SKILL_POISON and _area(spec, pos, facing).intersects(world.player_box()) and _roll_status(world, id, spec) \
					and apply_poison(world, slot, int(record.mob_id), float(spec.get("x", 0.0)), duration, path + "/affected"):
				affected = path + "/affected"
			if id == SKILL_MIST and _roll_status(world, id, spec):
				_place_mist(world, slot, int(record.mob_id), spec, level, _area(spec, pos, facing))
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
			elif id == SKILL_BANISH:
				world.banish_player({"mob": slot, "mob_id": int(record.mob_id), "skill_id": id, "level": level,
					"effect": path + "/affected" if spec.has("affected") else "",
					"message": _banish_message(world, int(record.mob_id))})
			_ready[key] = now + interval
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


## One `prop` roll of status `id` on stream 19 (mob_status_rng, tier C), made once per in-area cast. No roll is drawn
## while the status is locked out (the cast then spends its interval and has no effect), and prop >= 100 never draws.
func _roll_status(world: RunWorld, id: int, spec: Dictionary) -> bool:
	if statuses.is_locked(id, world.time):
		return false
	var prop := float(spec.get("prop", 100.0))
	return prop >= 100.0 or (prop > 0.0 and world.mob_status_rng.randf() * 100.0 < prop)


## Forgets the cast schedule of boss `index`, so each of its skills is ready one interval after the record's
## `form_time` (or spawn_time): a final form starts its own cooldowns, whatever the shell had cast (#456).
func reset_boss(index: int) -> void:
	var prefix := "%d/" % index
	for key: String in _ready.keys():
		if key.begins_with(prefix):
			_ready.erase(key)


## Banish (129) notice of boss `mob_id`: its survivor mobs.json `banish_message` (Shade's reworded v83 banMsg, #256),
## "" when it has none.
static func _banish_message(world: RunWorld, mob_id: int) -> String:
	return String(world.data.get("mobs", {}).get("mobs", {}).get(str(mob_id), {}).get("banish_message", ""))


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
## boss/elite source multipliers (RunWorld.mob_weapon_attack); magic attacks are unchanged.
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


## Detached presentation state for the timed Poison ({} when not poisoned).
func poison_state(now: float) -> Dictionary:
	return statuses.state(SKILL_POISON, now)


## One mist rule of balance.mob_skills.mist (DEFAULT_MIST when absent).
func mist_rule(key: String) -> float:
	return float(_mist_rules.get(key, DEFAULT_MIST[key]))


## Poisons the character for `duration` s at `x` HP per whole second (Poison 125, and the S mist), through the status seam
## (its lockout floor, one at a time), with the source boss for the hit telemetry. Returns whether it took effect.
func apply_poison(world: RunWorld, boss_slot: int, boss_mob_id: int, x: float, duration: float, visual: String) -> bool:
	# tier C (#459): v83 does not say what `x` is; read as HP lost each whole second, never lethal (take_poison).
	return statuses.apply(SKILL_POISON, world.time, duration, {"x": x, "mob": boss_slot, "mob_id": boss_mob_id,
		"start": world.time, "ticks": floori(duration + 1e-6), "paid": 0, "visual": visual})


## Pays the whole-second ticks of the active Poison that fell due by `world.time` (a tick at each second after the cast, up
## to `time`, including the one at the very end); a skipped tick step is caught up, never lost. No random draw.
func step_poison(world: RunWorld) -> void:
	var poison := statuses.raw_payload(SKILL_POISON)
	if poison.is_empty():
		return
	var due := mini(int(poison.ticks), floori(world.time - float(poison.start) + 1e-6)) - int(poison.paid)
	for tick in maxi(0, due):
		poison.paid = int(poison.paid) + 1
		world.take_poison(int(poison.x), int(poison.mob), int(poison.mob_id))


## A character standing in a live hazard of kind `kind` (GroundHazards.ICE / POISON) this tick: ice keeps Slow at the
## mist's strength (never weaker or shorter than a Slow already on it), poison applies Poison when it is not locked
## out; `visual` is the level's `affected` art. Announces the status with `hazard_status` when it first takes hold.
func touch_hazard(world: RunWorld, kind: int, strength: float, boss_slot: int, boss_mob_id: int, visual: String) -> void:
	var now := world.time
	if kind == GroundHazards.ICE:
		var was := statuses.is_active(SKILL_SLOW, now)
		var multiplier := clampf(mist_rule("slow_x") / 100.0, 0.0, 1.0)
		var duration := mist_rule("slow_seconds")
		if was:
			multiplier = minf(multiplier, float(statuses.field(SKILL_SLOW, now, "multiplier", 1.0)))
			duration = maxf(duration, float(statuses.state(SKILL_SLOW, now).remaining))
		statuses.apply(SKILL_SLOW, now, duration, {"multiplier": multiplier, "visual": visual}, false)
		if not was:
			world.refresh_player_speed()
			world.emit("hazard_status", {"skill_id": SKILL_SLOW, "effect": visual})
	elif kind == GroundHazards.POISON and not statuses.is_locked(SKILL_POISON, now) \
			and apply_poison(world, boss_slot, boss_mob_id, minf(strength, mist_rule("poison_x_max")),
				mist_rule("poison_seconds"), visual):
		world.emit("hazard_status", {"skill_id": SKILL_POISON, "effect": visual})


## Poison mist 131: places the level's box (already mirrored by the boss's facing) as a hazard for `time` s with the
## level's elemAttr (a level without one only shows its mist, tier C) and `tile` art.
func _place_mist(world: RunWorld, boss_slot: int, boss_mob_id: int, spec: Dictionary, level: int, area: Rect2) -> void:
	var path := "Skill.wz/MobSkill.img/%d/level/%d" % [SKILL_MIST, level]
	var kind := GroundHazards.element_of(spec.get("elemAttr", ""))
	var slot := world.hazards.spawn({"rect": area, "born": world.time, "until": world.time + float(spec.get("time", 0.0)),
		"effect": kind, "strength": float(spec.get("x", 0.0)), "mob": boss_slot, "mob_id": boss_mob_id,
		"affected": path + "/affected" if spec.has("affected") else "", "tile_path": path + "/tile",
		"tile_count": (spec.get("tile", {}) as Dictionary).keys().filter(func(k: Variant) -> bool: return String(k).is_valid_int()).size()})
	world.emit("hazard_spawned", {"hazard": slot, "mob": boss_slot, "mob_id": boss_mob_id, "level": level,
		"rect": area, "hazard_kind": kind, "duration": float(spec.get("time", 0.0))})
