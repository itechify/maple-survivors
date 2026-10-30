class_name PlayerHull
extends RefCounted
## The `hull` state effect of a Form (spec #384 C11, GAME_DESIGN 7.120.9): a durability pool, a share of max HP, that takes the
## character's hits before HP does. A STATE_EFFECTS entry of PlayerForms: it sizes the pool at the form's start, soaks
## damage through `PlayerForms.absorb` (RunWorld.take_hit, after defence and armour and before HP) and ends the form with
## reason `broken` at 0. The pool lives in the form's state (`hull_hp` / `hull_max`, whole points), so a map transfer keeps it
## and death ends it with the form. No RNG, no clock, no assets, no skill ids.

## The registry entry: start/end/absorb handlers and the effect value's validator.
static var ENTRY := {"start": start, "absorb": absorb, "validate": valid}


## Sizes the pool: `hull_max = hull_hp = max(1, floor(pct / 100 x max HP x the skill's hull modifier))`, where `pct` is the
## canonical level field named by `value.field` at the form's level (tier A: the ship's `pdd` percent, CS-11). Fixed here: a
## later modifier or max HP change leaves a running hull alone.
static func start(world: RunWorld, state: Dictionary, value: Variant) -> void:
	var key := String(state.skill)
	var pct := world.book.canonical(key, int(state.level), String(value.field), 0.0)
	var share := pct / 100.0 * float(world.player_state.max_hp) * world.loadout.skill_stat(key, "hull", 1.0)
	state["hull_max"] = maxi(1, floori(share))
	state["hull_hp"] = int(state.hull_max)


## Takes up to `amount` whole points of damage and returns what is left for HP; the form ends `broken` when the pool hits 0.
static func absorb(world: RunWorld, state: Dictionary, amount: float) -> float:
	var taken := mini(int(amount), int(state.hull_hp))
	state["hull_hp"] = int(state.hull_hp) - taken
	if int(state.hull_hp) <= 0:
		world.runner.forms.end(world, String(state.skill), "broken")
	return amount - float(taken)


## Whether `value` is a well formed hull effect: `{field: <canonical field name>, of: "max_hp"}`.
static func valid(value: Variant) -> bool:
	return value is Dictionary and value.get("field") is String and not String(value.field).is_empty() \
		and value.get("of") is String and String(value.of) == "max_hp"
