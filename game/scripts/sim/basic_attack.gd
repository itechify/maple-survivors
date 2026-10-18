class_name BasicAttack
extends RefCounted
## One player's automatic physical swing: canonical weapon interval, body-frame impact timing and afterimage box.
## Starts only in a skill-free standing/airborne tick; pending swings complete without locking player movement.

## The five one-handed swing/stab actions (WeaponInfo.ACTIONS_ONE_HANDED, tier B): the bare-handed punch and the
## Beginner/Magician weapons use them in this order. Other weapons ask WeaponInfo.basic_actions.
const ACTIONS := WeaponInfo.ACTIONS_ONE_HANDED
## The bare-handed punch when no weapon is worn (v83 lets a character fight without one). tier A: the sound is
## Sound.wz/Weapon.img/barehands. tier C: normal attack speed 6, the same five body actions, no afterimage.
const BARE_HANDS := {"attackSpeed": WeaponInfo.NORMAL_SPEED, "sfx": "barehands"}
## tier C: the punch's reach, feet-relative and facing left (shorter than the starter Sword's swing).
const BARE_HANDS_BOX := Rect2(-55, -55, 50, 50)

var cooldown := 0.0
## The action and damage kind (swing, stab, shoot) of the latest swing started; "" before the first.
var last_action := ""
var last_kind := ""
var _body: Dictionary
var _images: Dictionary
var _pending := {}
## weapon id -> reach(); the afterimage and body data never change during a run.
var _reach := {}
## weapon id -> envelope(), cached like _reach.
var _envelope := {}
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
	var actions := WeaponInfo.basic_actions(weapon)
	var action: String = actions[world.basic_rng.randi_range(0, actions.size() - 1)]
	var spec := _spec(weapon, info, action, world.loadout.speed_steps)
	if spec.is_empty() or not _target_in_reach(world, weapon, info):
		return
	_pending = spec
	_pending["weapon_id"] = weapon
	_pending["action"] = action
	_pending["facing"] = world.player.facing
	var caster := world.loadout
	var kind := WeaponInfo.basic_kind(weapon, action)
	last_action = action
	last_kind = kind
	var damage := CombatMath.physical_damage_range(caster.str_stat, caster.dex_stat, caster.luk_stat,
		world.weapon_attack(kind == "shoot"), weapon, kind, caster.job_id, caster.mastery)
	var mult := caster.player_stat("damage", 1.0)
	_pending.merge({"skill": "basic_attack", "damage_type": "physical", "attack_kind": kind, "defense": "pdd",
		"damage_min": damage.x * mult, "damage_max": damage.y * mult, "damage_pct": 1.0, "magic": false,
		"player_level": caster.char_level, "crit": caster.player_stat("crit",
			caster.crit_chance + caster.acc * caster.crit_per_acc + caster.crit_bonus),
		"crit_mult": caster.crit_mult, "crit_damage_bonus": caster.crit_damage_bonus})
	_pending["left"] = float(spec.hit_after)
	cooldown = maxf(cooldown, -dt) + float(spec.interval)
	world.start_action(action, float(spec.action_time), true, float(spec.scale))
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
		for action: String in WeaponInfo.basic_actions(weapon):
			var spec := _spec(weapon, info, action)
			if not spec.is_empty():
				far = maxf(far, -(spec.box as Rect2).position.x)
	_reach[weapon] = far
	return far


## The held weapon's swing envelope: the union of the afterimage boxes of the stances reach() looks at (feet-relative,
## facing left), the box a "weapon_reach" skill (Warrior Power Strike) strikes inside; an empty Rect2 when the weapon
## cannot swing. Its far edge is reach(). Cached per weapon.
func envelope(world: RunWorld) -> Rect2:
	var weapon := world.weapon_id()
	if _envelope.has(weapon):
		return _envelope[weapon]
	var info := world.weapon_info() if weapon > 0 else BARE_HANDS
	var union := Rect2()
	var any := false
	if not info.is_empty():
		for action: String in WeaponInfo.basic_actions(weapon):
			var spec := _spec(weapon, info, action)
			if spec.is_empty():
				continue
			union = (spec.box as Rect2) if not any else union.merge(spec.box as Rect2)
			any = true
	_envelope[weapon] = union
	return union


