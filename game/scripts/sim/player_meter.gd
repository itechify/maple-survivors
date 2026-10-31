class_name PlayerMeter
extends RefCounted
## Round-owned event counter and cast snapshots, shared by Combo, Energy Charge and meso charge.
## No RNG: delayed attacks share a small cast receipt so only their first damaging hit earns a unit. The one clock is
## the optional `decay` of the meso charge (GAME_DESIGN 7.94); a meter without it never reads `step`'s dt.

var config: Dictionary
var value := 0
## Mesos picked up but not yet worth a unit (`gain.per_mesos`); kept across maps, empty at round start (a new meter).
var carry := 0
var _decay_clock := 0.0
var _held_seconds := 0.0
var _seconds := 0.0
var _peak := 0


## Creates a round counter from the job-owned meter definition.
func _init(definition: Dictionary = {}) -> void:
	config = definition.duplicate(true)


## Gains the configured amount for an event, emitting only actual changes.
func gain(event: String, events: Array) -> void:
	var rule: Dictionary = config.get("gain", {})
	if event == String(rule.get("event", "")):
		_set_value(value + int(rule.get("amount", 0)), events)


## Whether this meter's gain rule is driven by `event`.
func listens(event: String) -> bool:
	return not config.is_empty() and String(config.get("gain", {}).get("event", "")) == event


## Gains for an event that carries an amount. A rule with `per_mesos` earns its `amount` once per `per_mesos` of the
## event's amount and holds the remainder in `carry`; a rule without it behaves like `gain`.
func gain_amount(event: String, amount: int, events: Array) -> void:
	var rule: Dictionary = config.get("gain", {})
	if event != String(rule.get("event", "")):
		return
	if not rule.has("per_mesos"):
		gain(event, events)
		return
	var taken := MesoCharge.take(carry, amount, int(rule.per_mesos))
	carry = int(taken.carry)
	if int(taken.units) > 0:
		_set_value(value + int(taken.units) * int(rule.get("amount", 0)), events)


## Advances the optional decay clock and the held-pip statistics by one fixed tick. Without a `decay` key nothing
## changes but the statistics, so Combo and Energy Charge keep their values and events exactly.
func step(dt: float, events: Array) -> void:
	if config.is_empty():
		return
	var rule: Dictionary = config.get("decay", {})
	if not rule.is_empty():
		var stepped := MesoCharge.decay(_decay_clock, dt, float(rule.get("interval", 0.0)), value, int(rule.get("amount", 1)))
		_decay_clock = float(stepped.clock)
		if int(stepped.lost) > 0:
			_set_value(value - int(stepped.lost), events)
	_seconds += dt
	_held_seconds += value * dt
	_peak = maxi(_peak, value)


## Time-weighted mean of the held units and the most held, for the run summary ({} for a job without a meter).
func stats() -> Dictionary:
	if config.is_empty():
		return {}
	return {"mean": _held_seconds / _seconds if _seconds > 0.0 else 0.0, "peak": maxi(_peak, value)}


## Public HUD state; empty for jobs without a meter.
func snapshot() -> Dictionary:
	if config.is_empty():
		return {}
	return {"id": String(config.id), "value": value, "max": int(config.max), "art": String(config.get("art", ""))}


## Whether a skill's meter gate is satisfied.
func admits(definition: Dictionary) -> bool:
	var rule: Dictionary = definition.get("meter", {})
	# A read-only block (`read_per_unit` alone) never gates, with or without a meter.
	return rule.is_empty() or _reads_only(rule) or (not config.is_empty() and value >= int(rule.get("min", 0)))


## A cast-local copy with the held-unit bonus, optional spend and a shared first-hit receipt.
func begin_cast(world: RunWorld, key: String, stats: Dictionary) -> Dictionary:
	if config.is_empty() or key not in world.jobs.skill_pool(world.job_id()):
		return stats
	var out := stats.duplicate()
	var rule: Dictionary = world.book.meter_rule(key)
	var role := String(rule.get("role", ""))
	var per: Dictionary = config.get("per_unit", {})
	var factor := 1.0 + value * float(per.get("value", 0.0)) if String(per.get("stat", "")) == "damage" else 1.0
	# tier C: the held-pip read (Shadow Meso, NL9) multiplies on top of per_unit and spends nothing.
	factor *= 1.0 + value * float(rule.get("read_per_unit", 0.0))
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


func _reads_only(rule: Dictionary) -> bool:
	return rule.has("read_per_unit") and not (rule.has("min") or rule.has("spend") or rule.has("role"))


func _set_value(next: int, events: Array) -> void:
	var clamped := clampi(next, 0, int(config.get("max", 0)))
	if clamped == value:
		return
	value = clamped
	if value == 0:
		_decay_clock = 0.0
	events.append({"type": "meter_changed", "id": String(config.id), "value": value, "max": int(config.max)})
