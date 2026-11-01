extends TestCase
## Shadower assets (spec #425, SH1 #426): the shadower.json manifest fragment, and against the real v83 cache the skill
## ids, String.wz names, level tables, art nodes, Sound.wz nodes (with the three UOLs), the Razor and the dagger's
## stances that the Shadower tickets read. The cache tests SKIP without it (a SKIP proves nothing); the manifest test
## needs none.

const SOUND_IDS := ["4121001", "4211002", "4211004", "4211006", "4221001", "4221004", "4221006", "4221007"]
## {id: String.wz name, verbatim} (tier A) and the book each lives in.
const NAMES := {"4001003": "Dark Sight", "4001334": "Double Stab", "4201004": "Steal", "4201005": "Savage Blow",
	"4211002": "Assaulter", "4211004": "Band of Thieves", "4211006": "Meso Explosion", "4221001": "Assassinate",
	"4221004": "Ninja Ambush", "4221006": "Smokescreen", "4221007": "Boomerang Step", "4220005": "Venomous Stab"}
const BOOKS := {"4001003": "400", "4001334": "400", "4201004": "420", "4201005": "420", "4211002": "421", "4211004": "421",
	"4211006": "421", "4221001": "422", "4221004": "422", "4221006": "422", "4221007": "422", "4220005": "422"}
const LEVEL_COUNTS := {"4001003": 20, "4001334": 20, "4201004": 30, "4201005": 30, "4211002": 30, "4211004": 30,
	"4211006": 30, "4221001": 30, "4221004": 30, "4221006": 30, "4221007": 30, "4220005": 30}
## Ranks 1..8 -> WZ level (`ceil(r x maxLevel / 8)`).
const LEVELS_20 := [3, 5, 8, 10, 13, 15, 18, 20]
const LEVELS_30 := [4, 8, 12, 15, 19, 23, 27, 30]
## The fields each later ticket reads (every level must hold every one: no hole).
const FIELDS := {"4001003": ["speed", "time", "x"], "4001334": ["damage", "attackCount"], "4201004": ["damage", "prop"],
	"4201005": ["damage", "attackCount"], "4211002": ["damage", "prop", "time", "mobCount", "lt", "rb"],
	"4211004": ["damage", "x", "mobCount", "lt", "rb"], "4211006": ["x", "attackCount", "mobCount", "lt", "rb"],
	"4221001": ["damage", "attackCount", "prop", "criticalDamage", "time", "mobCount", "lt", "rb"],
	"4221004": ["damage", "mobCount", "time", "lt", "rb"], "4221006": ["time", "cooltime", "lt", "rb"],
	"4221007": ["damage", "attackCount", "mobCount", "prop", "time", "lt", "rb"], "4220005": ["prop", "time", "mad"]}
## The only value drops in those fields: the per-line damage where the line count steps up (totals stay monotone).
const DROPS := {"4201005/damage": [11, 21], "4211004/damage": [7, 13, 19, 25]}
const ACTIONS := {"4001003": "darksight", "4001334": "stabO1", "4201005": "savage", "4211002": "assaulter",
	"4211006": "prone2", "4221001": "assassination", "4221004": "alert3", "4221006": "smokeshell", "4221007": "alert5"}
const DAGGERS := [1332005, 1332010, 1332056]
const SHIELD := 1092018
## Body actions the Shadower skills use; the dagger and the shield are drawn in every frame of every one.
const DAGGER_ACTIONS := ["stand1", "walk1", "alert", "alert5", "darksight", "assaulter", "assassination", "savage",
	"smokeshell", "prone2", "stabO1", "stabO2", "stabOF", "swingO1", "swingO2", "swingO3", "swingOF", "proneStab", "prone",
	"heal", "fly", "jump"]
const DAGGERLESS_ACTIONS := ["shoot1", "swingT1", "stabT1", "sit", "ladder", "rope", "dead"]


func _book(lib: AssetLibrary, id: String) -> Dictionary:
	var img := lib.img("Skill.wz/%s.img" % BOOKS[id])
	return img.root["skill"][id] if img != null else {}


func _levels(lib: AssetLibrary, id: String) -> Dictionary:
	return _book(lib, id).get("level", {})


