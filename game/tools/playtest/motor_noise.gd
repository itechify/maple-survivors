extends RefCounted
## The playtest motor layer (spec #91, ticket #97): a personality's motor parameters applied on top of the tactic
## controller's MoveInput, every fixed tick. Its randomness is its own RandomNumberGenerator (seeded from the run seed),
## separate from every sim stream; with zero noise and no potion thresholds `apply` returns the controller's input
## object unchanged, so the sensible personality plays exactly like BotInput. Tool code only.
##
## Order per tick: potion thresholds, then reaction delay, then mistake bursts.
##   potion_hp_fraction / potion_mp_fraction  null: the controller's own potion timing. A number: drink only while the
##       pool is below that share of its max (and stock remains), replacing the controller's timing (a late drinker
##       never drinks above it, an early drinker drinks as soon as it falls below it).
##   reaction_delay_ticks N  after the wanted movement changes, the previous movement repeats for N ticks, then the
##       latest wanted movement applies. Jump and Teleport presses (one-tick edges) count as changes and are latched
##       through the delay, so a slow player still jumps, just late. Potion presses are never delayed.
##   mistake_rate  per-second chance of a burst (BURST_MIN..BURST_MAX ticks): half the time the horizontal key is the
##       wrong way (a random direction if none was wanted), half the time no movement key at all.
## Potion presses are not touched by delays or bursts: potion timing is the thresholds' job.

const DT := 1.0 / 60.0
## tier C: a mistake burst lasts this many ticks (0.33 to 0.83 s).
const BURST_MIN := 20
const BURST_MAX := 50

var reaction_delay_ticks := 0
var mistake_rate := 0.0
## < 0: the controller's own timing (null in the personality file).
var potion_hp_fraction := -1.0
var potion_mp_fraction := -1.0
## The motor's own stream.
var rng := RandomNumberGenerator.new()

## Movement last applied (held keys only), null before the first tick.
var _applied: MoveInput = null
## Ticks left in the current delay; -1: not delaying.
var _wait := -1
var _latch_jump := false
var _latch_teleport := false
var _burst_left := 0
var _burst_kind := ""
var _burst_dir := 1
var _stats := {"delayed_ticks": 0, "bursts": 0, "wrong_direction": 0, "no_input": 0, "burst_ticks": 0,
	"potion_hp_drinks": 0, "potion_mp_drinks": 0}


## `seed_value` is the run seed; `params` the personality's motor dictionary (missing keys: no noise).
func _init(seed_value := 0, params: Dictionary = {}) -> void:
	rng.seed = hash("motor-%d" % seed_value)
	reaction_delay_ticks = maxi(0, int(params.get("reaction_delay_ticks", 0)))
	mistake_rate = maxf(0.0, float(params.get("mistake_rate", 0.0)))
	var hp: Variant = params.get("potion_hp_fraction")
	var mp: Variant = params.get("potion_mp_fraction")
	potion_hp_fraction = float(hp) if hp != null else -1.0
	potion_mp_fraction = float(mp) if mp != null else -1.0


## True when this layer never changes an input (the sensible personality).
func is_quiet() -> bool:
	return reaction_delay_ticks == 0 and mistake_rate <= 0.0 and potion_hp_fraction < 0.0 and potion_mp_fraction < 0.0


## The input actually pressed this tick of `w`, given the controller's `wanted` (`w` may be null without thresholds).
func apply(w: RunWorld, wanted: MoveInput) -> MoveInput:
	var mi := wanted
	if is_quiet():
		return mi
	if potion_hp_fraction >= 0.0 or potion_mp_fraction >= 0.0:
		mi = _potions(w, mi)
	var out := _delay(mi)
	return _mistakes(out)


