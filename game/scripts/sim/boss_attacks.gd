class_name BossAttacks
extends RefCounted
## Scheduled bosses' canonical area (0), targeted direct (1) and ball (2) attacks: survivor data selects which attacks,
## their cadence and scaling; the windup/impact code is MobAttacks' shared half (ordinary mobs use the same code).

## tier C: fallback repeat interval for authored attacks without a survivor override (WZ has no attack interval).
const DEFAULT_INTERVAL := 8.0
## tier C: missing/nonpositive WZ bulletSpeed fallback in px/s; balance.mob_projectiles.default_speed overrides it.
const DEFAULT_BALL_SPEED := 320.0
var _pending: Dictionary = {}
var _next: Dictionary = {}


## Advances pending effects/impacts, then starts an in-range, fully visible grounded boss's next ready attack.
func step(world: RunWorld) -> void:
	var swarm := world.swarm
	var bosses := world.bosses
	for index: int in _pending.keys():
		var pending: Dictionary = _pending[index]
		var slot := int(pending.mob)
		if bool(bosses.records[index].dead) or bool(bosses.records[index].get("fading", false)) \
				or not swarm.is_live(slot):
			_pending.erase(index)
			continue
		if MobAttacks.service(pending, world):
			_pending.erase(index)
	var now := world.time
	for index in bosses.records.size():
		var record: Dictionary = bosses.records[index]
		var slot := int(record.slot)
		if world.state != RunWorld.PLAYING or _pending.has(index) or not bosses.can_act(index, now) \
				or not swarm.can_act(slot) or swarm.fh[slot] < 0:
			continue
		var entry: Dictionary = bosses.entries[index]
		var img := world.mob_img(int(record.mob_id))
		for attack: String in entry.get("attacks", []):
			var key := "%d/%s" % [index, attack]
			if now < float(_next.get(key, 0.0)) - MobAttacks.EPS:
				continue
			var pending := MobAttacks.plan(world, slot, img, attack, index,
				float(entry.get("attack_dmg_mult", entry.get("dmg_mult", 1.0))))
			if pending.is_empty():
				continue
			bosses.begin_action(index, attack, float(pending.duration), int(pending.facing), now)
			_pending[index] = pending
			_next[key] = now + float(entry.get("attack_interval", DEFAULT_INTERVAL))
			MobAttacks.emit(pending, "start", world)
			if MobAttacks.service(pending, world):
				_pending.erase(index)
			break


## True while any scheduled boss's attack is winding up (its telegraph is up, before the impact).
func telegraph_up() -> bool:
	return not _pending.is_empty()


## World-space canonical attack range, mirrored horizontally when the mob faces right (MobAttacks.area_at).
static func area_at(range_data: Dictionary, pos: Vector2, facing: int) -> Rect2:
	return MobAttacks.area_at(range_data, pos, facing)
