class_name MobActions
extends RefCounted
## Authored stances of ordinary (non-boss) mobs, per swarm slot in packed arrays: a mob attack's windup or a mob
## skill's cast stance, held for its canonical duration (docs/ARCHITECTURE.md 4.4.1). Scheduled bosses keep theirs in
## BossDirector; view() composes both into the one per-slot snapshot MobSwarm.step and MobRenderer read. While no
## ordinary stance is live, view() returns the boss snapshot itself, so runs without ordinary attackers are unchanged.

var action := PackedStringArray()
var start := PackedFloat64Array()
var until := PackedFloat64Array()
var facing := PackedInt32Array()
var _acting := PackedInt32Array()
var _written := PackedInt32Array()
var _view := {"actions": PackedStringArray(), "times": PackedFloat32Array(), "facings": PackedInt32Array()}


## Grows the per-slot arrays with the swarm; new slots hold no stance.
func resize(capacity: int) -> void:
	if action.size() >= capacity:
		return
	action.resize(capacity)
	start.resize(capacity)
	until.resize(capacity)
	facing.resize(capacity)


## Holds `stance` facing `dir` on slot for `seconds` from `now`.
func begin(slot: int, stance: String, seconds: float, dir: int, now: float) -> void:
	if not _acting.has(slot):
		_acting.append(slot)
	action[slot] = stance
	start[slot] = now
	until[slot] = now + maxf(0.0, seconds)
	facing[slot] = dir


## Whether slot is still inside an authored stance at `now` (attacks and skills share this gate, like bosses).
func busy(slot: int, now: float) -> bool:
	return slot < action.size() and action[slot] != "" and now < until[slot] - 1e-6


## A new mob in the slot (or one relocated out of it) starts without a stance.
func reset_slot(slot: int) -> void:
	if slot < action.size():
		action[slot] = ""
		until[slot] = 0.0


## The per-slot action snapshot: `boss_view` (BossDirector.action_snapshot) when no ordinary stance is live, else a
## reused composed copy with both. Borrowed: read it at once, like the boss snapshot.
func view(boss_view: Dictionary, bosses: BossDirector, swarm: MobSwarm, now: float) -> Dictionary:
	_expire(now)
	var actions: PackedStringArray = _view.actions
	var times: PackedFloat32Array = _view.times
	var facings: PackedInt32Array = _view.facings
	var capacity := swarm.capacity()
	if actions.size() != capacity:
		actions.resize(capacity)
		times.resize(capacity)
		facings.resize(capacity)
	for slot in _written:
		if slot < capacity:
			actions[slot] = ""
	_written.resize(0)
	if _acting.is_empty():
		return boss_view
	var boss_actions: PackedStringArray = boss_view.get("actions", PackedStringArray())
	var boss_times: PackedFloat32Array = boss_view.get("times", PackedFloat32Array())
	var boss_facings: PackedInt32Array = boss_view.get("facings", PackedInt32Array())
	for record: Dictionary in bosses.records:
		var slot := int(record.slot)
		if slot >= 0 and slot < capacity and slot < boss_actions.size() and boss_actions[slot] != "":
			actions[slot] = boss_actions[slot]
			times[slot] = boss_times[slot]
			facings[slot] = boss_facings[slot]
			_written.append(slot)
	for slot in _acting:
		if slot < capacity and swarm.active[slot] != 0:
			actions[slot] = action[slot]
			times[slot] = maxf(0.0, now - start[slot])
			facings[slot] = facing[slot]
			_written.append(slot)
	return _view


func _expire(now: float) -> void:
	var i := 0
	while i < _acting.size():
		var slot := _acting[i]
		if action[slot] != "" and now < until[slot] - 1e-6:
			i += 1
			continue
		action[slot] = ""
		_acting.remove_at(i)
