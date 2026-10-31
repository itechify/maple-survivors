class_name PlayerForms
extends RefCounted
## Timed caster stances and their admitted sub-skills. Owns window lifecycle, effect dispatch and sub admission; no clock, RNG or assets.

## Effect records: optional resolve(world,key,stats,value), apply(stats,value), validate(value),
## on_start(world,state), on_end(world,state), absorb(world,state,amount). Missing hooks are no-ops.
## absorb returns remaining damage and may end its window through end(world,key,reason).
static var EFFECTS := {
	"element": {"apply": _element, "validate": _valid_element},
	"damage": {"resolve": _resolve_damage, "apply": _damage, "validate": _valid_damage},
}
## State effects (spec #384 C11): entries own state in the running window instead of editing a cast copy. Optional
## start(world,state,value) (after the window is appended), end(world,state,reason), absorb(world,state,amount) (as
## EFFECTS.absorb) and validate(value). `only_skills` and `art_variant` hold only a validator: FormRules reads their value.
static var STATE_EFFECTS := {
	"hull": PlayerHull.ENTRY,
	"only_skills": FormRules.ONLY_SKILLS,
	"art_variant": FormRules.ART_VARIANT,
}
## tier C: nearby elemental arbitration radius, independent of a form's admission radius.
const PREFERRED_RADIUS := 400.0
## The path token a skill definition writes where the element's art key goes (`hit/0/{art}`).
static var ART_INDEX := Elements.art_indices()
const ART_TOKEN := "{art}"
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
	var effects: Dictionary = block.get("effects", {}).duplicate(true)
	for effect: String in effects:
		var resolve: Callable = EFFECTS.get(effect, {}).get("resolve", Callable())
		if resolve.is_valid():
			effects[effect] = resolve.call(world, key, st, effects[effect])
	var subs: Array[Dictionary] = []
	for sub: Dictionary in block.get("subs", []):
		subs.append({"rule": sub.duplicate(true), "next": float(sub.first_after), "done": false, "version": -1, "stats": {}})
	var state := {"skill": key, "skill_id": int(st.skill_id), "group": String(block.exclusive_group),
		"remaining": float(st.duration), "age": 0.0, "rank": int(st.rank), "level": int(st.level), "effects": effects, "subs": subs}
	_active.append(state)
	_hooks("on_start", world, state)
	for effect: String in effects:
		var start_state: Callable = STATE_EFFECTS.get(effect, {}).get("start", Callable())
		if start_state.is_valid():
			start_state.call(world, state, effects[effect])
	world.buffs.start(key, st)
	var started := {"skill": key, "skill_id": int(st.skill_id),
		"element": String(effects.get("element", "")), "duration": float(st.duration)}
	if block.get("presentation", {}).has("mount"):
		started["mount"] = int(block.presentation.mount) # optional: only a form that names a mount carries it
	world.emit("form_started", started)

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
			if int(sub.version) != world.loadout.version:
				sub.stats = world.loadout.sub_stats(key, world.loadout.stats(String(state.skill)), int(state.rank))
				sub.version = world.loadout.version
			var st: Dictionary = sub.stats
			var origin := world.cast_origin()
			if (world.is_hidden() and not bool(sub.rule.get("ignores_hidden", false)) and SkillRunner.is_attack(st)) or not world.can_pay_hp(int(st.hp_cost)) \
					or not world.runner.has_target(world, key, st, origin):
				continue
			var plan := world.runner.prepare_cast(world, key, st, origin)
			if plan.is_empty():
				continue
			st = begin_cast(world, key, world.meter.begin_cast(world, key, st))
			world.spend_hp(int(st.hp_cost))
			world.runner.resolve_cast(world, key, st, origin, plan)
			if bool(sub.rule.get("ends_form", false)):
				end(world, String(state.skill), "consumed")
				break
			sub.done = bool(sub.rule.get("once", false))
			# No catch-up burst after a wait: the interval starts at the successful cast.
			sub.next = float(state.age) + float(sub.rule.get("interval", 0.0))

## Passes unmodified casts through; otherwise applies effects to a cast-local copy, then fills the `{art}` token of its hit and effect paths with the
## cast's element. Non-damaging casts remain untouched.
func begin_cast(world: RunWorld, key: String, stats: Dictionary) -> Dictionary:
	if String(stats.damage_type) == "none":
		return stats
	var out := stats
	if not _active.is_empty():
		out = stats.duplicate()
		for state in _active:
			for effect: String in state.effects:
				if EFFECTS.has(effect):
					var apply: Callable = EFFECTS[effect].get("apply", Callable())
					if apply.is_valid():
						apply.call(out, state.effects[effect])
		out = FormRules.art_variant(_active, world, key, out)
	for field: String in ["hit", "effect"]:
		if String(out.get(field, "")).contains(ART_TOKEN):
			if is_same(out, stats):
				out = stats.duplicate()
			out[field] = fill_art(String(out[field]), String(out.get("element", "")))
	return out

## The art key of `element` (0 for none or an element with no art row).
static func art_index(element: String) -> int:
	return Elements.art_index(element)