func _art(lib: AssetLibrary, id: String, path: String) -> Variant:
	var node: Variant = _book(lib, id)
	for part in path.split("/"):
		node = (node as Dictionary).get(part) if node is Dictionary else null
	return node


## The numbered children of an animation node that are canvases (a frame count).
func _n(lib: AssetLibrary, id: String, path: String) -> int:
	var node: Variant = _art(lib, id, path)
	var count := 0
	if node is Dictionary:
		for k: Variant in (node as Dictionary).keys():
			if str(k).is_valid_int() and WzImg.is_canvas(node[k]):
				count += 1
	return count


func _vec(v: Variant) -> Vector2:
	var a: Array = (v as Dictionary)["$v"]
	return Vector2(float(a[0]), float(a[1]))


func _cache() -> bool:
	return require_cache_img("Skill.wz/422.img") and require_cache_img("Character.wz/Weapon/01332005.img")


func _at(lib: AssetLibrary, id: String, field: String, levels: Array) -> Array:
	var got := []
	for lv: int in levels:
		got.append(float(_levels(lib, id)[str(lv)][field]))
	return got


func _box(lib: AssetLibrary, id: String, levels: Array) -> Array:
	var got := []
	for lv: int in levels:
		var l: Dictionary = _levels(lib, id)[str(lv)]
		got.append([_vec(l.lt), _vec(l.rb)])
	return got


func _unique(a: PackedStringArray) -> Dictionary:
	var d := {}
	for s in a:
		d[s] = true
	return d


func test_the_shadower_fragment_names_both_books_the_razor_and_the_eight_sounds() -> void:
	var m := AssetManifest.load_merged("res://data/asset_manifest.json")
	assert_false(m.is_empty())
	var imgs := PackedStringArray()
	var sounds := PackedStringArray()
	for row: Dictionary in m.imgs:
		imgs.append(row.img)
		if row.img == "Sound.wz/Skill.img":
			sounds.append_array(PackedStringArray(row.paths))
	for img in ["Skill.wz/400.img", "Skill.wz/420.img", "Skill.wz/421.img", "Skill.wz/422.img"]:
		assert_eq(imgs.count(img), 1, "%s once" % img)
	for id: String in SOUND_IDS:
		assert_true(id in sounds, "Sound.wz/Skill.img/%s selected" % id)
	# 4121004 (Night Lord's, the target of 4221004/Use) and the thief fragment's four ids are listed once, by their owners.
	for id in ["4121004", "4001003", "4001334", "4201004", "4201005"]:
		assert_eq(sounds.count(id), 1, "%s listed exactly once" % id)
	assert_eq(sounds.size(), _unique(sounds).size(), "no Sound.wz/Skill.img path appears twice")
	var ids := []
	for id: Variant in m.character:
		ids.append(int(id))
	assert_eq(ids.count(1332005), 1, "the Razor, the Shadower's creation dagger, listed once")


func test_real_cache_ids_names_books_and_level_counts() -> void:
	if not _cache():
		return
	var lib := AssetLibrary.get_default()
	for id: String in NAMES:
		assert_eq(lib.find("String.wz/Skill.img/%s/name" % id), NAMES[id], "name of %s" % id)
		assert_false(_book(lib, id).is_empty(), "%s in book %s" % [id, BOOKS[id]])
		assert_eq(_levels(lib, id).size(), LEVEL_COUNTS[id], "%s level count" % id)
		assert_true(WzImg.is_canvas(_art(lib, id, "icon")) or id == "4220005" or WzImg.is_canvas(_art(lib, id, "iconDisabled")), "%s icon" % id)
	for id: String in ACTIONS:
		var action: Variant = _art(lib, id, "action/0")
		assert_eq(action, ACTIONS[id], "%s action" % id)
	# Steal's action is a plain string, Band of Thieves and Meso Explosion's neighbours have none of the dagger-skill stances.
	assert_eq(_art(lib, "4201004", "action"), "swingO2")
	assert_eq(_art(lib, "4211004", "action"), null, "Band of Thieves names no action")
	assert_eq(_art(lib, "4221001", "effect/action"), "assassination", "Assassinate's effect names the stance too")
	assert_eq(int(_art(lib, "4221001", "invisible")), 1)
	assert_eq(int(_art(lib, "4221004", "invisible")), 1)
	assert_eq(int(_art(lib, "4221006", "invisible")), 1)
	assert_eq(int(_art(lib, "4221004", "req/4220002")), 5, "Ninja Ambush needs Shadow Shifter 5 (ignored)")
	assert_eq(int(_art(lib, "4001003", "req/4001002")), 3, "Dark Sight needs Disorder 3 (ignored)")
	assert_eq(int(_art(lib, "4221007", "masterLevel")), 10, "Boomerang Step's stray masterLevel")
	for id in ["4001334", "4201005", "4211002", "4211004", "4221001", "4221007"]:
		assert_eq(int(_art(lib, id, "weapon")), 33, "%s needs a dagger (weapon 33)" % id)
	for id in ["4201004", "4211006", "4221004", "4221006", "4001003"]:
		assert_eq(_art(lib, id, "weapon"), null, "%s names no weapon" % id)
	assert_eq(_art(lib, "4221001", "hit"), null, "Assassinate has no hit node")
	assert_eq(_art(lib, "4211002", "effect"), null, "Assaulter has no effect")


