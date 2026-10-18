class_name PlayerUpkeep
extends RefCounted
## The player's per-tick timers (docs/ARCHITECTURE.md 4.4.6), owned by RunWorld as `upkeep`: timed buffs
## (PlayerBuffs) and their healing pulses, hit invincibility, the cast-stance hold and the balance.regen pulse clock.
## RunWorld owns the HP/MP pools: tick() reports the buff healing due and regen_pulses() how many regeneration
## pulses fell due, and the world applies them. Pure: no nodes, files or time.

## tier B: v83 MP recovery cadence/base; tier C: owner-selected always-on HP recovery.
const DEFAULT_REGEN := {"interval": 10.0, "hp": 10.0, "mp": 3.0}

## tier C (ours, spec #88): the shrinking hit window; balance.hit_window overrides it.
const DEFAULT_HIT_WINDOW := {"lengths": [1.5, 1.0, 0.6, 0.4], "chain_gap": 2.5, "reset_after": 3.0}
## Float slack for the chain/reset comparisons against accumulated fixed-tick time.
const _EPS := 1e-9

## Seconds of hit invincibility left.
var invincible_t := 0.0
## Index into the window lengths of the last windowed hit (0 = the full window); per-round, not saved.
var hit_step := 0
## Seconds since the last landed hit of any kind; INF before the first one.
var since_hit := INF
## The stance a cast or swing holds, for cast_left more seconds; airborne swings may show it in the air.
var cast_action := ""
var cast_left := 0.0
var action_airborne := false
## The fraction of the stance's canonical frame time it plays in (attack speed, WeaponInfo.speed_factor); 1.0 normally.
var action_scale := 1.0
var _buffs: PlayerBuffs
var _regen: Dictionary
var _regen_elapsed := 0.0
var _window_lengths: Array[float] = []
var _chain_gap := float(DEFAULT_HIT_WINDOW.chain_gap)
var _reset_after := float(DEFAULT_HIT_WINDOW.reset_after)


## `buffs` is the run's PlayerBuffs; `regen` the balance.regen rules (DEFAULT_REGEN when absent, per key);
## `hit_window` the balance.hit_window rules (DEFAULT_HIT_WINDOW when absent, per key).
func _init(buffs: PlayerBuffs, regen: Dictionary = DEFAULT_REGEN, hit_window: Dictionary = DEFAULT_HIT_WINDOW) -> void:
	_buffs = buffs
	_regen = regen
	for length: Variant in hit_window.get("lengths", DEFAULT_HIT_WINDOW.lengths):
		_window_lengths.append(float(length))
	if _window_lengths.is_empty():
		_window_lengths.append(float(DEFAULT_HIT_WINDOW.lengths[0]))
	_chain_gap = float(hit_window.get("chain_gap", DEFAULT_HIT_WINDOW.chain_gap))
	_reset_after = float(hit_window.get("reset_after", DEFAULT_HIT_WINDOW.reset_after))


## Advances buff timers (emitting their events), invincibility, the hit chain clock and the cast hold; returns the
## buff HP healing due.
func tick(dt: float, events: Array) -> float:
	var healing := _buffs.step(dt, events)
	invincible_t = maxf(0.0, invincible_t - dt)
	since_hit += dt
	cast_left = maxf(0.0, cast_left - dt)
	return healing


## Whether a hit from `source` ignores the window: a scheduled boss's skill attack or ball (source_kind "attack" or
## "projectile"). Boss body touch, ordinary mob attacks and contact damage respect it. tier C: spec #88.
static func bypasses_window(source: Dictionary) -> bool:
	return bool(source.get("boss", false)) and String(source.get("source_kind", "")) in ["attack", "projectile"]


## A hit landed (not a miss): starts the window it earns and returns its length. A windowed hit steps the chain
## (first hit or `reset_after` since the last landed hit -> the full window; within `chain_gap` -> one shorter;
## between the two -> the same step); a boss skill attack always starts the full window without stepping the chain.
## Either kind refreshes the time of the last landed hit.
func land_hit(boss_skill: bool) -> float:
	# A lapsed chain restarts for either kind; a boss hit refreshing the clock must not revive a lapsed chain.
	var lapsed := since_hit >= _reset_after - _EPS
	if lapsed:
		hit_step = 0
	var seconds: float
	if boss_skill:
		seconds = maxf(invincible_t, _window_lengths[0])
	else:
		if not lapsed and since_hit <= _chain_gap + _EPS:
			hit_step = mini(hit_step + 1, _window_lengths.size() - 1)
		seconds = _window_lengths[hit_step]
	invincible_t = seconds
	since_hit = 0.0
	return seconds


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


## Base MP restored by one pulse (before mp_regen modifiers and the skills' Loadout.regen_bonus).
func pulse_mp() -> float:
	return float(_regen.get("mp", DEFAULT_REGEN.mp))


## Holds `action` for `seconds`; airborne opts basic swings into the same visual without changing motion; `scale` is the
## attack-speed fraction of the frame time the avatar plays it in.
func start_action(action: String, seconds: float, airborne: bool = false, scale: float = 1.0) -> void:
	if action == "" or seconds <= 0.0:
		return
	cast_action = action
	cast_left = seconds
	action_airborne = airborne
	action_scale = scale
