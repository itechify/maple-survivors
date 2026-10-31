extends TestCase
## The cached MobSkill 123 `affected` art above the character follows the live Stun through RunScene (#456).
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0

var lib: AssetLibrary
var scene: RunScene


func before_each() -> void:
	lib = AssetLibrary.new()
	lib.open()


func after_each() -> void:
	if scene != null:
		scene.free()
	lib.free()


func _make(stage: String, seed_value: int, options: Dictionary) -> RunScene:
	var s: RunScene = (load(RunScene.SCENE_PATH) as PackedScene).instantiate()
	s.library = lib
	options["use_flow"] = false
	s.configure(stage, seed_value, options)
	(Engine.get_main_loop() as SceneTree).current_scene.add_child(s)
	return s


func _frames(n: int) -> void:
	for tick in n:
		scene.advance_frame(DT)


## The art loops while the sim status lasts (past its own 300 ms cycle) and stops with it; a second Stun is another fx.
func test_player_stun_uses_repeating_art_until_sim_expiry() -> void:
	if not require_cache():
		return
	var sfx := (Engine.get_main_loop() as SceneTree).root.get_node("Sfx") as AudioService
	var previous_library := sfx.library
	sfx.library = lib
	scene = _make("henesys", 22, {})
	var data := scene.data.duplicate(true)
	data.balance.bosses.teleport_stall = 10000.0
	RF.set_bosses(data.stages.stages.henesys, [{"mob_id": 2220000, "time": 0.0}])
	for keyframe: Dictionary in data.stages.stages.henesys.keyframes:
		keyframe.rate = 0
		keyframe.max_alive = 0
	var setup := DataRepo.build_setup(data, "henesys", 22, Vector2(800, 600),
		func(p: String) -> Dictionary: return lib.img(p).root if lib.img(p) != null else {}, lib.mob_root)
	setup.mob_imgs[2220000] = setup.mob_imgs[2220000].duplicate(true)
	setup.mob_imgs[2220000].info.skill = {"0": {"skill": 123.0, "level": 8.0, "action": 1.0, "effectAfter": 0.0}}
	setup.mob_imgs[2220000].info.speed = -100.0
	setup.mob_skill_img = setup.mob_skill_img.duplicate(true)
	setup.mob_skill_img["123"].level["8"].prop = 100.0
	scene.world = RunWorld.new(setup)
	var w := scene.world
	w.god = true
	_frames(899)
	var boss := int(w.bosses.records[0].slot)
	w.player.place(w.swarm.pos(boss) + Vector2(-50, 0), w.fhm)
	_frames(2)
	var slot := int(w.bosses.records[0].slot)
	assert_false(w.can_cast())
	assert_eq(w.bosses.action_snapshot(w.swarm).actions[slot], "skill1", "canonical boss skill stance")
	assert_true(scene.fx.active_count() >= 1, "stun affected animation plays")
	w.swarm.despawn(slot)
	_frames(60)
	scene.fx.advance(1.0)
	assert_true(scene.fx.active_count() >= 1, "stun art repeats beyond its 300ms cycle")
	_frames(60)
	assert_eq(scene.fx.active_count(), 0, "the affected effect ends with canonical duration")
	assert_true(lib.anim("Skill.wz/MobSkill.img/123/level/8/affected").frames.size() > 0)
	assert_eq(lib.missing, PackedStringArray(), "no missing MobSkill art")
	sfx.library = previous_library
