extends TestCase
## Flyer behaviour through the seeded RunWorld seam: air spawns, pursuit, touch, bounds and stage HP scaling.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const FLYERS := [9300063, 9300062, 9300064, 2300100]


func _air_world() -> RunWorld:
	var setup := RF.setup("quiet", 16, RF.quiet_data())
	setup.map_img = RF.map_from_segments([{ "x1": -100, "y1": 0, "x2": 100, "y2": 0 }])
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
	var stage: Dictionary = data.stages.stages.henesys_hg1
	var first := {}
	for keyframe: Dictionary in stage.keyframes:
		for id: int in FLYERS:
			if keyframe.pool.has(str(id)) and not first.has(id):
				first[id] = int(keyframe.t)
	assert_eq(first, {9300063: 180, 9300062: 300, 9300064: 480, 2300100: 660}, "3/5/8/11 minute flyer arrivals")
	var tree_ids := DataRepo.stage_mob_ids(data, "tree_that_grew_1")
	for id: int in FLYERS:
		assert_false(id in tree_ids, "the Tree stage keeps ground mobs only")
