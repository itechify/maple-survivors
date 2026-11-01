extends TestCase
## Dark Sight presentation against the real cache: the whole avatar fades as one image for the Form's window, then returns (SH11 #436).

const RF := preload("res://tests/fixtures/run_fixtures.gd")

var scene: RunScene


func after_each() -> void:
	if scene != null:
		scene.free()


func test_hidden_avatar_is_translucent_for_the_form_window_and_opacity_returns() -> void:
	if not require_cache_img("Skill.wz/422.img"):
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
	# #284: the fresh character is a 212 (its start skills cleared here); the Form is learned directly (SH11 #436: Dark Sight
	# is a pool Form of the Shadower now, not a passive-slot buff, and no job-400 card offers it).
	w.loadout.order.clear()
	w.loadout.ranks.clear()
	assert_true(w.learn_skill("dark_sight"))
	w.refresh_player_stats()
	var f := w.player.fh
	var m := w.spawn_mob(0, w.player.pos + Vector2(70, 0), f, 1.0, false)
	w.swarm.alpha[m] = 1.0
	# Keep the sole target alive for the whole window.
	w.swarm.hp[m] = 1000000
	w.swarm.max_hp[m] = 1000000
	for tick in 3:
		scene.advance_frame(1.0 / 60.0)
	assert_true(w.is_hidden(), "the learned Dark Sight starts its Form with a monster within 150 px")
	assert_eq(scene.avatar.morph_id, 0, "Dark Sight keeps the avatar")
	assert_near(scene.player_group.self_modulate.a, 0.5)
	for tick in 90:
		scene.advance_frame(1.0 / 60.0)
	assert_true(w.is_hidden(), "still Hidden 1.5 s in, through Assassinate's first cast")
	assert_near(scene.player_group.self_modulate.a, 0.5, 0.000001, "the whole avatar stays faded through the ambush")
	for tick in 260:
		scene.advance_frame(1.0 / 60.0)
	assert_false(w.is_hidden(), "the 5 s window is over")
	assert_near(scene.player_group.self_modulate.a, 1.0)
	assert_true(w.warnings.is_empty())
	assert_eq(scene.library.missing, PackedStringArray(), "no missing skill art")
	assert_eq(scene.avatar.missing, PackedStringArray(), "no missing avatar art")
