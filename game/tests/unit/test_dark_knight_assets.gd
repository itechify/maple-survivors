extends TestCase
## Dark Knight assets (spec #348, D1 #349): the dark_knight.json manifest fragment, and against the real v83 cache the skill
## ids, String.wz names, level tables, art nodes and Sound.wz nodes (with their UOLs) the Dark Knight tickets read. The cache
## tests SKIP without it; the manifest test needs none.

const SOUND_IDS := ["1311001", "1311002", "1311003", "1311004", "1311005", "1311006", "1321001", "1321003", "1321007"]
## {id: String.wz name, verbatim}. Names are tier A (String.wz/Skill.img).
const NAMES := {"1311001": "Spear Crusher", "1311002": "Pole Arm Crusher", "1311003": "Dragon Fury: Spear",
	"1311004": "Dragon Fury: Pole Arm", "1311005": "Sacrifice", "1311006": "Dragon Roar", "1321001": "Monster Magnet",
	"1321003": "Rush", "1321007": "Beholder", "1320008": "Aura of the Beholder", "1320009": "Hex of the Beholder",
	"1320006": "Berserk"}
## The eight mapped levels: 30-level skills (rank r -> ceil(r x 30 / 8), rank 1 = 4), Spear Crusher's explicit table (DK-7),
## the 10-level Beholder and the 25-level Aura and Hex.
const LEVELS_30 := [4, 8, 12, 15, 19, 23, 27, 30]
const LEVELS_CRUSHER := [4, 8, 12, 15, 23, 25, 27, 30]
const LEVELS_10 := [2, 3, 4, 5, 7, 8, 9, 10]
const LEVELS_25 := [4, 7, 10, 13, 16, 19, 22, 25]


func _book(lib: AssetLibrary, id: String) -> Dictionary:
	var img := lib.img("Skill.wz/%s.img" % id.substr(0, 3))
	return img.root["skill"][id] if img != null else {}


func _levels(lib: AssetLibrary, id: String) -> Dictionary:
	return _book(lib, id).get("level", {})


func _frames(node: Variant) -> Array:
	var keys := []
	if node is Dictionary:
		for k: Variant in (node as Dictionary).keys():
			if str(k).is_valid_int() and WzImg.is_canvas(node[k]):
				keys.append(int(str(k)))
	keys.sort()
	return keys


func _row(lib: AssetLibrary, id: String, level: int) -> Dictionary:
	return _levels(lib, id).get(str(level), {})


func test_the_dark_knight_fragment_names_both_books_and_the_nine_sounds() -> void:
	var m := AssetManifest.load_merged("res://data/asset_manifest.json")
	assert_false(m.is_empty())
	var imgs := PackedStringArray()
	var sounds := PackedStringArray()
	for row: Dictionary in m.imgs:
		imgs.append(row.img)
		if row.img == "Sound.wz/Skill.img":
			sounds.append_array(PackedStringArray(row.paths))
	for img in ["Skill.wz/130.img", "Skill.wz/131.img", "Skill.wz/132.img", "Skill.wz/112.img"]:
		assert_true(img in imgs, "%s selected" % img)
	for id: String in SOUND_IDS:
		assert_true(id in sounds, "Sound.wz/Skill.img/%s selected" % id)
	# The UOL targets outside this fragment: Hero's Monster Magnet and Rush Use sounds.
	assert_true("1121001" in sounds and "1121006" in sounds, "Hero's Use sounds, the targets of 1321001 and 1321003")
	# Aura and Hex have no Sound nodes: nothing is invented for them.
	assert_false("1320008" in sounds or "1320009" in sounds)


