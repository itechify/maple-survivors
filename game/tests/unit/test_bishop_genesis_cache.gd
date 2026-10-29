extends TestCase
## Bishop Genesis and Big Bang against the real Skill.wz (spec #372, BS6 #378): the eight survivor ranks map to the WZ levels
## 4, 8, 12, 15, 19, 23, 27, 30 and read those level rows of book 232; the art, tile spacing, delay and sounds the definitions
## name exist; Big Bang 232 matches 212 node for node; and the I5 drift guard passes on the shipped big_bang_bishop / big_bang pair.
## Real-cache test: SKIPs without the cache or without Skill.wz/232.img (import with the Bishop manifest fragment).

## The eight survivor ranks of a 30-level skill (skills.json rank_levels "30", ADR 0006 #287, tier C).
const LEVELS := [4, 8, 12, 15, 19, 23, 27, 30]
## Genesis mad at ranks 1..8 (BS1-373.md "Rank values").
const GENESIS_MAD := [460, 500, 540, 570, 610, 635, 655, 670]
const BIG_BANG_MAD := [190, 230, 270, 300, 340, 380, 420, 450]

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
	if not imgs.has("232") or not imgs.has("212"):
		skip("the cache has no Skill.wz/232.img (import with asset_manifest.d/bishop.json)")
		return false
	return true


func _wz_level(id: int, level: int) -> Dictionary:
	return imgs["232"].skill[str(id)].level[str(level)]


func test_all_eight_ranks_of_both_skills_read_the_mapped_232_level_rows() -> void:
	if not _ready_or_skip():
		return
	for key: String in ["genesis", "big_bang_bishop"]:
		var id := book.skill_id(key)
		var lo := Loadout.new(book)
		assert_true(lo.add_skill(key))
		assert_eq(book.max_rank(key), 8, key)
		for rank in range(1, 9):
			lo.set_rank(key, rank)
			var lv: int = LEVELS[rank - 1]
			var st := lo.stats(key)
			assert_eq(int(st.level), lv, "%s rank %d" % [key, rank])
			var row := _wz_level(id, lv)
			assert_eq(book.canonical(key, lv, "mad"), float(row.mad), "%s rank %d mad" % [key, rank])
			assert_eq(int(st.mob_count), int(row.mobCount), "%s rank %d mobCount" % [key, rank])
			if key == "genesis":
				assert_eq(book.canonical(key, lv, "mad"), float(GENESIS_MAD[rank - 1]), "Genesis rank %d against the BS1 table" % rank)
				assert_eq(st.box, Rect2(-400, -350, 800, 600), "the WZ box at rank %d" % rank)
				assert_eq(int(st.mob_count), 15, "mobCount at rank %d" % rank)
			else:
				assert_eq(book.canonical(key, lv, "mad"), float(BIG_BANG_MAD[rank - 1]), "Big Bang rank %d against the BS1 table" % rank)


func test_the_rank_values_the_spec_lists() -> void:
	if not _ready_or_skip():
		return
	var genesis := {1: 460.0, 4: 570.0, 8: 670.0}
	var big_bang := {1: 190.0, 4: 300.0, 8: 450.0}
	for rank: int in genesis:
		var lv: int = LEVELS[rank - 1]
		assert_eq(book.canonical("genesis", lv, "mad"), genesis[rank], "Genesis rank %d" % rank)
		assert_eq(book.canonical("big_bang_bishop", lv, "mad"), big_bang[rank], "Big Bang rank %d" % rank)
	assert_eq(book.canonical("genesis", 30, "mobCount"), 15.0)
	assert_eq(book.canonical("big_bang_bishop", 30, "mobCount"), 6.0)


## A node as text with every canvas reduced to its size: the atlas page and position depend on how each book was packed, the
## size, origin, delay and values are the skill's own.
func _shape(node: Variant) -> Variant:
	if node is Dictionary:
		var out := {}
		for k: String in node:
			if k == "$canvas":
				return [node[k][3], node[k][4]]
			out[k] = _shape(node[k])
		return out
	return node


