extends TestCase
## Job weapon families in equipment drops and the Warrior drop and scroll data (spec #151, #159, #292). A weapon only drops
## when its family is one of the job's weapon families (survivor/jobs/<line>.json, passed to EquipmentDrops as `families`),
## whatever the character holds; shields drop for the jobs whose reqJob admits them, armour is unchanged; drops keep the
## equipment stream. Item info is synthetic (shaped like Character.wz `info`); seeded RNG and fixed 1/60 s ticks.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0

## Synthetic items: id -> info. Warrior (reqJob 1) weapons and shield around level 30, Magician gear, all-job armour.
const INFO := {
	1002001: {"reqLevel": 0, "reqJob": 0, "incPDD": 4, "tuc": 7}, # hat, all jobs
	1040002: {"reqLevel": 30, "reqJob": 0, "incPDD": 3, "tuc": 7}, # top, all jobs
	1302008: {"reqLevel": 30, "reqJob": 1, "incPAD": 47, "attackSpeed": 5, "tuc": 7}, # one-handed sword
	1302004: {"reqLevel": 30, "reqJob": 1, "incPAD": 52, "attackSpeed": 5, "tuc": 7}, # one-handed sword
	1402002: {"reqLevel": 30, "reqJob": 1, "incPAD": 50, "attackSpeed": 6, "tuc": 7}, # two-handed sword
	1312005: {"reqLevel": 30, "reqJob": 1, "incPAD": 47, "attackSpeed": 6, "tuc": 7}, # one-handed axe
	1412006: {"reqLevel": 30, "reqJob": 1, "incPAD": 52, "attackSpeed": 6, "tuc": 7}, # two-handed axe
	1322014: {"reqLevel": 30, "reqJob": 1, "incPAD": 49, "attackSpeed": 6, "tuc": 7}, # one-handed blunt weapon
	1422001: {"reqLevel": 30, "reqJob": 1, "incPAD": 52, "attackSpeed": 6, "tuc": 7}, # two-handed blunt weapon
	1432002: {"reqLevel": 30, "reqJob": 1, "incPAD": 52, "attackSpeed": 8, "tuc": 7}, # spear
	1442001: {"reqLevel": 30, "reqJob": 1, "incPAD": 52, "attackSpeed": 8, "tuc": 7}, # polearm
	1092002: {"reqLevel": 30, "reqJob": 1, "incPDD": 40, "tuc": 7}, # Warrior shield
	1372004: {"reqLevel": 30, "reqJob": 2, "incPAD": 24, "incMAD": 38, "tuc": 7}, # wand
	1382012: {"reqLevel": 30, "reqJob": 2, "incMAD": 45, "tuc": 7}, # staff
	1050001: {"reqLevel": 30, "reqJob": 2, "incPDD": 20, "incMDD": 12, "tuc": 10}, # Magician overall
}
const RULES := {"boss_top_parts": 3}
const BAND := [0, 70]
const WARRIOR_WEAPONS := {
	"sword": [1302008, 1302004, 1402002], "axe": [1312005, 1412006], "blunt": [1322014, 1422001],
	"spear": [1432002], "polearm": [1442001],
}
const ARMOUR := [1002001, 1040002]


