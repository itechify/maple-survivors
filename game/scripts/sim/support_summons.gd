class_name SupportSummons
extends RefCounted
## The support summon (roster M10, spec #348): a PlayerSummons follower whose definition carries `summon.support`
## instead of an attack. It pulses: each pulse has its own countdown per summon slot, plays its animation and applies
## its effect to the owner when the animation starts. PlayerSummons keeps the lifecycle (spawn, follow, expiry,
## replace on recast, map transfer, `summon_count`) and calls `begin` at spawn and `step` every tick; nothing here
## knows a job, a skill id or an animation name. Pure sim: no nodes, no clock but `dt`, no RNG.
##
## Definition (`summon.support`): `pulses[]` of {skill, kind, first_after, anim, anim_by_stat?}. `skill` is a sub-skill
## (slot "summon_sub", `summon_sub_of` the parent): never in a pool, never a card, never in Loadout.order. The sub's
## numbers come from Loadout.stats(sub, parent rank) through the sub's own `ranks` table. `first_after` is seconds or
## "interval" (the sub's first interval). The parent's modifiers apply: `support_heal` (mul, on heal amounts),
## `support_rate` (mul, on every pulse interval), `duration` (the summon's life), `summon_count`.
##
## A later job adds a pulse kind as one entry in KINDS (resolve + apply) plus its own tests; PlayerSummons is never
## edited for it. docs/GAME_DESIGN.md 7.67, docs/ARCHITECTURE.md 4.4.4.

## tier C: shortest pulse interval after `support_rate`, so a stack of rate cards can never pulse every tick.
const MIN_INTERVAL := 0.1

## Pulse kind -> {resolve, apply}. `resolve(lo, parent, sub, sub_stats) -> Dictionary` returns the kind's cast-time
## numbers plus `interval` (seconds, before `support_rate`) and optionally `stats` (the effects the pulse carries, for
## `anim_by_stat`); `apply(world, pulse)` applies one resolved pulse to the owner.
static var KINDS := {
	"heal": {"resolve": _resolve_heal, "apply": _apply_heal},
	"buff": {"resolve": _resolve_buff, "apply": _apply_buff},
}

## Per summon slot: the pulse countdowns, {"p": resolved pulse, "left": seconds to the next one, "anim_len": seconds}.
var pulses: Array = []
## Per summon slot: the pulse animation still playing ("" when none) and the seconds it has left.
var held := PackedStringArray()
var held_left := PackedFloat64Array()


## Resolves every pulse of parent skill `parent` at survivor rank `rank` for a cast: [{skill, skill_id, name, kind,
## interval (seconds, after `support_rate`), first_after (seconds), anim, plus the kind's own fields}]. [] when the
## parent has no support block.
static func resolve(lo: Loadout, parent: String, rank: int) -> Array:
	var out: Array = []
	var rate := lo.skill_stat(parent, "support_rate", 1.0)
	var support: Dictionary = lo.book.def(parent).get("summon", {}).get("support", {})
	for def: Dictionary in support.get("pulses", []):
		var kind := String(def.kind)
		if not KINDS.has(kind):
			continue
		var sub := String(def.skill)
		var p: Dictionary = KINDS[kind].resolve.call(lo, parent, sub, lo.stats(sub, rank))
		p["skill"] = sub
		p["skill_id"] = lo.book.skill_id(sub)
		p["name"] = String(lo.book.def(sub).get("name", sub))
		p["kind"] = kind
		p["interval"] = maxf(MIN_INTERVAL, float(p.interval) * rate)
		var first: Variant = def.first_after
		p["first_after"] = float(p.interval) if first is String and first == "interval" else float(first)
		p["anim"] = _anim_for(def, p.get("effects", {}))
		out.append(p)
	return out


## The value a card previews for mod stat `stat` ("support_heal": the first heal pulse's HP; "support_rate": the first
## pulse's interval in seconds, two decimals) from resolved cast stats `st`; 0 when the skill has no such pulse.
static func preview(st: Dictionary, stat: String) -> Variant:
	var list: Array = st.get("support", [])
	if stat == "support_rate":
		return snappedf(float(list[0].interval), 0.01) if not list.is_empty() else 0.0
	for p: Dictionary in list:
		if p.kind == "heal":
			return int(p.amount)
	return 0


