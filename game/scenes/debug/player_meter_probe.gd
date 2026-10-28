extends Node
## Tool-only meter HUD probe on the real map, with an injected Combo counter; never saves a character.

func _ready() -> void:
	var shots := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			shots = arg.trim_prefix("--shots=")
	if shots.is_empty():
		push_error("player_meter_probe requires --shots=<absolute evidence directory>")
		get_tree().quit(1)
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var run: RunScene = load(RunScene.SCENE_PATH).instantiate()
	run.configure("henesys", 299, {"job": 212, "autopick": true, "use_flow": false,
		"shots_dir": shots, "shot_every": 1.0, "quit_after": 5.0,
		"world_prepared": func(w: RunWorld) -> void:
			w.god = true
			# Diagnostic only: H2 owns Hero's real job data, H8 the finishers.
			w.meter = PlayerMeter.new({"id": "combo", "max": 10,
				"gain": {"event": "cast_landed", "amount": 1, "exclude": "finisher"},
				"per_unit": {"stat": "damage", "value": 0.02},
				"art": "Skill.wz/111.img/skill/1111002/state"})
			for i in 7:
				w.meter.gain("cast_landed", w.events)
	})
	add_child(run)
