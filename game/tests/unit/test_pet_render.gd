extends TestCase
## Drawing the pet (spec #34, ticket #120): which Item.wz/Pet animation a simulated action shows, the Free Market
## follower (same PetSystem as a round), and the real-cache check that all curated species draw with nothing missing.

const FM := preload("res://tests/unit/test_free_market.gd")
const DT := 1.0 / 60.0
const SPECIES := [5000000, 5000001, 5000002]


func _hub_with_pet() -> FreeMarketMotion:
	var hub := FreeMarketMotion.new(FM.hub_map())
	hub.set_pet(5000000, {})
	return hub


func test_action_picks_the_matching_pet_animation() -> void:
	assert_eq(PetRenderer.anim_name("stand", false), "stand0")
	assert_eq(PetRenderer.anim_name("move", false), "move")
	assert_eq(PetRenderer.anim_name("jump", false), "jump")
	assert_eq(PetRenderer.anim_name("hang", false), "hang")
	assert_eq(PetRenderer.anim_name("jump", true), "fly", "airborne on the way to a drop (Wing Boots) flies")
	assert_eq(PetRenderer.anim_name("move", true), "move")
	assert_eq(PetRenderer.anim_name("bogus", false), "stand0", "unknown actions fall back to standing")
	assert_eq(PetRenderer.anim_path(5000002, "move"), "Item.wz/Pet/5000002.img/move")


func test_hanging_pet_is_drawn_beside_the_climber_not_behind_it() -> void:
	assert_eq(PetRenderer.hang_offset("hang", 1), Vector2(-22, 0))
	assert_eq(PetRenderer.hang_offset("hang", -1), Vector2(22, 0))
	assert_eq(PetRenderer.hang_offset("move", 1), Vector2.ZERO)


func test_wz_pets_face_left_so_facing_right_mirrors() -> void:
	assert_true(PetRenderer.flipped(1))
	assert_false(PetRenderer.flipped(-1))


func test_free_market_brings_only_the_owned_pet_the_character_has_out() -> void:
	var data := DataRepo.load_all()
	assert_eq(FreeMarket.owned_pet({"pet": 5000001}, data, [5000001]), 5000001)
	assert_eq(FreeMarket.owned_pet({"pet": 5000001}, data, [5000000]), 0, "a pet the account does not own is not out")
	assert_eq(FreeMarket.owned_pet({}, data, [5000000]), 0, "no pet out")
	assert_eq(FreeMarket.owned_pet({"pet": 1812002}, data, [1812002]), 0, "an upgrade is not a pet")


func test_free_market_without_a_pet_has_no_pet_state() -> void:
	var hub := FreeMarketMotion.new(FM.hub_map())
	assert_eq(hub.pet_state(), {})
	hub.step(DT, MoveInput.new())
	assert_eq(hub.pet_state(), {})


func test_free_market_pet_follows_the_player_with_the_round_controller() -> void:
	var hub := _hub_with_pet()
	assert_true(hub.pet is PetSystem, "the hub reuses the sim pet controller")
	hub.player.place(Vector2(100, 200), hub.fhm)
	hub.pet.place(Vector2(100, 200), hub.fhm)
	var seen_move := false
	for tick in 240:
		hub.step(DT, MoveInput.make(false, true))
		seen_move = seen_move or hub.pet_state().action == "move"
	assert_true(seen_move, "the pet walks while the player does")
	for tick in 120:
		hub.step(DT, MoveInput.new())
	var state := hub.pet_state()
	assert_eq(state.species, 5000000)
	assert_between(state.pos.x, hub.player.pos.x - 60.0, hub.player.pos.x + 60.0, "caught up: %s" % state.pos)
	assert_eq(state.pos.y, 200.0, "on the same floor")
	assert_eq(state.action, "stand")


func test_free_market_pet_snaps_with_the_player_through_a_portal_and_says_so() -> void:
	var map := FM.hub_map()
	map.portal["3"] = {"pn": "up00", "pt": 1, "x": 800, "y": 200, "tm": 910000000, "tn": "up01"}
	map.portal["4"] = {"pn": "up01", "pt": 1, "x": 1000, "y": 200, "tm": 999999999, "tn": ""}
	var hub := FreeMarketMotion.new(map)
	hub.set_pet(5000001, {})
	hub.player.place(Vector2(800, 200), hub.fhm)
	hub.pet.place(Vector2(800, 200), hub.fhm)
	var events := hub.step(DT, MoveInput.make(false, false, true))
	var teleports := events.filter(func(e: Dictionary) -> bool: return e.type == "pet_teleported")
	assert_eq(teleports.size(), 1, "the portal moves the pet at once, announced like a round teleport")
	assert_eq(hub.pet_state().pos, hub.player.pos)
	assert_eq(teleports[0].pos, hub.player.pos)


func test_free_market_pet_hangs_on_the_rope_with_the_player() -> void:
	var map := FM.hub_map()
	map.ladderRope = {"0": {"l": 1, "uf": 1, "x": 100, "y1": 0, "y2": 200}}
	var hub := FreeMarketMotion.new(map)
	hub.set_pet(5000002, {})
	hub.player.place(Vector2(100, 200), hub.fhm)
	hub.pet.place(Vector2(100, 200), hub.fhm)
	for tick in 30:
		hub.step(DT, MoveInput.make(false, false, true))
	assert_eq(hub.player.state, PlayerMotion.ST_LADDER)
	assert_eq(hub.pet_state().action, "hang")
	assert_eq(hub.pet_state().pos, hub.player.pos)


func test_real_cache_every_curated_species_draws_each_action_with_nothing_missing() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.get_default()
	lib.clear_missing()
	for species: int in SPECIES:
		var renderer := PetRenderer.new()
		renderer.library = lib
		(Engine.get_main_loop() as SceneTree).current_scene.add_child(renderer)
		for action: String in ["stand", "move", "jump", "hang"]:
			renderer.show_state({"species": species, "pos": Vector2(50, 60), "facing": 1, "action": action,
				"fetching": false, "abilities": {}}, 0.0)
			assert_true(renderer.visible, "%d %s is drawn" % [species, action])
			assert_eq(renderer.shown_anim, PetRenderer.anim_name(action, false))
			assert_true(renderer.frame_count() >= 1)
			assert_eq(renderer.position, Vector2(50, 60) + PetRenderer.hang_offset(action, 1))
			renderer.show_state({"species": species, "pos": Vector2(50, 60), "facing": -1, "action": action,
				"fetching": false, "abilities": {}}, 0.5)
		renderer.show_state({"species": species, "pos": Vector2(0, 0), "facing": 1, "action": "jump",
			"fetching": true, "abilities": {}}, 0.0)
		assert_eq(renderer.shown_anim, "fly")
		assert_true(lib.frame("Item.wz/Pet/%07d.img/info/icon" % species) != null, "%d icon" % species)
		renderer.hide_pet()
		assert_false(renderer.visible)
		renderer.free()
	assert_eq(lib.missing, PackedStringArray(), "no failed lookups")
