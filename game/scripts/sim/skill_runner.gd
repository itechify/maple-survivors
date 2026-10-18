class_name SkillRunner
extends RefCounted
## Auto-casting (docs/GAME_DESIGN.md section 7). Every owned active skill counts its cooldown down; when it is ready
## and a living mob is within its range of the cast origin (the player's body, `RunWorld.cast_origin()`), it fires:
## a `cast` event, the player's cast stance, then
## - projectile skills: `count` shots, each aimed at the position (body centre) of a different target at cast time,
##   scheduled bosses first, then nearest (SpatialHash query; RunWorld.targets_before); with fewer targets than shots the extra shots reuse targets in order, aimed a
##   few px apart; each shot starts at RunWorld.shot_origin (the hand, cast_forward px toward its target);
## - instant skills: `attack_count` damage lines on each of the `count` nearest targets (Magic Claw: 2 lines); the
##   `box`, `weapon_reach` (the held weapon's swing envelope, Warrior Power Strike) and `range_around` (the level's
##   `range` around the body, Slash Blast) rules strike `mob_count` targets instead, and the last two turn a standing
##   character toward the target first. A skill with an HP cost (`hp_cost`) never casts when paying it would leave 0 HP.
## A skill with a `displacement` block (a moving attack, docs/GAME_DESIGN.md 7.9) also moves the grounded character away
## from or toward its first target before, after or during the hits (`_resolve_cast`, `_resolve_charge`).
## A ready skill without a target waits (it fires on the first tick one is in range). The cooldown restarts on cast.
## A skill whose weapon requirement the held weapon fails (SkillBook.usable_with) is skipped.
## At most one skill fires per tick, oldest-ready first, paying its canonical MP cost. A short-MP skill remains
## ready and signals its waiting episode once; a later affordable skill may cast instead. Buffs need no mob target,
## stay out of the ready list while active, and use their canonical duration as the next readiness time.
## Stats come from Loadout.stats(), cached until Loadout.version changes.

## Vertical spacing of shots that reuse a target. tier C: ours.
const REUSE_SPREAD := 8.0
## Grid candidates _any_target checks before it reads the whole query. Performance only, not behaviour (no tier):
## the answer is the same for any value.
const ANY_PROBE := 8
## What a skill's `count` is, by its kind (count_meaning): SHOTS (projectiles fired per cast) for a projectile, else
## TARGETS (mobs struck). Card previews, Skill window tooltips and the level-up window name `count` effects by this.
const SHOTS := "shots"
const TARGETS := "targets"

## skill key -> seconds until ready (<= 0 = ready).
var cooldowns := {}
## skill key -> the cooldown set at its last cast (absent before the first cast); the HUD sweep's denominator.
var cooldown_totals := {}
var casts := 0
## True if any skill cast during the latest step (cleared even when casting is blocked).
var fired_this_tick := false
## True while a ready, targeted skill is waiting for MP this tick (persistent presentation cue).
var waiting_mp := false

var _stats := {}
var _version := -1
var _buf := PackedInt32Array()
var _tgt := PackedInt32Array()
var _tgt_d := PackedFloat64Array()
var _shortages := {}
var _undead := PackedByteArray()
var _slow_serial := 0


func _init() -> void:
	_buf.resize(128)


## SHOTS for a projectile skill kind, TARGETS otherwise.
static func count_meaning(kind: String) -> String:
	return SHOTS if kind == "projectile" else TARGETS


## How many shots or targets one cast of resolved stats `st` (Loadout.stats) reaches: box and crowd skills strike
## their mob_count (canonical mobCount plus count cards), the others `count`.
static func strike_count(st: Dictionary) -> int:
	return int(st.mob_count) if String(st.cast_rule) in ["box", "crowd", "weapon_reach", "range_around"] else int(st.count)


## Seconds a cast of resolved stats `st` waits before the skill is ready again: a buff its duration or its canonical
## buff cooldown, whichever is longer; any other skill its cooldown (cast_ready adds the tick's overshoot to it).
static func restart_cooldown(st: Dictionary) -> float:
	if String(st.kind) == "buff":
		return maxf(float(st.duration), float(st.buff_cooldown))
	return float(st.cooldown)


