extends Node
## Pet drawing probe (spec #34, ticket #120): each curated species standing, walking right and left, jumping and
## hanging on a rope, in a Henesys round and in the Free Market, on the real map and art. Fixed ticks, scripted input.
## Saves a full frame and a 3x crop around the player per pose, plus summary.json (failures, missing assets).
##   ISOLATE=s34-120 MAPLE_SURVIVORS_CACHE=<cache> bash scripts/run.sh res://scenes/debug/pet_driver.tscn -- \
##     --shots=<abs evidence dir> [--species=5000000,5000001,5000002] [--where=round,hub]
## Saves only under --shots (the Free Market part uses driver_save.json there), never the player's save.

const DT := 1.0 / 60.0
const SPECIES := [5000000, 5000001, 5000002]
const CROP := Vector2i(300, 190)  # logical px around the player
const CROP_SCALE := 3

var shots := ""
var failures: Array[String] = []
var missing: Array[String] = []


func _ready() -> void:
	call_deferred("_drive")


func _drive() -> void:
	var args := SceneFlow.parse_flags(OS.get_cmdline_user_args())
	shots = String(args.get("shots", ""))
	if shots == "":
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(shots)
	var species: Array = SPECIES
	if args.has("species"):
		species = Array(String(args.species).split(",")).map(func(s: String) -> int: return int(s))
	var where := String(args.get("where", "round,hub")).split(",")
	for id: int in species:
		if "round" in where:
			await _round(id)
		if "hub" in where:
			await _hub(id)
	var file := FileAccess.open(shots.path_join("summary.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"failures": failures, "missing": missing}, "\t"))
	file.close()
	print("pet_driver: ", JSON.stringify({"failures": failures, "missing": missing}))
	get_tree().quit(0 if failures.is_empty() else 1)


func _round(species: int) -> void:
	print("pet_driver: round ", species)
	var run: RunScene = (load(RunScene.SCENE_PATH) as PackedScene).instantiate()
	run.configure("henesys", 60, {"use_flow": false, "autopick": true,
		"account": {"owned": [species], "pet": species, "alert": {"hp": 0.0, "mp": 0.0}}})
	add_child(run)
	run.set_process(false)
	var w := run.world
	w.god = true
	_check(w.pet_state().get("species", 0) == species, "round %d: the pet is out" % species)
	var tag := "round_%d" % species
	await _pose(run, w, tag + "_walk_right", 40, MoveInput.make(false, true))
	await _pose(run, w, tag + "_stand", 100, MoveInput.new())
	await _pose(run, w, tag + "_walk_left", 40, MoveInput.make(true, false))
	# Jump: lift the pet and let it fall (the follow controller only jumps for platforms).
	var pet := w.pet_system
	pet.motion.pos.y -= 40.0
	pet.motion.state = PlayerMotion.ST_AIR
	pet.motion.fh = -1
	await _pose(run, w, tag + "_jump", 3, MoveInput.new())
	_check(w.pet_state().action == "jump", "round %d: the airborne pet jumps" % species)
	# Rope: the first real rope or ladder, climbed from its foot.
	var i := _longest_ladder(w.ladders)
	if i >= 0:
		w.player.place(Vector2(w.ladders.x[i], w.ladders.y2[i]), w.fhm)
		w.pet_system.place(w.player.pos, w.fhm)
		run.cam.snap_to(w.player.pos)
		await _pose(run, w, tag + "_rope", 45, MoveInput.make(false, false, true))
		_check(w.pet_state().action == "hang", "round %d: hangs on the rope" % species)
	missing.append_array(Array(run.library.missing).filter(func(m: String) -> bool: return not m in missing))
	run.queue_free()
	await get_tree().process_frame


func _hub(species: int) -> void:
	var flow := get_node("/root/Flow") as SceneFlow
	flow.host = self
	flow.deferred_swaps = false
	var path := shots.path_join("driver_save.json")
	for file: String in [path, path + ".bak", path + ".tmp"]:
		if FileAccess.file_exists(file):
			DirAccess.remove_absolute(file)
	flow.save = SaveData.new(path)
	flow.save.set_account({"nx": 0, "owned": [species]})
	flow.create_character("Pet%d" % (species % 10))
	var character: Dictionary = DataRepo.load_json("res://tests/fixtures/characters/lv35_magician_2nd.json")
	character["pet"] = species
	flow.finish_run({"stage": "henesys", "cleared": true, "time": 960.0, "level": 35,
		"job_id": 210, "job_name": "Wizard (Fire, Poison)", "kills": 3000, "damage_dealt": 100000, "seed": 1,
		"bosses_killed": 3, "levels_gained": 12, "nx_awarded": 0}, character)
	var hub := flow.current as FreeMarket
	if hub == null or hub.motion == null or hub.pet_renderer == null:
		_check(false, "hub %d: no pet in the Free Market" % species)
		return
	hub.set_process(false)
	var tag := "hub_%d" % species
	await get_tree().create_timer(0.5).timeout
	await _hub_pose(hub, tag + "_walk_right", 40, MoveInput.make(false, true))
	await _hub_pose(hub, tag + "_stand", 100, MoveInput.new())
	await _hub_pose(hub, tag + "_walk_left", 40, MoveInput.make(true, false))
	var pet := hub.motion.pet
	pet.motion.pos.y -= 40.0
	pet.motion.state = PlayerMotion.ST_AIR
	pet.motion.fh = -1
	await _hub_pose(hub, tag + "_jump", 3, MoveInput.new())
	_check(hub.motion.pet_state().action == "jump", "hub %d: the airborne pet jumps" % species)
	var l := hub.motion.ladders
	var i := _longest_ladder(l)
	if i >= 0:
		hub.motion.player.place(Vector2(l.x[i], l.y2[i]), hub.motion.fhm)
		hub.motion.pet.place(hub.motion.player.pos, hub.motion.fhm)
		hub.camera.snap_to(hub.motion.player.pos)
		await _hub_pose(hub, tag + "_rope", 45, MoveInput.make(false, false, true))
		_check(hub.motion.pet_state().action == "hang", "hub %d: hangs on the rope" % species)
	for m in hub.missing_paths():
		if not m in missing:
			missing.append(m)
	await get_tree().process_frame


func _longest_ladder(l: LadderSet) -> int:
	var best := -1
	var span := 60.0
	for i in l.count():
		if l.y2[i] - l.y1[i] > span:
			span = l.y2[i] - l.y1[i]
			best = i
	return best


func _pose(run: RunScene, w: RunWorld, name: String, ticks: int, input: MoveInput) -> void:
	for t in ticks:
		var held := MoveInput.new()
		held.left = input.left
		held.right = input.right
		held.up = input.up
		w.step(DT, held)
		if w.transfer_pending:
			w.advance_map()
		run.handle_events(w.drain_events())
		run._present(DT)
	run.cam.snap_to(w.player.pos)
	run._present(0.0)
	var st := w.pet_state()
	print("pet_driver: ", name, " player ", w.player.pos, " facing ", w.player.facing, " pet ", st.pos, " facing ",
		st.facing, " ", st.action, " anim ", run.pet_renderer.shown_anim)
	await _shot(name, w.player.pos, st.pos)


func _hub_pose(hub: FreeMarket, name: String, ticks: int, input: MoveInput) -> void:
	for t in ticks:
		hub.step_input(DT, input)
		hub._present(DT)
	hub.camera.snap_to(hub.motion.player.pos)
	hub._present(0.0)
	await _shot(name, hub.motion.player.pos, hub.motion.pet.motion.pos)


func _shot(name: String, world_pos: Vector2, pet_pos: Vector2) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	_check(image.save_png(shots.path_join(name + ".png")) == OK, "screenshot " + name)
	_crop(image, world_pos, CROP, CROP_SCALE, name + "_zoom")
	_crop(image, pet_pos, Vector2i(120, 90), 6, name + "_pet")


func _crop(image: Image, world_pos: Vector2, size: Vector2i, scale: int, name: String) -> void:
	var screen := get_viewport().get_canvas_transform() * world_pos
	var logical := Rect2(Vector2i(screen) - Vector2i(size.x / 2, size.y - 30), size)
	var rect := GameSettings.capture_rect(image, get_viewport(), logical).intersection(
		Rect2i(Vector2i.ZERO, image.get_size()))
	var crop := image.get_region(rect)
	var k := float(image.get_width()) / get_viewport().get_visible_rect().size.x
	crop.resize(int(rect.size.x / k) * scale, int(rect.size.y / k) * scale, Image.INTERPOLATE_NEAREST)
	crop.save_png(shots.path_join(name + ".png"))


func _check(ok: bool, description: String) -> void:
	if not ok:
		failures.append(description)
		push_error("pet_driver: " + description)
