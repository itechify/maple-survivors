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
	var expected := {
		"henesys": ["Henesys Hunting Ground I → Mano", "The Pig Beach → Mushmom", "The Blue Mushroom Forest → Blue Mushmom"],
		"ellinia": ["The Tree That Grew I → Stumpy", "The Forest of Wisdom → King Slime", "The Forest of Evil I → Dyle"],
		"perion": ["West Street Corner of Perion → Mano", "East Rocky Mountain V → Stumpy", "The Burnt Land I → Iron Hook"],
		"kerning": ["Kerning City Construction Site → King Slime", "Line 1 <Area 1> → Shade", "The Swamp of Despair I → Dyle"],
		"nautilus": ["Pirate Training Center → Mano", "The Forest East of Henesys → Mushmom", "Pirate Test Room → King Clang"],
		"sleepywood": ["Dark Cave → Zombie Mushmom", "Drake Area → Snack Bar", "The Cursed Sanctuary → Jr. Balrog"],
	}
	var cards := SELECT.load_stages(data)
	assert_eq(cards.size(), data.stages.stages.size())
	for i in cards.size():
		if expected.has(cards[i].key):
			assert_eq(cards[i].get("map_rows", []), expected[cards[i].key], String(cards[i].key))
		assert_eq(cards[i].objective, "Defeat 3 bosses across 3 maps")
		assert_false(str(cards[i]).to_lower().contains("canonical"), "no developer terminology on the card")
		var mark: Variant = lib.find(AssetLibrary.map_img_path(int(cards[i].map_id)) + "/info/mapMark")
		assert_eq(cards[i].mark, mark, "region uses its first map's mark")


## Spec #264: a synthetic fifth region must fit without editing the shipped stage roster.
func test_five_region_cards_fit_in_order_without_overlapping_start() -> void:
	var data := _synthetic_tier(5)
	var cards := SELECT.load_stages(data, 0)
	assert_eq(cards.map(func(c: Dictionary) -> String: return String(c.key)),
		["henesys", "ellinia", "perion", "kerning", "synthetic_4"])
	var screen: Node2D = SELECT.new()
	Engine.get_main_loop().root.get_child(-1).add_child(screen)
	var paper := Rect2(40, 148, 432, 286)
	var start := Rect2(screen.start_button.position, screen.start_button.size)
	assert_true(start.position.x >= SELECT.DETAIL_X, "Start is under the detail column")
	for i in cards.size():
		var row: Rect2 = screen._entry_rect(i)
		assert_true(paper.encloses(row), "card %d stays on the paper" % i)
		assert_false(start.intersects(row), "card %d does not overlap Start" % i)
		assert_true(row.size.y >= 44, "map marks retain their space")
		if i > 0:
			assert_false(row.intersects(screen._entry_rect(i - 1)), "cards do not overlap")
	screen.free()


## Verifies six cards fit and shipped tiers never overflow.
func test_six_cards_fit_and_shipped_tiers_never_overflow() -> void:
	assert_eq(SELECT.MAX_CARDS, 6, "six regions fit without scrolling")
	var screen: Node2D = SELECT.new()
	Engine.get_main_loop().root.get_child(-1).add_child(screen)
	var paper: Rect2 = screen.CARD_AREA
	assert_true(paper.encloses(screen._entry_rect(5)), "sixth row stays on paper")
	assert_false(paper.encloses(screen._entry_rect(6)), "seventh row exceeds capacity")
	assert_eq(SELECT.load_stages(_synthetic_tier(6), 0).size(), 6)
	for tier: Array in DataRepo.load_all().stages.tiers:
		assert_true(tier.size() <= SELECT.MAX_CARDS, "%s exceeds map-select capacity" % [tier])
	screen.free()


## Verifies keyboard and mouse reach every region and confirm starts selection.
func test_keyboard_and_mouse_reach_every_region_and_confirm_starts_selection() -> void:
	var screen: Node2D = SELECT.new()
	Engine.get_main_loop().root.get_child(-1).add_child(screen)
	screen.stages = SELECT.load_stages(_synthetic_tier(5), 0)
	screen.scroll.unroll(true)
	var started: Array[String] = []
	# Observe the public button signal without starting a real saved round.
	screen.flow = null
	screen.start_button.pressed.connect(func() -> void: started.append(screen.stages[screen.selected].key))
	for i in 5:
		assert_eq(screen.selected, i, "Down selects card %d" % i)
		var enter := InputEventKey.new()
		enter.keycode = KEY_ENTER
		enter.pressed = true
		screen._unhandled_input(enter)
		var down := InputEventKey.new()
		down.keycode = KEY_DOWN
		down.pressed = true
		screen._unhandled_input(down)
	assert_eq(started, ["henesys", "ellinia", "perion", "kerning", "synthetic_4"])
	for i in range(4, -1, -1):
		var click := InputEventMouseButton.new()
		click.position = screen._entry_rect(i).get_center()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		screen.scroll.gui_input.emit(click)
		assert_eq(screen.selected, i, "mouse selects card %d" % i)
	var up := InputEventKey.new()
	up.keycode = KEY_UP
	up.pressed = true
	screen.select(4)
	screen._unhandled_input(up)
	assert_eq(screen.selected, 3, "Up selects previous card")
	screen.free()


func _synthetic_tier(count: int) -> Dictionary:
	var data := DataRepo.load_all().duplicate(true)
	data.stages.tiers[0] = ["henesys", "ellinia", "perion", "kerning"]
	for i in range(4, count):
		var key := "synthetic_%d" % i
		data.stages.stages[key] = data.stages.stages.henesys.duplicate(true)
		data.stages.stages[key].region = "Synthetic %d" % i
		data.stages.tiers[0].append(key)
	return data