## Horizontal reach in px from the player of a resolved skill `st` (Loadout.stats), the one number the bot reads to
## decide how close an attack needs it: a projectile or nearest-rule skill its range, a box skill its far edge (area
## cards included, the facing side), 0 for anything that is not an attack (buffs, manual skills, status-only and heal
## casts). One switch on the cast rule: weapon_reach is the held weapon's swing reach (BasicAttack.reach, the same number
## the basic attack engages at), range_around the level's `range` around the body.
static func reach_of(st: Dictionary, world: RunWorld) -> float:
	if String(st.kind) == "buff" or String(st.damage_type) == "none":
		return 0.0
	match String(st.cast_rule):
		"", "nearest", "range_around":
			return maxf(float(st.range), 0.0)
		"weapon_reach":
			return maxf(world.basic.reach(world), 0.0)
		"box":
			if not bool(st.has_box):
				return 0.0
			return maxf(-(st.box as Rect2).position.x, 0.0)
	return 0.0


## Cached resolved stats of `key` (refreshed when the loadout changed).
func stats_of(world: RunWorld, key: String) -> Dictionary:
	if world.loadout.version != _version:
		_stats.clear()
		_version = world.loadout.version
	if not _stats.has(key):
		_stats[key] = world.loadout.stats(key)
	return _stats[key]


## Whether `key` was ready with a target but short of MP at its latest cast scan (cleared by casting or losing it).
func is_waiting_mp(key: String) -> bool:
	return _shortages.has(key)


## Advances cooldowns and fires the oldest affordable ready skill with a target.
func step(dt: float, world: RunWorld) -> void:
	tick_cooldowns(dt, world)
	if world.can_cast():
		cast_ready(dt, world)


## Counts down every active skill, including while casting is blocked.
func tick_cooldowns(dt: float, world: RunWorld) -> void:
	fired_this_tick = false
	waiting_mp = false
	for key: String in world.loadout.order:
		if world.loadout.book.is_active(key):
			cooldowns[key] = float(cooldowns.get(key, 0.0)) - dt


## Fires one affordable skill, oldest-ready first; learned order breaks ties. Short MP never restarts cooldowns.
func cast_ready(dt: float, world: RunWorld) -> void:
	var lo := world.loadout
	var ready: Array[String] = []
	var held := world.held_weapon_family()
	for key: String in lo.order:
		if not lo.book.is_active(key):
			continue
		if not lo.book.usable_with(key, held):
			# The held weapon cannot use it (spec #151, #156): not considered, its cooldown keeps running, and it
			# resumes on the first tick a matching weapon is held again.
			_shortages.erase(key)
			continue
		if not world.buffs.has(key) and float(cooldowns.get(key, 0.0)) <= 1e-6 \
				and String(stats_of(world, key).cast_rule) != "manual":
			ready.append(key)
	ready.sort_custom(func(a: String, b: String) -> bool:
		var ca := float(cooldowns.get(a, 0.0))
		var cb := float(cooldowns.get(b, 0.0))
		return ca < cb if ca != cb else lo.order.find(a) < lo.order.find(b))
	for key: String in ready:
		var cd := float(cooldowns.get(key, 0.0))
		var st := stats_of(world, key)
		var origin := world.cast_origin()
		var is_buff := String(st.kind) == "buff"
		# has_target gives admission's answer without building and sorting the target list (issue #146): a ready skill
		# without a target, or short of MP, never needs the list. Only a skill about to cast is admitted in full.
		if not has_target(world, key, st, origin):
			_shortages.erase(key)
			continue
		if not world.can_pay_hp(int(st.hp_cost)):
			# Slash Blast pays HP too and never casts when that would leave 0 HP: not an MP shortage, nothing is spent.
			_shortages.erase(key)
			continue
		if not world.mp_affordable(int(st.mp_cost)):
			waiting_mp = true
			if not _shortages.has(key):
				world.emit("mp_short", {"skill": key, "skill_id": int(st.skill_id), "required_mp": int(st.mp_cost),
					"mp": int(world.player_state.mp)})
			_shortages[key] = true
			continue
		var plan := _admit_cast(world, key, st, origin)  # has_target said yes, so admission does too
		world.spend_mp(int(st.mp_cost))
		world.spend_hp(int(st.hp_cost))
		_shortages.erase(key)
		cooldowns[key] = restart_cooldown(st) if is_buff else maxf(cd, -dt) + restart_cooldown(st)
		cooldown_totals[key] = cooldowns[key]
		_resolve_cast(world, key, st, origin, plan)
		break


