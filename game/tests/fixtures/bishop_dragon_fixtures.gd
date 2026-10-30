extends RefCounted
## Shared Summon Dragon / Bahamut fixtures for the Bishop tests (spec #372, BS7 #379): synthetic Skill.wz-shaped books 231 and 232
## with the recorded v83 values at the eight ranks (BS1 note), added to the Bishop bolt fixture's setup.

const BF := preload("res://tests/fixtures/bishop_bolt_fixtures.gd")
const IL := preload("res://tests/fixtures/il_fixtures.gd")

## WZ levels of ranks 1..8 are BF.RANK_LEVELS; the recorded values at those levels (BS1-373.md "Rank values").
const DRAGON_MAD := [76, 92, 108, 120, 128, 136, 144, 150]
const DRAGON_TIME := [25, 45, 65, 80, 96, 112, 128, 140]
const BAHAMUT_MAD := [122, 134, 148, 160, 176, 195, 215, 230]
const BAHAMUT_TIME := [30, 50, 70, 85, 105, 125, 145, 160]
const BAHAMUT_TARGETS := [3, 3, 3, 3, 3, 3, 3, 6]


## An animation node of `frames` frames, each `delay_ms` long.
static func _anim(frames: int, delay_ms: float) -> Dictionary:
	var out := {}
	for i in frames:
		out[str(i)] = {"$canvas": [0, 0, 0, 40, 40], "delay": delay_ms}
	return out


static func _range(lt: Array, rb: Array) -> Dictionary:
	return {"lt": {"$v": lt}, "rb": {"$v": rb}}


## Skill.wz/231.img Summon Dragon: five animations and NO `move` (it flies), one-target attack (no `mobCount`), box (-200,-150)..(200,150),
## attackAfter 500, no `elemAttr`. Skill.wz/232.img Bahamut: `elemAttr h`, attack box (-200,-150)..(0,30), attackAfter 990, constant
## `info.mobCount` 3 and the level `mobCount` 3 up to level 29 and 6 at level 30.
static func books() -> Dictionary:
	var dragon := {"icon": {"$canvas": [0, 0, 0, 32, 32]}, "action": {"0": "alert2"}, "hit": {"0": _anim(1, 250)},
		"level": IL.levels({"mad": BF.points(DRAGON_MAD, 70), "mastery": BF.mastery(), "time": BF.points(DRAGON_TIME, 20)}),
		"summon": {"summoned": _anim(5, 100), "fly": _anim(5, 90), "stand": _anim(5, 90), "attack1": _anim(8, 75),
			"die": _anim(6, 100)}}
	dragon.summon.attack1["info"] = {"range": _range([-200, -150], [200, 150]), "type": 1.0, "attackAfter": 500.0}
	var bahamut := {"icon": {"$canvas": [0, 0, 0, 32, 32]}, "elemAttr": "h", "action": {"0": "alert2"}, "hit": {"0": _anim(7, 100)},
		"level": IL.levels({"mad": BF.points(BAHAMUT_MAD, 110), "mastery": BF.mastery(), "time": BF.points(BAHAMUT_TIME, 25),
			"mobCount": {1: 3, 29: 3, 30: 6}}),
		"summon": {"summoned": _anim(6, 120), "fly": _anim(6, 150), "stand": _anim(12, 150), "attack1": _anim(18, 90),
			"die": _anim(6, 100)}}
	bahamut.summon.attack1["info"] = {"range": _range([-200, -150], [0, 30]), "type": 0.0, "attackAfter": 990.0, "mobCount": 3.0}
	return {"dragon": dragon, "bahamut": bahamut}


static func setup() -> Dictionary:
	var setup := BF.setup()
	var b := books()
	setup.skill_imgs["231"]["skill"]["2311006"] = b.dragon
	setup.skill_imgs["232"]["skill"]["2321003"] = b.bahamut
	return setup
