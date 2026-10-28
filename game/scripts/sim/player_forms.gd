class_name PlayerForms
extends RefCounted
## Timed caster stances and their admitted sub-skills. Owns no clock, RNG, assets or class-specific rules.

## Effect key -> static handler. Later class tickets add handlers here, never in SkillRunner.
static var EFFECTS := {"element": _element, "damage": _damage}
## tier C: nearby elemental arbitration radius, independent of a form's admission radius.
const PREFERRED_RADIUS := 400.0
var _active: Array[Dictionary] = []

## Whether no running stance occupies this definition's exclusion group.
func admits(world: RunWorld, key: String) -> bool:
	var group := String(world.book.def(key).get("form", {}).get("exclusive_group", ""))
	for state in _active:
		if String(state.group) == group:
			return false
	return true

## Starts a snapshot window, replacing its group even for callers bypassing normal admission.
func start(world: RunWorld, key: String, stats: Dictionary) -> void:
	var block: Dictionary = world.book.def(key).form
	for state in _active.duplicate():
		if String(state.group) == String(block.exclusive_group):
			_end(world, state, "replaced")
	var st := stats.duplicate(true)
	st.duration = float(block.duration) * world.loadout.skill_stat(key, "form_time", 1.0)
	var effects: Dictionary = block.get("effects", {}).duplicate(true)
	if effects.has("damage"):
		effects.damage = world.book.canonical(key, int(st.level), String(effects.damage.field), 100.0) / 100.0 \
			+ world.loadout.skill_stat(key, "form_power", 0.0)
	var subs: Array[Dictionary] = []
	for sub: Dictionary in block.get("subs", []):
		subs.append({"rule": sub.duplicate(true), "next": float(sub.first_after), "done": false})
	_active.append({"skill": key, "skill_id": int(st.skill_id), "group": String(block.exclusive_group),
		"remaining": float(st.duration), "age": 0.0, "rank": int(st.rank), "effects": effects, "subs": subs})
	world.buffs.start(key, st)
	world.emit("form_started", {"skill": key, "skill_id": int(st.skill_id),
		"element": String(effects.get("element", "")), "duration": float(st.duration)})

## Advances windows and due sub-skills. Rejected casts remain due until admitted or the window ends.
func step(dt: float, world: RunWorld) -> void:
	if world.state == RunWorld.DEAD:
		clear(world)
		return
	for state in _active.duplicate():
		state.remaining = maxf(0.0, float(state.remaining) - dt)
		state.age = float(state.age) + dt
		if float(state.remaining) <= 1e-6:
			_end(world, state, "expired")
			continue
		if not world.can_cast():
			continue
		for sub: Dictionary in state.subs:
			if bool(sub.done) or float(state.age) + 1e-6 < float(sub.next):
				continue
			var key := String(sub.rule.skill)
			# Inherit just the parent's skill-local damage and area. Resolve geometry through Loadout itself.
			var lo := world.loadout.clone()
			for stat: String in ["damage", "area"]:
				lo.add_skill_mod(key, stat, "mul", world.loadout.skill_stat(String(state.skill), stat, 1.0))
			var st := lo.stats(key, int(state.rank))
			var origin := world.cast_origin()
			if (world.is_hidden() and SkillRunner.is_attack(st)) or not world.can_pay_hp(int(st.hp_cost)) \
					or not world.runner.has_target(world, key, st, origin):
				continue
			var plan := world.runner.prepare_cast(world, key, st, origin)
			if plan.is_empty():
				continue
			st = begin_cast(world, key, world.meter.begin_cast(world, key, st))
			world.spend_hp(int(st.hp_cost))
			world.runner._resolve_cast(world, key, st, origin, plan)
			sub.done = bool(sub.rule.get("once", false))
			# No catch-up burst after a wait: the interval starts at the successful cast.
			sub.next = float(state.age) + float(sub.rule.get("interval", 0.0))

## Applies every active effect to a cast-local copy. Non-damaging casts remain untouched.
func begin_cast(_world: RunWorld, _key: String, stats: Dictionary) -> Dictionary:
	if _active.is_empty() or String(stats.damage_type) == "none":
		return stats
	var out := stats.duplicate()
	for state in _active:
		for effect: String in state.effects:
			if EFFECTS.has(effect):
				(EFFECTS[effect] as Callable).call(out, state.effects[effect])
	return out

