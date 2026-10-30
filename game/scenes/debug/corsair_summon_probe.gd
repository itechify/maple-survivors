extends Node
## Tool-only Corsair summon probe (spec #384 C6 #390): --shots=<absolute evidence dir> [--shot-every=<s>] [--crowd=<n>] [--quit-after=<s>].
## A Corsair (job 522 stand-in, Pistol worn, god mode) with Octopus and Gaviota at rank 8 on Henesys and a crowd of standing,
## near-unkillable mobs in front of it (200 by default), so the planted octopus's balls and the bird's dive can be looked at.
## Needs Skill.wz/521.img in the cache. Never saves a character; diagnostic art and cost evidence, not balance evidence.

func _ready() -> void:
	var shots := ""
	var every := 1.0
	var crowd := 200
	var quit_after := 20.0
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			shots = arg.trim_prefix("--shots=")
		if arg.begins_with("--shot-every="):
			every = float(arg.trim_prefix("--shot-every="))
		if arg.begins_with("--crowd="):
			crowd = int(arg.trim_prefix("--crowd="))
		if arg.begins_with("--quit-after="):
			quit_after = float(arg.trim_prefix("--quit-after="))
	if shots.is_empty():
		push_error("corsair_summon_probe requires --shots=<absolute evidence directory>")
		get_tree().quit(1)
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var run: RunScene = load(RunScene.SCENE_PATH).instantiate()
	run.configure("henesys", 291, {"autopick": true, "use_flow": false, "perf": true,
		"shots_dir": shots, "shot_every": every, "quit_after": quit_after,
		"world_prepared": func(w: RunWorld) -> void:
			w.god = true
			w.set_job(522)
			w.wear_new_item(1492000)
			w.loadout.order.clear()
			for key: String in ["octopus", "gaviota"]:
				w.learn_skill(key)
				w.loadout.set_rank(key, 8)
				w.loadout.add_skill_mod(key, "damage", "mul", 0.01) # the crowd survives the whole capture
			for kind: MobKind in w.mob_kinds:
				kind.move_speed = 0.0
			# Stand on the floor nearest the bottom of the map; the crowd stands in front of the player on the same floor.
			var ground := w.fhm.nearest_floor_point(Vector2(w.player.pos.x, w.fhm.bounds().end.y))
			w.player.place(Vector2(ground.x, ground.y), w.fhm)
			w.update_view()
			for i in crowd:
				var mob_x := w.player.pos.x + 200.0 + float(i % 25) * 10.0
				var mob_fh := w.fhm.find_below(mob_x, ground.y - 5.0)
				if mob_fh < 0:
					continue
				var slot := w.spawn_mob(0, Vector2(mob_x, w.fhm.y_at(mob_fh, mob_x)), mob_fh, 1.0, false)
				if slot >= 0:
					w.swarm.hp[slot] = 100000
					w.swarm.max_hp[slot] = 100000
	})
	add_child(run)
