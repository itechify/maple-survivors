extends TestCase
## Region cards use String.wz names and preserve the region's map/boss order (#247).

const SELECT := preload("res://scenes/ui/stage_select.gd")


func test_region_cards_list_three_maps_with_their_bosses_from_the_cache() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.get_default()
	var data := DataRepo.load_all()
	for key: String in data.stages.stages:
		for entry: Dictionary in DataRepo.stage_maps(data, key):
			if lib.img(AssetLibrary.map_img_path(int(entry.map_id))) == null:
				skip("region map absent from cache: %d" % int(entry.map_id))
				return
	var expected := [
		["Henesys Hunting Ground I → Mano", "The Pig Beach → Mushmom", "The Blue Mushroom Forest → Blue Mushmom"],
		["The Tree That Grew I → Prime Minister", "The Forest of Wisdom → Grey Yeti and King Pepe", "The Forest of Evil I → Faust"],
		["West Street Corner of Perion → King Clang", "East Rocky Mountain V → Stumpy", "The Burnt Land I → Iron Hook"],
		["Kerning City Construction Site → King Slime", "Line 1 <Area 1> → Shade", "The Swamp of Despair I → Dyle"],
		["Dark Cave → Zombie Mushmom", "Drake Area → Snack Bar", "The Cursed Sanctuary → Jr. Balrog"],
	]
	var cards := SELECT.load_stages(data)
	assert_eq(cards.size(), 5)
	for i in cards.size():
		assert_eq(cards[i].get("map_rows", []), expected[i], String(cards[i].key))
		assert_eq(cards[i].objective, "Defeat 3 bosses across 3 maps")
		assert_false(str(cards[i]).to_lower().contains("canonical"), "no developer terminology on the card")
		var mark: Variant = lib.find(AssetLibrary.map_img_path(int(cards[i].map_id)) + "/info/mapMark")
		assert_eq(cards[i].mark, mark, "region uses its first map's mark")


## Spec #253: the first four regions are Henesys, Ellinia, Perion and Kerning City in that order; four cards is the most the
## parchment fits above the Start button (more scroll, #286).
func test_the_first_four_regions_fill_the_four_card_layout() -> void:
	var data := DataRepo.load_all()
	var cards := SELECT.load_stages(data, data.stages.progression.slice(0, 4))
	assert_eq(cards.map(func(c: Dictionary) -> String: return String(c.key)),
		["henesys", "ellinia", "perion", "kerning"])
	assert_eq(cards.map(func(c: Dictionary) -> String: return String(c.region)),
		["Henesys", "Ellinia", "Perion", "Kerning City"])
	var select: Node2D = SELECT.new()
	var start_top := ParchmentScroll.PARCHMENT.end.y - 50.0
	assert_true(select._entry_rect(SELECT.MAX_CARDS - 1).end.y <= start_top, "the last card ends above Start")
	assert_true(select._entry_rect(SELECT.MAX_CARDS).end.y > start_top, "one more card would overlap Start")
	select.free()


## ADR 0007 (#450): map select lists the progression in order and marks each region locked, cleared or open.
func test_load_progression_orders_the_regions_and_marks_locked_and_cleared() -> void:
	var data := DataRepo.load_all()
	var order: Array = data.stages.progression
	var fresh := SELECT.load_progression(data, [])
	assert_eq(fresh.map(func(c: Dictionary) -> String: return String(c.key)), order)
	assert_eq(fresh.map(func(c: Dictionary) -> int: return int(c.step)), [0, 1, 2, 3, 4])
	assert_eq(fresh.map(func(c: Dictionary) -> bool: return bool(c.locked)), [false, true, true, true, true],
		"a new character has only Henesys open")
	assert_eq(fresh.map(func(c: Dictionary) -> bool: return bool(c.cleared)), [false, false, false, false, false])
	assert_eq(fresh[0].previous, "", "the first region needs nothing")
	assert_eq(fresh[1].previous, "Henesys")
	assert_eq(SELECT.locked_text(fresh[1].previous), "Locked. Clear Henesys to unlock.")
	var after := SELECT.load_progression(data, ["henesys"])
	assert_eq(after.map(func(c: Dictionary) -> bool: return bool(c.locked)), [false, false, true, true, true],
		"a clear of step k unlocks step k+1 and nothing else")
	assert_eq(after.map(func(c: Dictionary) -> bool: return bool(c.cleared)), [true, false, false, false, false])
	var tier_two := SELECT.load_progression(data, ["henesys", "ellinia", "perion", "kerning"])
	assert_eq(tier_two.map(func(c: Dictionary) -> bool: return bool(c.locked)), [false, false, false, false, false])
	assert_eq(tier_two[4].previous, "", "an open region needs no hint")
