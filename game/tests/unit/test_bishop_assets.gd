extends TestCase
## The Bishop's imported assets (spec #372 ticket #373, docs/ASSET_PIPELINE.md 4.1): the 231 and 232 books are in the asset
## cache, every sound of the ten-skill pool resolves through AssetLibrary.sound (Big Bang's UOL sounds under its own skill id
## included), and the art nodes the skill tickets (BS4-BS8) read have the frame counts recorded in BS1-373.md. Real-cache
## test: SKIPs without the cache (CI has none).

## Sound.wz/Skill.img node -> the sound names it must have (tier A, read off the imported data).
const SOUNDS := {2311004: ["Use"], 2311006: ["Use", "Summon"], 2321001: ["Use", "Loop"], 2321003: ["Use"], 2321006: ["Use"],
	2321007: ["Use"], 2321008: ["Use", "Hit"]}
## skill id -> {node under Skill.wz/<book>.img/skill/<id>: frame count}; tier A, read off the imported books.
const FRAMES := {
	2301005: {"ball": 3, "effect": 7, "hit/0": 3},
	2311004: {"effect": 11, "hit/0": 2},
	2321007: {"ball": 1, "effect": 15, "hit/0": 7},
	2301002: {"effect": 10, "affected": 7, "hit/0": 7},
	2311006: {"summon/summoned": 5, "summon/fly": 5, "summon/stand": 5, "summon/attack1": 8, "summon/die": 6, "hit/0": 1},
	2321003: {"summon/summoned": 6, "summon/fly": 6, "summon/stand": 12, "summon/attack1": 18, "summon/die": 6, "hit/0": 7},
	2321008: {"tile/0": 24, "tile/1": 24, "tile/2": 24, "tile/3": 23, "tile/4": 23, "tile/5": 23, "tile/6": 23, "tile/7": 23,
		"tile/8": 23, "effect": 22, "effect0": 22, "hit/0": 23},
	2321001: {"keydown": 18, "effect": 10, "special/0": 5, "special/1": 5, "special/2": 5},
	2321006: {"effect": 21, "affected": 15},
}
## key -> [skill id, level count]; the pool's tier A level tables.
const POOL := {"holy_arrow": [2301005, 30], "shining_ray": [2311004, 30], "angel_ray": [2321007, 30], "heal": [2301002, 30],
	"summon_dragon": [2311006, 30], "bahamut": [2321003, 30], "genesis": [2321008, 30], "big_bang": [2321001, 30],
	"resurrection": [2321006, 10]}

var lib: AssetLibrary


func before_each() -> void:
	lib = AssetLibrary.new()
	lib.open()


func after_each() -> void:
	lib.free()


## True when the cache holds the Bishop books (an older cache imported without the fragment skips).
func _ready_cache() -> bool:
	if not require_cache():
		return false
	if lib.img("Skill.wz/232.img") == null or lib.img("Skill.wz/231.img") == null:
		skip("the cache has no Skill.wz/231.img or 232.img (import with the Bishop manifest fragment)")
		return false
	return true


## The skill node path of `id` in its own book.
func _skill(id: int) -> String:
	return "Skill.wz/%d.img/skill/%d" % [id / 10000, id]


## Numbered canvas children of `path` (0, 1, 2, ... until the first gap), -1 when the node is absent.
func _frames(path: String) -> int:
	var n: Variant = lib.node(path)
	if not n is Dictionary:
		return -1
	var count := 0
	while WzImg.is_canvas((n as Dictionary).get(str(count))):
		count += 1
	return count


func _level(id: int, lv: int, field: String) -> Variant:
	return lib.node("%s/level/%d/%s" % [_skill(id), lv, field])


func test_every_bishop_pool_sound_resolves_under_its_own_skill_id() -> void:
	if not _ready_cache():
		return
	for id: int in SOUNDS:
		for sound: String in SOUNDS[id]:
			var path := "Sound.wz/Skill.img/%d/%s" % [id, sound]
			assert_true(lib.sound(path) != null, "%s resolves" % path)
	assert_eq(lib.missing.size(), 0, "no lookup missed: %s" % str(lib.missing))


func test_big_bang_sounds_are_uols_that_play_the_f_p_files() -> void:
	if not _ready_cache():
		return
	for sound in ["Use", "Loop"]:
		var own: Variant = lib.node("Sound.wz/Skill.img/2321001/%s" % sound)
		var parent: Variant = lib.node("Sound.wz/Skill.img/2121001/%s" % sound)
		assert_true(own is Dictionary and parent is Dictionary, "2321001 %s: both nodes exist" % sound)
		assert_eq(String(own["$sound"]), String(parent["$sound"]), "2321001 %s is the F/P file" % sound)
		assert_true(lib.sound("Sound.wz/Skill.img/2321001/%s" % sound) != null)