func test_real_cache_ids_names_and_max_levels() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.get_default()
	for id: String in NAMES:
		assert_eq(lib.find("String.wz/Skill.img/%s/name" % id), NAMES[id], "name of %s" % id)
		var want := 30
		if id == "1321007":
			want = 10
		elif id in ["1320008", "1320009"]:
			want = 25
		assert_eq(_levels(lib, id).size(), want, "%s max level" % id)
	assert_eq(_book(lib, "1321001").get("masterLevel"), 10, "Magnet masterLevel")
	assert_eq(_book(lib, "1321007").get("masterLevel"), 10, "Beholder masterLevel")
	for id in ["1311003", "1311004"]:
		assert_eq((_book(lib, id).action as Dictionary), {"0": "swingP1", "1": "swingP2"}, "%s actions" % id)
	assert_eq((_book(lib, "1311006").action as Dictionary)["0"], "alert3")
	assert_eq((_book(lib, "1321007").action as Dictionary)["0"], "alert2")
	assert_eq((_book(lib, "1321003").action as Dictionary)["0"], "rush")
	assert_false(_book(lib, "1311001").has("action"), "Spear Crusher's action is per level")
	assert_false(_book(lib, "1311005").has("action"), "Sacrifice names no action")
	assert_false(_book(lib, "1321001").has("action"), "Magnet names no action, only prepare/action dash")
	assert_eq(_book(lib, "1321003").get("invisible"), 1)
	assert_eq(int(_book(lib, "1320008").req["1321007"]), 1, "Aura needs the Beholder")
	assert_eq(int(_book(lib, "1320009").req["1321007"]), 1, "Hex needs the Beholder")
	assert_eq(int(_book(lib, "1311006").req["1311005"]), 3, "Roar needs Sacrifice level 3")


func test_real_cache_the_fields_the_tickets_read_exist_at_every_mapped_level() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.get_default()
	var plan := [
		["1311001", ["damage", "attackCount", "mobCount", "action", "lt", "rb"], LEVELS_CRUSHER],
		["1311002", ["damage", "attackCount", "mobCount", "action", "lt", "rb"], LEVELS_CRUSHER],
		["1311003", ["damage", "mobCount", "hpCon"], LEVELS_30], ["1311004", ["damage", "mobCount", "hpCon"], LEVELS_30],
		["1311005", ["damage", "x"], LEVELS_30], ["1311006", ["damage", "x", "y", "lt", "rb", "mobCount"], LEVELS_30],
		["1321001", ["prop", "range", "mobCount"], LEVELS_30], ["1321003", ["damage", "mobCount", "lt", "rb"], LEVELS_30],
		["1321007", ["time"], LEVELS_10], ["1320008", ["hp", "x"], LEVELS_25],
		["1320009", ["time", "x", "pdd"], LEVELS_25], ["1320006", ["x", "damage"], LEVELS_30]]
	for p: Array in plan:
		for lv: int in p[2]:
			for f: String in p[1]:
				assert_true(_row(lib, p[0], lv).has(f), "%s level %d has %s" % [p[0], lv, f])
	# No hole anywhere: every level of every skill carries the same field set (Hex adds a stat at each unlock level).
	for id in ["1311001", "1311003", "1311005", "1311006", "1321001", "1321003", "1321007", "1320006", "1320008"]:
		var sets := {}
		for lv: Variant in _levels(lib, id).keys():
			var keys: Array = (_levels(lib, id)[lv] as Dictionary).keys()
			keys.sort()
			sets[str(keys)] = true
		assert_eq(sets.size(), 1, "%s has one field set at every level" % id)
	# Hex: each stat's first level (the unlock levels the spec's DK-5 reads).
	for pair: Array in [["pdd", 1], ["mdd", 6], ["acc", 11], ["eva", 16], ["pad", 21]]:
		var first := 0
		for lv in range(1, 26):
			if _row(lib, "1320009", lv).has(pair[0]):
				first = lv
				break
		assert_eq(first, pair[1], "Hex %s unlocks at level %d" % pair)
	assert_false(_row(lib, "1320009", 4).has("mdd"), "rank 1 Hex (level 4) has only pdd")


