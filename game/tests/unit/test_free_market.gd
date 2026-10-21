extends TestCase
## Hub movement/exit behavior through fixed ticks; real-cache presentation is checked separately.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0


static func hub_map() -> Dictionary:
	var map := RF.map_from_segments([{"x1": 0, "y1": 200, "x2": 1200, "y2": 200}])
	map.portal = {
		"0": {"pn": "sp", "pt": 0, "x": 100, "y": 200},
		"1": {"pn": "out00", "pt": 7, "x": 500, "y": 200, "tm": 999999999, "tn": ""},
		"2": {"pn": "in01", "pt": 2, "x": 200, "y": 200, "tm": 910000001, "tn": "sp"},
	}
	return map


func test_walk_right_past_inert_room_then_up_at_out00_requests_map_select() -> void:
	var hub := FreeMarketMotion.new(hub_map())
	for tick in 150:
		assert_true(hub.step(DT, MoveInput.make(false, true)).is_empty(), "walking never exits")
	assert_true(hub.player.pos.x > 350, "normal motion walks right from the spawn")
	hub.player.place(Vector2(200, 200), hub.fhm)
	assert_true(hub.step(DT, MoveInput.make(false, false, true)).is_empty(), "room portal is inert")
	for tick in 180:
		if hub.player.pos.x >= 490:
			break
		hub.step(DT, MoveInput.make(false, true))
	assert_eq(hub.step(DT, MoveInput.make(false, false, true)), [{"type": "exit_requested"}])


func test_boundary_pause_saves_without_a_round_loss_warning() -> void:
	var pause := PauseMenu.new()
	pause.set("boundary_mode", true)
	var emitted: Array = []
	pause.quit_requested.connect(func() -> void: emitted.append("save"))
	pause.open()
	pause.activate(1)
	assert_eq(emitted, ["save"], "boundary quit needs no destructive-round confirmation")
	assert_false(pause.confirming_quit)
	pause.free()


func test_normal_jump_ladder_and_same_map_links_remain_available() -> void:
	var map := hub_map()
	map.ladderRope = {"0": {"l": 1, "uf": 1, "x": 100, "y1": 0, "y2": 200}}
	map.portal["3"] = {"pn": "up00", "pt": 1, "x": 800, "y": 200, "tm": 910000000, "tn": "up01"}
	map.portal["4"] = {"pn": "up01", "pt": 1, "x": 1000, "y": 200, "tm": 999999999, "tn": ""}
	var hub := FreeMarketMotion.new(map)
	hub.step(DT, MoveInput.make(false, false, false, false, true))
	assert_true(hub.player.pos.y < 200, "jump uses normal player physics")
	hub.player.place(Vector2(100, 200), hub.fhm)
	hub.step(DT, MoveInput.make(false, false, true))
	assert_eq(hub.player.state, PlayerMotion.ST_LADDER)
	for tick in 20:
		hub.step(DT, MoveInput.make(false, false, true))
	assert_true(hub.player.pos.y < 180, "Up climbs the canonical ladder")
	hub.player.place(Vector2(800, 200), hub.fhm)
	assert_eq(hub.step(DT, MoveInput.make(false, false, true)),
		[{"type": "portal_used", "portal": "up00", "target": "up01", "pos": Vector2(1000, 170)}])
	assert_eq(hub.player.pos, Vector2(1000, 170))


func test_look_comes_only_from_character_and_weapon_follows_job() -> void:
	var data := DataRepo.load_all()
	var character := {"look": {}, "job_id": 0, "beginner_weapon": 0}
	var look := FreeMarket.character_look(character, data)
	assert_eq(look.face, 20000, "empty look uses AvatarRenderer's default")
	assert_true(1302000 in look.equips, "a format-1 Beginner draws the default creation weapon")
	character.look = {"skin": 2, "face": 21000, "hair": 31000, "equips": [1041002, 1061002, 1072001, 1302000]}
	character.beginner_weapon = 1322005
	look = FreeMarket.character_look(character, data)
	assert_eq(look.equips, [1041002, 1061002, 1072001, 1322005])
	assert_eq(look.skin, 2)
	assert_eq(look.face, 21000)
	character.job_id = 210
	look = FreeMarket.character_look(character, data)
	assert_eq(look.equips, [1041002, 1061002, 1072001, 1372005], "second job inherits Magician weapon")
	assert_eq(character.look.equips, [1041002, 1061002, 1072001, 1302000], "presentation leaves snapshot unchanged")


