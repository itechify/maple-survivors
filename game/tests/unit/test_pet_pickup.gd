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


func test_the_pet_collects_mesos_into_the_shared_wallet() -> void:
	var w := _far_pet_world()
	var before := w.mesos
	var slot := w.pickups.spawn_meso(Vector2(FAR.x + 20.0, 0.0), 123)
	w.pickups.state[slot] = PickupSystem.REST
	var events := PF.run(w, 2)
	assert_eq(w.mesos, before + 123)
	var got := PF.of_type(events, "pickup_collected")
	assert_eq(got[0].collector, "pet")
	assert_eq(got[0].kind, "meso")
	assert_eq(w.pickups.collected_mesos, 123)


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
	for x: float in [20.0, 140.0, 600.0, 900.0, 1180.0]:
		_rest_drop(w, x, 1)
	var meso := w.pickups.spawn_meso(Vector2(1000.0, -60.0), 123)
	w.pickups.state[meso] = PickupSystem.REST
	var events := PF.run(w, 360)
	var got := PF.of_type(events, "pickup_collected")
	assert_eq(got.size(), 6, "all six drops, wherever they lay")
	assert_eq(w.pickups.active_count(), 0)
	var by_pet := got.filter(func(e: Dictionary) -> bool: return e.collector == "pet")
	assert_true(by_pet.size() >= 4, "far ones flew to the pet: %d" % by_pet.size())


func test_dismissing_a_vac_pet_releases_the_drops_flying_to_it() -> void:
	var w := PF.world([PF.KITTY, PF.WING, PF.BINOCULAR, PF.VAC])
	PF.put_player(w, 300.0, 0.0)
	PF.put_pet(w, Vector2(300.0, 0.0))
	var slot := _rest_drop(w, 1180.0)
	PF.run(w, 30)
	assert_eq(w.pickups.to_pet[slot], 1, "flying to the pet")
	var flying_x := w.pickups.x[slot]
	assert_eq(w.set_pet(0), "")
	var events := PF.run(w, 240)
	assert_eq(w.pickups.active[slot], 1, "nobody collected it: no pet is out")
	assert_eq(PF.of_type(events, "pickup_collected").size(), 0)
	assert_eq(w.pickups.to_pet[slot], 0, "it is an ordinary drop again")
	assert_eq(w.pickups.state[slot], PickupSystem.REST, "lying where it was released, not steered toward the origin")
	assert_between(w.pickups.x[slot], flying_x, 1200.0, "x=%.1f" % w.pickups.x[slot])
	assert_eq(w.pickups.pet_collected, 0)


func test_a_drop_released_from_the_pet_is_collected_by_the_player_like_any_other() -> void:
	var w := PF.world([PF.KITTY, PF.WING, PF.BINOCULAR, PF.VAC])
	PF.put_player(w, 300.0, 0.0)
	PF.put_pet(w, Vector2(300.0, 0.0))
	var slot := _rest_drop(w, 1180.0, 5)
	PF.run(w, 30)
	assert_eq(w.set_pet(0), "")
	PF.run(w, 240)
	PF.put_player(w, w.pickups.x[slot] - 20.0, 0.0)
	var got := PF.of_type(PF.run(w, 60), "pickup_collected")
	assert_eq(got.size(), 1)
	assert_eq(got[0].collector, "player")
	assert_eq(int(w.player_state.exp), 5)


func test_the_pickup_system_stops_steering_to_a_pet_that_is_no_longer_vacuuming() -> void:
	var drops := PickupSystem.new(4, {"spread": 0.0})
	var slot := drops.spawn(Vector2(500.0, 0.0), 1, 1)
	drops.state[slot] = PickupSystem.REST
	var events: Array = []
	drops.step(1.0 / 60.0, Vector2(0.0, 0.0), 90.0, null, events, -1, Vector2(0.0, -15.0), 60.0, true)
	assert_eq(drops.to_pet[slot], 1)
	drops.step(1.0 / 60.0, Vector2(0.0, 0.0), 90.0, null, events, -1, Vector2.ZERO, 0.0, false)
	assert_eq(drops.to_pet[slot], 0, "no VAC: back to an ordinary drop")
	assert_true(drops.state[slot] != PickupSystem.MAGNET)
	assert_true(drops.x[slot] > 400.0, "still far out, not pulled toward the origin: %.1f" % drops.x[slot])
	assert_eq(events.size(), 0)


func test_without_vac_far_drops_stay_put() -> void:
	var w := PF.world([PF.KITTY, PF.BINOCULAR])
	PF.put_player(w, 300.0, 0.0)
	PF.put_pet(w, Vector2(300.0, 0.0))
	var slot := _rest_drop(w, 1180.0)
	PF.run(w, 240)
	assert_eq(w.pickups.active[slot], 1)


## A resting meso bundle of `amount` at (x, 0) (spec #33 #107 drops), without stepping the world.
func _rest_meso(w: RunWorld, x: float, amount: int) -> int:
	var slot := w.pickups.spawn_meso(Vector2(x, 0.0), amount)
	w.pickups.state[slot] = PickupSystem.REST
	w.pickups.vx[slot] = 0.0
	w.pickups.vy[slot] = 0.0
	return slot