func _rng(p_seed: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = p_seed
	return rng


func _ids() -> Array:
	var ids := INFO.keys()
	ids.sort()
	return ids


func _eligible(job_id: int, families: Array) -> Array:
	return EquipmentDrops.eligible(_ids(), INFO, job_id, BAND, RULES, families)


func _weapons(ids: Array) -> Array:
	return ids.filter(func(id: int) -> bool: return Equipment.slot_of(id) == "weapon")


# --- the family filter -------------------------------------------------------------------------------------------

func test_a_sword_family_drops_one_and_two_handed_swords() -> void:
	var weapons := _weapons(_eligible(100, ["sword"]))
	weapons.sort()
	assert_eq(weapons, [1302004, 1302008, 1402002], "one- and two-handed swords, nothing else")


func test_an_axe_family_drops_only_axes() -> void:
	var weapons := _weapons(_eligible(100, ["axe"]))
	weapons.sort()
	assert_eq(weapons, [1312005, 1412006])


func test_every_warrior_family_drops_only_its_own_weapons() -> void:
	for family: String in WARRIOR_WEAPONS:
		var got := _weapons(_eligible(100, [family]))
		got.sort()
		var want: Array = WARRIOR_WEAPONS[family].duplicate()
		want.sort()
		assert_eq(got, want, "family %s" % family)


func test_several_families_drop_the_union() -> void:
	var got := _weapons(_eligible(100, ["axe", "polearm"]))
	got.sort()
	assert_eq(got, [1312005, 1412006, 1442001])


func test_a_job_without_families_drops_no_weapon_but_armour_and_shields_still_do() -> void:
	var ids := _eligible(100, [])
	assert_eq(_weapons(ids), [], "no weapon without a family")
	assert_true(1040002 in ids and 1092002 in ids, "armour and the shield are not weapons")


func test_armour_does_not_depend_on_the_families() -> void:
	for families: Array in [[], ["sword"], ["polearm"], ["wand"]]:
		var ids := _eligible(100, families).filter(func(id: int) -> bool: return Equipment.slot_of(id) != "weapon")
		assert_eq(ids, [1002001, 1040002, 1092002], "families %s" % [families])


func test_a_weapon_of_another_job_never_drops_whatever_the_families() -> void:
	assert_false(1372004 in _eligible(100, ["wand"]), "a Warrior cannot wear a wand even with the family listed")
	assert_false(1302008 in _eligible(200, ["sword"]), "a Magician cannot wear a Warrior sword")
	assert_false(1302008 in _eligible(0, ["sword"]), "a Beginner cannot wear it either")


# --- shields ------------------------------------------------------------------------------------------------------

func test_shields_drop_for_a_warrior_line_job_and_never_for_a_magician_or_beginner() -> void:
	for job in [100, 110, 111, 120, 130]:
		assert_true(1092002 in _eligible(job, ["sword"]), "job %d wears the Warrior shield" % job)
	for job in [0, 200, 210, 220, 230, 300, 400, 500]:
		assert_false(1092002 in _eligible(job, ["sword"]), "job %d does not" % job)
		assert_false(1092002 in _eligible(job, []), "job %d does not, without families" % job)


# --- wand and staff: the Magician's two families (the shipped 212 data) ----------------------------------------------

func test_the_magician_lists_both_and_each_family_alone_drops_only_itself() -> void:
	var both := _weapons(_eligible(200, ["wand", "staff"]))
	both.sort()
	assert_eq(both, [1372004, 1382012])
	assert_eq(_weapons(_eligible(200, ["wand"])), [1372004])
	assert_eq(_weapons(_eligible(200, ["staff"])), [1382012])
	assert_eq(_weapons(_eligible(200, ["sword"])), [], "a Magician listing only swords gets no wand")


# --- pick and pick_boss ---------------------------------------------------------------------------------------------

func test_pick_and_pick_boss_never_return_a_weapon_of_another_family() -> void:
	var rng := _rng(11)
	for family: String in ["sword", "axe", "blunt", "spear", "polearm", ""]:
		var families := [family] if family != "" else []
		for i in 80:
			for id: int in [EquipmentDrops.pick(_ids(), INFO, 100, BAND, RULES, rng, families),
					EquipmentDrops.pick_boss(_ids(), INFO, 100, BAND, RULES, rng, families)]:
				assert_true(id > 0, "something always drops")
				if Equipment.slot_of(id) == "weapon":
					assert_eq(WeaponInfo.family(id), family, "family '%s' got %d" % [family, id])


func test_the_boss_fallback_for_an_empty_band_respects_the_families() -> void:
	# band 60..70 holds nothing, so the nearest item by level wins; a polearm job never gets a sword
	for i in 40:
		var id := EquipmentDrops.pick_boss(_ids(), INFO, 100, [60, 70], RULES, _rng(i), ["polearm"])
		assert_true(id in [1442001, 1092002, 1040002], "got %d" % id)


func test_pick_is_deterministic_per_seed() -> void:
	var a := EquipmentDrops.pick(_ids(), INFO, 100, BAND, RULES, _rng(5), ["sword"])
	var b := EquipmentDrops.pick(_ids(), INFO, 100, BAND, RULES, _rng(5), ["sword"])
	assert_eq(a, b)


# --- RunWorld: kills and bosses drop by the job's families ------------------------------------------------------------------

func _fit(setup: Dictionary) -> Dictionary:
	for id: int in INFO:
		var merged: Dictionary = setup.equipment_info.get(id, {}).duplicate()
		merged.merge(INFO[id], true)
		setup.equipment_info[id] = merged
	return setup


## A world of `job` on the quiet map (Lv1, tier 1: band 0..30) whose drop list is `items`, wearing weapon `held` (0 = bare
## hands); `job` lists the weapon `families`.
func _world(items: Array, job: int, families: Array, held: int, p_seed := 31, chance := 1.0) -> RunWorld:
	var data := RF.quiet_data()
	data.equipment_drops.items = items
	data.equipment_drops.chance = chance
	data.jobs_survivor.jobs["212"]["starting_skill"] = ""; data.jobs_survivor.jobs["212"]["mobility_skill"] = ""
	data.jobs_survivor.jobs[str(job)] = data.jobs_survivor.jobs.get(str(job), {}).duplicate()
	data.jobs_survivor.jobs[str(job)]["weapon_families"] = families
	var w := RunWorld.new(_fit(RF.setup("quiet", p_seed, data)))
	RF.place_player(w, 400)
	w.god = true
	if job != 0:
		RF.change_job_bare(w, job)
	_hold(w, held)
	w.drain_events()
	return w


func _hold(w: RunWorld, id: int) -> void:
	if id > 0:
		w.equipment.worn["weapon"] = Equipment.create(id, INFO[id])
	else:
		w.equipment.worn.erase("weapon")


func _kill_at(w: RunWorld, x: float) -> void:
	var slot := RF.put_mob(w, 100100, x)
	w.hit_mob(slot, {"damage_min": 1000000.0, "damage_max": 1000000.0, "magic": false, "crit": 0.0,
		"crit_mult": 1.5, "skill": "three_snails"}, -1)


func _dropped_ids(w: RunWorld, kills: int) -> Array:
	var ids := []
	for i in kills:
		_kill_at(w, 405)
		for e: Dictionary in w.drain_events():
			if e.type == "pickup_spawned" and e.kind == "equip":
				ids.append(int(e.item_id))
		for p in w.pickups.capacity():
			w.pickups.despawn(p)
	return ids


func _distinct_weapons(ids: Array) -> Array:
	var seen := {}
	for id: int in _weapons(ids):
		seen[id] = true
	var out := seen.keys()
	out.sort()
	return out


func test_a_warrior_with_the_sword_family_gets_only_swords_and_the_shield() -> void:
	var w := _world(_ids(), 100, ["sword"], 1302008)
	var ids := _dropped_ids(w, 160)
	assert_eq(_distinct_weapons(ids), [1302004, 1302008, 1402002], "one- and two-handed swords, every one of them")
	assert_true(1092002 in ids and 1040002 in ids, "the shield and the armour drop too")
	assert_false(1372004 in ids or 1382012 in ids or 1050001 in ids, "no Magician gear")


func test_another_family_changes_the_weapons_not_the_armour() -> void:
	for family: String in ["axe", "blunt", "spear", "polearm"]:
		var w := _world(_ids(), 100, [family], 0)
		var ids := _dropped_ids(w, 140)
		var weapons := _distinct_weapons(ids)
		assert_true(weapons.size() >= 1, "the %s job gets weapons" % family)
		for id: int in weapons:
			assert_eq(WeaponInfo.family(id), family, "%s job got %d" % [family, id])
		assert_true(1092002 in ids and 1040002 in ids, "armour and shield for the %s job" % family)


func test_the_held_weapon_is_not_read_when_the_drop_rolls() -> void:
	var sword := _world(_ids(), 100, ["polearm"], 1302008)
	var bare := _world(_ids(), 100, ["polearm"], 0)
	assert_eq(_distinct_weapons(_dropped_ids(sword, 120)), [1442001], "a polearm job holding a sword still gets polearms")
	assert_eq(_distinct_weapons(_dropped_ids(bare, 120)), [1442001], "and bare-handed too")


func test_a_job_without_weapon_families_drops_everything_but_weapons() -> void:
	var w := _world(_ids(), 100, [], 1302008)
	var ids := _dropped_ids(w, 120)
	assert_eq(_weapons(ids), [])
	assert_true(1092002 in ids and 1040002 in ids)


func test_shields_never_drop_for_a_magician() -> void:
	var w := _world(_ids(), 212, ["wand", "staff"], 1372004)
	assert_false(1092002 in _dropped_ids(w, 120))


func test_the_warrior_line_leaves_the_magician_drops_identical() -> void:
	# The same seed with and without the Warrior ids in the list: a Magician draws the same stream.
	var magician_only := _ids().filter(func(id: int) -> bool: return int(INFO[id].reqJob) != 1)
	var a := _world(magician_only, 212, ["wand", "staff"], 1372004, 77, 0.5)
	var b := _world(_ids(), 212, ["wand", "staff"], 1372004, 77, 0.5)
	var da := _dropped_ids(a, 150)
	var db := _dropped_ids(b, 150)
	assert_true(da.size() > 20, "a real sample")
	assert_eq(da, db, "same seed, same drops")


func test_a_boss_drops_a_weapon_of_the_job_families_only() -> void:
	for p_seed in [1, 2, 3, 4, 5, 6, 7, 8]:
		var data := RF.quiet_data()
		data.equipment_drops.items = _ids()
		data.equipment_drops.chance = 0.0
		data.jobs_survivor.jobs["212"]["starting_skill"] = ""; data.jobs_survivor.jobs["212"]["mobility_skill"] = ""
		data.jobs_survivor.jobs["100"] = {"weapon_families": ["spear"]}
		RF.set_bosses(data.stages.stages.quiet, [{"time": 0.1, "mob_id": 2220000, "hp_mult": 1.0,
			"rewards": {"exp_mult": 5, "exp_drops": 2, "spread": 100, "potions": {"hp": 1, "mp": 1}, "bonus_choices": 1}}])
		var w := RunWorld.new(_fit(RF.setup("quiet", p_seed, data)))
		RF.place_player(w, 400)
		w.god = true
		RF.change_job_bare(w, 100)
		_hold(w, 1302008)
		for i in 6:
			w.step(DT, MoveInput.new())
		w.drain_events()
		w.hit_mob(int(w.bosses.records[0].slot), {"damage_min": 1000000.0, "damage_max": 1000000.0,
			"magic": false, "crit": 0.0, "crit_mult": 1.5, "skill": "three_snails"}, -1)
		var spawned := w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "pickup_spawned" and e.kind == "equip")
		assert_eq(spawned.size(), 2, "exactly two boss items (seed %d)" % p_seed)
		for drop: Dictionary in spawned:
			var id := int(drop.item_id)
			# tier 1 band 0..30, top third 20..30 -> the level-30 items; a spear job never gets another weapon
			assert_true(Equipment.slot_of(id) != "weapon" or WeaponInfo.family(id) == "spear", "seed %d: got %d" % [p_seed, id])


