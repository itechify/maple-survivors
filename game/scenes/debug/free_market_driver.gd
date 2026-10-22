extends Node
## Visual hub probe: supplies a completed round with the committed character fixture, then exercises boundary flow.
## Saves only under --shots=<absolute evidence directory>, never the player's save. Uses the real map and art.
## ISOLATE=t71 MAPLE_SURVIVORS_CACHE=<private cache> bash scripts/test.sh free_market ui_flow
## ISOLATE=t71 MAPLE_SURVIVORS_CACHE=<private cache> bash scripts/godot.sh --path _scratch/godot_runs/t71/game
##   res://scenes/debug/free_market_driver.tscn -- --shots=<repo>/evidence/t71/hub

var flow: SceneFlow
var shots := ""
var failures: Array[String] = []
var missing := PackedStringArray()


func _ready() -> void:
	shots = String(SceneFlow.parse_flags(OS.get_cmdline_user_args()).get("shots", ""))
	if shots.is_empty():
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(shots)
	flow = get_node("/root/Flow") as SceneFlow
	flow.host = self
	flow.deferred_swaps = false
	var path := shots.path_join("driver_save.json")
	for file: String in [path, path + ".bak", path + ".tmp"]:
		if FileAccess.file_exists(file):
			DirAccess.remove_absolute(file)
	flow.save = SaveData.new(path)
	flow.create_character("Market71")
	var character: Dictionary = DataRepo.load_json("res://tests/fixtures/characters/lv35_magician_2nd.json")
	flow.finish_run({"stage": "henesys", "cleared": true, "time": 960.0, "level": 35,
		"job_id": 210, "job_name": "Wizard (Fire, Poison)", "kills": 3000, "damage_dealt": 100000, "seed": 1,
		"bosses_killed": 3, "levels_gained": 12, "nx_awarded": 310}, character)
	var hub := flow.current as FreeMarket
	if hub == null or hub.motion == null:
		get_tree().quit(1)
		return
	_check(flow.save.slot(0).phase == "free_market", "arrival autosave")
	await get_tree().create_timer(1.0).timeout
	await _shot("01_arrival")
	# Canonical NPC platform; show all four inert NPCs and the character's wand/outfit.
	hub.motion.player.place(Vector2(180, -176), hub.motion.fhm)
	hub.camera.snap_to(hub.motion.player.pos)
	await get_tree().create_timer(0.5).timeout
	await _shot("02_npcs")
	await _key(KEY_ESCAPE)
	await get_tree().create_timer(0.3).timeout
	_check(hub.pause_menu.is_open(), "Esc opens hub pause")
	await _shot("03_save_quit")
	hub.pause_menu.activate(1)
	_check(flow.current_name == "character_select", "Save & quit returns to characters")
	flow.save = SaveData.new(path)
	flow.continue_character(0)
	_check(flow.current_name == "free_market", "Continue opens the hub")
	hub = flow.current as FreeMarket
	await get_tree().create_timer(0.5).timeout
	await _shot("04_continue")
	hub.motion.player.place(Vector2(560, -269), hub.motion.fhm)
	hub.camera.snap_to(hub.motion.player.pos)
	await _key(KEY_UP)
	_check(flow.current_name == "free_market", "room portal is inert")
	await get_tree().create_timer(0.3).timeout
	await _shot("05_rooms")
	# Reuse the real fixed-tick walking seam, then activate out00 through normal keyboard input.
	hub.motion.player.place(Vector2(-650, 34), hub.motion.fhm)
	for tick in 65:
		hub.step_input(1.0 / 60.0, MoveInput.make(false, true))
	hub.motion.player.vel = Vector2.ZERO
	hub.camera.snap_to(hub.motion.player.pos)
	await get_tree().create_timer(0.3).timeout
	await _shot("06_out00")
	missing = hub.missing_paths()
	await _key(KEY_UP)
	_check(flow.current_name == "stage_select", "out00 opens map select")
	_check(flow.save.slot(0).phase == "map_select", "exit autosaves map select")
	await get_tree().create_timer(2.0).timeout
	await _shot("07_next_tier")
	for item: String in AssetLibrary.get_default().missing:
		if not item in missing:
			missing.append(item)
	_check(missing.is_empty(), "missing assets")
	var boundary: Dictionary = flow.save.slot(0)
	# #115: a death in the next tier credits its NX with the archive and the results screen shows it.
	flow.finish_run({"stage": "sleepywood", "map_id": 0, "region": "Sleepywood", "continent": "Victoria Island", "map_name": "Dark Cave", "street_name": "Victoria Road",
		"cleared": false, "time": 412.0, "duration": 900.0, "level": 41, "job_id": 210,
		"job_name": "Wizard (Fire, Poison)", "kills": 1500, "damage_dealt": 80000, "seed": 2,
		"bosses_killed": 1, "levels_gained": 6, "nx_awarded": 70}, character)
	_check(flow.current_name == "results" and flow.save.account.nx == 380, "NX credited by clear and death")
	await get_tree().create_timer(2.0).timeout
	await _shot("08_results_death")
	var report := {"failures": failures, "missing": Array(missing), "phase": boundary.phase,
		"tier": boundary.tier, "nx": flow.save.account.nx, "character": character}
	var file := FileAccess.open(shots.path_join("summary.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("free_market_driver: ", JSON.stringify({"failures": failures, "missing": Array(missing)}))
	get_tree().quit(0 if failures.is_empty() else 1)


func _check(ok: bool, description: String) -> void:
	if not ok:
		failures.append(description)
		push_error("free_market_driver: " + description)


func _key(key: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = key
		event.physical_keycode = key
		event.pressed = pressed
		Input.parse_input_event(event)
		await get_tree().process_frame


func _shot(name: String) -> void:
	await get_tree().process_frame
	RenderingServer.force_draw()
	var error := get_viewport().get_texture().get_image().save_png(shots.path_join(name + ".png"))
	_check(error == OK, "screenshot " + name)