## Whether ready skill `key` (resolved stats `st`) would be admitted from `origin` now: exactly
## `not _admit_cast(...).is_empty()`, but it only counts targets (up to what admission needs) instead of collecting and
## ordering them. cast_ready uses it while the skill is short of MP, when the targets themselves are never used.
func has_target(world: RunWorld, key: String, st: Dictionary, origin: Vector2) -> bool:
	match String(st.cast_rule):
		"", "nearest":
			if String(st.kind) == "buff":
				if not world.can_start_buff(key, st):
					return false
				if float(st.duration) > 0.0:
					return true
			return _any_target(world, origin, float(st.range), int(st.count))
		"box":
			var need := maxi(1, int(st.cast_params.get("min_targets", 1)))
			return bool(st.has_box) and world.skill_box_count(st.box, need) >= need
		"crowd":
			var need := maxi(1, int(st.cast_params.get("min_targets", 1)))
			return bool(st.has_box) and world.skill_box_count(st.box, need, func(slot: int) -> bool:
				return world.swarm.can_slow_cast(slot, _slow_serial)) >= need
		"weapon_reach":
			var box := world.basic.envelope(world)
			return world.skill_box_count(box, 1) > 0 or world.skill_box_count(box, 1, Callable(),
				PackedByteArray(), -world.player.facing) > 0
		"range_around":
			return _any_target(world, origin, float(st.range), strike_count(st))
		"hp_or_undead":
			var heal: Dictionary = world.book.def(key).get("heal", {})
			if float(world.player_state.hp) < float(world.player_state.max_hp) * float(heal.get("hp_threshold", 0.0)):
				return true
			if not bool(st.has_box):
				return false
			# The undead filter of _admit_hp_or_undead as a mask over mob kinds (no Callable per body).
			var kinds: Array = world.swarm.kinds
			_undead.resize(kinds.size())
			var any := false
			for k in kinds.size():
				_undead[k] = 1 if (kinds[k] as MobKind).undead else 0
				any = any or _undead[k] != 0
			return any and world.skill_box_count(st.box, 1, Callable(), _undead) >= 1
	return false


func _admit_cast(world: RunWorld, key: String, st: Dictionary, origin: Vector2) -> Dictionary:
	match String(st.cast_rule):
		"", "nearest":
			return _admit_nearest(world, key, st, origin)
		"box":
			return _admit_box(world, st)
		"crowd":
			return _admit_crowd(world, st)
		"weapon_reach":
			return _admit_weapon_reach(world)
		"range_around":
			return _admit_range_around(world, st, origin)
		"hp_or_undead":
			return _admit_hp_or_undead(world, key, st)
		"manual":
			return {}
	return {}


func _admit_nearest(world: RunWorld, key: String, st: Dictionary, origin: Vector2) -> Dictionary:
	if String(st.kind) == "buff":
		if not world.can_start_buff(key, st):
			return {}
		if float(st.duration) > 0.0:
			return {"go": true}
	if _find_targets(world, origin, float(st.range), int(st.count)) == 0:
		return {}
	return {"targets": _tgt.duplicate()}


