extends Node
## #214 presentation evidence: real Bandit/cache, durable nearby mobs, canonical Savage Blow and successful Steal.
## ISOLATE=s167-t214-visual bash scripts/run.sh res://scenes/debug/bandit_attack_driver.tscn -- --shots=<evidence dir>
## Only this diagnostic disables waves/collection and holds simulation between casts; no saves or balance edits.

const DT := 1.0 / 60.0

var run: RunScene
var shots := ""


func _ready() -> void:
	call_deferred("_drive")


func _drive() -> void:
	shots = String(SceneFlow.parse_flags(OS.get_cmdline_user_args()).get("shots", ""))
	if shots == "":
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(shots)
	run = (load(RunScene.SCENE_PATH) as PackedScene).instantiate()
	run.configure("henesys", 214, {"use_flow": false})
	add_child(run)
	run.set_process(false)
	run.fx.set_process(false)
	run.fx_back.set_process(false)
	var w := run.world
	if w == null:
		get_tree().quit(2)
		return
	w.god = true
	w.change_job(400, "dagger")
	w.progression.level = 30
	w.change_job(420)
	w.pending_cards.clear()
	w.state = RunWorld.PLAYING
	w.loadout.ranks.clear()
	w.loadout.order.clear()
	w.loadout.version += 1
	# Place everyone on the open Henesys ground floor; high HP keeps six hits from hiding the target in DIE.
	var x := 400.0
	var f := w.fhm.find_below(x, 200.0)
	w.player.place(Vector2(x, w.fhm.y_at(f, x)), w.fhm)
	var mob_x := x + 65.0
	var mf := w.fhm.find_below(mob_x, w.player.pos.y - 5.0)
	var m := w.spawn_mob(int(w.kind_of_id[1110100]), Vector2(mob_x, w.fhm.y_at(mf, mob_x)), mf, 10000, false)
	w.swarm.alpha[m] = 1.0
	w.upgrades.apply("savage_blow_new", w)
	w.loadout.set_rank("savage_blow", 30)
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	run.handle_events(w.drain_events())
	await _present(1.5)
	w.runner.step(DT, w)
	w._write_player_state(0.0)
	var savage_events := w.drain_events()
	run.handle_events(savage_events)
	run.hud.push_notice("bandit_probe", "Savage Blow: 6 hits with the Reef Claw", 6.0)
	await _present(0.30)
	await _shot("savage_blow.png")
	await _present(1.5)
	# Keep Savage Blow owned for the HUD, but hold its cooldown while showing Steal alone.
	w.runner.cooldowns["savage_blow"] = 999.0
	w.upgrades.apply("steal_new", w)
	w.loadout.set_rank("steal", 30)
	var attempts := 0
	var steal_events: Array = []
	while w.swarm.stolen[m] == 0 and attempts < 100:
		attempts += 1
		w.start_action("", 0.0)
		w.runner.cooldowns["steal"] = 0.0
		w.runner.step(DT, w)
		steal_events = w.drain_events()
	w._write_player_state(0.0)
	run.handle_events(steal_events)
	run.hud.push_notice("bandit_probe", "Steal succeeded: one extra drop from this living monster", 6.0)
	# Land the real dropped item without allowing the magnet to collect it before the screenshot.
	var ignored: Array = []
	for tick in 40:
		w.pickups.step(DT, w.player.pos - Vector2(1000, 0), 0.0, w.fhm, ignored)
	await _present(0.16)
	await _shot("steal_success.png")
	var report := {"savage_hits": savage_events.filter(func(e: Dictionary) -> bool:
		return e.type == "mob_hit" and e.skill == "savage_blow").size(),
		"steal_attempts": attempts, "stolen": w.swarm.stolen[m], "mob_alive": w.swarm.is_live(m),
		"extra_drops": steal_events.filter(func(e: Dictionary) -> bool: return e.type == "pickup_spawned").size(),
		"player_pos": [w.player.pos.x, w.player.pos.y], "camera_pos": [run.cam.global_position.x, run.cam.global_position.y],
		"warnings": Array(w.warnings), "missing": Array(run.library.missing), "avatar_missing": Array(run.avatar.missing)}
	var file := FileAccess.open(shots.path_join("summary.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	get_tree().quit(0 if report.savage_hits == 6 and report.stolen == 1 and report.extra_drops == 1 else 1)


func _present(seconds: float) -> void:
	for frame in roundi(seconds * 60.0):
		run._present(DT)
		run.cam.update_camera(DT)
		run.fx.advance(DT)
		run.fx_back.advance(DT)
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(shots.path_join(name))
