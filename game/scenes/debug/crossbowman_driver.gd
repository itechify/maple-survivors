extends Node
## Crossbowman evidence (#203): real RunScene casts, piercing line, ranged Final Attack and ammo tiers.
## Fixed-tick diagnostic targets, no player saves. Run with --shots=<absolute evidence directory>.

var run: RunScene
var shots := ""
var summary := {}
var line_hits: Array = []


func _ready() -> void:
	call_deferred("_drive")


func _drive() -> void:
	shots = String(SceneFlow.parse_flags(OS.get_cmdline_user_args()).get("shots", ""))
	if shots == "":
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(shots)
	await _new_run()
	var w := run.world
	w.learn_skill("iron_arrow")
	w.loadout.set_rank("iron_arrow", 30)
	w.refresh_player_stats()
	for i in 7:
		_target(90.0 + i * 30.0, true)
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	w.runner.step(1.0 / 60.0, w)
	run.handle_events(w.drain_events())
	await _flight_frames(7)
	await _shot("iron_arrow_line.png")
	await _flight_frames(14)
	await _shot("iron_arrow_six_hits.png")
	summary.iron_arrow = {"hits": line_hits, "casts": w.runner.casts, "missing": Array(run.library.missing)}
	await _new_run()
	w = run.world
	w.learn_skill("power_knockback_crossbow")
	w.loadout.set_rank("power_knockback_crossbow", 20)
	w.refresh_player_stats()
	for dx: float in [-100, -60, 60, 100, 125]:
		var slot := _target(dx)
		w.swarm.steady[slot] = 0
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	w.runner.step(1.0 / 60.0, w)
	run.handle_events(w.drain_events())
	await _frames(0.12)
	await _shot("power_knockback_crossbow.png")
	summary.power_knockback = {"casts": w.runner.casts, "weapon": w.weapon_id(), "missing": Array(run.library.missing)}
	await _new_run()
	w = run.world
	w.learn_skill("final_attack_crossbow")
	w.loadout.set_rank("final_attack_crossbow", 30)
	w.refresh_player_stats()
	var target := _target(210)
	var followup := false
	for trial in 30:
		w.hit_mob(target, {"skill": "basic_attack", "damage_type": "physical", "damage_min": 1,
			"damage_max": 1, "crit": 0, "crit_mult": 1.5}, -1)
		w.step(1.0 / 60.0, MoveInput.new())
		var events := w.drain_events()
		followup = events.any(func(e: Dictionary) -> bool: return e.type == "ammo_shot")
		run.handle_events(events)
		if followup:
			break
	await _frames(0.08)
	await _shot("final_attack_arrow.png")
	summary.final_attack = {"followup": followup, "ammo": w.ammo_id(), "missing": Array(run.library.missing)}
	for level in [30, 40, 50]:
		await _new_run(level - 1)
		w = run.world
		w.progression.level = level
		w.refresh_player_stats()
		var events := w.drain_events()
		var notices := events.filter(func(e: Dictionary) -> bool: return e.type == "ammo_upgraded")
		run.handle_events(events)
		w.learn_skill("arrow_blow")
		_target(220, true)
		w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
		await _frames(0.16)
		await _shot("ammo_lv%d.png" % level)
		summary["ammo_lv%d" % level] = {"ammo": w.ammo_id(), "notices": notices, "missing": Array(run.library.missing)}
	await _new_run()
	w = run.world
	for key: String in ["crossbow_mastery", "final_attack_crossbow", "crossbow_booster", "power_knockback_crossbow", "iron_arrow"]:
		w.learn_skill(key)
	w.refresh_player_stats()
	run.handle_events(w.drain_events())
	run.toggle_window("skill")
	var skill := run.ui_windows.find_window("skill") as SkillWindow
	skill.select_tab(2)
	await _frames(0.2)
	await _shot("skill_crossbowman.png")
	var file := FileAccess.open(shots.path_join("summary.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(summary, "\t"))
	get_tree().quit()


func _new_run(level := 40) -> void:
	if run != null:
		run.queue_free()
		await get_tree().process_frame
	run = (load(RunScene.SCENE_PATH) as PackedScene).instantiate()
	run.configure("henesys_hg1", 203, {"use_flow": false, "autopick": true, "job": 320})
	add_child(run)
	run.set_process(false)
	var w := run.world
	w.god = true
	w.progression.level = level
	w.change_job(300, "bow")
	w.change_job(320)
	w.loadout.order.clear()
	w.heal_fraction("mp", 1.0)
	w.basic.cooldown = 1000.0
	for kind: MobKind in w.mob_kinds:
		kind.move_speed = 0
	var f := w.fhm.find_below(-150.0, 100.0)
	w.player.place(Vector2(-150, w.fhm.y_at(f, -150)), w.fhm)
	w.player.facing = 1
	w.update_view()
	run.handle_events(w.drain_events().filter(func(e: Dictionary) -> bool: return e.type != "job_changed"))
	await _frames(0.05)


func _target(dx: float, align_hand := false) -> int:
	var w := run.world
	var x := w.player.pos.x + dx
	var f := w.fhm.find_below(x, w.player.pos.y - 10)
	var slot := w.spawn_mob(0, Vector2(x, w.fhm.y_at(f, x)), f, 10000.0, false)
	if align_hand:
		w.swarm.y[slot] = w.cast_origin().y - w.mob_kinds[0].hitbox.get_center().y
	w.swarm.alpha[slot] = 1
	w.swarm.steady[slot] = 1
	run.handle_events(w.drain_events())
	return slot


func _flight_frames(count: int) -> void:
	for tick in count:
		run.world.projectiles.step(1.0 / 60.0, run.world.swarm, run.world.mob_grid, run.world.events)
		var events := run.world.drain_events()
		line_hits.append_array(events.filter(func(e: Dictionary) -> bool: return e.type == "mob_hit"))
		run.handle_events(events)
		# Freeze target physics for this diagnostic line; advance real projectile and presentation clocks once.
		run._present(1.0 / 60.0)
		await get_tree().process_frame


func _frames(seconds: float) -> void:
	for tick in roundi(seconds * 60):
		run.advance_frame(1.0 / 60.0)
		await get_tree().process_frame


func _shot(filename: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(shots.path_join(filename))