func test_real_hub_draws_all_npcs_refills_pools_and_keeps_rooms_inert() -> void:
	if not require_cache():
		return
	var data := DataRepo.load_all()
	var character := DataRepo.load_json("res://tests/fixtures/characters/lv35_magician_2nd.json") as Dictionary
	assert_false(character.is_empty())
	var hub := FreeMarket.new()
	hub.configure({"name": "Market71", "character": character}, null)
	(Engine.get_main_loop() as SceneTree).current_scene.add_child(hub)
	hub.set_process(false)
	assert_eq(hub.npcs.map(func(n: Dictionary) -> int: return int(n.id)), [9030000, 9030100, 9250025, 9000069])
	assert_eq(hub.motion.ladders.count(), 2)
	assert_eq((hub.get_node("/root/Sfx") as AudioService).current_bgm, "Sound.wz/Bgm00.img/FloralLife")
	assert_true(hub.avatar.current_parts().any(func(p: Dictionary) -> bool: return p.name == "weapon"),
		"the current job weapon is composed by AvatarRenderer")
	var setup := RF.setup("henesys_hg1", 7, data)
	setup.character = character
	var round_world := RunWorld.new(setup)
	assert_eq(hub.status.player_state.hp, round_world.player_state.max_hp)
	assert_eq(hub.status.player_state.mp, round_world.player_state.max_mp)
	var before := JSON.stringify(hub.snapshot)
	var count := 0
	for portal: Dictionary in hub.map.map_root.portal.values():
		if String(portal.get("pn", "")).begins_with("in"):
			count += 1
			hub.motion.player.place(Vector2(float(portal.x), float(portal.y)), hub.motion.fhm)
			assert_true(hub.motion.step(DT, MoveInput.make(false, false, true)).is_empty(), String(portal.pn))
	assert_eq(count, 22)
	assert_eq(JSON.stringify(hub.snapshot), before, "walking changes no carried progression")
	var feet := hub.motion.player.pos
	hub.open_pause()
	hub.step_input(DT, MoveInput.make(false, true))
	assert_eq(hub.motion.player.pos, feet, "the pause window holds movement")
	assert_eq(hub.missing_paths(), PackedStringArray())
	hub.free()


func test_name_tag_skipped_for_npcs_the_map_hides() -> void:
	assert_false(FreeMarket.npc_shows_name_tag({"type": "n", "id": "9250025", "hide": 1}), "hidden Maple TV has no tag")
	assert_true(FreeMarket.npc_shows_name_tag({"type": "n", "id": "9030000", "hide": 0}))
	assert_true(FreeMarket.npc_shows_name_tag({"type": "n", "id": "9030000"}), "no hide field means shown")


func test_real_hub_hidden_maple_tv_has_no_name_tag() -> void:
	if not require_cache():
		return
	var character := DataRepo.load_json("res://tests/fixtures/characters/lv35_magician_2nd.json") as Dictionary
	var hub := FreeMarket.new()
	hub.configure({"name": "Market111", "character": character}, null)
	(Engine.get_main_loop() as SceneTree).current_scene.add_child(hub)
	hub.set_process(false)
	for npc: Dictionary in hub.npcs:
		var sprite := npc.sprite as Node2D
		assert_eq(sprite.get_child_count(), 0 if int(npc.id) == 9250025 else 1, "tag children of %d" % int(npc.id))
	hub.free()


# --- the bot in the hub and the hub's scroll randomness (review fixes of spec #33) ----------------------------------

