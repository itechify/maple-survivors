extends TestCase
## Corsair assets (spec #384, C1 #385): the corsair.json manifest fragment, and against the real v83 cache the skill ids,
## String.wz names, level tables, art nodes, Sound.wz nodes (with the Burst Fire UOL), the Battleship's TamingMob image
## and the gun's stances that the Corsair tickets read. The cache tests SKIP without it (a SKIP proves nothing); the
## manifest test needs none.

const SOUND_IDS := ["5210000", "5211001", "5211002", "5211004", "5211005", "5211006", "5221003", "5221004", "5221006",
	"5221007", "5221008"]
## {id: String.wz name, verbatim}. Names are tier A (String.wz/Skill.img).
const NAMES := {"5001003": "Double Shot", "5001005": "Dash", "5210000": "Burst Fire", "5201001": "Invisible Shot",
	"5201006": "Recoil Shot", "5201002": "Grenade", "5211004": "Flamethrower", "5211005": "Ice Splitter",
	"5211001": "Octopus", "5211002": "Gaviota", "5211006": "Homing Beacon", "5221003": "Aerial Strike",
	"5221004": "Rapid Fire", "5221006": "Battleship", "5221007": "Battleship Cannon", "5221008": "Battleship Torpedo",
	"5220002": "Wrath of the Octopi", "5220011": "Bullseye", "5220001": "Elemental Boost", "5200000": "Gun Mastery",
	"5201003": "Gun Booster", "5000000": "Bullet Time", "5221010": "Speed Infusion"}
## Skill id -> its book (Skill.wz/<book>.img).
const BOOKS := {"5001003": "500", "5001005": "500", "5000000": "500", "5210000": "521", "5211004": "521", "5211005": "521",
	"5211001": "521", "5211002": "521", "5211006": "521", "5201001": "520", "5201006": "520", "5201002": "520",
	"5200000": "520", "5201003": "520", "5221003": "522", "5221004": "522", "5221006": "522", "5221007": "522",
	"5221008": "522", "5220002": "522", "5220011": "522", "5220001": "522", "5221010": "522"}
## WZ level counts of the pool skills and the sub-skills.
const LEVEL_COUNTS := {"5001003": 20, "5001005": 10, "5210000": 20, "5201001": 20, "5201006": 20, "5201002": 20,
	"5211004": 30, "5211005": 30, "5211001": 30, "5211002": 30, "5211006": 30, "5221003": 30, "5221004": 30,
	"5221006": 10, "5221007": 30, "5221008": 30, "5220002": 20, "5220011": 20}
## The eight mapped levels (rank r -> ceil(r x maxLevel / 8); rank 1 = 4 for 30; the level-10 table of Battleship and Dash).
const LEVELS_20 := [3, 5, 8, 10, 13, 15, 18, 20]
const LEVELS_30 := [4, 8, 12, 15, 19, 23, 27, 30]
const LEVELS_10 := [2, 3, 4, 5, 7, 8, 9, 10]
## The fields each later ticket reads (every level must hold every one: no hole).
const FIELDS := {"5210000": ["damage", "bulletCount", "range"], "5211004": ["damage", "mobCount", "time", "lt", "rb"],
	"5211005": ["damage", "mobCount", "time", "lt", "rb"], "5211001": ["pad", "time", "cooltime"],
	"5211002": ["pad", "time", "cooltime"], "5211006": ["damage", "range"],
	"5221003": ["damage", "mobCount", "lt", "rb", "cooltime"], "5221004": ["damage", "range"],
	"5221006": ["pdd", "mdd", "x", "cooltime", "time"], "5221007": ["damage", "bulletCount", "range"],
	"5221008": ["damage", "mobCount", "lt", "rb"], "5220002": ["pad", "time", "cooltime"], "5220011": ["damage", "x"],
	"5001005": ["x", "y", "time"]}
const ACTIONS := {"5001003": "doublefire", "5210000": "triplefire", "5201006": "backstep", "5211004": "fireburner",
	"5211005": "coolingeffect", "5211001": "octopus", "5211006": "homing", "5221003": "airstrike", "5221007": "cannon",
	"5221008": "torpedo", "5220002": "octopus", "5220011": "homing"}
