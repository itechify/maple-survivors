extends TestCase
## Buccaneer assets (spec #412, B1 #413): the buccaneer.json manifest fragment, and against the real v83 cache the skill ids,
## String.wz names, level tables, art nodes, Morph.wz actions and Sound.wz nodes (with the Super Transformation UOL) the
## Buccaneer tickets read. The cache tests SKIP without it; the manifest test needs none.

const SOUND_IDS := ["5110001", "5111004", "5111005", "5111006", "5121001", "5121002", "5121003", "5121004", "5121005", "5121007"]
## {id: String.wz name, verbatim}. Names are tier A (String.wz/Skill.img); "Sommersault Kick" is the v83 spelling.
const NAMES := {"5001001": "Flash Fist", "5001002": "Sommersault Kick", "5101002": "Backspin Blow", "5101003": "Double Uppercut",
	"5101004": "Corkscrew Blow", "5001005": "Dash", "5110001": "Energy Charge", "5111004": "Energy Drain",
	"5121002": "Energy Orb", "5111005": "Transformation", "5121003": "Super Transformation", "5111006": "Shockwave",
	"5121004": "Demolition", "5121005": "Snatch", "5121001": "Dragon Strike", "5121007": "Barrage"}
## Skill id -> its book (Skill.wz/<book>.img) and WZ level count.
const BOOKS := {"5001001": "500", "5001002": "500", "5001005": "500", "5101002": "510", "5101003": "510", "5101004": "510",
	"5110001": "511", "5111004": "511", "5111005": "511", "5111006": "511", "5121001": "512", "5121002": "512",
	"5121003": "512", "5121004": "512", "5121005": "512", "5121007": "512"}
const LEVEL_COUNTS := {"5001001": 20, "5001002": 20, "5001005": 10, "5101002": 20, "5101003": 20, "5101004": 20, "5111004": 20,
	"5111005": 20, "5121003": 20, "5111006": 30, "5121001": 30, "5121002": 30, "5121004": 30, "5121005": 30, "5121007": 30}
## The eight mapped levels of a 20-level and of a 30-level skill (rank r -> ceil(r x maxLevel / 8), rank 1 = 4 for 30).
const LEVELS_20 := [3, 5, 8, 10, 13, 15, 18, 20]
const LEVELS_30 := [4, 8, 12, 15, 19, 23, 27, 30]
## The fields each later ticket reads (the verification table of B1).
const FIELDS := {"5001001": ["damage", "mobCount", "lt", "rb"], "5001002": ["damage", "mobCount", "lt", "rb"],
	"5101002": ["damage", "time", "mobCount", "lt", "rb"], "5101003": ["damage", "attackCount", "time"],
	"5101004": ["damage", "mobCount", "lt", "rb"], "5001005": ["x", "y", "time"],
	"5111004": ["damage", "x", "lt", "rb", "mobCount"],
	"5111005": ["morph", "time", "str", "pdd", "mdd", "speed", "jump", "cooltime"],
	"5121003": ["morph", "time", "str", "pdd", "mdd", "speed", "jump", "cooltime"],
	"5111006": ["damage", "mobCount", "lt", "rb"], "5121001": ["damage", "mobCount", "lt", "rb"],
	"5121002": ["damage", "mobCount", "range"], "5121004": ["damage", "attackCount", "time", "lt", "rb", "mobCount"],
	"5121005": ["damage", "mobCount", "time", "lt", "rb"], "5121007": ["damage", "attackCount"]}
const ACTIONS := {"5001001": "straight", "5001002": "somersault", "5101002": "backspin", "5101003": "doubleupper",
	"5101004": "screw", "5111004": "edrain", "5111006": "shockwave", "5121001": "dragonstrike", "5121002": "eorb",
	"5121004": "demolition", "5121005": "snatch", "5121007": "fist"}
