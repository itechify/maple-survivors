extends Node
## Dash evidence on the real Henesys map and cache (#188): a Pirate learns Dash, Key Config lists its skill key, the real
## X key starts the buff and the arrow key runs under it. Saves key_config_dash.png, dash_cast.png and dash_run.png plus
## summary.json (speed and jump stats, distance run with and without the buff).
## MAPLE_SURVIVORS_CACHE=<cache> ISOLATE=<name> bash scripts/run.sh res://scenes/debug/dash_driver.tscn -- \
##   --shots=<abs evidence dir> [--rank=10]

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
	run = (load(RunScene.SCENE_PATH) as PackedScene).instantiate()
	run.configure("henesys", 60, {"use_flow": false, "autopick": true})
	add_child(run)
	run.set_process(false)
	var w := run.world
	w.god = true
	w.change_job(500, "knuckle")
	w.upgrades.apply("dash_new", w)
	for i in int(args.get("rank", 10)) - 1:
		w.upgrades.apply("dash_rank", w)
	w.heal_fraction("mp", 1.0)
	run.handle_events(w.drain_events())
	await _frames(0.5)
	# Key Config lists Dash's skill key (and nothing else of this kind).
	run.toggle_window("key_config")
	await _frames(0.5)
	var kc := run.ui_windows.top() as KeyConfigWindow
	var listed: Array = []
	if kc != null:
		listed = kc.draft.actions().filter(func(a: String) -> bool: return a in KeyBindings.SKILL_KEYS)
	await _shot("key_config_dash.png")
	run.ui_windows.close("key_config")
	await _frames(0.3)
	# Walk a second without the buff, then run a second with it, through the real input path.
	var start := w.player.pos
	_press(KEY_RIGHT, true)
	await _frames(1.0)
	_press(KEY_RIGHT, false)
	var plain := w.player.pos.x - start.x
	await _frames(0.6)
	var speed_before := w.player.speed_stat
	var jump_before := w.player.jump_stat
	var mp_before := int(w.player_state.mp)
	_press(KEY_X, true)
	await _frames(1.0 / 60.0)
	_press(KEY_X, false)
	await _frames(0.05)
	await _shot("dash_cast.png")
	var speed_after := w.player.speed_stat
	var jump_after := w.player.jump_stat
	var mp_after := int(w.player_state.mp)
	start = w.player.pos
	_press(KEY_RIGHT, true)
	await _frames(0.5)
	await _shot("dash_run.png")
	await _frames(0.5)
	_press(KEY_RIGHT, false)
	var dashed := w.player.pos.x - start.x
	var file := FileAccess.open(shots.path_join("summary.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"skill_keys_listed": listed, "rank": w.loadout.rank("dash"),
		"speed_stat": [speed_before, speed_after], "jump_stat": [jump_before, jump_after],
		"mp": [mp_before, mp_after], "run_px_per_second": {"plain": plain, "dash": dashed},
		"buff_left": float(w.buffs.active.get("dash", {}).get("remaining", 0.0))}, "\t"))
	get_tree().quit()


func _press(key: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.keycode = key
	event.pressed = pressed
	Input.parse_input_event(event)


func _frames(seconds: float) -> void:
	for i in maxi(1, roundi(seconds * 60.0)):
		run.advance_frame(1.0 / 60.0)
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(shots.path_join(name))
