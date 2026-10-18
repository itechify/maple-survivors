extends Node
## Gunslinger attack evidence on the real Henesys map and cache (#192): a Lv 30 Gunslinger with one attack at a time in
## front of a few motionless monsters. Saves <skill>_a.png / <skill>_b.png (early and later frames of the first cast:
## the shot and the hit effects, Grenade's ball in flight and its blast, Recoil Shot before and after the hop) and
## summary.json (positions, hits, statuses).
## MAPLE_SURVIVORS_CACHE=<cache> ISOLATE=<name> bash scripts/run.sh res://scenes/debug/gunslinger_driver.tscn -- \
##   --shots=<abs evidence dir> [--rank=10]

## skill -> [monster x offsets, [seconds after the first frame of the cast to take the two screenshots]]
const SCENARIOS := {
	"invisible_shot": [[110.0, 190.0, -110.0, -190.0], [0.10, 0.45]],
	"blank_shot": [[100.0, 160.0, 220.0], [0.30, 1.00]],
	"grenade": [[120.0, 300.0, 325.0, 350.0], [0.20, 0.60]],
	"recoil_shot": [[200.0], [0.08, 0.50]],
}

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
	for key: String in SCENARIOS:
		await _scenario(key, int(args.get("rank", 10)))
	var file := FileAccess.open(shots.path_join("summary.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(summary, "\t"))
	get_tree().quit()


func _scenario(key: String, rank: int) -> void:
	if run != null:
		run.queue_free()
		await get_tree().process_frame
	run = (load(RunScene.SCENE_PATH) as PackedScene).instantiate()
	run.configure("henesys_hg1", 60, {"use_flow": false, "autopick": true})
	add_child(run)
	run.set_process(false)
	var w := run.world
	w.god = true
	w.change_job(500, "gun")
	w.progression.level = 30
	w.change_job(520)
	w.drain_events()
	w.loadout.order.clear()
	w.learn_skill(key)
	w.loadout.set_rank(key, rank)
	w.refresh_player_stats()
	w.heal_fraction("mp", 1.0)
	for mk: MobKind in w.mob_kinds:
		mk.move_speed = 0.0
	w.player.facing = 1
	_stand_on_flat_ground(w)
	var slots: Array[int] = []
	for dx: float in SCENARIOS[key][0]:
		var x := w.player.pos.x + dx
		var f := w.fhm.find_below(x, w.player.pos.y - 10.0)
		var slot := w.spawn_mob(0, Vector2(x, w.fhm.y_at(f, x)), f, 200.0, false)
		w.swarm.alpha[slot] = 1.0
		slots.append(slot)
	run.handle_events(w.drain_events())
	var start_x := w.player.pos.x
	var elapsed := 0.0
	var times: Array = SCENARIOS[key][1]
	var next := 0
	while next < times.size():
		run.advance_frame(1.0 / 60.0)
		elapsed += 1.0 / 60.0
		await get_tree().process_frame
		if elapsed >= float(times[next]):
			await _shot("%s_%s.png" % [key, "ab"[next]])
			next += 1
	var hurt := 0
	var stunned := 0
	for s in slots:
		if w.swarm.hp[s] < w.swarm.max_hp[s]:
			hurt += 1
		if w.swarm.status_time(s, MobSwarm.STUN) > 0.0:
			stunned += 1
	summary[key] = {"rank": rank, "mobs_hurt": hurt, "mobs_stunned": stunned, "player_dx": w.player.pos.x - start_x,
		"casts": w.runner.casts, "state": w.state, "can_cast": w.can_cast(), "mp": int(w.player_state.mp), "mob_xs": slots.map(
			func(s: int) -> float: return w.swarm.x[s] - start_x)}


## Moves the player to the lowest ground (the start platform's y or below) with the flattest 800 px around it, so the
## boxes and the hop meet level floor instead of haystacks.
func _stand_on_flat_ground(w: RunWorld) -> void:
	var y0 := w.player.pos.y
	var best_x := w.player.pos.x
	var best_spread := INF
	var x := w.bounds.position.x + 450.0
	while x < w.bounds.end.x - 450.0:
		var lo := INF
		var hi := -INF
		var dx := -400.0
		while dx <= 400.0:
			var f := w.fhm.find_below(x + dx, y0 - 10.0)
			if f < 0:
				lo = -INF
				hi = INF
				break
			var y := w.fhm.y_at(f, x + dx)
			lo = minf(lo, y)
			hi = maxf(hi, y)
			dx += 25.0
		if hi - lo < best_spread:
			best_spread = hi - lo
			best_x = x
		x += 25.0
	var f := w.fhm.find_below(best_x, y0 - 10.0)
	w.player.place(Vector2(best_x, w.fhm.y_at(f, best_x)), w.fhm)
	w.update_view()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(shots.path_join(name))
