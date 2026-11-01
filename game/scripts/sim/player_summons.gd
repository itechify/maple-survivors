class_name PlayerSummons
extends RefCounted
## Packed player-owned allies, shared by every skill with a summon block. SkillRunner owns map cleanup.
## Resolved cast snapshots are cold metadata; position, lifetime, attack and animation state use parallel arrays.
var active := PackedByteArray()
var x := PackedFloat32Array()
var y := PackedFloat32Array()
var left := PackedFloat64Array()
var facing := PackedInt32Array()
var age := PackedFloat64Array()
var action := PackedStringArray()
var wait := PackedFloat64Array()
var impact := PackedFloat64Array()
var stats: Array[Dictionary] = []
var definitions: Array[Dictionary] = []
var offsets := PackedFloat32Array()
## Spawn serial of each slot: a delayed echo names the clone it belongs to, and a recast reuses the slot (EchoCast).
var uid := PackedInt64Array()
var _next_uid := 1
## Pulse countdowns of the summons whose definition carries `summon.support` (docs/GAME_DESIGN.md 7.67).
var support := SupportSummons.new()
## The `summon.behavior` entry points (spec #384 M9, docs/GAME_DESIGN.md 7.121): a definition without the key is the trailing
## ally below. Each behaviour object owns what its allies do each tick (`spawn_slot`, `step_slot`); this seam owns the
## lifecycle (spawn, expiry, replace, clear). A new behaviour adds a field here and one line in each of `_behavior` and
## `describe_behavior`, and implements `spawn_slot`, `step_slot`, `holds_expiry` and a static `describe`.
var turret := SummonTurret.new()
var kamikaze := SummonKamikaze.new()
var _buf := PackedInt32Array()

## Test hook: number of allies still able to attack.
func living_count() -> int:
	var count := 0
	for i in active.size():
		if active[i] != 0 and left[i] > 0.0:
			count += 1
	return count

## Slots of the living clones (summons whose definition carries `summon.echo`, docs/GAME_DESIGN.md 7.94.3).
func clones() -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in active.size():
		if active[i] != 0 and left[i] > 0.0 and definitions[i].has("echo"):
			out.append(i)
	return out

## Removes map-local allies while preserving the runner's cooldowns.
func clear() -> void:
	active.fill(0)
	turret.clear()

## Calls allies using resolved rank stats; recasting replaces this skill's previous group.
func spawn(world: RunWorld, st: Dictionary) -> void:
	for i in active.size():
		if active[i] != 0 and stats[i].skill == st.skill:
			active[i] = 0
	var d: Dictionary = world.book.def(st.skill).summon.duplicate(true)
	# Keep the definition block distinct from the resolved st.support pulse list.
	if d.has("support"):
		d["support_definition"] = d["support"]
		d.erase("support")
	if d.has("echo") and not d.has("attack"):
		d["attack"] = "" # a clone never strikes: no attack animation or cycle
	var node: Dictionary = world.book.skill_node(st.skill).get("summon", {})
	var attack_node: Dictionary = node.get(String(d.attack), {})
	d["info"] = attack_node.get("info", {})
	if d.has("attack_after"):
		# tier C (Gaviota, spec #384 C6): a literal wind-up in seconds replaces the WZ `attackAfter` (its 1.92 s outlasts the
		# 0.84 s dive art, so the bird would hang for a second before the grenade lands).
		d["info"] = d.info.duplicate()
		d.info["attackAfter"] = float(d.attack_after) * 1000.0
	d["durations"] = {}
	# Spec #332 M8: `move` names the animation node played while following (`fly` for a flyer), `hover` lifts the
	# follower above its trailing point, and an attack node's `info/effect` is drawn on each struck monster.
	d["move"] = String(d.get("move", "move"))
	d["hover"] = float(d.get("hover", 0.0))
	d["settle"] = bool(d.get("settle", false))
	var strike: Variant = d.info.get("effect")
	d["strike_effect"] = "%s/%s/info/effect" % [d.path, d.attack] if strike is Dictionary else ""
	var anims: Array[String] = ["summoned", "stand", String(d.move), "die"]
	if String(d.attack) != "": # a support summon has no attack animation, only the pulses' own
		anims.append(String(d.attack))
	for pulse: Dictionary in st.get("support", []):
		anims.append(String(pulse.anim))
	for a: String in anims:
		d.durations[a] = WeaponInfo.frame_times(node.get(a, {})).total
	var count := maxi(1, roundi(world.loadout.skill_stat(st.skill, "summon_count", 1.0)))
	for ordinal in count:
		var i := active.find(0)
		if i < 0:
			i = active.size()
			active.append(0)
			x.append(0)
			offsets.append(0)
			uid.append(0)
			y.append(0)
			left.append(0)
			facing.append(0)
			age.append(0)
			action.append("")
			wait.append(0)
			impact.append(-1)
			stats.append({})
			definitions.append({})
		active[i] = 1
		uid[i] = _next_uid
		_next_uid += 1
		offsets[i] = ordinal * float(d.get("ordinal_spread", 36.0)) # tier C: per-ally spacing.
		x[i] = world.player.pos.x + offsets[i]
		y[i] = world.player.pos.y - float(d.hover) # tier C: a flyer enters at its hover height.
		facing[i] = world.player.facing
		left[i] = maxf(0.0, world.loadout.skill_stat(st.skill, "duration", float(st.duration)))
		stats[i] = SkillRunner.cast_snapshot(st)
		definitions[i] = d
		action[i] = ""
		set_action(i, "summoned")
		wait[i] = float(d.durations.summoned)
		impact[i] = -1.0
		if d.has("support_definition"):
			support.begin(i, st.get("support", []), d.durations)
		var behavior: Variant = _behavior(d)
		if behavior != null:
			behavior.spawn_slot(self, i, ordinal, world, d)
		var spawned := {"skill": st.skill, "slot": i}
		var sound := String(world.book.def(st.skill).get("sounds", {}).get("summon", ""))
		if sound != "":
			spawned["sound"] = sound # only when listed: Elquines' event bytes stay what the F/P oracles hash.
		world.emit("summon_spawn", spawned)