func test_real_cache_no_hole_and_no_unexpected_drop_in_the_fields_the_tickets_read() -> void:
	if not _cache():
		return
	var lib := AssetLibrary.get_default()
	for id: String in FIELDS:
		var levels := _levels(lib, id)
		for lv: String in levels:
			for f: String in FIELDS[id]:
				assert_true((levels[lv] as Dictionary).has(f), "%s level %s has %s" % [id, lv, f])
		for f: String in FIELDS[id]:
			var prev := -INF
			var drops := []
			for lv in range(1, levels.size() + 1):
				var v: Variant = levels[str(lv)][f]
				if v is Dictionary:
					continue
				if float(v) < prev:
					drops.append(lv)
				prev = float(v)
			assert_eq(drops, DROPS.get("%s/%s" % [id, f], []), "%s %s drops" % [id, f])
	# The per-line damage drops where the lines step up, and the totals never do.
	for pair in [["4201005", "attackCount"], ["4211004", "x"]]:
		var levels := _levels(lib, pair[0])
		var prev := 0.0
		for lv in range(1, 31):
			var total := float(levels[str(lv)].damage) * float(levels[str(lv)][pair[1]])
			assert_true(total >= prev, "%s lines x damage never decreases (level %d)" % [pair[0], lv])
			prev = total
	# mpCon is the one other non-monotone field (never read).
	assert_true(_levels(lib, "4221001")["30"].mpCon < _levels(lib, "4221001")["26"].mpCon)


