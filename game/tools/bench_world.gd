extends SceneTree
## Headless benchmark of the world-movement sim: MobSwarm.step + SpatialHash.rebuild + targeting queries per 1/60 s
## tick, at several mob counts, on a synthetic multi-platform map and (when the asset cache exists) on the real
## Henesys Hunting Ground I (104040000).
##
##   bash scripts/bench.sh                 # 100 300 600 1000 mobs
##   bash scripts/bench.sh 300 2000        # custom counts
##
## Prints one line per (map, count): microseconds per tick for the swarm step, the hash rebuild, 20 radius queries,
## and the total. Deterministic workload (seeded RNG); timings are wall-clock on this machine.

const DT := 1.0 / 60.0
const WARMUP := 60
const TICKS := 600
const QUERIES := 20


func _init() -> void:
	var counts: Array[int] = []
	for a in OS.get_cmdline_user_args():
		if a.is_valid_int():
			counts.append(int(a))
	if counts.is_empty():
		counts = [100, 300, 600, 1000]
	print("bench_world: Godot %s, %s build, %d ticks per run after %d warm-up ticks" % [
		Engine.get_version_info().string, "debug" if OS.is_debug_build() else "release", TICKS, WARMUP])
	var maps: Array = [["synthetic", _synthetic_map()]]
	var real := _real_map()
	if not real.is_empty():
		maps.append(["104040000", real])
	else:
		print("bench_world: no asset cache with 104040000; real-map run skipped")
	for entry: Array in maps:
		var img: Dictionary = entry[1]
		for n in counts:
			_run(entry[0], img, n)
	quit()


func _run(label: String, img: Dictionary, n: int) -> void:
	var m := FootholdMap.from_wz(img)
	var bounds := MapBounds.from_map(img, m)
	var kinds: Array = [_kind(-65, false, 2.0), _kind(-20, true, 1.5), _kind(0, true, 1.0), _kind(-30, false, 1.5)]
	var ctx := {
		"fhm": m, "nav": NavGraph.build(m, {"can_jump": false}), "nav_jump": NavGraph.build(m, {"can_jump": true}),
		"bounds": bounds, "target": Vector2.ZERO, "target_fh": -1, "speed_mult": 1.0,
	}
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242 + n
	var floors: Array = []
	for f in m.count():
		if m.is_floor(f):
			floors.append(f)
	var swarm := MobSwarm.new(64, kinds)
	for i in n:
		var f: int = floors[rng.randi_range(0, floors.size() - 1)]
		swarm.spawn(i % kinds.size(), rng.randf_range(m.x1[f], m.x2[f]), 0.0, f)
	var grid := SpatialHash.new(64.0, bounds)
	var out := PackedInt32Array()
	out.resize(256)
	var t_step := 0
	var t_hash := 0
	var t_query := 0
	var found := 0
	for t in WARMUP + TICKS:
		if t % 120 == 0:
			var f: int = floors[rng.randi_range(0, floors.size() - 1)]
			var tx := rng.randf_range(m.x1[f], m.x2[f])
			ctx.target = Vector2(tx, m.y_at(f, tx))
			ctx.target_fh = f
		if t % 15 == 0:
			# Steady churn: kill two mobs, spawn two (exercises DIE -> FREE and slot reuse).
			for k in 2:
				if swarm.apply_hit(rng.randi_range(0, swarm.capacity() - 1), 1000000, 1):
					var f: int = floors[rng.randi_range(0, floors.size() - 1)]
					swarm.spawn(rng.randi_range(0, kinds.size() - 1), rng.randf_range(m.x1[f], m.x2[f]), 0.0, f)
		var a := Time.get_ticks_usec()
		swarm.step(DT, ctx)
		var b := Time.get_ticks_usec()
		grid.rebuild(swarm.x, swarm.y, swarm.active, swarm.capacity())
		var c := Time.get_ticks_usec()
		var target: Vector2 = ctx.target
		for q in QUERIES:
			found += grid.query_radius(target + Vector2(q * 13.0 - 130.0, 0.0), 420.0, out)
		var d := Time.get_ticks_usec()
		if t >= WARMUP:
			t_step += b - a
			t_hash += c - b
			t_query += d - c
	var per := float(TICKS)
	print("%-10s %5d mobs (alive %4d, lost %d): step %7.1f us  hash %6.1f us  %d queries %6.1f us  total %7.1f us/tick  (%.2f us/mob)" % [
		label, n, swarm.alive_count(), swarm.lost_count, t_step / per, t_hash / per, QUERIES, t_query / per,
		(t_step + t_hash + t_query) / per, (t_step + t_hash + t_query) / per / maxf(1.0, n)])


