extends Node
## Tool-only meter HUD probe on the real map, with an injected Combo counter; never saves a character.
## `--meso` shows the meso charge instead (M23: the spec's block, six pips picked up); `--no-art` drops its art path so
## the drawn pips are checked too.

func _ready() -> void:
	var shots := ""
	var meso := false
	var no_art := false
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			shots = arg.trim_prefix("--shots=")
		meso = meso or arg == "--meso"
		no_art = no_art or arg == "--no-art"
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
			# Diagnostic: the live Hero configuration displayed on the F/P probe character.
			if meso:
				var block: Dictionary = w.jobs.lineage_value(412, "meter", {}).duplicate(true)
				if no_art:
					block.erase("art")
				w.meter = PlayerMeter.new(block)
				w.meter.gain_amount("meso_picked", 6500, w.events)
				return
			w.meter = PlayerMeter.new(w.jobs.lineage_value(112, "meter", {}))
			for i in 7:
				w.meter.gain("cast_landed", w.events)
	})
	add_child(run)