func _target_in_reach(world: RunWorld, weapon: int, info: Dictionary) -> bool:
	# Reach gates the opportunity, not its uniformly selected stance. Shorter stances may miss at impact.
	for action: String in WeaponInfo.basic_actions(weapon):
		var spec := _spec(weapon, info, action)
		if not spec.is_empty() and _nearest(world, spec.box, world.player.facing) >= 0:
			return true
	return false


## The timing, box and effect paths of one action of `weapon` ({} when it cannot be played); what a swing starts with.
## For tools and tests (the weapon gallery draws exactly this); the automatic attack calls the same code.
func action_spec(weapon: int, info: Dictionary, action: String, boost: int = 0) -> Dictionary:
	return _spec(weapon, info, action, boost)


## One action's timing, box and effect paths for the weapon, or {} when the body or the afterimage cannot play it. `boost`
## Booster steps shorten the interval by the speed table and the body timing (hit_after, action_time) by `scale`
## (WeaponInfo.speed_factor; 1.0 without a Booster). A
## melee weapon needs the afterimage's lt/rb box and lands on the afterimage's first frame. A ranged family (bow,
## crossbow, claw, gun) hits at WeaponInfo.ranged_box until #155's projectiles carry their own range, lands on the
## afterimage's first frame when it has one (the Bow's draw frame) else on the body's last frame, and shows no
## afterimage when the node is a melee trail with a box (a Claw's swordOL) or missing (the Gun's).
func _spec(weapon: int, info: Dictionary, action: String, boost: int = 0) -> Dictionary:
	var body: Dictionary = _body.get(action, {})
	if is_same(info, BARE_HANDS):
		return _bare_spec(body, action, boost)
	var name := WeaponInfo.afterimage_name(info)
	var node: Dictionary = _images.get(name, {}).get(WeaponInfo.AFTERIMAGE_VARIANT, {}).get(action, {})
	var ranged := WeaponInfo.is_ranged(weapon)
	var boxed := node.has("lt") and node.has("rb")
	if body.is_empty() or (not ranged and (node.is_empty() or not boxed)):
		return {}
	var frame := 999
	for key: String in node:
		if key.is_valid_int():
			frame = mini(frame, int(key))
	if frame == 999 and not ranged:
		return {}
	var last := -1
	for key: String in body:
		if key.is_valid_int():
			last = maxi(last, int(key))
	if last < 0:
		return {}
	var impact := frame if frame != 999 else last
	var before := 0.0
	var total := 0.0
	for key: String in body:
		if key.is_valid_int():
			var delay := absf(float(body[key].get("delay", 100))) / 1000.0
			total += delay
			if int(key) < impact:
				before += delay
	var box := WeaponInfo.ranged_box(weapon)
	if not ranged:
		var lt := Vector2(float(node.lt["$v"][0]), float(node.lt["$v"][1]))
		var rb := Vector2(float(node.rb["$v"][0]), float(node.rb["$v"][1]))
		box = Rect2(lt, rb - lt).abs()
	var trail := frame != 999 and not (ranged and boxed)
	var scale := WeaponInfo.speed_factor(int(info.get("attackSpeed", 0)), boost)
	return {"box": box, "hit_after": before * scale, "action_time": total * scale, "scale": scale,
		"interval": WeaponInfo.attack_interval(info, boost),
		"afterimage": WeaponInfo.afterimage_frame_path(name, action, frame) if trail else "",
		"hit_visual": WeaponInfo.hit_spark_path(name, action), "sound": WeaponInfo.sound_path(info)}


## tier C: a punch lands when the body action's last frame starts; reach BARE_HANDS_BOX, no afterimage or spark.
func _bare_spec(body: Dictionary, action: String, boost: int = 0) -> Dictionary:
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
	var scale := WeaponInfo.speed_factor(int(BARE_HANDS.attackSpeed), boost)
	return {"box": BARE_HANDS_BOX, "hit_after": before * scale, "action_time": total * scale, "scale": scale,
		"interval": WeaponInfo.attack_interval(BARE_HANDS, boost), "afterimage": "", "hit_visual": "",
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
	world.hit_mob(mob, _pending, world.visual_index(String(_pending.hit_visual)), world.basic_rng)


func _emit(world: RunWorld, phase: String) -> void:
	world.emit("basic_attack", {"phase": phase, "weapon_id": int(_pending.weapon_id), "action": String(_pending.action),
		"facing": int(_pending.facing), "pos": world.player.pos, "afterimage": String(_pending.afterimage),
		"sound": String(_pending.sound), "hit_after": float(_pending.hit_after), "interval": float(_pending.interval)})
