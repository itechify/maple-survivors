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


## The first four regions are Henesys, Ellinia, Perion and Kerning City in that order (spec #253).
func test_the_first_four_regions_are_listed_in_order() -> void:
	var data := DataRepo.load_all()
	var cards := SELECT.load_stages(data, data.stages.progression.slice(0, 4))
	assert_eq(cards.map(func(c: Dictionary) -> String: return String(c.key)),
		["henesys", "ellinia", "perion", "kerning"])
	assert_eq(cards.map(func(c: Dictionary) -> String: return String(c.region)),
		["Henesys", "Ellinia", "Perion", "Kerning City"])


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
	assert_eq(SELECT.locked_text(fresh[1].previous), "Locked. Clear Henesys to unlock.", "without a boss name")
	var after := SELECT.load_progression(data, ["henesys"])
	assert_eq(after.map(func(c: Dictionary) -> bool: return bool(c.locked)), [false, false, true, true, true],
		"a clear of step k unlocks step k+1 and nothing else")
	assert_eq(after.map(func(c: Dictionary) -> bool: return bool(c.cleared)), [true, false, false, false, false])
	var tier_two := SELECT.load_progression(data, ["henesys", "ellinia", "perion", "kerning"])
	assert_eq(tier_two.map(func(c: Dictionary) -> bool: return bool(c.locked)), [false, false, false, false, false])
	assert_eq(tier_two[4].previous, "", "an open region needs no hint")


## A progression of `count` synthetic regions: r<i> has a curve map (keyframe pool), a life map (one excluded and one hidden
## mob) and an explicit-pool map with a final form. Levels, names and map life come from `_source`.
func _synthetic(count: int) -> Dictionary:
	var stages := {}
	var order := []
	for i in count:
		var base := 100000000 + i * 10
		order.append("r%d" % i)
		stages["r%d" % i] = {"region": "Region %d" % i, "continent": "Land", "duration": 900.0, "map_seconds": 300,
			"drop_band": [0, 10], "keyframes": [{"t": 0, "pool": {str(1000 + i): 1}}],
			"maps": [
				{"map_id": base, "pool": "curve", "boss": {"mob_id": 8000 + i * 10, "time": 300}},
				{"map_id": base + 1, "pool_from_life": true, "exclude": [3000 + i],
					"boss": {"mob_id": 8001 + i * 10, "time": 300}},
				{"map_id": base + 2, "pool": {str(2000 + i): 1},
					"boss": {"mob_id": 8002 + i * 10, "final_form": 8003 + i * 10, "time": 300}}]}
	return {"stages": {"progression": order, "stages": stages}}


## Region i: curve mob Lv 10+5i, life mob Lv 12+5i, explicit mob Lv 20+5i, plus an excluded (Lv 99), a hidden (Lv 150) and a
## boss (Lv 200) that must not count, so the range is 10+5i .. 20+5i.
func _source(count: int) -> Dictionary:
	var levels := {}
	var life := {}
	for i in count:
		levels[1000 + i] = 10 + 5 * i
		levels[4000 + i] = 12 + 5 * i
		levels[2000 + i] = 20 + 5 * i
		levels[3000 + i] = 99
		levels[5000 + i] = 150
		for boss in [8000, 8001, 8002, 8003]:
			levels[boss + i * 10] = 200
		life[100000000 + i * 10 + 1] = {"life": {
			"0": {"type": "m", "id": 4000 + i}, "1": {"type": "m", "id": 3000 + i},
			"2": {"type": "m", "id": 5000 + i, "hide": 1}, "3": {"type": "n", "id": 9999999}}}
	return {
		"mob_level": func(id: int) -> int: return int(levels.get(id, 0)),
		"mob_name": func(id: int) -> String: return "Mob %d" % id if id > 0 else "",
		"map_name": func(id: int) -> String: return "Map %d" % id,
		"map_img": func(map_id: int) -> Dictionary: return life.get(map_id, {}),
	}


func _keys(cards: Array) -> Array:
	return cards.map(func(c: Dictionary) -> String: return String(c.key))


class StubFlow extends SceneFlow:
	var started: Array[String] = []

	func start_round(stage_key: String, _p_seed: int = -1) -> void:
		started.append(stage_key)


## A StageSelect on `count` synthetic regions with the first `cleared` of them cleared, in the tree.
func _screen(count: int, cleared: int) -> Node2D:
	var flow := StubFlow.new()
	flow.save = SaveData.new(test_dir("select_save.json"))
	var screen: Node2D = SELECT.new()
	screen.data = _synthetic(count)
	screen.source = _source(count)
	screen.flow = flow
	screen.snapshot = {"name": "Tester", "character": {"job_id": 212, "cleared_regions": _synthetic(count).stages.progression.slice(0, cleared)}}
	Engine.get_main_loop().root.get_child(-1).add_child(screen)
	return screen


func _free(screen: Node2D) -> void:
	screen.flow.free()
	screen.free()


