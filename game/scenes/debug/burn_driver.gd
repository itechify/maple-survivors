extends Node
## Burning-monster evidence on the real Henesys map and cache (#337): a row of one kind of mob standing still, the first two burning. Saves
## burn_tint.png (no cue art configured: the orange fallback tint), then, with --cue=<Skill.wz path>, burn_cue.png (that
## animation drawn on the burning monsters) and burn_end.png (the burn expired). Applies the burn through apply_status with
## a pulse of 5, so it needs no burning skill.
## ISOLATE=<name> bash scripts/run.sh res://scenes/debug/burn_driver.tscn -- --shots=<abs evidence dir> [--cue=<path>]

var run: RunScene
var shots := ""


func _ready() -> void:
	call_deferred("_drive")


func _drive() -> void:
	var args := SceneFlow.parse_flags(OS.get_cmdline_user_args())
	shots = String(args.get("shots", ""))
	if shots == "":
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(shots)
	run = (load(RunScene.SCENE_PATH) as PackedScene).instantiate()
	run.configure("henesys", 60, {"use_flow": false, "autopick": true})
	add_child(run)
	run.set_process(false)
	var w := run.world
	w.god = true
	var slots: Array[int] = []
	w.mob_kinds[0].move_speed = 0.0 # one kind standing still: burning and unburnt monsters compare side by side
	for n in 4:
		var kind := 0
		var x := w.player.pos.x + 90.0 + 70.0 * n
		var f := w.fhm.find_below(x, w.player.pos.y - 10.0)
		var slot := w.spawn_mob(kind, Vector2(x, w.fhm.y_at(f, x)), f, 20.0, false)
		w.swarm.alpha[slot] = 1.0
		slots.append(slot)
	for n in 2:
		w.swarm.apply_status(slots[n], "burn", {"time": 3.0, "pulse": 5, "skill": "inferno"}, w.events)
	run.handle_events(w.drain_events())
	await _frames(0.5)
	await _shot("burn_tint.png")
	var cue := String(args.get("cue", ""))
	if cue != "":
		for mr in run.mob_renderers:
			mr.burn_cue_path = cue
		await _frames(0.3)
		await _shot("burn_cue.png")
	await _frames(3.0)
	await _shot("burn_end.png")
	var file := FileAccess.open(shots.path_join("summary.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"burn_dealt": w.swarm.burn_dealt, "cue": cue,
		"burn_left": slots.map(func(s: int) -> float: return w.swarm.status_time(s, MobSwarm.BURN))}, "\t"))
	get_tree().quit()


func _frames(seconds: float) -> void:
	for i in roundi(seconds * 60.0):
		run.advance_frame(1.0 / 60.0)
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(shots.path_join(name))
