extends Node
## Hunter #202 visual evidence: real cache, stationary diagnostic targets, fixed ticks, no player saves.
## Run with private cache through scripts/run.sh res://scenes/debug/hunter_driver.tscn -- --shots=<evidence dir>.

var run: RunScene
var shots := ""
var summary := {}


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
	w.learn_skill("power_knockback_bow")
	w.loadout.set_rank("power_knockback_bow", 20)
	w.refresh_player_stats()
	var mobs: Array[int] = []
	for dx in [-90, 70, 110]:
		mobs.append(_mob(dx))
	w.loadout.order.clear()
	await _frames(1.0 / 60.0)
	await _shot("power_knockback_before.png")
	w.loadout.order.append("power_knockback_bow")
	await _frames(0.05)
	await _shot("power_knockback.png")
	summary["knockback"] = mobs.map(func(m: int) -> float: return w.swarm.x[m] - w.player.pos.x)
	await _new_run()
	w = run.world
	w.learn_skill("arrow_bomb")
	w.loadout.set_rank("arrow_bomb", 30)
	w.refresh_player_stats()
	mobs.clear()
	for dx in [100, 130, 160, 190, 220, 245]:
		mobs.append(_mob(dx))
	await _frames(0.05)
	await _shot("arrow_bomb_flight.png")
	await _frames(0.23)
	await _shot("arrow_bomb_blast.png")
	summary["bomb_stunned"] = mobs.map(func(m: int) -> float: return w.swarm.status_time(m, MobSwarm.STUN))
	# Let the canonical blast finish without another cast hiding the stun stars.
	w.loadout.order.clear()
	await _frames(1.60)
	await _shot("arrow_bomb_stun.png")
	for row: Array in [[30,2060001,"bronze"],[40,2060002,"steel"],[50,2060003,"red"]]:
		await _new_run(int(row[0]))
		w = run.world
		w.learn_skill("final_attack_bow")
		w.loadout.set_rank("final_attack_bow", 30)
		w.refresh_player_stats()
		var target := _mob(240)
		var proc := false
		for attempt in 30:
			w.hit_mob(target, w.loadout.stats("arrow_blow"), -1)
			w.step(1.0 / 60.0, MoveInput.new())
			if w.transfer_pending:
				w.advance_map()
			var events := w.drain_events()
			proc = events.any(func(e: Dictionary) -> bool: return e.type == "ammo_shot")
			run.handle_events(events)
			if proc:
				break
		assert(proc)
		assert(w.ammo_id() == int(row[1]))
		await _frames(0.12)
		await _shot("final_attack_" + String(row[2]) + ".png")
		summary[String(row[2])] = {"ammo": w.ammo_id(), "final_attack": proc}
	await _new_run()
	w = run.world
	for key: String in ["bow_mastery", "final_attack_bow", "bow_booster", "power_knockback_bow", "arrow_bomb"]:
		w.learn_skill(key)
	w.refresh_player_stats()
	run.handle_events(w.drain_events())
	run.toggle_window("skill")
	var skill := run.ui_windows.find_window("skill") as SkillWindow
	skill.tab = 2
	skill.queue_redraw()
	await _frames(0.1)
	await _shot("hunter_skill_window.png")
	skill.scroll = 1
	skill.queue_redraw()
	await _frames(0.1)
	await _shot("hunter_skill_window_bottom.png")
	var ids: Array = w.equipment.inventory.map(func(item: Dictionary) -> int: return int(item.id))
	assert(w.equip_item(ids.find(1462001)) == "")
	run.handle_events(w.drain_events())
	skill.queue_redraw()
	await _frames(0.1)
	await _shot("hunter_crossbow_grey.png")
	summary["missing"] = Array(run.library.missing)
	var file := FileAccess.open(shots.path_join("summary.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(summary, "\t"))
	get_tree().quit()


func _new_run(level := 30) -> void:
	if run != null:
		summary["missing_previous"] = summary.get("missing_previous", []) + Array(run.library.missing)
		run.queue_free()
		await get_tree().process_frame
	run = (load(RunScene.SCENE_PATH) as PackedScene).instantiate()
	run.configure("henesys", 202, {"use_flow": false, "autopick": true})
	add_child(run)
	run.set_process(false)
	var w := run.world
	w.god = true
	w.progression.level = level
	w.change_job(300, "bow")
	w.change_job(310)
	w.loadout.order.clear()
	w.basic = BasicAttack.new({}, {})
	for kind: MobKind in w.mob_kinds:
		kind.move_speed = 0
	var f := w.fhm.find_below(-150.0, 100.0)
	w.player.place(Vector2(-150.0, w.fhm.y_at(f, -150.0)), w.fhm)
	w.player.facing = 1
	w.update_view()
	run.handle_events(w.drain_events().filter(func(e: Dictionary) -> bool: return e.type != "job_changed"))
	await _frames(0.05)


func _mob(dx: float) -> int:
	var w := run.world
	var x := w.player.pos.x + dx
	var f := w.fhm.find_below(x, w.player.pos.y - 10)
	var slot := w.spawn_mob(0, Vector2(x, w.fhm.y_at(f, x)), f, 10000.0, false)
	w.swarm.alpha[slot] = 1
	run.handle_events(w.drain_events())
	return slot


func _frames(seconds: float) -> void:
	for tick in roundi(seconds * 60):
		run.advance_frame(1.0 / 60.0)
		await get_tree().process_frame


func _shot(filename: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(shots.path_join(filename))