const SHIP := "Character.wz/TamingMob/01932000.img"
const SHIP_STANCES := ["stand1", "walk1", "jump", "prone", "cannon", "torpedo", "fireburner", "coolingeffect", "alert2"]
## Body actions the Corsair skills use, and the ones where the pistol is drawn in every frame (all but sit).
const GUN_ACTIONS := ["stand1", "walk1", "alert2", "shoot1", "doublefire", "triplefire", "backstep", "fireburner",
	"coolingeffect", "homing", "airstrike", "octopus", "cannon", "torpedo", "rapidfire", "jump", "prone"]
const GUNLESS_ACTIONS := ["sit", "swingO1", "dead"]


func _book(lib: AssetLibrary, id: String) -> Dictionary:
	var img := lib.img("Skill.wz/%s.img" % BOOKS[id])
	return img.root["skill"][id] if img != null else {}


func _levels(lib: AssetLibrary, id: String) -> Dictionary:
	return _book(lib, id).get("level", {})


## The numbered children of an animation node that are canvases (a frame count).
func _frames(node: Variant) -> Array:
	var keys := []
	if node is Dictionary:
		for k: Variant in (node as Dictionary).keys():
			if str(k).is_valid_int() and WzImg.is_canvas(node[k]):
				keys.append(int(str(k)))
	keys.sort()
	return keys


func _art(lib: AssetLibrary, id: String, path: String) -> Variant:
	var node: Variant = _book(lib, id)
	for part in path.split("/"):
		node = (node as Dictionary).get(part) if node is Dictionary else null
	return node


func _n(lib: AssetLibrary, id: String, path: String) -> int:
	return _frames(_art(lib, id, path)).size()


func _vec(v: Variant) -> Vector2:
	var a: Array = (v as Dictionary)["$v"]
	return Vector2(float(a[0]), float(a[1]))


## The cache holds the spec's images (521, 522 and the ship); an older cache SKIPs instead of failing.
func _cache() -> bool:
	return require_cache_img("Skill.wz/522.img") and require_cache_img(SHIP)


func _at(lib: AssetLibrary, id: String, field: String, levels: Array) -> Array:
	var got := []
	for lv: int in levels:
		got.append(float(_levels(lib, id)[str(lv)][field]))
	return got


func test_the_corsair_fragment_names_both_books_the_ship_and_the_eleven_sounds() -> void:
	var m := AssetManifest.load_merged("res://data/asset_manifest.json")
	assert_false(m.is_empty())
	var imgs := PackedStringArray()
	var sounds := PackedStringArray()
	for row: Dictionary in m.imgs:
		imgs.append(row.img)
		if row.img == "Sound.wz/Skill.img":
			sounds.append_array(PackedStringArray(row.paths))
	for img in ["Skill.wz/500.img", "Skill.wz/520.img", "Skill.wz/521.img", "Skill.wz/522.img", SHIP]:
		assert_true(img in imgs, "%s selected" % img)
	for id: String in SOUND_IDS:
		assert_true(id in sounds, "Sound.wz/Skill.img/%s selected" % id)
	# The Pirate fragment keeps the first and second job sounds, among them the UOL target 5001003 (Burst Fire's Hit).
	for id in ["5001003", "5001005", "5201001", "5201002", "5201006"]:
		assert_true(id in sounds, "pirate.json's %s" % id)
	assert_eq(sounds.size(), _unique(sounds).size(), "no Sound.wz/Skill.img path appears twice")
	for img in ["Skill.wz/521.img", "Skill.wz/522.img", SHIP]:
		assert_eq(imgs.count(img), 1, "%s once" % img)
	# The ship is a generic Character.wz image entry, not a TamingMob.wz one.
	assert_false(("TamingMob.wz/01932000.img") in imgs)


func _unique(a: PackedStringArray) -> Dictionary:
	var d := {}
	for s in a:
		d[s] = true
	return d


