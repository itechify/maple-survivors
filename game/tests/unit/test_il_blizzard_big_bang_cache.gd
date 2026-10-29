extends TestCase
## I/L Blizzard and Big Bang against the real Skill.wz (spec #319 I10 #329): the eight survivor ranks map to the WZ levels
## 4, 8, 12, 15, 19, 23, 27, 30 and read those level rows of book 222; the art, tile spacing, delay and sounds the definitions
## name exist; and the I5 drift guard passes on the shipped big_bang_il / big_bang pair. Real-cache test: SKIPs without it.

## The eight survivor ranks of a 30-level skill (skills.json rank_levels "30", ADR 0006 #287, tier C).
const LEVELS := [4, 8, 12, 15, 19, 23, 27, 30]

var lib: AssetLibrary
var imgs := {}
var book: SkillBook


func before_each() -> void:
	lib = AssetLibrary.new()
	lib.open()
	imgs = {}
	var data := DataRepo.load_all()
	for b: String in DataRepo.skill_books(data):
		var w := lib.img(DataRepo.skill_img_path(b))
		if w != null:
			imgs[b] = w.root
	book = SkillBook.from_data(data.skills, imgs)


func after_each() -> void:
	lib.free()


func _ready_or_skip() -> bool:
	if not require_cache():
		return false
	if not imgs.has("222"):
		skip("the cache has no Skill.wz/222.img (import with the I/L manifest fragment)")
		return false
	return true


func _wz_level(id: int, level: int) -> Dictionary:
	return imgs["222"].skill[str(id)].level[str(level)]


func test_all_eight_ranks_of_both_skills_read_the_mapped_222_level_rows() -> void:
	if not _ready_or_skip():
		return
	for key: String in ["blizzard", "big_bang_il"]:
		var id := book.skill_id(key)
		var lo := Loadout.new(book)
		assert_true(lo.add_skill(key))
		assert_eq(book.max_rank(key), 8)
		for rank in range(1, 9):
			lo.set_rank(key, rank)
			var lv: int = LEVELS[rank - 1]
			var st := lo.stats(key)
			assert_eq(int(st.level), lv, "%s rank %d" % [key, rank])
			var row := _wz_level(id, lv)
			assert_eq(book.canonical(key, lv, "mad"), float(row.mad), "%s rank %d mad" % [key, rank])
			assert_eq(int(st.mob_count), int(row.mobCount), "%s rank %d mobCount" % [key, rank])
			if key == "blizzard":
				assert_eq(book.canonical(key, lv, "time"), float(row.time), "freeze time at rank %d" % rank)
				assert_eq(st.box, Rect2(-400, -350, 800, 600), "the WZ box at rank %d" % rank)


func test_the_rank_values_the_spec_lists() -> void:
	if not _ready_or_skip():
		return
	var blizzard := {1: [360.0, 1.0], 4: [470.0, 2.0], 8: [570.0, 3.0]}
	var big_bang := {1: 190.0, 4: 300.0, 8: 450.0}
	for rank: int in blizzard:
		var lv: int = LEVELS[rank - 1]
		assert_eq(book.canonical("blizzard", lv, "mad"), blizzard[rank][0], "Blizzard rank %d" % rank)
		assert_eq(book.canonical("blizzard", lv, "time"), blizzard[rank][1], "Blizzard freeze rank %d" % rank)
		assert_eq(book.canonical("big_bang_il", lv, "mad"), big_bang[rank], "Big Bang rank %d" % rank)
	assert_eq(book.canonical("blizzard", 30, "mobCount"), 15.0)
	assert_eq(book.canonical("big_bang_il", 30, "mobCount"), 6.0)


func test_the_222_big_bang_numbers_equal_the_212_ones_at_every_mapped_level() -> void:
	if not _ready_or_skip():
		return
	for lv: int in LEVELS:
		var il: Dictionary = _wz_level(2221001, lv)
		var fp: Dictionary = imgs["212"].skill["2121001"].level[str(lv)]
		assert_eq(JSON.stringify(il), JSON.stringify(fp), "level %d" % lv)


func test_the_i5_drift_guard_iterates_the_shipped_pair_and_passes() -> void:
	if not _ready_or_skip():
		return
	var exists := func(path: String) -> bool: return lib.find(path) != null or lib.sound(path) != null
	var pairs := SkillTemplate.pairs(book)
	assert_true(["big_bang_il", "big_bang"] in pairs, "the shipped pair is among %s" % [pairs])
	var problems := SkillTemplate.drift_problems(book, "big_bang_il", "big_bang", exists)
	assert_eq(problems, PackedStringArray(), "%s" % [problems])


func test_blizzard_data_matches_the_wz_nodes_it_mirrors() -> void:
	if not _ready_or_skip():
		return
	var node: Dictionary = imgs["222"].skill["2221007"]
	var d := book.def("blizzard")
	assert_eq(float(d.pending.delay), float(node.hit["0"].hitAfter) / 1000.0, "pending delay = hitAfter")
	assert_eq(String(book.skill_node("blizzard").elemAttr), "i")
	assert_eq(String(d.element), "i")
	var distance := int(node.tile.effectDistance)
	assert_eq(distance, 180)
	for k in 9:
		assert_eq(int(d.cast_visuals[k].x), (k - 4) * distance)


func test_every_art_and_sound_path_of_both_skills_resolves() -> void:
	if not _ready_or_skip():
		return
	for key: String in ["blizzard", "big_bang_il"]:
		var d := book.def(key)
		var paths: Array = [d.effect, d.hit, d.icon]
		paths.append_array(d.get("release_visuals", []))
		paths.append(String(d.get("pending", {}).get("effect", "")))
		for visual: Dictionary in d.get("cast_visuals", []):
			paths.append(visual.path)
		for path: String in paths:
			if path == "":
				continue
			if path.ends_with("/icon"):
				assert_true(lib.find(path) != null, path)
			else:
				assert_true(lib.anim(path).frames.size() > 0, path)
		for path: String in d.sounds.values():
			assert_true(lib.sound(path) != null, path)
	assert_eq(lib.anim("Skill.wz/222.img/skill/2221007/effect").frames.size(), 25)
	assert_eq(lib.anim("Skill.wz/222.img/skill/2221007/hit/0").frames.size(), 21)
	assert_eq(lib.anim("Skill.wz/222.img/skill/2221001/keydown").frames.size(), 18)
	assert_true(lib.missing.is_empty(), str(lib.missing))
