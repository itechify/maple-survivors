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