func test_real_cache_ids_names_and_max_levels() -> void:
	if not _cache():
		return
	var lib := AssetLibrary.get_default()
	for id: String in NAMES:
		assert_eq(lib.find("String.wz/Skill.img/%s/name" % id), NAMES[id], "name of %s" % id)
		assert_false(_book(lib, id).is_empty(), "%s in book %s" % [id, BOOKS[id]])
	for id: String in LEVEL_COUNTS:
		assert_eq(_levels(lib, id).size(), LEVEL_COUNTS[id], "%s level count" % id)
	for id: String in ACTIONS:
		assert_eq((_book(lib, id).action as Dictionary)["0"], ACTIONS[id], "%s action" % id)
	for id in ["5221006", "5211002", "5221004", "5001005"]:
		assert_false(_book(lib, id).has("action"), "%s names no action" % id)
	# Rapid Fire's prepare node names the body action it plays (the skill has no `action` node of its own).
	assert_eq(_art(lib, "5221004", "prepare/action"), "rapidfire")
	assert_eq(int(_art(lib, "5221004", "prepare/time")), 540)
	assert_eq(int(_book(lib, "5221006").invisible), 1)
	assert_eq(int(_art(lib, "5221007", "req/5221006")), 1, "Cannon needs the ship")
	assert_eq(int(_art(lib, "5221008", "req/5221006")), 1, "Torpedo needs the ship")
	assert_eq(int(_art(lib, "5221003", "req/5211002")), 15, "Aerial Strike needs Gaviota 15")
	assert_eq(int(_art(lib, "5210000", "req/5001003")), 20, "Burst Fire needs Double Shot 20")
	assert_eq(int(_art(lib, "5220011", "req/5211006")), 30, "Bullseye needs Homing Beacon 30")
	for id in ["5211004", "5211005", "5210000", "5221007", "5221008"]:
		assert_eq(int(_book(lib, id).get("weapon", _book(lib, id).get("weapon ", 0))), 49, "%s needs a gun (weapon 49)" % id)
	assert_eq(_book(lib, "5211004").elemAttr, "f", "Flamethrower is fire")
	assert_eq(_book(lib, "5211005").elemAttr, "i", "Ice Splitter is ice")
	for id in ["5001003", "5210000", "5211004", "5211005", "5211001", "5211002", "5211006", "5221003", "5221004", "5221006",
			"5221007", "5221008"]:
		assert_true(WzImg.is_canvas(_art(lib, id, "icon")), "%s has an icon" % id)


func test_real_cache_the_fields_the_tickets_read_exist_at_every_level() -> void:
	if not _cache():
		return
	var lib := AssetLibrary.get_default()
	for id: String in FIELDS:
		var levels := _levels(lib, id)
		# No hole anywhere (the Shout level-4 kind): every field at every level, not only the mapped ones.
		for lv: String in levels:
			for f: String in FIELDS[id]:
				assert_true((levels[lv] as Dictionary).has(f), "%s level %s has %s" % [id, lv, f])
	# Every numeric field this spec reads is monotone over all levels (Rapid Fire's and Dash's mpCon are not, and unread).
	for id: String in FIELDS:
		for f: String in FIELDS[id]:
			var prev := -INF
			var levels := _levels(lib, id)
			for lv in range(1, levels.size() + 1):
				var v: Variant = levels[str(lv)][f]
				if v is Dictionary:
					continue
				assert_true(float(v) >= prev, "%s %s never decreases (level %d)" % [id, f, lv])
				prev = float(v)
	assert_true(_levels(lib, "5221004")["4"].has("mpCon"), "Rapid Fire has an mpCon (non-monotone; never read)")