## Actions both morphs hold, and the two only Super Transformation's morph holds.
const MORPH_ACTIONS := ["stand", "walk", "jump", "prone", "ladder", "rope", "sit", "fly", "straight", "somersault", "backspin",
	"doubleupper", "screw", "eburster", "edrain", "eorb", "dragonstrike", "fist", "shockwave", "alert2", "alert3", "alert4",
	"stabO1", "stabO2"]
const SUPER_ONLY := ["demolition", "snatch"]


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


func test_the_buccaneer_fragment_names_both_books_both_morphs_and_the_ten_sounds() -> void:
	var m := AssetManifest.load_merged("res://data/asset_manifest.json")
	assert_false(m.is_empty())
	var imgs := PackedStringArray()
	var sounds := PackedStringArray()
	for row: Dictionary in m.imgs:
		imgs.append(row.img)
		if row.img == "Sound.wz/Skill.img":
			sounds.append_array(PackedStringArray(row.paths))
	for img in ["Skill.wz/500.img", "Skill.wz/510.img", "Skill.wz/511.img", "Skill.wz/512.img", "Morph.wz/1000.img",
			"Morph.wz/1001.img", "Morph.wz/1002.img"]:
		assert_true(img in imgs, "%s selected" % img)
	for id: String in SOUND_IDS:
		assert_true(id in sounds, "Sound.wz/Skill.img/%s selected" % id)
	assert_false("5111002" in sounds, "Energy Blast is not in the pool and is not imported")
	# The first and second job sounds stay in pirate.json.
	for id in ["5001001", "5001002", "5001005", "5101002", "5101003", "5101004"]:
		assert_true(id in sounds, "pirate.json's %s" % id)
	# The UOL 5121003/Use -> 5111005/Use has both ends in the list, and no path is selected twice.
	assert_eq(sounds.size(), _unique(sounds).size(), "no Sound.wz/Skill.img path appears twice")
	assert_eq(imgs.count("Skill.wz/511.img"), 1)
	assert_eq(imgs.count("Skill.wz/512.img"), 1)


func _unique(a: PackedStringArray) -> Dictionary:
	var d := {}
	for s in a:
		d[s] = true
	return d


func test_real_cache_ids_names_and_max_levels() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.get_default()
	for id: String in NAMES:
		assert_eq(lib.find("String.wz/Skill.img/%s/name" % id), NAMES[id], "name of %s" % id)
		assert_false(_book(lib, id).is_empty(), "%s in book %s" % [id, BOOKS[id]])
	for id: String in LEVEL_COUNTS:
		assert_eq(_levels(lib, id).size(), LEVEL_COUNTS[id], "%s level count" % id)
	assert_eq(lib.find("String.wz/Skill.img/5111002/name"), "Energy Blast", "Energy Blast exists in v83 (and is dropped)")
	assert_true(_book(lib, "5110001").has("level"), "Energy Charge has levels (the meter reads none)")
	for id in ["5121001", "5121002", "5121007"]:
		assert_eq(_book(lib, id).get("masterLevel"), 10, "%s masterLevel" % id)
	for id: String in ACTIONS:
		assert_eq((_book(lib, id).action as Dictionary)["0"], ACTIONS[id], "%s action" % id)
	assert_false(_book(lib, "5001005").has("action"), "Dash names no action")
	assert_false(_book(lib, "5111005").has("action"), "Transformation names no action")
	assert_false(_book(lib, "5121003").has("action"), "Super Transformation names no action")
	assert_eq(int(_book(lib, "5121003").invisible), 1)


