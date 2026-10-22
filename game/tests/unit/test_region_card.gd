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
		["Dark Cave → Zombie Mushmom", "Drake Area → Snack Bar", "The Cursed Sanctuary → Jr. Balrog"],
	]
	var cards := SELECT.load_stages(data)
	assert_eq(cards.size(), 3)
	for i in cards.size():
		assert_eq(cards[i].get("map_rows", []), expected[i], String(cards[i].key))
		assert_eq(cards[i].objective, "Defeat 3 bosses across 3 maps")
		assert_false(str(cards[i]).to_lower().contains("canonical"), "no developer terminology on the card")
		var mark: Variant = lib.find(AssetLibrary.map_img_path(int(cards[i].map_id)) + "/info/mapMark")
		assert_eq(cards[i].mark, mark, "region uses its first map's mark")