func test_real_cache_the_numbers_the_spec_quotes_at_the_eight_mapped_ranks() -> void:
	if not _cache():
		return
	var lib := AssetLibrary.get_default()
	assert_eq(_at(lib, "5210000", "damage", LEVELS_20), [125.0, 135.0, 150.0, 160.0, 175.0, 185.0, 200.0, 210.0])
	assert_eq(_at(lib, "5210000", "bulletCount", LEVELS_20), [3.0, 3.0, 3.0, 3.0, 3.0, 3.0, 3.0, 3.0])
	assert_eq(_at(lib, "5210000", "range", LEVELS_20), [350.0, 350.0, 350.0, 350.0, 350.0, 350.0, 350.0, 350.0])
	assert_eq(_at(lib, "5211006", "damage", LEVELS_30), [172.0, 204.0, 236.0, 260.0, 292.0, 324.0, 356.0, 380.0])
	assert_eq(_at(lib, "5211006", "range", LEVELS_30), [350.0, 350.0, 350.0, 350.0, 350.0, 350.0, 350.0, 350.0])
	assert_false(_levels(lib, "5211006")["4"].has("time"), "Homing Beacon has no time: the mark's length is tier C")
	assert_false(_levels(lib, "5211006")["4"].has("x"), "Homing Beacon has no x")
	assert_eq(_at(lib, "5211001", "pad", LEVELS_30), [96.0, 112.0, 128.0, 140.0, 156.0, 172.0, 188.0, 200.0])
	assert_eq(_at(lib, "5211001", "time", LEVELS_30), [10.0, 10.0, 20.0, 20.0, 20.0, 30.0, 30.0, 30.0])
	assert_eq(_at(lib, "5211001", "cooltime", LEVELS_30), [10.0, 10.0, 10.0, 10.0, 10.0, 10.0, 10.0, 10.0])
	assert_eq(_at(lib, "5211002", "pad", LEVELS_30), [242.0, 274.0, 306.0, 330.0, 362.0, 394.0, 426.0, 450.0])
	assert_eq(_at(lib, "5211002", "time", LEVELS_30), [10.0, 10.0, 20.0, 20.0, 20.0, 30.0, 30.0, 30.0])
	assert_eq(_at(lib, "5211002", "cooltime", LEVELS_30), [5.0, 5.0, 5.0, 5.0, 5.0, 5.0, 5.0, 5.0])
	assert_eq(_at(lib, "5221003", "damage", LEVELS_30), [580.0, 660.0, 790.0, 850.0, 930.0, 1060.0, 1140.0, 1200.0])
	assert_eq(_at(lib, "5221003", "mobCount", LEVELS_30), [6.0, 6.0, 6.0, 6.0, 6.0, 6.0, 6.0, 6.0])
	assert_eq([_vec(_levels(lib, "5221003")["4"].lt), _vec(_levels(lib, "5221003")["4"].rb)], [Vector2(-400, -500), Vector2(400, 100)])
	assert_eq(_at(lib, "5221004", "damage", LEVELS_30), [108.0, 116.0, 124.0, 130.0, 138.0, 156.0, 164.0, 170.0])
	assert_eq(_at(lib, "5221004", "range", LEVELS_30), [350.0, 350.0, 350.0, 350.0, 350.0, 350.0, 350.0, 350.0])
	assert_false(_levels(lib, "5221004")["4"].has("bulletCount"), "Rapid Fire has no bullet count (a held-key stream)")
	assert_false(_levels(lib, "5221004")["4"].has("mobCount"))
	# Battleship: 10 levels, pdd = mdd = 10 x level, x 1, cooltime 90, time 2,100,000.
	assert_eq(_at(lib, "5221006", "pdd", LEVELS_10), [20.0, 30.0, 40.0, 50.0, 70.0, 80.0, 90.0, 100.0])
	assert_eq(_at(lib, "5221006", "mdd", LEVELS_10), _at(lib, "5221006", "pdd", LEVELS_10))
	assert_eq(_at(lib, "5221006", "cooltime", LEVELS_10), [90.0, 90.0, 90.0, 90.0, 90.0, 90.0, 90.0, 90.0])
	assert_eq(_at(lib, "5221006", "time", LEVELS_10), [2100000.0, 2100000.0, 2100000.0, 2100000.0, 2100000.0, 2100000.0, 2100000.0, 2100000.0])
	assert_eq(_at(lib, "5221007", "damage", LEVELS_30), [220.0, 240.0, 270.0, 285.0, 305.0, 345.0, 365.0, 380.0])
	assert_eq(_at(lib, "5221007", "bulletCount", LEVELS_30), [3.0, 3.0, 4.0, 4.0, 4.0, 4.0, 4.0, 4.0])
	assert_eq(_at(lib, "5221007", "range", LEVELS_30), [400.0, 400.0, 400.0, 400.0, 400.0, 400.0, 400.0, 400.0])
	assert_eq(_at(lib, "5221008", "damage", LEVELS_30), [420.0, 460.0, 550.0, 580.0, 620.0, 710.0, 750.0, 780.0])
	assert_eq(_at(lib, "5221008", "mobCount", LEVELS_30), [4.0, 4.0, 5.0, 5.0, 5.0, 6.0, 6.0, 6.0])
	assert_eq([_vec(_levels(lib, "5221008")["4"].lt), _vec(_levels(lib, "5221008")["4"].rb)], [Vector2(-400, -80), Vector2(-10, 20)])
	# Wrath of the Octopi (20 levels) and Bullseye.
	assert_eq([int(_levels(lib, "5220002")["1"].pad), int(_levels(lib, "5220002")["20"].pad)], [210, 500])
	assert_eq([int(_levels(lib, "5220002")["1"].time), int(_levels(lib, "5220002")["20"].time)], [35, 40])
	assert_eq([int(_levels(lib, "5220011")["1"].damage), int(_levels(lib, "5220011")["20"].damage)], [390, 580])
	assert_eq([int(_levels(lib, "5220011")["1"].x), int(_levels(lib, "5220011")["20"].x)], [1, 20])
	# Dash on the level-10 table.
	assert_eq(_at(lib, "5001005", "x", LEVELS_10), [14.0, 16.0, 18.0, 20.0, 24.0, 26.0, 28.0, 30.0])
	assert_eq(_at(lib, "5001005", "y", LEVELS_10), [2.0, 3.0, 4.0, 5.0, 7.0, 8.0, 9.0, 10.0])
	assert_eq(_at(lib, "5001005", "time", LEVELS_10), [4.0, 8.0, 8.0, 12.0, 16.0, 16.0, 20.0, 20.0])


