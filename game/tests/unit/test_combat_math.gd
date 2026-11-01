extends TestCase
## CombatMath (docs/GAME_DESIGN.md section 6) with hand-computed values, and the shared hit roll.


func test_mastery_fraction() -> void:
	assert_near(CombatMath.mastery_fraction(1), 0.15, 1e-9, "Energy Bolt L1: mastery 1 = 15%")
	assert_near(CombatMath.mastery_fraction(10), 0.60, 1e-9, "L20: mastery 10 = 60%")
	assert_near(CombatMath.mastery_fraction(0), 0.10, 1e-9)


func test_magic_damage_range_known_inputs() -> void:
	# INT 39, Wooden Wand 23 -> MAG 62; Energy Bolt L1: mad 20, mastery 15%.
	# MAX = ((62^2/1000 + 62)/30 + 39/200) x 20 = 47.796; MIN = ((3.844 + 62 x 0.15 x 0.9)/30 + 0.195) x 20 = 12.0427
	var r := CombatMath.magic_damage_range(39.0, 23.0, 20.0, 0.15)
	assert_near(r.y, 47.796, 1e-3, "max")
	assert_near(r.x, 12.0427, 1e-3, "min")
	# INT 100, no weapon, Energy Bolt L20: mad 55, mastery 60%: MAX = (110/30 + 0.5) x 55, MIN = (64/30 + 0.5) x 55.
	var r2 := CombatMath.magic_damage_range(100.0, 0.0, 55.0, 0.6)
	assert_near(r2.y, (110.0 / 30.0 + 0.5) * 55.0, 1e-3)
	assert_near(r2.x, (64.0 / 30.0 + 0.5) * 55.0, 1e-3)
	var full := CombatMath.magic_damage_range(50.0, 10.0, 30.0, 1.0 / 0.9)
	assert_near(full.x, full.y, 1e-3, "mastery x 0.9 = 1 gives a flat roll")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 200:
		assert_between(CombatMath.roll_range(r, rng), r.x, r.y, "rolls stay in range")


func test_fixed_damage() -> void:
	assert_eq(CombatMath.fixed_damage(10.0), 10, "Three Snails L1")
	assert_eq(CombatMath.fixed_damage(25.0), 25, "L2")
	assert_eq(CombatMath.fixed_damage(40.0, 1.2), 48, "with a survivor multiplier")
	assert_eq(CombatMath.fixed_damage(0.0), 1, "at least 1")


func test_mob_magic_defense() -> void:
	assert_near(CombatMath.apply_defense(100.0, 0.0), 100.0, 1e-9, "MDD 0")
	assert_near(CombatMath.apply_defense(100.0, 10.0), 93.75, 1e-6, "Slime MDD 10: x (1 - 10/160)")
	assert_near(CombatMath.apply_defense(100.0, 150.0), 50.0, 1e-6, "MDD = k halves")
	assert_near(CombatMath.apply_defense(80.0, 40.0, 40.0), 40.0, 1e-6, "custom k")


func test_monster_damage_rounding_and_mitigation() -> void:
	assert_eq(CombatMath.monster_damage(42.0, 0.0, 7.0), 31, "round(35.7 - floor(5.25))")
	assert_eq(CombatMath.monster_damage(42.0, 1.0, 7.0), 37)
	assert_eq(CombatMath.monster_damage(82.0, 0.0, 7.0), 65)
	assert_eq(CombatMath.monster_damage(82.0, 1.0, 7.0), 77)
	assert_eq(CombatMath.monster_damage(82.0, 0.0, 47.0), 35)
	assert_eq(CombatMath.monster_damage(82.0, 1.0, 47.0), 47)
	assert_eq(CombatMath.monster_damage(12.0, 1.0, 40.0), 1, "never below 1")
	assert_eq(CombatMath.monster_damage(100.0, 1.0, 20.0, 100.0), 1, "complete resistance still costs 1")


func test_crit_roll() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var before := rng.state
	assert_false(CombatMath.roll_crit(0.0, rng), "no crit chance")
	assert_eq(rng.state, before, "a zero chance consumes no roll")
	assert_true(CombatMath.roll_crit(1.0, rng))
	var n := 0
	for i in 1000:
		if CombatMath.roll_crit(0.25, rng):
			n += 1
	assert_between(n, 200, 300, "about 25%")


func test_shared_hit_roll() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var fixed := ProjectileSystem.roll_damage(25.0, 25.0, false, 40.0, 150.0, 0.0, 1.5, rng)
	assert_eq(fixed, Vector2i(25, 0), "fixed damage ignores MDD")
	for i in 100:
		var m := ProjectileSystem.roll_damage(12.0, 48.0, true, 10.0, 150.0, 0.0, 1.5, rng)
		assert_between(m.x, roundi(12.0 * 0.9375), roundi(48.0 * 0.9375), "magic roll after MDD 10")
		assert_eq(m.y, 0)
	var crit := ProjectileSystem.roll_damage(20.0, 20.0, false, 0.0, 150.0, 1.0, 1.5, rng)
	assert_eq(crit, Vector2i(30, 1), "crit x 1.5")


func test_damage_type_default_and_byte_codes() -> void:
	assert_eq(CombatMath.damage_type_of("", true), "magic", "the legacy magic flag")
	assert_eq(CombatMath.damage_type_of("", false), "fixed")
	assert_eq(CombatMath.damage_type_of("physical", true), "physical", "an explicit type wins")
	for name: String in CombatMath.DAMAGE_TYPE_NAMES:
		assert_eq(CombatMath.DAMAGE_TYPE_NAMES[CombatMath.damage_type_code(name)], name)
	assert_eq(CombatMath.damage_type_code("none"), CombatMath.DAMAGE_FIXED, "an unknown name behaves as fixed")
	var shots := ProjectileSystem.new()
	var slots: Array[int] = []
	for spec: Dictionary in [{}, {"magic": true}, {"damage_type": "physical"}, {"damage_type": "physical", "magic": true}]:
		slots.append(shots.spawn(spec))
	assert_eq(slots.map(func(s: int) -> int: return shots.damage_kind[s]),
		[CombatMath.DAMAGE_FIXED, CombatMath.DAMAGE_MAGIC, CombatMath.DAMAGE_PHYSICAL, CombatMath.DAMAGE_PHYSICAL])