# --- the shipped Warrior data ---------------------------------------------------------------------------------------------

## Item category (Scrolls.category_of_item) of every weapon kind and the shield, by scroll slot name.
const SLOT_CATEGORY := {"sword": 30, "axe": 31, "blunt": 32, "two_handed_sword": 40, "two_handed_axe": 41,
	"two_handed_blunt": 42, "spear": 43, "polearm": 44, "shield": 9}
const WARRIOR_FAMILIES := ["sword", "axe", "blunt", "spear", "polearm"]
## Drop-info for the shop tests: one real id of the shipped list per category, shaped like Character.wz info.
const SHOP_INFO := {
	1002001: {"incPDD": 4, "tuc": 7}, 1372005: {"reqJob": 2, "reqLevel": 8, "tuc": 7}, 1382012: {"reqJob": 2, "reqLevel": 30, "tuc": 7},
	1302008: {"reqJob": 1, "reqLevel": 30, "tuc": 7}, 1312005: {"reqJob": 1, "reqLevel": 30, "tuc": 7},
	1322014: {"reqJob": 1, "reqLevel": 30, "tuc": 7}, 1402002: {"reqJob": 1, "reqLevel": 30, "tuc": 7},
	1412006: {"reqJob": 1, "reqLevel": 30, "tuc": 7}, 1422001: {"reqJob": 1, "reqLevel": 30, "tuc": 7},
	1432002: {"reqJob": 1, "reqLevel": 30, "tuc": 7}, 1442001: {"reqJob": 1, "reqLevel": 30, "tuc": 7},
	1092002: {"reqJob": 1, "reqLevel": 30, "tuc": 7},
}


