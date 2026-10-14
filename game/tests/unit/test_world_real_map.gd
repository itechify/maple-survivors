extends TestCase
## Sim-world against the real v83 Henesys Hunting Ground I (104040000) from the imported asset cache. Loads the img
## JSON directly (FileAccess + JSON) so it does not depend on the Assets autoload. SKIPs without the cache.

const WF := preload("res://tests/fixtures/world_fixtures.gd")
const MAP := "Map.wz/Map/Map1/104040000.img"
const DT := 1.0 / 60.0


func _img(path: String) -> Dictionary:
	var file := AssetCachePaths.resolve_cache_root().path_join(path + ".json")
	if not FileAccess.file_exists(file):
		return {}
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(file))
	return d if d is Dictionary else {}


func _map() -> Dictionary:
	if not require_cache():
		return {}
	var img := _img(MAP)
	if img.is_empty():
		skip("cache has no %s" % MAP)
	return img


func _bottom(m: FootholdMap) -> int:
	return m.platform_of(m.find_below(600.0, 200.0))


func test_real_footholds_and_bounds() -> void:
	var img := _map()
	if img.is_empty():
		return
	var m := FootholdMap.from_wz(img)
	assert_eq(m.count(), 181, "foothold count")
	assert_eq(m.bounds(), Rect2(-489, -1105, 2238, 1585), "foothold bbox (docs/research/wz-inventory.md)")
	assert_true(m.platform_count() > 1)
	assert_eq(m.platform_count(), 23, "maximal floor chains")
	var bottom := _bottom(m)
	assert_eq(m.platform_span(bottom), Vector2(-489, 1749), "the ground spans the map")
	var b := MapBounds.from_map(img, m)
	assert_eq(b, Rect2(-530, -1278, 2317, 1832), "no VR: miniMap rect")
	assert_true(b.encloses(m.bounds()), "bounds contain every foothold")
	var l := LadderSet.from_wz(img)
	assert_eq(l.count(), 8)


func test_real_nav_routes() -> void:
	var img := _map()
	if img.is_empty():
		return
	var m := FootholdMap.from_wz(img)
	var walk := NavGraph.build(m, {"can_jump": false})
	var jump := NavGraph.build(m, {"can_jump": true})
	var bottom := _bottom(m)
	var n := m.platform_count()
	var to_bottom := 0
	var up_jump := 0
	var up_walk := 0
	for p in n:
		if p == bottom:
			continue
		if walk.reachable(p, bottom):
			to_bottom += 1
		if jump.reachable(bottom, p):
			up_jump += 1
		if walk.reachable(bottom, p):
			up_walk += 1
	print("  104040000: %d platforms, %d walker / %d jumper edges; %d/%d reach the ground by dropping; jumper from the ground reaches %d, walker %d" % [
		n, walk.edge_count(), jump.edge_count(), to_bottom, n - 1, up_jump, up_walk])
	assert_eq(to_bottom, n - 1, "every platform reaches the ground by dropping")
	assert_eq(up_walk, 0, "walkers never go up")
	# The tiers (y 215 / -85 / -325 / -565 / -1105, 240 px apart) are joined only by ladders and ropes, so a 70 px
	# hop reaches just the low step platforms next to the ground.
	assert_true(up_jump >= 4, "jumper reaches the step platforms from the ground (%d)" % up_jump)
	for p in n:
		for q in n:
			if jump.reachable(p, q) and p != q:
				var e := jump.route(p, q)
				assert_eq(jump.e_from[e], p, "route starts on its platform")


func test_real_player_lands_from_every_spawn_portal() -> void:
	var img := _map()
	if img.is_empty():
		return
	var m := FootholdMap.from_wz(img)
	var l := LadderSet.from_wz(img)
	var b := MapBounds.from_map(img, m)
	var phys := PhysicsConstants.from_wz(_img("Map.wz/Physics.img")) if not _img("Map.wz/Physics.img").is_empty() \
		else PhysicsConstants.v83_defaults()
	var portals := 0
	for key: String in img.get("portal", {}):
		var pt: Dictionary = img.portal[key]
		if String(pt.get("pn", "")) != "sp":
			continue
		portals += 1
		var p := PlayerMotion.new(phys)
		p.place(Vector2(float(pt.x), float(pt.y)), m)
		var still := MoveInput.new()
		for t in 180:
			p.step(DT, still, m, l, b)
		assert_true(p.fh >= 0, "portal %s at (%s, %s) lands on a foothold" % [key, pt.x, pt.y])
		if p.fh >= 0:
			assert_near(p.pos.y, m.y_at(p.fh, p.pos.x), 1e-3)
			assert_near(p.pos.x, float(pt.x), 10.0, "falls straight down (then may slide a little on a slope)")
	assert_eq(portals, 14, "spawn portals")