func test_real_cache_the_numbers_the_spec_quotes_at_the_eight_mapped_ranks() -> void:
	if not _cache():
		return
	var lib := AssetLibrary.get_default()
	assert_eq(_at(lib, "4001003", "speed", LEVELS_20), [-26.0, -22.0, -16.0, -12.0, -7.0, -5.0, -2.0, 0.0])
	assert_eq([_levels(lib, "4001003")["1"].time, _levels(lib, "4001003")["20"].time], [10.0, 200.0])
	assert_eq(_at(lib, "4001334", "damage", LEVELS_20), [102.0, 106.0, 112.0, 116.0, 122.0, 126.0, 132.0, 140.0])
	assert_eq(_at(lib, "4001334", "attackCount", LEVELS_20), [2.0, 2.0, 2.0, 2.0, 2.0, 2.0, 2.0, 2.0])
	assert_eq(_at(lib, "4201004", "damage", LEVELS_30), [48.0, 56.0, 64.0, 70.0, 78.0, 86.0, 94.0, 100.0])
	assert_eq(_at(lib, "4201004", "prop", LEVELS_30), [14.0, 18.0, 22.0, 25.0, 29.0, 33.0, 37.0, 40.0])
	assert_eq(_at(lib, "4201005", "damage", LEVELS_30), [52.0, 68.0, 62.0, 68.0, 76.0, 73.0, 77.0, 80.0])
	assert_eq(_at(lib, "4201005", "attackCount", LEVELS_30), [4.0, 4.0, 5.0, 5.0, 5.0, 6.0, 6.0, 6.0])
	assert_eq(_at(lib, "4211002", "damage", LEVELS_30), [240.0, 280.0, 320.0, 350.0, 390.0, 415.0, 435.0, 450.0])
	assert_eq(_at(lib, "4211002", "prop", LEVELS_30), [28.0, 36.0, 44.0, 50.0, 58.0, 66.0, 74.0, 80.0])
	assert_eq(_at(lib, "4211002", "time", LEVELS_30), [2.0, 2.0, 3.0, 3.0, 3.0, 4.0, 4.0, 4.0])
	assert_eq(_at(lib, "4211002", "mobCount", LEVELS_30), [1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0])
	assert_eq(_box(lib, "4211002", [4, 30]), [[Vector2(-200, -120), Vector2(0, 0)], [Vector2(-200, -120), Vector2(0, 0)]])
	assert_eq(_at(lib, "4211004", "damage", LEVELS_30), [140.0, 130.0, 170.0, 150.0, 140.0, 180.0, 180.0, 210.0])
	assert_eq(_at(lib, "4211004", "x", LEVELS_30), [1.0, 2.0, 2.0, 3.0, 4.0, 4.0, 5.0, 5.0])
	assert_eq(_at(lib, "4211004", "mobCount", LEVELS_30), [2.0, 3.0, 3.0, 4.0, 5.0, 5.0, 6.0, 6.0])
	assert_eq(_box(lib, "4211004", [4, 15, 30]), [[Vector2(-130, -50), Vector2(130, 50)], [Vector2(-140, -50), Vector2(140, 50)],
		[Vector2(-150, -50), Vector2(150, 50)]])
	# Meso Explosion has no damage: x is the String's "Mastery" and attackCount its "Explode up to".
	assert_false(_levels(lib, "4211006")["4"].has("damage"), "Meso Explosion has no damage field")
	assert_eq(_at(lib, "4211006", "x", LEVELS_30), [560.0, 640.0, 720.0, 780.0, 860.0, 930.0, 970.0, 1000.0])
	assert_eq([_levels(lib, "4211006")["1"].x, _levels(lib, "4211006")["30"].x], [500.0, 1000.0])
	assert_eq(_at(lib, "4211006", "attackCount", LEVELS_30), [10.0, 12.0, 14.0, 14.0, 16.0, 18.0, 20.0, 20.0])
	assert_eq(_at(lib, "4211006", "mobCount", LEVELS_30), [6.0, 6.0, 6.0, 6.0, 6.0, 6.0, 6.0, 6.0])
	assert_eq(_box(lib, "4211006", [4, 15, 30]), [[Vector2(-200, -100), Vector2(0, 50)], [Vector2(-250, -110), Vector2(0, 50)],
		[Vector2(-300, -120), Vector2(0, 50)]])
	assert_true(str(lib.find("String.wz/Skill.img/4211006/h30")).contains("Mastery 100%, Explode upto 20"))
	# Assassinate: three lines against the String's "4 times"; damage = 5 x the String's percent.
	assert_eq(_at(lib, "4221001", "damage", LEVELS_30), [230.0, 310.0, 380.0, 425.0, 485.0, 530.0, 570.0, 600.0])
	assert_eq(_at(lib, "4221001", "attackCount", LEVELS_30), [3.0, 3.0, 3.0, 3.0, 3.0, 3.0, 3.0, 3.0])
	assert_eq(_at(lib, "4221001", "prop", LEVELS_30), [38.0, 46.0, 54.0, 60.0, 68.0, 76.0, 84.0, 90.0])
	assert_eq(_at(lib, "4221001", "criticalDamage", LEVELS_30), [120.0, 140.0, 160.0, 175.0, 195.0, 215.0, 235.0, 250.0])
	assert_eq(_at(lib, "4221001", "time", LEVELS_30), [6.0, 6.0, 9.0, 9.0, 9.0, 12.0, 12.0, 12.0])
	assert_eq(_box(lib, "4221001", [4, 30]), [[Vector2(-100, -120), Vector2(-10, 0)], [Vector2(-100, -120), Vector2(-10, 0)]])
	for lv in [1, 4, 15, 30]:
		assert_true(str(lib.find("String.wz/Skill.img/4221001/h%d" % lv)).contains("Attack %d%%" % (int(_levels(lib, "4221001")[str(lv)].damage) / 5)))
	assert_true(str(lib.find("String.wz/Skill.img/4221001/desc")).contains("4 times"))
	# Smokescreen: a constant cooltime 600, time 31 -> 60, a box that grows (the y edges differ by one pixel at some levels).
	assert_eq(_at(lib, "4221006", "cooltime", LEVELS_30), [600.0, 600.0, 600.0, 600.0, 600.0, 600.0, 600.0, 600.0])
	assert_eq(_at(lib, "4221006", "time", LEVELS_30), [34.0, 38.0, 42.0, 45.0, 49.0, 53.0, 57.0, 60.0])
	assert_eq(_box(lib, "4221006", [4, 15, 30]), [[Vector2(-120, -90), Vector2(120, 90)], [Vector2(-150, -112), Vector2(150, 113)],
		[Vector2(-200, -150), Vector2(200, 150)]])
	# Boomerang Step.
	assert_eq(_at(lib, "4221007", "damage", LEVELS_30), [290.0, 330.0, 370.0, 400.0, 440.0, 465.0, 485.0, 500.0])
	assert_eq(_at(lib, "4221007", "mobCount", LEVELS_30), [2.0, 2.0, 3.0, 3.0, 3.0, 4.0, 4.0, 4.0])
	assert_eq(_at(lib, "4221007", "prop", LEVELS_30), [38.0, 46.0, 54.0, 60.0, 68.0, 76.0, 84.0, 90.0])
	assert_eq(_at(lib, "4221007", "time", LEVELS_30), [2.0, 2.0, 3.0, 3.0, 3.0, 4.0, 4.0, 4.0])
	assert_eq(_box(lib, "4221007", [4, 30]), [[Vector2(-300, -110), Vector2(0, 0)], [Vector2(-300, -110), Vector2(0, 0)]])
	# Ninja Ambush's box at the rank levels.
	assert_eq(_box(lib, "4221004", [4, 15, 30]), [[Vector2(-120, -130), Vector2(120, 70)], [Vector2(-150, -130), Vector2(150, 70)],
		[Vector2(-200, -130), Vector2(200, 70)]])