func test_the_books_hold_every_pool_skill_with_icons_levels_and_names() -> void:
	if not _ready_cache():
		return
	for key: String in POOL:
		var id: int = POOL[key][0]
		var base := _skill(id)
		for icon in ["icon", "iconMouseOver", "iconDisabled"]:
			assert_true(lib.frame("%s/%s" % [base, icon]) != null, "%d %s" % [id, icon])
		var levels: Variant = lib.node(base + "/level")
		assert_true(levels is Dictionary and (levels as Dictionary).size() == POOL[key][1], "%s has %d levels" % [key, POOL[key][1]])
		# No field hole: every field of level 1 is present at every level.
		for lv in range(1, int(POOL[key][1]) + 1):
			for field: String in ((levels as Dictionary)["1"] as Dictionary):
				assert_true(((levels as Dictionary)[str(lv)] as Dictionary).has(field), "%s level %d has %s" % [key, lv, field])
		assert_true(lib.string_name("Skill", id) != "", "%d has a String.wz name" % id)
	var names := {2301005: "Holy Arrow", 2311004: "Shining Ray", 2321007: "Angel Ray", 2301002: "Heal", 2311006: "Summon Dragon",
		2321003: "Bahamut", 2321008: "Genesis", 2321001: "Big Bang", 2321006: "Resurrection", 2301001: "Teleport"}
	for id: int in names:
		assert_eq(lib.string_name("Skill", id), names[id], "%d name" % id)


func test_the_art_nodes_the_skill_tickets_read_have_the_listed_frame_counts() -> void:
	if not _ready_cache():
		return
	for id: int in FRAMES:
		for node: String in FRAMES[id]:
			assert_eq(_frames("%s/%s" % [_skill(id), node]), FRAMES[id][node], "%d %s frame count" % [id, node])
	assert_true(WzImg.is_canvas(lib.node(_skill(2321007) + "/ball/0")), "Angel Ray ball/0 is the single canvas frame")
	assert_eq(lib.node(_skill(2321008) + "/hit/0/hitAfter"), 1800.0)
	assert_eq(lib.node(_skill(2321008) + "/tile/effectDistance"), 150.0)
	assert_eq(lib.node(_skill(2321006) + "/affected/0/delay"), 1320.0, "Resurrection's affected lead-in frame")
	var lead := lib.frame(_skill(2321006) + "/affected/0")
	assert_true(lead != null, "the lead-in frame decodes")
	assert_eq(lib.node(_skill(2321003) + "/summon/attack1/info/attackAfter"), 990.0)
	assert_eq(lib.node(_skill(2321003) + "/summon/attack1/info/mobCount"), 3.0)
	assert_eq(lib.node(_skill(2311006) + "/summon/attack1/info/attackAfter"), 500.0)
	assert_eq(lib.node(_skill(2311006) + "/summon/attack1/info/type"), 1.0)
	assert_eq(lib.find(_skill(2311006) + "/summon/attack1/info/mobCount"), null, "Summon Dragon strikes one target")
	assert_eq(lib.find(_skill(2311006) + "/summon/move"), null, "the dragons have fly, not move")
	assert_eq(lib.find(_skill(2321003) + "/summon/move"), null)
	assert_eq(lib.node(_skill(2321001) + "/prepare/action"), "dash")
	assert_eq(lib.node(_skill(2321001) + "/special/start"), 150.0)


func test_actions_and_elements_match_the_spec() -> void:
	if not _ready_cache():
		return
	var actions := {2301005: "shoot1", 2311004: "magic2", 2321007: "shoot1", 2301002: "alert2", 2311006: "alert2",
		2321003: "alert2", 2321008: "genesis", 2321006: "resurrection"}
	for id: int in actions:
		assert_eq(lib.node(_skill(id) + "/action/0"), actions[id], "%d action" % id)
	for id in [2301005, 2311004, 2321007, 2321003, 2321008]:
		assert_eq(lib.node(_skill(id) + "/elemAttr"), "h", "%d is holy" % id)
	for id in [2301002, 2311006, 2321001, 2321006]:
		assert_eq(lib.find(_skill(id) + "/elemAttr"), null, "%d has no elemAttr" % id)
	assert_eq(lib.node(_skill(2321003) + "/req/2311006"), 15.0, "Bahamut's (dropped) prerequisite")


