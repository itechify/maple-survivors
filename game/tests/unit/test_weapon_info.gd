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
