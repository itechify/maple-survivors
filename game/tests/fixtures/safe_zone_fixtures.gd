extends RefCounted
## A synthetic safe-zone skill on the quiet world (spec #425 SH4): made-up book 999 and skill 9992001, a 30-level-style table
## read at three ranks (levels 1, 4, 8, boxes +-120 x +-90, +-150 x +-113, +-200 x +-150 like Smokescreen's), no real data or art.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const KEY := "test_cloud"
const SKILL_ID := 9992001
const DT := 1.0 / 60.0
const SNAIL := 100100
## The mob that touches (contact damage) in the tests that need a real hit.
const BODY_MOB := 1110100


## A quiet world with 1000 HP, no regeneration and the synthetic cloud learned at rank 1 (6 s life, min 3 monsters within
## 250 px, 24 s cooldown), the character standing at x = 400. The auto-cast stays idle until a test puts monsters near.
static func world(p_seed := 429, block := {}) -> RunWorld:
	var data := RF.quiet_data()
	data.balance.player.hp = 1000
	data.balance.regen.hp = 0
	data.balance.regen.mp = 0
	data.balance.magnet_radius = 0
	data.balance.mob_motion.push_px = 0
	var w := RunWorld.new(RF.setup("quiet", p_seed, data))
	RF.place_player(w, 400)
	w.player.facing = 1
	w.loadout.order.clear()
	var definition := {"skill_id": SKILL_ID, "book": "999", "kind": "instant", "slot": "active", "damage": "none",
		"cooldown": 24.0, "ranks": [1, 4, 8], "action": "swingO1", "action_time": 0.4, "effect": "",
		"cast": {"rule": "safe_zone", "min_mobs": 3, "mob_within": 250.0}, "safe_zone": {"duration": 6.0}}
	definition.merge(block, true)
	w.book.defs[KEY] = definition
	w.book.skill_imgs["999"] = {"skill": {str(SKILL_ID): {"level": {
		"1": _box(120, 90), "4": _box(150, 113), "8": _box(200, 150)}}}}
	assert(w.learn_skill(KEY))
	w.drain_events()
	return w


static func _box(half_w: int, half_h: int) -> Dictionary:
	return {"lt": {"$v": [-half_w, -half_h]}, "rb": {"$v": [half_w, half_h]}}


## Puts a standing, harmless snail at `x` (default the character's row) and refreshes the mob grid; returns its slot.
static func mob(w: RunWorld, x: float, y := 190.0) -> int:
	var kind: MobKind = w.mob_kinds[int(w.kind_of_id[SNAIL])]
	kind.move_speed = 0.0
	kind.body_attack = false
	var m := RF.put_mob(w, SNAIL, x, y, 100000.0)
	w.swarm.alpha[m] = 1.0
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	return m


## Three snails near the character (inside the 250 px reach), so the auto-cast is admitted.
static func crowd(w: RunWorld) -> void:
	for dx in [60.0, 90.0, 120.0]:
		mob(w, w.player.pos.x + dx)


## Casts the skill at once from the character's body (the runner path, no waiting for a tick's overshoot); returns the world.
static func cast(w: RunWorld) -> RunWorld:
	w.runner.cooldowns[KEY] = 0.0
	w.runner.step(DT, w)
	return w


## The events of `type` in `events`.
static func of(events: Array, type: String) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return e.type == type)
