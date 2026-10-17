extends Node
## Equipment drop evidence on the real map/cache (spec #33, #109): drops lying on the ground, the full-Equip-tab notice
## next to one, and its pickup once a slot is freed.
## ISOLATE=s33t109 bash scripts/run.sh res://scenes/debug/equipment_drop_driver.tscn -- --shots=<abs evidence dir>
## Saves ground.png, full.png, picked.png and summary.json. No cache import or balance edits.

var run: RunScene
var shots := ""
## Wand, hat, overall, shoes, gloves, staff (Magician list items across the level range).
const DROPS := [1372004, 1002215, 1050001, 1072136, 1082019, 1382019]


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
	w.change_job(200)
	w.progression.level = 45
	var infos: Dictionary = w.setup.get("equipment_info", {})
	var rng := RandomNumberGenerator.new()
	rng.seed = 109
	while w.equipment.inventory.size() < w.inventory_slots():
		w.equipment.inventory.append(Equipment.create(1002001, Equipment.info_of(infos, 1002001)))
	var origin := w.player.pos
	# The drops lie on the ground floor (the first floor below the spawn point), the player starts far to the left.
	var ground_x := origin.x - 430.0  # open ground left of the hut below the spawn platform
	var ground_y := w.fhm.y_at(w.fhm.find_below(ground_x, origin.y), ground_x)
	_stand(w, ground_x - 300.0, origin.y)
	var spots := []
	for i in DROPS.size():
		var id: int = DROPS[i]
		var pos := Vector2(ground_x + 160.0 + float(i) * 42.0, ground_y - 30.0)
		spots.append(pos)
		w.spawn_equipment(pos, Equipment.create_drop(id, Equipment.info_of(infos, id), rng))
	# Step far enough for the pops to land; the player is outside the magnet radius of every drop, so they lie.
	for t in 90:
		run.advance_frame(1.0 / 60.0)
	# Where the first (leftmost) drop landed: stand on its floor, a little to its left, outside the magnet radius (90 px).
	var first := Vector2(INF, 0.0)
	for i in w.pickups.capacity():
		if w.pickups.active[i] != 0 and w.pickups.kind[i] == PickupSystem.EQUIP and w.pickups.x[i] < first.x:
			first = Vector2(w.pickups.x[i], w.pickups.y[i])
	_stand(w, first.x - 130.0, first.y - 5.0)
	for t in 60:
		run.advance_frame(1.0 / 60.0)
	await _shot("ground.png")
	# Walk onto the first drop with a full tab: it stays and the notice appears.
	_stand(w, first.x, first.y - 5.0)
	for t in 20:
		run.advance_frame(1.0 / 60.0)
	await _shot("full.png")
	var before_full: int = w.equipment.inventory.size()
	# Free a slot: the drop is collected.
	w.discard_item(0)
	for t in 60:
		run.advance_frame(1.0 / 60.0)
	await _shot("picked.png")
	var summary := run.perf_summary()
	summary["equipment_probe"] = {"inventory_full_size": before_full, "after_size": w.equipment.inventory.size(),
		"collected": w.equips_collected, "dropped": w.equips_dropped,
		"last_item": int(w.equipment.inventory[w.equipment.inventory.size() - 1].id)}
	var file := FileAccess.open(shots.path_join("summary.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(summary, "\t"))
	get_tree().quit()


func _stand(w: RunWorld, x: float, y: float) -> void:
	w.player.place(Vector2(x, w.fhm.y_at(w.fhm.find_below(x, y), x)), w.fhm)
	w.update_view()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(shots.path_join(name))
