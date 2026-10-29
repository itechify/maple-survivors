extends RefCounted
## The Bishop's real `resurrection` definition (skills/bishop.json) on the quiet stage with a synthetic book 232 (spec #372
## BS8, docs/GAME_DESIGN.md 7.81): ten levels, each with the WZ-shaped 800 x 600 box and the v83 `cooltime` line. No asset
## cache is needed; the real-cache identity tests live in test_bishop_resurrection.gd.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const RV := preload("res://tests/fixtures/revive_fixtures.gd")
const KEY := "resurrection"
const SKILL_ID := 2321006
## tier A: the recharge table of the spec (cooltime / 3 - 480 over the mapped WZ levels 2, 3, 4, 5, 7, 8, 9, 10), the synthetic
## revive skill's.
const TABLE := RV.TABLE
const LEVELS := [2, 3, 4, 5, 7, 8, 9, 10]


## Skill.wz-shaped img of the skill: levels 1..10, `cooltime` 3420 - 180 per level after the first, the 800 x 600 box.
static func img() -> Dictionary:
	return RV.img_of(SKILL_ID, 10)


## The setup of the quiet stage for a Bishop with the synthetic book.
static func setup(p_seed := 380) -> Dictionary:
	var s := RF.setup("quiet", p_seed, RF.quiet_data())
	s.job = 232
	s.skill_imgs["232"] = img()
	return s


## A world standing at x = 800 whose only skill is the learned Resurrection (rank 1, ready).
static func world(p_seed := 380) -> RunWorld:
	var w := RunWorld.new(setup(p_seed))
	RF.place_player(w, 800)
	w.loadout.order.clear()
	w.learn_skill(KEY)
	w.drain_events()
	return w


## A lethal hit from a touching monster (accuracy 0, so it cannot miss); returns the damage dealt.
static func lethal_hit(w: RunWorld, source_kind := "touch") -> int:
	return w.take_hit(1.0e6, false, "", w.player.pos - Vector2(10.0, 0.0), {"accuracy": 0.0, "mob": -1, "source_kind": source_kind})
