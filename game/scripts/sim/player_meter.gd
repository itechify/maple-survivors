class_name PlayerMeter
extends RefCounted
## Round-owned event counter and cast snapshots, shared by Combo, Energy Charge and meso charge.
## No clock or RNG: delayed attacks share a small cast receipt so only their first damaging hit earns a unit.

var config: Dictionary
var value := 0


## Creates a round counter from the job-owned meter definition.
func _init(definition: Dictionary = {}) -> void:
	config = definition.duplicate(true)


## Gains the configured amount for an event, emitting only actual changes.
func gain(event: String, events: Array) -> void:
	var rule: Dictionary = config.get("gain", {})
	if event == String(rule.get("event", "")):
		_set_value(value + int(rule.get("amount", 0)), events)


## Public HUD state; empty for jobs without a meter.
func snapshot() -> Dictionary:
	if config.is_empty():
		return {}
	return {"id": String(config.id), "value": value, "max": int(config.max), "art": String(config.get("art", ""))}


## Whether a skill's meter gate is satisfied.
func admits(definition: Dictionary) -> bool:
	var rule: Dictionary = definition.get("meter", {})
	return rule.is_empty() or (not config.is_empty() and value >= int(rule.get("min", 0)))


## A cast-local copy with the held-unit bonus, optional spend and a shared first-hit receipt.
func begin_cast(world: RunWorld, key: String, stats: Dictionary) -> Dictionary:
	if config.is_empty() or key not in world.jobs.skill_pool(world.job_id()):
		return stats
	var out := stats.duplicate()
	var rule: Dictionary = world.book.meter_rule(key)
	var role := String(rule.get("role", ""))
	var per: Dictionary = config.get("per_unit", {})
	var factor := 1.0 + value * float(per.get("value", 0.0)) if String(per.get("stat", "")) == "damage" else 1.0
	if rule.has("spend"):
		var available := maxi(0, value - maxi(0, roundi(world.loadout.skill_stat(key, "meter_keep", 0.0))))
		var spent := available if str(rule.spend) == "all" else clampi(int(rule.spend), 0, available)
		factor *= 1.0 + spent * float(rule.get("damage_per_unit", 0.0))
		out["meter_spent"] = spent
		_set_value(value - spent, world.events)
	for field: String in SkillRunner.DAMAGE_FIELDS:
		out[field] = float(out.get(field, 0.0)) * factor
	if role == "" or String(config.get("gain", {}).get("exclude", "")) != role:
		out["meter_receipt"] = {"landed": false}
	return out


## Records the first positive damage of a cast, including delayed/projectile/summon hits.
func landed(receipt: Dictionary, events: Array) -> void:
	if receipt.is_empty() or bool(receipt.landed):
		return
	receipt.landed = true
	gain("cast_landed", events)


## Chooses among prepared finisher plans; a single-target scheduled-boss strike wins, otherwise target count.
## The ordinary learned/cooldown order breaks ties. No skill IDs or job IDs enter admission.
func preferred(world: RunWorld, ready: Array[String]) -> String:
	var best := ""
	var score := -1
	for key in ready:
		var definition := world.book.def(key)
		if String(world.book.meter_rule(key).get("role", "")) != "finisher" or not admits(definition):
			continue
		var st := world.runner.stats_of(world, key)
		if not HpRisk.admits(world, st) or not world.runner.has_target(world, key, st, world.cast_origin()):
			continue
		var plan := world.runner.prepare_cast(world, key, st, world.cast_origin())
		var targets: PackedInt32Array = plan.get("targets", PackedInt32Array())
		var count := mini(targets.size(), SkillRunner.strike_count(st))
		if count < maxi(1, int(st.cast_params.get("min_targets", 1))):
			continue
		# tier C: single-target finishers prefer a scheduled boss over the crowd finisher.
		var boss := SkillRunner.strike_count(st) == 1 and not targets.is_empty() and world.is_scheduled_boss(targets[0])
		var candidate := count + (world.swarm.capacity() if boss else 0)
		if candidate > score:
			best = key
			score = candidate
	return best


func _set_value(next: int, events: Array) -> void:
	var clamped := clampi(next, 0, int(config.get("max", 0)))
	if clamped == value:
		return
	value = clamped
	events.append({"type": "meter_changed", "id": String(config.id), "value": value, "max": int(config.max)})
