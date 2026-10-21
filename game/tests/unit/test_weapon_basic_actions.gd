extends TestCase
## The automatic basic attack follows the held weapon's family (#154): its action set comes from WeaponInfo (data),
## each action tells the damage model swing, stab or shoot, ranged families fire from a distance, and the melee
## families' afterimage, spark and sound come from the weapon's own info. Synthetic canonical-shaped weapon trees.

const BF := preload("res://tests/fixtures/basic_attack_fixtures.gd")
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const BOX_LT := [-90.0, -50.0]
const BOX_RB := [-20.0, -10.0]


## A BF world wearing weapon `id` whose item info is `info`, with a body stance and an afterimage (melee box, or just a
## frame when `box` is false) for each action in `actions`.
func _world(id: int, info: Dictionary, actions: Array, box := true, seed_value := 7) -> RunWorld:
	var world := BF.world(seed_value)
	world.setup.equipment_info[id] = info
	var images: Dictionary = {"0": {}}
	for action: String in actions:
		world.setup.body_img[action] = {"0": {"delay": 300.0}, "1": {"delay": 150.0}, "2": {"delay": 350.0}}
		var node := {"2": {"0": {"$canvas": [0, 0, 0, 40, 30], "delay": 200.0}}}
		if box:
			node["lt"] = {"$v": BOX_LT.duplicate()}
			node["rb"] = {"$v": BOX_RB.duplicate()}
		images["0"][action] = node
	world.setup.afterimage_imgs[String(info.afterImage)] = images
	world.equipment.inventory.append(Equipment.create(id, info))
	assert_eq(world.equip_item(world.equipment.inventory.size() - 1), "", "wears %d" % id)
	return world


func _target(world: RunWorld, x: float) -> int:
	world.mob_kinds[int(world.kind_of_id[100100])].move_speed = 0
	var mob := RF.put_mob(world, 100100, x, 190, 100)
	world.swarm.hp[mob] = 1000000
	world.swarm.max_hp[mob] = 1000000
	return mob


## Runs `ticks` fixed ticks; returns {"starts": [event], "hits": [event], "kinds": {action: kind}}.
func _fight(world: RunWorld, ticks: int) -> Dictionary:
	var out := {"starts": [], "hits": [], "kinds": {}}
	for tick in ticks:
		world.step(DT, MoveInput.new())
		for event: Dictionary in world.drain_events():
			if event.type == "basic_attack" and event.phase == "start":
				out.starts.append(event)
				out.kinds[String(event.action)] = world.basic.last_kind
			elif event.type == "mob_hit":
				out.hits.append(event)
	return out


func _distinct(starts: Array) -> PackedStringArray:
	var seen := PackedStringArray()
	for event: Dictionary in starts:
		if not (String(event.action) in seen):
			seen.append(String(event.action))
	seen.sort()
	return seen


func test_a_two_handed_sword_swings_its_own_stances_with_swing_and_stab_kinds() -> void:
	var info := {"incPAD": 40.0, "attackSpeed": 4.0, "afterImage": "swordTS", "sfx": "swordS", "stand": 2.0, "walk": 1.0,
		"attack": 5.0}
	var actions := ["swingT1", "swingT2", "swingT3", "stabO1", "stabO2"]
	var world := _world(1402001, info, actions)
	_target(world, 450)
	var fight := _fight(world, 60 * 40)
	assert_true(fight.starts.size() >= 20, "swings repeatedly")
	assert_eq(_distinct(fight.starts), PackedStringArray(["stabO1", "stabO2", "swingT1", "swingT2", "swingT3"]))
	for action: String in fight.kinds:
		assert_eq(fight.kinds[action], "stab" if action.begins_with("stab") else "swing", action)
	assert_true(fight.hits.size() >= 10, "and hits")
	assert_true(String(fight.starts[0].afterimage).begins_with("Character.wz/Afterimage/swordTS.img/0/"),
		String(fight.starts[0].afterimage))
	assert_eq(String(fight.starts[0].sound), "Sound.wz/Weapon.img/swordS/Attack")


func test_a_spear_stabs_and_a_pole_arm_swings() -> void:
	var spear := _world(1432000, {"incPAD": 32.0, "attackSpeed": 8.0, "afterImage": "spear", "sfx": "spear", "stand": 2.0,
		"walk": 2.0, "attack": 2.0}, ["stabT1", "stabT2", "swingP1"])
	_target(spear, 450)
	var fight := _fight(spear, 60 * 40)
	assert_eq(_distinct(fight.starts), PackedStringArray(["stabT1", "stabT2", "swingP1"]))
	assert_eq(fight.kinds.stabT1, "stab")
	assert_eq(fight.kinds.stabT2, "stab")
	assert_eq(fight.kinds.swingP1, "swing")
	assert_eq(String(fight.starts[0].sound), "Sound.wz/Weapon.img/spear/Attack")
	var pole := _world(1442000, {"incPAD": 32.0, "attackSpeed": 8.0, "afterImage": "poleArm", "sfx": "poleArm", "stand": 2.0,
		"walk": 2.0, "attack": 2.0}, ["swingP1", "swingP2", "swingT2"])
	_target(pole, 450)
	fight = _fight(pole, 60 * 40)
	assert_eq(_distinct(fight.starts), PackedStringArray(["swingP1", "swingP2", "swingT2"]))
	for kind: String in fight.kinds.values():
		assert_eq(kind, "swing")


