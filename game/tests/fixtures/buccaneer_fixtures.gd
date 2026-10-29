extends RefCounted
## Shared synthetic Buccaneer (512) worlds (spec #412, B11 #423): every pool skill defined, so the bot test and the baseline oracle
## play the whole pool. The books are the fixtures of the skill tickets (B4 Brawler books 500/510 from the run fixtures, B6 Drain,
## B7 Orb, B8 Barrage and Dragon Strike, B9 Transformation and Shockwave, B10 Super Transformation, Demolition and Snatch).

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const TRANSFORMATION := preload("res://tests/fixtures/buccaneer_transformation_book.gd")
const ORB := preload("res://tests/fixtures/buccaneer_orb_book.gd")
const BARRAGE_DRAGON := preload("res://tests/fixtures/buccaneer_barrage_dragon_book.gd")
const SUPER := preload("res://tests/fixtures/buccaneer_super_transformation_book.gd")
## The creation weapon, the Steel Knuckler (v83 Item.wz 1482000).
const KNUCKLE := 1482000


## `RF.skill_imgs()` plus book 511 (Transformation, Shockwave, Energy Drain) and book 512 (Barrage, Dragon Strike, Energy Orb,
## Super Transformation, Demolition, Snatch): every Buccaneer pool skill and sub-skill is defined.
static func skill_imgs() -> Dictionary:
	var imgs := RF.skill_imgs()
	var book511 := TRANSFORMATION.book_node()
	book511.skill.merge(ORB._drain_book().skill)
	imgs["511"] = book511
	var book512 := BARRAGE_DRAGON.book_node()
	book512.skill.merge(ORB.book_node().skill)
	book512.skill.merge(SUPER.book_node().skill)
	imgs["512"] = book512
	return imgs


## `RF.setup(stage, seed, data)` for a Buccaneer: the Brawler and Buccaneer books above, the basic-attack fixtures with the knuckle's
## afterimage added so `weapon_reach` skills have a swing envelope (without it the knuckle has none and they cannot fire), `job = 512`.
## The shipped data already has the job playable; `data` is the caller's copy.
static func setup(stage: String, seed_value: int, data: Dictionary) -> Dictionary:
	var out := RF.with_basic_attack(RF.setup(stage, seed_value, data))
	out.skill_imgs = skill_imgs()
	out.equipment_info[KNUCKLE] = {"incPAD": 18.0, "attackSpeed": 5.0, "afterImage": "mace", "sfx": "mace"}
	out["job"] = 512
	return out