func _kind(speed: int, jumper: bool, mult: float) -> MobKind:
	var k := MobKind.new()
	k.speed_stat = speed
	k.move_speed = (speed + 100) * MobKind.SPEED_SCALE * mult
	k.can_jump = jumper
	k.max_hp = 50
	k.die_time = 0.9
	return k


## A 3000 px wide map: ground with skirts, three tiers of floating platforms (some sloped, some with bumps), a cliff
## with a rising wall, a pit. WZ-shaped like the cache JSON.
func _synthetic_map() -> Dictionary:
	var segs: Array = []
	# Ground: a raised block at 1800..2200 makes rising walls (cliffs) on both sides.
	_chain(segs, [Vector2(-1000, 200), Vector2(0, 200), Vector2(900, 200)])
	segs.append([Vector2(900, 200), Vector2(900, 260)])  # pit wall down
	_chain(segs, [Vector2(900, 260), Vector2(1100, 260)])
	segs.append([Vector2(1100, 260), Vector2(1100, 200)])  # pit wall up
	_chain(segs, [Vector2(1100, 200), Vector2(1800, 200)])
	segs.append([Vector2(1800, 200), Vector2(1800, 150)])  # cliff up
	_chain(segs, [Vector2(1800, 150), Vector2(2200, 150)])
	segs.append([Vector2(2200, 150), Vector2(2200, 200)])  # cliff down
	_chain(segs, [Vector2(2200, 200), Vector2(2600, 220), Vector2(3000, 200)])
	var y := 140.0
	for tier in 3:
		for p in 6:
			var x0 := -900.0 + p * 650.0 + tier * 90.0
			var w := 260.0 + 40.0 * ((p + tier) % 3)
			var pts: Array = [Vector2(x0, y)]
			for s in 4:
				pts.append(Vector2(x0 + w * (s + 1) / 4.0, y - 6.0 * ((s + p) % 2)))
			_chain(segs, pts)
			segs.append([Vector2(x0, y), Vector2(x0, y + 20)])  # skirts hang below the ends
			segs.append([pts[-1], pts[-1] + Vector2(0, 20)])
		y -= 60.0 if tier == 0 else 200.0
	var fh := {}
	for i in segs.size():
		var s: Array = segs[i]
		fh[str(i + 1)] = {"x1": s[0].x, "y1": s[0].y, "x2": s[1].x, "y2": s[1].y, "prev": 0.0, "next": 0.0}
	# Link consecutive floors that share end points (and walls to the floors they touch).
	for i in segs.size():
		for j in segs.size():
			if i != j and segs[i][1] == segs[j][0]:
				fh[str(i + 1)].next = float(j + 1)
				fh[str(j + 1)].prev = float(i + 1)
	return {"foothold": {"1": {"0": fh}}}


func _chain(segs: Array, pts: Array) -> void:
	for i in pts.size() - 1:
		segs.append([pts[i], pts[i + 1]])


func _real_map() -> Dictionary:
	var path := AssetCachePaths.resolve_cache_root().path_join("Map.wz/Map/Map1/104040000.img.json")
	if not FileAccess.file_exists(path):
		return {}
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return d if d is Dictionary else {}
