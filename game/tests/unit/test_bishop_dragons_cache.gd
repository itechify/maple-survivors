extends TestCase
## Summon Dragon and Bahamut against the real v83 books (spec #372, BS7 #379): the mapped `mad`, `time` and `mobCount` of all eight
## ranks, the attack info and every animation node. Needs the asset cache with Skill.wz 231/232 (`require_cache()`; a SKIP proves nothing).
const BF := preload("res://tests/fixtures/bishop_bolt_fixtures.gd")
const D := preload("res://tests/unit/test_bishop_dragons.gd")

func _book(lib: AssetLibrary) -> SkillBook:
	return SkillBook.from_data(DataRepo.load_all().skills,
		{"231": lib.img("Skill.wz/231.img").root, "232": lib.img("Skill.wz/232.img").root})

func test_cached_dragons_map_all_eight_ranks_to_the_recorded_values() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	assert_true(lib.open())
	var book := _book(lib)
	var lo := Loadout.new(book)
	lo.add_skill("summon_dragon")
	lo.add_skill("bahamut")
	assert_eq(book.skill_id("summon_dragon"), 2311006)
	assert_eq(book.skill_id("bahamut"), 2321003)
	for key: String in ["summon_dragon", "bahamut"]:
		assert_eq(book.max_rank(key), 8, key)
		var mads: Array = D.DRAGON_MAD if key == "summon_dragon" else D.BAHAMUT_MAD
		var times: Array = D.DRAGON_TIME if key == "summon_dragon" else D.BAHAMUT_TIME
		for rank in range(1, 9):
			lo.set_rank(key, rank)
			var st := lo.stats(key)
			var label := "%s rank %d" % [key, rank]
			assert_eq(int(st.level), BF.RANK_LEVELS[rank - 1], label + " level")
			assert_near(book.canonical(key, int(st.level), "mad", 0.0), float(mads[rank - 1]), 0.0001, label + " mad")
			assert_near(float(st.duration), float(times[rank - 1]), 0.0001, label + " time")
			assert_near(book.canonical(key, int(st.level), "mastery", 0.0), float(BF.MASTERY[rank - 1]), 0.0001, label + " mastery")
			var wz_count := book.canonical(key, int(st.level), "mobCount", -1.0)
			if key == "bahamut":
				assert_eq(int(wz_count), D.BAHAMUT_TARGETS[rank - 1], label + " mobCount")
			else:
				assert_eq(wz_count, -1.0, label + ": Summon Dragon has no mobCount (one target)")
			assert_eq(st.element, "h", label)
	lib.free()

func test_cached_dragons_attack_info_and_every_animation_node() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	assert_true(lib.open())
	var book := _book(lib)
	var dragon: Dictionary = book.skill_node("summon_dragon")
	var bahamut: Dictionary = book.skill_node("bahamut")
	assert_false(dragon.has("elemAttr"), "Summon Dragon's holy element is tier C: the WZ has none")
	assert_eq(String(bahamut.elemAttr), "h")
	var d_info: Dictionary = dragon.summon.attack1.info
	var b_info: Dictionary = bahamut.summon.attack1.info
	assert_false(d_info.has("mobCount"), "no info.mobCount: one target")
	assert_eq(int(d_info.attackAfter), 500)
	assert_eq(d_info.range.lt["$v"], [-200.0, -150.0])
	assert_eq(d_info.range.rb["$v"], [200.0, 150.0])
	assert_eq(int(b_info.attackAfter), 990)
	assert_eq(int(b_info.mobCount), 3, "the attack node's count is a constant 3: the level field is the one that rises")
	assert_eq(b_info.range.lt["$v"], [-200.0, -150.0])
	assert_eq(b_info.range.rb["$v"], [0.0, 30.0])
	var frames := {"summoned": [5, 6], "fly": [5, 6], "stand": [5, 12], "attack1": [8, 18], "die": [6, 6]}
	for i in 2:
		var key := "summon_dragon" if i == 0 else "bahamut"
		var def := book.def(key)
		assert_eq(String(def.summon.move), "fly", key)
		assert_true(book.skill_node(key).summon.get("move") == null, "%s: the book has no move node" % key)
		for a: String in frames:
			var anim := lib.anim(String(def.summon.path) + "/" + a)
			assert_true(anim != null and not anim.is_empty(), "%s %s" % [key, a])
			assert_eq(anim.frame_count(), frames[a][i], "%s %s frames" % [key, a])
		assert_true(not lib.anim(String(def.hit)).is_empty(), key + " hit/0")
	assert_eq(lib.anim(book.def("summon_dragon").hit).frame_count(), 1)
	assert_eq(lib.anim(book.def("bahamut").hit).frame_count(), 7)
	assert_true(lib.missing.is_empty(), str(lib.missing))
	lib.free()