func _warrior_ids() -> Array:
	var d: Dictionary = DataRepo.load_json(DataRepo.fragment_path("equipment_drops", "warrior", DataRepo.DATA_ROOT))
	return d.items.map(func(raw: Variant) -> int: return int(raw)) # JSON numbers are floats; `in` needs ints


func test_the_warrior_drop_list_is_weapons_of_the_five_families_and_shields_no_duplicates() -> void:
	var errors := PackedStringArray()
	var data := DataRepo.load_all(DataRepo.DATA_ROOT, errors)
	assert_eq(errors, PackedStringArray(), "no duplicate id across the line files")
	var ids := _warrior_ids()
	assert_true(ids.size() > 80, "a real list")
	var families := {}
	var shields := 0
	for raw: Variant in ids:
		var id := int(raw)
		var slot := Equipment.slot_of(id)
		assert_true(slot in ["weapon", "shield"], "%d is a weapon or a shield" % id)
		if slot == "weapon":
			var family := WeaponInfo.family(id)
			assert_true(family in WARRIOR_FAMILIES, "%d is a %s" % [id, family])
			families[family] = int(families.get(family, 0)) + 1
		else:
			shields += 1
		assert_true(float(id) in data.equipment_drops.items, "%d reaches the merged list" % id)
	assert_eq(families.keys().size(), 5, "every Warrior family has drops")
	assert_true(shields >= 10, "and shields")
	var sorted_ids := ids.duplicate()
	sorted_ids.sort()
	assert_eq(ids, sorted_ids, "the fragment is ascending")


