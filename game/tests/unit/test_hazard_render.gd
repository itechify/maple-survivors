extends TestCase
## The cached MobSkill 131 `tile` art of the poison mist (#459): the HazardRenderer's puff layout over the hazard's box and the
## live hazard through RunScene. Needs the asset cache.
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const TILE := "Skill.wz/MobSkill.img/131/level/7/tile"

var lib: AssetLibrary
var scene: RunScene
var view: HazardRenderer


func before_each() -> void:
	lib = AssetLibrary.new()
	lib.open()


func after_each() -> void:
	if scene != null:
		scene.free()
		scene = null
	if view != null:
		view.free()
		view = null
	lib.free()


func _hazards(rect: Rect2) -> GroundHazards:
	var pool := GroundHazards.new()
	pool.spawn({"rect": rect, "born": 10.0, "until": 20.0, "effect": GroundHazards.ICE, "tile_path": TILE, "tile_count": 11})
	return pool


## The tile art exists: 11 numbered animations of two alpha-fading frames each, no missing lookups.
func test_the_level_tile_animations_load() -> void:
	if not require_cache():
		return
	for tile in 11:
		var anim := lib.anim("%s/%d" % [TILE, tile])
		assert_true(anim != null and anim.frame_count() >= 2, "tile %d has its frames" % tile)
	assert_eq(lib.missing, PackedStringArray())


## One puff per grid cell over the box, every one inside it (within the jitter), the same layout for the same hazard
## and another for the next cast, and nothing once the hazard has ended.
func test_puffs_cover_the_box_and_follow_the_hazard_life() -> void:
	if not require_cache():
		return
	view = HazardRenderer.new()
	view.library = lib
	(Engine.get_main_loop() as SceneTree).current_scene.add_child(view)
	var rect := Rect2(550, 40, 350, 200)
	var pool := _hazards(rect)
	view.update_from(pool, 12.0)
	var cells := roundi(rect.size.x / HazardRenderer.PUFF_W) * roundi(rect.size.y / HazardRenderer.PUFF_H)
	assert_eq(view.visible_count(), cells, "one puff per cell: %d" % cells)
	var positions := HazardRenderer.puff_positions(rect, int(pool.generation[0]))
	assert_eq(positions.size(), cells)
	var padded := rect.grow_individual(HazardRenderer.JITTER.x, HazardRenderer.JITTER.y, HazardRenderer.JITTER.x, HazardRenderer.JITTER.y)
	for p in positions:
		assert_true(padded.has_point(p), "puff %s lies over the box" % p)
	assert_eq(HazardRenderer.puff_positions(rect, int(pool.generation[0])), positions, "deterministic")
	assert_ne(HazardRenderer.puff_positions(rect, int(pool.generation[0]) + 1), positions, "another cast looks different")
	var second := pool.spawn({"rect": Rect2(0, 0, 160, 112), "born": 10.0, "until": 20.0, "tile_path": TILE, "tile_count": 11})
	assert_eq(second, 1)
	view.update_from(pool, 12.0)
	assert_eq(view.visible_count(), cells + 4, "a second hazard adds its own puffs")
	view.update_from(pool, 20.0)
	assert_eq(view.visible_count(), 0, "nothing at its end")
	assert_eq(lib.missing, PackedStringArray(), "no missing MobSkill art")


## The mist fades in and out: transparent at the first and last instants, opaque between the FADE-second ramps.
func test_the_mist_fades_at_both_ends() -> void:
	assert_eq(HazardRenderer.fade_at(0.0, 10.0), 0.0)
	assert_near(HazardRenderer.fade_at(0.25, 9.75), 0.5, 1e-6)
	assert_eq(HazardRenderer.fade_at(5.0, 5.0), 1.0)
	assert_near(HazardRenderer.fade_at(9.75, 0.25), 0.5, 1e-6)
	assert_eq(HazardRenderer.fade_at(10.0, 0.0), 0.0)


## Through RunScene: Snowman's real 131/7 is cast, its puffs show over the box on the player's layer and go with the mist.
func test_a_cast_mist_is_drawn_and_removed_with_the_hazard() -> void:
	if not require_cache():
		return
	var sfx := (Engine.get_main_loop() as SceneTree).root.get_node("Sfx") as AudioService
	var previous_library := sfx.library
	sfx.library = lib
	var s: RunScene = (load(RunScene.SCENE_PATH) as PackedScene).instantiate()
	s.library = lib
	s.configure("henesys", 22, {"use_flow": false})
	(Engine.get_main_loop() as SceneTree).current_scene.add_child(s)
	scene = s
	var data := scene.data.duplicate(true)
	data.balance.bosses.teleport_stall = 10000.0
	RF.set_bosses(data.stages.stages.henesys, [{"mob_id": 2220000, "time": 0.0}])
	for keyframe: Dictionary in data.stages.stages.henesys.keyframes:
		keyframe.rate = 0
		keyframe.max_alive = 0
	var setup := DataRepo.build_setup(data, "henesys", 22, Vector2(800, 600),
		func(p: String) -> Dictionary: return lib.img(p).root if lib.img(p) != null else {}, lib.mob_root)
	setup.mob_imgs[2220000] = setup.mob_imgs[2220000].duplicate(true)
	setup.mob_imgs[2220000].info.skill = {"0": {"skill": 131.0, "level": 7.0, "action": 1.0, "effectAfter": 0.0}}
	setup.mob_imgs[2220000].info.speed = -100.0
	setup.mob_skill_img = setup.mob_skill_img.duplicate(true)
	setup.mob_skill_img["131"].level["7"].interval = 5.0
	setup.mob_skill_img["131"].level["7"].prop = 100.0
	scene.world = RunWorld.new(setup)
	var w := scene.world
	w.god = true
	for tick in 299:
		scene.advance_frame(DT)
	assert_eq(w.hazards.active_count(), 0)
	assert_eq(scene.hazard_view.visible_count(), 0)
	for tick in 3:
		scene.advance_frame(DT)
	assert_eq(w.hazards.active_count(), 1, "the boss cast its mist")
	assert_true(scene.hazard_view.visible_count() >= 12, "puffs are drawn: %d" % scene.hazard_view.visible_count())
	w.swarm.despawn(int(w.bosses.records[0].slot)) # no second cast while the first one is checked
	for tick in 660:
		scene.advance_frame(DT)
	assert_eq(w.hazards.active_count(), 0, "it ended after its 10 s")
	assert_eq(scene.hazard_view.visible_count(), 0, "and its puffs went with it")
	assert_eq(lib.missing, PackedStringArray(), "no missing MobSkill art")
	sfx.library = previous_library