## `path` with its `{art}` token replaced by the art key of `element`.
static func fill_art(path: String, element: String) -> String:
	return path.replace(ART_TOKEN, str(art_index(element)))

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
	_hooks("on_end", world, state)
	for effect: String in state.effects:
		var end_state: Callable = STATE_EFFECTS.get(effect, {}).get("end", Callable())
		if end_state.is_valid():
			end_state.call(world, state, reason)
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
		if _seconds(block.get("duration")) <= 0:
			errors.append("%s.form.duration must be positive seconds" % key)
		if not block.get("exclusive_group") is String or String(block.get("exclusive_group", "")).strip_edges().is_empty():
			errors.append("%s.form.exclusive_group must be nonempty" % key)
		var cast: Variant = d.get("cast", {})
		if not cast is Dictionary or String(cast.get("rule", "")) != "form" or _seconds(cast.get("mob_within")) <= 0:
			errors.append("%s.cast needs rule form and positive mob_within" % key)
		if String(d.get("damage", "")) != "none" or String(d.get("slot", "")) != "active":
			errors.append("%s: form needs damage none and slot active" % key)
		var effects: Variant = block.get("effects")
		if not effects is Dictionary:
			errors.append("%s.form.effects needs an object" % key)
		else:
			for effect: String in effects:
				var record: Dictionary = EFFECTS.get(effect, STATE_EFFECTS.get(effect, {}))
				if record.is_empty():
					errors.append("%s.form.effects.%s is unknown" % [key, effect])
				else:
					var validate: Callable = record.get("validate", Callable())
					if validate.is_valid() and not bool(validate.call(effects[effect])):
						errors.append("%s.form.effects.%s has an invalid value" % [key, effect])
		if block.has("presentation") and not FormRules.valid_presentation(block.presentation):
			errors.append("%s.form.presentation needs an object with a positive whole mount" % key)
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
			if parents is String:
				parents = [parents]
			if String(child.get("slot", "")) != "form_sub" or not parents is Array or not key in parents:
				errors.append("%s.form.subs: %s needs slot form_sub and form_sub_of parent" % [key, skill])
			if _seconds(sub.get("first_after")) < 0:
				errors.append("%s.form.subs.%s.first_after must be nonnegative seconds" % [key, skill])
			for flag: String in ["ignores_hidden", "ends_form"]:
				if not sub.get(flag, false) is bool:
					errors.append("%s.form.subs.%s.%s must be boolean" % [key, skill, flag])
			var once: Variant = sub.get("once", false)
			if not once is bool:
				errors.append("%s.form.subs.%s.once must be boolean" % [key, skill])
			if not (once is bool and bool(once)) and _seconds(sub.get("interval")) <= 0:
				errors.append("%s.form.subs.%s needs once or positive interval" % [key, skill])
	return errors


static func _seconds(value: Variant) -> float:
	if not (value is float or value is int):
		return -1.0
	var seconds := float(value)
	return seconds if is_finite(seconds) else -1.0

## Ends one window, leaving independent groups running. Missing keys are harmless.
func end(world: RunWorld, key: String, reason: String) -> void:
	for state in _active.duplicate():
		if String(state.skill) == key:
			_end(world, state, reason)

## Whether pool skill `key` may auto-cast now: false only for a pool active outside a running form's `only_skills`
## (FormRules.permits). SkillRunner.cast_ready asks once per candidate; with no running form it is always true.
func permits(world: RunWorld, key: String) -> bool:
	return _active.is_empty() or FormRules.permits(_active, world, key)

## The remaining share (0..1) of the running hull, or -1.0 when no running form has one (the HUD's hull bar). The first
## hull in start order wins; two forms of different groups with hulls are not a case the specs have.
func hull_fraction() -> float:
	for state in _active:
		if state.has("hull_max"):
			return float(state.hull_hp) / float(state.hull_max)
	return -1.0

## Folds incoming post-defence damage through the active effect pools in start order.
func absorb(world: RunWorld, amount: float) -> float:
	for state in _active.duplicate():
		for effect: String in state.effects:
			var hook: Callable = EFFECTS.get(effect, STATE_EFFECTS.get(effect, {})).get("absorb", Callable())
			if hook.is_valid():
				amount = clampf(float(hook.call(world, state, amount)), 0.0, amount)
	return amount

func _hooks(name: String, world: RunWorld, state: Dictionary) -> void:
	for effect: String in state.effects:
		var hook: Callable = EFFECTS.get(effect, {}).get(name, Callable())
		if hook.is_valid():
			hook.call(world, state)

static func _resolve_damage(world: RunWorld, key: String, stats: Dictionary, value: Variant) -> float:
	return world.book.canonical(key, int(stats.level), String(value.field), 100.0) / 100.0 + world.loadout.skill_stat(key, "form_power", 0.0)

static func _valid_element(value: Variant) -> bool:
	return value is String and not String(value).is_empty() and Elements.has_art(String(value))

static func _valid_damage(value: Variant) -> bool:
	return value is Dictionary and value.get("field") is String and not String(value.field).is_empty()
