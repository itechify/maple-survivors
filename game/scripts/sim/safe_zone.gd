class_name SafeZone
extends RefCounted
## The safe zone (M18, spec #425 SH4, docs/GAME_DESIGN.md 7.132): a placed ground box in which every hit the character takes
## is negated for the zone's life. Generic: any skill whose cast block is {"rule": "safe_zone", "min_mobs": n, "mob_within": px}
## and whose definition has a {"safe_zone": {"duration": s}} block uses it (Smokescreen is the first user); there is no skill ID
## in this file. SkillRunner only dispatches to it, RunWorld owns one as `safe_zones`.
##
## Place: the box is the skill's canonical `lt` / `rb` at its level scaled by the `area` modifier (Loadout.stats `box`), anchored
## at the cast origin in world space and fixed there (it does not follow the caster, and has no facing: the WZ box is symmetric).
## One zone per skill key; a recast replaces it. Life: `safe_zone.duration` x the `zone_time` modifier, read at placement (a
## placed zone ignores a later modifier). Admission: at least `min_mobs` living monsters within `mob_within` px of the cast
## origin and the character not inside a live zone of that skill, otherwise the skill waits with its cooldown at 0.
## Negation: RunWorld.take_hit asks `negate` right after its Hidden safety net; a hit whose target (the body centre) is inside
## a live zone does nothing: no damage, no avoid roll, no hit window, no knock-back, no `player_hit`; one `hit_negated` event.
## Statuses the monsters apply by skill are not hits and are not touched here.
##
## Pure: no nodes, no clock but the fixed `dt`, no RNG draw. Events: `safe_zone_started`, `safe_zone_ended`, `hit_negated`.

## A zone is over once this little life is left (float noise of a 6 s life counted down in 1/60 s ticks). tier C: ours.
const LIFE_EPS := 1e-6

## One {skill, skill_id, rect (world, top-left and size), left, total} per live zone, oldest first.
var _zones: Array[Dictionary] = []
var _buf := PackedInt32Array()


func _init() -> void:
	_buf.resize(128) # a starting capacity only: query_radius grows it, so the size changes no result


## Whether any zone is live.
func is_empty() -> bool:
	return _zones.is_empty()


## A copy of the live zones: {skill, skill_id, rect, left, total} in placement order.
func snapshot() -> Array:
	return _zones.duplicate(true)


## The live zone of `key`'s world rect, or an empty Rect2 when it has none.
func rect_of(key: String) -> Rect2:
	var at := _index_of(key)
	return Rect2() if at < 0 else _zones[at].rect as Rect2


## Whether a cast of resolved stats `st` (skill `key`) from `origin` is admitted now: the box exists, at least the block's
## `min_mobs` living monsters have a body centre within `mob_within` px of `origin`, and the character is not inside a live
## zone of `key`.
func admits(world: RunWorld, key: String, st: Dictionary, origin: Vector2) -> bool:
	if not bool(st.has_box) or float(st.get("safe_zone_duration", 0.0)) <= 0.0:
		return false
	if _inside(key, world.player_body_center()):
		return false
	var need := maxi(1, int(st.cast_params.get("min_mobs", 1)))
	var reach := float(st.cast_params.get("mob_within", 0.0))
	return _count_within(world, origin, reach, need) >= need


## Places the zone of `key` (resolved stats `st`) anchored at `origin`, replacing a live one of the same skill
## (`safe_zone_ended` reason `replaced`), and emits `safe_zone_started`. Returns false, placing nothing, for a skill with no
## box or no life.
func place(world: RunWorld, key: String, st: Dictionary, origin: Vector2) -> bool:
	var total := float(st.get("safe_zone_duration", 0.0))
	if not bool(st.has_box) or total <= 0.0:
		return false
	var at := _index_of(key)
	if at >= 0:
		_end(world, at, "replaced")
	var box: Rect2 = st.box
	var zone := {"skill": key, "skill_id": int(st.skill_id), "rect": Rect2(origin + box.position, box.size),
		"left": total, "total": total}
	_zones.append(zone)
	world.emit("safe_zone_started", {"skill": key, "skill_id": int(st.skill_id), "pos": (zone.rect as Rect2).position,
		"size": box.size, "duration": total})
	return true