func test_real_cache_ninja_ambush_and_venomous_stab_equal_night_lords_at_every_level() -> void:
	if not _cache() or not require_cache_img("Skill.wz/412.img"):
		return
	var lib := AssetLibrary.get_default()
	var night_lord: Dictionary = lib.img("Skill.wz/412.img").root["skill"]
	for pair in [["4221004", "4121004"], ["4220005", "4120005"]]:
		var mine := _levels(lib, pair[0])
		var theirs: Dictionary = (night_lord[pair[1]] as Dictionary)["level"]
		assert_eq(mine.size(), theirs.size())
		for lv: String in mine:
			assert_eq(mine[lv], theirs[lv], "%s level %s equals %s" % [pair[0], lv, pair[1]])


func test_real_cache_art_node_frame_counts_the_tickets_draw() -> void:
	if not _cache():
		return
	var lib := AssetLibrary.get_default()
	# Dark Sight: effect 4 (no delay values). Double Stab: hit/0 and hit/1 three frames; CharLevel/10..25/hit/0 five.
	assert_eq(_n(lib, "4001003", "effect"), 4)
	assert_eq([_n(lib, "4001334", "hit/0"), _n(lib, "4001334", "hit/1")], [3, 3])
	for lv in [10, 15, 20, 25]:
		assert_eq(_n(lib, "4001334", "CharLevel/%d/hit/0" % lv), 5)
	# Steal: effect 4 (100-130 ms), effect0 5 behind the avatar (z -1). Savage Blow: effect 8, hit/0..2 one frame each.
	assert_eq([_n(lib, "4201004", "effect"), _n(lib, "4201004", "effect0")], [4, 5])
	assert_eq(int(_art(lib, "4201004", "effect0/z")), -1)
	assert_eq(_n(lib, "4201005", "effect"), 8)
	for i in 3:
		assert_true(WzImg.is_canvas(_art(lib, "4201005", "hit/%d/0" % i)), "Savage Blow hit/%d/0 is one canvas" % i)
	# Assaulter: hit/0 four frames, mob three (pos 2, repeat 1), no effect.
	assert_eq([_n(lib, "4211002", "hit/0"), _n(lib, "4211002", "mob")], [4, 3])
	assert_eq([int(_art(lib, "4211002", "mob/pos")), int(_art(lib, "4211002", "mob/repeat"))], [2, 1])
	# Band of Thieves: effect 5; hit/0 three frames, hit/1..5 seven frames with hitAfter 240 / 240 / 240 / 360 / 240.
	assert_eq(_n(lib, "4211004", "effect"), 5)
	assert_eq(_n(lib, "4211004", "hit/0"), 3)
	assert_eq(_art(lib, "4211004", "hit/0/hitAfter"), null)
	var after := [240, 240, 240, 360, 240]
	for i in 5:
		assert_eq(_n(lib, "4211004", "hit/%d" % (i + 1)), 7, "hit/%d frames" % (i + 1))
		assert_eq(int(_art(lib, "4211004", "hit/%d/hitAfter" % (i + 1))), after[i], "hit/%d hitAfter" % (i + 1))
	assert_eq(_art(lib, "4211004", "hit/6"), null, "six hit nodes in all")
	assert_true(_art(lib, "4211004", "afterimage/swordOS/stabO1") is Dictionary)
	# Meso Explosion: effect 13 (75 ms), nine hit nodes of four frames.
	assert_eq(_n(lib, "4211006", "effect"), 13)
	for i in 9:
		assert_eq(_n(lib, "4211006", "hit/%d" % i), 4, "Meso Explosion hit/%d" % i)
	assert_eq(_art(lib, "4211006", "hit/9"), null, "nine hit nodes in all")
	# Boomerang Step: effect 15, hit/0 and hit/1 five frames (pos 1), mob 3 (pos 2, repeat 1).
	assert_eq([_n(lib, "4221007", "effect"), _n(lib, "4221007", "hit/0"), _n(lib, "4221007", "hit/1"), _n(lib, "4221007", "mob")],
		[15, 5, 5, 3])
	assert_eq([int(_art(lib, "4221007", "hit/0/pos")), int(_art(lib, "4221007", "mob/pos"))], [1, 2])
	# Ninja Ambush: effect 19 (90 ms), mob one 4x4, mob0 13 frames (pos 2, repeat 1, fixed 1).
	assert_eq([_n(lib, "4221004", "effect"), _n(lib, "4221004", "mob"), _n(lib, "4221004", "mob0")], [19, 1, 13])
	assert_eq([int(_art(lib, "4221004", "mob0/pos")), int(_art(lib, "4221004", "mob0/repeat")), int(_art(lib, "4221004", "mob0/fixed"))],
		[2, 1, 1])
	# Assassinate: effect 25 (frames 10 and 15 are 4x4 holds of 160 ms), special 10 frames of 60 ms.
	assert_eq([_n(lib, "4221001", "effect"), _n(lib, "4221001", "special")], [25, 10])
	assert_eq([int(_art(lib, "4221001", "effect/10/delay")), int(_art(lib, "4221001", "effect/15/delay"))], [160, 160])
	# Smokescreen: effect 11 (frame 0 a 1x1 held 360 ms); tile is eleven puff variants of TWO frames each (alpha 64 -> 128).
	assert_eq(_n(lib, "4221006", "effect"), 11)
	assert_eq(int(_art(lib, "4221006", "effect/0/delay")), 360)
	for i in 11:
		assert_eq(_n(lib, "4221006", "tile/%d" % i), 2, "Smokescreen tile/%d" % i)
	assert_eq(_art(lib, "4221006", "tile/11"), null, "eleven tile nodes in all")
	assert_eq([int(_art(lib, "4221006", "tile/0/0/a0")), int(_art(lib, "4221006", "tile/0/0/a1"))], [64, 128])


