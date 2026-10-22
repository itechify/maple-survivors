extends SceneTree
## Headless benchmark of a whole RunWorld tick (player, MobSwarm, SpawnDirector, SpatialHash, SkillRunner,
## ProjectileSystem, PickupSystem, touch damage) at fixed alive-mob counts, on the synthetic multi-platform map of the
## tests and (when the asset cache exists) on the real Henesys Hunting Ground I (104040000).
##
##   bash scripts/bench.sh run               # 100 300 600 1000 alive mobs
##   bash scripts/bench.sh run 300 2000      # custom counts
##   bash scripts/bench.sh run 300 --statuses   # every live mob kept slowed and poisoned, every third frozen
##
## Setup per run: a "bench" stage that refills to exactly N alive (rate 600/s, the full henesys mob pool at 2x
## HP), a god-mode player driven by the kiting test bot, and a late-game build (Three Snails rank 3 with 5 shells and
## pierce 3; Magician with Energy Bolt rank 4 with 4 bolts, Magic Claw), so shots, kills, drops and pickups all churn.
## Choice windows are answered between ticks (not timed); with --statuses, statuses are (re)applied there too, so the
## timed step includes their movement, pulse and expiry cost but not the application. Prints microseconds per
## RunWorld.step, plus the average alive mobs, shots in flight and drops on the ground. Seeded; timings are
## wall-clock on this machine.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const WARMUP := 240
const TICKS := 600

## --statuses: keep player statuses active on the swarm (see the class doc).
var _statuses := false


func _init() -> void:
	var counts: Array[int] = []
	for a in OS.get_cmdline_user_args():
		if a.is_valid_int():
			counts.append(int(a))
		elif a == "--statuses":
			_statuses = true
	if counts.is_empty():
		counts = [100, 300, 600, 1000]
	print("bench_run: Godot %s, %s build, %d timed ticks after %d warm-up ticks" % [
		Engine.get_version_info().string, "debug" if OS.is_debug_build() else "release", TICKS, WARMUP])
	var maps: Array = [["synthetic", {"map_img": RF.big_map_img(), "mob_imgs": RF.mob_imgs(),
		"skill_imgs": RF.skill_imgs()}]]
	var real := _real()
	if not real.is_empty():
		maps.append(["104040000", real])
	else:
		print("bench_run: no asset cache with 104040000; real-map run skipped")
	for entry: Array in maps:
		for n in counts:
			_run(entry[0], entry[1], n)
	quit()


func _run(label: String, imgs: Dictionary, n: int) -> void:
	var data := DataRepo.load_all()
	var pool := {}
	for id in DataRepo.stage_mob_ids(data, "henesys"):
		pool[str(id)] = 1.0
	data.stages.stages["bench"] = {
		"maps": [{"map_id": 0, "boss": {}}], "duration": 1.0e9, "hard_cap": n,
		"keyframes": [{"t": 0.0, "rate": 600.0, "max_alive": float(n), "hp": 2.0, "speed": 1.0, "damage": 1.0,
			"pool": pool}],
	}
	var setup := RF.setup("bench", 4242 + n, data)
	setup.map_img = imgs.map_img
	setup.mob_imgs = imgs.mob_imgs
	setup.skill_imgs = imgs.skill_imgs
	if imgs.has("physics_img"):
		setup.physics_img = imgs.physics_img
	var w := RunWorld.new(setup)
	w.god = true
	_late_game_build(w)
	var memo := {}
	var total := 0
	var alive := 0
	var shots := 0
	var drops := 0
	var mp_short := 0
	for t in WARMUP + TICKS:
		RF.auto_choose(w)
		if _statuses:
			_keep_statuses(w)
		var input := RF.bot_input(w, memo)
		var a := Time.get_ticks_usec()
		w.step(DT, input)
		var b := Time.get_ticks_usec()
		w.drain_events()
		if t >= WARMUP:
			total += b - a
			alive += w.swarm.alive_count()
			shots += w.projectiles.active_count()
			drops += w.pickups.active_count()
			if w.runner.waiting_mp:
				mp_short += 1
	var per := float(TICKS)
	print("%-10s %5d target%s: alive %6.1f  shots %5.1f  drops %5.1f  kills %5d  mp-short %3.0f%%  ->  %8.1f us/tick (%.2f us/mob)" % [
		label, n, " +statuses" if _statuses else "", alive / per, shots / per, drops / per, w.kills,
		100.0 * mp_short / per, total / per, total / per / maxf(1.0, alive / per)])


## Keeps every live mob slowed (canonical level-20 x -40) and poisoned (level 20), and every third slot frozen,
## reapplying each status once it expires (untimed; bosses and immune kinds reject theirs).
static func _keep_statuses(w: RunWorld) -> void:
	var sw := w.swarm
	for i in sw.capacity():
		if not sw.is_live(i):
			continue
		if sw.status_time(i, MobSwarm.SLOW) <= 0.0:
			sw.apply_status(i, "slow", {"x": -40.0, "time": 5.0}, w.events)
		if sw.status_time(i, MobSwarm.POISON) <= 0.0:
			sw.apply_status(i, "poison", {"level": 20, "time": 5.0}, w.events)
		if i % 3 == 0 and sw.status_time(i, MobSwarm.FREEZE) <= 0.0:
			sw.apply_status(i, "freeze", {"time": 2.0}, w.events)


## Three Snails rank 3 x5 shells, pierce 3; Magician with Energy Bolt rank 4 x4 bolts and Magic Claw.
static func _late_game_build(w: RunWorld) -> void:
	var up := w.upgrades
	for id: String in ["three_snails_rank", "three_snails_rank", "three_snails_count", "three_snails_count",
			"three_snails_count", "three_snails_count", "three_snails_pierce", "three_snails_pierce",
			"three_snails_pierce"]:
		up.apply(id, w)
	w.change_job(200)
	for id: String in ["energy_bolt_new", "energy_bolt_rank", "energy_bolt_rank", "energy_bolt_rank",
			"energy_bolt_count", "energy_bolt_count", "energy_bolt_count", "magic_claw_new"]:
		up.apply(id, w)
	w.drain_events()


func _real() -> Dictionary:
	var root := AssetCachePaths.resolve_cache_root()
	var map := _json(root, "Map.wz/Map/Map1/104040000.img")
	if map.is_empty():
		return {}
	var mobs := {}
	for id in DataRepo.stage_mob_ids(DataRepo.load_all(), "henesys"):
		var m := _json(root, "Mob.wz/%07d.img" % id)
		if not m.is_empty():
			mobs[id] = m
	var skills := {}
	for book: String in ["000", "200", "210"]:
		var s := _json(root, "Skill.wz/%s.img" % book)
		if not s.is_empty():
			skills[book] = s
	return {"map_img": map, "mob_imgs": mobs, "skill_imgs": skills, "physics_img": _json(root, "Map.wz/Physics.img")}


static func _json(root: String, path: String) -> Dictionary:
	var file := root.path_join(path + ".json")
	if not FileAccess.file_exists(file):
		return {}
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(file))
	return d if d is Dictionary else {}