func test_real_cache_the_fields_the_tickets_read_exist_at_every_level() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.get_default()
	for id: String in FIELDS:
		var levels := _levels(lib, id)
		# No hole anywhere (the Shout level-4 kind): every field at every level, not only the eight mapped ones.
		for lv: String in levels:
			for f: String in FIELDS[id]:
				assert_true((levels[lv] as Dictionary).has(f), "%s level %s has %s" % [id, lv, f])
	var want_30 := {"5111006": [310, 370, 430, 475, 535, 595, 655, 700], "5121001": [320, 380, 490, 535, 595, 705, 765, 810],
		"5121002": [360, 440, 530, 590, 670, 760, 840, 900], "5121004": [120, 160, 210, 240, 280, 330, 370, 400],
		"5121005": [240, 280, 370, 400, 440, 530, 570, 600], "5121007": [106, 122, 148, 160, 176, 202, 218, 230]}
	for id: String in want_30:
		var got := []
		for lv: int in LEVELS_30:
			got.append(int(_levels(lib, id)[str(lv)].damage))
		assert_eq(got, want_30[id], "%s damage at the eight mapped levels" % id)
	var want_20 := {"5001001": [168, 180, 198, 210, 228, 240, 258, 270], "5001002": [122, 130, 142, 150, 162, 170, 182, 190],
		"5101002": [104, 120, 144, 160, 184, 200, 224, 240], "5101003": [120, 140, 170, 190, 220, 240, 270, 290],
		"5101004": [165, 195, 240, 270, 315, 345, 390, 420], "5111004": [275, 285, 300, 310, 325, 335, 350, 360]}
	for id: String in want_20:
		var got := []
		for lv: int in LEVELS_20:
			got.append(int(_levels(lib, id)[str(lv)].damage))
		assert_eq(got, want_20[id], "%s damage at the eight mapped levels" % id)


func test_real_cache_the_numbers_the_spec_quotes() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.get_default()
	var drain := _levels(lib, "5111004")
	var heal := []
	var targets := []
	for lv: int in LEVELS_20:
		heal.append(int(drain[str(lv)].x))
		targets.append(int(drain[str(lv)].mobCount))
	assert_eq(heal, [12, 13, 14, 15, 17, 18, 19, 20], "Energy Drain heals x percent")
	assert_eq(targets, [1, 1, 1, 1, 1, 1, 1, 1], "Energy Drain strikes one monster")
	assert_eq(_vec(drain["8"].lt), Vector2(-200, -100), "Energy Drain box")
	var orb := _levels(lib, "5121002")
	assert_eq([int(orb["4"].mobCount), int(orb["30"].mobCount), int(orb["4"].range)], [2, 6, 200], "Energy Orb mobCount and range")
	assert_false((orb["4"] as Dictionary).has("lt"), "Energy Orb has no box")
	var dragon := _levels(lib, "5121001")
	assert_eq([_vec(dragon["4"].lt), _vec(dragon["4"].rb), int(dragon["4"].mobCount), int(dragon["30"].mobCount)],
		[Vector2(-400, -100), Vector2(25, 20), 4, 6], "Dragon Strike box and mobCount")
	var wave := _levels(lib, "5111006")
	assert_eq([_vec(wave["4"].lt), _vec(wave["4"].rb)], [Vector2(-330, -140), Vector2(0, 20)], "Shockwave box")
	var demo := _levels(lib, "5121004")
	assert_eq([int(demo["4"].attackCount), int(demo["4"].time), _vec(demo["4"].lt), _vec(demo["4"].rb)],
		[8, 1, Vector2(-300, -150), Vector2(-20, 15)], "Demolition")
	var snatch := _levels(lib, "5121005")
	assert_eq([int(snatch["4"].time), _vec(snatch["4"].lt), _vec(snatch["4"].rb), snatch["4"].has("range")],
		[1, Vector2(-300, -100), Vector2(-50, 15), false], "Snatch has a box and a stun but no range node")
	assert_eq([int(_levels(lib, "5121007")["4"].attackCount), int(_levels(lib, "5121007")["30"].attackCount)], [6, 6])
	# Flash Fist and Somersault Kick boxes, Backspin's and Corkscrew's.
	assert_eq([_vec(_levels(lib, "5001001")["3"].lt), _vec(_levels(lib, "5001001")["3"].rb)], [Vector2(-74, -30), Vector2(-20, 10)])
	assert_eq([_vec(_levels(lib, "5001002")["3"].lt), _vec(_levels(lib, "5001002")["3"].rb)], [Vector2(-81, -71), Vector2(-5, 0)])
	assert_eq([_vec(_levels(lib, "5101002")["3"].lt), _vec(_levels(lib, "5101002")["3"].rb)], [Vector2(0, -50), Vector2(140, 0)])
	var screw := []
	for lv: int in LEVELS_20:
		screw.append(int(_vec(_levels(lib, "5101004")[str(lv)].lt).x))
	assert_eq(screw, [-110, -120, -130, -140, -160, -170, -180, -200], "Corkscrew's per-level reach")
	# Dash: ten levels, x +2 a level, y +1, time doubling every second level.
	var dash := _levels(lib, "5001005")
	var xs := []
	var ts := []
	for lv in range(1, 11):
		xs.append(int(dash[str(lv)].x))
		ts.append(int(dash[str(lv)].time))
	assert_eq(xs, [12, 14, 16, 18, 20, 22, 24, 26, 28, 30])
	assert_eq(ts, [4, 4, 8, 8, 12, 12, 16, 16, 20, 20])
	assert_eq([int(dash["1"].y), int(dash["10"].y)], [1, 10])


