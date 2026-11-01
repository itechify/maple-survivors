class_name MobBuffs
extends RefCounted
## Per-slot timed boss self-buff state of MobSkill 101/111 (magic attack up), 102/103 (their `mob` icons; the defense
## numbers live in MobSkillRunner next to 112/113) and the magic immunity 141 (docs/GAME_DESIGN.md "Constants and
## provenance", spec #448 B2). Plain data: no files, nodes or canonical-stat mutation. Every array is indexed by mob slot
## and follows the swarm's resize / reset / move hooks.

## Icon channels: which buff a `mob` icon belongs to (one icon each, a recast replaces it).
const ICON_MAGIC_ATTACK := 0 # 101 and 111
const ICON_PDD := 1 # 102
const ICON_MDD := 2 # 103
const ICON_CHANNELS := 3

var _magic_mult := PackedFloat32Array()
var _magic_until := PackedFloat64Array()
var _icon_until: Array[PackedFloat64Array] = []
var _icon_visual: Array[PackedStringArray] = []
var _immune_until := PackedFloat64Array()
var _immune_visual := PackedStringArray()


func _init() -> void:
	for channel in ICON_CHANNELS:
		_icon_until.append(PackedFloat64Array())
		_icon_visual.append(PackedStringArray())


## Grows the pools without changing existing statuses.
func resize(capacity: int) -> void:
	_magic_mult.resize(capacity)
	_magic_until.resize(capacity)
	_immune_until.resize(capacity)
	_immune_visual.resize(capacity)
	for channel in ICON_CHANNELS:
		_icon_until[channel].resize(capacity)
		_icon_visual[channel].resize(capacity)


## A new mob in a reused slot starts clean.
func reset_slot(slot: int) -> void:
	_magic_mult[slot] = 0
	_magic_until[slot] = 0
	_immune_until[slot] = 0
	_immune_visual[slot] = ""
	for channel in ICON_CHANNELS:
		_icon_until[channel][slot] = 0
		_icon_visual[channel][slot] = ""


## Carries the statuses of `from` to `to` (a relocation) and cleans `from`.
func move_slot(from: int, to: int) -> void:
	if from == to:
		return
	_magic_mult[to] = _magic_mult[from]
	_magic_until[to] = _magic_until[from]
	_immune_until[to] = _immune_until[from]
	_immune_visual[to] = _immune_visual[from]
	for channel in ICON_CHANNELS:
		_icon_until[channel][to] = _icon_until[channel][from]
		_icon_visual[channel][to] = _icon_visual[channel][from]
	reset_slot(from)


## Magic attack up on `slot` until `until` (a recast replaces the multiplier and refreshes the end; it never stacks).
func set_magic_attack(slot: int, mult: float, until: float) -> void:
	_magic_mult[slot] = mult
	_magic_until[slot] = until


## Multiplier on the magic attack of the mob in `slot`: the cast's x/100 while 101/111 lasts, else 1. Applied where a
## magic attackN's MADamage becomes damage (RunWorld.mob_magic_attack); touch and weapon attacks never read it.
func magic_attack_multiplier(slot: int, now: float) -> float:
	if slot < 0 or slot >= _magic_until.size() or now >= _magic_until[slot] - 1e-9:
		return 1.0
	return _magic_mult[slot]


## Shows `visual` (a `mob` icon path) over `slot` on `channel` until `until`.
func set_icon(channel: int, slot: int, visual: String, until: float) -> void:
	_icon_until[channel][slot] = until
	_icon_visual[channel][slot] = visual


## The icon paths active over `slot` now (empty when none), one per channel.
func icons(slot: int, now: float) -> Array[String]:
	var out: Array[String] = []
	if slot < 0 or slot >= _magic_until.size():
		return out
	for channel in ICON_CHANNELS:
		if now < _icon_until[channel][slot] - 1e-9 and _icon_visual[channel][slot] != "":
			out.append(_icon_visual[channel][slot])
	return out


## Magic immunity (141) on `slot` until `until`.
func set_magic_immunity(slot: int, until: float, visual: String) -> void:
	_immune_until[slot] = until
	_immune_visual[slot] = visual


## Whether a magic hit may damage `slot` at `now`.
func magic_hit_allowed(slot: int, now: float) -> bool:
	return slot < 0 or slot >= _immune_until.size() or now >= _immune_until[slot] - 1e-9


## Detached presentation state of an active magic immunity, empty otherwise.
func immunity_state(slot: int, now: float) -> Dictionary:
	return {} if magic_hit_allowed(slot, now) else {"remaining": _immune_until[slot] - now, "visual": _immune_visual[slot]}


## For every slot below `n` whose `active` entry is set, writes 1/0 into `out` (magic_hit_allowed); others keep theirs.
func fill_magic_allowed(active: PackedByteArray, n: int, now: float, out: PackedByteArray) -> void:
	var immune := _immune_until.size()
	for slot in n:
		if active[slot] != 0:
			out[slot] = 1 if slot >= immune or now >= _immune_until[slot] - 1e-9 else 0