func test_real_cache_level_numbers_the_spec_quotes() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.get_default()
	# Spear Crusher at the mapped levels: damage, hits, targets and stance (DK-7's 140 ... 1530 totals).
	var crusher := {}
	var totals := []
	for lv: int in LEVELS_CRUSHER:
		var l := _row(lib, "1311001", lv)
		crusher[lv] = [int(l.damage), int(l.attackCount), int(l.mobCount), String(l.action)]
		totals.append(int(l.damage) * int(l.attackCount) * int(l.mobCount))
	assert_eq(totals, [140, 360, 648, 720, 894, 930, 1449, 1530])
	assert_eq(crusher[4], [70, 2, 1, "burster1"])
	assert_eq(crusher[15], [120, 2, 3, "burster1"])
	assert_eq(crusher[23], [149, 3, 2, "burster2"])
	assert_eq(crusher[30], [170, 3, 3, "burster2"])
	assert_eq([int(_row(lib, "1311001", 15).mobCount), int(_row(lib, "1311001", 16).mobCount)], [3, 1], "mobCount falls back at 16")
	assert_eq(WzImg.vec(_row(lib, "1311001", 4).lt), Vector2(-130, -50))
	assert_eq(WzImg.vec(_row(lib, "1311001", 30).lt), Vector2(-150, -70))
	assert_eq(WzImg.vec(_row(lib, "1311001", 30).rb), Vector2(-16, 0))
	# Dragon Fury: damage 80 -> 250, 6 targets, HP cost 20 -> 30, no box of its own.
	assert_eq([int(_row(lib, "1311003", 1).damage), int(_row(lib, "1311003", 30).damage)], [80, 250])
	assert_eq([int(_row(lib, "1311003", 1).hpCon), int(_row(lib, "1311003", 30).hpCon)], [20, 30])
	assert_false(_row(lib, "1311003", 4).has("lt"), "Dragon Fury's reach is the afterimage box")
	# Sacrifice: damage 205 -> 350, x 20 -> 5 (% of the damage dealt).
	assert_eq([int(_row(lib, "1311005", 1).damage), int(_row(lib, "1311005", 30).damage)], [205, 350])
	assert_eq([int(_row(lib, "1311005", 1).x), int(_row(lib, "1311005", 30).x)], [20, 5])
	assert_eq(LEVELS_30.map(func(lv: int) -> int: return int(_row(lib, "1311005", lv).x)), [18, 16, 14, 13, 11, 9, 7, 5])
	# Dragon Roar: x = HP cost % of max HP (59 -> 30), y = stun seconds (4 -> 2), 15 targets, the box grows to 800 x 600.
	assert_eq([int(_row(lib, "1311006", 1).x), int(_row(lib, "1311006", 30).x)], [59, 30])
	assert_eq([int(_row(lib, "1311006", 1).y), int(_row(lib, "1311006", 30).y)], [4, 2])
	assert_eq([int(_row(lib, "1311006", 1).damage), int(_row(lib, "1311006", 30).damage)], [96, 240])
	assert_eq(WzImg.vec(_row(lib, "1311006", 1).lt), Vector2(-110, -132))
	assert_eq(WzImg.vec(_row(lib, "1311006", 30).lt), Vector2(-400, -350))
	assert_eq(WzImg.vec(_row(lib, "1311006", 30).rb), Vector2(400, 250))
	assert_eq(LEVELS_30.map(func(lv: int) -> int: return int(_row(lib, "1311006", lv).mobCount)), [15, 15, 15, 15, 15, 15, 15, 15])
	# Monster Magnet: pull 200 -> 400 px, success 42 -> 95 %, 6 monsters.
	assert_eq(LEVELS_30.map(func(lv: int) -> int: return int(_row(lib, "1321001", lv).prop)), [48, 56, 64, 70, 78, 86, 92, 95])
	assert_eq(LEVELS_30.map(func(lv: int) -> int: return int(_row(lib, "1321001", lv).range)), [200, 200, 300, 300, 300, 400, 400, 400])
	# Rush: 78 -> 130 %, 15 monsters, reach 170 -> 250 px at the mapped levels.
	assert_eq(LEVELS_30.map(func(lv: int) -> int: return int(_row(lib, "1321003", lv).damage)), [78, 86, 94, 100, 108, 116, 124, 130])
	assert_eq(LEVELS_30.map(func(lv: int) -> int: return int(WzImg.vec(_row(lib, "1321003", lv).lt).x)),
		[-170, -180, -190, -200, -220, -230, -240, -250])
	# Beholder: WZ time is session-scale (660 -> 1200 s), not read.
	assert_eq(LEVELS_10.map(func(lv: int) -> int: return int(_row(lib, "1321007", lv).time)), [720, 780, 840, 900, 1020, 1080, 1140, 1200])
	# Aura: flat HP 85 -> 500 every x seconds 10 -> 4.
	assert_eq(LEVELS_25.map(func(lv: int) -> int: return int(_row(lib, "1320008", lv).hp)), [85, 170, 200, 280, 360, 390, 470, 500])
	assert_eq(LEVELS_25.map(func(lv: int) -> int: return int(_row(lib, "1320008", lv).x)), [10, 9, 8, 7, 7, 6, 5, 4])
	# Hex at the top level: every stat, time 99 (a hole in the monotone run: levels 21-24 say 100).
	var hex := _row(lib, "1320009", 25)
	assert_eq([int(hex.time), int(hex.x), int(hex.pdd), int(hex.mdd), int(hex.acc), int(hex.eva), int(hex.pad)], [99, 4, 100, 100, 25, 50, 15])
	assert_eq(int(_row(lib, "1320009", 24).time), 100)
	assert_eq(int(_row(lib, "1320009", 1).x), 48, "Hex level 1 node says 48 (the String text says 58 s)")
	# Berserk: threshold x 21 -> 50, damage 32 -> 100 (the String text says 113 % at level 1).
	assert_eq([int(_row(lib, "1320006", 1).x), int(_row(lib, "1320006", 30).x)], [21, 50])
	assert_eq([int(_row(lib, "1320006", 1).damage), int(_row(lib, "1320006", 30).damage)], [32, 100])


