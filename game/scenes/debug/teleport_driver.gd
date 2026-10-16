extends Node
## Close Teleport evidence on the real map/cache, using the normal X input and card learning path.
## ISOLATE=t60 bash scripts/run.sh res://scenes/debug/teleport_driver.tscn -- --branch=210 --shots=<abs evidence dir>
## Saves departure/arrival and unaffordable HUD views plus summary.json. No cache import or balance edits.

var run: RunScene
var shots := ""


func _ready() -> void:
	call_deferred("_drive")


func _drive() -> void:
	var args := SceneFlow.parse_flags(OS.get_cmdline_user_args())
	shots = String(args.get("shots", ""))
	if shots == "":
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(shots)
	var branch := int(args.get("branch", 210))
	var key := {210: "teleport_fp", 220: "teleport_il", 230: "teleport_cleric"}.get(branch, "") as String
	if key == "":
		get_tree().quit(2)
		return
	run = (load(RunScene.SCENE_PATH) as PackedScene).instantiate()
	run.configure("henesys_hg1", 60, {"use_flow": false, "autopick": true})
	add_child(run)
	run.set_process(false)
	var w := run.world
	w.god = true
	w.change_job(200)
	w.change_job(branch)
	w.upgrades.apply(key + "_new", w)
	w.heal_fraction("mp", 1.0)
	run.handle_events(w.drain_events())
	# Wait for advancement presentation before testing the manual input.
	for tick in 120:
		run.advance_frame(1.0 / 60.0)
		await get_tree().process_frame
	var departure := w.player.pos
	_press(KEY_X, true)
	await get_tree().process_frame
	run.advance_frame(1.0 / 60.0)
	_press(KEY_X, false)
	for tick in 4:
		run.advance_frame(1.0 / 60.0)
		await get_tree().process_frame
	await _shot("teleport.png")
	var arrival := w.player.pos
	w.spend_mp(int(w.player_state.mp))
	run.advance_frame(1.0 / 60.0)
	await _shot("teleport_no_mp.png")
	var summary := run.perf_summary()
	summary["teleport_probe"] = {"departure": [departure.x, departure.y], "arrival": [arrival.x, arrival.y],
		"key": "X", "skill": key, "affordable": w.teleport_affordable()}
	var file := FileAccess.open(shots.path_join("summary.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(summary, "\t"))
	get_tree().quit()


func _press(key: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.keycode = key
	event.pressed = pressed
	Input.parse_input_event(event)


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(shots.path_join(name))
