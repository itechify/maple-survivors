class_name BasicAttack
extends RefCounted
## One player's automatic physical swing: canonical weapon interval, body-frame impact timing and afterimage box.
## Starts only in a skill-free standing/airborne tick; pending swings complete without locking player movement.

## tier B: the five standard one-handed swing/stab actions (pre-Big-Bang client descriptions).
const ACTIONS := ["swingO1", "swingO2", "swingO3", "stabO1", "stabO2"]
## The bare-handed punch when no weapon is worn (v83 lets a character fight without one). tier A: the sound is
## Sound.wz/Weapon.img/barehands. tier C: normal attack speed 6, the same five body actions, no afterimage.
const BARE_HANDS := {"attackSpeed": 6, "sfx": "barehands"}
## tier C: the punch's reach, feet-relative and facing left (shorter than the starter Sword's swing).
const BARE_HANDS_BOX := Rect2(-55, -55, 50, 50)

var cooldown := 0.0
var _body: Dictionary
var _images: Dictionary
var _pending := {}
## weapon id -> reach(); the afterimage and body data never change during a run.
var _reach := {}
var _buffer := PackedInt32Array()


func _init(body: Dictionary = {}, images: Dictionary = {}) -> void:
	_body = body
	_images = images
	_buffer.resize(128)


## Advances the existing swing, then starts one when its interval and the shared action gate allow it.
func step(dt: float, world: RunWorld) -> void:
	cooldown -= dt
	if not _pending.is_empty():
		_pending.left = float(_pending.left) - dt
		if float(_pending.left) <= 1e-9:
			_impact(world)
			_pending = {}
	if cooldown > 1e-9 or not _pending.is_empty() or not world.can_cast() or world.runner.fired_this_tick:
		return
	if world.player.state not in [PlayerMotion.ST_STAND, PlayerMotion.ST_AIR]:
		return
	var weapon := world.weapon_id()
	var info := world.weapon_info() if weapon > 0 else BARE_HANDS
	if info.is_empty():
		return
	var action: String = ACTIONS[world.basic_rng.randi_range(0, ACTIONS.size() - 1)]
	var spec := _spec(info, action)
	if spec.is_empty() or not _target_in_reach(world, info):
		return
	_pending = spec
	_pending["weapon_id"] = weapon
	_pending["action"] = action
	_pending["facing"] = world.player.facing
	_pending["str"] = int(world.player_state.str)
	_pending["dex"] = int(world.player_state.dex)
	_pending["level"] = int(world.player_state.level)
	_pending["watk"] = world.weapon_attack()
	_pending["left"] = float(spec.hit_after)
	cooldown = maxf(cooldown, -dt) + float(spec.interval)
	world.start_action(action, float(spec.action_time), true)
	_emit(world, "start")


## Horizontal reach in px of the held weapon's swing: the farthest afterimage box edge over the five stances (the same
## stances that gate starting a swing), or the punch's box bare-handed; 0 when the weapon cannot swing. Cached per weapon.
func reach(world: RunWorld) -> float:
	var weapon := world.weapon_id()
	if _reach.has(weapon):
		return _reach[weapon]
	var info := world.weapon_info() if weapon > 0 else BARE_HANDS
	var far := 0.0
	if not info.is_empty():
		for action: String in ACTIONS:
			var spec := _spec(info, action)
			if not spec.is_empty():
				far = maxf(far, -(spec.box as Rect2).position.x)
	_reach[weapon] = far
	return far


func _target_in_reach(world: RunWorld, info: Dictionary) -> bool:
	# Reach gates the opportunity, not its uniformly selected stance. Shorter stances may miss at impact.
	for action: String in ACTIONS:
		var spec := _spec(info, action)
		if not spec.is_empty() and _nearest(world, spec.box, world.player.facing) >= 0:
			return true
	return false


