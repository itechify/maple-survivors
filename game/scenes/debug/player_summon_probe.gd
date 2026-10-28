extends Node
## Tool-only Elquines art/performance probe: --shots=<absolute evidence dir> [--without-summon] [--skill=hawk|phoenix].
## `--skill=hawk|phoenix` (spec #332 B6, needs Skill.wz/311.img and 312.img in the cache) runs a physical follower defined
## here as a diagnostic of the same shape the Bowmaster definitions will have, on a Bowmaster stand-in (job 312, held bow).
## Never saves a character.

func _ready() -> void:
	var shots := ""
	var enabled := true
	var follower := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			shots = arg.trim_prefix("--shots=")
		if arg.begins_with("--skill="):
			follower = arg.trim_prefix("--skill=")
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
			w.loadout.order.clear()
			if enabled and follower != "":
				_learn_follower(w, follower)
			elif enabled:
				w.learn_skill("elquines")
				w.loadout.set_rank("elquines", 8)
				w.loadout.add_skill_mod("elquines", "damage", "mul", 0.01)
			if follower != "":
				w.loadout.add_skill_mod("probe_" + follower, "damage", "mul", 0.01)
			# Diagnostic targets: real mob art, still standing, high HP; this is not survival/balance evidence.
			for kind: MobKind in w.mob_kinds:
				kind.move_speed = 0.0
			for i in 200:
				var slot := w.spawn_mob(0, w.player.pos + Vector2(70 + i % 20 * 5, 0), w.player.fh, 1.0, false)
				if slot >= 0:
					w.swarm.hp[slot] = 100000
					w.swarm.max_hp[slot] = 100000
	})
	add_child(run)


## A diagnostic physical follower of the Hawk's / Phoenix's shape (GAME_DESIGN 7.44) learned at rank 8 on a bow user.
func _learn_follower(w: RunWorld, which: String) -> void:
	var hawk := which == "hawk"
	var book := "311" if hawk else "312"
	var lib := AssetLibrary.get_default()
	w.book.skill_imgs[book] = lib.img("Skill.wz/%s.img" % book).root
	var id := 3111005 if hawk else 3121006
	var key := "probe_" + which
	var base := "Skill.wz/%s.img/skill/%d" % [book, id]
	w.book.defs[key] = {"skill_id": id, "book": book, "job": int(book), "kind": "summon", "slot": "active",
		"name": which, "damage": "physical", "cooldown": 30.0, "action": "alert2", "action_time": 0.8,
		"cast": {"rule": "summon"}, "hit": base + "/hit/0", "effect": "", "ball": "", "rotate": false,
		"summon": {"path": base + "/summon", "attack": "attack1", "move": "fly", "hover": 80.0 if hawk else 70.0,
			"follow_speed": 220.0, "follow_distance": 70.0, "teleport_distance": 600.0, "attack_interval": 1.6 if hawk else 3.0,
			"watk_field": "pad", "settle": true},
		"sounds": {"use": "Sound.wz/Skill.img/%d/Use" % id, "summon": "Sound.wz/Skill.img/%d/Summon" % id}}
	if hawk:
		w.book.defs[key]["on_hit"] = {"status": "stun", "chance_field": "prop", "duration": 1.5}
	else:
		w.book.defs[key]["element"] = "f"
	w.book._by_id[id] = key
	w.set_job(312)
	w.wear_new_item(1452051)
	w.learn_skill(key)
	w.loadout.set_rank(key, 8)
