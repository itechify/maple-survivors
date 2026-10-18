extends Node
## Stunned-mob evidence on the real Henesys map and cache (#187): a row of mobs, the first two stunned, the last two
## free to walk. Saves stun_start.png, stun_mid.png (the stars still looping) and stun_end.png (the stun expired).
## MAPLE_SURVIVORS_CACHE=<cache with the stun cue> ISOLATE=<name> bash scripts/run.sh \
##   res://scenes/debug/stun_driver.tscn -- --shots=<abs evidence dir>

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
	run.configure("henesys_hg1", 60, {"use_flow": false, "autopick": true})
	add_child(run)
	run.set_process(false)
	var w := run.world
	w.god = true
	var slots: Array[int] = []
	for n in 4:
		var kind := n % w.mob_kinds.size()
		var x := w.player.pos.x + 90.0 + 60.0 * n
		var f := w.fhm.find_below(x, w.player.pos.y - 10.0)
		var slot := w.spawn_mob(kind, Vector2(x, w.fhm.y_at(f, x)), f, 1.0, false)
		w.swarm.alpha[slot] = 1.0
		slots.append(slot)
	for n in 2:
		w.swarm.apply_status(slots[n], "stun", {"time": 1.5}, w.events)
	run.handle_events(w.drain_events())
	var positions: Array = slots.map(func(s: int) -> Vector2: return w.swarm.pos(s))
	await _frames(0.25)
	await _shot("stun_start.png")
	await _frames(0.6)
	await _shot("stun_mid.png")
	await _frames(1.0)
	await _shot("stun_end.png")
	var moved: Array = []
	for n in slots.size():
		moved.append(w.swarm.pos(slots[n]).distance_to(positions[n]))
	var file := FileAccess.open(shots.path_join("summary.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"moved_px": moved, "stun_left": slots.map(
		func(s: int) -> float: return w.swarm.status_time(s, MobSwarm.STUN))}, "\t"))
	get_tree().quit()


func _frames(seconds: float) -> void:
	for i in roundi(seconds * 60.0):
		run.advance_frame(1.0 / 60.0)
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(shots.path_join(name))