func test_real_cache_twins_and_rush_and_magnet_match_their_references() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.get_default()
	assert_eq(_levels(lib, "1311001"), _levels(lib, "1311002"), "Spear and Pole Arm Crusher share every level row")
	assert_eq(_levels(lib, "1311003"), _levels(lib, "1311004"), "Dragon Fury twins share every level row")
	assert_eq(_levels(lib, "1321003"), _levels(lib, "1121006"), "Dark Knight Rush numbers equal Hero's at every level")
	assert_eq(_levels(lib, "1321001"), _levels(lib, "1121001"), "Dark Knight Monster Magnet numbers equal Hero's")
	var hero_rush: Dictionary = (lib.img("Skill.wz/112.img").root["skill"]["1121006"] as Dictionary)
	assert_eq((hero_rush.action as Dictionary)["0"], "rush2", "Hero's Rush body action")
	assert_eq((_book(lib, "1321003").action as Dictionary)["0"], "rush", "Dark Knight's Rush body action differs")


func test_real_cache_art_nodes_and_frame_counts() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.get_default()
	for id in ["1311001", "1311002"]:
		var b := _book(lib, id)
		assert_eq(_frames(b.effect).size(), 2, "%s effect (the wings)" % id)
		assert_eq(_frames(b.effect0).size(), 3, "%s effect0 (the rings, frame 0 blank)" % id)
		for k in ["effect1", "effect2", "effect3"]:
			assert_eq(_frames(b[k]).size(), 3, "%s %s (blank wait, blur, dragon head)" % [id, k])
		assert_eq([int(b.effect1["0"].delay), int(b.effect2["0"].delay), int(b.effect3["0"].delay)], [600, 750, 900],
			"the k-th dragon thrust waits for the k-th body thrust")
		assert_eq(_frames(b.hit["0"]).size(), 4, "%s hit/0" % id)
	for id in ["1311003", "1311004"]:
		var b := _book(lib, id)
		assert_eq(_frames(b.effect).size(), 1)
		assert_eq(_frames(b.effect0).size(), 2, "effect0: blank then the 161 x 139 ring")
		assert_eq(_frames(b.hit["0"]).size(), 8)
	var spear: Dictionary = _book(lib, "1311003").afterimage["spear"]
	var pole: Dictionary = _book(lib, "1311004").afterimage["poleArm"]
	for src: Dictionary in [spear, pole]:
		assert_eq(WzImg.vec(src["swingP1"].lt), Vector2(-241, -81))
		assert_eq(WzImg.vec(src["swingP1"].rb), Vector2(-16, 31))
		assert_eq(WzImg.vec(src["swingP2"].lt), Vector2(-225, -81))
		assert_eq(WzImg.vec(src["swingP2"].rb), Vector2(-1, 31))
	assert_eq(_frames(_book(lib, "1311005").effect).size(), 2, "Sacrifice effect")
	assert_false(_book(lib, "1311005").has("hit"), "Sacrifice has no hit art")
	assert_eq(_frames(_book(lib, "1311006").effect).size(), 18, "Roar effect")
	assert_eq(_frames(_book(lib, "1311006").hit["0"]).size(), 3, "Roar hit/0")
	assert_eq(_frames(_book(lib, "1321001").effect).size(), 18, "Magnet effect")
	var rush := _book(lib, "1321003")
	assert_eq(_frames(rush.effect).size(), 7, "Rush effect: effect/0 is a blank 1 x 1")
	assert_eq(_frames(rush.effect0).size(), 6, "Rush dust")
	assert_false(rush.has("hit"))
	var summon: Dictionary = _book(lib, "1321007").summon
	var counts := {"summoned": 16, "stand": 16, "move": 8, "die": 8, "skill1": 24, "skill2": 16, "skill3": 16, "skill4": 16,
		"skill5": 16, "skill6": 16}
	for k: String in counts:
		assert_eq(_frames(summon[k]).size(), counts[k], "Beholder summon/%s frames" % k)
	assert_eq(_frames(_book(lib, "1321007").affected).size(), 9, "Beholder affected (on the owner)")
	assert_eq(_frames(_book(lib, "1320006").effect).size(), 13, "Berserk effect")


