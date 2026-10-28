extends Node
## First-job Bowman evidence (#199): the real Skill window and each attack with each weapon on Henesys (the job window
## is gone with job advancement, #284).
## Uses a private asset cache, fixed ticks and motionless targets; never writes player saves.
## MAPLE_SURVIVORS_CACHE=<cache> ISOLATE=s166-t199-visual bash scripts/run.sh \
##   res://scenes/debug/bowman_driver.tscn -- --shots=<absolute evidence dir>

const RF := preload("res://tests/fixtures/run_fixtures.gd")

var run: RunScene
var shots := ""
var summary := {}


func _ready() -> void:
	call_deferred("_drive")


func _drive() -> void:
	var args := SceneFlow.parse_flags(OS.get_cmdline_user_args())
	shots = String(args.get("shots", ""))
	if shots == "":
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(shots)
	for family: String in ["bow", "crossbow"]:
		for key: String in ["arrow_blow", "bow_double_shot"]:
			await _scenario(family, key)
	await _new_run()
	var w := run.world
	w.progression.level = 20
	RF.as_job(w, 300, "bow")
	for key: String in ["blessing_of_amazon", "critical_shot", "eye_of_amazon", "focus", "arrow_blow", "bow_double_shot"]:
		w.learn_skill(key)
	w.refresh_player_stats()
	run.handle_events(w.drain_events())
	await _frames(0.1)
	run.toggle_window("skill")
	await _frames(0.5)
	await _shot("skill_window_top.png")
	var skill := run.ui_windows.find_window("skill") as SkillWindow
	skill.scroll = 2
	skill.queue_redraw()
	await _frames(0.2)
	await _shot("skill_window_bottom.png")
	summary["missing"] = Array(run.library.missing)
	var file := FileAccess.open(shots.path_join("summary.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(summary, "\t"))
	get_tree().quit()


func _new_run() -> void:
	if run != null:
		run.queue_free()
		await get_tree().process_frame
	run = (load(RunScene.SCENE_PATH) as PackedScene).instantiate()
	run.configure("henesys", 199, {"use_flow": false, "autopick": true})
	add_child(run)
	run.set_process(false)
	run.world.god = true


func _scenario(family: String, key: String) -> void:
	await _new_run()
	var w := run.world
	w.progression.level = 20
	RF.as_job(w, 300, family)
	w.loadout.order.clear()
	w.learn_skill(key)
	w.loadout.set_rank(key, 10)
	w.refresh_player_stats()
	w.heal_fraction("mp", 1.0)
	for kind: MobKind in w.mob_kinds:
		kind.move_speed = 0.0
	# Fixed flat ground clear of the west portal's looping beam, with both targets inside the camera.
	var f := w.fhm.find_below(-150.0, 100.0)
	w.player.place(Vector2(-150.0, w.fhm.y_at(f, -150.0)), w.fhm)
	w.player.facing = 1
	w.update_view()
	run.handle_events(w.drain_events())
	await _frames(0.1)
	for dx: float in [120.0, 240.0]:
		var x := w.player.pos.x + dx
		var floor_id := w.fhm.find_below(x, w.player.pos.y - 10)
		var slot := w.spawn_mob(0, Vector2(x, w.fhm.y_at(floor_id, x)), floor_id, 200.0, false)
		w.swarm.alpha[slot] = 1.0
	run.handle_events(w.drain_events())
	await _frames(0.1)
	await _shot(family + "_" + key + "_shot.png")
	await _frames(0.3)
	await _shot(family + "_" + key + "_hit.png")
	summary[family + "_" + key] = {"casts": w.runner.casts, "weapon": w.weapon_id(), "ammo": w.ammo_id(),
		"missing": Array(run.library.missing)}


func _frames(seconds: float) -> void:
	for tick in roundi(seconds * 60):
		run.advance_frame(1.0 / 60.0)
		await get_tree().process_frame


func _shot(filename: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(shots.path_join(filename))