## Selects the best admitted form per group; ready order breaks elemental-score ties.
func preferred(world: RunWorld, ready: Array[String]) -> Array[String]:
	var winners := {}
	var scores := {}
	for key in ready:
		var block: Dictionary = world.book.def(key).get("form", {})
		if block.is_empty() or not admits(world, key):
			continue
		var st := world.runner.stats_of(world, key)
		if not world.can_pay_hp(int(st.hp_cost)) or not world.runner.has_target(world, key, st, world.cast_origin()):
			continue
		var score := 0.0
		var element := String(block.get("effects", {}).get("element", ""))
		if not element.is_empty():
			for m in world.swarm.capacity():
				if world.swarm.active[m] != 0 and world.mob_center(m).distance_squared_to(world.cast_origin()) <= PREFERRED_RADIUS * PREFERRED_RADIUS:
					score += world.swarm.element_multiplier(m, element)
		var group := String(block.exclusive_group)
		if not winners.has(group) or score > float(scores[group]):
			winners[group] = key
			scores[group] = score
	var out: Array[String] = []
	for key in winners.values():
		out.append(String(key))
	return out

## Detached running-window state, including resolved effects and sub clocks.
func snapshot() -> Array:
	return _active.duplicate(true)

## Ends every window on death; map transfer deliberately never calls this.
func clear(world: RunWorld, reason: String = "died") -> void:
	for state in _active.duplicate():
		_end(world, state, reason)

func _end(world: RunWorld, state: Dictionary, reason: String) -> void:
	_active.erase(state)
	world.buffs.end(String(state.skill), world.events)
	world.emit("form_ended", {"skill": String(state.skill), "skill_id": int(state.skill_id), "reason": reason})

static func _element(stats: Dictionary, value: Variant) -> void:
	if String(stats.get("element", "")).is_empty():
		stats.element = String(value)

static func _damage(stats: Dictionary, value: Variant) -> void:
	for field: String in ["damage_min", "damage_max", "status_damage_mult"]:
		stats[field] = float(stats.get(field, 0.0)) * float(value)

## Definition errors, suitable for data-file tests and synthetic catalogs; no assets are required.
static func validation_errors(defs: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	for key: String in defs:
		var d: Dictionary = defs[key]
		if String(d.get("slot", "")) == "form_sub":
			var parents: Variant = d.get("form_sub_of", [])
			if parents is String:
				parents = [parents]
			if not parents is Array or parents.is_empty():
				errors.append("%s.form_sub_of needs parent form keys" % key)
			else:
				for parent: Variant in parents:
					if not defs.has(parent) or String(defs[parent].get("kind", "")) != "form":
						errors.append("%s.form_sub_of: unknown form %s" % [key, parent])
		if String(d.get("kind", "")) != "form":
			continue
		var block: Variant = d.get("form")
		if not block is Dictionary:
			errors.append("%s.form needs an object" % key)
			continue
		if not block.get("duration") is float and not block.get("duration") is int or float(block.get("duration", 0)) <= 0:
			errors.append("%s.form.duration must be positive seconds" % key)
		if not block.get("exclusive_group") is String or String(block.get("exclusive_group", "")).strip_edges().is_empty():
			errors.append("%s.form.exclusive_group must be nonempty" % key)
		var cast: Variant = d.get("cast", {})
		if not cast is Dictionary or String(cast.get("rule", "")) != "form" or float(cast.get("mob_within", 0)) <= 0:
			errors.append("%s.cast needs rule form and positive mob_within" % key)
		if String(d.get("damage", "")) != "none" or String(d.get("slot", "")) != "active":
			errors.append("%s: form needs damage none and slot active" % key)
		var effects: Variant = block.get("effects")
		if not effects is Dictionary:
			errors.append("%s.form.effects needs an object" % key)
		else:
			for effect: String in effects:
				if not EFFECTS.has(effect):
					errors.append("%s.form.effects.%s is unknown" % [key, effect])
				elif effect == "element" and (not effects[effect] is String or String(effects[effect]) not in ["f", "i", "l", "h", "s", "fs"]):
					errors.append("%s.form.effects.element needs an element code" % key)
				elif effect == "damage" and (not effects[effect] is Dictionary or not effects[effect].get("field") is String or String(effects[effect].get("field", "")).is_empty()):
					errors.append("%s.form.effects.damage needs a canonical field" % key)
		var subs: Variant = block.get("subs")
		if not subs is Array:
			errors.append("%s.form.subs needs an array" % key)
			continue
		for sub: Variant in subs:
			if not sub is Dictionary:
				errors.append("%s.form.subs entries must be objects" % key)
				continue
			var skill := String(sub.get("skill", ""))
			var child: Dictionary = defs.get(skill, {})
			var parents: Variant = child.get("form_sub_of", [])
			if String(child.get("slot", "")) != "form_sub" or not key in parents:
				errors.append("%s.form.subs: %s needs slot form_sub and form_sub_of parent" % [key, skill])
			if not sub.get("first_after") is float and not sub.get("first_after") is int or float(sub.get("first_after", -1)) < 0:
				errors.append("%s.form.subs.%s.first_after must be nonnegative seconds" % [key, skill])
			if not bool(sub.get("once", false)) and float(sub.get("interval", 0)) <= 0:
				errors.append("%s.form.subs.%s needs once or positive interval" % [key, skill])
	return errors