func test_real_cache_the_sounds_resolve_including_the_three_uols() -> void:
	if not _cache():
		return
	var lib := AssetLibrary.get_default()
	for id: String in SOUND_IDS:
		assert_true(lib.sound("Sound.wz/Skill.img/%s/Use" % id) != null, "%s Use" % id)
	for id in ["4211006", "4221007"]:
		assert_true(lib.sound("Sound.wz/Skill.img/%s/Hit" % id) != null, "%s Hit" % id)
	assert_true(lib.sound("Sound.wz/Skill.img/4121001/Use2") != null)
	# 4221001/Use and Use2 and 4221004/Use are exported under their UOL targets' files and play.
	assert_eq(String(lib.find("Sound.wz/Skill.img/4221001/Use")["$sound"]), "Sound.wz/Skill.img/4121001/Use.mp3")
	assert_eq(String(lib.find("Sound.wz/Skill.img/4221001/Use2")["$sound"]), "Sound.wz/Skill.img/4121001/Use2.mp3")
	assert_eq(String(lib.find("Sound.wz/Skill.img/4221004/Use")["$sound"]), "Sound.wz/Skill.img/4121004/Use.mp3")
	for pair in [["4221001/Use", "4121001/Use"], ["4221001/Use2", "4121001/Use2"], ["4221004/Use", "4121004/Use"]]:
		assert_eq(lib.sound("Sound.wz/Skill.img/" + pair[0]).get_length(), lib.sound("Sound.wz/Skill.img/" + pair[1]).get_length(), "%s is the same file" % pair[0])
	assert_eq(lib.missing.size(), 0, "no asset miss recorded: %s" % str(lib.missing))


