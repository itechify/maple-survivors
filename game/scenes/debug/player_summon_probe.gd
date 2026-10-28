extends Node
## Tool-only summon art/performance probe: --shots=<absolute evidence dir> [--skill=elquines|ifrit] [--without-summon].
## Ifrit runs as the I/L job (222) with every other monster fire_weak, so its priority order shows. Never saves a character.

func _ready() -> void:
	var shots := ""
	var enabled := true
	var skill := "elquines"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			shots = arg.trim_prefix("--shots=")
		if arg.begins_with("--skill="):
			skill = arg.trim_prefix("--skill=")
		if arg == "--without-summon":
			enabled = false
	if shots.is_empty():
		push_error("player_summon_probe requires --shots=<absolute evidence directory>")
		get_tree().quit(1)
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var run: RunScene = load(RunScene.SCENE_PATH).instantiate()
	run.configure("henesys", 291, {"autopick": true, "use_flow": false, "perf": true,
		"shots_dir": shots, "shot_every": 1.0, "quit_after": 20.0,
		"world_prepared": func(w: RunWorld) -> void:
			w.god = true
			if skill == "ifrit":
				w.set_job(222)
			w.loadout.order.clear()
			if enabled:
				w.learn_skill(skill)
				w.loadout.set_rank(skill, 8)
				w.loadout.add_skill_mod(skill, "damage", "mul", 0.01)
			# Diagnostic targets: real mob art, still standing, high HP; this is not survival/balance evidence.
			for kind: MobKind in w.mob_kinds:
				kind.move_speed = 0.0
			for i in 200:
				var slot := w.spawn_mob(0, w.player.pos + Vector2(70 + i % 20 * 5, 0), w.player.fh, 1.0, false)
				if slot >= 0:
					w.swarm.hp[slot] = 100000
					w.swarm.max_hp[slot] = 100000
					if skill == "ifrit" and i % 2 == 0:
						w.swarm.apply_status(slot, "fire_weak", {"time": 1000.0}, w.events)
	})
	add_child(run)
