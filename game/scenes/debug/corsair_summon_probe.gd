extends Node
## Tool-only Corsair summon probe (spec #384 C6 #390): --shots=<absolute evidence dir> [--shot-every=<s>] [--crowd=<n>] [--quit-after=<s>]
## [--skills=<csv of skill keys>] [--ship] [--break-hull-at=<s>].
## A Corsair (job 522 stand-in, Pistol worn, god mode) with the `--skills` (default Octopus and Gaviota) at rank 8 on Henesys and a
## crowd of standing, near-unkillable mobs in front of it (200 by default), so the planted octopus's balls and the bird's dive can be
## looked at. `--ship` starts the Battleship form (hull and mount; the crowd still stands in front) for the mounted frame cost;
## `--break-hull-at=<s>` lands a hit bigger than the hull then, so the broken-hull frame (bar gone, ship gone) is on a shot.
## Needs Skill.wz/521.img in the cache. Never saves a character; diagnostic art and cost evidence, not balance evidence.

var _run_scene: RunScene
var _ball_shots := 0
var _last_ball_shot := -1.0


## A shot (`ball_<n>.png`, at most six, 0.2 s apart) whenever a turret ball is in the air: the frames the once-a-second t<s> shots miss.
func _process(_delta: float) -> void:
	if _run_scene == null or _run_scene.world == null or _ball_shots >= 6:
		return
	var w := _run_scene.world
	if w.runner.summons.turret.ball_count() > 0 and w.time - _last_ball_shot >= 0.2:
		_last_ball_shot = w.time
		_ball_shots += 1
		_run_scene._request_shot("ball_%d.png" % _ball_shots)


func _ready() -> void:
	var shots := ""
	var every := 1.0
	var crowd := 200
	var quit_after := 20.0
	var skills: Array = ["octopus", "gaviota"]
	var ship := false
	var break_at := -1.0
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			shots = arg.trim_prefix("--shots=")
		if arg.begins_with("--shot-every="):
			every = float(arg.trim_prefix("--shot-every="))
		if arg.begins_with("--crowd="):
			crowd = int(arg.trim_prefix("--crowd="))
		if arg.begins_with("--quit-after="):
			quit_after = float(arg.trim_prefix("--quit-after="))
		if arg.begins_with("--skills="):
			skills = arg.trim_prefix("--skills=").split(",", false)
		if arg == "--ship":
			ship = true
		if arg.begins_with("--break-hull-at="):
			break_at = float(arg.trim_prefix("--break-hull-at="))
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
			for key: String in skills:
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
	_run_scene = run
	if ship or break_at >= 0.0:
		_ship_script(run, ship, break_at)


## Starts the Battleship once the world exists and, at `break_at` run seconds, lands a hit larger than the hull.
func _ship_script(run: RunScene, ship: bool, break_at: float) -> void:
	await get_tree().process_frame
	var w := run.world
	if ship:
		w.learn_skill("battleship")
		w.loadout.set_rank("battleship", 1)
		w.runner.forms.start(w, "battleship", w.loadout.stats("battleship"))
	if break_at < 0.0:
		return
	while w.time < break_at:
		await get_tree().process_frame
	_run_scene._request_shot("hull_before.png")
	await get_tree().create_timer(0.1).timeout
	w.god = false # take_hit ignores a god-mode hit; 60% of max HP is more than the rank-1 hull (20%) and not lethal
	var dealt := w.take_hit(float(w.player_state.max_hp) * 0.6, false, "", w.player.pos + Vector2(-60, 0),
		{"accuracy": 1.0e9, "boss": true, "source_kind": "attack"})
	w.god = true
	print("corsair_summon_probe t=%.1f hull-breaking hit: %d reached HP" % [w.time, dealt])
	await get_tree().create_timer(0.3).timeout
	_run_scene._request_shot("hull_broken.png")