## A real hub (needs the cache) for the Lv38 fixture carrying `mesos`; `options` as FreeMarket.configure takes them.
func _bot_hub(mesos: int, options: Dictionary = {}, round_seed := 4242) -> FreeMarket:
	var character := DataRepo.load_json("res://tests/fixtures/characters/lv35_magician_2nd.json") as Dictionary
	character.mesos = mesos
	var hub := FreeMarket.new()
	hub.configure({"name": "BotHub", "character": character, "round_seed": round_seed}, null, options)
	(Engine.get_main_loop() as SceneTree).current_scene.add_child(hub)
	hub.set_process(false)
	return hub


func test_autoplay_runs_the_sensible_shop_visit_once_on_entering_the_hub() -> void:
	if not require_cache():
		return
	var idle := _bot_hub(300000)
	assert_eq(idle.shop_visit, {}, "no visit without autoplay")
	assert_eq(idle.inventory.mesos, 300000)
	idle.free()
	var hub := _bot_hub(300000, {"autoplay": true})
	assert_true(int(hub.shop_visit.get("bought", 0)) > 0, "the bot bought scrolls on entry: %s" % [hub.shop_visit])
	assert_eq(int(hub.shop_visit.used), int(hub.shop_visit.bought), "and read them")
	assert_true(hub.inventory.mesos < 300000, "mesos were spent")
	assert_eq(int(hub.snapshot.character.mesos), hub.inventory.mesos, "the visit is in the carried snapshot")
	hub.free()


func test_the_hub_seeds_scrolls_from_the_saved_state_so_reloading_cannot_reroll() -> void:
	var base := {"name": "A", "round_seed": 77, "character": {"mesos": 10, "scrolls": {"2043700": 2},
		"equipment": {"worn": {"hat": {"id": 1002001, "stats": {"incPDD": 4}, "slots": 7, "scrolls": 0}}, "inventory": []}}}
	var seed_a := FreeMarket.scroll_seed(base)
	assert_eq(seed_a, FreeMarket.scroll_seed(base.duplicate(true)), "the same save always gives the same seed")
	var read := base.duplicate(true)
	read.character.scrolls["2043700"] = 1
	read.character.equipment.worn.hat.slots = 6
	read.character.equipment.worn.hat.scrolls = 1
	assert_ne(FreeMarket.scroll_seed(read), seed_a, "every scroll changes the next seed")
	var richer := base.duplicate(true)
	richer.character.mesos = 11
	assert_ne(FreeMarket.scroll_seed(richer), seed_a, "mesos are part of the state")
	var other_run := base.duplicate(true)
	other_run.round_seed = 78
	assert_ne(FreeMarket.scroll_seed(other_run), seed_a, "the run's stored seed is mixed in")


func test_two_hubs_from_the_same_save_read_the_same_scroll_results() -> void:
	if not require_cache():
		return
	var outcomes := []
	for _i in 2:
		var hub := _bot_hub(0)
		hub.inventory.scrolls["2043700"] = 3
		var results := []
		for _s in 3:
			assert_eq(hub.inventory.use_scroll(2043700, "weapon"), "")
			results.append(hub.inventory.equipment.worn.weapon.duplicate(true))
		outcomes.append(results)
		hub.free()
	assert_eq(outcomes[0], outcomes[1])