func test_real_cache_the_warrior_weapons_have_every_stance_the_dark_knight_casts_in() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.get_default()
	var body: Dictionary = lib.img("Character.wz/00002000.img").root
	for weapon in [1432000, 1442000]:
		var item := lib.img(AvatarRenderer.part_img_path(weapon))
		assert_true(item != null, "weapon %d imported" % weapon)
		for action in ["burster1", "burster2", "swingP1", "swingP2", "alert2", "alert3", "rush", "stabT1"]:
			var node: Dictionary = body[action]
			for k in SpriteAnim.frame_keys(node):
				var fr: Dictionary = node[k]
				var st := String(fr.get("action", action))
				var fi := str(int(fr.get("frame", int(k))))
				var stance: Variant = item.root.get(st)
				assert_true(stance is Dictionary and (stance as Dictionary).has(fi) and (stance[fi] as Dictionary).has("weapon"),
					"%d draws its weapon in %s (resolves to %s frame %s)" % [weapon, action, st, fi])


func test_real_cache_every_dark_knight_sound_resolves_including_the_uol_targets() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.get_default()
	for id: String in SOUND_IDS:
		var path := "Sound.wz/Skill.img/%s/Use" % id
		assert_true(lib.sound(path) != null, path)
	# The UOL nodes resolve to the sibling's stream: the spear versions and Hero's Magnet and Rush.
	for pair: Array in [["1311002", "1311001"], ["1311004", "1311003"], ["1321001", "1121001"], ["1321003", "1121006"]]:
		var node: Dictionary = lib.find("Sound.wz/Skill.img/%s/Use" % pair[0])
		assert_eq(String(node["$sound"]), "Sound.wz/Skill.img/%s/Use.mp3" % pair[1], "%s is a UOL to %s" % pair)
	assert_eq(lib.missing.size(), 0, "no asset miss recorded: %s" % str(lib.missing))