func _avatar(weapon: int, shield: bool) -> AvatarRenderer:
	var a := AvatarRenderer.new()
	a.library = AssetLibrary.get_default()
	var equips := [1040002, 1060002, 1072001, weapon]
	if shield:
		equips.append(SHIELD)
	a.set_look({"equips": equips})
	return a


## One letter per frame: Y when a part owned by `owner` is drawn.
func _drawn(a: AvatarRenderer, owner: int, action: String) -> String:
	var flags := ""
	for fi in a.stance_delays(action).size():
		var drawn := false
		for p: Dictionary in a.compose(action, fi):
			if int(p.get("owner", 0)) == owner:
				drawn = true
		flags += "Y" if drawn else "n"
	return flags


func test_real_cache_the_dagger_and_the_thief_shield_are_drawn_in_every_shadower_stance() -> void:
	if not _cache() or not require_cache_img("Character.wz/Shield/01092018.img"):
		return
	for weapon: int in DAGGERS:
		if not require_cache_img("Character.wz/Weapon/%08d.img" % weapon):
			continue
		var a := _avatar(weapon, true)
		for action in DAGGER_ACTIONS:
			assert_true(a.has_stance(action), "the body has %s" % action)
			for owner in [weapon, SHIELD]:
				var flags := _drawn(a, owner, action)
				assert_true(flags != "" and not flags.contains("n"), "%d drawn in every frame of %s (%s)" % [owner, action, flags])
		# Two-handed, ranged and resting stances lose the dagger (no Shadower skill uses one).
		for action in DAGGERLESS_ACTIONS:
			assert_false(_drawn(a, weapon, action).contains("Y"), "dagger %d is not drawn in %s" % [weapon, action])
		a.free()
	# The six skill stances are links to ordinary stances (frame by frame), so the dagger's own images carry them.
	var body := AssetLibrary.get_default().img("Character.wz/00002000.img")
	assert_eq([SpriteAnim.frame_keys(body.root["assaulter"]).size(), SpriteAnim.frame_keys(body.root["assassination"]).size(),
		SpriteAnim.frame_keys(body.root["savage"]).size(), SpriteAnim.frame_keys(body.root["smokeshell"]).size(),
		SpriteAnim.frame_keys(body.root["alert5"]).size(), SpriteAnim.frame_keys(body.root["prone2"]).size(),
		SpriteAnim.frame_keys(body.root["darksight"]).size()], [2, 11, 8, 7, 3, 2, 1])
	assert_eq(body.root["assaulter"]["0"]["action"], "swingO1")


func test_real_cache_the_razor_is_a_wearable_dagger() -> void:
	if not _cache():
		return
	var lib := AssetLibrary.get_default()
	var info: Dictionary = lib.img("Character.wz/Weapon/01332005.img").root["info"]
	assert_eq([int(info.reqJob), int(info.reqLevel), int(info.incPAD)], [0, 5, 20])
	assert_eq(lib.find("String.wz/Eqp.img/Eqp/Weapon/1332005/name"), "Razor")