func test_real_cache_flamethrower_and_ice_splitter_store_damage_as_strings() -> void:
	if not _cache():
		return
	var lib := AssetLibrary.get_default()
	for id in ["5211004", "5211005"]:
		var levels := _levels(lib, id)
		for lv: String in levels:
			assert_eq(typeof(levels[lv].damage), TYPE_STRING, "%s damage is a string at level %s" % [id, lv])
			assert_true(String(levels[lv].damage).is_valid_int(), "%s damage parses at level %s" % [id, lv])
			assert_true(typeof(levels[lv].mobCount) in [TYPE_INT, TYPE_FLOAT], "mobCount is a number")
			assert_true(typeof(levels[lv].time) in [TYPE_INT, TYPE_FLOAT], "time is a number")
	assert_eq(_levels(lib, "5211004")["4"].damage, "82")
	assert_eq(_levels(lib, "5211004")["30"].damage, "160")
	assert_eq(_levels(lib, "5211005")["4"].damage, "78")
	assert_eq(_levels(lib, "5211005")["30"].damage, "130")
	assert_eq(_at(lib, "5211004", "time", LEVELS_30), [3.0, 3.0, 4.0, 4.0, 4.0, 5.0, 5.0, 5.0], "burn seconds")
	assert_eq(_at(lib, "5211005", "time", LEVELS_30), [1.0, 1.0, 2.0, 2.0, 2.0, 3.0, 3.0, 3.0], "freeze seconds")
	assert_eq(_at(lib, "5211004", "mobCount", LEVELS_30), [2.0, 3.0, 3.0, 4.0, 5.0, 5.0, 6.0, 6.0])
	for id in ["5211004", "5211005"]:
		assert_eq([_vec(_levels(lib, id)["4"].lt), _vec(_levels(lib, id)["4"].rb)], [Vector2(-350, -100), Vector2(0, 0)], "%s front-only box" % id)
	assert_eq(int(_levels(lib, "5211004")["4"].itemConsume), 2331000)
	assert_eq(int(_levels(lib, "5211005")["4"].itemConsume), 2331001)
	# SkillBook.canonical parses the numeric strings.
	var img := lib.img("Skill.wz/521.img")
	var book := SkillBook.from_data({"skills": {"flamethrower": {"skill_id": 5211004, "book": "521"}}}, {"521": img.root})
	assert_eq(book.canonical("flamethrower", 15, "damage"), 115.0)


