extends TestCase
## The pet in the round simulation (spec #34, ticket #119): it exists only with an owned pet out, follows the player on
## the footholds with the player's physics, and teleports to the player when left behind.

const PF := preload("res://tests/fixtures/pet_fixtures.gd")


func test_no_pet_out_means_no_pet_state() -> void:
	var w := RunWorld.new(PF.setup(PF.data(), 0, [PF.KITTY]))
	assert_true(w.pet_system == null, "no pet worn: no pet simulation")
	assert_eq(w.pet_state(), {})
	var unowned := RunWorld.new(PF.setup(PF.data(), PF.KITTY, []))
	assert_true(unowned.pet_system == null, "a pet the account does not own is not out")


func test_pet_state_is_exposed_for_drawing() -> void:
	var w := PF.world([PF.KITTY])
	var state := w.pet_state()
	assert_eq(state.species, PF.KITTY)
	assert_eq(state.action, "stand")
	assert_true(state.facing == 1 or state.facing == -1)
	assert_eq(state.abilities, {"auto_hp": false, "auto_mp": false, "wing_boots": false, "binocular": false,
		"vac": false})
	assert_near(state.pos.distance_to(w.player.pos), 0.0, 1.0, "starts at the player")
	assert_eq(PF.world([PF.KITTY, PF.WING]).pet_state().abilities.wing_boots, true)
	assert_eq(PF.world(PF.EVERYTHING).pet_state().abilities,
		{"auto_hp": true, "auto_mp": true, "wing_boots": true, "binocular": true, "vac": true})


func test_pet_walks_after_the_player_without_teleporting() -> void:
	var w := PF.world()
	PF.put_player(w, 300.0, 0.0)
	PF.put_pet(w, Vector2(80.0, 0.0))
	var events := PF.run(w, 4, MoveInput.new())
	assert_eq(w.pet_state().action, "move", "walking toward the player")
	events.append_array(PF.run(w, 240))
	var state := w.pet_state()
	assert_between(state.pos.x, 300.0 - 60.0, 300.0 + 60.0, "caught up: x=%.1f" % state.pos.x)
	assert_eq(state.pos.y, 0.0)
	assert_eq(state.action, "stand")
	assert_eq(PF.of_type(events, "pet_teleported").size(), 0)


func test_pet_hops_up_onto_the_platform_the_player_stands_on() -> void:
	var w := PF.world()
	PF.put_player(w, 250.0, -60.0)
	PF.put_pet(w, Vector2(0.0, 0.0))
	var events := PF.run(w, 300)
	var state := w.pet_state()
	assert_eq(state.pos.y, -60.0, "on the low platform: %s" % state.pos)
	assert_between(state.pos.x, 250.0 - 60.0, 250.0 + 60.0)
	assert_eq(PF.of_type(events, "pet_teleported").size(), 0, "it walked and jumped, no teleport")


func test_pet_drops_down_after_the_player() -> void:
	var w := PF.world()
	PF.put_player(w, 250.0, 0.0)
	PF.put_pet(w, Vector2(250.0, -60.0))
	var events := PF.run(w, 240)
	assert_eq(w.pet_state().pos.y, 0.0, "back on the ground")
	assert_eq(PF.of_type(events, "pet_teleported").size(), 0)


func test_pet_uses_the_jump_action_in_the_air() -> void:
	var w := PF.world()
	PF.put_player(w, 250.0, -60.0)
	PF.put_pet(w, Vector2(200.0, 0.0))
	var seen := {}
	for i in 120:
		PF.run(w, 1)
		seen[w.pet_state().action] = true
	assert_true(seen.has("jump"), "airborne while hopping up: %s" % [seen.keys()])


func test_pet_teleports_when_it_is_too_far() -> void:
	var w := PF.world()
	PF.put_pet(w, Vector2(30.0, 0.0))
	PF.put_player(w, 1100.0, 0.0)
	var events := PF.run(w, 2)
	var tele := PF.of_type(events, "pet_teleported")
	assert_eq(tele.size(), 1)
	assert_near(w.pet_state().pos.x, 1100.0, 1.0)
	assert_eq(tele[0].from, Vector2(30.0, 0.0))


func test_pet_teleports_when_it_stays_out_of_reach_too_long() -> void:
	# The top platform is two jumps above the ground: the pet cannot get there, so it is left behind.
	var w := PF.world([PF.KITTY], {}, PF.data({"lost_distance": 100.0, "lost_seconds": 1.0}))
	PF.put_pet(w, Vector2(300.0, 0.0))
	PF.put_player(w, 360.0, -120.0)
	var early := PF.run(w, 50)
	assert_eq(PF.of_type(early, "pet_teleported").size(), 0, "not yet: %.2f s" % w.time)
	var late := PF.run(w, 20)
	assert_eq(PF.of_type(late, "pet_teleported").size(), 1)
	assert_between(w.pet_state().pos.distance_to(w.player.pos), 0.0, 5.0)


func test_pet_hangs_while_the_player_climbs() -> void:
	var s := PF.setup(PF.data(), PF.KITTY, [PF.KITTY])
	s.map_img = PF.RF.big_map_img()
	var w := RunWorld.new(s)
	# A rope at x=-100 spans y 82..198 on the big map: grab it and climb.
	w.player.place(Vector2(-100.0, 200.0), w.fhm)
	w.update_view()
	w.pet_system.place(Vector2(-100.0, 200.0), w.fhm)
	var up := MoveInput.make(false, false, true)
	PF.run(w, 20, up)
	assert_eq(w.player.state, PlayerMotion.ST_LADDER)
	assert_eq(w.pet_state().action, "hang")
	assert_eq(w.pet_state().pos.x, w.player.pos.x)
	PF.run(w, 1, MoveInput.make(true, false, false, false, true, true))
	PF.run(w, 90)
	assert_ne(w.pet_state().action, "hang", "back on its feet once the player lets go")
