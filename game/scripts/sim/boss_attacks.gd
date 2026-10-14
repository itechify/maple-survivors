class_name BossAttacks
extends RefCounted
## Canonical type-0 boss windups and delayed area impacts; survivor data selects attacks, cadence and damage scaling.

## tier C: fallback repeat interval for authored attacks without a survivor override (WZ has no attack interval).
const DEFAULT_INTERVAL := 8.0
var _pending: Dictionary = {}
var _next: Dictionary = {}


## Advances pending effects/impacts, then starts an in-range, fully visible grounded boss's next ready attack.
func step(world: RunWorld) -> void:
	for index: int in _pending.keys():
		var pending: Dictionary = _pending[index]
		var slot := int(pending.mob)
		if bool(world.bosses.records[index].dead) or world.swarm.active[slot] == 0:
			_pending.erase(index)
			continue
		_service(pending, world)
	for index in world.bosses.records.size():
		var record: Dictionary = world.bosses.records[index]
		var slot := int(record.slot)
		if world.state != RunWorld.PLAYING or _pending.has(index) or not world.bosses.can_act(index, world.time) \
				or slot < 0 or world.swarm.active[slot] == 0 or world.swarm.alpha[slot] < 1.0 or world.swarm.fh[slot] < 0:
			continue
		var entry: Dictionary = world.bosses.entries[index]
		var id := int(record.mob_id)
		var img: Dictionary = world.setup.mob_imgs.get(id, {})
		for attack: String in entry.get("attacks", []):
			var key := "%d/%s" % [index, attack]
			if world.time < float(_next.get(key, 0.0)) - 1e-6:
				continue
			var stance: Dictionary = img.get(attack, {})
			var info: Dictionary = stance.get("info", {})
			if int(info.get("type", -1)) != 0:
				continue
			var pos := Vector2(world.swarm.x[slot], world.swarm.y[slot])
			var facing := 1 if world.player.pos.x > pos.x else -1
			var area := area_at(info.get("range", {}), pos, facing)
			if not area.intersects(Rect2(world.player.pos + world.body.position, world.body.size), true):
				continue
			var after := maxf(0.0, float(info.get("attackAfter", 0.0)) / 1000.0)
			var effect_after := maxf(0.0, float(info.get("effectAfter", 0.0)) / 1000.0)
			var magic := info.has("MADamage") and not info.has("PADamage")
			var damage := float(info.get("MADamage" if magic else "PADamage", world.mob_kinds[world.swarm.kind[slot]].pad))
			var duration := maxf(after, MobKind.stance_time(stance, after))
			world.bosses.begin_action(index, attack, duration, facing, world.time)
			var pending := {"boss_index": index, "mob": slot, "mob_id": id, "attack": attack,
				"pos": pos, "facing": facing, "area": area, "impact_time": world.time + after,
				"effect_time": world.time + effect_after, "effect_done": false, "damage": damage,
				"magic": magic, "element": String(info.get("elemAttr", "")),
				"jump_attack": int(info.get("jumpAttack", 0)) != 0,
				"dmg_mult": float(entry.get("attack_dmg_mult", entry.get("dmg_mult", 1.0))),
				"effect": "Mob.wz/%07d.img/%s/info/effect" % [id, attack] if info.has("effect") else "",
				"sound": "Sound.wz/Mob.img/%07d/%s" % [id, attack.left(1).to_upper() + attack.substr(1)]}
			_pending[index] = pending
			_next[key] = world.time + float(entry.get("attack_interval", DEFAULT_INTERVAL))
			_emit(pending, "start", world)
			_service(pending, world)
			break


## World-space canonical attack range, mirrored horizontally when the mob faces right.
static func area_at(range_data: Dictionary, pos: Vector2, facing: int) -> Rect2:
	var lt := _vec(range_data.get("lt", {}))
	var rb := _vec(range_data.get("rb", {}))
	var rect := Rect2(lt, rb - lt).abs()
	if facing > 0:
		rect.position.x = -rect.end.x
	rect.position += pos
	return rect


func _service(pending: Dictionary, world: RunWorld) -> void:
	if not bool(pending.effect_done) and world.time >= float(pending.effect_time) - 1e-6:
		pending.effect_done = true
		_emit(pending, "effect", world)
	if world.time < float(pending.impact_time) - 1e-6:
		return
	_emit(pending, "impact", world)
	var box := Rect2(world.player.pos + world.body.position, world.body.size)
	# tier C: the lore jump-slam dodge uses the player's grounded state at impact, not at windup.
	var can_hit := not bool(pending.jump_attack) or world.player.fh >= 0
	if can_hit and (pending.area as Rect2).intersects(box, true):
		var kind: MobKind = world.mob_kinds[world.swarm.kind[int(pending.mob)]]
		world.take_hit(float(pending.damage), bool(pending.magic), pending.element, pending.pos,
			{"mob": int(pending.mob), "mob_id": int(pending.mob_id), "boss": true,
				"accuracy": kind.acc, "dmg_mult": float(pending.dmg_mult), "source_kind": "attack"})
	_pending.erase(int(pending.boss_index))


func _emit(pending: Dictionary, phase: String, world: RunWorld) -> void:
	world.emit("boss_attack", {"boss_index": int(pending.boss_index), "mob": int(pending.mob),
		"mob_id": int(pending.mob_id), "attack": String(pending.attack), "phase": phase,
		"pos": pending.pos, "facing": int(pending.facing), "area": pending.area,
		"time": world.time, "impact_time": float(pending.impact_time),
		"effect": String(pending.effect), "sound": String(pending.sound)})


static func _vec(value: Variant) -> Vector2:
	if value is Vector2:
		return value
	if value is Dictionary and value.get("$v") is Array and value["$v"].size() >= 2:
		return Vector2(float(value["$v"][0]), float(value["$v"][1]))
	return Vector2.ZERO