func test_real_cache_art_node_frame_counts_the_tickets_draw() -> void:
	if not _cache():
		return
	var lib := AssetLibrary.get_default()
	# Burst Fire: effect 8 (first and last a 1x1), hit/0 4, ball one frame.
	assert_eq([_n(lib, "5210000", "effect"), _n(lib, "5210000", "hit/0"), _n(lib, "5210000", "ball")], [8, 4, 1])
	# Flamethrower: effect and effect_ship 15 frames (first a 1x1 held 240 ms, last a 1x1), hit/0 5.
	assert_eq([_n(lib, "5211004", "effect"), _n(lib, "5211004", "effect_ship"), _n(lib, "5211004", "hit/0")], [15, 15, 5])
	assert_eq([_n(lib, "5211005", "effect"), _n(lib, "5211005", "effect_ship"), _n(lib, "5211005", "hit/0")], [13, 13, 5])
	for id in ["5211004", "5211005"]:
		assert_eq(int((_art(lib, id, "effect/0") as Dictionary).get("delay")), 240, "%s effect holds 240 ms first" % id)
	# Octopus: summoned 12 (first a 1x1 held 630 ms), stand 8, attack1 8, die 12; attack1/info/ball 2 frames; hit/0 5.
	assert_eq([_n(lib, "5211001", "summon/summoned"), _n(lib, "5211001", "summon/stand"), _n(lib, "5211001", "summon/attack1"),
		_n(lib, "5211001", "summon/die"), _n(lib, "5211001", "summon/attack1/info/ball"), _n(lib, "5211001", "hit/0")], [12, 8, 8, 12, 2, 5])
	assert_eq(int((_art(lib, "5211001", "summon/summoned/0") as Dictionary).get("delay")), 630)
	var info := _art(lib, "5211001", "summon/attack1/info") as Dictionary
	assert_eq([int(info.attackAfter), int(info.mobCount), int(info.bulletSpeed), int((info.range as Dictionary).r)], [480, 1, 300, 300])
	assert_eq(_vec((info.range as Dictionary).sp), Vector2(-23, -18))
	assert_false((info.range as Dictionary).has("lt"), "the Octopus range is a radius")
	assert_eq(_art(lib, "5211001", "summon/move"), null, "the Octopus has no move animation")
	# Wrath of the Octopi: a second summon with attack1 and attack2 (two sprites, two sp), 15-frame summoned.
	assert_eq([_n(lib, "5220002", "summon/attack1"), _n(lib, "5220002", "summon/attack2"), _n(lib, "5220002", "summon/summoned")], [9, 9, 15])
	assert_eq(_vec((_art(lib, "5220002", "summon/attack2/info/range") as Dictionary).sp), Vector2(-22, -46))
	# Gaviota: summoned / fly / stand 5, attack1 7, die 7; attackAfter 1920; hit/0 13 (hitAfter 1080), hit/1 4.
	assert_eq([_n(lib, "5211002", "summon/summoned"), _n(lib, "5211002", "summon/fly"), _n(lib, "5211002", "summon/stand"),
		_n(lib, "5211002", "summon/attack1"), _n(lib, "5211002", "summon/die")], [5, 5, 5, 7, 7])
	var gi := _art(lib, "5211002", "summon/attack1/info") as Dictionary
	assert_eq([int(gi.attackAfter), int(gi.mobCount), int(gi.type)], [1920, 3, 1])
	assert_eq([_vec((gi.range as Dictionary).lt), _vec((gi.range as Dictionary).rb), int((gi.range as Dictionary).r)],
		[Vector2(-80, -60), Vector2(80, 60), 400])
	assert_eq([_n(lib, "5211002", "hit/0"), _n(lib, "5211002", "hit/1"), int(_art(lib, "5211002", "hit/0/hitAfter"))], [13, 4, 1080])
	# Homing Beacon (and Bullseye, the same art): ball 4, mob 5 (repeat 1, pos 2), effect 6, hit/0 5.
	for id in ["5211006", "5220011"]:
		assert_eq([_n(lib, id, "ball"), _n(lib, id, "mob"), _n(lib, id, "effect")], [4, 5, 6], "%s art" % id)
		assert_eq(int(_art(lib, id, "mob/repeat")), 1, "%s mob loops" % id)
	assert_eq(_n(lib, "5211006", "hit/0"), 5)
	# Aerial Strike: effect 10 (first a 1x1 held 720 ms), effect0 30 at 90 ms, effect1 14 (first a 1x1 held 1800 ms), hit/0 5.
	assert_eq([_n(lib, "5221003", "effect"), _n(lib, "5221003", "effect0"), _n(lib, "5221003", "effect1"), _n(lib, "5221003", "hit/0")],
		[10, 30, 14, 5])
	assert_eq([int((_art(lib, "5221003", "effect/0") as Dictionary).delay), int((_art(lib, "5221003", "effect1/0") as Dictionary).delay)], [720, 1800])
	# Rapid Fire: prepare 9 x 60 ms (z -1), keydown 8, keydown0 2 (z -1), keydownend 9, hit/0 3, afterimage a 1x1.
	assert_eq([_n(lib, "5221004", "prepare"), _n(lib, "5221004", "keydown"), _n(lib, "5221004", "keydown0"),
		_n(lib, "5221004", "keydownend"), _n(lib, "5221004", "hit/0")], [9, 8, 2, 9, 3])
	assert_eq(_n(lib, "5221004", "afterimage/gun/shot/1"), 1)
	# Battleship: effect 11, effect0 7 (first a 1x1 held 450 ms, z -1). Cannon: ball 1 (21x17), effect a 1x1, hit/0 4.
	# Torpedo: ball 6 at 30 ms, hit/0 6.
	assert_eq([_n(lib, "5221006", "effect"), _n(lib, "5221006", "effect0")], [11, 7])
	assert_eq(int((_art(lib, "5221006", "effect0/0") as Dictionary).delay), 450)
	assert_eq([_n(lib, "5221007", "ball"), _n(lib, "5221007", "hit/0")], [1, 4])
	var cannon_ball := (_art(lib, "5221007", "ball/0") as Dictionary)["$canvas"] as Array
	assert_eq([int(cannon_ball[3]), int(cannon_ball[4])], [21, 17])
	assert_eq([_n(lib, "5221008", "ball"), _n(lib, "5221008", "hit/0")], [6, 6])
	assert_eq(int((_art(lib, "5221008", "ball/0") as Dictionary).delay), 30)


