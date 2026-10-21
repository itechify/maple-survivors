extends TestCase
## The pet's Auto HP / Auto MP Potion Pouch (spec #34, ticket #119): it drinks the character's potion from the shared
## cooldown below the ALERT level, never above it, never faster than the shared cooldown, and never when
## the ALERT says "do not alert"; its drinks are counted apart from the player's.

const PF := preload("res://tests/fixtures/pet_fixtures.gd")


## A world with both pouches. HP/MP are set directly (the sim keeps them private): `hp_fraction` of max HP.
func _world(alert: Dictionary, hp_fraction := 0.3, owned: Array = [PF.KITTY, PF.AUTO_HP, PF.AUTO_MP]) -> RunWorld:
	var w := PF.world(owned, alert)
	w._hp = w._max_hp * hp_fraction
	w._mp = w._max_mp * 0.2
	return w


func test_drinks_below_the_alert_level() -> void:
	var w := _world({"hp": 0.5, "mp": 0.0})
	var hp_before := float(w._hp)
	var events := PF.run(w, 2)
	var drinks := PF.of_type(events, "pet_potion_used")
	assert_eq(drinks.size(), 1)
	assert_eq(drinks[0].kind, "hp")
	assert_eq(drinks[0].item_id, 2000000)
	assert_true(w._hp > hp_before, "restored HP")
	assert_false(w.potions.is_ready("hp"))
	assert_eq(PF.of_type(events, "potion_used").size(), 0, "not reported as the player's drink")


func test_never_at_or_above_the_alert_level() -> void:
	var w := _world({"hp": 0.5, "mp": 0.0}, 0.5)
	assert_eq(PF.of_type(PF.run(w, 120), "pet_potion_used").size(), 0, "exactly at the level is not below it")
	var higher := _world({"hp": 0.5, "mp": 0.0}, 0.9)
	assert_eq(PF.of_type(PF.run(higher, 120), "pet_potion_used").size(), 0)


func test_never_when_the_alert_is_off() -> void:
	var w := _world({"hp": 0.0, "mp": 0.0}, 0.05)
	assert_eq(PF.of_type(PF.run(w, 120), "pet_potion_used").size(), 0)
	var absent := PF.world([PF.KITTY, PF.AUTO_HP, PF.AUTO_MP])
	absent._hp = 1.0
	assert_eq(PF.of_type(PF.run(absent, 120), "pet_potion_used").size(), 0, "no ALERT given: do not alert")


func test_never_without_the_pouch_or_while_player_cooldown_runs() -> void:
	var no_pouch := _world({"hp": 0.5, "mp": 0.5}, 0.1, [PF.KITTY])
	assert_eq(PF.of_type(PF.run(no_pouch, 120), "pet_potion_used").size(), 0, "the pet has no pouch")
	var empty := _world({"hp": 0.9, "mp": 0.0}, 0.1)
	assert_true(empty.drink_potion("hp"))
	empty._hp = 1.0
	var events := PF.run(empty, 120)
	assert_eq(PF.of_type(events, "pet_potion_used").size(), 0, "manual drink holds the pet until the shared cooldown ends")
	assert_eq(empty.potions.used.hp, 1)


func test_never_faster_than_the_shared_cooldown() -> void:
	var w := _world({"hp": 0.99, "mp": 0.0}, 0.01)
	w.god = true
	var times: Array = []
	for tick in 2460:
		for e: Dictionary in PF.of_type(PF.run(w, 1), "pet_potion_used"):
			times.append(w.time)
		w._hp = 1.0  # stays low so every tick is a chance to drink
	assert_eq(times.size(), 3, "drinks immediately, at 20 s and at 40 s over 41 sim seconds")
	for i in range(1, times.size()):
		assert_true(times[i] - times[i - 1] >= 20.0 - 1e-6, "gap %.3f" % (times[i] - times[i - 1]))


func test_mp_alert_drinks_mp() -> void:
	var w := _world({"hp": 0.0, "mp": 0.5})
	var events := PF.run(w, 2)
	var drinks := PF.of_type(events, "pet_potion_used")
	assert_eq(drinks.size(), 1)
	assert_eq(drinks[0].kind, "mp")
	assert_false(w.potions.is_ready("mp"))


func test_the_pet_decides_from_the_current_and_maximum_value() -> void:
	var w := PF.world([PF.KITTY, PF.AUTO_HP])
	var pet := w.pet_system
	assert_true(pet.should_drink("hp", 40.0, 100, 0.5, true), "40/100 is below the 50 % level")
	assert_false(pet.should_drink("hp", 50.0, 100, 0.5, true), "exactly at the level is not below it")
	assert_false(pet.should_drink("hp", 40.0, 100, 0.0, true), "ALERT off")
	assert_false(pet.should_drink("hp", 0.0, 0, 0.5, true), "no maximum, nothing to compare")
	assert_false(pet.should_drink("mp", 10.0, 100, 0.5, true), "no Auto MP pouch")
	pet.drank("hp")
	assert_false(pet.should_drink("hp", 40.0, 100, 0.5, false), "the caller supplies the shared cooldown gate")


func test_pet_and_player_drinks_are_counted_separately() -> void:
	var w := _world({"hp": 0.5, "mp": 0.0}, 0.3)
	PF.run(w, 2)
	assert_false(w.drink_potion("hp"), "the pet blocks the player on the shared cooldown")
	w.alert.hp = 0.0
	PF.run(w, 1201)
	assert_true(w.drink_potion("hp"), "the player can drink after expiry")
	assert_eq(w.potions.used.hp, 1, "the player's total leaves the pet's out")
	assert_eq(w.potions.pet_used.hp, 1)
	assert_eq(w.pet_system.drinks.hp, 1)
	assert_false(w.potions.is_ready("hp"), "the player starts the same shared cooldown")
