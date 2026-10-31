class_name FormRules
extends RefCounted
## The two rule effects of a Form that change what the character casts rather than what it takes (spec #384 C11,
## GAME_DESIGN 7.120.9). Both are STATE_EFFECTS entries of PlayerForms with only a validator; the running forms' state holds
## the declared value and these functions read it.
##  - `only_skills [key...]`: while a running form carries it, a pool skill outside the list does not auto-cast
##    (SkillRunner.cast_ready asks `PlayerForms.permits` once per candidate). Its cooldown keeps counting and it casts the
##    tick the form ends. The mobility key, forms, `form_sub` skills and triggered skills (manual / reaction) are never
##    restricted; bursts, strikes and summons already out were cast before and are not consulted.
##  - `art_variant {slot: node}`: presentation only. While a running form carries it, a skill whose definition has a field
##    named `node` (a path template like `effect`) draws that art in place of `slot`; nothing else about the cast changes.
## No RNG, no clock, no assets.

## The registry entries.
static var ONLY_SKILLS := {"validate": valid_only_skills}
static var ART_VARIANT := {"validate": valid_art_variant}


## Whether pool skill `key` may auto-cast now, given the running form states `states`.
static func permits(states: Array[Dictionary], world: RunWorld, key: String) -> bool:
	var d := world.book.def(key)
	if String(d.get("slot", "active" if world.book.is_active(key) else "passive")) != "active" or String(d.get("kind", "")) == "form" \
			or SkillRunner.is_triggered_rule(String(d.get("cast", {}).get("rule", ""))):
		return true
	for state in states:
		var only: Variant = state.effects.get("only_skills")
		if only is Array and not key in only:
			return false
	return true


## `st` with the effect art of the first running form's `art_variant` for each slot the skill `key` defines a node for;
## returns `st` itself when nothing changes, else an edited copy.
static func art_variant(states: Array[Dictionary], world: RunWorld, key: String, st: Dictionary) -> Dictionary:
	var out := st
	for state in states:
		var variants: Variant = state.effects.get("art_variant")
		if not variants is Dictionary:
			continue
		for slot: String in variants:
			var node := String(variants[slot])
			if not world.book.def(key).has(node):
				continue
			if is_same(out, st):
				out = st.duplicate()
			out[slot] = world.book.art_path(key, world.book.visual(key, node, int(st.level), world.loadout.char_level), world.loadout.weapon_family)
	return out


## `only_skills`: a list of nonempty skill keys.
static func valid_only_skills(value: Variant) -> bool:
	if not value is Array:
		return false
	for key: Variant in value:
		if not key is String or String(key).is_empty():
			return false
	return true


## `art_variant`: a map of nonempty slot names to nonempty node names.
static func valid_art_variant(value: Variant) -> bool:
	if not value is Dictionary or value.is_empty():
		return false
	for slot: Variant in value:
		if not slot is String or String(slot).is_empty() or not value[slot] is String or String(value[slot]).is_empty():
			return false
	return true


## `presentation`: an object whose optional `mount` is a positive whole number (a TamingMob id).
static func valid_presentation(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var mount: Variant = value.get("mount", 1)
	return (mount is int or (mount is float and is_equal_approx(mount, roundf(mount)))) and mount > 0