## Weapon-reach rule (Warrior Power Strike): the live mobs inside the held weapon's swing envelope (BasicAttack.envelope),
## nearest first. The player turns in every movement state, so both sides are asked and the side with the nearer first
## target wins (the current facing on a tie). The plan carries the side to face before casting; a walking or airborne
## player's held direction sets its facing again on the next motion step, so the turn lasts for the cast (tier C).
func _admit_weapon_reach(world: RunWorld) -> Dictionary:
	var box := world.basic.envelope(world)
	if not box.has_area():
		return {}
	var sides: Array[int] = [world.player.facing, -world.player.facing]
	var origin := world.cast_origin()
	var best := PackedInt32Array()
	var best_side := 0
	for side in sides:
		var found := world.skill_box_targets(box, Callable(), side)
		if found.is_empty():
			continue
		if best.is_empty() or world.targets_before(found[0], world.mob_center(found[0]).distance_squared_to(origin),
				best[0], world.mob_center(best[0]).distance_squared_to(origin)):
			best = found
			best_side = side
	if best.is_empty():
		return {}
	return {"targets": best, "facing": best_side}


## Range-around rule (Warrior Slash Blast): the nearest live mobs whose body centre is within the level's `range` of the
## player's body, up to the skill's mob count; bosses first (RunWorld.targets_before).
func _admit_range_around(world: RunWorld, st: Dictionary, origin: Vector2) -> Dictionary:
	if _find_targets(world, origin, float(st.range), strike_count(st)) == 0:
		return {}
	return {"targets": _tgt.duplicate()}


func _admit_box(world: RunWorld, st: Dictionary) -> Dictionary:
	if not bool(st.has_box):
		return {}
	var targets := world.skill_box_targets(st.box)
	# tier C: a box cast defaults to one eligible target; skill data may require a crowd.
	if targets.size() < maxi(1, int(st.cast_params.get("min_targets", 1))):
		return {}
	return {"targets": targets}


func _admit_hp_or_undead(world: RunWorld, key: String, st: Dictionary) -> Dictionary:
	var targets := PackedInt32Array()
	if bool(st.has_box):
		targets = world.skill_box_targets(st.box, func(slot: int) -> bool: return world.swarm.mob_kind(slot).undead)
	var heal: Dictionary = world.book.def(key).get("heal", {})
	var injured := float(world.player_state.hp) < float(world.player_state.max_hp) * float(heal.get("hp_threshold", 0.0))
	return {"targets": targets} if injured or not targets.is_empty() else {}


func _resolve_cast(world: RunWorld, key: String, st: Dictionary, origin: Vector2, plan: Dictionary) -> void:
	var targets: PackedInt32Array = plan.get("targets", PackedInt32Array())
	if String(st.cast_rule) in ["", "nearest"] and not targets.is_empty() and String(st.kind) != "buff":
		world.face_toward(world.mob_center(targets[0]).x)
	elif String(st.cast_rule) == "weapon_reach":
		world.player.facing = int(plan.facing) # admitted on that side, so it is the nearest mob's side
	elif String(st.cast_rule) == "range_around" and not targets.is_empty():
		world.face_toward(world.mob_center(targets[0]).x, true)
	# A moving attack (7.9) faces the mob it is aimed at in every movement state, then moves away from it or toward it.
	var disp: Dictionary = st.displacement
	var moves := not disp.is_empty() and String(st.kind) != "buff" and float(disp.distance) > 0.0
	var side := 0
	if moves:
		if not targets.is_empty():
			world.face_toward(world.mob_center(targets[0]).x, true)
		var toward := world.player.facing
		if not targets.is_empty() and absf(world.mob_center(targets[0]).x - world.player.pos.x) > 0.5:
			toward = 1 if world.mob_center(targets[0]).x > world.player.pos.x else -1
		side = toward if String(disp.direction) == "toward" else -toward
	var when := String(disp.get("when", "")) if moves else ""
	casts += 1
	fired_this_tick = true
	if String(st.cast_rule) in ["", "nearest"] and String(st.kind) == "buff":
		world.start_buff(key, st)
	# The cast event's pos is where the cast begins, before any displacement.
	world.emit("cast", {"skill": key, "skill_id": int(st.skill_id), "level": int(st.level),
		"pos": world.player.pos, "facing": world.player.facing, "action": String(st.action), "effect": String(st.effect)})
	world.start_action(String(st.action), float(st.action_time), false, float(st.speed_factor))
	var start := world.player.pos
	# `during` on a projectile skill has no sweep to resolve: the shots fly after the move, like `before`.
	var charge := when == "during" and String(st.kind) != "projectile"
	if when == "before" or when == "during":
		world.displace_player(side, float(disp.distance))
	if charge:
		_resolve_charge(world, st, start)
	else:
		match String(st.cast_rule):
			"box", "weapon_reach", "range_around":
				_resolve_instant_targets(world, st, targets, strike_count(st), int(st.attack_count),
					world.visual_index(String(st.hit)))
			"crowd":
				_resolve_crowd(world, key, st, targets)
			"hp_or_undead":
				_resolve_hp_or_undead(world, key, st, targets)
			"", "nearest":
				if String(st.kind) != "buff":
					_resolve_nearest(world, key, st, origin, targets)
	if when == "after":
		world.displace_player(side, float(disp.distance))


