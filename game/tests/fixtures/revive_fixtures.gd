extends RefCounted
## A test-only synthetic revive skill for the second-life seam (spec #372 BS3, docs/GAME_DESIGN.md 7.81), injected into the
## quiet test data so the seam is built and tested with no Bishop definition: `test_revive`, a reaction skill of a made-up
## book with eight levels (one per rank) that all carry the Resurrection-shaped 800 x 600 box. The recharge table is the
## spec's (600 s down to 120 s) unless a test passes its own.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const KEY := "test_revive"
const BOOK := "999"
const SKILL_ID := 9999001
const TABLE := [600.0, 540.0, 480.0, 420.0, 300.0, 240.0, 180.0, 120.0]


## The quiet data plus the skill's definition (`revive` overrides the default block; `table` the recharge per rank).
static func data(table: Array = TABLE, revive: Dictionary = {}) -> Dictionary:
	var d := RF.quiet_data()
	var block := {"hp": 0.5, "guard": 2.0, "push": {"distance": 140.0}}
	block.merge(revive, true)
	d.skills.skills[KEY] = {
		"skill_id": SKILL_ID, "book": BOOK, "job": 232, "kind": "instant", "slot": "active", "name": "Test Revive",
		"desc": "", "icon": "", "damage": "none", "cast": {"rule": "reaction"},
		"cooldown_by_rank": table.duplicate(), "revive": block,
		"ranks": [1, 2, 3, 4, 5, 6, 7, 8], "action": "alert2", "action_time": 0.0,
		"ball": "", "effect": "", "hit": "", "rotate": false, "sounds": {"use": "", "hit": ""},
	}
	return d


## The Skill.wz-shaped img of the made-up book.
static func img() -> Dictionary:
	var levels := {}
	for lv in range(1, 9):
		levels[str(lv)] = {"lt": {"$v": [-400.0, -350.0]}, "rb": {"$v": [400.0, 250.0]}, "cooltime": 3600.0 - 180.0 * lv}
	return {"skill": {str(SKILL_ID): {"icon": RF._canvas(32, 32), "level": levels}}}


## A setup of the quiet stage with the skill's img.
static func setup(p_seed := 375, table: Array = TABLE, revive: Dictionary = {}) -> Dictionary:
	var s := RF.setup("quiet", p_seed, data(table, revive))
	s.skill_imgs[BOOK] = img()
	return s


## A world standing at x = 800 whose only skill is the owned, ready revive skill (rank 1).
static func world(p_seed := 375, table: Array = TABLE, revive: Dictionary = {}, owned := true) -> RunWorld:
	var w := RunWorld.new(setup(p_seed, table, revive))
	RF.place_player(w, 800)
	w.loadout.order.clear()
	if owned:
		w.learn_skill(KEY)
	w.drain_events()
	return w


## A lethal-sized hit from `source` (accuracy 0, so it cannot miss); returns the damage dealt.
static func hit(w: RunWorld, source: Dictionary, attack := 1.0e6) -> int:
	var s := {"accuracy": 0.0, "mob": -1}
	s.merge(source, true)
	return w.take_hit(attack, false, "", w.player.pos - Vector2(10.0, 0.0), s)