## Advances follow, windup, impact and expiry with fixed simulation ticks.
func step(dt: float, world: RunWorld) -> void:
	turret.step_balls(dt, world) # before the allies: a ball launched this tick first flies on the next one
	for i in active.size():
		if active[i] == 0:
			continue
		var d := definitions[i]
		age[i] += dt
		left[i] -= dt
		var behavior: Variant = _behavior(d)
		if left[i] <= 0.0 and not (behavior != null and behavior.holds_expiry(i)):
			if action[i] != "die":
				set_action(i, "die")
				impact[i] = -1.0
			if age[i] >= float(d.durations.die):
				active[i] = 0
			continue
		if behavior != null:
			behavior.step_slot(self, i, dt, world)
			continue
		var pulse_anim := support.step(i, dt, world) if d.has("support_definition") else ""
		wait[i] -= dt
		if impact[i] >= 0.0:
			impact[i] -= dt
			if impact[i] <= 1e-6:
				impact[i] = -1.0
				if not world.is_hidden() and not bool(world.player_state.dead):
					strike(i, world)
		# Opt-in `settle`: once the attack animation is over a follower leaves its pose and keeps following until the
		# attack interval ends (the hawk's body frame is empty while its bolt strikes), without choosing a new target.
		var cooling := wait[i] > 1e-6
		if cooling and not (bool(d.settle) and action[i] != "summoned" and impact[i] < 0.0
				and (action[i] != String(d.attack) or age[i] >= float(d.durations[d.attack]))):
			continue
		var pos := Vector2(x[i], y[i])
		var destination := world.player.pos + Vector2(offsets[i], -float(d.hover)) \
			- Vector2(world.player.facing * float(d.follow_distance), 0)
		# tier C: one-pixel stand/move deadzone prevents animation flicker at the trailing point.
		var moved := pos.distance_to(destination) > 1.0
		if pos.distance_to(destination) > float(d.teleport_distance):
			pos = destination
		else:
			pos = pos.move_toward(destination, float(d.follow_speed) * dt)
		x[i] = pos.x
		y[i] = pos.y
		set_action(i, pulse_anim if pulse_anim != "" else String(d.move) if moved else "stand")
		if d.has("echo"):
			facing[i] = world.player.facing # a clone mirrors its owner and never strikes (EchoCast throws its stars)
			continue
		if d.has("support_definition"):
			continue
		if world.is_hidden() or bool(world.player_state.dead):
			continue
		if cooling:
			continue
		var targets := _targets(i, world, true)
		if targets.is_empty():
			continue
		facing[i] = 1 if world.mob_center(targets[0]).x > x[i] else -1
		set_action(i, String(d.attack))
		impact[i] = float(d.info.get("attackAfter", 0.0)) / 1000.0
		wait[i] = maxf(float(d.attack_interval), maxf(float(d.durations[d.attack]), impact[i]))
		world.emit("summon_attack", {"skill": stats[i].skill, "slot": i, "pos": pos})