## A charge (displacement `during`): the character has already moved from `start` to where the terrain let it stop; it
## strikes up to the skill's mob count among the live mobs inside the swept path, bosses first then nearest to where
## the charge began. The path is the skill's attack box (the player's body without one) at the start and at the end,
## and everything between: a mob that triggered the cast is still struck when the charge stops short of it, and a
## cast whose admitted mobs lie outside the path strikes nothing (tier C).
func _resolve_charge(world: RunWorld, st: Dictionary, start: Vector2) -> void:
	var local: Rect2 = st.box if bool(st.has_box) else world.body
	if bool(st.has_box) and world.player.facing > 0:
		local.position.x = -local.end.x  # canonical boxes face left
	var at_start := Rect2(local.position + start, local.size)
	var at_end := Rect2(local.position + world.player.pos, local.size)
	var swept := world.skill_rect_targets(at_start.merge(at_end), start - Vector2(0.0, world.cast_height),
		int(st.mob_count))
	_resolve_instant_targets(world, st, swept, int(st.mob_count), int(st.attack_count),
		world.visual_index(String(st.hit)))


func _admit_crowd(world: RunWorld, st: Dictionary) -> Dictionary:
	if not bool(st.has_box):
		return {}
	var targets := world.skill_box_targets(st.box, func(slot: int) -> bool:
		return world.swarm.can_slow_cast(slot, _slow_serial))
	# tier C: survivor crowd threshold lives in the skill's cast block, before MP payment.
	if targets.size() < maxi(1, int(st.cast_params.get("min_targets", 1))):
		return {}
	return {"targets": targets}


func _resolve_crowd(world: RunWorld, key: String, st: Dictionary, targets: PackedInt32Array) -> void:
	_slow_serial += 1
	var params := {"x": world.book.canonical(key, int(st.level), "x"),
		"time": world.book.canonical(key, int(st.level), "time")}
	for i in mini(strike_count(st), targets.size()):
		world.swarm.apply_slow_cast(targets[i], _slow_serial, params, world.events)


func _resolve_instant_targets(world: RunWorld, st: Dictionary, targets: PackedInt32Array,
		limit: int, lines: int, hv: int) -> void:
	for i in mini(limit, targets.size()):
		var slot := targets[i]
		for line in lines:
			# Both queries return valid slots. Keep nearest's active-mask check; is_live adds only bounds checks.
			if world.swarm.active[slot] == 0:
				break
			world.hit_mob(slot, st, hv)


func _resolve_hp_or_undead(world: RunWorld, key: String, st: Dictionary, targets: PackedInt32Array) -> void:
	var heal: Dictionary = world.book.def(key).get("heal", {})
	var power := world.book.canonical(key, int(st.level), String(heal.get("field", "hp")))
	var lo := world.loadout
	var luk := float(world.player_state.luk)
	var recovery := CombatMath.heal_recovery_range(lo.int_stat, luk, lo.matk, power)
	world.restore_player("hp", floori(CombatMath.roll_range(recovery, world.rng)), key)
	var damage := CombatMath.heal_damage_range(lo.int_stat, luk, lo.matk, power, targets.size() + 1)
	var hit := st.duplicate()
	hit.damage_min = damage.x
	hit.damage_max = damage.y
	hit.magic = true
	hit.damage_type = "magic"
	hit.defense = "mdd"
	hit.element = "h" # tier B: Heal's holy undead attack; canonical node has no elemAttr, research/cleric-heal.md.
	var hv := world.visual_index(String(st.hit))
	# tier C: ticket #57 requires every undead in the box, without the original six-target cap.
	for slot: int in targets:
		world.hit_mob(slot, hit, hv)