func test_real_cache_the_two_forms_stat_package_and_the_text_versus_node_disagreement() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.get_default()
	var trans := _levels(lib, "5111005")
	var super_ := _levels(lib, "5121003")
	var pdd_t := []
	var pdd_s := []
	for lv: int in LEVELS_20:
		pdd_t.append(int(trans[str(lv)].pdd))
		pdd_s.append(int(super_[str(lv)].pdd))
		assert_eq(int(trans[str(lv)].mdd), int(trans[str(lv)].pdd), "Transformation mdd = pdd at %d" % lv)
		assert_eq(int(super_[str(lv)].mdd), int(super_[str(lv)].pdd), "Super Transformation mdd = pdd at %d" % lv)
		for l: Dictionary in [trans[str(lv)], super_[str(lv)]]:
			assert_eq([int(l.time), int(l.speed), int(l.jump)], [120, 40, 20], "WZ time, speed and jump at %d" % lv)
		assert_eq(int(trans[str(lv)].morph), 1000)
		assert_eq(int(super_[str(lv)].morph), 1001)
	assert_eq(pdd_t, [6, 10, 16, 20, 26, 30, 36, 40])
	assert_eq(pdd_s, [43, 45, 48, 50, 53, 55, 58, 60])
	# The node carries pdd/mdd, never pad/mad: the String line's "att." is a text-versus-node disagreement, and the node wins.
	assert_false((super_["8"] as Dictionary).has("pad"), "no pad on Super Transformation")
	assert_false((super_["8"] as Dictionary).has("mad"), "no mad on Super Transformation")
	assert_true(String(lib.find("String.wz/Skill.img/5121003/h1")).contains("att."), "the String line says att.")
	assert_eq(int(_book(lib, "5121003").req["5111005"]), 20, "Super Transformation needs Transformation Lv20 (not used)")


func test_real_cache_double_uppercut_stores_attack_count_and_time_as_strings() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.get_default()
	var levels := _levels(lib, "5101003")
	for lv: String in levels:
		assert_eq(typeof(levels[lv].attackCount), TYPE_STRING, "attackCount is a string at level %s" % lv)
		assert_eq(typeof(levels[lv].time), TYPE_STRING, "time is a string at level %s" % lv)
		assert_eq(levels[lv].attackCount, "2")
		assert_eq(levels[lv].time, "1")
		assert_true(typeof(levels[lv].damage) in [TYPE_INT, TYPE_FLOAT], "damage is a number")
	# SkillBook.canonical parses numeric strings, so the string-typed fields read 2 and 1.
	var img := lib.img("Skill.wz/510.img")
	var book := SkillBook.from_data({"skills": {"double_uppercut": {"skill_id": 5101003, "book": "510"}}}, {"510": img.root})
	assert_eq(book.canonical("double_uppercut", 10, "attackCount"), 2.0)
	assert_eq(book.canonical("double_uppercut", 10, "time"), 1.0)
	assert_eq(book.canonical("double_uppercut", 10, "damage"), 190.0)