func test_real_physics_and_mobs() -> void:
	if not require_cache():
		return
	var phys_img := _img("Map.wz/Physics.img")
	if phys_img.is_empty():
		skip("cache has no Map.wz/Physics.img")
		return
	var c := PhysicsConstants.from_wz(phys_img)
	var d := PhysicsConstants.v83_defaults()
	for key: String in PhysicsConstants.WZ_KEYS:
		var field: String = PhysicsConstants.WZ_KEYS[key]
		assert_near(c.get(field), d.get(field), 1e-6, key)
	var snail_img := _img("Mob.wz/0100100.img")
	if not snail_img.is_empty():
		var snail := MobKind.from_wz(snail_img, 100100)
		assert_near(snail.move_speed, 21.875, 1e-6)
		assert_false(snail.can_jump)
		assert_near(snail.die_time, 1.26, 1e-6)
		assert_eq(snail.hitbox, Rect2(-18, -26, 37, 26))
	var pig_img := _img("Mob.wz/1210100.img")
	if not pig_img.is_empty():
		var pig := MobKind.from_wz(pig_img, 1210100)
		assert_true(pig.can_jump, "Pig has a jump stance")
		assert_near(pig.move_speed, 62.5, 1e-6)


func test_real_swarm_invariants() -> void:
	var img := _map()
	if img.is_empty():
		return
	var m := FootholdMap.from_wz(img)
	var bounds := MapBounds.from_map(img, m)
	var kinds: Array = [
		MobKind.from_wz(WF.mob_img(false), 1, {"speed_mult": 3.0}),
		MobKind.from_wz(WF.mob_img(true), 2, {"speed_mult": 1.5}),
	]
	var ctx := {
		"fhm": m, "nav": NavGraph.build(m, {"can_jump": false}), "nav_jump": NavGraph.build(m, {"can_jump": true}),
		"bounds": bounds, "target": Vector2.ZERO, "target_fh": -1,
	}
	var s := MobSwarm.new(64, kinds)
	var rng := RandomNumberGenerator.new()
	rng.seed = 104040000
	var floors: Array = []
	for f in m.count():
		if m.is_floor(f):
			floors.append(f)
	for n in 200:
		var f: int = floors[rng.randi_range(0, floors.size() - 1)]
		s.spawn(n % 2, rng.randf_range(m.x1[f], m.x2[f]), 0.0, f)
	var bottom := _bottom(m)
	for t in 1200:
		if t % 180 == 0:
			var f: int = floors[rng.randi_range(0, floors.size() - 1)]
			var tx := rng.randf_range(m.x1[f], m.x2[f])
			ctx.target = Vector2(tx, m.y_at(f, tx))
			ctx.target_fh = f
		var px := s.x.duplicate()
		var py := s.y.duplicate()
		var was := s.active.duplicate()
		s.step(DT, ctx)
		for v in WF.swarm_violations(s, m, bounds, px, py, was, "tick %d" % t):
			fail(v)
	assert_eq(s.lost_count, 0, "nobody fell out of the world")
	assert_eq(s.alive_count(), 200)
	# Finally chase a player on the ground: after 20 s most mobs that can reach it are on the ground platform.
	var gx := 600.0
	ctx.target = Vector2(gx, m.y_at(m.find_below(gx, 200.0), gx))
	ctx.target_fh = m.find_below(gx, 200.0)
	for t in 1200:
		s.step(DT, ctx)
	var on_ground := 0
	for i in s.capacity():
		if s.state[i] != MobSwarm.FREE and s.platform[i] == bottom:
			on_ground += 1
	assert_true(on_ground >= 150, "mobs converged on the ground (%d/200)" % on_ground)


