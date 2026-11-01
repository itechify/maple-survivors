extends TestCase
## Bowman equipment (#201): shipped line data through seeded drops, scroll application and Free Market stock.
## Synthetic canonical-shaped info keeps the behaviour tests offline; the separate cache check verifies v83 facts/art.

const INFO := {
	1452002: {"reqJob": 4, "reqLevel": 10, "incPAD": 25, "tuc": 7},
	1452005: {"reqJob": 4, "reqLevel": 30, "incPAD": 45, "tuc": 7},
	1452009: {"reqJob": 4, "reqLevel": 70, "incPAD": 80, "tuc": 7},
	1462001: {"reqJob": 4, "reqLevel": 12, "incPAD": 29, "tuc": 7},
	1462000: {"reqJob": 4, "reqLevel": 28, "incPAD": 44, "tuc": 7},
	1462009: {"reqJob": 4, "reqLevel": 70, "incPAD": 83, "tuc": 7},
}


func _rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = 201
	return rng


func test_seeded_bowman_drops_use_only_the_listed_family_through_both_bands() -> void:
	var rules: Dictionary = DataRepo.load_all().equipment_drops
	for job in [300, 310, 320]:
		for family: String in ["bow", "crossbow"]:
			var rng := _rng()
			for band: Array in [[0, 30], [30, 70]]:
				var seen := {}
				for roll in 100:
					seen[EquipmentDrops.pick(rules.items, INFO, job, band, rules, rng, [family])] = true
					seen[EquipmentDrops.pick_boss(rules.items, INFO, job, band, rules, rng, [family])] = true
				assert_false(seen.has(0), "%d %s band %s has regular and boss drops" % [job, family, band])
				for id: int in seen:
					assert_eq(WeaponInfo.family(id), family, "%d only %s" % [id, family])
	for job in [0, 100, 200, 210, 400, 500, 520]:
		for family: String in ["bow", "crossbow"]:
			assert_eq(EquipmentDrops.eligible(rules.items, INFO, job, [0, 70], [family]), [])
			assert_eq(EquipmentDrops.pick_boss(rules.items, INFO, job, [0, 70], rules, _rng(), [family]), 0)


func test_scroll_shops_stock_each_bowman_family_at_the_weapon_price_and_only_for_bowmen() -> void:
	var data := DataRepo.load_all()
	var expected := {
		1032103: [2044500, 2044600],
		2022002: [2044501, 2044601],
		1052104: [2044502, 2044602],
		2041016: [2044504, 2044505, 2044604, 2044605],
	}
	for npc: Dictionary in data.shops.npcs:
		for job in [300, 310, 320]:
			var stock := Shop.stock(npc, data.shops, data.scrolls, data.equipment_drops.items, INFO, job)
			assert_eq(stock.map(func(row: Dictionary) -> int: return int(row.id)), expected[int(npc.id)])
			for row: Dictionary in stock:
				assert_eq(row.price, 70000)
		for job in [0, 100, 200, 210, 400, 500, 520]:
			assert_eq(Shop.stock(npc, data.shops, data.scrolls, data.equipment_drops.items, INFO, job), [])


func test_bowman_scrolls_spend_slots_only_on_their_own_family() -> void:
	var table: Dictionary = DataRepo.load_all().scrolls
	for pair: Array in [["bow", 1452002, 1462001], ["crossbow", 1462001, 1452002]]:
		var families: Dictionary = table.families.get(pair[0], {})
		assert_false(families.is_empty(), "%s scrolls exist" % pair[0])
		for by_rate: Dictionary in families.values():
			for rate: String in by_rate:
				var id := int(by_rate[rate])
				# Synthetic info guarantees success so the application and refusal can be checked without lucky rolls.
				var info := {"success": 100, "incPAD": 1}
				var own := {"weapon": Equipment.create(pair[1], INFO[pair[1]])}
				assert_eq(Scrolls.use(own, "weapon", id, info, _rng()), "success")
				assert_eq(own.weapon.slots, 6)
				assert_eq(own.weapon.stats.incPAD, int(INFO[pair[1]].incPAD) + 1)
				for wrong_id: int in [pair[2], 1302000, 1372005, 1482000, 1492000]:
					var wrong := {"weapon": Equipment.create(wrong_id, {"tuc": 7})}
					var before := wrong.duplicate(true)
					var rng := _rng()
					var state := rng.state
					assert_eq(Scrolls.use(wrong, "weapon", id, info, rng), "scroll_type")
					assert_eq(wrong, before)
					assert_eq(rng.state, state, "a refused scroll draws no RNG")


func test_every_bowman_drop_has_regular_v83_info_icons_and_progression_in_the_private_cache() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	var line: Dictionary = DataRepo.load_json(DataRepo.fragment_path("equipment_drops", "bowman", "res://data"))
	var data := DataRepo.load_all()
	var infos := {}
	var slots := {}
	var weapons := []
	for raw: Variant in line.items:
		var id := int(raw)
		var path := AvatarRenderer.part_img_path(id)
		var img := lib.img(path)
		assert_true(img != null, path)
		if img == null:
			continue
		var info: Dictionary = img.root.get("info", {})
		infos[id] = info
		assert_eq(int(info.get("reqJob", 0)), 4, "%d Bowman only" % id)
		assert_between(float(info.get("reqLevel", -1)), 10.0, 120.0, str(id)) # 120 since #474 (late bands)
		for field: String in ["cash", "tradeBlock", "notSale", "timeLimited", "expireOnLogout"]:
			assert_eq(int(info.get(field, 0)), 0, "%d %s" % [id, field])
		for icon: String in ["icon", "iconRaw"]:
			assert_true(lib.frame(path + "/info/" + icon) != null, "%d %s" % [id, icon])
		var slot := Equipment.slot_of(id)
		slots[slot] = true
		if slot == "weapon":
			weapons.append(id)
	assert_eq(weapons.size(), 51, "regular bow/crossbow progression to Lv110 (22 to Lv70 before #474), without instructor/event weapons")
	for slot: String in ["hat", "top", "bottom", "overall", "shoes", "gloves", "weapon"]:
		assert_has(slots, slot)
	assert_false(slots.has("shield"))
	for band: Array in [[0, 30], [30, 70]]:
		for family: String in ["bow", "crossbow"]:
			var eligible := EquipmentDrops.eligible(weapons, infos, 300, band, [family])
			assert_false(eligible.is_empty(), "%s progression in band %s" % [family, band])
	var scroll_infos := DataRepo.scroll_info(Scrolls.ids(data.scrolls), func(path: String) -> Dictionary:
		var img := lib.img(path)
		return img.root if img != null else {})
	for pair: Array in [[2044500, 1452002], [2044600, 1462001]]:
		var worn := {"weapon": Equipment.create(pair[1], infos[pair[1]])}
		assert_eq(Scrolls.use(worn, "weapon", pair[0], scroll_infos[pair[0]], _rng()), "success")
		assert_eq(worn.weapon.stats.incPAD, int(infos[pair[1]].incPAD) + 1, "canonical ATT +1")
	assert_eq(Array(lib.missing), [])
	lib.free()
