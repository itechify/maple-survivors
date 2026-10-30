class_name GroundStrike
extends RefCounted
## The damaging periodic ground zone (`ground.strike`, spec #383 NL8, GAME_DESIGN 7.95): a skill whose `ground` block holds
## a `strike` object instead of a `status` leaves a zone at the cast position that, for the skill's WZ `time`, hits the
## monsters inside its box on a clock. `{"strike": {"interval": 1.0, "first_delay": 0.3}}`: the first strike lands
## `first_delay` seconds after the cast, then one every `interval`, the last at or before the lifetime. Generic: Ninja Ambush
## (4121004) uses it today and Shadower's copy (4221004) is a data copy; there is no skill ID in this file.
##
## This script holds only the pure arithmetic (pulse times, how many pulses a lifetime holds, the target limit) and the
## data-file check. SkillRunner owns the zones (`_queue_area`, `_step_areas`) and resolves each strike through its ordinary
## instant-hit path (RunWorld.hit_mob: defence, crit, element, on-hit statuses, the first-hit meter receipt, kills and loot).
## It draws no random numbers of its own.

## tier C: ours (the spec's reading of the 4121004 strike cadence), GAME_DESIGN 7.95. v83 has no WZ field for it.
const DEFAULT_INTERVAL := 1.0
const DEFAULT_FIRST_DELAY := 0.3
## Float slack of the pulse comparisons: a strike due exactly at the lifetime still lands.
const EPS := 1e-9


## Whether a `ground` block is a damaging zone (it has a `strike` key).
static func is_strike(ground: Dictionary) -> bool:
	return ground.has("strike")


## The cadence of a strike zone: `{interval, first_delay}` with the tier C defaults filled in; {} for a block with no strike.
static func spec(ground: Dictionary) -> Dictionary:
	if not is_strike(ground) or not ground.strike is Dictionary:
		return {}
	var block: Dictionary = ground.strike
	return {"interval": float(block.get("interval", DEFAULT_INTERVAL)),
		"first_delay": float(block.get("first_delay", DEFAULT_FIRST_DELAY))}


## The age at which strike `k` (0-based) lands.
static func strike_time(first_delay: float, interval: float, k: int) -> float:
	return first_delay + interval * k


## How many strikes a zone of `duration` seconds holds: those at or before the lifetime, none when it ends before the first.
static func strike_count(first_delay: float, interval: float, duration: float) -> int:
	if first_delay > duration + EPS or interval <= 0.0:
		return 0
	return int(floor((duration - first_delay) / interval + EPS)) + 1


## The most monsters one strike hits: the resolved `mob_count` (canonical mobCount plus `count` bonuses), at least one.
static func target_limit(st: Dictionary) -> int:
	return maxi(1, int(st.get("mob_count", 1)))


## Load errors of the `ground` blocks of a skills file (`{"skills": {key: definition}}`): `status` and `strike` are mutually
## exclusive, a strike has no chance roll, and its numbers must be usable (an interval above 0, a first delay of 0 or more).
static func errors(skills_file: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var skills: Variant = skills_file.get("skills")
	if not skills is Dictionary:
		return out
	for key: Variant in skills:
		var definition: Variant = skills[key]
		if not definition is Dictionary or not definition.get("ground") is Dictionary:
			continue
		var ground: Dictionary = definition.ground
		if not is_strike(ground):
			continue
		if ground.has("status"):
			out.append("skill '%s': ground.status and ground.strike are mutually exclusive" % key)
		if ground.has("chance_field"):
			out.append("skill '%s': ground.strike has no chance roll (chance_field belongs to ground.status)" % key)
		if not ground.strike is Dictionary:
			out.append("skill '%s': ground.strike must be an object" % key)
			continue
		var block: Dictionary = ground.strike
		var interval: Variant = block.get("interval", DEFAULT_INTERVAL)
		if not (interval is float or interval is int) or float(interval) <= 0.0:
			out.append("skill '%s': ground.strike.interval must be a number above 0" % key)
		var delay: Variant = block.get("first_delay", DEFAULT_FIRST_DELAY)
		if not (delay is float or delay is int) or float(delay) < 0.0:
			out.append("skill '%s': ground.strike.first_delay must be a number of 0 or more" % key)
	return out