## Every NavGraph edge on every cached v83 map is executed as the graph says: a mob placed just before the takeoff
## and chasing a target on the edge's to_p lands first on to_p, at slow and fast speeds (Snail walkers, Slime
## jumpers; x0.5 .. x4), and nobody falls out of the world.
func test_real_every_edge_lands_where_the_graph_says() -> void:
	if not require_cache():
		return
	var phys_img := _img("Map.wz/Physics.img")
	var phys := PhysicsConstants.from_wz(phys_img) if not phys_img.is_empty() else PhysicsConstants.v83_defaults()
	var nav_opts := {"gravity": phys.gravity_acc, "fall_speed": phys.fall_speed, "jump_speed": phys.jump_speed}
	var snail_img := _img("Mob.wz/0100100.img")
	var slime_img := _img("Mob.wz/0210100.img")
	var walker := MobKind.from_wz(snail_img if not snail_img.is_empty() else WF.mob_img(false), 100100)
	var jumper := MobKind.from_wz(slime_img if not slime_img.is_empty() else WF.mob_img(true), 210100)
	assert_false(walker.can_jump)
	assert_true(jumper.can_jump)
	var maps_done := 0
	for map_id: String in ["104040000", "100010000", "101010100"]:
		var img := _img("Map.wz/Map/Map%s/%s.img" % [map_id.substr(0, 1), map_id])
		if img.is_empty():
			print("  %s: not in the cache, skipped" % map_id)
			continue
		maps_done += 1
		var m := FootholdMap.from_wz(img)
		var w_opts := nav_opts.duplicate()
		w_opts["can_jump"] = false
		var nav_w := NavGraph.build(m, w_opts)
		var nav_j := NavGraph.build(m, nav_opts)
		var bounds := MapBounds.from_map(img, m)
		var trials := 0
		var bad := 0
		var lost := 0
		for mk: MobKind in [walker, jumper]:
			var nav := nav_j if mk.can_jump else nav_w
			for e in nav.edge_count():
				var d := nav.edge(e)
				var sp := m.platform_span(d.from_p)
				var toward: float = d.x_to - d.x_from if d.kind == "jump" else d.vx
				var x0: float = clampf(d.x_from - signf(toward) * 12.0, sp.x, sp.y)
				if m.platform_fh_at(d.from_p, x0) < 0:
					x0 = d.x_from
				var tsp := m.platform_span(d.to_p)
				var tx := (tsp.x + tsp.y) * 0.5
				if m.platform_fh_at(d.to_p, tx) < 0:
					tx = tsp.x
				for smult: float in [0.5, 1.0, 1.3, 4.0]:
					trials += 1
					var r := _first_landing(m, mk, bounds, nav_w, nav_j, phys, d.from_p, x0, d.to_p, tx, smult)
					lost += r.y
					if r.x != d.to_p:
						bad += 1
						fail("%s %s x%s edge %d %s: first landing on platform %d" % [map_id,
							"jumper" if mk.can_jump else "walker", smult, e, d, r.x])
		print("  %s: %d platforms, %d walker / %d jumper edges, %d trials, %d wrong landings, %d lost" % [map_id,
			m.platform_count(), nav_w.edge_count(), nav_j.edge_count(), trials, bad, lost])
		assert_eq(lost, 0, "%s: nobody fell out of the world" % map_id)
	assert_true(maps_done >= 1, "at least the stage map is cached")


## Platform of the first landing after the mob leaves the ground (x; -1 = none) and lost_count (y).
func _first_landing(m: FootholdMap, mk: MobKind, bounds: Rect2, nav_w: NavGraph, nav_j: NavGraph,
		phys: PhysicsConstants, from_p: int, x0: float, to_p: int, tx: float, smult: float) -> Vector2i:
	var s := MobSwarm.new(2, [mk])
	var tf := m.platform_fh_at(to_p, tx)
	var ctx := {"fhm": m, "nav": nav_w, "nav_jump": nav_j, "bounds": bounds, "physics": phys,
		"target": Vector2(tx, m.y_at(tf, tx)), "target_fh": tf, "speed_mult": smult}
	var i := s.spawn(0, x0, 0.0, m.platform_fh_at(from_p, x0))
	var left := false
	for t in 3600:
		s.step(DT, ctx)
		if s.state[i] == MobSwarm.FREE:
			break
		if s.fh[i] < 0:
			left = true
		elif left:
			return Vector2i(s.platform[i], s.lost_count)
	return Vector2i(-1, s.lost_count)