func test_rows_follow_the_progression_order_for_five_and_sixteen_regions() -> void:
	for count in [5, 16]:
		var cards := SELECT.load_progression(_synthetic(count), [], _source(count))
		assert_eq(_keys(cards), _synthetic(count).stages.progression, "%d regions" % count)
		assert_eq(cards.map(func(c: Dictionary) -> int: return int(c.step)), range(count))


func test_lock_cleared_and_frontier_marks_follow_the_cleared_set() -> void:
	var data := _synthetic(6)
	var cards := SELECT.load_progression(data, ["r0", "r1"], _source(6))
	assert_eq(cards.map(func(c: Dictionary) -> bool: return bool(c.cleared)), [true, true, false, false, false, false])
	assert_eq(cards.map(func(c: Dictionary) -> bool: return bool(c.locked)), [false, false, false, true, true, true])
	assert_eq(cards.map(func(c: Dictionary) -> bool: return bool(c.frontier)), [false, false, true, false, false, false],
		"the frontier is the first unlocked, uncleared region")
	assert_eq(SELECT.frontier_index(cards), 2)
	assert_eq(SELECT.progress_text(cards), "Regions cleared 2/6")
	var fresh := SELECT.load_progression(data, [], _source(6))
	assert_eq(fresh.map(func(c: Dictionary) -> bool: return bool(c.frontier)), [true, false, false, false, false, false])
	assert_eq(SELECT.progress_text(fresh), "Regions cleared 0/6")
	var all := SELECT.load_progression(data, data.stages.progression, _source(6))
	assert_eq(SELECT.frontier_index(all), 5, "all cleared: the last region")
	assert_false(all.any(func(c: Dictionary) -> bool: return bool(c.frontier) or bool(c.locked)), "no NEW mark, nothing locked")
	assert_eq(SELECT.progress_text(all), "Regions cleared 6/6")
	assert_eq(SELECT.frontier_index([]), -1)


func test_the_unlock_hint_names_the_previous_regions_last_boss_and_its_region() -> void:
	var cards := SELECT.load_progression(_synthetic(4), ["r0"], _source(4))
	assert_eq(cards[1].unlock_boss, "", "an open region needs no hint")
	assert_eq(cards[2].previous, "Region 1")
	assert_eq(cards[2].unlock_boss, "Mob 8013", "map 3's final form of r1, not its first boss")
	assert_eq(SELECT.locked_text(cards[2].previous, cards[2].unlock_boss),
		"Locked. Defeat Mob 8013 in Region 1 to unlock.")
	var plain := _synthetic(3)
	plain.stages.stages.r0.maps[2].boss.erase("final_form")
	var cards_plain := SELECT.load_progression(plain, [], _source(3))
	assert_eq(cards_plain[1].unlock_boss, "Mob 8002", "no final form: the map 3 boss")
	assert_eq(cards_plain[2].unlock_boss, "Mob 8013", "r1 keeps its final form")


func test_level_range_covers_every_pool_rule_and_leaves_out_bosses_and_exclusions() -> void:
	var cards := SELECT.load_stages(_synthetic(3), [], _source(3))
	for i in 3:
		assert_eq(Vector2i(cards[i].level_lo, cards[i].level_hi), Vector2i(10 + 5 * i, 20 + 5 * i), "region %d" % i)
		assert_eq(SELECT.level_text(cards[i]), "Lv %d-%d" % [10 + 5 * i, 20 + 5 * i])
	assert_eq(SELECT.level_text({"level_lo": 7, "level_hi": 7}), "Lv 7", "one level")
	var unknown := SELECT.load_stages(_synthetic(1), [], {"mob_level": func(_id: int) -> int: return 0})
	assert_eq(SELECT.level_text(unknown[0]), "", "omitted when the cache lacks the mob info")


func test_the_list_opens_on_the_frontier_and_scrolls_it_into_view() -> void:
	for case: Array in [[16, 0, 0, 0], [16, 4, 4, 2], [16, 10, 10, 8], [16, 15, 15, 10], [16, 16, 15, 10], [5, 2, 2, 0],
			[5, 5, 4, 0]]:
		var screen := _screen(case[0], case[1])
		assert_eq(screen.selected, case[2], "selected with %d cleared of %d" % [case[1], case[0]])
		assert_eq(screen.top, case[3], "top with %d cleared of %d" % [case[1], case[0]])
		assert_true(screen.selected >= screen.top and screen.selected < screen.top + SELECT.MAX_CARDS, "selection shows")
		assert_eq(screen.progress_label.text, "Regions cleared %d/%d" % [case[1], case[0]])
		_free(screen)


