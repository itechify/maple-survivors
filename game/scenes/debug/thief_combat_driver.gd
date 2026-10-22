extends Node
## Thief combat/star evidence (#215), using the real cache and RunScene without save writes.
## --shots=<absolute evidence dir>. Diagnostic setup: direct job grants, rank 10 attacks, god mode, stationary durable
## mobs, disabled basic attack and held waves. Fixed ticks capture the actual cast/flight, including level-up ammo events.

const DT := 1.0 / 60.0
# tier C: diagnostic placements, ranks, timing and seeds only; no survivor tuning.
const SCENARIOS := {
	"claw_lucky_seven": {"job": 400, "path": "claw", "level": 10, "skill": "lucky_seven", "dx": 180.0, "ammo": 2070015},
	"dagger_double_stab": {"job": 400, "path": "dagger", "level": 10, "skill": "double_stab", "dx": 45.0, "ammo": 0},
	"assassin_drain_wolbi": {"job": 410, "path": "claw", "level": 30, "skill": "drain", "dx": 180.0, "ammo": 2070001},
	"assassin_lucky_wolbi": {"job": 410, "path": "claw", "level": 30, "skill": "lucky_seven", "dx": 180.0, "ammo": 2070001},
	"assassin_upgrade_mokbi": {"job": 410, "path": "claw", "level": 35, "skill": "lucky_seven", "dx": 180.0, "ammo": 2070002, "upgrade": true},
	"assassin_upgrade_ilbi": {"job": 410, "path": "claw", "level": 55, "skill": "lucky_seven", "dx": 180.0, "ammo": 2070006, "upgrade": true},
	"assassin_drain_ilbi": {"job": 410, "path": "claw", "level": 55, "skill": "drain", "dx": 180.0, "ammo": 2070006},
}

var run: RunScene
var shots := ""
var failed := false


func _ready() -> void:
	call_deferred("_drive")


func _drive() -> void:
	shots = String(SceneFlow.parse_flags(OS.get_cmdline_user_args()).get("shots", ""))
	if shots == "":
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(shots)
	var summary := {}
	for key: String in SCENARIOS:
		summary[key] = await _scenario(key)
	var file := FileAccess.open(shots.path_join("summary.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(summary, "\t"))
	file.close()
	get_tree().quit(1 if failed else 0)


func _scenario(key: String) -> Dictionary:
	var spec: Dictionary = SCENARIOS[key]
	if run != null:
		run.queue_free()
		await get_tree().process_frame
	run = (load(RunScene.SCENE_PATH) as PackedScene).instantiate()
	run.configure("henesys", 215, {"use_flow": false})
	add_child(run)
	run.set_process(false)
	var w := run.world
	w.god = true
	w.progression.level = 10
	w.change_job(400, String(spec.path))
	if int(spec.job) != 400:
		w.progression.level = 30
		w.change_job(int(spec.job))
	w.progression.level = int(spec.level) - 1 if spec.get("upgrade", false) else int(spec.level)
	w.pending_cards.clear()
	w.state = RunWorld.PLAYING
	w.loadout.order.clear()
	w.loadout.ranks.clear()
	w.loadout.version += 1
	w.learn_skill(String(spec.skill))
	w.loadout.set_rank(String(spec.skill), 10)
	w.refresh_player_stats()
	w.heal_fraction("mp", 1.0)
	w.heal_fraction("hp", 1.0)
	# Keep the equipment update, but omit the large diagnostic job/learn effects covering the avatar.
	run.handle_events(w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "equipment_changed"))
	var ammo_before := w.ammo_id()
	var upgrades := []
	if spec.get("upgrade", false):
		w._gain_exp(w.progression.exp_to_next())
		var events := w.drain_events()
		upgrades = events.filter(func(e: Dictionary) -> bool: return e.type == "ammo_upgraded")
		run.handle_events(upgrades) # show the real ammo notice without opening the diagnostic level-up card modal.
		w.progression.pop_front() # diagnostic: omit this level's card choice so the captured projectile can keep flying.
		w.pending_cards.clear()
		w.state = RunWorld.PLAYING
	var x := 400.0
	var f := w.fhm.find_below(x, 200.0)
	w.player.place(Vector2(x, w.fhm.y_at(f, x)), w.fhm)
	w.player.facing = 1
	for kind: MobKind in w.mob_kinds:
		kind.move_speed = 0.0
	var mx := x + float(spec.dx)
	var mf := w.fhm.find_below(mx, w.player.pos.y - 5.0)
	var m := w.spawn_mob(0, Vector2(mx, w.fhm.y_at(mf, mx)), mf, 10000.0, false)
	w.swarm.alpha[m] = 1.0
	w.basic.cooldown = 10000.0
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	run.handle_events(w.drain_events())
	# Settle camera/presentation without advancing waves or casting before capture.
	for frame in 90:
		run._present(DT)
		run.cam.update_camera(DT)
		await get_tree().process_frame
	var bullets := []
	for tick in 30:
		w.step(DT, MoveInput.new())
		if w.transfer_pending:
			w.advance_map()
		var events := w.drain_events()
		for slot in w.projectiles.capacity():
			if w.projectiles.active[slot] != 0:
				var path := String(w.visual_paths[w.projectiles.visual[slot]])
				if path not in bullets:
					bullets.append(path)
		run.handle_events(events)
		run._present(DT)
		run.cam.update_camera(DT)
		await get_tree().process_frame
		if tick in [7, 20]:
			RenderingServer.force_draw()
			var image := get_viewport().get_texture().get_image()
			var error := image.save_png(shots.path_join("%s_%s.png" % [key, "a" if tick == 7 else "b"]))
			failed = failed or error != OK
	var report := {"job": w.progression.job_id, "level": w.progression.level, "weapon": w.weapon_id(),
		"ammo_before": ammo_before, "ammo": w.ammo_id(), "ammo_upgrades": upgrades,
		"bullet_paths": bullets, "casts": w.runner.casts, "mob_hurt": w.swarm.hp[m] < w.swarm.max_hp[m],
		"warnings": Array(w.warnings), "missing": Array(run.library.missing), "avatar_missing": Array(run.avatar.missing)}
	failed = failed or w.ammo_id() != int(spec.ammo) or not report.mob_hurt \
		or not w.warnings.is_empty() or not run.library.missing.is_empty() or not run.avatar.missing.is_empty()
	if spec.get("upgrade", false):
		failed = failed or upgrades.size() != 1
	if int(spec.ammo) != 0:
		failed = failed or bullets != [Ammo.bullet_path(int(spec.ammo))]
	print("thief_combat_driver: ", key, " ", JSON.stringify(report))
	return report