func test_real_cache_art_node_frame_counts_the_spec_lists() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.get_default()
	# Dragon Strike: effect 16, hit/0..2 and tile/0..3 13 frames each, the tile spacing 200, hitAfter 840 + 120 per target.
	assert_eq(_frames(_art(lib, "5121001", "effect")).size(), 16)
	for i in 3:
		assert_eq(_frames(_art(lib, "5121001", "hit/%d" % i)).size(), 13, "Dragon Strike hit/%d" % i)
		assert_eq(int(_art(lib, "5121001", "hit/%d/hitAfter" % i)), 840 + 120 * i, "hitAfter of hit/%d" % i)
	for i in 4:
		assert_eq(_frames(_art(lib, "5121001", "tile/%d" % i)).size(), 13, "Dragon Strike tile/%d" % i)
	assert_eq(int(_art(lib, "5121001", "tile/effectDistance")), 200)
	# Barrage: effect 5; hit/0 12 (the spec said 13), hit0 9, hit1 17.
	assert_eq(_frames(_art(lib, "5121007", "effect")).size(), 5)
	assert_eq(_frames(_art(lib, "5121007", "hit/0")).size(), 12)
	assert_eq(_frames(_art(lib, "5121007", "hit0/0")).size(), 9)
	assert_eq(_frames(_art(lib, "5121007", "hit1/0")).size(), 17)
	# Demolition hit/0 is 23 frames (the spec said 24); Snatch effect 10.
	assert_eq(_frames(_art(lib, "5121004", "hit/0")).size(), 23)
	assert_eq(_frames(_art(lib, "5121005", "effect")).size(), 10)
	assert_eq(_frames(_art(lib, "5121005", "hit/0")).size(), 3)
	# Shockwave: the effect and effect0..3 are five eight-frame ripples (a blank 1x1 first), hit/0 5 frames.
	for n in ["effect", "effect0", "effect1", "effect2", "effect3"]:
		assert_eq(_frames(_art(lib, "5111006", n)).size(), 8, "Shockwave %s" % n)
	assert_eq(_frames(_art(lib, "5111006", "hit/0")).size(), 5)
	# Energy Orb: effect 13, effect0 6, hit/0 7, ball one frame.
	assert_eq([_frames(_art(lib, "5121002", "effect")).size(), _frames(_art(lib, "5121002", "effect0")).size(),
		_frames(_art(lib, "5121002", "hit/0")).size()], [13, 6, 7])
	assert_true(WzImg.is_canvas((_art(lib, "5121002", "ball") as Dictionary)["0"]), "ball is one canvas")
	# Energy Drain: effect 15, hit/0 15.
	assert_eq([_frames(_art(lib, "5111004", "effect")).size(), _frames(_art(lib, "5111004", "hit/0")).size()], [15, 15])
	# Energy Charge: affected 11 entries (a 1x1 blank, then 10), special 5, effect/0 9, effect/1 10, hit/0 4; no `state` node.
	assert_eq(_frames(_art(lib, "5110001", "affected")).size(), 11)
	assert_eq(_frames(_art(lib, "5110001", "special")).size(), 5)
	assert_eq(_frames(_art(lib, "5110001", "effect/0")).size(), 9)
	assert_eq(_frames(_art(lib, "5110001", "effect/1")).size(), 10)
	assert_eq(_frames(_art(lib, "5110001", "hit/0")).size(), 4)
	assert_eq(_art(lib, "5110001", "state"), null, "the meter has no state art: the HUD draws its own pips")
	var blank := (_art(lib, "5110001", "affected") as Dictionary)["0"] as Dictionary
	assert_eq(int(blank["$canvas"][3]) * int(blank["$canvas"][4]), 1, "affected/0 is a 1x1 blank")
	# Flash Fist and Somersault Kick keep their CharLevel variants at 10, 15, 20, 25.
	for id in ["5001001", "5001002"]:
		var cl := _art(lib, id, "CharLevel") as Dictionary
		assert_eq(cl.keys().size(), 4, "%s CharLevel variants" % id)
		for th in ["10", "15", "20", "25"]:
			assert_true(cl.has(th), "%s CharLevel/%s" % [id, th])