func test_a_locked_start_is_refused_by_keyboard_and_mouse() -> void:
	var screen := _screen(8, 2)
	var flow: StubFlow = screen.flow
	screen.scroll.unroll(true)
	assert_false(screen.start_button.disabled, "the frontier can start")
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.pressed = true
	screen._unhandled_input(enter)
	assert_eq(flow.started, ["r2"])
	screen.select(5)
	assert_true(screen.start_button.disabled, "Start is disabled on a locked region")
	screen._unhandled_input(enter)
	screen.start_button.pressed.emit()
	assert_eq(flow.started, ["r2"], "keyboard and the button start nothing")
	screen.select(0)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.double_click = true
	click.position = screen._entry_rect(4).get_center()
	screen.scroll.gui_input.emit(click)
	click.position = screen._entry_rect(4).get_center()
	screen.scroll.gui_input.emit(click)
	assert_eq(screen.selected, 4)
	assert_eq(flow.started, ["r2"], "a double click on a locked row starts nothing")
	screen.select(1)
	click.position = screen._entry_rect(1).get_center()
	screen.scroll.gui_input.emit(click)
	assert_eq(flow.started, ["r2", "r1"], "a cleared region replays by double click")
	_free(screen)


func test_six_rows_are_visible_and_none_overlaps_start() -> void:
	assert_true(SELECT.MAX_CARDS >= 6, "at least six rows")
	for count in [5, 16]:
		var screen := _screen(count, 0)
		var start := Rect2(screen.start_button.position, screen.start_button.size)
		assert_true(start.position.x >= SELECT.DETAIL_X, "Start is under the details column")
		assert_true(SELECT.CARD_AREA.encloses(start), "Start stays on the paper")
		var shown := mini(count, SELECT.MAX_CARDS)
		assert_eq(shown, 5 if count == 5 else 6, "all five rows show; six of sixteen")
		for i in range(screen.top, screen.top + shown):
			var row: Rect2 = screen._entry_rect(i)
			assert_true(SELECT.CARD_AREA.encloses(row), "row %d stays on the paper" % i)
			assert_false(start.intersects(row), "row %d does not overlap Start" % i)
			if i > screen.top:
				assert_false(row.intersects(screen._entry_rect(i - 1)), "rows do not overlap")
		assert_false(SELECT.CARD_AREA.encloses(screen._entry_rect(screen.top + SELECT.MAX_CARDS)), "a seventh row would not fit")
		_free(screen)


func test_keys_and_wheel_scroll_a_long_list_and_keep_the_selection_visible() -> void:
	var screen := _screen(16, 0)
	screen.scroll.unroll(true)
	for i in 15:
		var down := InputEventKey.new()
		down.keycode = KEY_DOWN
		down.pressed = true
		screen._unhandled_input(down)
		assert_true(screen.selected >= screen.top and screen.selected < screen.top + SELECT.MAX_CARDS, "visible at %d" % i)
	assert_eq(screen.selected, 15)
	assert_eq(screen.top, 10, "the list ends on the last region")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	for i in 15:
		screen.scroll.gui_input.emit(wheel)
	assert_eq(screen.selected, 0)
	assert_eq(screen.top, 0)
	_free(screen)


## Henesys and Sleepywood against their real pools (cache-backed, SKIPs without it).
func test_lv_range_of_the_real_regions() -> void:
	if not require_cache():
		return
	var data := DataRepo.load_all()
	var lib := AssetLibrary.get_default()
	for key: String in ["henesys", "sleepywood"]:
		if not lib.has_img(AssetLibrary.mob_img_path(int(data.stages.stages[key].maps[0].boss.mob_id))):
			skip("mob imgs absent from cache")
			return
	var cards := SELECT.load_progression(data, [])
	var expected := {}
	for key: String in ["henesys", "sleepywood"]:
		var st: Dictionary = data.stages.stages[key]
		var ids := {}
		for kf: Dictionary in st.keyframes:
			for id: Variant in kf.get("pool", {}):
				ids[int(id)] = true
		for entry: Dictionary in st.maps:
			var img := lib.img(AssetLibrary.map_img_path(int(entry.map_id)))
			for id: int in StagePools.resolve(entry, img.root if img != null else {}):
				ids[id] = true
		for entry: Dictionary in st.maps:
			ids.erase(int(entry.boss.mob_id))
		var lo := 9999
		var hi := 0
		for id: int in ids:
			var level := int(lib.img(AssetLibrary.mob_img_path(id)).root.info.level)
			lo = mini(lo, level)
			hi = maxi(hi, level)
		expected[key] = [lo, hi]
	for card: Dictionary in cards:
		if expected.has(card.key):
			assert_eq([card.level_lo, card.level_hi], expected[card.key], "%s Lv range" % card.key)
			assert_eq(SELECT.level_text(card), "Lv %d-%d" % expected[card.key])
	# Read by hand from the pools: Henesys Snail Lv 1 .. Horny Mushroom Lv 22 (Mano, Mushmom and the Blue Mushmom form excluded);
	# Sleepywood Stirge Lv 20 .. Taurospear Lv 75 (the Dark Cave, Drake Area and Cursed Sanctuary pools).
	assert_eq(SELECT.level_text(cards[0]), "Lv 1-22")
	assert_eq(SELECT.level_text(cards[4]), "Lv 20-75")
