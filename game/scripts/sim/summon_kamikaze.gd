class_name SummonKamikaze
extends RefCounted
## The kamikaze summon (spec #384 M9, GAME_DESIGN 7.121): a PlayerSummons ally with `summon.behavior: "kamikaze"`, single
## use. It spawns beside the caster, picks the k-th nearest living monster (k = its `summon_count` ordinal; bosses and,
## once the mark lands, marked monsters first, all through RunWorld.targets_before) within `info.range.r` of the caster,
## flies at `follow_speed` to `hover` px above it and, within the attack box's half-width, starts its attack animation.
## At `attackAfter` it strikes up to `mobCount` plus `count` monsters in the box (feet-relative, as PlayerSummons.strike),
## then plays `die` and frees its slot. With no monster in reach it waits by the caster; the level `time` is the wait
## limit, after which PlayerSummons expires it with no hit (no refund). A bird that has locked a monster is past waiting:
## `holds_expiry` keeps it alive until its dive lands or the monster is gone.
##
## PlayerSummons keeps the lifecycle (spawn, spacing, recast replaces, expiry and `die`, map transfer) and calls
## `spawn_slot` and `step_slot`. Nothing here names a job, a skill or an id. Pure sim: no RNG beyond the damage rolls.

const SEEK := 0
const STRIKE := 1
const SPENT := 2

## tier C: the ally hunts the monster it first chose until that one is gone, then picks again.
## tier C: the level `time` ends only a bird without a locked target; a bird chasing or diving runs on to its strike.
## tier C: an ordinal past the number of monsters in reach takes the farthest one in reach (a bird is never idle for it).
var ordinal := PackedInt32Array()
var phase := PackedByteArray()
var target := PackedInt32Array()
var target_id := PackedInt64Array()
var _buf := PackedInt32Array()


## Called once for each ally of a fresh cast with its `summon_count` ordinal (0 for the first).
func spawn_slot(_summons: PlayerSummons, i: int, nth: int, _world: RunWorld, _d: Dictionary) -> void:
	while ordinal.size() <= i:
		ordinal.append(0)
		phase.append(SEEK)
		target.append(-1)
		target_id.append(0)
	ordinal[i] = nth
	phase[i] = SEEK
	target[i] = -1
	target_id[i] = 0


## Whether the level `time` running out must not end ally i yet: it has locked a monster or is diving.
func holds_expiry(i: int) -> bool:
	return phase[i] == STRIKE or (phase[i] == SEEK and target[i] >= 0)


## One tick of one kamikaze: hunt, wind up, strike once.
func step_slot(s: PlayerSummons, i: int, dt: float, world: RunWorld) -> void:
	var d := s.definitions[i]
	var away := world.is_hidden() or bool(world.player_state.dead)
	if target[i] >= 0 and not _alive(world, i):
		target[i] = -1
	if phase[i] == STRIKE:
		if away:
			return # the strike waits for the caster, as a follower's pending hit is suppressed
		_chase(s, i, dt, world)
		s.impact[i] -= dt
		if s.impact[i] <= 1e-6:
			s.impact[i] = -1.0
			s.strike(i, world)
			phase[i] = SPENT
			s.left[i] = 0.0 # single use: PlayerSummons plays `die` and frees the slot
		return
	if not away and target[i] < 0:
		_pick(s, i, world)
	if target[i] < 0:
		_wait(s, i, dt, world)
		return
	var dest := _destination(s, i, world)
	var pos := Vector2(s.x[i], s.y[i])
	if pos.distance_to(dest) <= s.box(i).size.x * 0.5:
		phase[i] = STRIKE
		s.facing[i] = 1 if dest.x > pos.x else -1 if dest.x < pos.x else s.facing[i]
		s.set_action(i, String(d.attack))
		s.impact[i] = float(d.info.get("attackAfter", 0.0)) / 1000.0
		world.emit("summon_attack", {"skill": s.stats[i].skill, "slot": i, "pos": pos})
		return
	_chase(s, i, dt, world)


## Where the ally flies to: `hover` px above the target's feet.
func _destination(s: PlayerSummons, i: int, world: RunWorld) -> Vector2:
	var m := target[i]
	return Vector2(world.swarm.x[m], world.swarm.y[m] - float(s.definitions[i].hover))


func _chase(s: PlayerSummons, i: int, dt: float, world: RunWorld) -> void:
	if target[i] < 0:
		return # the monster died during the wind-up: the strike lands where the ally hangs
	var d := s.definitions[i]
	var dest := _destination(s, i, world)
	var pos := Vector2(s.x[i], s.y[i])
	var next := pos.move_toward(dest, float(d.follow_speed) * dt)
	if next.x != pos.x:
		s.facing[i] = 1 if next.x > pos.x else -1
	s.x[i] = next.x
	s.y[i] = next.y
	if phase[i] == SEEK:
		s.set_action(i, String(d.move))


## No monster in reach: trail the caster like a follower does.
func _wait(s: PlayerSummons, i: int, dt: float, world: RunWorld) -> void:
	var d := s.definitions[i]
	var pos := Vector2(s.x[i], s.y[i])
	var destination := world.player.pos + Vector2(s.offsets[i], -float(d.hover)) \
		- Vector2(world.player.facing * float(d.follow_distance), 0)
	var moved := pos.distance_to(destination) > 1.0 # tier C: the follower's one-pixel stand/move deadzone
	if pos.distance_to(destination) > float(d.teleport_distance):
		pos = destination
	else:
		pos = pos.move_toward(destination, float(d.follow_speed) * dt)
	s.x[i] = pos.x
	s.y[i] = pos.y
	if s.action[i] == "summoned" and s.age[i] < float(d.durations.summoned):
		return
	s.facing[i] = world.player.facing
	s.set_action(i, String(d.move) if moved else "stand")


func _pick(s: PlayerSummons, i: int, world: RunWorld) -> void:
	if s.action[i] == "summoned" and s.age[i] < float(s.definitions[i].durations.summoned):
		return # still being called in
	var r := float(s.definitions[i].info.get("range", {}).get("r", 0.0))
	var origin := world.cast_origin() # where the cast was admitted from (SkillRunner.has_target)
	var n := world.mob_grid.query_rect(Rect2(origin - Vector2(r, r), Vector2(r, r) * 2.0).grow(world.body_pad), _buf)
	var found: Array[int] = []
	for k in n:
		var m := _buf[k]
		if world.swarm.active[m] != 0 and world.mob_center(m).distance_to(origin) <= r:
			found.append(m)
	if found.is_empty():
		return
	found.sort_custom(func(a: int, b: int) -> bool:
		return world.targets_before(a, world.mob_center(a).distance_squared_to(origin),
			b, world.mob_center(b).distance_squared_to(origin)))
	var m := found[mini(ordinal[i], found.size() - 1)]
	target[i] = m
	target_id[i] = world.swarm.identity[m]


func _alive(world: RunWorld, i: int) -> bool:
	var m := target[i]
	return world.swarm.active[m] != 0 and world.swarm.identity[m] == target_id[i]


## The Skill-window line: how far the bird looks and that it is spent by one dive.
static func describe(book: SkillBook, key: String, attack: String) -> String:
	var info: Dictionary = book.skill_node(key).get("summon", {}).get(attack, {}).get("info", {})
	var reach := float(info.get("range", {}).get("r", 0.0))
	if reach <= 0.0:
		return ""
	return "Dives once at a monster within %d px of you, then is spent" % roundi(reach)