## Counts for the round record: ticks of stale movement, bursts by kind, burst ticks, threshold drinks pressed.
func summary() -> Dictionary:
	var s := _stats.duplicate()
	s["params"] = {"reaction_delay_ticks": reaction_delay_ticks, "mistake_rate": mistake_rate,
		"potion_hp_fraction": potion_hp_fraction if potion_hp_fraction >= 0.0 else null,
		"potion_mp_fraction": potion_mp_fraction if potion_mp_fraction >= 0.0 else null}
	return s


func _potions(w: RunWorld, wanted: MoveInput) -> MoveInput:
	var mi := _held(wanted, wanted)
	mi.jump_pressed = wanted.jump_pressed
	mi.teleport_pressed = wanted.teleport_pressed
	var ps := w.player_state
	if potion_hp_fraction >= 0.0:
		mi.drink_hp = _below(w, "hp", float(ps.hp), float(ps.max_hp), potion_hp_fraction)
		_stats.potion_hp_drinks += int(mi.drink_hp)
	if potion_mp_fraction >= 0.0:
		mi.drink_mp = _below(w, "mp", float(ps.mp), float(ps.max_mp), potion_mp_fraction)
		_stats.potion_mp_drinks += int(mi.drink_mp)
	return mi


func _below(w: RunWorld, kind: String, value: float, max_value: float, fraction: float) -> bool:
	return max_value > 0.0 and value < fraction * max_value and BotInput.worth_drinking(w, kind, max_value - value, 0.0)


func _same_hold(a: MoveInput, b: MoveInput) -> bool:
	return a.left == b.left and a.right == b.right and a.up == b.up and a.down == b.down and a.jump_held == b.jump_held \
		and a.teleport_held == b.teleport_held


## A copy of the held keys of `src`, no edges, with the potion presses of `drinks`.
func _held(src: MoveInput, drinks: MoveInput) -> MoveInput:
	var o := MoveInput.make(src.left, src.right, src.up, src.down, false, src.jump_held)
	o.teleport_held = src.teleport_held
	o.drink_hp = drinks.drink_hp
	o.drink_mp = drinks.drink_mp
	return o


func _delay(mi: MoveInput) -> MoveInput:
	if reaction_delay_ticks <= 0:
		return mi
	if _applied == null:
		_applied = _held(mi, mi)
		return mi
	var changed := not _same_hold(mi, _applied) or mi.jump_pressed or mi.teleport_pressed
	if _wait < 0 and not changed:
		_applied = _held(mi, mi)
		return mi
	if _wait < 0:
		_wait = reaction_delay_ticks
	_latch_jump = _latch_jump or mi.jump_pressed
	_latch_teleport = _latch_teleport or mi.teleport_pressed
	if _wait > 0:
		_wait -= 1
		_stats.delayed_ticks += 1
		return _held(_applied, mi)
	_wait = -1
	var out := _held(mi, mi)
	out.jump_pressed = _latch_jump
	out.teleport_pressed = _latch_teleport
	_latch_jump = false
	_latch_teleport = false
	_applied = _held(mi, mi)
	return out


func _mistakes(mi: MoveInput) -> MoveInput:
	if mistake_rate <= 0.0:
		return mi
	if _burst_left <= 0 and rng.randf() < mistake_rate * DT:
		_burst_left = rng.randi_range(BURST_MIN, BURST_MAX)
		_burst_kind = "wrong_direction" if rng.randf() < 0.5 else "no_input"
		_burst_dir = -1 if rng.randf() < 0.5 else 1
		_stats.bursts += 1
		_stats[_burst_kind] += 1
	if _burst_left <= 0:
		return mi
	_burst_left -= 1
	_stats.burst_ticks += 1
	var o := MoveInput.new()
	o.drink_hp = mi.drink_hp
	o.drink_mp = mi.drink_mp
	if _burst_kind == "no_input":
		return o
	var dir := -mi.dir() if mi.dir() != 0 else _burst_dir
	o.left = dir < 0
	o.right = dir > 0
	o.up = mi.up
	o.down = mi.down
	o.jump_pressed = mi.jump_pressed
	o.jump_held = mi.jump_held
	return o
