extends Node
## Tool-only M22 evidence (#402): diagnostic job 412 with a synthetic catalogue, ordinary hits grant poison/stun.
## Does not enable the unfinished Night Lord in shipped data. --job=412 --shots=<absolute evidence directory>.

func _ready() -> void:
	call_deferred("_drive")


func _drive() -> void:
	var args := SceneFlow.parse_flags(OS.get_cmdline_user_args())
	var shots := String(args.get("shots", ""))
	if shots == "":
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(shots)
	# tier C: diagnostic-only job and guaranteed grants, not survivor balance.
	DataRepo.patch = {"jobs_survivor": {"jobs": {"412": {"name": "Night Lord", "playable": true,
		"skill_pool": ["energy_bolt"], "starting_skill": "energy_bolt", "creation_weapon": 1472000,
		"weapon_families": ["claw"]}}}, "balance": {"status_bonuses": {
		"venomous_star": {"kind": "poison", "chance": 100, "time": 10, "level": 30},
		"stunning_avenger": {"kind": "stun", "chance": 100, "time": 10}}}}
	var run := (load(RunScene.SCENE_PATH) as PackedScene).instantiate() as RunScene
	run.configure("henesys", 402, {"use_flow": false, "autopick": true, "job": 412})
	add_child(run)
	DataRepo.patch = {}
	run.set_process(false)
	var w := run.world
	w.god = true
	w.loadout.order.clear()
	w.mob_kinds[0].move_speed = 0.0
	for n in 3:
		var x := w.player.pos.x + 160.0 + n * 70.0
		var fh := w.fhm.find_below(x, w.player.pos.y - 10.0)
		var slot := w.spawn_mob(0, Vector2(x, w.fhm.y_at(fh, x)), fh, 20.0, false)
		w.swarm.alpha[slot] = 1.0
		if n < 2:
			var id := "venomous_star" if n == 0 else "stunning_avenger"
			var st := w.loadout.stats("energy_bolt")
			st.damage_min = 1.0
			st.damage_max = 1.0
			st.damage_type = "fixed"
			st["status_grants"] = StatusBonus.resolve(w.loadout.status_bonuses, [id], 1)
			w.hit_mob(slot, st, -1)
	run.handle_events(w.drain_events())
	for tick in 30:
		run.advance_frame(1.0 / 60.0)
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(shots.path_join("status_bonus.png"))
	get_tree().quit()
