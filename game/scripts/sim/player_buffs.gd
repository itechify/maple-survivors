class_name PlayerBuffs
extends RefCounted
## Pure timed player-buff state. Casts snapshot canonical duration/effect at their skill level; rank changes affect
## the next cast. Timers run independently of movement and casting gates, including on ropes.

var active := {}
var _periodic := {}
# Derived from `active` by _refresh() whenever a buff starts or ends, so the per-tick checks below are field reads.
var _hidden := false
var _morph := 0
var _ends_on_hp := false


## Whether the named skill is currently active.
func has(skill: String) -> bool:
	return active.has(skill)


## Starts a resolved buff and snapshots the data needed by hit rules and the HUD.
func start(skill: String, stats: Dictionary) -> void:
	active[skill] = {"skill": skill, "skill_id": int(stats.skill_id), "level": int(stats.level),
		"icon": String(stats.icon), "remaining": float(stats.duration), "duration": float(stats.duration),
		"effect_stat": String(stats.buff_stat), "value": float(stats.buff_value),
		"effects": stats.get("buff_effects", {String(stats.buff_stat): float(stats.buff_value)}).duplicate(true),
		# Hidden (#194): the buff makes the character Hidden; `morph` is the Morph.wz id it is drawn as (0 = the avatar);
		# `end_hp_above` > 0 ends it early once HP is above that fraction of Max HP.
		"hidden": bool(stats.get("hidden", false)), "morph": int(stats.get("morph", 0)),
		"end_hp_above": float(stats.get("end_hp_above", 0.0))}
	if float(stats.pulse_interval) > 0:
		_periodic[skill] = {"interval": float(stats.pulse_interval), "elapsed": 0.0}
	_refresh()


## Counts down buffs, emits periodic pulses before expiry, and returns HP healing due.
func step(dt: float, events: Array) -> int:
	var heal := 0
	if active.is_empty():
		return heal
	var ended := false
	for skill: String in active.keys():
		var buff: Dictionary = active[skill]
		var elapsed := minf(dt, float(buff.remaining))
		buff.remaining = maxf(0.0, float(buff.remaining) - dt)
		if _periodic.has(skill):
			var pulse: Dictionary = _periodic[skill]
			pulse.elapsed = float(pulse.elapsed) + elapsed
			while float(pulse.elapsed) >= float(pulse.interval) - 1e-6:
				pulse.elapsed = maxf(0.0, float(pulse.elapsed) - float(pulse.interval))
				var amount := int(buff.value)
				heal += amount if buff.effect_stat == "hp" else 0
				events.append({"type": "buff_pulse", "skill": skill, "skill_id": int(buff.skill_id), "amount": amount})
		if float(buff.remaining) <= 1e-6:
			active.erase(skill)
			_periodic.erase(skill)
			events.append({"type": "buff_expired", "skill": skill, "skill_id": int(buff.skill_id)})
			ended = true
	if ended:
		_refresh()
	return heal


## Ends the named buff now (its `buff_expired` event goes to `events`); false when it is not active.
func end(skill: String, events: Array) -> bool:
	if not active.has(skill):
		return false
	var buff: Dictionary = active[skill]
	active.erase(skill)
	_periodic.erase(skill)
	events.append({"type": "buff_expired", "skill": skill, "skill_id": int(buff.skill_id)})
	_refresh()
	return true


## Drops every active buff without events (tests).
func clear() -> void:
	active.clear()
	_periodic.clear()
	_refresh()


## Whether an active buff makes the character Hidden (docs/GAME_DESIGN.md 7.18).
func hidden() -> bool:
	return _hidden


## The Morph.wz id the character is drawn as (the first active morphing buff), 0 for the plain avatar.
func morph() -> int:
	return _morph


## Whether any active buff ends early once HP passes a fraction (`end_hp_above`), so callers can skip the check.
func ends_on_hp() -> bool:
	return _ends_on_hp


func _refresh() -> void:
	_hidden = false
	_morph = 0
	_ends_on_hp = false
	for buff: Dictionary in active.values():
		_hidden = _hidden or bool(buff.get("hidden", false))
		if _morph == 0 and int(buff.get("morph", 0)) > 0:
			_morph = int(buff.morph)
		_ends_on_hp = _ends_on_hp or float(buff.get("end_hp_above", 0.0)) > 0.0


## Sum of active canonical effects feeding a hit-rule stat (e.g. pdd or avoid).
func effect_total(stat: String) -> float:
	var total := 0.0
	for buff: Dictionary in active.values():
		total += float(buff.effects.get(stat, 0.0))
	return total


## The first active skill (in cast order) whose effect `stat` is above 0; "" when none is.
func skill_with_effect(stat: String) -> String:
	for skill: String in active:
		if float(active[skill].effects.get(stat, 0.0)) > 0.0:
			return skill
	return ""


## Detached presentation snapshot, in cast order.
func snapshot() -> Array:
	return active.values().duplicate(true)
