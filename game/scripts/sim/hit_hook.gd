class_name HitHook
extends RefCounted
## One participant in RunWorld.take_hit's ordered hook point (spec #372 BS3, docs/GAME_DESIGN.md 7.81). A feature that
## must react to the hits the character takes (a second life, a ship's hull) is a HitHook registered with
## RunWorld.add_hit_hook(hook, order): hooks run in ascending `order`, equal orders in registration order. The base
## class does nothing, so a hook overrides only the phases it needs; a world with no hook that acts is unchanged.
## Phases, in the order take_hit reaches them:
##  - `guarding()` (true while `guard_left()` is above zero): asked before the miss roll. True returns 0 from the hit at
##    once (no RNG, no event), sources that ignore the hit window included.
##  - `absorb(world, amount, source)`: asked after the hit has been through the miss roll, defence, armour and Power Guard,
##    right before HP is reduced. Returns the damage left for the next hook (and finally HP) to take; a hull returns
##    `amount` less what it soaked. Every hook is asked in order, so a hull registers at an order below
##    PlayerRevive.HIT_ORDER and what it soaks never reaches HP or the lethal check. The hit's damage number shows
##    what got through (0 when everything was soaked).
##  - `intercept_lethal(world, source)`: asked once the hit has been processed in full and left HP at zero or below.
##    The first hook to return true keeps the character alive (it must have restored HP, RunWorld.grant_second_life);
##    when none does the character dies as ever. Later phases, such as damage absorption before HP, are new methods
##    here with pass-through defaults, called from take_hit where that phase belongs.
##  - `step(dt)`: once per world tick, for the hook's own timers.
## Hooks use no RNG of their own and no per-entity Nodes.

## A guard counts as run out at or below this many seconds, like SkillRunner.cast_ready's ready test.
const GUARD_EPS := 1e-6


## Seconds of guard left: how long this hook still refuses every hit (0 for a hook that never guards). The HUD blinks the
## character for the longest of these (RunWorld.hit_guard_left).
func guard_left() -> float:
	return 0.0


## Whether hits are refused now (see above).
func guarding() -> bool:
	return guard_left() > GUARD_EPS


## The damage from `source` left after this hook has taken its share of `amount` (see above): the base hook takes none.
func absorb(_world: RunWorld, amount: int, _source: Dictionary) -> int:
	return amount


## Whether this hook turns the lethal hit from `source` into a survived one (see above).
func intercept_lethal(_world: RunWorld, _source: Dictionary) -> bool:
	return false


## Advances the hook's timers by `dt` seconds.
func step(_dt: float) -> void:
	pass
