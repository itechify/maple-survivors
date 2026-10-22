extends TestCase
## Flyer behaviour through the seeded RunWorld seam: air spawns, pursuit, touch, bounds and stage HP scaling.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const FLYERS := [9300063, 9300062, 9300064, 2300100]


func _air_world() -> RunWorld:
	var setup := RF.setup("quiet", 16, RF.quiet_data())
	# Pursuit probes have no basic attack: RF.setup carries no body or afterimage data to swing with.
	setup.map_img = RF.map_from_segments([{"x1": -100, "y1": 0, "x2": 100, "y2": 0}])
	setup.map_img.info = {"VRLeft": -1000, "VRRight": 1000, "VRTop": -1000, "VRBottom": 500}
	var img: Dictionary = setup.mob_imgs[100100]
	img.fly = img.move
	img.erase("move")
	img.erase("stand")
	img.info.flySpeed = 100.0
	var world := RunWorld.new(setup)
	RF.place_player(world, 0, -5)
	world.loadout.ranks.clear()
	world.loadout.order.clear()
	return world


func test_flyer_spawns_in_air_without_an_offscreen_floor() -> void:
	var world := _air_world()
	var kind := int(world.kind_of_id[100100])
	for n in 30:
		var p := world.director.pick_spawn(world, kind)
		var pos := Vector2(p.x, p.y)
		assert_eq(int(p.z), -1, "air spawn has no foothold")
		assert_true(world.bounds.has_point(pos), "air spawn stays in map bounds")
		assert_false(world.director.screen_rect(world).has_point(pos), "air spawn stays outside the screen")
		assert_true(pos.distance_to(world.player.pos) >= 200, "air spawn respects player distance")


func test_henesys_flyers_join_at_their_stage_times_only() -> void:
	var data := DataRepo.load_all()
	var stage: Dictionary = data.stages.stages.henesys
	var first := {}
	for keyframe: Dictionary in stage.keyframes:
		for id: int in FLYERS:
			if keyframe.pool.has(str(id)) and not first.has(id):
				first[id] = int(keyframe.t)
	assert_eq(first, {9300063: 180, 9300062: 300, 9300064: 480, 2300100: 660}, "3/5/8/11 minute flyer arrivals")
	var tree_ids := DataRepo.stage_mob_ids(data, "ellinia")
	for id: int in FLYERS:
		assert_false(id in tree_ids, "the Tree stage keeps ground mobs only")


func test_flyer_bobs_without_drifting_at_the_player() -> void:
	var world := _air_world()
	world.god = true
	var i := world.spawn_mob(int(world.kind_of_id[100100]), world.player.pos, -1, 1.0, false)
	var low := INF
	var high := -INF
	for tick in 180:
		world.step(DT, MoveInput.new())
		if tick > 30:
			low = minf(low, world.swarm.y[i])
			high = maxf(high, world.swarm.y[i])
	assert_true(high - low > 2.0, "a stationary flyer visibly bobs")
	assert_between(low, world.player.pos.y - 3.0, world.player.pos.y + 3.0, "no downward drift")
	assert_between(high, world.player.pos.y - 3.0, world.player.pos.y + 3.0, "no upward drift")


func test_director_scales_flyer_hp_at_spawn_time() -> void:
	for id: int in FLYERS:
		var data := RF.quiet_data()
		data.stages.stages.quiet.keyframes = [
			{"t": 0, "rate": 60, "max_alive": 1, "hp": 1, "speed": 1, "damage": 1, "pool": {str(id): 1}},
			{"t": 720, "rate": 60, "max_alive": 1, "hp": 3.4, "speed": 1, "damage": 1, "pool": {str(id): 1}}]
		var world := RunWorld.new(RF.setup("quiet", 16, data))
		world.time = 720.0 - DT
		world.god = true
		world.step(DT, MoveInput.new())
		var expected := {9300063: 204, 9300062: 272, 9300064: 527, 2300100: 1020}
		var spawned := false
		for event: Dictionary in world.drain_events():
			if event.type == "mob_spawned":
				spawned = true
				assert_eq(event.mob_id, id)
				assert_eq(world.swarm.max_hp[event.mob], expected[id], "canonical HP times the 12-minute HP keyframe")
		assert_true(spawned, "director spawned the flyer")


