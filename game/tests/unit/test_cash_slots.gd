extends TestCase
## Cash catalog data, the eleven cash slots and Fortune from worn cash equipment (spec #34, ticket #116).

const SLOTS := ["hat", "face", "eye", "earrings", "top", "bottom", "shoes", "gloves", "cape", "weapon", "shield"]
# Representative v83 cash ids by category (id / 10000): hat 100, face 101, eye 102, earrings 103, top 104, overall 105,
# bottom 106, shoes 107, gloves 108, shield 109, cape 110, weapon cover 170.
const HAT := 1000001
const FACE := 1010001
const EYE := 1020001
const EARRINGS := 1030001
const TOP := 1040001
const OVERALL := 1050001
const BOTTOM := 1060001
const SHOES := 1070001
const GLOVES := 1080001
const SHIELD := 1090001
const CAPE := 1100001
const COVER := 1700001
const TWO_HANDED_COVER := 1700002 # synthetic: no Magician weapon is two-handed, so the rule is tested with data


func _catalog() -> CashCatalog:
	var data := DataRepo.load_all()
	var extra := [HAT, FACE, EYE, EARRINGS, TOP, OVERALL, BOTTOM, SHOES, GLOVES, SHIELD, CAPE, COVER]
	for id: int in extra:
		data.cash_items.items.append({"id": id, "kind": "equip", "price": 1000})
	data.cash_items.items.append({"id": TWO_HANDED_COVER, "kind": "equip", "price": 1000, "two_handed": true})
	return CashCatalog.from_data(data)


func _all_owned() -> Array:
	return [HAT, FACE, EYE, EARRINGS, TOP, OVERALL, BOTTOM, SHOES, GLOVES, SHIELD, CAPE, COVER, TWO_HANDED_COVER]


func test_slot_fortune_data_covers_the_eleven_slots_and_sums_to_100() -> void:
	var catalog := CashCatalog.from_data(DataRepo.load_all())
	assert_eq(catalog.slot_fortune.size(), 11)
	var sum := 0.0
	for slot: String in SLOTS:
		assert_true(catalog.slot_fortune.has(slot), "fortune for " + slot)
		assert_true(float(catalog.slot_fortune[slot]) > 0.0, slot + " adds Fortune")
		sum += float(catalog.slot_fortune[slot])
	assert_near(sum, 100.0, 1e-9, "tier C placeholders sum to 100 with every slot filled")
	assert_eq(CashCatalog.SLOTS, SLOTS)


func test_seed_items_use_the_real_commodity_prices_and_prerequisites() -> void:
	var catalog := CashCatalog.from_data(DataRepo.load_all())
	for pet: int in [5000000, 5000001, 5000002]:
		assert_eq(catalog.kind_of(pet), "pet")
		assert_eq(catalog.price_of(pet), 4900, "Commodity.img price of pet %d (tier A)" % pet)
	for upgrade: int in [1812002, 1812003, 1812004, 1812005]:
		assert_eq(catalog.kind_of(upgrade), "pet_upgrade")
		assert_eq(catalog.price_of(upgrade), 1800)
	assert_eq(catalog.kind_of(9990000), "pet_upgrade", "VAC is a survivor-only pet upgrade")
	assert_eq(catalog.price_of(9990000), 20000)
	assert_eq(catalog.item(9990000).desc, "Your pet pulls every drop on the map to itself. While a pet with VAC is out, "
		+ "the Magnet card is no longer offered.")
	assert_false(catalog.prerequisites_met(1812002, []), "an upgrade needs an owned pet")
	assert_true(catalog.prerequisites_met(1812002, [5000001]))
	assert_false(catalog.prerequisites_met(9990000, [5000000, 1812004]), "VAC needs Wing Boots and Binocular")
	assert_true(catalog.prerequisites_met(9990000, [5000000, 1812004, 1812005]))
	assert_false(catalog.prerequisites_met(9990000, [1812004, 1812005]), "and a pet")
	assert_true(catalog.prerequisites_met(5000000, []), "a pet needs nothing")


func test_slots_come_from_the_item_id_category() -> void:
	var catalog := _catalog()
	var expected := {HAT: ["hat"], FACE: ["face"], EYE: ["eye"], EARRINGS: ["earrings"], TOP: ["top"],
		BOTTOM: ["bottom"], SHOES: ["shoes"], GLOVES: ["gloves"], SHIELD: ["shield"], CAPE: ["cape"],
		COVER: ["weapon"], OVERALL: ["top", "bottom"], TWO_HANDED_COVER: ["weapon", "shield"]}
	for id: int in expected:
		assert_eq(catalog.slots_for(id), PackedStringArray(expected[id]), "slots of %d" % id)
	assert_eq(catalog.slots_for(1112000), PackedStringArray(), "rings are not cash slots")
	assert_eq(catalog.slots_for(5000000), PackedStringArray(), "a pet is not worn")


