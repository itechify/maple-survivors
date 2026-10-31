extends Node
## Tool-only evidence for the Night Lord status effects on the real map (spec #383 review S9/S10, needs the asset cache):
## `--scenario=status` leaves a pack of six monsters, two poisoned by Venomous Star's real catalogue row, two stunned by
## Stunning Avenger's and two untouched; `--scenario=storm` casts Ninja Storm into a pack and logs the pushed monsters'
## positions. `--shots=<absolute evidence directory>`. Writes `<scenario>_*.png` and `<scenario>.json`; never saves anything.

const PACK := 6


func _ready() -> void:
	call_deferred("_drive")


func _drive() -> void:
	var args := SceneFlow.parse_flags(OS.get_cmdline_user_args())
	var shots := String(args.get("shots", ""))
	if shots == "":
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(shots)
	var scenario := String(args.get("scenario", "status"))
	var run := (load(RunScene.SCENE_PATH) as PackedScene).instantiate() as RunScene
	run.configure("henesys", 383, {"use_flow": false, "autopick": true, "job": 412})
	add_child(run)
	run.set_process(false)
	var w := run.world
	w.god = true
	w.loadout.order.clear()
	for mk: MobKind in w.mob_kinds:
		mk.move_speed = 0.0
	_stand_on_ground(w, w.player.pos.x + 250.0)
	var pack := _spawn_pack(w, 120.0 if scenario == "status" else 50.0, 64.0 if scenario == "status" else 46.0)
	var log := {"scenario": scenario, "before": _xs(w, pack)}
	if scenario == "status":
		_apply_status(w, pack)
		for tick in 20:
			run.advance_frame(1.0 / 60.0)
			await get_tree().process_frame
		log["poisoned"] = pack.slice(0, 2).map(func(m: int) -> bool: return w.swarm.status_time(m, MobSwarm.POISON) > 0.0)
		log["stunned"] = pack.slice(2, 4).map(func(m: int) -> bool: return w.swarm.status_time(m, MobSwarm.STUN) > 0.0)
		log["plain"] = pack.slice(4).map(func(m: int) -> bool: return w.swarm.status_time(m, MobSwarm.POISON) <= 0.0 \
			and w.swarm.status_time(m, MobSwarm.STUN) <= 0.0)
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		image.save_png(shots.path_join("status_pack.png"))
		_save_zoom(image, shots.path_join("status_pack_zoom.png"), w, pack)
	else:
		w.learn_skill("ninja_storm")
		w.loadout.set_rank("ninja_storm", 8)
		var frame := 0
		for tick in 90:
			run.advance_frame(1.0 / 60.0)
			await get_tree().process_frame
			if tick in [2, 6, 14, 50]:
				await RenderingServer.frame_post_draw
				var image := get_viewport().get_texture().get_image()
				image.save_png(shots.path_join("storm_%02d.png" % frame))
				_save_zoom(image, shots.path_join("storm_%02d_zoom.png" % frame), w, pack)
				frame += 1
		log["after"] = _xs(w, pack)
		log["pushed"] = pack.size() - pack.filter(func(m: int) -> bool:
			return absf(w.swarm.x[m] - float(log.before[pack.find(m)])) < 1.0).size()
		log["player_x"] = w.player.pos.x
	var file := FileAccess.open(shots.path_join("%s.json" % scenario), FileAccess.WRITE)
	file.store_string(JSON.stringify(log, "\t"))
	file.close()
	get_tree().quit()


## Puts the player on the floor under (x, the start height): the open ground beside the start platform.
func _stand_on_ground(w: RunWorld, x: float) -> void:
	var fh := w.fhm.find_below(x, w.player.pos.y - 10.0)
	w.player.place(Vector2(x, w.fhm.y_at(fh, x)), w.fhm)
	w.update_view()


## Six monsters in a row to the left of the player, beginning `lead` px away, `gap` px apart.
func _spawn_pack(w: RunWorld, lead: float, gap: float) -> Array:
	var out := []
	for n in PACK:
		var x := w.player.pos.x - lead - n * gap
		var fh := w.fhm.find_below(x, w.player.pos.y - 10.0)
		var slot := w.spawn_mob(0, Vector2(x, w.fhm.y_at(fh, x)), fh, 20.0, false)
		w.swarm.alpha[slot] = 1.0
		out.append(slot)
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	return out


func _xs(w: RunWorld, pack: Array) -> Array:
	return pack.map(func(m: int) -> float: return snappedf(w.swarm.x[m], 0.1))


## Hits the first two with a Venomous Star grant and the next two with a Stunning Avenger grant (100% chance, rank 8).
func _apply_status(w: RunWorld, pack: Array) -> void:
	var st := w.loadout.stats("lucky_seven")
	st.damage_min = 1.0
	st.damage_max = 1.0
	st.damage_type = "fixed"
	for n in 4:
		var grants := StatusBonus.resolve(w.book.status_bonuses, ["venomous_star" if n < 2 else "stunning_avenger"], 8)
		grants[0]["chance"] = 100.0
		st["status_grants"] = grants
		w.hit_mob(pack[n], st, -1)
	w.drain_events()


## A 4x crop (nearest) of the screen around the pack and the player: the status art on a monster is small at the native size.
func _save_zoom(image: Image, path: String, w: RunWorld, pack: Array) -> void:
	var lo := w.player.pos.x
	var hi := w.player.pos.x
	for m: int in pack:
		lo = minf(lo, w.swarm.x[m])
		hi = maxf(hi, w.swarm.x[m])
	var origin := get_viewport().get_canvas_transform() * Vector2(lo - 60.0, w.player.pos.y - 130.0)
	var corner := get_viewport().get_canvas_transform() * Vector2(hi + 60.0, w.player.pos.y + 40.0)
	var rect := Rect2i(Vector2i(origin), Vector2i(corner - origin)).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	if rect.size.x <= 0 or rect.size.y <= 0:
		return
	var crop := image.get_region(rect)
	crop.resize(rect.size.x * 4, rect.size.y * 4, Image.INTERPOLATE_NEAREST)
	crop.save_png(path)