func test_both_hand_variants_are_in_the_list() -> void:
	var types := {}
	for raw: Variant in _warrior_ids():
		types[WeaponInfo.type_of(int(raw))] = true
	for type in [130, 131, 132, 140, 141, 142, 143, 144, 109]:
		assert_true(types.has(type), "type %d" % type)


func test_every_listed_warrior_item_is_in_the_asset_manifest() -> void:
	var listed := {}
	var merged := AssetManifest.load_merged("res://data/asset_manifest.json")
	for id: Variant in merged.get("character", []):
		listed[int(id)] = true
	for raw: Variant in _warrior_ids():
		assert_true(listed.has(int(raw)), "%d is imported (asset_manifest.d/warrior.json)" % int(raw))


func test_the_warrior_scroll_slots_match_the_item_they_scroll() -> void:
	var table: Dictionary = DataRepo.load_all().scrolls
	for slot: String in SLOT_CATEGORY:
		assert_true(table.families.has(slot), slot)
		for family: String in table.families[slot]:
			for id: Variant in table.families[slot][family].values():
				assert_eq(Scrolls.category_of_scroll(int(id)), int(SLOT_CATEGORY[slot]), "%d under %s %s" % [int(id), slot, family])
	for slot: String in ["sword", "axe", "blunt", "two_handed_sword", "two_handed_axe", "two_handed_blunt", "spear", "polearm"]:
		assert_true(table.families[slot].has("ATT") and table.families[slot].has("ACC"), slot)
		assert_eq(table.families[slot].ATT.keys(), ["100", "60", "10", "dark70", "dark30"])
	assert_eq(table.families.sword.ATT["100"], 2043000, "One-Handed Sword for ATT 100%")
	assert_eq(table.families.two_handed_sword.ATT["60"], 2044001)
	assert_eq(table.families.spear.ATT["10"], 2044302)
	assert_eq(table.families.polearm.ACC["dark30"], 2044413)
	assert_eq(table.families.shield.DEF["100"], 2040900)
	assert_false(table.families.shield.ATT.has("100"), "v83 has no 100% shield ATT scroll")


