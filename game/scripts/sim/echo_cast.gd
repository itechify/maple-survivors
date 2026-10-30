class_name EchoCast
extends RefCounted
## Echo summon (M11, docs/GAME_DESIGN.md 7.91): repeats a star cast from every living clone (a `PlayerSummons` summon whose
## definition carries `summon.echo`) a short delay later at a percent of its damage. Owned by SkillRunner as `echoes`.
## Entries are plain dictionaries holding a detached cast snapshot and a logical target identity, like BurstCast's.
var _entries: Array[Dictionary] = []

## Drops unfinished echoes at a map boundary, death or Hidden, without touching cooldowns or launched projectiles.
func clear_pending() -> void:
	_entries.clear()

## Whether this skill still has echoes scheduled.
func has_skill(key: String) -> bool:
	for entry in _entries:
		if String(entry.key) == key:
			return true
	return false

## Number of echoes scheduled and not yet thrown.
func pending_count() -> int:
	return _entries.size()

## Schedules one echo per living clone and per recorded shot of a successful cast of `key`. `shots` holds
## {slot, aim} of every shot the cast fired. An echoed cast, a skill without an `echo` flag and a world without a clone
## schedule nothing.
func on_cast(world: RunWorld, key: String, st: Dictionary, shots: Array) -> void:
	if shots.is_empty() or bool(st.get("echo", false)):
		return
	var rule: Dictionary = world.book.def(key).get("echo", {})
	if rule.is_empty():
		return
	var summons := world.runner.summons
	for i in summons.clones():
		var cfg: Dictionary = summons.definitions[i].echo
		var field := String(cfg.get("attack_field", "x")) if String(rule.get("class", "")) == "attack" \
			else String(cfg.get("skill_field", "y"))
		var partner := String(summons.stats[i].skill)
		# The Shadow Partner's level field at its rank, as a fraction, times its `damage` modifier (Shadow Power, Mastery).
		var percent := world.book.canonical(partner, int(summons.stats[i].level), field) / 100.0 \
			* world.loadout.skill_stat(partner, "damage", 1.0)
		var echo_st := SkillRunner.cast_snapshot(st)
		echo_st.erase("meter_receipt")
		echo_st.erase("damage_heal")
		echo_st["damage_min"] = float(st.damage_min) * percent
		echo_st["damage_max"] = float(st.damage_max) * percent
		echo_st["echo"] = true
		for shot: Dictionary in shots:
			_entries.append({"key": key, "st": echo_st, "clone": i, "uid": summons.uid[i],
				"left": float(cfg.get("delay", 0.25)), "slot": int(shot.slot),
				"identity": world.swarm.identity[int(shot.slot)], "aim": shot.aim,
				"overshoot": float(cfg.get("overshoot", 0.0))})

## Advances the delays and throws the due echoes. Hidden and death cancel the unthrown ones (as for bursts).
func step(dt: float, world: RunWorld) -> void:
	if _entries.is_empty():
		return
	if world.is_hidden() or bool(world.player_state.dead):
		clear_pending()
		return
	var i := 0
	while i < _entries.size():
		var entry := _entries[i]
		entry.left = float(entry.left) - dt
		if float(entry.left) > 1e-9:
			i += 1
			continue
		_entries.remove_at(i)
		_throw(world, entry)

func _throw(world: RunWorld, entry: Dictionary) -> void:
	var summons := world.runner.summons
	var c := int(entry.clone)
	if c >= summons.active.size() or summons.active[c] == 0 or summons.uid[c] != int(entry.uid) or summons.left[c] <= 0.0:
		return # tier C: an expired or replaced clone throws nothing
	var st: Dictionary = entry.st
	var body := Vector2(summons.x[c], summons.y[c] - world.cast_height)
	var reach := float(st.range)
	var slot := int(entry.slot)
	var target := Vector2.ZERO
	var live := world.swarm.is_live(slot) and world.swarm.identity[slot] == int(entry.identity)
	if live:
		target = world.mob_center(slot)
		var limit := reach + float(entry.overshoot)
		live = target.distance_squared_to(body) <= limit * limit
	if not live:
		# tier C: a dead or out-of-reach target retargets to the nearest monster in reach of the clone; none drops the echo.
		slot = world.runner.nearest_to(world, body, reach)
		if slot < 0:
			return
		target = world.mob_center(slot)
	var side := signf(target.x - body.x)
	if side == 0.0:
		side = float(summons.facing[c])
	var hand := body + Vector2(side * world.cast_forward, 0.0)
	if signf(target.x - hand.x) != signf(target.x - body.x):
		hand = body # a target inside the reach of the hand: throw straight from the body, as the owner does
	summons.facing[c] = int(side)
	var flight := st
	if float(entry.overshoot) > 0.0:
		# tier C (ROSTER_PLAN D12): the clone trails the owner by `overshoot`, so its star also flies that much farther and still
		# lands on a monster at the end of the owner's reach. The caller's snapshot is shared, so the copy is shallow.
		flight = st.duplicate()
		flight["range"] = reach + float(entry.overshoot)
	world.runner.fire_shot(world, String(entry.key), flight, body, target, hand)
	world.emit("echo_cast", {"skill": String(entry.key), "clone": c, "pos": hand, "facing": int(side)})
