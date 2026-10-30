class_name PlayerStatuses
extends RefCounted
## The timed statuses boss skills put on the character (Slow 126, Stun 123, and the later Darkness, Weakness, Curse,
## Poison, Seduce, Confuse), as plain data keyed by MobSkill id, with the shared lockout floor (docs/GAME_DESIGN.md
## "Constants and provenance", spec #448): no nodes, no clock of its own; every call takes the simulation time.

## tier C (#448): seconds a status cannot re-apply after it ends, at least; the immunity lasts max(this, the status's own
## `time`). balance.mob_skills.status_lockout {default, "<id>": s} overrides it per status.
const DEFAULT_LOCKOUT := 4.0
const EPS := 1e-9

var _lockout_rules: Dictionary
## id -> sim time the status ends.
var _until := {}
## id -> sim time its post-expiry immunity ends (statuses with a floor only).
var _immune_until := {}
## id -> the status's own fields (copied into `state`).
var _payload := {}


func _init(lockout_rules: Dictionary = {}) -> void:
	_lockout_rules = lockout_rules


## The post-expiry immunity of status `id` lasting `duration` s: max(its lockout rule, duration).
func lockout_seconds(id: int, duration: float) -> float:
	var rule := float(_lockout_rules.get(str(id), _lockout_rules.get("default", DEFAULT_LOCKOUT)))
	return maxf(rule, duration)


## Whether status `id` is active at `now`.
func is_active(id: int, now: float) -> bool:
	return now < float(_until.get(id, 0.0)) - EPS


## Whether `id` cannot take effect at `now`: it is active, or its immunity after the last cast has not ended.
func is_locked(id: int, now: float) -> bool:
	return now < float(_immune_until.get(id, 0.0)) - EPS


## Applies `id` for `duration` s from `now` with `payload` fields. With `with_lockout` the status is refused while locked (it
## neither refreshes nor stacks) and, once applied, is immune to re-application for lockout_seconds after it ends;
## without it a recast overwrites the active status (Slow keeps its behaviour). Returns whether it took effect.
func apply(id: int, now: float, duration: float, payload: Dictionary = {}, with_lockout: bool = true) -> bool:
	if with_lockout:
		if is_locked(id, now):
			return false
		_immune_until[id] = now + duration + lockout_seconds(id, duration)
	_until[id] = now + duration
	_payload[id] = payload
	return true


## Ends `id` at once; its immunity, if any, still runs from when the status was applied.
func clear(id: int) -> void:
	_until.erase(id)
	_payload.erase(id)


## Detached presentation state of an active status: {skill_id, remaining, ...payload}, empty when it is not active.
func state(id: int, now: float) -> Dictionary:
	if not is_active(id, now):
		return {}
	var out := {"skill_id": id, "remaining": float(_until[id]) - now}
	out.merge(_payload[id])
	return out


## A payload field of an active status, `fallback` when it is not active or lacks it.
func field(id: int, now: float, key: String, fallback: Variant) -> Variant:
	return _payload[id].get(key, fallback) if is_active(id, now) else fallback