## Counts every zone's life down by `dt` and ends the ones that ran out (`expired`).
func step(dt: float, world: RunWorld) -> void:
	var i := 0
	while i < _zones.size():
		_zones[i].left = float(_zones[i].left) - dt
		if float(_zones[i].left) <= LIFE_EPS:
			_end(world, i, "expired")
		else:
			i += 1


## Whether the point `pos` is inside a live zone (edges count as inside).
func negates(pos: Vector2) -> bool:
	return _zone_at(pos) >= 0


## RunWorld.take_hit's question: when `pos` (the character's body centre) is inside a live zone, appends one `hit_negated
## {skill, source}` (the first such zone in placement order; `source` is the hit's `source_kind`, "other" without one) and
## returns true, else false and nothing.
func negate(world: RunWorld, pos: Vector2, source: Dictionary) -> bool:
	var at := _zone_at(pos)
	if at < 0:
		return false
	world.emit("hit_negated", {"skill": String(_zones[at].skill), "source": String(source.get("source_kind", "other"))})
	return true


## Ends every live zone with `reason` (`transferred` on a map change, `died`), oldest first.
func clear(world: RunWorld, reason: String) -> void:
	while not _zones.is_empty():
		_end(world, 0, reason)


## Load errors of the safe zone blocks of a skills file (`{"skills": {key: definition}}`): a skill with the `safe_zone` cast
## rule has a `safe_zone.duration` above 0, a `min_mobs` of 1 or more and a `mob_within` above 0, and deals no damage; a
## `safe_zone` block on another rule is an error.
static func errors(skills_file: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var skills: Variant = skills_file.get("skills")
	if not skills is Dictionary:
		return out
	for key: Variant in skills:
		var definition: Variant = skills[key]
		if not definition is Dictionary:
			continue
		var cast: Variant = definition.get("cast", {})
		var rule := String(cast.get("rule", "")) if cast is Dictionary else ""
		if rule != "safe_zone":
			if definition.has("safe_zone"):
				out.append("skill '%s': a safe_zone block needs the cast rule \"safe_zone\"" % key)
			continue
		var block: Variant = definition.get("safe_zone")
		if not block is Dictionary:
			out.append("skill '%s': the safe_zone cast rule needs a safe_zone object" % key)
			continue
		var duration: Variant = block.get("duration")
		if not (duration is float or duration is int) or float(duration) <= 0.0:
			out.append("skill '%s': safe_zone.duration must be a number above 0" % key)
		var min_mobs: Variant = cast.get("min_mobs", 1)
		if not (min_mobs is float or min_mobs is int) or float(min_mobs) < 1.0:
			out.append("skill '%s': cast.min_mobs must be a number of 1 or more" % key)
		var within: Variant = cast.get("mob_within")
		if not (within is float or within is int) or float(within) <= 0.0:
			out.append("skill '%s': cast.mob_within must be a number above 0" % key)
		if String(definition.get("damage", "none")) != "none":
			out.append("skill '%s': a safe_zone skill deals no damage (damage \"none\")" % key)
	return out


func _index_of(key: String) -> int:
	for i in _zones.size():
		if String(_zones[i].skill) == key:
			return i
	return -1


## The index of the first (oldest) live zone containing `pos`, or -1.
func _zone_at(pos: Vector2) -> int:
	for i in _zones.size():
		if _contains(_zones[i].rect as Rect2, pos):
			return i
	return -1


func _inside(key: String, pos: Vector2) -> bool:
	var at := _index_of(key)
	return at >= 0 and _contains(_zones[at].rect as Rect2, pos)


static func _contains(rect: Rect2, pos: Vector2) -> bool:
	return pos.x >= rect.position.x and pos.x <= rect.end.x and pos.y >= rect.position.y and pos.y <= rect.end.y


func _end(world: RunWorld, at: int, reason: String) -> void:
	var zone: Dictionary = _zones[at]
	_zones.remove_at(at)
	world.emit("safe_zone_ended", {"skill": String(zone.skill), "reason": reason})


## Living monsters whose body centre is within `reach` px of `origin`, counting no further than `limit`.
func _count_within(world: RunWorld, origin: Vector2, reach: float, limit: int) -> int:
	var swarm := world.swarm
	var r2 := reach * reach
	var n := world.mob_grid.query_radius(origin, reach + world.body_pad, _buf)
	var found := 0
	for c in n:
		var m := _buf[c]
		if swarm.is_live(m) and world.mob_center(m).distance_squared_to(origin) <= r2:
			found += 1
			if found >= limit:
				break
	return found
