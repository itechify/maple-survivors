extends Node
## Boss Poison 125 and poison mist 131 evidence on the real Henesys map and cache (#459): a boss forced to cast only one skill
## (diagnostic, the same replacement the render tests make), the character standing in or out of its box, and a screenshot at
## each step. `--mode=mist` (default; `--elem=I|S` picks the level's element) saves mist_before, mist_cast (the mist drawn, the
## character outside), mist_inside (Slow or Poison on the character) and mist_after; `--mode=poison` saves poison_before,
## poison_hit (the character poisoned, HP dropping) and poison_after. summary.json holds the sim numbers.
## MAPLE_SURVIVORS_CACHE=<cache> ISOLATE=<name> bash scripts/run.sh res://scenes/debug/hazard_driver.tscn -- \
##   --shots=<abs evidence dir> [--mode=mist|poison] [--elem=I|S]

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
	# Uncapped, like the flow driver: an unfocused window is otherwise throttled to about 1 frame per second.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var mode := String(args.get("mode", "mist"))
	var elem := String(args.get("elem", "I"))
	run = (load(RunScene.SCENE_PATH) as PackedScene).instantiate()
	run.configure("henesys", 22, {"use_flow": false})
	add_child(run)
	run.set_process(false)
	var lib := run.library
	var data := run.data.duplicate(true)
	data.balance.bosses.teleport_stall = 10000.0
	data.stages.stages.henesys.maps[0].boss = {"mob_id": 2220000, "time": 0.0}
	for keyframe: Dictionary in data.stages.stages.henesys.keyframes:
		keyframe.rate = 0
		keyframe.max_alive = 0
	var setup := DataRepo.build_setup(data, "henesys", 22, Vector2(800, 600),
		func(p: String) -> Dictionary: return lib.img(p).root if lib.img(p) != null else {}, lib.mob_root)
	setup.mob_imgs[2220000] = setup.mob_imgs[2220000].duplicate(true)
	setup.mob_imgs[2220000].info.speed = -100.0
	setup.mob_skill_img = setup.mob_skill_img.duplicate(true)
	if mode == "poison":
		setup.mob_imgs[2220000].info.skill = {"0": {"skill": 125.0, "level": 1.0, "action": 1.0, "effectAfter": 0.0}}
		setup.mob_skill_img["125"].level["1"].interval = 3.0
		setup.mob_skill_img["125"].level["1"].prop = 100.0
		setup.mob_skill_img["125"].level["1"].time = 8.0
	else:
		setup.mob_imgs[2220000].info.skill = {"0": {"skill": 131.0, "level": 7.0, "action": 1.0, "effectAfter": 0.0}}
		setup.mob_skill_img["131"].level["7"].interval = 3.0
		setup.mob_skill_img["131"].level["7"].prop = 100.0
		setup.mob_skill_img["131"].level["7"].elemAttr = elem
	run.world = RunWorld.new(setup)
	var w := run.world
	w.god = mode != "poison"
	w.balance.regen = {"interval": 100000.0, "hp": 0.0}
	await _frames(1)
	var boss := int(w.bosses.records[0].slot)
	var base := w.swarm.pos(boss)
	summary = {"mode": mode, "elem": elem}
	if mode == "poison":
		_stand(w, base.x - 90.0)
		await _frames(1)
		await _shot("poison_before.png")
		await _until(func() -> bool: return not w.player_state.get("poison", {}).is_empty(), 5.0)
		await _frames(0.3)
		summary["fx_active_at_start"] = run.fx.active_count()
		summary["status_fx"] = run._status_fx.keys()
		await _shot("poison_start.png")
		await _frames(3.0)
		await _shot("poison_hit.png")
		summary["hp_after_3s"] = int(w.player_state.hp)
		w.swarm.despawn(boss)
		await _frames(7.0)
		summary["hp_end"] = int(w.player_state.hp)
		summary["poisoned_end"] = not w.player_state.get("poison", {}).is_empty()
		await _shot("poison_after.png")
	else:
		_stand(w, base.x - 260.0)
		await _frames(1)
		await _shot("mist_before.png")
		await _until(func() -> bool: return w.hazards.active_count() > 0, 5.0)
		await _frames(1.2)
		summary["rect"] = w.hazards.rect(0)
		await _shot("mist_cast.png")
		var rect := w.hazards.rect(0)
		_stand(w, rect.get_center().x)
		await _frames(1.0)
		await _shot("mist_inside.png")
		summary["slowed"] = not w.player_state.get("slow", {}).is_empty()
		summary["poisoned"] = not w.player_state.get("poison", {}).is_empty()
		w.swarm.despawn(boss)
		_stand(w, rect.position.x - 200.0)
		await _frames(10.0)
		summary["hazards_after"] = w.hazards.active_count()
		await _shot("mist_after.png")
	summary["hazards_cast"] = w.hazards.cast_count
	summary["hazard_seconds"] = w.hazards.seconds
	summary["missing"] = Array(lib.missing)
	var file := FileAccess.open(shots.path_join("summary.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(summary, "\t"))
	get_tree().quit()


func _stand(w: RunWorld, x: float) -> void:
	var f := w.fhm.find_below(x, w.player.pos.y - 10.0)
	w.player.place(Vector2(x, w.fhm.y_at(f, x)), w.fhm)
	w.update_view()


func _frames(seconds: float) -> void:
	for i in maxi(1, roundi(seconds * 60.0)):
		run.advance_frame(1.0 / 60.0)
		await get_tree().process_frame


func _until(done: Callable, limit: float) -> void:
	for i in roundi(limit * 60.0):
		if done.call():
			return
		await _frames(1.0 / 60.0)


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(shots.path_join(name))
	# The whole frame at 3x (the window is small and the status art only about 35 px).
	var zoom := image.duplicate() as Image
	zoom.resize(image.get_width() * 3, image.get_height() * 3, Image.INTERPOLATE_NEAREST)
	zoom.save_png(shots.path_join(name.replace(".png", "_zoom.png")))