func test_the_232_big_bang_matches_the_212_node_for_node() -> void:
	if not _ready_or_skip():
		return
	var bishop: Dictionary = imgs["232"].skill["2321001"]
	var fp: Dictionary = imgs["212"].skill["2121001"]
	assert_eq(bishop.keys().size(), fp.keys().size(), "the same top-level keys")
	for lv in range(1, 31):
		assert_eq(JSON.stringify(bishop.level[str(lv)]), JSON.stringify(fp.level[str(lv)]), "level %d" % lv)
	for k: String in fp.keys():
		assert_true(bishop.has(k), "232 has %s" % k)
		assert_eq(JSON.stringify(_shape(bishop.get(k))), JSON.stringify(_shape(fp[k])), "node %s" % k)
	assert_eq((bishop.keydown as Dictionary).size(), 18)


func test_the_i5_drift_guard_iterates_the_shipped_pair_and_passes() -> void:
	if not _ready_or_skip():
		return
	var exists := func(path: String) -> bool: return lib.find(path) != null or lib.sound(path) != null
	var pairs := SkillTemplate.pairs(book)
	assert_true(["big_bang_bishop", "big_bang"] in pairs, "the shipped pair is among %s" % [pairs])
	assert_false(["big_bang_bishop", "big_bang_il"] in pairs, "never the I/L child")
	var problems := SkillTemplate.drift_problems(book, "big_bang_bishop", "big_bang", exists)
	assert_eq(problems, PackedStringArray(), "%s" % [problems])


func test_genesis_data_matches_the_wz_nodes_it_mirrors() -> void:
	if not _ready_or_skip():
		return
	var node: Dictionary = imgs["232"].skill["2321008"]
	var d := book.def("genesis")
	assert_eq(float(d.pending.delay), float(node.hit["0"].hitAfter) / 1000.0, "pending delay = hitAfter")
	assert_eq(String(book.skill_node("genesis").elemAttr), "h")
	assert_eq(String(d.element), "h")
	assert_eq(String(node.action["0"]), String(d.action), "action/0 is the stance")
	var distance := int(node.tile.effectDistance)
	assert_eq(distance, 150)
	for k in 9:
		assert_eq(int(d.cast_visuals[k].x), (k - 4) * distance, "tile %d x" % k)
	# Tile frame counts: 24, 24, 24, then 23 (the BS1 correction; the spec lists none).
	var counts := []
	for k in 9:
		counts.append(lib.anim("Skill.wz/232.img/skill/2321008/tile/%d" % k).frames.size())
	assert_eq(counts, [24, 24, 24, 23, 23, 23, 23, 23, 23])
	assert_eq(lib.anim("Skill.wz/232.img/skill/2321008/effect").frames.size(), 22)
	assert_eq(lib.anim("Skill.wz/232.img/skill/2321008/effect0").frames.size(), 22)
	assert_eq(lib.anim("Skill.wz/232.img/skill/2321008/hit/0").frames.size(), 23)


func test_the_outer_tile_columns_reach_past_the_damage_box() -> void:
	# Nine columns at 150 px: the outermost centres are at +-600, past the +-400 box; the widest frame of each tile (read
	# from the real canvases) keeps the curtain's edges at or beyond the box edges. Interior gaps between thin columns are
	# the art's own (a tile is a growing pillar of light, not a wall); the screenshot is the judge of the look.
	if not _ready_or_skip():
		return
	var d := book.def("genesis")
	var left := 1.0e9
	var right := -1.0e9
	for k in 9:
		var anim := lib.anim(String(d.cast_visuals[k].path))
		var widest := 0.0
		for f in anim.frames:
			widest = maxf(widest, f.region.size.x)
		assert_true(widest > 50.0, "tile %d has a real column (%d px)" % [k, widest])
		left = minf(left, float(d.cast_visuals[k].x) - widest * 0.5)
		right = maxf(right, float(d.cast_visuals[k].x) + widest * 0.5)
	assert_true(left <= -400.0 and right >= 400.0, "the curtain %d..%d covers the box" % [left, right])


func test_every_art_and_sound_path_of_both_skills_resolves() -> void:
	if not _ready_or_skip():
		return
	for key: String in ["genesis", "big_bang_bishop"]:
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
		for path: String in paths + d.sounds.values():
			assert_false(path.contains("212.img") or path.contains("2121001"), "%s names an F/P path: %s" % [key, path])
	assert_eq(lib.anim("Skill.wz/232.img/skill/2321001/keydown").frames.size(), 18)
	assert_true(lib.missing.is_empty(), str(lib.missing))