func test_far_flyer_relocates_to_air_without_losing_hp() -> void:
	var world := _air_world()
	world.god = true
	var kind := int(world.kind_of_id[100100])
	world.mob_kinds[kind].move_speed = 0.0
	var slot := world.spawn_mob(kind, Vector2(-990, -990), -1, 1.0, false)
	world.swarm.hp[slot] = 5
	world.drain_events()
	var relocations := 0
	for tick in 60 * 4:
		world.step(DT, MoveInput.new())
		for event: Dictionary in world.drain_events():
			if event.type == "mob_spawned" and event.relocated_from == slot:
				relocations += 1
				assert_eq(world.swarm.fh[event.mob], -1, "relocated flyer is still airborne")
				assert_eq(world.swarm.hp[event.mob], 5, "relocation preserves injured HP")
				assert_false(world.director.screen_rect(world).has_point(event.pos), "no visible relocation")
	assert_eq(relocations, 1, "an off-screen stalled flyer relocates rather than being discarded")
	assert_eq(world.director.recycled, 0, "a valid air spawn counts as a relocation")


func _real_world() -> RunWorld:
	var data := RF.quiet_data()
	# Observe flyer contact without an attacking camper (RF.setup has no body data, so no basic attack).
	var setup := RF.setup("quiet", 16, data)
	var lib := AssetLibrary.get_default()
	if not lib.has_img(DataRepo.map_img_path(104040000)):
		skip("cache lacks Henesys map")
		return null
	setup.map_img = lib.img(DataRepo.map_img_path(104040000)).root
	for id: int in FLYERS:
		if not lib.has_img(AssetLibrary.mob_img_path(id)):
			skip("cache lacks flyer %d (rerun import)" % id)
			return null
		setup.mob_imgs[id] = lib.mob_root(id)
	var world := RunWorld.new(setup)
	world.loadout.ranks.clear()
	world.loadout.order.clear()
	return world


func _wait_for_flyer_touch(world: RunWorld, id: int) -> void:
	var at := world.player.pos + Vector2(250, 250)
	var slot := world.spawn_mob(int(world.kind_of_id[id]), at, -1, 1.0, false)
	var start := world.player.pos
	var hit := false
	for tick in 60 * 20:
		world.step(DT, MoveInput.new())
		var pos := Vector2(world.swarm.x[slot], world.swarm.y[slot])
		assert_true(world.bounds.has_point(pos), "%d stays in bounds" % id)
		for event: Dictionary in world.drain_events():
			assert_false(event.type in ["boss_attack", "mob_attack"], "flyers emit no ranged attacks")
			if event.type == "player_hit" and not bool(event.get("miss", false)):
				hit = true
				assert_true(int(event.damage) > 0, "touch damage from the flyer")
		if hit:
			break
	assert_true(hit, "%d reaches and touches a camper at %s" % [id, start])
	assert_eq(world.swarm.fh[slot], -1, "flyer never lands on the intervening platforms")


func test_real_flyers_touch_a_camper_on_the_top_platform() -> void:
	if not require_cache():
		return
	for id: int in FLYERS:
		var world := _real_world()
		if world == null:
			return
		var top := -1
		var y := INF
		for f in world.fhm.count():
			if world.fhm.is_floor(f) and world.fhm.y1[f] < y:
				top = f
				y = world.fhm.y1[f]
		assert_true(top >= 0)
		var x := (world.fhm.x1[top] + world.fhm.x2[top]) * 0.5
		world.player.place(Vector2(x, y), world.fhm)
		world.update_view()
		_wait_for_flyer_touch(world, id)


func test_real_flyers_touch_a_camper_on_the_ground_rope() -> void:
	if not require_cache():
		return
	for id: int in FLYERS:
		var world := _real_world()
		if world == null:
			return
		var rope := -1
		var bottom := -INF
		for l in world.ladders.count():
			if world.ladders.is_ladder[l] == 0 and world.ladders.y2[l] > bottom:
				rope = l
				bottom = world.ladders.y2[l]
		assert_true(rope >= 0)
		world.player.pos = Vector2(world.ladders.x[rope], bottom)
		world.player.fh = -1
		world.player.vel = Vector2.ZERO
		var input := MoveInput.new()
		input.up = true
		world.step(DT, input)
		assert_eq(world.player.ladder, rope, "holding Up grabs the real ground rope")
		_wait_for_flyer_touch(world, id)
		assert_eq(world.player.ladder, rope, "contact damages the player while hanging")


func test_real_flyer_renderer_uses_fly_hit_and_die_stances() -> void:
	if not require_cache():
		return
	if _real_world() == null:
		return
	var renderer := MobRenderer.new()
	for id: int in FLYERS:
		for state: int in [MobSwarm.STAND, MobSwarm.MOVE, MobSwarm.HIT, MobSwarm.DIE]:
			var anim := renderer.anim_for(id, state)
			assert_true(anim != null, "%d has a rendered stance for state %d" % [id, state])
			if anim != null:
				var stance := "hit1" if state == MobSwarm.HIT else "die1" if state == MobSwarm.DIE else "fly"
				assert_eq(anim.path, "Mob.wz/%07d.img/%s" % [id, stance], "uses the canonical animation")
	assert_true(renderer.missing.is_empty(), "all flyer render assets present")
	renderer.free()