## The card / Skill-window line of a definition's `summon.behavior` ("" for the trailing ally): the one other place, besides
## `_behavior`, that names the behaviours. `stats` are the cast's resolved stats (Loadout.stats).
static func describe_behavior(book: SkillBook, key: String, summon: Dictionary, stats: Dictionary) -> String:
	match String(summon.get("behavior", "")):
		"turret":
			return SummonTurret.describe(book, key, String(summon.attack), float(stats.get("area", 1.0)))
		"kamikaze":
			return SummonKamikaze.describe(book, key, String(summon.attack), int(stats.get("count", 1)) - 1)
	return ""


## The behaviour object for a definition's `summon.behavior`, or null for the trailing ally.
func _behavior(d: Dictionary) -> Variant:
	match String(d.get("behavior", "")):
		"turret":
			return turret
		"kamikaze":
			return kamikaze
	return null

## Entry points for the behaviours (SummonTurret, SummonKamikaze): they use the lifecycle and the strike this seam owns.
## Plays animation node `value` from its first frame unless it is already playing.
func set_action(i: int, value: String) -> void:
	if action[i] != value:
		action[i] = value
		age[i] = 0.0

## The attack node's box of ally i, feet-relative, scaled by the cast's `area`.
func box(i: int) -> Rect2:
	var r: Dictionary = definitions[i].info.get("range", {})
	var lt: Array = r.get("lt", {}).get("$v", [0, 0])
	var rb: Array = r.get("rb", {}).get("$v", [0, 0])
	var scale := float(stats[i].area)
	return Rect2(Vector2(float(lt[0]), float(lt[1])) * scale,
		Vector2(float(rb[0]) - float(lt[0]), float(rb[1]) - float(lt[1])) * scale)

func _targets(i: int, world: RunWorld, both_sides: bool) -> PackedInt32Array:
	var pos := Vector2(x[i], y[i] + float(definitions[i].hover)) # the box is feet-relative: hover is only flight height.
	var attack_box := box(i)
	var mirrored := Rect2(Vector2(-attack_box.end.x, attack_box.position.y), attack_box.size)
	var query := attack_box.merge(mirrored) if both_sides else (mirrored if facing[i] > 0 else attack_box)
	query.position += pos
	var n := world.mob_grid.query_rect(query.grow(world.body_pad), _buf)
	var matches: Array[int] = []
	for c in n:
		var m := _buf[c]
		if world.swarm.active[m] == 0:
			continue
		var body := world.swarm.mob_kind(m).hitbox_at(world.swarm.x[m], world.swarm.y[m], world.swarm.facing[m])
		if query.intersects(body, true):
			matches.append(m)
	# Opt-in `summon.priority_status` (tier C reading of the WZ attack `priority`): after scheduled bosses (they take no
	# statuses), monsters running that status come before the rest. Without the key the sort is the shared one, untouched.
	var priority := MobSwarm.STATUS_NAMES.find(String(definitions[i].get("priority_status", "")))
	matches.sort_custom(func(a: int, b: int) -> bool:
		if priority >= 0:
			var boss := world.is_scheduled_boss(a)
			if boss != world.is_scheduled_boss(b):
				return boss
			var marked := world.swarm.status_time(a, priority) > 0.0
			if marked != (world.swarm.status_time(b, priority) > 0.0):
				return marked
		return world.targets_before(a, world.mob_center(a).distance_squared_to(pos),
			b, world.mob_center(b).distance_squared_to(pos)))
	return PackedInt32Array(matches)


## The strike's target count before `count` modifiers: the attack node's `info.mobCount`, or, with the opt-in `summon.count_field`,
## that field of the cast's mapped level (Bahamut: 3, 6 at level 30).
func base_count(i: int, world: RunWorld) -> float:
	var field := String(definitions[i].get("count_field", ""))
	var fallback := float(definitions[i].info.get("mobCount", 1))
	return world.book.canonical(String(stats[i].skill), int(stats[i].level), field, fallback) if field != "" else fallback


## Hits ally i's attack box once, exactly as the trailing ally's strike does.
func strike(i: int, world: RunWorld) -> void:
	var st := stats[i]
	var targets := _targets(i, world, false)
	var count := maxi(1, roundi(world.loadout.skill_stat(st.skill, "count", base_count(i, world))))
	var strike_art := String(definitions[i].strike_effect)
	for t in mini(count, targets.size()):
		if strike_art != "":
			world.emit("summon_strike", {"skill": st.skill, "slot": i, "mob": targets[t],
				"pos": world.mob_center(targets[t]), "effect": strike_art})
		for line in int(st.attack_count):
			if world.swarm.active[targets[t]] == 0:
				break
			world.hit_mob(targets[t], st, world.visual_index(st.hit))