func _stock(npc_id: int, job_id: int) -> Array:
	var data := DataRepo.load_all()
	for npc: Dictionary in data.shops.npcs:
		if int(npc.id) == npc_id:
			return Shop.stock(npc, data.shops, data.scrolls, data.equipment_drops.items, SHOP_INFO, job_id)
	return []


func _slots(stock: Array) -> Array:
	var seen := {}
	for e: Dictionary in stock:
		seen[String(e.slot)] = true
	var out := seen.keys()
	out.sort()
	return out


func test_a_warrior_in_the_free_market_sees_the_weapon_and_shield_scrolls() -> void:
	var slots := _slots(_stock(1032103, 100))
	for slot: String in SLOT_CATEGORY:
		assert_true(slot in slots, "a Warrior sees %s scrolls" % slot)
	assert_false("wand" in slots or "staff" in slots, "but no Magician weapon scrolls")
	for job in [110, 111, 120, 130]:
		assert_eq(_slots(_stock(1032103, job)), slots, "job %d shops like the Warrior" % job)


func test_warrior_scrolls_cost_the_v83_prices_and_come_at_every_rate() -> void:
	for e: Dictionary in _stock(1032103, 100):
		if e.slot == "shield":
			assert_eq(e.price, 35000, "shield scrolls are armour-priced")
		elif e.slot in SLOT_CATEGORY:
			assert_eq(e.price, 70000, "%s scrolls are weapon-priced" % e.slot)
	var sword_ids := _stock(1032103, 100).filter(func(e: Dictionary) -> bool: return e.slot == "sword").map(
		func(e: Dictionary) -> int: return int(e.id))
	assert_eq(sword_ids, [2043000, 2043015], "100%: ATT and ACC")
	var dark := _stock(2041016, 100).filter(func(e: Dictionary) -> bool: return e.slot == "polearm").map(
		func(e: Dictionary) -> int: return int(e.id))
	assert_eq(dark, [2044404, 2044405, 2044411, 2044413], "Vega: dark 70% then dark 30% of ATT, then of ACC")


func test_a_magician_and_a_beginner_shop_exactly_as_before() -> void:
	for job in [0, 200, 210, 220, 230]:
		var slots := _slots(_stock(1032103, job))
		for slot: String in SLOT_CATEGORY:
			assert_false(slot in slots, "job %d never sees %s scrolls" % [job, slot])
		var warrior_free := _stock_without_warrior(1032103, job)
		assert_eq(_stock(1032103, job), warrior_free, "job %d: the stock equals the one without the Warrior line's data" % job)


## Shop.stock for `job_id` with the Warrior line's scrolls, drops and weapon slots taken out (the pre-#159 data).
func _stock_without_warrior(npc_id: int, job_id: int) -> Array:
	var data := DataRepo.load_all()
	var scrolls: Dictionary = data.scrolls.duplicate(true)
	for slot: String in SLOT_CATEGORY:
		scrolls.families.erase(slot)
	var rules: Dictionary = data.shops.duplicate(true)
	rules.weapon_slots = rules.weapon_slots.filter(func(s: String) -> bool: return not s in SLOT_CATEGORY)
	var warrior := _warrior_ids()
	var items: Array = data.equipment_drops.items.filter(func(id: Variant) -> bool: return not int(id) in warrior)
	assert_eq(items.size(), data.equipment_drops.items.size() - warrior.size(), "the Warrior ids were taken out")
	for npc: Dictionary in data.shops.npcs:
		if int(npc.id) == npc_id:
			return Shop.stock(npc, rules, scrolls, items, SHOP_INFO, job_id)
	return []


# --- against the real v83 asset cache (SKIP without it) ---------------------------------------------------------------------

func _cache_infos(ids: Array) -> Dictionary:
	var lib := AssetLibrary.new()
	lib.open()
	var infos := {}
	for raw: Variant in ids:
		var img := lib.img(AvatarRenderer.part_img_path(int(raw)))
		if img != null:
			infos[int(raw)] = img.root.get("info", {})
	lib.free()
	return infos