func test_rank_values_match_the_spec_and_never_decrease_with_level() -> void:
	if not _ready_cache():
		return
	# rank 1 / 4 / 8 = WZ levels 4 / 15 / 30 (Resurrection 2 / 5 / 10).
	var rows := {
		[2301005, "mad"]: [28, 50, 80], [2311004, "mad"]: [66, 88, 105], [2321007, "mad"]: [132, 170, 240],
		[2301002, "hp"]: [40, 150, 300], [2311006, "mad"]: [76, 120, 150], [2311006, "time"]: [25, 80, 140],
		[2321003, "mad"]: [122, 160, 230], [2321003, "time"]: [30, 85, 160], [2321008, "mad"]: [460, 570, 670],
		[2321001, "mad"]: [190, 300, 450]}
	for key: Array in rows:
		var at: Array = rows[key]
		var lvs := [4, 15, 30]
		for i in 3:
			assert_eq(_level(key[0], lvs[i], key[1]), float(at[i]), "%d %s at level %d" % [key[0], key[1], lvs[i]])
	# Every numeric growth field is non-decreasing over the levels (mpCon is not read and is wild).
	for key: String in POOL:
		var id: int = POOL[key][0]
		for field in ["mad", "hp", "time", "mastery", "mobCount"]:
			var prev := -1.0
			for lv in range(1, int(POOL[key][1]) + 1):
				var v: Variant = _level(id, lv, field)
				if v == null:
					break
				assert_true(float(v) >= prev, "%s %s never drops at level %d" % [key, field, lv])
				prev = float(v)
	# Bahamut's level node mobCount is 3 up to level 29 and 6 only at level 30.
	for lv in range(1, 30):
		assert_eq(_level(2321003, lv, "mobCount"), 3.0, "Bahamut level %d" % lv)
	assert_eq(_level(2321003, 30, "mobCount"), 6.0)
	assert_eq(_level(2311006, 1, "mobCount"), null, "Summon Dragon has no mobCount")
	# Boxes: Heal grows at level 16, Shining Ray at 11 and 21, Genesis and Resurrection never change.
	assert_eq(WzImg.vec(lib.node(_skill(2301002) + "/level/15/rb")), Vector2(250, 150))
	assert_eq(WzImg.vec(lib.node(_skill(2301002) + "/level/16/rb")), Vector2(300, 200))
	assert_eq(WzImg.vec(lib.node(_skill(2311004) + "/level/10/rb")), Vector2(150, 50))
	assert_eq(WzImg.vec(lib.node(_skill(2311004) + "/level/11/rb")), Vector2(160, 50))
	assert_eq(WzImg.vec(lib.node(_skill(2311004) + "/level/21/rb")), Vector2(170, 50))
	for lv in [1, 15, 30]:
		assert_eq(WzImg.vec(lib.node(_skill(2321008) + "/level/%d/lt" % lv)), Vector2(-400, -350))
		assert_eq(WzImg.vec(lib.node(_skill(2321008) + "/level/%d/rb" % lv)), Vector2(400, 250))
	for lv in [1, 5, 10]:
		assert_eq(WzImg.vec(lib.node(_skill(2321006) + "/level/%d/rb" % lv)), Vector2(400, 250))


func test_resurrection_recharge_table_is_the_wz_cooltime_curve_rescaled() -> void:
	if not _ready_cache():
		return
	var table := [600.0, 540.0, 480.0, 420.0, 300.0, 240.0, 180.0, 120.0]
	var levels := [2, 3, 4, 5, 7, 8, 9, 10]
	for i in 8:
		var cooltime: float = float(_level(2321006, levels[i], "cooltime"))
		assert_eq(cooltime / 3.0 - 480.0, table[i], "recharge of rank %d is cooltime / 3 - 480" % (i + 1))
	assert_eq(_level(2321006, 1, "cooltime"), 3420.0)
	assert_eq(_level(2321006, 10, "cooltime"), 1800.0)


func test_big_bang_232_is_big_bang_212_on_everything_the_game_reads() -> void:
	if not _ready_cache():
		return
	for lv in range(1, 31):
		for field in ["mad", "mastery", "mobCount"]:
			var f := "level/%d/%s" % [lv, field]
			assert_eq(lib.node(_skill(2321001) + "/" + f), lib.node("Skill.wz/212.img/skill/2121001/" + f),
				"Big Bang %s at level %d matches the F/P book" % [field, lv])
	for node in ["keydown", "effect", "special/0", "special/1", "special/2"]:
		assert_eq(_frames(_skill(2321001) + "/" + node), _frames("Skill.wz/212.img/skill/2121001/" + node),
			"Big Bang %s frame count matches the F/P book" % node)
	assert_eq(lib.node(_skill(2321001) + "/masterLevel"), lib.node("Skill.wz/212.img/skill/2121001/masterLevel"))


func test_teleport_in_the_cleric_book_is_the_f_p_teleport() -> void:
	if not _ready_cache():
		return
	for lv in [1, 10, 11, 15, 20]:
		assert_eq(_level(2301001, lv, "range"), _level(2101002, lv, "range"), "Teleport range at level %d" % lv)
	assert_eq(_level(2301001, 1, "range"), 130.0)
	assert_eq(_level(2301001, 20, "range"), 150.0)
