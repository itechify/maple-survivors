class_name ChainCast
extends RefCounted
## The chain cast rule (`cast.rule == "chain"`, M12, spec #319): the skill strikes one monster, then jumps from body
## to body to the nearest monster it has not struck yet, up to its mob_count, one hit each. Generic: any skill whose cast
## block is {"rule": "chain", "acquire": px, "hop": px, "min_targets": n} uses it (Chain Lightning today, Corsair or
## others later); there is no skill ID in this file. SkillRunner only dispatches to it.
##
## The rule is deterministic and draws no random numbers: selection is distance, then slot. It reads the resolved stats
## (Loadout.stats) of the skill: `range` is the acquisition radius (the block's `acquire`, widened by the `range`
## modifier), `area` scales the hop distance, `mob_count` is the chain length (canonical mobCount plus `count`
## modifiers) and `attack_count` the damage lines per link. Damage is unchanged along the chain and goes through
## RunWorld.hit_mob, so defence, crit, immunity and statuses are unified with every other rule.
##
## Admission: the head is a live monster whose body centre is within `acquire` px of the caster (a scheduled boss first,
## then nearest, then slot: RunWorld.targets_before). Each further link is the nearest unhit live monster to the
## previous link's body centre within `hop` px (distance, then slot; bosses get no priority on a hop). Fewer than
## mob_count links is fine. A distance exactly equal to `acquire` or `hop` is in range.

## How many candidates has_target looks at before it reads the whole grid query (a monster is usually in reach).
const ANY_PROBE := 8 # tier C: query optimization, does not change admission.


## Ball animation paths in variant order for presentation and preloading.
static func ball_paths(definition: Dictionary) -> Array:
	return definition.get("chain", {}).get("ball", [])


## Default acquisition range of a chain definition, before Loadout range modifiers.
static func base_range(cast: Dictionary) -> float:
	return float(cast.get("acquire", 0.0))

static var _buf := PackedInt32Array()


## The resolved acquisition radius in px of chain skill stats `st`.
static func acquire_of(st: Dictionary) -> float:
	return maxf(float(st.range), 0.0)


## The resolved hop distance in px of chain skill stats `st` (the block's `hop` times the `area` modifier).
static func hop_of(st: Dictionary) -> float:
	return maxf(float(st.cast_params.get("hop", 0.0)) * float(st.area), 0.0)


## The cast plan from `origin` (the caster's body): {"targets": the chain in order, "points": the bolt's polyline
## (caster hand, then each link's body centre)}, or {} when nothing is in reach or fewer than `min_targets` monsters
## would be struck.
static func admit(world: RunWorld, st: Dictionary, origin: Vector2) -> Dictionary:
	var head := _head(world, origin, acquire_of(st))
	if head < 0:
		return {}
	var chain := PackedInt32Array([head])
	var centres := PackedVector2Array([world.mob_center(head)])
	var hop := hop_of(st)
	var want := maxi(1, int(st.mob_count))
	while chain.size() < want:
		var next := _nearest_unhit(world, centres[centres.size() - 1], hop, chain)
		if next < 0:
			break
		chain.append(next)
		centres.append(world.mob_center(next))
	if chain.size() < maxi(1, int(st.cast_params.get("min_targets", 1))):
		return {}
	var points := PackedVector2Array([world.shot_origin(centres[0])])
	points.append_array(centres)
	return {"targets": chain, "points": points}


## Whether admit() would return a plan: exactly `not admit(...).is_empty()`, but with the common single-target
## requirement it only looks for a head and builds no chain.
static func has_target(world: RunWorld, st: Dictionary, origin: Vector2) -> bool:
	if maxi(1, int(st.cast_params.get("min_targets", 1))) > 1:
		return not admit(world, st, origin).is_empty()
	return _any_within(world, origin, acquire_of(st))


## Strikes the planned chain: `attack_count` lines per link through RunWorld.hit_mob, all now, in order, skipping a
## monster that is gone by its turn. Emits `skill_chain` first, with the polyline through the links still standing.
static func resolve(world: RunWorld, key: String, st: Dictionary, plan: Dictionary, hv: int) -> void:
	var targets: PackedInt32Array = plan.targets
	var points := PackedVector2Array([(plan.points as PackedVector2Array)[0]])
	for i in targets.size():
		if world.swarm.active[targets[i]] != 0:
			points.append((plan.points as PackedVector2Array)[i + 1])
	world.emit("skill_chain", {"skill": key, "skill_id": int(st.skill_id), "points": points})
	for m in targets:
		for line in int(st.attack_count):
			if world.swarm.active[m] == 0:
				break
			world.hit_mob(m, st, hv)


## The head: the live monster within `reach` of `origin` that RunWorld.targets_before puts first, or -1.
static func _head(world: RunWorld, origin: Vector2, reach: float) -> int:
	var best := -1
	var best_d2 := 0.0
	var r2 := reach * reach
	var n := _query(world, origin, reach, 0)
	for c in n:
		var m := _buf[c]
		if world.swarm.active[m] == 0:
			continue
		var d2 := world.mob_center(m).distance_squared_to(origin)
		if d2 > r2:
			continue
		if best < 0 or world.targets_before(m, d2, best, best_d2):
			best = m
			best_d2 = d2
	return best


## The nearest live monster to `from` within `hop` that is not in `chain` (distance, then slot), or -1.
static func _nearest_unhit(world: RunWorld, from: Vector2, hop: float, chain: PackedInt32Array) -> int:
	var best := -1
	var best_d2 := 0.0
	var r2 := hop * hop
	var n := _query(world, from, hop, 0)
	for c in n:
		var m := _buf[c]
		if world.swarm.active[m] == 0 or chain.has(m):
			continue
		var d2 := world.mob_center(m).distance_squared_to(from)
		if d2 > r2:
			continue
		if best < 0 or d2 < best_d2 or (d2 == best_d2 and m < best):
			best = m
			best_d2 = d2
	return best


## Whether any live monster's body centre is within `reach` of `origin`; reads the first ANY_PROBE grid candidates and
## the whole query only when none of them qualifies.
static func _any_within(world: RunWorld, origin: Vector2, reach: float) -> bool:
	var r2 := reach * reach
	var limit := ANY_PROBE
	while true:
		var n := _query(world, origin, reach, limit)
		for c in n:
			var m := _buf[c]
			if world.swarm.active[m] != 0 and world.mob_center(m).distance_squared_to(origin) <= r2:
				return true
		if limit == 0 or n < limit:
			return false
		limit = 0
	return false


## Grid candidates (feet positions) for a centre-distance query: the radius is padded by the largest body extent.
static func _query(world: RunWorld, at: Vector2, reach: float, limit: int) -> int:
	if _buf.size() < 64:
		_buf.resize(64)
	return world.mob_grid.query_radius(at, reach + world.body_pad, _buf, limit)