## Starts the countdowns of summon slot `slot` from a cast's resolved `support` list; `durations` are the summon
## animations' lengths in seconds.
func begin(slot: int, resolved: Array, durations: Dictionary) -> void:
	while pulses.size() <= slot:
		pulses.append([])
		held.append("")
		held_left.append(0.0)
	var list: Array = []
	for p: Dictionary in resolved:
		list.append({"p": p, "left": float(p.first_after), "anim_len": float(durations.get(p.anim, 0.0))})
	pulses[slot] = list
	held[slot] = ""
	held_left[slot] = 0.0


## Advances slot `slot`'s countdowns by `dt` and fires the pulses that are due (a dead owner gets none). Returns the
## pulse animation the summon should be playing ("" for its ordinary stand/move).
func step(slot: int, dt: float, world: RunWorld) -> String:
	if slot >= pulses.size() or bool(world.player_state.dead):
		return held[slot] if slot < held.size() else ""
	if held_left[slot] > 0.0:
		held_left[slot] -= dt
		if held_left[slot] <= 1e-6:
			held[slot] = ""
			held_left[slot] = 0.0
	for s: Dictionary in pulses[slot]:
		s.left = float(s.left) - dt
		if float(s.left) <= 1e-6:
			s.left = float(s.left) + float(s.p.interval)
			_fire(slot, s, world)
	return held[slot]


## `anim_by_stat` (optional, {stat: animation}) picks the animation of the last listed stat the pulse carries (the
## newest unlocked one); a pulse that carries none of them, or has no map, plays its plain `anim`.
static func _anim_for(def: Dictionary, effects: Dictionary) -> String:
	var anim := String(def.anim)
	var by_stat: Dictionary = def.get("anim_by_stat", {})
	for stat: String in by_stat:
		if effects.has(stat):
			anim = String(by_stat[stat])
	return anim


func _fire(slot: int, s: Dictionary, world: RunWorld) -> void:
	var p: Dictionary = s.p
	held[slot] = String(p.anim)
	held_left[slot] = float(s.anim_len)
	world.emit("support_pulse", {"skill": p.skill, "skill_id": p.skill_id, "kind": p.kind, "slot": slot})
	KINDS[p.kind].apply.call(world, p)


static func _resolve_heal(lo: Loadout, parent: String, sub: String, st: Dictionary) -> Dictionary:
	var lv := int(st.level)
	return {"amount": roundi(lo.book.canonical(sub, lv, "hp") * lo.skill_stat(parent, "support_heal", 1.0)),
		"interval": lo.book.canonical(sub, lv, "x")}


static func _apply_heal(world: RunWorld, p: Dictionary) -> void:
	world.restore_player("hp", int(p.amount), String(p.skill))


## The sub's `buff.effects` ({stat, field}) that its level has: a field absent at this level is not carried (a stat
## unlocks at its level). The buff lasts the canonical `time`; the interval is the canonical `x`.
static func _resolve_buff(lo: Loadout, _parent: String, sub: String, st: Dictionary) -> Dictionary:
	var lv := int(st.level)
	var node := lo.book.level_node(sub, lv)
	var effects := {}
	for effect: Dictionary in lo.book.def(sub).get("buff", {}).get("effects", []):
		var field := String(effect.field)
		if node.has(field):
			var stat := String(effect.stat)
			effects[stat] = float(effects.get(stat, 0.0)) + lo.book.canonical(sub, lv, field) * float(effect.get("scale", 1.0))
	var duration := lo.book.canonical(sub, lv, "time")
	# The PlayerBuffs.start dictionary: a same-key buff replaces its entry, so a repeat pulse refreshes and never stacks.
	var first := String(effects.keys()[0]) if not effects.is_empty() else ""
	return {"interval": lo.book.canonical(sub, lv, "x"), "effects": effects, "duration": duration,
		"buff": {"skill": sub, "skill_id": lo.book.skill_id(sub), "level": lv,
			"icon": String(lo.book.def(sub).get("icon", "")), "duration": duration, "buff_stat": first,
			"buff_value": float(effects.get(first, 0.0)), "buff_effects": effects, "pulse_interval": 0.0}}


static func _apply_buff(world: RunWorld, p: Dictionary) -> void:
	if not (p.effects as Dictionary).is_empty():
		world.start_buff(String(p.skill), p.buff)
