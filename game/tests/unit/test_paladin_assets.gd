extends TestCase
## Paladin assets (spec #308, P1 #309): the paladin.json manifest fragment, and against the real v83 cache the skill ids,
## String.wz names, level tables, art nodes and Sound.wz nodes (with their UOLs) the Paladin tickets read. The cache tests
## SKIP without it; the manifest test needs none.

const SOUND_IDS := ["1211002", "1211003", "1211004", "1211005", "1211006", "1211007", "1211008", "1221001", "1221003",
	"1221004", "1221007", "1221009", "1221011"]
## {id: String.wz name, verbatim}. Names are tier A (String.wz/Skill.img).
const NAMES := {"1211002": "Charged Blow", "1211003": "Fire Charge: Sword", "1211004": "Flame Charge: BW",
	"1211005": "Ice Charge: Sword", "1211006": "Blizzard Charge: BW", "1211007": "Thunder Charge: Sword",
	"1211008": "Lightning Charge: BW", "1221001": "Monster Magnet", "1221003": "Holy Charge : Sword",
	"1221004": "Divine Charge : BW", "1221007": "Rush", "1221009": "Blast", "1221011": "Heaven's Hammer"}
## The eight mapped levels of a 30-level skill and of the 20-level Holy Charge (rank r -> ceil(r x maxLevel / 8) with rank 1 = 4).
const LEVELS_30 := [4, 8, 12, 15, 19, 23, 27, 30]
const LEVELS_20 := [3, 5, 8, 10, 13, 15, 18, 20]
const TWINS := {"1211003": "1211004", "1211005": "1211006", "1211007": "1211008", "1221003": "1221004"}
## The art index of Charged Blow's and Blast's element nodes: 0 none, 1 ice, 2 fire, 3 lightning, 5 holy (4 = poison, no art).
const ART_KEYS := ["0", "1", "2", "3", "5"]


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


func test_the_paladin_fragment_names_both_books_and_the_thirteen_sounds() -> void:
	var m := AssetManifest.load_merged("res://data/asset_manifest.json")
	assert_false(m.is_empty())
	var imgs := PackedStringArray()
	var sounds := PackedStringArray()
	for row: Dictionary in m.imgs:
		imgs.append(row.img)
		if row.img == "Sound.wz/Skill.img":
			sounds.append_array(PackedStringArray(row.paths))
	for img in ["Skill.wz/120.img", "Skill.wz/121.img", "Skill.wz/122.img", "Skill.wz/112.img"]:
		assert_true(img in imgs, "%s selected" % img)
	for id: String in SOUND_IDS:
		assert_true(id in sounds, "Sound.wz/Skill.img/%s selected" % id)
	# The UOL targets outside this fragment: Hero's Monster Magnet and Rush Use sounds.
	assert_true("1121001" in sounds and "1121006" in sounds, "Hero's Use sounds, the targets of 1221001 and 1221007")


func test_real_cache_ids_names_and_max_levels() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.get_default()
	for id: String in NAMES:
		assert_eq(lib.find("String.wz/Skill.img/%s/name" % id), NAMES[id], "name of %s" % id)
		var book := _book(lib, id)
		assert_false(book.is_empty(), "%s in its book" % id)
		var want := 20 if id in ["1221003", "1221004"] else 30
		assert_eq(_levels(lib, id).size(), want, "%s max level" % id)
	assert_eq(_book(lib, "1221009").get("masterLevel"), 10, "Blast masterLevel")
	assert_eq(_book(lib, "1221011").get("elemAttr"), "h", "Heaven's Hammer is holy")
	for id in ["1211003", "1211004", "1211005", "1211006", "1211007", "1211008", "1221003", "1221004"]:
		assert_eq((_book(lib, id).action as Dictionary)["0"], "alert4", "%s action" % id)
	assert_eq((_book(lib, "1221009").action as Dictionary)["0"], "blast")
	assert_eq((_book(lib, "1221011").action as Dictionary)["0"], "sanctuary")
	assert_eq((_book(lib, "1221007").action as Dictionary)["0"], "rush2")
	assert_false(_book(lib, "1221001").has("action"), "Magnet names no action, only prepare/action dash")
	assert_false(_book(lib, "1211002").has("action"), "Charged Blow names no action")


func test_real_cache_the_fields_the_tickets_read_exist_at_every_mapped_level() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.get_default()
	var fields := {"1221009": ["damage"], "1221001": ["prop", "range", "mobCount"],
		"1211002": ["damage", "prop", "time", "range", "mobCount", "hpCon"], "1221011": ["damage", "lt", "rb", "mobCount"],
		"1221007": ["damage", "mobCount", "lt", "rb"]}
	for id in ["1211003", "1211004", "1211005", "1211006", "1211007", "1211008", "1221003", "1221004"]:
		fields[id] = ["damage", "time"]
	for id: String in fields:
		var levels := _levels(lib, id)
		for lv: int in (LEVELS_20 if id in ["1221003", "1221004"] else LEVELS_30):
			for f: String in fields[id]:
				assert_true((levels.get(str(lv), {}) as Dictionary).has(f), "%s level %d has %s" % [id, lv, f])


