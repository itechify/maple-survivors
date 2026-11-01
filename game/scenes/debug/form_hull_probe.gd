extends Node
## Tool-only probe of the ship's hull presentation (spec #384 C11): a synthetic form with a hull on the real map, hit by a
## boss-style attack every 0.6 s so the bar drains and the blue absorbed number appears, then the hull breaks and the bar
## goes. Run with `-- --shots=<absolute evidence directory>`; never saves a character.

const HIT_EVERY := 0.6
var _run: RunScene
var _clock := 0.0
var _next := 0.5


func _ready() -> void:
	var shots := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			shots = arg.trim_prefix("--shots=")
	if shots.is_empty():
		push_error("form_hull_probe requires --shots=<absolute evidence directory>")
		get_tree().quit(1)
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_run = load(RunScene.SCENE_PATH).instantiate()
	_run.configure("henesys", 395, {"job": 212, "autopick": true, "use_flow": false,
		"shots_dir": shots, "shot_every": 0.5, "quit_after": 5.0,
		"world_prepared": func(w: RunWorld) -> void:
			w.loadout.add_player_mod("max_hp", "add", 950.0)
			w.refresh_player_stats()
			w.restore_player("hp", 2000, "probe")
			w.book.defs["probe_ship"] = {"skill_id": 9991001, "book": "999", "kind": "form", "slot": "active",
				"damage": "none", "icon": w.book.def("magic_claw").icon, "ranks": [1],
				"form": {"duration": 30.0, "exclusive_group": "probe",
					"effects": {"hull": {"field": "pdd", "of": "max_hp"}}, "presentation": {"mount": 1932000}, "subs": []}}
			w.book.skill_imgs["999"] = {"skill": {"9991001": {"level": {"1": {"pdd": 25}}}}}
			w.runner.forms.start(w, "probe_ship", w.loadout.stats("probe_ship"))
	})
	add_child(_run)


func _process(delta: float) -> void:
	_clock += delta
	if _run == null or _run.world == null or _clock < _next:
		return
	_next += HIT_EVERY
	var dealt := _run.world.take_hit(60.0, false, "", _run.world.player.pos + Vector2(-60, 0),
		{"accuracy": 1.0e9, "boss": true, "source_kind": "attack"})
	print("form_hull_probe t=%.1f hp damage %d, hull %.2f" % [_clock, dealt, _run.world.runner.forms.hull_fraction()])
