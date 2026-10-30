extends TestCase
## The I/L Arch Mage's imported assets (spec #319 ticket #320, docs/ASSET_PIPELINE.md 4.1): the 221 and 222 books are in the
## asset cache, every sound of the twelve-skill pool resolves through AssetLibrary.sound (the three UOL sounds under their
## own skill ids included), and the art nodes the skill tickets (I6-I10) read have the frame counts the spec lists. Real-cache
## test: SKIPs without the cache (CI has none).

## Sound.wz/Skill.img node -> true when the skill also has a `Hit` sound.
const SOUND_SKILLS := {2211002: false, 2211003: false, 2211006: false, 2221001: false, 2221003: true, 2221005: false,
	2221006: true, 2221007: true}
## skill id -> {node under Skill.wz/<book>.img/skill/<id>: frame count}; tier A, read off the imported books.
const FRAMES := {
	2211002: {"effect": 11, "hit/0": 6},
	2211003: {"effect": 15, "hit/0": 5},
	2211006: {"ball": 3, "effect": 13, "hit/0": 3},
	2221001: {"keydown": 18, "effect": 10, "special/0": 5, "special/1": 5, "special/2": 5},
	2221003: {"ball": 4, "effect": 14, "hit/0": 5},
	2221005: {"summon/summoned": 15, "summon/stand": 6, "summon/move": 6, "summon/die": 12, "hit/0": 8},
	2221006: {"ball/0": 6, "ball/1": 6, "ball/2": 6, "effect": 12, "hit/0": 6},
	2221007: {"tile/0": 25, "tile/1": 25, "tile/2": 25, "tile/3": 20, "tile/4": 23, "tile/5": 23, "tile/6": 21, "tile/7": 20,
		"tile/8": 21, "effect": 25, "hit/0": 21},
}

var lib: AssetLibrary


func before_each() -> void:
	lib = AssetLibrary.new()
	lib.open()


func after_each() -> void:
	lib.free()


## Numbered canvas children of `path` (0, 1, 2, ... until the first gap), -1 when the node is absent.
func _frames(path: String) -> int:
	var n: Variant = lib.node(path)
	if not n is Dictionary:
		return -1
	var count := 0
	while WzImg.is_canvas((n as Dictionary).get(str(count))):
		count += 1
	return count


func test_every_i_l_pool_sound_resolves_under_its_own_skill_id() -> void:
	if not require_cache():
		return
	if lib.img("Skill.wz/222.img") == null:
		skip("the cache has no Skill.wz/222.img (import with the I/L manifest fragment)")
		return
	for id: int in SOUND_SKILLS:
		var names: Array = ["Use"]
		if SOUND_SKILLS[id]:
			names.append("Hit")
		if id == 2221001:
			names.append("Loop")
		for sound: String in names:
			var path := "Sound.wz/Skill.img/%d/%s" % [id, sound]
			assert_true(lib.sound(path) != null, "%s resolves" % path)
	assert_eq(lib.missing.size(), 0, "no lookup missed: %s" % str(lib.missing))


func test_the_uol_sounds_play_the_f_p_files_they_link_to() -> void:
	if not require_cache():
		return
	if lib.img("Skill.wz/222.img") == null:
		skip("the cache has no Skill.wz/222.img (import with the I/L manifest fragment)")
		return
	for pair: Array in [[2211006, 2111006, "Use"], [2221001, 2121001, "Use"], [2221001, 2121001, "Loop"]]:
		var own: Variant = lib.node("Sound.wz/Skill.img/%d/%s" % [pair[0], pair[2]])
		var parent: Variant = lib.node("Sound.wz/Skill.img/%d/%s" % [pair[1], pair[2]])
		assert_true(own is Dictionary and parent is Dictionary, "%d %s: both nodes exist" % [pair[0], pair[2]])
		assert_eq(String(own["$sound"]), String(parent["$sound"]), "%d %s is the F/P file" % [pair[0], pair[2]])
		assert_true(lib.sound("Sound.wz/Skill.img/%d/%s" % [pair[0], pair[2]]) != null)


func test_the_books_hold_every_pool_skill_with_icons_and_thirty_levels() -> void:
	if not require_cache():
		return
	if lib.img("Skill.wz/222.img") == null:
		skip("the cache has no Skill.wz/222.img (import with the I/L manifest fragment)")
		return
	for id: int in [2211002, 2211003, 2211006, 2221001, 2221003, 2221005, 2221006, 2221007]:
		var base := "Skill.wz/%d.img/skill/%d" % [id / 10000, id]
		for icon in ["icon", "iconMouseOver", "iconDisabled"]:
			assert_true(lib.frame("%s/%s" % [base, icon]) != null, "%d %s" % [id, icon])
		var levels: Variant = lib.node(base + "/level")
		assert_true(levels is Dictionary and (levels as Dictionary).size() == 30, "%d has 30 levels" % id)
		for lv in range(1, 31):
			var row: Variant = (levels as Dictionary).get(str(lv))
			assert_true(row is Dictionary and (row as Dictionary).has("mad"), "%d level %d has mad" % [id, lv])
		assert_true(lib.string_name("Skill", id) != "", "%d has a String.wz name" % id)


func test_the_art_nodes_the_skill_tickets_read_have_the_listed_frame_counts() -> void:
	if not require_cache():
		return
	if lib.img("Skill.wz/222.img") == null:
		skip("the cache has no Skill.wz/222.img (import with the I/L manifest fragment)")
		return
	for id: int in FRAMES:
		var base := "Skill.wz/%d.img/skill/%d/" % [id / 10000, id]
		for node: String in FRAMES[id]:
			assert_eq(_frames(base + node), FRAMES[id][node], "%d %s frame count" % [id, node])
	# Big Bang's other node and timing fields, and Blizzard's delay before impact (the pending-area `hitAfter`).
	assert_eq(lib.node("Skill.wz/222.img/skill/2221001/special/start"), 150.0)
	assert_eq(lib.node("Skill.wz/222.img/skill/2221007/hit/0/hitAfter"), 1600.0)
	assert_eq(lib.node("Skill.wz/222.img/skill/2221007/tile/effectDistance"), 180.0)
	assert_eq(lib.node("Skill.wz/222.img/skill/2221005/summon/attack1/info/priority"), 2221003.0)


func test_the_three_big_bangs_are_the_same_skill_in_their_books() -> void:
	if not require_cache():
		return
	if lib.img("Skill.wz/222.img") == null:
		skip("the cache has no Skill.wz/222.img (import with the I/L manifest fragment)")
		return
	for lv in [1, 4, 15, 30]:
		for field in ["mad", "mastery", "mobCount"]:
			var f := "level/%d/%s" % [lv, field]
			assert_eq(lib.node("Skill.wz/222.img/skill/2221001/" + f), lib.node("Skill.wz/212.img/skill/2121001/" + f),
				"Big Bang %s at level %d matches the F/P book" % [field, lv])
	for node in ["keydown", "effect", "special/0", "special/1", "special/2"]:
		assert_eq(_frames("Skill.wz/222.img/skill/2221001/" + node), _frames("Skill.wz/212.img/skill/2121001/" + node),
			"Big Bang %s frame count matches the F/P book" % node)