func test_real_cache_the_corsair_sounds_resolve_including_the_burst_fire_uol() -> void:
	if not _cache():
		return
	var lib := AssetLibrary.get_default()
	for id: String in SOUND_IDS:
		var path := "Sound.wz/Skill.img/%s/Use" % id
		assert_true(lib.sound(path) != null, path)
	for id in ["5210000", "5211004", "5211005", "5211006", "5221003", "5221004", "5221007", "5221008"]:
		assert_true(lib.sound("Sound.wz/Skill.img/%s/Hit" % id) != null, "%s Hit" % id)
	for id in ["5211001", "5211002", "5221006"]:
		assert_eq(lib.find("Sound.wz/Skill.img/%s/Hit" % id), null, "%s has no Hit sound" % id)
	# 5210000/Hit is a UOL to ../5001003/Hit: the importer exports it under the Double Shot file, and it plays.
	var node: Dictionary = lib.find("Sound.wz/Skill.img/5210000/Hit")
	assert_eq(String(node["$sound"]), "Sound.wz/Skill.img/5001003/Hit.mp3", "Burst Fire's Hit is Double Shot's")
	assert_true(lib.sound("Sound.wz/Skill.img/5210000/Hit") != null)
	assert_eq(lib.sound("Sound.wz/Skill.img/5210000/Hit").get_length(), lib.sound("Sound.wz/Skill.img/5001003/Hit").get_length(),
		"the same file")
	# Cannon and Torpedo use one 2.3 s file for Use and Hit.
	for id in ["5221007", "5221008"]:
		assert_eq(int(lib.find("Sound.wz/Skill.img/%s/Use" % id)["$ms"]), int(lib.find("Sound.wz/Skill.img/%s/Hit" % id)["$ms"]))
	assert_eq(lib.missing.size(), 0, "no asset miss recorded: %s" % str(lib.missing))


func test_real_cache_the_ship_has_every_stance_with_two_canvases_and_a_navel() -> void:
	if not _cache():
		return
	var lib := AssetLibrary.get_default()
	var ship := lib.img(SHIP)
	assert_true(ship != null, "the ship image is in the cache")
	assert_eq(int(ship.root["info"]["tamingMob"]), 4)
	for st: String in SHIP_STANCES + ["stand2", "walk2", "fly", "tired", "alert3"]:
		var node: Variant = ship.root.get(st)
		assert_true(node is Dictionary, "stance %s" % st)
		var keys := SpriteAnim.frame_keys(node)
		assert_true(keys.size() >= 6, "%s has frames" % st)
		for k in keys:
			var frame: Dictionary = node[k]
			assert_true(WzImg.is_canvas(frame["0"]) and WzImg.is_canvas(frame["1"]), "%s/%s has two canvases" % [st, k])
			assert_eq(String(frame["0"]["z"]), "tamingMobFront", "%s/%s canvas 0 is the front" % [st, k])
			assert_eq(String(frame["1"]["z"]), "tamingMobRear", "%s/%s canvas 1 is the rear" % [st, k])
			for c in ["0", "1"]:
				assert_true(frame[c]["map"].has("navel"), "%s/%s/%s has a navel" % [st, k, c])
				assert_true(_vec(frame[c]["map"]["navel"]).y < 0.0, "%s/%s/%s navel above the feet" % [st, k, c])
	assert_eq(SpriteAnim.frame_keys(ship.root["cannon"]).size(), 6)
	assert_eq(SpriteAnim.frame_keys(ship.root["torpedo"]).size(), 12)
	assert_eq(int(ship.root["cannon"]["0"]["delay"]), 130)
	assert_eq(_vec(ship.root["stand1"]["0"]["1"]["map"]["navel"]), Vector2(6, -38), "stand1 rear navel")
	assert_eq(_vec(ship.root["stand1"]["0"]["0"]["map"]["navel"]), Vector2(6, -38), "stand1 front navel")
	# The ship's canvases are drawable through the library's frame loader.
	assert_true(lib.frame(SHIP + "/stand1/0/0") != null and lib.frame(SHIP + "/stand1/0/1") != null)
	assert_eq(lib.missing.size(), 0, "no asset miss recorded: %s" % str(lib.missing))


