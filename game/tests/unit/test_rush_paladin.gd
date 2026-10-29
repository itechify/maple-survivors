extends "res://tests/unit/test_rush.gd"
## Paladin's Rush (spec #308 P4, #312; WZ 1221007, book 122): the whole Rush test set of test_rush.gd re-run for
## `rush_paladin` (every inherited test_ method runs with the Paladin job, book, key and skill id), plus the checks that it
## is a data copy of Hero's Rush and ranks with the round level exactly like Hero's (balance.mobility_rank_levels).

const PER_BOOK_FIELDS := ["skill_id", "book", "job", "icon", "effect", "cast_visuals", "sounds"]


func _job() -> int:
	return 122


func _book() -> String:
	return "122"


func _key() -> String:
	return "rush_paladin"


func _skill_id() -> int:
	return 1221007


## A definition without its `_` notes and without the fields that name the book, the art or the sound.
static func _shape(def: Dictionary) -> Dictionary:
	var out := {}
	for field: String in def:
		if not field.begins_with("_") and not field in PER_BOOK_FIELDS and field != "extends":
			out[field] = def[field]
	return out


# --- Data ---------------------------------------------------------------------------------------------------------------

## Paladin's Rush is `rush_hero` with its own book, ids, art and sound: every other field is the same value (#312 "copy").
func test_rush_paladin_is_a_data_copy_of_rush_hero() -> void:
	var defs: Dictionary = SkillBook.from_data(DataRepo.load_all().skills, {}).defs
	assert_true(defs.has("rush_paladin"), "P4 defines it in skills/paladin.json")
	assert_eq(_shape(defs.rush_paladin), _shape(defs.rush_hero), "the same shape, ranks and numbers")
	var paladin: Dictionary = defs.rush_paladin
	assert_eq(int(paladin.skill_id), 1221007)
	assert_eq(String(paladin.book), "122")
	assert_eq(int(paladin.job), 122)
	assert_eq(String(paladin.icon), "Skill.wz/122.img/skill/1221007/icon")
	assert_eq(String(paladin.effect), "Skill.wz/122.img/skill/1221007/effect")
	assert_eq(String(paladin.cast_visuals[0].path), "Skill.wz/122.img/skill/1221007/effect0")
	assert_eq(String(paladin.sounds.use), "Sound.wz/Skill.img/1221007/Use", "the UOL to Hero's Use sound, as P1 imports it")
	assert_false(paladin.has("ranks"), "no ranks override, as Hero's")
	assert_false(paladin.has("level_ranks"))


# --- Rank -----------------------------------------------------------------------------------------------------------------

## Both Rushes take the same rank at every round level 1..40, and the same numbers at that rank: the shared rule, not a card.
func test_paladin_rush_ranks_with_the_round_level_exactly_like_hero_rush() -> void:
	var hero := _world_for(112, "112", 1121006)
	var paladin := _world_for(122, "122", 1221007)
	for level in range(1, 41):
		_level_to(hero, level)
		_level_to(paladin, level)
		assert_eq(paladin.loadout.rank("rush_paladin"), hero.loadout.rank("rush_hero"), "rank at Lv%d" % level)
		var hs := hero.runner.stats_of(hero, "rush_hero")
		var ps := paladin.runner.stats_of(paladin, "rush_paladin")
		assert_eq(int(ps.level), int(hs.level), "WZ level at Lv%d" % level)
		assert_near(float(ps.damage_pct), float(hs.damage_pct), 1e-9, "damage at Lv%d" % level)
		assert_eq(int(ps.mob_count), int(hs.mob_count), "mobCount at Lv%d" % level)
		assert_eq(float(ps.displacement.distance), float(hs.displacement.distance), "dash distance at Lv%d" % level)
	assert_eq(paladin.loadout.rank("rush_paladin"), 8, "rank 8 at Lv40, clamped like Hero's")


# --- Real cache -----------------------------------------------------------------------------------------------------------

## Needs the real asset cache (SKIPs without it, which proves nothing): the rank table of 1221007 reads the same WZ levels
## as 1121006's, and the level-30 row of Paladin's Rush is the Hero's too (P1 #309 compares every level row).
func test_real_cache_paladin_rush_ranks_on_the_same_wz_levels_as_hero_rush() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	assert_true(lib.open())
	var book := SkillBook.from_data(DataRepo.load_all().skills, {
		"112": lib.img("Skill.wz/112.img").root, "122": lib.img("Skill.wz/122.img").root})
	assert_eq(book.max_level("rush_paladin"), book.max_level("rush_hero"))
	for rank in range(1, 9):
		assert_eq(book.canonical_level("rush_paladin", rank), book.canonical_level("rush_hero", rank), "rank %d" % rank)
	assert_eq(book.canonical_level("rush_paladin", 8), 30)
	assert_eq(book.canonical("rush_paladin", 30, "damage"), 130.0)
	lib.free()