func test_the_basic_attack_stream_picks_the_same_stances_as_before_for_one_handed_weapons() -> void:
	# The Beginner and Magician weapons keep the exact five-stance index order of BasicAttack.ACTIONS.
	var world := BF.world(11)
	_target(world, 450)
	var first: Array = _fight(world, 60 * 20).starts
	assert_true(first.size() >= 5)
	assert_eq(WeaponInfo.basic_actions(1302000), PackedStringArray(BasicAttack.ACTIONS))
	var twin := BF.world(11)
	assert_eq(String(first[0].action), BasicAttack.ACTIONS[twin.basic_rng.randi_range(0, 4)], "stream 5, legacy index order")


func test_a_bow_shoots_from_range_with_shoot_kind_and_no_melee_box() -> void:
	var info := {"incPAD": 40.0, "attackSpeed": 5.0, "afterImage": "bow", "sfx": "bow", "stand": 1.0, "walk": 1.0, "attack": 3.0}
	var world := _world(1452000, info, ["shoot1"], false)
	assert_eq(world.basic.reach(world), WeaponInfo.RANGED_REACH.bow, "the bot kites by the ranged reach")
	_target(world, 400 + 280)
	var fight := _fight(world, 60 * 20)
	assert_true(fight.starts.size() >= 5, "a target 280 px away is in a bow's reach")
	assert_eq(_distinct(fight.starts), PackedStringArray(["shoot1"]))
	assert_eq(fight.kinds.shoot1, "shoot")
	assert_true(fight.hits.size() >= 3, "the arrow lands (the projectile itself is #155)")
	assert_eq(String(fight.starts[0].afterimage), "Character.wz/Afterimage/bow.img/0/shoot1/2", "the bow's draw frame")
	assert_eq(String(fight.starts[0].sound), "Sound.wz/Weapon.img/bow/Attack")
	var far := _world(1452000, info, ["shoot1"], false)
	_target(far, 400 + 340)
	assert_eq(_fight(far, 120).starts.size(), 0, "beyond the reach nothing is shot")


func test_a_claw_throws_with_swing_stances_that_count_as_shoot() -> void:
	var info := {"incPAD": 10.0, "attackSpeed": 6.0, "afterImage": "swordOL", "sfx": "tGlove", "stand": 1.0, "walk": 1.0,
		"attack": 7.0}
	var world := _world(1472000, info, ["swingO1", "swingO2", "swingO3"])
	_target(world, 400 + 240)
	var fight := _fight(world, 60 * 30)
	assert_eq(_distinct(fight.starts), PackedStringArray(["swingO1", "swingO2", "swingO3"]))
	for action: String in fight.kinds:
		assert_eq(fight.kinds[action], "shoot", action)
	assert_true(fight.hits.size() >= 3, "240 px away is inside a claw's throw, outside the sword trail's box")
	assert_eq(String(fight.starts[0].afterimage), "", "a thrown star leaves no sword trail")


func test_a_gun_and_a_knuckle() -> void:
	var gun := _world(1492000, {"incPAD": 13.0, "attackSpeed": 5.0, "afterImage": "gun", "sfx": "gun", "stand": 1.0, "walk": 1.0,
		"attack": 9.0}, ["shoot1"], false)
	gun.setup.afterimage_imgs.gun["0"].erase("shoot1")
	_target(gun, 400 + 200)
	var fight := _fight(gun, 60 * 15)
	assert_eq(_distinct(fight.starts), PackedStringArray(["shoot1"]))
	assert_eq(fight.kinds.shoot1, "shoot")
	assert_true(fight.hits.size() >= 2)
	assert_eq(String(fight.starts[0].afterimage), "", "the Gun's afterimage has no shoot1 frame")
	assert_eq(String(fight.starts[0].sound), "Sound.wz/Weapon.img/gun/Attack")
	var knuckle := _world(1482000, {"incPAD": 18.0, "attackSpeed": 5.0, "afterImage": "knuckle", "sfx": "knuckle", "stand": 1.0,
		"walk": 1.0, "attack": 8.0}, ["stabO1", "stabO2"])
	_target(knuckle, 450)
	fight = _fight(knuckle, 60 * 20)
	assert_eq(_distinct(fight.starts), PackedStringArray(["stabO1", "stabO2"]))
	assert_eq(fight.kinds.stabO1, "stab")


func test_stab_and_swing_weapons_roll_their_own_multiplier() -> void:
	# A Spear (5.0 stab / 3.0 swing): the kind a stance reports picks the multiplier; maximum hits show it.
	var world := _world(1432000, {"incPAD": 32.0, "attackSpeed": 8.0, "afterImage": "spear", "sfx": "spear", "stand": 2.0,
		"walk": 2.0, "attack": 2.0}, ["stabT1", "stabT2", "swingP1"])
	world.loadout.crit_per_acc = 0.0
	_target(world, 450)
	var by_action := {}
	for tick in 60 * 60:
		world.step(DT, MoveInput.new())
		for event: Dictionary in world.drain_events():
			if event.type == "mob_hit":
				by_action[world.basic.last_action] = maxi(int(event.damage), int(by_action.get(world.basic.last_action, 0)))
	assert_true(by_action.has("stabT1") and by_action.has("swingP1"), str(by_action))
	assert_true(int(by_action.stabT1) > int(by_action.swingP1), "5.0 stab beats 3.0 swing: %s" % [by_action])