func test_fortune_is_the_sum_of_the_filled_slots() -> void:
	var catalog := _catalog()
	var owned := _all_owned()
	var one := catalog.resolve({"hat": HAT}, 0, owned)
	assert_near(one.fortune, float(catalog.slot_fortune.hat), 1e-9)
	var worn := {"hat": HAT, "face": FACE, "shoes": SHOES}
	var three := catalog.resolve(worn, 0, owned)
	assert_near(three.fortune, catalog.slot_fortune.hat + catalog.slot_fortune.face + catalog.slot_fortune.shoes, 1e-9)
	assert_eq(three.warnings, PackedStringArray())
	var every := {"hat": HAT, "face": FACE, "eye": EYE, "earrings": EARRINGS, "top": TOP, "bottom": BOTTOM,
		"shoes": SHOES, "gloves": GLOVES, "cape": CAPE, "weapon": COVER, "shield": SHIELD}
	assert_near(catalog.resolve(every, 0, owned).fortune, 100.0, 1e-9, "every slot filled")


func test_an_overall_fills_top_and_bottom_and_a_two_handed_cover_fills_weapon_and_shield() -> void:
	var catalog := _catalog()
	var owned := _all_owned()
	var overall := catalog.resolve({"top": OVERALL, "bottom": OVERALL}, 0, owned)
	assert_near(overall.fortune, catalog.slot_fortune.top + catalog.slot_fortune.bottom, 1e-9)
	var lone := catalog.resolve({"top": OVERALL}, 0, owned)
	assert_near(lone.fortune, overall.fortune, 1e-9, "the item, not the stored key, decides which slots it fills")
	var cover := catalog.resolve({"weapon": TWO_HANDED_COVER, "shield": TWO_HANDED_COVER}, 0, owned)
	assert_near(cover.fortune, catalog.slot_fortune.weapon + catalog.slot_fortune.shield, 1e-9)
	var both := catalog.resolve({"top": OVERALL, "bottom": OVERALL, "weapon": TWO_HANDED_COVER,
		"shield": TWO_HANDED_COVER}, 0, owned)
	assert_near(both.fortune, overall.fortune + cover.fortune, 1e-9)
	var one_handed := catalog.resolve({"weapon": COVER}, 0, owned)
	assert_near(one_handed.fortune, catalog.slot_fortune.weapon, 1e-9, "a one-handed cover leaves the shield slot empty")


func test_an_unowned_or_misplaced_item_gives_no_fortune_and_a_warning() -> void:
	var catalog := _catalog()
	var unowned := catalog.resolve({"hat": HAT, "face": FACE}, 0, [FACE])
	assert_near(unowned.fortune, catalog.slot_fortune.face, 1e-9, "only the owned item counts")
	assert_eq(unowned.warnings.size(), 1)
	assert_true(unowned.warnings[0].contains(str(HAT)) and unowned.warnings[0].contains("not owned"))
	assert_false(unowned.worn.has("hat"))
	var misplaced := catalog.resolve({"shoes": HAT}, 0, [HAT])
	assert_near(misplaced.fortune, 0.0, 1e-9, "a hat cannot be worn as shoes")
	assert_eq(misplaced.warnings.size(), 1)
	assert_eq(catalog.resolve({"bogus": HAT}, 0, [HAT]).warnings.size(), 1, "an unknown slot is reported")


func test_the_pet_must_be_an_owned_pet() -> void:
	var catalog := _catalog()
	assert_eq(catalog.resolve({}, 5000001, [5000001]).pet, 5000001)
	var unowned := catalog.resolve({}, 5000001, [5000000])
	assert_eq(unowned.pet, 0)
	assert_eq(unowned.warnings.size(), 1)
	var not_a_pet := catalog.resolve({}, 1812004, [1812004])
	assert_eq(not_a_pet.pet, 0, "an upgrade is not a pet")
	assert_eq(not_a_pet.warnings.size(), 1)
	var none := catalog.resolve({}, 0, [])
	assert_eq(none.pet, 0)
	assert_eq(none.warnings, PackedStringArray())
