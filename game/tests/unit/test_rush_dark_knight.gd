extends "res://tests/unit/test_rush.gd"
## Dark Knight's Rush (spec #348 D8, #356; WZ 1321003, book 132): the whole Rush test set of test_rush.gd re-run for
## `rush_dark_knight` (every inherited test_ method runs with the Dark Knight job, book, key and skill id, and the body
## action `rush`), plus the checks that it is a data copy of Hero's Rush and ranks with the round level exactly like it.

const PER_BOOK_FIELDS := ["skill_id", "book", "job", "action", "icon", "effect", "cast_visuals", "sounds"]


func _job() -> int:
	return 132


func _book() -> String:
	return "132"


func _key() -> String:
	return "rush_dark_knight"


func _skill_id() -> int:
	return 1321003


## The body action of Dark Knight's Rush: its node says `rush` where Hero's says `rush2` (the body img has both; DK-14).
func _action() -> String:
	return "rush"


## A definition without its `_` notes and without the fields that name the book, the art, the sound or the action.
static func _shape(def: Dictionary) -> Dictionary:
	var out := {}
	for field: String in def:
		if not field.begins_with("_") and not field in PER_BOOK_FIELDS:
			out[field] = def[field]
	return out


# --- Data ---------------------------------------------------------------------------------------------------------------

## Dark Knight's Rush is `rush_hero` with its own book, ids, art, sound and body action: every other field is the same value.
func test_rush_dark_knight_is_a_data_copy_of_rush_hero() -> void:
	var defs: Dictionary = DataRepo.load_all().skills.skills
	assert_true(defs.has("rush_dark_knight"), "D8 defines it in skills/dark_knight.json")
	assert_eq(_shape(defs.rush_dark_knight), _shape(defs.rush_hero), "the same shape, ranks and numbers")
	var dk: Dictionary = defs.rush_dark_knight
	assert_eq(int(dk.skill_id), 1321003)
	assert_eq(String(dk.book), "132")
	assert_eq(int(dk.job), 132)
	assert_eq(String(dk.action), "rush", "the one data difference: Hero's node says rush2")
	assert_eq(String(dk.icon), "Skill.wz/132.img/skill/1321003/icon")
	assert_eq(String(dk.effect), "Skill.wz/132.img/skill/1321003/effect")
	assert_eq(String(dk.cast_visuals[0].path), "Skill.wz/132.img/skill/1321003/effect0")
	assert_eq(String(dk.sounds.use), "Sound.wz/Skill.img/1321003/Use", "the UOL to Hero's Use sound, as D1 imports it")
	assert_false(dk.has("ranks"), "no ranks override, as Hero's")
	assert_false(dk.has("level_ranks"))


# --- Rank -----------------------------------------------------------------------------------------------------------------

## Both Rushes take the same rank at every round level 1..40, and the same numbers at that rank: the shared rule, not a card.
func test_dark_knight_rush_ranks_with_the_round_level_exactly_like_hero_rush() -> void:
	var hero := _world_for(112, "112", 1121006)
	var dk := _world_for(132, "132", 1321003)
	for level in range(1, 41):
		_level_to(hero, level)
		_level_to(dk, level)
		assert_eq(dk.loadout.rank("rush_dark_knight"), hero.loadout.rank("rush_hero"), "rank at Lv%d" % level)
		var hs := hero.runner.stats_of(hero, "rush_hero")
		var ds := dk.runner.stats_of(dk, "rush_dark_knight")
		assert_eq(int(ds.level), int(hs.level), "WZ level at Lv%d" % level)
		assert_near(float(ds.damage_pct), float(hs.damage_pct), 1e-9, "damage at Lv%d" % level)
		assert_eq(int(ds.mob_count), int(hs.mob_count), "mobCount at Lv%d" % level)
		assert_eq(float(ds.displacement.distance), float(hs.displacement.distance), "dash distance at Lv%d" % level)
	assert_eq(dk.loadout.rank("rush_dark_knight"), 8, "rank 8 at Lv40, clamped like Hero's")


# --- Real cache -----------------------------------------------------------------------------------------------------------

## Needs the real asset cache (SKIPs without it, which proves nothing): the rank table of 1321003 reads the same WZ levels
## as 1121006's, and the top rank (level 30: 130 %, 250 px, box (-250,-50)) is Hero's too. The base test checks rank 1.
func test_real_cache_dark_knight_rush_ranks_on_the_same_wz_levels_as_hero_rush() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	assert_true(lib.open(AssetCachePaths.resolve_cache_root()))
	var book := SkillBook.from_data(DataRepo.load_all().skills, {
		"112": lib.img("Skill.wz/112.img").root, "132": lib.img("Skill.wz/132.img").root})
	assert_eq(book.max_level("rush_dark_knight"), book.max_level("rush_hero"))
	for rank in range(1, 9):
		assert_eq(book.canonical_level("rush_dark_knight", rank), book.canonical_level("rush_hero", rank), "rank %d" % rank)
	assert_eq(book.canonical_level("rush_dark_knight", 8), 30)
	assert_eq(book.canonical("rush_dark_knight", 30, "damage"), 130.0)
	assert_eq(book.canonical("rush_dark_knight", 30, "mobCount"), 15.0)
	var lt: Array = book.level_node("rush_dark_knight", 30).lt["$v"]
	assert_eq([lt[0], lt[1]], [-250.0, -50.0], "the level-30 box")
	lib.free()