func test_the_pet_collects_mesos_credited_exactly_like_the_players_pickup() -> void:
	var by_pet := _far_pet_world()
	var by_player := _far_pet_world()
	var start := by_pet.mesos
	assert_eq(by_player.mesos, start)
	var pet_slot := _rest_meso(by_pet, FAR.x + 30.0, 57)
	var player_slot := _rest_meso(by_player, 120.0, 57)
	var pet_got := PF.of_type(PF.run(by_pet, 40), "pickup_collected")
	var player_got := PF.of_type(PF.run(by_player, 40), "pickup_collected")
	assert_eq(pet_got.size(), 1)
	assert_eq(player_got.size(), 1)
	assert_eq(pet_got[0].pickup, pet_slot)
	assert_eq(player_got[0].pickup, player_slot)
	assert_eq(pet_got[0].collector, "pet")
	assert_eq(player_got[0].collector, "player")
	for e: Dictionary in [pet_got[0], player_got[0]]:
		assert_eq(e.kind, "meso")
		assert_eq(e.count, 57, "a meso event carries its amount")
		assert_eq(e.exp, 0)
	assert_eq(by_pet.mesos, start + 57, "the pet's mesos are the character's")
	assert_eq(by_pet.mesos, by_player.mesos, "credited the same as the player's own pickup")
	assert_eq(by_pet.pickups.collected_mesos, by_player.pickups.collected_mesos)
	assert_eq(by_pet.pet_system.pickups, 1)
	assert_eq(int(by_pet.character_snapshot().mesos), start + 57, "and carried into the snapshot")


func test_vac_pulls_far_mesos_to_the_pet() -> void:
	var w := PF.world([PF.KITTY, PF.WING, PF.BINOCULAR, PF.VAC])
	PF.put_player(w, 300.0, 0.0)
	PF.put_pet(w, Vector2(300.0, 0.0))
	var start := w.mesos
	for x: float in [20.0, 900.0, 1180.0]:
		_rest_meso(w, x, 11)
	var got := PF.of_type(PF.run(w, 360), "pickup_collected")
	assert_eq(got.size(), 3)
	assert_eq(w.mesos, start + 33)
	assert_true(got.any(func(e: Dictionary) -> bool: return e.collector == "pet"), "far mesos flew to the pet")


## Fills the character's Equip tab (spec #33: a full tab leaves equipment drops on the ground).
func _fill_equip_tab(w: RunWorld) -> void:
	while w.equipment.inventory.size() < w.inventory_slots():
		w.equipment.inventory.append({"id": 1002001, "stats": {}, "slots": 7, "scrolls": 0})


## A resting equipment drop at (x, 0), without stepping the world.
func _rest_equip(w: RunWorld, x: float) -> int:
	var slot := w.spawn_equipment(Vector2(x, 0.0), {"id": 1372005, "stats": {}, "slots": 7, "scrolls": 0})
	w.pickups.state[slot] = PickupSystem.REST
	w.pickups.vx[slot] = 0.0
	w.pickups.vy[slot] = 0.0
	return slot


func test_the_pet_takes_equipment_only_while_the_equip_tab_has_room() -> void:
	var w := _far_pet_world()
	_fill_equip_tab(w)
	var slot := _rest_equip(w, FAR.x + 10.0)
	PF.run(w, 10)
	assert_eq(w.pickups.active[slot], 1, "a full Equip tab: the pet leaves it on the ground too")
	w.equipment.inventory.pop_back()
	var got := PF.of_type(PF.run(w, 3), "pickup_collected")
	assert_eq(got.size(), 1)
	assert_eq(got[0].kind, "equip")
	assert_eq(got[0].collector, "pet")
	assert_eq(int(w.equipment.inventory.back().id), 1372005, "the pet's pickup lands in the Equip tab")


func test_vac_does_not_pull_equipment_the_equip_tab_has_no_room_for() -> void:
	var drops := PickupSystem.new(4, {"spread": 0.0})
	var slot := drops.spawn_equipment(Vector2(500.0, 0.0), {"id": 1372005, "stats": {}, "slots": 7, "scrolls": 0})
	drops.state[slot] = PickupSystem.REST
	var events: Array = []
	drops.step(1.0 / 60.0, Vector2(0.0, 0.0), 90.0, null, events, 0, Vector2(0.0, -15.0), 60.0, true)
	assert_eq(drops.to_pet[slot], 0, "no room: not pulled")
	assert_eq(drops.x[slot], 500.0)
	drops.step(1.0 / 60.0, Vector2(0.0, 0.0), 90.0, null, events, 1, Vector2(0.0, -15.0), 60.0, true)
	assert_eq(drops.to_pet[slot], 1, "room again: VAC pulls it")
	drops.step(1.0 / 60.0, Vector2(0.0, 0.0), 90.0, null, events, 0, Vector2(0.0, -15.0), 60.0, true)
	assert_eq(drops.to_pet[slot], 0, "the tab filled while it flew: it drops like an ordinary drop")
	assert_true(drops.state[slot] != PickupSystem.MAGNET)


func test_wing_boots_do_not_fetch_equipment_the_equip_tab_has_no_room_for() -> void:
	var w := PF.world([PF.KITTY, PF.WING])
	PF.put_player(w, 300.0, 0.0)
	PF.put_pet(w, Vector2(300.0, 0.0))
	_fill_equip_tab(w)
	var slot := _rest_equip(w, 480.0)
	var seen_fetching := false
	for tick in 120:
		PF.run(w, 1)
		seen_fetching = seen_fetching or bool(w.pet_state().fetching)
	assert_false(seen_fetching, "nothing it could pick up")
	assert_eq(w.pickups.active[slot], 1)