func test_real_cache_both_morphs_hold_the_brawler_actions() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.get_default()
	for m in [1000, 1001]:
		var img := lib.img("Morph.wz/%d.img" % m)
		assert_true(img != null, "Morph.wz/%d.img imported" % m)
		for a in MORPH_ACTIONS:
			assert_true(img.root.get(a) is Dictionary and _frames(img.root[a]).size() > 0, "morph %d has %s" % [m, a])
		for a in SUPER_ONLY:
			assert_eq(img.root.get(a) is Dictionary, m == 1001, "morph %d %s only in 1001" % [m, a])
	# Frame counts and the delays (ms) the presentation ticket aligns to the avatar's stance timing.
	var m1 := lib.img("Morph.wz/1001.img")
	assert_eq([_frames(m1.root["stand"]).size(), _frames(m1.root["fist"]).size(), _frames(m1.root["shockwave"]).size(),
		_frames(m1.root["dragonstrike"]).size(), _frames(m1.root["demolition"]).size(), _frames(m1.root["snatch"]).size(),
		_frames(m1.root["alert2"]).size(), _frames(m1.root["edrain"]).size()], [30, 25, 16, 12, 11, 11, 6, 6])
	# Each morph action plays as long as the avatar's own action, except edrain, somersault, eburster and snatch (the notes).
	assert_eq(_total_ms(m1.root["fist"]), 2430)
	assert_eq(_total_ms(m1.root["shockwave"]), 1980)
	assert_eq(_total_ms(m1.root["demolition"]), 3120)
	assert_eq(_total_ms(m1.root["dragonstrike"]), 1440)
	assert_eq(_total_ms(m1.root["alert2"]), 600)
	# The origin sits at the feet: the canvas bottom is a few pixels below it on a standing frame, never above it.
	var stand: Dictionary = m1.root["stand"]["0"]
	var below := int(stand["$canvas"][4]) - int(stand["origin"]["$v"][1])
	assert_true(below >= 0 and below <= 15, "the stand frame reaches %d px below its origin" % below)


func test_real_cache_the_buccaneer_sounds_resolve_including_the_super_transformation_uol() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.get_default()
	for id: String in SOUND_IDS:
		var path := "Sound.wz/Skill.img/%s/Use" % id
		assert_true(lib.sound(path) != null, path)
	for id in ["5111004", "5111006", "5121001", "5121002", "5121004", "5121005", "5121007"]:
		assert_true(lib.sound("Sound.wz/Skill.img/%s/Hit" % id) != null, "%s Hit" % id)
	assert_true(lib.sound("Sound.wz/Skill.img/5110001/Use2") != null, "Energy Charge Use2")
	# 5121003/Use is a UOL to ../5111005/Use: the importer exports it under the target's file name.
	var node: Dictionary = lib.find("Sound.wz/Skill.img/5121003/Use")
	assert_eq(String(node["$sound"]), "Sound.wz/Skill.img/5111005/Use.mp3", "5121003 is a UOL to 5111005")
	assert_true(lib.sound("Sound.wz/Skill.img/5121003/Use") == lib.sound("Sound.wz/Skill.img/5111005/Use") \
		or lib.sound("Sound.wz/Skill.img/5121003/Use") != null, "the UOL stream loads")
	assert_eq(lib.missing.size(), 0, "no asset miss recorded: %s" % str(lib.missing))


func _vec(v: Variant) -> Vector2:
	var a: Array = (v as Dictionary)["$v"]
	return Vector2(float(a[0]), float(a[1]))


## Sum of a stance's frame delays in ms with the game's rule (a missing or zero delay is 100 ms, the sign is a flag).
func _total_ms(stance: Dictionary) -> int:
	var t := 0
	for k in _frames(stance):
		var d: Variant = (stance[str(k)] as Dictionary).get("delay")
		var ms := absi(int(d)) if d != null else 0
		t += ms if ms > 0 else 100
	return t
