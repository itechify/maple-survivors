extends RefCounted
## Shared Genesis / Big Bang fixtures for the Bishop tests (spec #372, BS6 #378): a synthetic book 232 Genesis table (the
## (-400,-350)..(400,250) box and 15 mobs at every level) added on top of the Bishop bolt fixture's setup, the Big Bang nodes
## of books 232 and 212, and a Bishop world with one skill learned on a flat floor.

const BF := preload("res://tests/fixtures/bishop_bolt_fixtures.gd")
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const IlBigBang := preload("res://tests/unit/test_il_big_bang.gd")

const GENESIS := 2321008
const BIG_BANG := 2321001
const CASTER_X := 2000.0
const FLAT := [{"x1": 0, "y1": 200, "x2": 4000, "y2": 200}]


## A synthetic 232 level table in the WZ shape of Genesis: the (-400,-350)..(400,250) box at every level, 15 mobs.
static func levels(mad: float, attack_count: float) -> Dictionary:
	var out := {}
	for lv in range(1, 31):
		out[str(lv)] = {"mad": mad, "mobCount": 15.0, "attackCount": attack_count, "mastery": 10.0,
			"lt": {"$v": [-400, -350]}, "rb": {"$v": [400, 250]}}
	return out


## The Genesis and Big Bang nodes added to the Bishop bolt fixture's book 232 (and Big Bang's parent book 212).
static func add_books(setup: Dictionary, mad: float = 120.0, attack_count: float = 1.0) -> Dictionary:
	setup.skill_imgs["232"].skill[str(GENESIS)] = {"elemAttr": "h", "level": levels(mad, attack_count)}
	setup.skill_imgs["232"].skill[str(BIG_BANG)] = {"level": IlBigBang.levels(mad, attack_count)}
	setup.skill_imgs["212"] = {"skill": {"2121001": {"level": IlBigBang.levels(mad, attack_count)}}}
	return setup


## A Bishop world with only `key` learned, the player at CASTER_X on a flat floor, god mode, motionless pin-size mobs.
static func world(key: String, mad: float = 120.0, attack_count: float = 1.0, p_seed: int = 378) -> RunWorld:
	var w := RunWorld.new(add_books(BF.setup(RF.quiet_data(), p_seed), mad, attack_count))
	w.bounds = Rect2(0, -500, 4000, 1000)
	w.fhm = FootholdMap.from_segments(FLAT)
	w.swarm.fhm = w.fhm
	RF.place_player(w, CASTER_X)
	w.loadout.ranks.clear()
	w.loadout.order.clear()
	w.learn_skill(key)
	w.loadout.set_caster(100.0, 0.0, 30)
	w.god = true
	for mk: MobKind in w.mob_kinds:
		mk.hitbox = Rect2(-5, -10, 10, 10)
		mk.move_speed = 0.0
	w.drain_events()
	return w
