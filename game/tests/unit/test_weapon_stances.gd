extends TestCase
## The standing and walking body stance follows the held weapon (#154): PlayerMotion plays WeaponInfo.stand_stance /
## walk_stance of the worn weapon, which RunWorld refreshes whenever the weapon changes.

const BF := preload("res://tests/fixtures/basic_attack_fixtures.gd")
const WF := preload("res://tests/fixtures/world_fixtures.gd")
const DT := 1.0 / 60.0


func _flat() -> FootholdMap:
	return FootholdMap.from_segments([{"x1": -4000.0, "y1": 0.0, "x2": 4000.0, "y2": 0.0}])


func test_player_motion_plays_the_stances_it_is_given() -> void:
	var m := _flat()
	var p := PlayerMotion.new(PhysicsConstants.v83_defaults())
	p.place(Vector2.ZERO, m)
	assert_eq(p.stance(), "stand1", "default")
	p.stand_stance = "stand2"
	p.walk_stance = "walk2"
	assert_eq(p.stance(), "stand2", "a two-handed weapon stands with stand2")
	for t in 20:
		p.step(DT, MoveInput.make(false, true), m, null, Rect2())
	assert_eq(p.stance(), "walk2", "and walks with walk2")
	p.alert_t = 1.0
	p.state = PlayerMotion.ST_STAND
	assert_eq(p.stance(), "alert", "alert, jump, prone and ladders are shared by every weapon")
	p.state = PlayerMotion.ST_AIR
	assert_eq(p.stance(), "jump")


func test_a_two_handed_weapon_picks_stand2_and_walk2_and_the_sword_goes_back() -> void:
	var world := BF.world()
	world.setup.equipment_info[1412000] = {"incPAD": 47.0, "attackSpeed": 6.0, "afterImage": "axe", "sfx": "swordS",
		"stand": 2.0, "walk": 2.0, "attack": 5.0}
	world.setup.equipment_info[1402001] = {"incPAD": 40.0, "attackSpeed": 6.0, "afterImage": "swordTS", "sfx": "swordS",
		"stand": 2.0, "walk": 1.0, "attack": 5.0}
	world.step(DT, MoveInput.new())
	assert_eq(world.player.stance(), "stand1", "the Beginner's sword stands with stand1")
	assert_eq(world.player.walk_stance, "walk1")
	for id: int in [1412000, 1402001]:
		world.equipment.inventory.append(Equipment.create(id, world.setup.equipment_info[id]))
		assert_eq(world.equip_item(world.equipment.inventory.size() - 1), "", str(id))
		assert_eq(world.player.stand_stance, "stand2", "%d stands with stand2" % id)
		assert_eq(world.player.walk_stance, "walk2" if id == 1412000 else "walk1", "%d walks" % id)
		world.step(DT, MoveInput.new())
		assert_eq(String(world.player_state.action), "stand2", "the action the avatar plays follows")
	assert_eq(world.unequip_item("weapon"), "")
	assert_eq(world.player.stand_stance, "stand1", "bare hands stand with stand1")
	assert_eq(world.player.walk_stance, "walk1")