func test_real_cache_zmap_draws_the_ship_front_over_and_the_rear_under_every_avatar_layer() -> void:
	if not _cache():
		return
	var lib := AssetLibrary.get_default()
	var order := AvatarRenderer.zmap_order(lib)
	assert_true(order.has("tamingMobFront") and order.has("tamingMobRear"))
	# zmap lists the front-most first: a smaller index is in front.
	for z in ["body", "head", "face", "hair", "weapon", "cap", "mailChest", "pants", "shoes", "arm", "hand", "cape", "glove"]:
		assert_true(int(order["tamingMobFront"]) < int(order[z]), "the ship's front canvas is in front of %s" % z)
		assert_true(int(order["tamingMobRear"]) > int(order[z]), "the ship's rear canvas is behind %s" % z)
	assert_true(int(order["tamingMobRear"]) > int(order["backWeapon"]), "the rear is behind even the back layers")
	assert_true(int(order["tamingMobRear"]) > int(order["characterEnd"]))
	assert_true(int(order["tamingMobFront"]) < int(order["characterStart"]))


func _avatar(weapon: int) -> AvatarRenderer:
	var a := AvatarRenderer.new()
	a.library = AssetLibrary.get_default()
	a.set_look({"equips": [1040002, 1060002, 1072001, weapon]})
	return a


## True per frame: the weapon part is among the parts the avatar draws.
func _gun_drawn(a: AvatarRenderer, weapon: int, action: String) -> String:
	var flags := ""
	for fi in a.stance_delays(action).size():
		var drawn := false
		for p: Dictionary in a.compose(action, fi):
			if int(p.get("owner", 0)) == weapon:
				drawn = true
		flags += "Y" if drawn else "n"
	return flags


func test_real_cache_the_gun_is_drawn_in_every_corsair_stance_but_sit() -> void:
	if not _cache():
		return
	# A pistol (1492000, the creation weapon) and the highest gun in the cache (1492009).
	for weapon in [1492000, 1492009]:
		var a := _avatar(weapon)
		for action in GUN_ACTIONS:
			assert_true(a.has_stance(action), "the body has %s" % action)
			var flags := _gun_drawn(a, weapon, action)
			assert_true(flags != "" and not flags.contains("n"), "gun %d drawn in every frame of %s (%s)" % [weapon, action, flags])
		# The rider on the ship sits: the gun is not drawn (tier C fallback, the Battleship's C12 decision).
		for action in GUNLESS_ACTIONS:
			assert_false(_gun_drawn(a, weapon, action).contains("Y"), "gun %d is not drawn in %s" % [weapon, action])
		a.free()
	# The body holds every action the skills name, with the frame counts the sheets showed.
	var body := AssetLibrary.get_default().img("Character.wz/00002000.img")
	assert_eq(SpriteAnim.frame_keys(body.root["airstrike"]).size(), 15)
	assert_eq(SpriteAnim.frame_keys(body.root["octopus"]).size(), 9)
	for action in ["triplefire", "doublefire", "fireburner", "coolingeffect", "homing", "cannon", "torpedo", "rapidfire", "sit", "backstep"]:
		assert_true(body.root.get(action) is Dictionary, "body action %s" % action)
