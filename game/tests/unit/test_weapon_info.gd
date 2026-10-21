extends TestCase
## WeaponInfo's weapon families and the two-handed rule (docs/adr/0005), from original item ids and Skill.wz codes.


func test_family_of_every_v83_weapon_type() -> void:
	var expected := {
		1302000: "sword", 1312004: "axe", 1322005: "blunt", 1332063: "dagger", 1372005: "wand", 1382000: "staff",
		1402001: "sword", 1412001: "axe", 1422001: "blunt", 1432000: "spear", 1442000: "polearm",
		1452051: "bow", 1462000: "crossbow", 1472061: "claw", 1482000: "knuckle", 1492000: "gun",
	}
	for id: int in expected:
		assert_eq(WeaponInfo.family(id), expected[id], str(id))


func test_bare_hands_and_non_weapons_have_no_family() -> void:
	assert_eq(WeaponInfo.family(0), "")
	assert_eq(WeaponInfo.family(1092030), "", "a shield is not a weapon")
	assert_eq(WeaponInfo.family(1002000), "", "a hat is not a weapon")


func test_skill_weapon_codes_map_to_families() -> void:
	assert_eq(WeaponInfo.family_of_skill_code(30), "sword")
	assert_eq(WeaponInfo.family_of_skill_code(40), "sword")
	assert_eq(WeaponInfo.family_of_skill_code(47), "claw")
	assert_eq(WeaponInfo.family_of_skill_code(49), "gun")
	assert_eq(WeaponInfo.family_of_skill_code(0), "")


func test_two_handed_from_type_140() -> void:
	for id: int in [1302000, 1312004, 1322005, 1332063, 1372005, 1382000]:
		assert_false(WeaponInfo.is_two_handed(id), str(id))
	for id: int in [1402001, 1412001, 1422001, 1432000, 1442000, 1452051, 1462000, 1472061, 1482000, 1492000]:
		assert_true(WeaponInfo.is_two_handed(id), str(id))
	assert_false(WeaponInfo.is_two_handed(0))
	assert_false(WeaponInfo.is_two_handed(1092030))


func test_stand_and_walk_stances_come_from_the_weapon_info() -> void:
	assert_eq(WeaponInfo.stand_stance({}), "stand1", "bare hands and synthetic infos")
	assert_eq(WeaponInfo.walk_stance({}), "walk1")
	assert_eq(WeaponInfo.stand_stance({"stand": 1, "walk": 1}), "stand1")
	# Two-handed Bow/Spear style: both stances are the second variant.
	assert_eq(WeaponInfo.stand_stance({"stand": 2, "walk": 2}), "stand2")
	assert_eq(WeaponInfo.walk_stance({"stand": 2, "walk": 2}), "walk2")
	# Real 2H swords (1402000, 1402001) stand with stand2 but walk with walk1: the two numbers are independent.
	assert_eq(WeaponInfo.stand_stance({"stand": 2.0, "walk": 1.0}), "stand2", "JSON numbers are floats")
	assert_eq(WeaponInfo.walk_stance({"stand": 2.0, "walk": 1.0}), "walk1")


func test_basic_actions_of_each_family_are_data() -> void:
	var legacy := PackedStringArray(["swingO1", "swingO2", "swingO3", "stabO1", "stabO2"])
	var two_handed := PackedStringArray(["swingT1", "swingT2", "swingT3", "stabO1", "stabO2"])
	var expected := {
		1302000: legacy, 1312004: legacy, 1322005: legacy, 1332000: legacy, 1372005: legacy, 1382000: legacy,
		1402001: two_handed, 1412000: two_handed, 1422000: two_handed,
		1432000: PackedStringArray(["stabT1", "stabT2", "swingP1"]),
		1442000: PackedStringArray(["swingP1", "swingP2", "swingT2"]),
		1452000: PackedStringArray(["shoot1"]), 1462000: PackedStringArray(["shoot2"]),
		1472000: PackedStringArray(["swingO1", "swingO2", "swingO3"]),
		1482000: PackedStringArray(["stabO1", "stabO2"]), 1492000: PackedStringArray(["shoot1"]),
		0: legacy, 9999999: legacy,
	}
	for id: int in expected:
		assert_eq(WeaponInfo.basic_actions(id), expected[id], str(id))


func test_every_basic_action_tells_the_damage_model_swing_stab_or_shoot() -> void:
	for id: int in [0, 1302000, 1332000, 1372005, 1382000, 1402001, 1412000, 1422000, 1432000, 1442000, 1452000, 1462000,
			1472000, 1482000, 1492000]:
		for action in WeaponInfo.basic_actions(id):
			assert_true(WeaponInfo.basic_kind(id, action) in ["swing", "stab", "shoot"], "%d %s" % [id, action])
	assert_eq(WeaponInfo.basic_kind(1302000, "swingO2"), "swing")
	assert_eq(WeaponInfo.basic_kind(1302000, "stabO1"), "stab")
	assert_eq(WeaponInfo.basic_kind(1432000, "stabT1"), "stab")
	assert_eq(WeaponInfo.basic_kind(1442000, "swingP1"), "swing")
	assert_eq(WeaponInfo.basic_kind(1452000, "shoot1"), "shoot")
	assert_eq(WeaponInfo.basic_kind(1492000, "shoot1"), "shoot")
	# Claws throw with swing stances; the family, not the stance name, makes it a ranged attack.
	assert_eq(WeaponInfo.basic_kind(1472000, "swingO1"), "shoot")
	assert_eq(WeaponInfo.attack_kind("shot"), "shoot", "the Gun's own body stance")
	for id: int in [1452000, 1462000, 1472000, 1492000]:
		assert_true(WeaponInfo.is_ranged(id), str(id))
	for id: int in [0, 1302000, 1382000, 1402001, 1432000, 1442000, 1482000]:
		assert_false(WeaponInfo.is_ranged(id), str(id))


func test_hit_spark_family_follows_the_afterimage_name() -> void:
	assert_eq(WeaponInfo.hit_spark_path("swordTS", "swingT1"), "Character.wz/Afterimage/hit.img/sword1")
	assert_eq(WeaponInfo.hit_spark_path("swordOS", "stabO1"), "Character.wz/Afterimage/hit.img/sword2")
	assert_eq(WeaponInfo.hit_spark_path("axe", "swingT2"), "Character.wz/Afterimage/hit.img/mace1")
	assert_eq(WeaponInfo.hit_spark_path("spear", "stabT1"), "Character.wz/Afterimage/hit.img/mace2")
	assert_eq(WeaponInfo.hit_spark_path("knuckle", "stabO1"), "Character.wz/Afterimage/hit.img/mace2")
