class_name MobSkillRunner
extends RefCounted
## Canonical scheduled-boss skills and their timed status state; no files, nodes or canonical-stat mutation.
var _images: Dictionary
var _tables: Dictionary
var _rules: Dictionary
var _enabled: Array
var _ready := {}
var _busy := {}
var _slow_until := 0.0
var _slow_factor := 1.0
var _slow_visual := ""
func _init(setup: Dictionary, rules: Dictionary = {}) -> void:
	_rules = rules
	_images = setup.get("mob_imgs", {})
	_tables = setup.get("mob_skill_img", {})
	for id: Variant in rules.get("enabled_ids", []):
		_enabled.append(int(id))
## Current movement multiplier from the area's timed slow.
func speed_multiplier(now: float) -> float:
	return _slow_factor if now < _slow_until - 1e-9 else 1.0
## Public presentation state for the player's active slow; empty after expiration.
func slow_state(now: float) -> Dictionary:
	return {"skill_id": 126, "remaining": _slow_until - now, "multiplier": _slow_factor, "visual": _slow_visual} if now < _slow_until - 1e-9 else {}
## Casts one ready canonical skill per boss after its own HP gate and stance availability.
func step(world: RunWorld) -> void:
	for record: Dictionary in world.bosses.records:
		var slot := int(record.slot)
		if slot < 0 or slot >= world.swarm.capacity() or world.swarm.active[slot] == 0 or not int(record.mob_id) in _enabled:
			continue
		var index := int(record.boss_index)
		if world.time < float(_busy.get(index, 0.0)) - 1e-9:
			continue
		var image: Dictionary = _images.get(int(record.mob_id), _images.get(str(int(record.mob_id)), {}))
		for entry: Dictionary in image.get("info", {}).get("skill", {}).values():
			var id := int(entry.skill)
			var level := int(entry.level)
			var spec: Dictionary = _tables.get(str(id), {}).get("level", {}).get(str(level), {})
			if spec.is_empty() or id not in [126,200]:
				continue
			var key := "%d/%d/%d" % [index,id,level]
			var ready := float(_ready.get(key, float(record.spawn_time) + float(spec.get("interval", 0.0))))
			if world.time < ready - 1e-9 or float(world.swarm.hp[slot]) * 100.0 > float(world.swarm.max_hp[slot]) * float(spec.get("hp", 100.0)):
				continue
			if id == 200 and summoned_alive(world,index) >= int(spec.get("limit",0)):
				continue
			var pos := Vector2(world.swarm.x[slot], world.swarm.y[slot])
			var duration := float(spec.get("time", 0.0))
			var path := "Skill.wz/MobSkill.img/%d/level/%d" % [id,level]
			var affected := ""
			if id == 126 and _area(spec, pos, world.swarm.facing[slot]).has_point(world.player.pos):
				# tier C: x is retained percent of upgraded speed (x80 means 20% slower).
				_slow_factor = clampf(float(spec.get("x", 100.0)) / 100.0, 0.0, 1.0)
				_slow_until = world.time + duration
				_slow_visual = path + "/affected"
				affected = _slow_visual
			if id == 200:
				_summon(world,slot,index,spec)
			_ready[key] = world.time + float(spec.get("interval", 0.0))
			var action := "skill%d" % int(entry.get("action", 1))
			_busy[index] = world.time + MobKind.stance_time(image.get(action), 0.0)
			world.player.speed_stat = roundi(world.player_speed_stat())
			world.emit("boss_skill", {"mob": slot, "mob_id": int(record.mob_id), "skill_id": id, "level": level,
				"pos": pos, "facing": int(world.swarm.facing[slot]), "action": action, "duration": duration,
				"effect": path + "/effect" if spec.has("effect") else "", "player_effect": affected, "targets": []})
			break
func _area(spec: Dictionary, pos: Vector2, facing: int) -> Rect2:
	var lt: Array = spec.get("lt", {"$v": [0,0]})["$v"]
	var rb: Array = spec.get("rb", {"$v": [0,0]})["$v"]
	var box := Rect2(Vector2(float(lt[0]),float(lt[1])), Vector2(float(rb[0])-float(lt[0]),float(rb[1])-float(lt[1]))).abs()
	if facing > 0:
		box.position.x = -box.end.x
	box.position += pos
	return box

## Number of this encounter's still-living summoned slots, independent of their present position or kind.
func summoned_alive(world: RunWorld, owner: int) -> int:
	var count := 0
	for slot in world.swarm.capacity():
		if world.swarm.active[slot] != 0 and world.mob_summon_owner[slot] == owner:
			count += 1
	return count
func _summon(world: RunWorld, source: int, owner: int, spec: Dictionary) -> void:
	var keys := PackedInt32Array()
	for key: String in spec:
		if key.is_valid_int():
			keys.append(int(key))
	keys.sort()
	var available := maxi(0,int(spec.get("limit",0)) - summoned_alive(world,owner))
	var platform := world.swarm.platform[source]
	if platform < 0:
		return
	var span := world.fhm.platform_span(platform)
	# tier C: symmetric survivor spawn spacing; canonical list/limit/stats remain unchanged.
	var spacing := float(_rules.get("summon_spacing",24.0))
	for i in mini(keys.size(),available):
		var id := int(spec[str(keys[i])])
		if not world.kind_of_id.has(id):
			continue
		var x := clampf(world.swarm.x[source] + (i - (keys.size()-1) * 0.5) * spacing,span.x,span.y)
		var fh := world.fhm.platform_fh_at(platform,x)
		if fh < 0:
			continue
		var slot := world.spawn_mob(int(world.kind_of_id[id]),Vector2(x,world.fhm.y_at(fh,x)),fh,1.0,false)
		world.mob_summon_owner[slot] = owner
