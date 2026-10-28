extends TestCase
## Dark Sight presentation against the real cache: the whole avatar fades as one image, then returns on recovery.

const RF := preload("res://tests/fixtures/run_fixtures.gd")

var scene: RunScene


func after_each() -> void:
	if scene != null:
		scene.free()


func test_hidden_avatar_is_translucent_and_recovery_restores_opacity() -> void:
	if not require_cache():
		return
	scene = (load(RunScene.SCENE_PATH) as PackedScene).instantiate()
	scene.configure("henesys", 211, {"use_flow": false, "autopick": true})
	var tree := Engine.get_main_loop() as SceneTree
	tree.current_scene.add_child(scene)
	scene.set_process(false)
	var w := scene.world
	RF.as_job(w, 400, "dagger")
	w.pending_cards = []
	w.state = RunWorld.PLAYING
	# #284: the fresh character is a 212 (its start skills cleared here) and no job grants MP: give the pool the
	# removed Thief advancement added.
	w.loadout.order.clear()
	w.loadout.ranks.clear()
	w.loadout.add_player_mod("max_mp", "add", 37.0)
	w.refresh_player_stats()
	assert_eq(w.upgrades.apply("dark_sight_new", w), 1)
	w.heal_fraction("hp", 1.0)
	w.heal_fraction("hp", -1.0)
	w.heal_fraction("hp", 0.2)
	w.heal_fraction("mp", 1.0)
	var f := w.player.fh
	var m := w.spawn_mob(0, w.player.pos + Vector2(70, 0), f, 1.0, false)
	w.swarm.alpha[m] = 1.0
	# Keep the sole target alive for the escape cast.
	w.swarm.hp[m] = 1000000
	w.swarm.max_hp[m] = 1000000
	for tick in 3:
		scene.advance_frame(1.0 / 60.0)
	assert_true(w.is_hidden(), "the learned Dark Sight auto-casts")
	assert_eq(scene.avatar.morph_id, 0, "Dark Sight keeps the avatar")
	assert_near(scene.player_group.self_modulate.a, 0.5)
	w.heal_fraction("hp", 1.0)
	scene.advance_frame(1.0 / 60.0)
	assert_false(w.is_hidden())
	assert_near(scene.player_group.self_modulate.a, 1.0)
	assert_true(w.warnings.is_empty())
	assert_eq(scene.library.missing, PackedStringArray(), "no missing skill art")
	assert_eq(scene.avatar.missing, PackedStringArray(), "no missing avatar art")