func test_live_scroll_rolls_after_an_inventory_action_match_a_rebuilt_saved_hub() -> void:
	if not require_cache():
		return
	var live := _bot_hub(0, {}, 1)
	live.inventory.grant_scrolls(2043701, 3)
	# A real inventory action saves/reseeds through the handler used by Equip, Item and shops.
	assert_eq(live.inventory.unequip_item("weapon"), "")
	live._on_item_action("unequip")
	assert_eq(live.inventory.equip_item(live.inventory.equipment.inventory.size() - 1), "")
	live._on_item_action("equip")
	for attempt in 3:
		var saved: Dictionary = JSON.parse_string(JSON.stringify(live.snapshot))
		var rebuilt := FreeMarket.new()
		rebuilt.configure(saved, null)
		(Engine.get_main_loop() as SceneTree).current_scene.add_child(rebuilt)
		rebuilt.set_process(false)
		var live_state := live.inventory.scroll_rng.state
		var rebuilt_state := rebuilt.inventory.scroll_rng.state
		var live_rolls := []
		var rebuilt_rolls := []
		for roll in 8:
			live_rolls.append(live.inventory.scroll_rng.randi_range(0, 99))
			rebuilt_rolls.append(rebuilt.inventory.scroll_rng.randi_range(0, 99))
		assert_eq(live_rolls, rebuilt_rolls, "actual next rolls after saved action %d" % attempt)
		live.inventory.scroll_rng.state = live_state
		rebuilt.inventory.scroll_rng.state = rebuilt_state
		assert_eq(live.inventory.use_scroll(2043701, "weapon"), "")
		assert_eq(rebuilt.inventory.use_scroll(2043701, "weapon"), "")
		assert_eq(live.inventory.character_snapshot(), rebuilt.inventory.character_snapshot(),
			"the next 60% scroll has the same outcome live or after Continue/Cash Shop reconstruction")
		live._on_item_action("scroll")
		rebuilt.free()
	live.free()


func test_bot_shop_is_reproducible_for_a_seed_in_purchases_and_scroll_results() -> void:
	if not require_cache():
		return
	var records := []
	var worn := []
	for seed_value in [5, 5, 6]:
		var hub := _bot_hub(400000)
		records.append(hub.bot_shop("random", seed_value))
		worn.append(hub.inventory.equipment.worn.duplicate(true))
		hub.free()
	assert_true(int(records[0].used) > 0, "the careless bot read scrolls")
	assert_eq(records[0], records[1], "same seed, same purchases and results")
	assert_eq(worn[0], worn[1], "same seed, same scrolled equipment")
	assert_ne(JSON.stringify([records[0], worn[0]]), JSON.stringify([records[2], worn[2]]), "another seed, another visit")


## Spec #225: an old format-2 save (Magnet ranks, starter potions at Lv 45) is migrated and caught up on every load path.
func _old_potion_character() -> Dictionary:
	var character := DataRepo.load_json("res://tests/fixtures/characters/lv35_magician_2nd.json") as Dictionary
	character.level = 45
	character.card_ranks["magnet"] = 3
	character.player_mods["magnet"] = [0.0, 1.953125]
	character.potions.hp.item_id = 2000000
	character.potions.mp.item_id = 2000003
	return character


func test_continue_migration_drops_magnet_from_a_format_2_save() -> void:
	var character := _old_potion_character()
	var migrated := SceneFlow.migrated_character(character, Callable())
	assert_false(migrated.card_ranks.has("magnet"), "the Magnet rank is dropped on a format-2 load")
	assert_false(migrated.player_mods.has("magnet"))
	assert_true(character.card_ranks.has("magnet"), "the source is not mutated")
	assert_eq(SceneFlow.migrated_character(migrated, Callable()), migrated, "idempotent")


func test_hub_boundary_of_an_old_save_has_no_magnet_and_shows_the_caught_up_potions() -> void:
	if not require_cache():
		return
	var hub := FreeMarket.new()
	hub.configure({"name": "OldSave", "character": _old_potion_character(), "round_seed": 9}, null, {})
	(Engine.get_main_loop() as SceneTree).current_scene.add_child(hub)
	hub.set_process(false)
	var loadout := FreeMarket._boundary_loadout(hub.snapshot.character, DataRepo.load_all())
	assert_false(loadout.player_mods.has("magnet"), "no magnet radius modifier in the hub")
	assert_false(hub.snapshot.character.card_ranks.has("magnet"))
	assert_eq(hub.inventory.potions.stock.hp.item_id, 2022003, "Lv 45 shows Unagi in the hub Item window")
	assert_eq(hub.inventory.potions.stock.mp.item_id, 2022000, "and Pure Water")
	hub.free()
