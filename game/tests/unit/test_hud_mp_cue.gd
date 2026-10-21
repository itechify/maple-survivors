extends TestCase
## MP-wait feedback follows current pools across held choices and stops at terminal presentation boundaries.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0


func _waiting_world() -> RunWorld:
	var data := RF.quiet_data()
	data.balance.player.skills = []
	var w := RunWorld.new(RF.setup("quiet", 9, data))
	RF.change_job_bare(w, 200)
	w.learn_skill("energy_bolt")
	RF.place_player(w, 1200)
	RF.put_mob(w, 1110100, 1350, 190, 100)
	w.mob_kinds[int(w.kind_of_id[1110100])].move_speed = 0
	w.god = true
	w.spend_mp(int(w.player_state.mp))
	w.step(DT, MoveInput.new())
	assert_true(w.player_state.mp_short, "a living targeted skill waits for MP")
	return w


func test_level_up_refill_clears_the_cue_before_the_held_choice_resumes() -> void:
	var w := _waiting_world()
	w.pickups.spawn(w.player.pos, w.progression.exp_to_next(), 4000019)
	for tick in 120:
		w.step(DT, MoveInput.new())
		if w.state != RunWorld.PLAYING:
			break
	assert_eq(w.state, RunWorld.CHOOSING_UPGRADE, "a real EXP pickup holds the run for a choice")
	assert_eq(w.player_state.mp, w.player_state.max_mp, "level-up filled the new MP pool")
	assert_false(w.player_state.mp_short, "the snapshot no longer repeats the pre-refill cast result")
	var messages := HudMessages.new()
	messages.update(w.player_state, {})
	assert_false(messages.low_mp_visible(), "no warning over the full-MP choice")
	messages.free()


func test_death_clears_the_waiting_snapshot_without_another_cast_scan() -> void:
	var w := _waiting_world()
	w.god = false
	w.take_hit(1000000, false, "", w.player.pos + Vector2(100, 0))
	assert_eq(w.state, RunWorld.DEAD)
	assert_true(w.player_state.dead)
	assert_false(w.player_state.mp_short, "death cannot leave an actionable MP-wait snapshot")


func test_held_choice_keeps_the_cue_when_a_refill_still_cannot_pay() -> void:
	var w := _waiting_world()
	w.balance.level_up_refill = {"hp": 0.0, "mp": 0.0}
	w.pickups.spawn(w.player.pos, w.progression.exp_to_next(), 4000019)
	for tick in 120:
		w.step(DT, MoveInput.new())
		if w.state != RunWorld.PLAYING:
			break
	assert_eq(w.state, RunWorld.CHOOSING_UPGRADE)
	assert_true(w.player_state.mp_short, "a choice alone does not suppress a real shortage")


func test_hud_suppresses_stale_waiting_flags_for_death_clear_and_ending() -> void:
	var w := _waiting_world()
	var scene := RunScene.new()
	scene.world = w
	scene.hud = Hud.new()
	(Engine.get_main_loop() as SceneTree).current_scene.add_child(scene.hud)
	scene._update_hud()
	assert_true(scene.hud.low_mp_visible(), "living MP-wait is visible")
	for state: int in [RunWorld.DEAD, RunWorld.CLEARED]:
		w.state = state
		scene._update_hud()
		assert_false(scene.hud.low_mp_visible(), "terminal state %d hides a stale snapshot" % state)
	w.state = RunWorld.PLAYING
	scene._update_hud()
	assert_true(scene.hud.low_mp_visible())
	scene.set("_end_kind", "cleared")
	scene._update_hud()
	assert_false(scene.hud.low_mp_visible(), "ending hides the cue even before the next sim snapshot")
	scene.hud.free()
	scene.free()