## Fills the target buffer with up to `want` distinct live mobs whose body centre is within `rng_px` of `origin`,
## scheduled bosses first, then nearest, then slot (RunWorld.targets_before). Returns how many.
func _find_targets(world: RunWorld, origin: Vector2, rng_px: float, want: int) -> int:
	var s := world.swarm
	var n := world.mob_grid.query_radius(origin, rng_px + world.body_pad, _buf)
	_tgt.resize(0)
	_tgt_d.resize(0)
	var r2 := rng_px * rng_px
	for c in n:
		var m := _buf[c]
		if s.active[m] == 0:
			continue
		var ctr := world.mob_center(m)
		var d2 := ctr.distance_squared_to(origin)
		if d2 > r2:
			continue
		var at := _tgt.size()
		while at > 0 and world.targets_before(m, d2, _tgt[at - 1], _tgt_d[at - 1]):
			at -= 1
		if at >= want:
			continue
		_tgt.insert(at, m)
		_tgt_d.insert(at, d2)
		if _tgt.size() > want:
			_tgt.resize(want)
			_tgt_d.resize(want)
	return _tgt.size()


## Whether _find_targets(world, origin, rng_px, want) would find at least one target. It first looks at only the
## first ANY_PROBE candidates of the same grid query (usually one of them is in range) and reads the whole query only
## when none is.
func _any_target(world: RunWorld, origin: Vector2, rng_px: float, want: int) -> bool:
	if want <= 0:
		return false
	var s := world.swarm
	var r2 := rng_px * rng_px
	var limit := ANY_PROBE
	while true:
		var n := world.mob_grid.query_radius(origin, rng_px + world.body_pad, _buf, limit)
		for c in n:
			var m := _buf[c]
			if s.active[m] != 0 and world.mob_center(m).distance_squared_to(origin) <= r2:
				return true
		if limit == 0 or n < limit:
			return false
		limit = 0
	return false


func _resolve_nearest(world: RunWorld, key: String, st: Dictionary, origin: Vector2, targets: PackedInt32Array) -> void:
	var n := targets.size()
	var hv := world.visual_index(String(st.hit))
	if String(st.kind) == "projectile":
		var vis := world.visual_index(String(st.ball))
		var count := int(st.count)
		var speed := float(st.speed)
		for k in count:
			var m := targets[k % n]
			var reuse := floorf(float(k) / float(n))
			var aim := world.mob_center(m) + Vector2(0.0, REUSE_SPREAD * reuse * (1.0 if k % 2 == 0 else -1.0))
			var start := world.shot_origin(aim)
			var dir := (aim - start).normalized()
			if dir == Vector2.ZERO or signf(aim.x - start.x) != signf(aim.x - origin.x):
				# A target inside the reach of the hand: fly straight at it from the body instead.
				start = origin
				dir = (aim - origin).normalized()
			if dir == Vector2.ZERO:
				dir = Vector2(world.player.facing, 0.0)
			world.projectiles.spawn({
				"x": start.x, "y": start.y, "vx": dir.x * speed, "vy": dir.y * speed,
				"range": float(st.range), "radius": float(st.radius), "visual": vis, "hit_visual": hv,
				"rotate": bool(st.rotate), "dmg_min": float(st.damage_min), "dmg_max": float(st.damage_max),
				"magic": bool(st.magic), "crit": float(st.crit), "crit_mult": float(st.crit_mult),
				"damage_type": String(st.damage_type), "damage_pct": float(st.damage_pct),
				"player_level": int(st.player_level), "crit_damage_bonus": float(st.crit_damage_bonus),
				"pierce": int(st.pierce), "skill": key, "level": int(st.level), "element": String(st.element),
			})
	else:
		_resolve_instant_targets(world, st, targets, int(st.count), int(st.attack_count), hv)
