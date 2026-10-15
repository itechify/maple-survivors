class_name PlayerUpkeep
extends RefCounted
## The player's per-tick timers (docs/ARCHITECTURE.md 4.4.6), owned by RunWorld as `upkeep`: timed buffs
## (PlayerBuffs) and their healing pulses, hit invincibility, the cast-stance hold and the balance.regen pulse clock.
## RunWorld owns the HP/MP pools: tick() reports the buff healing due and regen_pulses() how many regeneration
## pulses fell due, and the world applies them. Pure: no nodes, files or time.

## tier B: v83 MP recovery cadence/base; tier C: owner-selected always-on HP recovery.
const DEFAULT_REGEN := {"interval": 10.0, "hp": 10.0, "mp": 3.0, "improved_mp_divisor": 10.0}

## Seconds of hit invincibility left.
var invincible_t := 0.0
## The stance a cast or swing holds, for cast_left more seconds; airborne swings may show it in the air.
var cast_action := ""
var cast_left := 0.0
var action_airborne := false
var _buffs: PlayerBuffs
var _regen: Dictionary
var _regen_elapsed := 0.0


## `buffs` is the run's PlayerBuffs; `regen` the balance.regen rules (DEFAULT_REGEN when absent, per key).
func _init(buffs: PlayerBuffs, regen: Dictionary = DEFAULT_REGEN) -> void:
	_buffs = buffs
	_regen = regen


## Advances buff timers (emitting their events), invincibility and the cast hold; returns the buff HP healing due.
func tick(dt: float, events: Array) -> float:
	var healing := _buffs.step(dt, events)
	invincible_t = maxf(0.0, invincible_t - dt)
	cast_left = maxf(0.0, cast_left - dt)
	return healing


## Advances the regeneration clock by dt (living players only) and returns the number of pulses due.
func regen_pulses(dt: float) -> int:
	var interval := maxf(0.01, float(_regen.get("interval", DEFAULT_REGEN.interval)))
	var pulses := 0
	_regen_elapsed += dt
	while _regen_elapsed >= interval - 1e-9:
		_regen_elapsed = maxf(0.0, _regen_elapsed - interval)
		pulses += 1
	return pulses


## Base HP restored by one pulse (before hp_regen modifiers).
func pulse_hp() -> float:
	return float(_regen.get("hp", DEFAULT_REGEN.hp))


## Base MP restored by one pulse (before mp_regen modifiers and the Improved MP Recovery bonus).
func pulse_mp() -> float:
	return float(_regen.get("mp", DEFAULT_REGEN.mp))


## Improved MP Recovery's MP per pulse. tier B: pre-Big-Bang rule floor(level x skill level / divisor), whole MP.
func improved_mp_bonus(level: int, skill_level: int) -> float:
	return floorf(float(level * skill_level)
		/ maxf(1.0, float(_regen.get("improved_mp_divisor", DEFAULT_REGEN.improved_mp_divisor))))


## Holds `action` for `seconds`; airborne opts basic swings into the same visual without changing motion.
func start_action(action: String, seconds: float, airborne: bool = false) -> void:
	if action == "" or seconds <= 0.0:
		return
	cast_action = action
	cast_left = seconds
	action_airborne = airborne
