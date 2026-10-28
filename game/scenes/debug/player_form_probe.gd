extends Node
## Tool-only synthetic Form presentation probe on the real map, with an injected Combo counter; never saves a character.

func _ready() -> void:
	var shots := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			shots = arg.trim_prefix("--shots=")
	if shots.is_empty():
		push_error("player_form_probe requires --shots=<absolute evidence directory>")
		get_tree().quit(1)
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var run: RunScene = load(RunScene.SCENE_PATH).instantiate()
	run.configure("henesys", 311, {"job": 212, "autopick": true, "use_flow": false,
		"shots_dir": shots, "shot_every": 1.0, "quit_after": 5.0,
		"world_prepared": func(w: RunWorld) -> void:
			w.god = true
			w.book.defs["probe_form"] = {"skill_id": 9991001, "book": "999", "kind": "form", "slot": "active",
				"damage": "none", "icon": w.book.def("magic_claw").icon, "ranks": [1],
				"form": {"duration": 30.0, "exclusive_group": "probe", "effects": {"element": "f"}, "subs": []}}
			w.runner.forms.start(w, "probe_form", w.loadout.stats("probe_form"))
	})
	add_child(run)