func test_every_listed_warrior_item_is_a_real_non_cash_warrior_item_with_an_icon() -> void:
	if not require_cache():
		return
	var ids := _warrior_ids()
	var infos := _cache_infos(ids)
	for raw: Variant in ids:
		var id := int(raw)
		assert_true(infos.has(id), "%d imported" % id)
		if not infos.has(id):
			continue
		var info: Dictionary = infos[id]
		assert_eq(int(info.get("cash", 0)), 0, "%d is not cash" % id)
		assert_true(int(info.get("reqJob", 0)) > 0 and (int(info.get("reqJob", 0)) & 1) != 0, "%d carries the Warrior bit" % id)
		assert_true(int(info.get("reqLevel", 0)) <= 70, "%d: level" % id)
		assert_true(info.has("icon") or info.has("iconRaw"), "%d has an icon" % id)


func test_every_shipped_band_has_drops_for_each_warrior_family_and_for_a_boss() -> void:
	if not require_cache():
		return
	var data := DataRepo.load_all()
	var infos := _cache_infos(data.equipment_drops.items)
	var ed: Dictionary = data.equipment_drops
	var rng := _rng(3)
	for tier in data.stages.tiers.size():
		var band := EquipmentDrops.band_of(data.stages, tier)
		for family in WARRIOR_FAMILIES:
			var got := _weapons(EquipmentDrops.eligible(ed.items, infos, 100, band, ed, [family]))
			assert_true(got.size() > 0, "tier %d band %s has a %s weapon" % [tier + 1, band, family])
			for id: int in got:
				assert_eq(WeaponInfo.family(id), family)
		assert_true(EquipmentDrops.pick_boss(ed.items, infos, 100, band, ed, rng, ["sword"]) > 0, "tier %d boss" % (tier + 1))
		assert_true(EquipmentDrops.eligible(ed.items, infos, 100, band, ed, []).size() > 0, "tier %d without a family" % (tier + 1))


func test_the_magician_drop_pools_are_unchanged_by_the_warrior_data() -> void:
	if not require_cache():
		return
	var data := DataRepo.load_all()
	var warrior := _warrior_ids()
	var old_items: Array = data.equipment_drops.items.filter(func(id: Variant) -> bool: return not int(id) in warrior)
	assert_eq(old_items.size(), data.equipment_drops.items.size() - warrior.size(), "the Warrior ids were taken out")
	var infos := _cache_infos(data.equipment_drops.items)
	var ed: Dictionary = data.equipment_drops
	for tier in data.stages.tiers.size():
		var band := EquipmentDrops.band_of(data.stages, tier)
		for job in [200, 210, 220, 230, 212]:
			assert_eq(EquipmentDrops.eligible(ed.items, infos, job, band, ed, ["wand", "staff"]),
				EquipmentDrops.eligible(old_items, infos, job, band, ed, ["wand", "staff"]), "job %d tier %d" % [job, tier + 1])
		# no Warrior-only gear ever reaches a Magician or a Beginner
		for job in [0, 200]:
			for id: int in EquipmentDrops.eligible(ed.items, infos, job, band, ed, ["sword"]):
				assert_false(id in warrior, "%d for job %d" % [id, job])


func test_the_212_magician_finds_wands_staves_and_every_armour_slot_in_both_shipped_bands() -> void:
	if not require_cache():
		return
	var data := DataRepo.load_all()
	var infos := _cache_infos(data.equipment_drops.items)
	var ed: Dictionary = data.equipment_drops
	var jobs := JobTree.from_data(data.jobs, data.jobs_survivor)
	for tier in data.stages.tiers.size():
		var band := EquipmentDrops.band_of(data.stages, tier)
		var ids := EquipmentDrops.eligible(ed.items, infos, 212, band, ed, jobs.weapon_families(212))
		var families := {}
		var slots := {}
		for id: int in ids:
			slots[Equipment.slot_of(id)] = true
			if Equipment.slot_of(id) == "weapon":
				families[WeaponInfo.family(id)] = true
		assert_eq(families.keys(), ["wand", "staff"] if families.keys()[0] == "wand" else ["staff", "wand"],
			"tier %d: wands and staves" % (tier + 1))
		for slot in ["hat", "top", "overall", "bottom", "shoes", "gloves", "weapon"]:
			assert_true(slots.has(slot), "tier %d: a Magician %s drop" % [tier + 1, slot])