func test_real_cache_level_numbers_the_spec_quotes() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.get_default()
	var blast := _levels(lib, "1221009")
	assert_eq([int(blast["1"].damage), int(blast["30"].damage)], [170, 550])
	var blow := _levels(lib, "1211002")
	for pair: Array in [["1", 162, 32, 2, 130, 15], ["30", 250, 90, 4, 150, 25]]:
		var l: Dictionary = blow[pair[0]]
		assert_eq([int(l.damage), int(l.prop), int(l.time), int(l.range), int(l.hpCon), int(l.mobCount)],
			[pair[1], pair[2], pair[3], pair[4], pair[5], 6], "Charged Blow level %s" % pair[0])
	var magnet := _levels(lib, "1221001")
	assert_eq([int(magnet["1"].range), int(magnet["30"].range), int(magnet["30"].prop)], [200, 400, 95])
	var hammer := _levels(lib, "1221011")
	assert_eq([int(hammer["1"].damage), int(hammer["30"].damage), int(hammer["30"].mobCount)], [420, 900, 15])
	assert_eq(WzImg.vec(hammer["30"].lt), Vector2(-400, -350))
	assert_eq(WzImg.vec(hammer["30"].rb), Vector2(400, 250))
	assert_eq([int(hammer["1"].cooltime), int(hammer["30"].cooltime)], [310, 20], "session-scale cooltime, not read")
	# The Charges' damage multiplier at level 1 and at the top level (the spec's 102 -> 120 / 100 -> 110 / 102 -> 125 / 102 -> 140).
	for row: Array in [["1211003", 102, 120], ["1211005", 100, 110], ["1211007", 102, 125], ["1221003", 102, 140]]:
		var levels := _levels(lib, row[0])
		assert_eq([int(levels["1"].damage), int(levels[str(levels.size())].damage)], [row[1], row[2]], row[0])


func test_real_cache_twins_and_rush_match_their_references() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.get_default()
	for sword: String in TWINS:
		assert_eq(_levels(lib, sword), _levels(lib, TWINS[sword]), "%s and %s share every level row" % [sword, TWINS[sword]])
	assert_eq(_levels(lib, "1221007"), _levels(lib, "1121006"), "Paladin Rush numbers equal Hero's Rush at every level")
	assert_eq(_levels(lib, "1221001"), _levels(lib, "1121001"), "Paladin Monster Magnet numbers equal Hero's")


func test_real_cache_element_art_index_and_frame_counts() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.get_default()
	var blow := _book(lib, "1211002")
	var blast := _book(lib, "1221009")
	# Charged Blow has no key 0; Blast has all five. Key 4 (poison) is absent everywhere.
	for k in ["1", "2", "3", "5"]:
		assert_true((blow.effect as Dictionary).has(k) and (blow.hit["0"] as Dictionary).has(k), "Charged Blow art %s" % k)
	assert_false((blow.effect as Dictionary).has("0") or (blow.effect as Dictionary).has("4"))
	for k in ART_KEYS:
		assert_eq(_frames(blast.effect[k]).size(), 14, "Blast effect/%s frames" % k)
		assert_eq(_frames(blast.hit["0"][k]).size(), 3, "Blast hit/0/%s frames" % k)
	assert_false((blast.effect as Dictionary).has("4"))
	for pair: Array in [["1", 6], ["2", 6], ["3", 6], ["5", 13]]:
		assert_eq(_frames(blow.effect[pair[0]]).size(), pair[1], "Charged Blow effect/%s frames" % pair[0])
	for pair: Array in [["1", 4], ["2", 4], ["3", 4], ["5", 8]]:
		assert_eq(_frames(blow.hit["0"][pair[0]]).size(), pair[1], "Charged Blow hit/0/%s frames" % pair[0])
	assert_eq(_frames(blow.mob).size(), 3, "stun stars")


func test_real_cache_heavens_hammer_slam_frame_and_charge_effect_frames() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.get_default()
	var effect: Dictionary = _book(lib, "1221011").effect
	assert_eq(_frames(effect).size(), 22)
	var t := 0.0
	for i in 13:
		assert_eq(int(effect[str(i)].delay), 120)
		t += 0.12
	assert_near(t, 1.56, 0.0001, "frame 13 starts at 1.56 s")
	# The `sanctuary` body stance: its thrust (stabOF frame 2) also starts at 1.56 s and the stance lasts 3.3 s.
	var body: Dictionary = lib.img("Character.wz/00002000.img").root["sanctuary"]
	var start_ms := 0
	var starts := []
	for i in 7:
		starts.append(start_ms)
		start_ms += absi(int(body[str(i)].delay))
	assert_eq(starts, [0, 1080, 1560, 1680, 2400, 2760, 3120])
	assert_eq(start_ms, 3300)
	for pair: Array in [["1211003", 15], ["1211004", 15], ["1211005", 15], ["1211006", 15], ["1211007", 15],
			["1211008", 15], ["1221003", 17], ["1221004", 17]]:
		assert_eq(_frames(_book(lib, pair[0]).effect).size(), pair[1], "%s effect frames" % pair[0])


func test_real_cache_every_paladin_sound_resolves_including_the_uol_targets() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.get_default()
	for id: String in SOUND_IDS:
		var path := "Sound.wz/Skill.img/%s/Use" % id
		assert_true(lib.sound(path) != null, path)
	for use in ["Use2", "Use3", "Use4", "Use5"]:
		assert_true(lib.sound("Sound.wz/Skill.img/1221009/%s" % use) != null, "Blast %s" % use)
	assert_true(lib.sound("Sound.wz/Skill.img/1221011/Hit") != null, "Heaven's Hammer Hit")
	# The UOL nodes resolve to the sibling's stream: the sword twin, Hero's Magnet and Hero's Rush.
	for pair: Array in [["1211004", "1211003"], ["1211006", "1211005"], ["1211008", "1211007"], ["1221004", "1221003"],
			["1221001", "1121001"], ["1221007", "1121006"]]:
		var node: Dictionary = lib.find("Sound.wz/Skill.img/%s/Use" % pair[0])
		assert_eq(String(node["$sound"]), "Sound.wz/Skill.img/%s/Use.mp3" % pair[1], "%s is a UOL to %s" % pair)
	assert_eq(lib.missing.size(), 0, "no asset miss recorded: %s" % str(lib.missing))
