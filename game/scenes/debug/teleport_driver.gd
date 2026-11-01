extends Node
## Close Teleport evidence on the real map/cache, using the normal X input and card learning path.
## ISOLATE=t60 bash scripts/run.sh res://scenes/debug/teleport_driver.tscn -- --branch=210 --shots=<abs evidence dir>
## Saves departure/arrival and unaffordable HUD views plus summary.json. No cache import or balance edits.

const RF := preload("res://tests/fixtures/run_fixtures.gd")

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
	run.configure("henesys", 60, {"use_flow": false, "autopick": true})
	add_child(run)
	run.set_process(false)
	var w := run.world
	w.god = true
	RF.as_job(w, 200)
	RF.as_job(w, branch)
	w.learn_skill(key)
	run.handle_events(w.drain_events())
	# WZ effects advance in presentation time, independently of this driver's fixed simulation ticks.
	await get_tree().create_timer(2.0).timeout
	run.advance_frame(1.0 / 60.0)
	var departure := w.player.pos
	_press(KEY_X, true)
	await get_tree().process_frame
	run.advance_frame(1.0 / 60.0)
	_press(KEY_X, false)
	await get_tree().create_timer(0.08).timeout
	await _shot("teleport.png")
	var arrival := w.player.pos
	var summary := run.perf_summary()
	summary["teleport_probe"] = {"departure": [departure.x, departure.y], "arrival": [arrival.x, arrival.y],
		"key": "X", "skill": key}
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
