class_name HitHook
extends RefCounted
## One participant in RunWorld.take_hit's ordered hook point (spec #372 BS3, docs/GAME_DESIGN.md 7.81). A feature that
## must react to the hits the character takes (a second life, a ship's hull) is a HitHook registered with
## RunWorld.add_hit_hook(hook, order): hooks run in ascending `order`, equal orders in registration order. The base
## class does nothing, so a hook overrides only the phases it needs; a world with no hook that acts is unchanged.
## Phases, in the order take_hit reaches them:
##  - `guarding()`: asked before the miss roll. True returns 0 from the hit at once (no RNG, no event), sources that
##    ignore the hit window included.
##  - `intercept_lethal(world, source)`: asked once the hit has been processed in full and left HP at zero or below.
##    The first hook to return true keeps the character alive (it must have restored HP, RunWorld.grant_second_life);
##    when none does the character dies as ever. Later phases, such as damage absorption before HP, are new methods
##    here with pass-through defaults, called from take_hit where that phase belongs.
##  - `step(dt)`: once per world tick, for the hook's own timers.
## Hooks use no RNG of their own and no per-entity Nodes.


## Whether hits are refused now (see above).
func guarding() -> bool:
	return false


## Whether this hook turns the lethal hit from `source` into a survived one (see above).
func intercept_lethal(_world: RunWorld, _source: Dictionary) -> bool:
	return false


## Advances the hook's timers by `dt` seconds.
func step(_dt: float) -> void:
	pass
