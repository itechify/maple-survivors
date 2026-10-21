extends Node
## Pirate combat evidence on the real Henesys map and cache (spec #168 QA #195): the two first-job paths fighting, the
## Brawler's attacks and the Gunslinger's bullet upgrades (basic Bullet at Lv 10, Split Bullet at Lv 30, Mighty Bullet
## at Lv 50), each in front of a few motionless monsters. Saves <scenario>_a.png / _b.png (early and later frames of the
## first cast) and summary.json (positions, hits, statuses, the ammo id). The Gunslinger's own attacks, Dash, Oak Barrel
## and the stunned mob have their own drivers (gunslinger_driver, dash_driver, morph_driver, stun_driver).
## MAPLE_SURVIVORS_CACHE=<cache> ISOLATE=<name> bash scripts/run.sh res://scenes/debug/pirate_combat_driver.tscn -- \
##   --shots=<abs evidence dir> [--rank=10]

## name -> {job, path, level, skill, mobs (x offsets), times (seconds after the first frame to shoot)}; job 500 is the first
## job at Lv 10, 510 / 520 the second jobs at Lv 30 (50 for the last bullet step).
const SCENARIOS := {
	"knuckle_flash_fist": {"job": 500, "path": "knuckle", "level": 10, "skill": "flash_fist", "mobs": [90.0, 150.0],
		"times": [0.15, 0.5]},
	"knuckle_somersault_kick": {"job": 500, "path": "knuckle", "level": 10, "skill": "somersault_kick",
		"mobs": [60.0, -60.0, 100.0], "times": [0.15, 0.5]},
	"gun_double_shot": {"job": 500, "path": "gun", "level": 10, "skill": "double_shot", "mobs": [120.0, 200.0, 280.0],
		"times": [0.12, 0.4]},
	"brawler_backspin_blow": {"job": 510, "path": "knuckle", "level": 30, "skill": "backspin_blow", "mobs": [-90.0, 70.0],
		"times": [0.12, 0.6]},
	"brawler_double_uppercut": {"job": 510, "path": "knuckle", "level": 30, "skill": "double_uppercut", "mobs": [70.0, 110.0],
		"times": [0.15, 0.6]},
	"brawler_corkscrew_blow": {"job": 510, "path": "knuckle", "level": 30, "skill": "corkscrew_blow", "mobs": [150.0],
		"times": [0.12, 0.5]},
	"bullet_basic_lv10": {"job": 500, "path": "gun", "level": 10, "skill": "double_shot", "mobs": [140.0, 240.0],
		"times": [0.12, 0.3]},
	"bullet_split_lv30": {"job": 520, "path": "gun", "level": 30, "skill": "double_shot", "mobs": [140.0, 240.0],
		"times": [0.12, 0.3]},
	"bullet_mighty_lv50": {"job": 520, "path": "gun", "level": 50, "skill": "double_shot", "mobs": [140.0, 240.0],
		"times": [0.12, 0.3]},
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
	var spec: Dictionary = SCENARIOS[key]
	if run != null:
		run.queue_free()
		await get_tree().process_frame
	run = (load(RunScene.SCENE_PATH) as PackedScene).instantiate()
	run.configure("henesys_hg1", 60, {"use_flow": false, "autopick": true})
	add_child(run)
	run.set_process(false)
	var w := run.world
	w.god = true
	w.progression.level = 10
	w.change_job(500, String(spec.path))
	if int(spec.job) != 500:
		w.progression.level = 30
		w.change_job(int(spec.job))
	w.progression.level = int(spec.level)
	w.drain_events()
	w.loadout.order.clear()
	w.learn_skill(String(spec.skill))
	w.loadout.set_rank(String(spec.skill), rank)
	w.refresh_player_stats()
	w.heal_fraction("mp", 1.0)
	for mk: MobKind in w.mob_kinds:
		mk.move_speed = 0.0
	w.player.facing = 1
	_stand_on_flat_ground(w)
	var slots: Array[int] = []
	for dx: float in spec.mobs:
		var x := w.player.pos.x + dx
		var f := w.fhm.find_below(x, w.player.pos.y - 10.0)
		var slot := w.spawn_mob(0, Vector2(x, w.fhm.y_at(f, x)), f, 200.0, false)
		w.swarm.alpha[slot] = 1.0
		slots.append(slot)
	run.handle_events(w.drain_events())
	var start_x := w.player.pos.x
	var elapsed := 0.0
	var times: Array = spec.times
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
	summary[key] = {"job": w.progression.job_id, "level": w.progression.level, "weapon": w.weapon_id(), "ammo": w.ammo_id(),
		"rank": rank, "mobs_hurt": hurt, "mobs_stunned": stunned, "player_dx": w.player.pos.x - start_x,
		"casts": w.runner.casts, "state": w.state, "mp": int(w.player_state.mp)}


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
