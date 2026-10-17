extends TestCase
## What the pet collects (spec #34, ticket #119): every drop kind inside its small radius, on top of the player's
## magnet and credited as if the player took it; Binocular widens the radius, Wing Boots fetch within the leash, VAC
## pulls every drop on the map.

const PF := preload("res://tests/fixtures/pet_fixtures.gd")
const FAR := Vector2(1100.0, 0.0)


## A world whose pet stands far from the player (so the player's magnet is out of the picture) and stays there.
func _far_pet_world(owned: Array = [PF.KITTY]) -> RunWorld:
	var w := PF.world(owned, {}, PF.data({"lost_seconds": 1000.0, "teleport_distance": 5000.0, "lost_distance": 5000.0}))
	PF.put_player(w, 100.0, 0.0)
	PF.put_pet(w, FAR)
	return w


## Drops EXP `exp` at (x, 0) already at rest, without stepping the world.
func _rest_drop(w: RunWorld, x: float, exp := 7) -> int:
	var slot := w.pickups.spawn(Vector2(x, 0.0), exp, 1)
	w.pickups.state[slot] = PickupSystem.REST
	w.pickups.vx[slot] = 0.0
	w.pickups.vy[slot] = 0.0
	return slot


func test_pet_collects_a_drop_inside_its_radius_and_not_outside() -> void:
	var w := _far_pet_world()
	var near := _rest_drop(w, FAR.x + 40.0)
	var outside := _rest_drop(w, FAR.x + 120.0)
	var events := PF.run(w, 3)
	var got := PF.of_type(events, "pickup_collected")
	assert_eq(got.size(), 1)
	assert_eq(got[0].pickup, near)
	assert_eq(got[0].collector, "pet", "the event says the pet collected it")
	assert_eq(w.pickups.active[outside], 1, "120 px away stays on the ground")


func test_the_pets_pickup_is_credited_to_the_player() -> void:
	var w := _far_pet_world()
	assert_eq(int(w.player_state.level), 1)
	_rest_drop(w, FAR.x + 10.0, 3)
	PF.run(w, 2)
	assert_eq(w.pickups.collected_exp, 3)
	assert_eq(int(w.player_state.exp), 3, "the EXP went to the character")
	assert_eq(w.pet_system.pickups, 1)


func test_the_player_still_collects_with_the_magnet_and_the_event_says_so() -> void:
	var w := _far_pet_world()
	var slot := _rest_drop(w, 120.0)
	var events := PF.run(w, 40)
	var got := PF.of_type(events, "pickup_collected")
	assert_eq(got.size(), 1)
	assert_eq(got[0].pickup, slot)
	assert_eq(got[0].collector, "player")


func test_the_pet_collects_potions_into_the_shared_stock() -> void:
	var w := _far_pet_world()
	var before := int(w.potions.stock.hp.count)
	var slot := w.pickups.spawn_potion(Vector2(FAR.x + 20.0, 0.0), 2, 2000000, "hp")
	w.pickups.state[slot] = PickupSystem.REST
	var events := PF.run(w, 2)
	assert_eq(int(w.potions.stock.hp.count), before + 2)
	var got := PF.of_type(events, "pickup_collected")
	assert_eq(got[0].collector, "pet")
	assert_eq(got[0].kind, "potion")
	assert_eq(w.potions.collected.hp, 2)


func test_binocular_widens_the_radius() -> void:
	var plain := _far_pet_world([PF.KITTY])
	var scope := _far_pet_world([PF.KITTY, PF.BINOCULAR])
	_rest_drop(plain, FAR.x + 100.0)
	var through_scope := _rest_drop(scope, FAR.x + 100.0)
	assert_eq(PF.of_type(PF.run(plain, 2), "pickup_collected").size(), 0, "100 px is outside the base radius")
	var got := PF.of_type(PF.run(scope, 2), "pickup_collected")
	assert_eq(got.size(), 1, "and inside the doubled one")
	assert_eq(got[0].pickup, through_scope)
	assert_eq(scope.pet_system.pickup_radius(), 2.0 * plain.pet_system.pickup_radius())


func test_wing_boots_fetch_a_drop_within_the_leash_and_come_back() -> void:
	var w := PF.world([PF.KITTY, PF.WING])
	PF.put_player(w, 300.0, 0.0)
	PF.put_pet(w, Vector2(300.0, 0.0))
	var slot := _rest_drop(w, 300.0 + 200.0)  # beyond the player's magnet (90), inside the leash (220)
	var seen_fetching := false
	var collected: Array = []
	for i in 360:
		collected.append_array(PF.of_type(PF.run(w, 1), "pickup_collected"))
		seen_fetching = seen_fetching or bool(w.pet_state().fetching)
	assert_true(seen_fetching, "it ran for the drop")
	assert_eq(collected.size(), 1)
	assert_eq(collected[0].pickup, slot)
	assert_eq(collected[0].collector, "pet")
	assert_between(w.pet_state().pos.x, 300.0 - 60.0, 300.0 + 60.0, "and came back to the player")
	assert_false(w.pet_state().fetching)


func test_wing_boots_ignore_a_drop_outside_the_leash() -> void:
	var w := PF.world([PF.KITTY, PF.WING])
	PF.put_player(w, 300.0, 0.0)
	PF.put_pet(w, Vector2(300.0, 0.0))
	var slot := _rest_drop(w, 300.0 + 320.0)
	var events := PF.run(w, 360)
	assert_eq(PF.of_type(events, "pickup_collected").size(), 0)
	assert_eq(w.pickups.active[slot], 1)
	assert_between(w.pet_state().pos.x, 300.0 - 60.0, 300.0 + 60.0, "it stayed with the player")


func test_without_wing_boots_the_pet_stays_with_the_player() -> void:
	var w := PF.world([PF.KITTY])
	PF.put_player(w, 300.0, 0.0)
	PF.put_pet(w, Vector2(300.0, 0.0))
	var slot := _rest_drop(w, 300.0 + 200.0)
	PF.run(w, 360)
	assert_eq(w.pickups.active[slot], 1)


func test_vac_pulls_every_drop_on_the_map_to_the_pet() -> void:
	var w := PF.world([PF.KITTY, PF.WING, PF.BINOCULAR, PF.VAC])
	PF.put_player(w, 300.0, 0.0)
	PF.put_pet(w, Vector2(300.0, 0.0))
	for x in [20.0, 140.0, 600.0, 900.0, 1180.0]:
		_rest_drop(w, x, 1)
	var potion := w.pickups.spawn_potion(Vector2(1000.0, -60.0), 1, 2000000, "mp")
	w.pickups.state[potion] = PickupSystem.REST
	var events := PF.run(w, 360)
	var got := PF.of_type(events, "pickup_collected")
	assert_eq(got.size(), 6, "all six drops, wherever they lay")
	assert_eq(w.pickups.active_count(), 0)
	var by_pet := got.filter(func(e: Dictionary) -> bool: return e.collector == "pet")
	assert_true(by_pet.size() >= 4, "far ones flew to the pet: %d" % by_pet.size())


func test_without_vac_far_drops_stay_put() -> void:
	var w := PF.world([PF.KITTY, PF.BINOCULAR])
	PF.put_player(w, 300.0, 0.0)
	PF.put_pet(w, Vector2(300.0, 0.0))
	var slot := _rest_drop(w, 1180.0)
	PF.run(w, 240)
	assert_eq(w.pickups.active[slot], 1)
