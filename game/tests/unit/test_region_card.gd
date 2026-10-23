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
		["The Tree That Grew I → Stumpy", "The Forest of Wisdom → King Slime", "The Forest of Evil I → Dyle"],
		["West Street Corner of Perion → Mano", "East Rocky Mountain V → Stumpy", "The Burnt Land I → Iron Hook"],
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


## Spec #253: tier 1 lists Henesys, Ellinia, Perion and Kerning City in that order; four cards is the most the
## parchment fits above the Start button, and every shipped tier stays within it.
func test_tier_one_shows_four_cards_and_four_is_the_layout_maximum() -> void:
	var data := DataRepo.load_all()
	var cards := SELECT.load_stages(data, 0)
	assert_eq(cards.map(func(c: Dictionary) -> String: return String(c.key)),
		["henesys", "ellinia", "perion", "kerning"])
	assert_eq(cards.map(func(c: Dictionary) -> String: return String(c.region)),
		["Henesys", "Ellinia", "Perion", "Kerning City"])
	for tier: Array in data.stages.tiers:
		assert_true(tier.size() <= SELECT.MAX_CARDS, "%s fits the map select" % [tier])
	var select: Node2D = SELECT.new()
	var start_top := ParchmentScroll.PARCHMENT.end.y - 50.0
	assert_true(select._entry_rect(SELECT.MAX_CARDS - 1).end.y <= start_top, "the last card ends above Start")
	assert_true(select._entry_rect(SELECT.MAX_CARDS).end.y > start_top, "one more card would overlap Start")
	select.free()