func _spec(info: Dictionary, action: String) -> Dictionary:
	var body: Dictionary = _body.get(action, {})
	if is_same(info, BARE_HANDS):
		return _bare_spec(body, action)
	var name := WeaponInfo.afterimage_name(info)
	var node: Dictionary = _images.get(name, {}).get(WeaponInfo.AFTERIMAGE_VARIANT, {}).get(action, {})
	if node.is_empty() or body.is_empty() or not node.has("lt") or not node.has("rb"):
		return {}
	var frame := 999
	for key: String in node:
		if key.is_valid_int():
			frame = mini(frame, int(key))
	if frame == 999:
		return {}
	var before := 0.0
	var total := 0.0
	for key: String in body:
		if key.is_valid_int():
			var delay := absf(float(body[key].get("delay", 100))) / 1000.0
			total += delay
			if int(key) < frame:
				before += delay
	var lt := Vector2(float(node.lt["$v"][0]), float(node.lt["$v"][1]))
	var rb := Vector2(float(node.rb["$v"][0]), float(node.rb["$v"][1]))
	return {"box": Rect2(lt, rb - lt).abs(), "hit_after": before, "action_time": total,
		"interval": WeaponInfo.attack_interval(info), "afterimage": WeaponInfo.afterimage_frame_path(name, action, frame),
		"hit_visual": WeaponInfo.hit_spark_path(name, action), "sound": WeaponInfo.sound_path(info)}


## tier C: a punch lands when the body action's last frame starts; reach BARE_HANDS_BOX, no afterimage or spark.
func _bare_spec(body: Dictionary, action: String) -> Dictionary:
	var last := -1
	for key: String in body:
		if key.is_valid_int():
			last = maxi(last, int(key))
	if last < 0:
		return {}
	var before := 0.0
	var total := 0.0
	for key: String in body:
		if key.is_valid_int():
			var delay := absf(float(body[key].get("delay", 100))) / 1000.0
			total += delay
			if int(key) < last:
				before += delay
	return {"box": BARE_HANDS_BOX, "hit_after": before, "action_time": total,
		"interval": WeaponInfo.attack_interval(BARE_HANDS), "afterimage": "", "hit_visual": "",
		"sound": WeaponInfo.sound_path(BARE_HANDS)}


## The swing's single target in the facing box: a scheduled boss first, then nearest, then slot (targets_before).
func _nearest(world: RunWorld, relative: Rect2, facing: int) -> int:
	var box := relative
	if facing > 0:
		box.position.x = -relative.end.x
	box.position += world.player.pos
	var count := world.mob_grid.query_rect(box.grow(world.body_pad), _buffer)
	var best := -1
	var distance := INF
	for n in count:
		var mob := _buffer[n]
		if world.swarm.active[mob] == 0:
			continue
		var kind: MobKind = world.mob_kinds[world.swarm.kind[mob]]
		if not box.intersects(kind.hitbox_at(world.swarm.x[mob], world.swarm.y[mob], world.swarm.facing[mob])):
			continue
		var d := world.mob_center(mob).distance_squared_to(world.cast_origin())
		if best < 0 or world.targets_before(mob, d, best, distance):
			best = mob
			distance = d
	return best


func _impact(world: RunWorld) -> void:
	_emit(world, "impact")
	var mob := _nearest(world, _pending.box, int(_pending.facing))
	if mob < 0:
		return
	var kind: MobKind = world.mob_kinds[world.swarm.kind[mob]]
	var damage := CombatMath.basic_damage_range(int(_pending.str), int(_pending.dex), float(_pending.watk),
		int(_pending.weapon_id), String(_pending.action), int(_pending.level), kind.level, world.mob_defense(mob, false))
	world.hit_mob(mob, {"skill": "basic_attack", "damage_min": damage.x, "damage_max": damage.y,
		"magic": false, "crit": 0.0, "crit_mult": 1.0}, world.visual_index(String(_pending.hit_visual)))


func _emit(world: RunWorld, phase: String) -> void:
	world.emit("basic_attack", {"phase": phase, "weapon_id": int(_pending.weapon_id), "action": String(_pending.action),
		"facing": int(_pending.facing), "pos": world.player.pos, "afterimage": String(_pending.afterimage),
		"sound": String(_pending.sound), "hit_after": float(_pending.hit_after), "interval": float(_pending.interval)})
