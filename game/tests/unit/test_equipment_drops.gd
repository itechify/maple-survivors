extends TestCase
## Equipment drops (spec #33, #109, #292): v83 random stats, the job and tier-band filters, the boss "top third" rule,
## the EQUIP pickup kind (including a full Equip tab) and kill drops in RunWorld. Item info is synthetic (shaped like
## Character.wz `info`); seeded RNG and fixed 1/60 s ticks.

const WF := preload("res://tests/fixtures/world_fixtures.gd")
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0

## Synthetic eligible items: id -> info. Levels 0..40 for Beginner (reqJob 0) and Magician (reqJob 2) gear.
const INFO := {
	1002001: {"reqLevel": 0, "reqJob": 0, "incPDD": 4, "tuc": 7}, # hat, all jobs
	1002017: {"reqLevel": 10, "reqJob": 2, "incPDD": 5, "incMDD": 15, "tuc": 7}, # Magician hat
	1040002: {"reqLevel": 0, "reqJob": 0, "incPDD": 3, "tuc": 7}, # top, all jobs
	1050001: {"reqLevel": 23, "reqJob": 2, "incPDD": 20, "incMDD": 12, "tuc": 10}, # Magician overall
	1072006: {"reqLevel": 10, "reqJob": 2, "incPDD": 3, "tuc": 5}, # Magician shoes
	1082019: {"reqLevel": 15, "reqJob": 2, "incPDD": 4, "tuc": 5}, # Magician gloves
	1372005: {"reqLevel": 8, "reqJob": 0, "incPAD": 15, "incMAD": 23, "tuc": 7}, # Wooden Wand, all jobs
	1372004: {"reqLevel": 23, "reqJob": 2, "incPAD": 24, "incMAD": 38, "tuc": 7}, # Ice Wand
	1372000: {"reqLevel": 38, "reqJob": 2, "incPAD": 33, "incMAD": 53, "tuc": 7}, # Fairy Wand
	1382019: {"reqLevel": 40, "reqJob": 2, "incPAD": 38, "incMAD": 55, "tuc": 7}, # staff
}
const RULES := {"boss_top_parts": 3}


func _rng(p_seed: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = p_seed
	return rng


func _ids() -> Array:
	var ids := INFO.keys()
	ids.sort()
	return ids


# --- v83 random stats (tier B) ---

func test_a_wooden_wand_rolls_its_matt_between_20_and_26_and_covers_the_whole_range() -> void:
	var rng := _rng(1)
	var seen := {}
	for i in 600:
		var drop := Equipment.create_drop(1372005, INFO[1372005], rng)
		seen[int(drop.stats.incMAD)] = true
	var low := 99
	var high := 0
	for v: int in seen:
		low = mini(low, v)
		high = maxi(high, v)
	assert_eq([low, high], [20, 26], "M.ATT 23 varies by up to ceil(10%) = 3 either way")
	assert_eq(seen.size(), 7, "every whole number between shows up")


func test_every_stat_stays_within_its_spread_and_cap() -> void:
	# base -> [max spread]: 10% rounded up, capped 5 (STR DEX INT LUK PAD MAD ACC EVA Speed Jump) or 10 (PDD MDD MHP MMP).
	var info := {"incSTR": 3, "incDEX": 50, "incINT": 12, "incLUK": 1, "incPAD": 15, "incMAD": 80, "incACC": 20,
		"incEVA": 2, "incSpeed": 15, "incJump": 30, "incPDD": 150, "incMDD": 42, "incMHP": 100, "incMMP": 200, "tuc": 7}
	var spread := {"incSTR": 1, "incDEX": 5, "incINT": 2, "incLUK": 1, "incPAD": 2, "incMAD": 5, "incACC": 2,
		"incEVA": 1, "incSpeed": 2, "incJump": 3, "incPDD": 10, "incMDD": 5, "incMHP": 10, "incMMP": 10}
	var rng := _rng(2)
	var lo := {}
	var hi := {}
	for i in 1500:
		var drop := Equipment.create_drop(1002017, info, rng)
		assert_eq(drop.slots, 7, "upgrade slots never vary (tuc)")
		assert_eq(drop.scrolls, 0)
		for key: String in spread:
			var v := int(drop.stats[key]) if drop.stats.has(key) else 0
			lo[key] = mini(int(lo.get(key, 9999)), v)
			hi[key] = maxi(int(hi.get(key, -1)), v)
	for key: String in spread:
		assert_between(float(lo[key]), float(maxi(0, int(info[key]) - int(spread[key]))), float(info[key]), "%s low end" % key)
		assert_between(float(hi[key]), float(info[key]), float(int(info[key]) + int(spread[key])), "%s high end" % key)
		assert_eq(int(lo[key]), maxi(0, int(info[key]) - int(spread[key])), "%s reaches the bottom of its spread" % key)
		assert_eq(int(hi[key]), int(info[key]) + int(spread[key]), "%s reaches the top of its spread" % key)


func test_a_stat_never_drops_below_zero_and_zero_stats_stay_absent() -> void:
	var rng := _rng(3)
	var zeros := 0
	for i in 400:
		var drop := Equipment.create_drop(1002017, {"incSTR": 1, "incPDD": 0, "tuc": 3}, rng)
		assert_false(drop.stats.has("incPDD"), "a zero base is never rolled")
		var v := int(drop.stats.get("incSTR", 0))
		assert_between(float(v), 0.0, 2.0, "base 1 rolls 0..2")
		if v == 0:
			zeros += 1
			assert_false(drop.stats.has("incSTR"), "stats holds only non-zero values")
	assert_true(zeros > 0, "a spread to 0 happens")


func test_stats_outside_the_listed_caps_and_non_inc_info_are_kept_as_they_are() -> void:
	var rng := _rng(4)
	var drop := Equipment.create_drop(1372005, {"incPAD": 15, "incRMAF": 110, "reqLevel": 8, "price": 1000, "tuc": 7}, rng)
	assert_eq(drop.stats.incRMAF, 110, "no listed spread for it")
	assert_false(drop.stats.has("price") or drop.stats.has("reqLevel"))


func test_create_drop_is_deterministic_per_seed() -> void:
	var a := Equipment.create_drop(1372000, INFO[1372000], _rng(77))
	var b := Equipment.create_drop(1372000, INFO[1372000], _rng(77))
	assert_eq(a, b)
	assert_eq(a.id, 1372000)


# --- job and band filters ---

const WEAPONS := ["wand", "staff"]


func test_a_beginner_only_gets_all_job_items_and_a_magician_both() -> void:
	var beginner := EquipmentDrops.eligible(_ids(), INFO, 0, [0, 30], [])
	for id: int in beginner:
		assert_eq(int(INFO[id].reqJob), 0, "%d is for every job" % id)
	assert_true(1002001 in beginner and 1040002 in beginner)
	assert_false(1372005 in beginner, "no weapon family, no wand (the job lists none)")
	assert_false(1002017 in beginner, "a Magician hat never drops for a Beginner")
	var magician := EquipmentDrops.eligible(_ids(), INFO, 200, [0, 30], WEAPONS)
	assert_true(1002017 in magician and 1372005 in magician and 1072006 in magician, "Magician and all-job")
	for job in [210, 220, 230, 211, 232]:
		assert_true(1002017 in EquipmentDrops.eligible(_ids(), INFO, job, [0, 30], WEAPONS), "job %d wears Magician gear" % job)
	assert_false(1002017 in EquipmentDrops.eligible(_ids(), INFO, 100, [0, 30], WEAPONS), "a Warrior line is not eligible")


func test_the_band_is_inclusive_at_both_ends_and_the_level_is_not_an_input() -> void:
	assert_eq(EquipmentDrops.eligible(_ids(), INFO, 200, [23, 23], WEAPONS), [1050001, 1372004],
		"reqLevel 23 exactly: the overall and the Ice Wand")
	assert_eq(EquipmentDrops.eligible(_ids(), INFO, 200, [24, 37], WEAPONS), [], "nothing between 24 and 37")
	assert_eq(EquipmentDrops.eligible(_ids(), INFO, 200, [38, 38], WEAPONS), [1372000], "the Lv38 wand at the edge")
	assert_true(1382019 in EquipmentDrops.eligible(_ids(), INFO, 200, [30, 60], WEAPONS), "Lv40 is inside 30..60")
	assert_false(1002017 in EquipmentDrops.eligible(_ids(), INFO, 200, [30, 60], WEAPONS), "Lv10 is below it")


func test_items_missing_from_the_info_table_never_drop() -> void:
	assert_eq(EquipmentDrops.eligible([1002001, 9999999], {1002001: INFO[1002001]}, 0, [0, 30], []), [1002001])


func test_every_item_in_the_band_is_equally_likely() -> void:
	var rng := _rng(5)
	var counts := {}
	for i in 6000:
		var id := EquipmentDrops.pick(_ids(), INFO, 200, [0, 30], RULES, rng, WEAPONS)
		counts[id] = int(counts.get(id, 0)) + 1
	# Lv0..30 for a Magician: 1002001, 1040002, 1002017, 1072006, 1082019, 1050001, 1372005, 1372004 (8 items)
	assert_eq(counts.size(), 8)
	for id: int in counts:
		assert_between(float(counts[id]), 750.0 - 130.0, 750.0 + 130.0, "item %d" % id)
	assert_false(counts.has(1372000), "Lv38 is outside the band")


func test_pick_returns_nothing_for_an_empty_band_and_is_deterministic() -> void:
	assert_eq(EquipmentDrops.pick(_ids(), INFO, 0, [60, 70], RULES, _rng(1), []), 0, "nothing in 60..70 for a Beginner")
	var a: Array = []
	var b: Array = []
	var ra := _rng(9)
	var rb := _rng(9)
	for i in 50:
		a.append(EquipmentDrops.pick(_ids(), INFO, 200, [0, 30], RULES, ra, WEAPONS))
		b.append(EquipmentDrops.pick(_ids(), INFO, 200, [0, 30], RULES, rb, WEAPONS))
	assert_eq(a, b)


# --- bosses: the top third of the band ---

func test_a_boss_item_comes_from_the_top_third_of_the_band() -> void:
	var rng := _rng(6)
	var seen := {}
	for i in 300:
		seen[EquipmentDrops.pick_boss(_ids(), INFO, 200, [0, 30], RULES, rng, WEAPONS)] = true
	# band 0..30, top third = reqLevel 20..30: only the reqLevel 23 items (overall, Ice Wand).
	var got := seen.keys()
	got.sort()
	assert_eq(got, [1050001, 1372004])


func test_a_boss_falls_back_to_the_highest_item_in_the_band_then_the_nearest_item() -> void:
	# band 5..17: top third 13..17 holds only the Gloves (15)
	assert_eq(EquipmentDrops.pick_boss(_ids(), INFO, 200, [5, 17], RULES, _rng(1), WEAPONS), 1082019)
	# band 5..14: nothing at 10..14 but the Lv10 hat/shoes and the Lv8 wand; top third 10..14 -> the Lv10 hat or shoes
	assert_true(EquipmentDrops.pick_boss(_ids(), INFO, 200, [5, 14], RULES, _rng(1), WEAPONS) in [1002017, 1072006])
	# a band whose top third is empty: the highest reqLevel in the band wins (the Lv15 gloves, not the Lv10 items)
	assert_eq(EquipmentDrops.pick_boss([1002017, 1072006, 1082019], INFO, 200, [0, 21], RULES, _rng(1), WEAPONS), 1082019)
	# nothing in the band at all (Beginner 60..70): the nearest eligible item by level (the Lv0 all-job items)
	assert_true(EquipmentDrops.pick_boss(_ids(), INFO, 0, [60, 70], RULES, _rng(1), []) in [1002001, 1040002])
	assert_eq(EquipmentDrops.pick_boss([], INFO, 0, [60, 70], RULES, _rng(1), []), 0, "no list, no item")


# --- survivor data ---

@warning_ignore("integer_division")
func test_the_shipped_list_is_ids_only_and_every_item_is_a_wearable_slot() -> void:
	var data := DataRepo.load_all()
	var ed: Dictionary = data.equipment_drops
	var items: Array = ed.items
	assert_true(items.size() > 200, "the v83 list is a few hundred items")
	var seen := {}
	for raw: Variant in items:
		var id := int(raw)
		assert_false(seen.has(id), "%d once" % id)
		seen[id] = true
		var slot := Equipment.slot_of(id)
		assert_true(slot != "", "%d has an equip slot" % id)
		if slot == "weapon":
			assert_true(id / 10000 in [137, 138, 130, 131, 132, 133, 140, 141, 142, 143, 144, 145, 146, 147, 148, 149],
				"only Magician, Warrior, Bowman, Thief and Pirate weapon families, not %d" % id)
	for must: int in [1372005, 1372006, 1372004, 1372003, 1372000, 1372007, 1372014, 1372015, 1382000, 1382002,
			1382019, 1382001, 1382006, 1382007, 1002017, 1002102, 1002016, 1002064, 1002141, 1002151, 1002215,
			1002242, 1050008, 1050001, 1050026, 1050002, 1050035, 1050045, 1050053, 1050067, 1072006, 1072136,
			1082019, 1082098]:
		assert_true(seen.has(must), "the ticket's example %d is eligible" % must)
	assert_eq(int(ed.boss_top_parts), 3, "tier C: a boss drops from the top third of the band")
	assert_false(ed.has("below") or ed.has("above") or ed.has("falloff"), "no character-level window any more")
	assert_eq(int(ed.boss_drops), 2, "tier C: spec #237 replaces the boss potion bundle with a second item")
	assert_true(float(ed.chance) > 0.0 and float(ed.chance) < 0.02, "a small chance")


## Needs the real asset cache (SKIPs without it, which proves nothing).
func test_every_listed_item_has_cache_info_and_an_icon_and_every_band_has_drops() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.get_default()
	var ed: Dictionary = DataRepo.load_all().equipment_drops
	var infos := {}
	for raw: Variant in ed.items:
		var id := int(raw)
		var img: WzImg = lib.img(AvatarRenderer.part_img_path(id))
		if img == null or not img.root.get("info") is Dictionary:
			fail("no cache img for %d" % id)
			continue
		var info: Dictionary = img.root.info
		infos[id] = info
		assert_true(int(info.get("reqLevel", -1)) >= 0 and int(info.reqLevel) <= 120, "%d reqLevel 0..120 (70 before the late bands, #474)" % id)
		assert_true(int(info.get("reqJob", -1)) == 0 or int(info.reqJob) & 31 != 0,
			"%d is all-job, Magician, Warrior, Bowman, Thief or Pirate" % id)
		assert_eq(int(info.get("cash", 0)), 0, "%d is not a cash item" % id)
		assert_true(lib.frame(AvatarRenderer.part_img_path(id) + "/info/iconRaw") != null, "%d has iconRaw" % id)
	var rng := _rng(8)
	var stages: Dictionary = DataRepo.load_all().stages
	for tier in stages.progression.size():
		var band := EquipmentDrops.band_of(stages.stages[stages.progression[tier]])
		# The late bands are sparse in v83: the [80, 90] band holds 10 items for a Magician, 2 of them weapons (#470), so
		# from band 80 the floor is 5 (the per-family coverage is test_late_equipment_bands').
		var floor_count := 20 if float(band[0]) < 80.0 else 5
		assert_true(EquipmentDrops.eligible(ed.items, infos, 212, band, WEAPONS).size() > floor_count, "tier %d has drops" % (tier + 1))
		var floor_req := EquipmentDrops.boss_floor(band, ed)
		for i in 30:
			var boss := EquipmentDrops.pick_boss(ed.items, infos, 212, band, ed, rng, WEAPONS)
			assert_true(boss > 0, "a boss drop exists in tier %d" % (tier + 1))
			assert_true(int(infos[boss].reqLevel) >= floor_req and int(infos[boss].reqLevel) <= int(band[1]),
				"and comes from the top third (%d..%d): %d is Lv%d" % [floor_req, band[1], boss, infos[boss].reqLevel])
	assert_eq(lib.missing.size(), 0, "%s" % [lib.missing])


# --- PickupSystem EQUIP kind ---

func _floor() -> FootholdMap:
	return FootholdMap.from_segments(WF.tiers_segments())


func _wand() -> Dictionary:
	return {"id": 1372005, "stats": {"incPAD": 15, "incMAD": 23}, "slots": 7, "scrolls": 0}


func _count(events: Array, type: String) -> int:
	return events.filter(func(e: Dictionary) -> bool: return e.type == type).size()


func test_an_equipment_pickup_carries_its_instance_is_magnetised_and_collected() -> void:
	var pk := PickupSystem.new(8, {"spread": 0.0})
	var fhm := _floor()
	var ev: Array = []
	var i := pk.spawn_equipment(Vector2(500, 0), _wand())
	assert_eq(pk.kind[i], PickupSystem.EQUIP)
	assert_eq(PickupSystem.EQUIP, 4, "pickup kind 4 (decisions.md)")
	assert_eq(pk.item_id[i], 1372005, "drawn with the item's own icon")
	assert_eq(pk.exp_count(), 0, "equipment is not an EXP drop")
	assert_eq(pk.equip_instance[i], _wand())
	var got: Array = []
	for t in 30:
		pk.step(DT, Vector2(2000, 0), 90.0, fhm, ev, 5)
	for t in 120:
		pk.step(DT, Vector2(570, 0), 90.0, fhm, ev, 5)
		got.append_array(pk.collected_equipment)
	assert_eq(got, [_wand()], "collected exactly once, instance intact")
	assert_eq(pk.active_count(), 0)
	assert_eq(ev.size(), 1)
	if ev.size() == 1:
		assert_eq(ev[0].type, "pickup_collected")
		assert_eq(ev[0].kind, "equip")
		assert_eq(ev[0].item_id, 1372005)
		assert_eq(ev[0].exp, 0)


func test_equipment_never_expires_merges_or_counts_toward_the_exp_cap() -> void:
	var pk := PickupSystem.new(8, {"spread": 0.0, "lifetime": 1.0, "fade": 0.5, "max_active": 1})
	var fhm := _floor()
	var ev: Array = []
	var e := pk.spawn_equipment(Vector2(500, 0), _wand())
	pk.spawn(Vector2(100, 0), 5, 4000019, Vector2(2000, 0))
	pk.spawn(Vector2(120, 0), 6, 4000019, Vector2(2000, 0))
	assert_eq(pk.active[e], 1, "not the absorbed drop")
	for t in 600:
		pk.step(DT, Vector2(2000, 0), 90.0, fhm, ev, 0)
	assert_eq(pk.active[e], 1, "10 s past the lifetime and still there")
	assert_eq(pk.alpha(e), 1.0)


func test_with_no_room_the_drop_stays_on_the_ground_and_says_so_once() -> void:
	var pk := PickupSystem.new(8, {"spread": 0.0})
	var fhm := _floor()
	var ev: Array = []
	var i := pk.spawn_equipment(Vector2(500, 0), _wand())
	for t in 60:
		pk.step(DT, Vector2(2000, 0), 90.0, fhm, ev, 0)
	var ground := Vector2(pk.x[i], pk.y[i])
	for t in 240:
		pk.step(DT, ground, 90.0, fhm, ev, 0)
	assert_eq(pk.active[i], 1, "still on the ground, not collected")
	assert_eq(pk.state[i], PickupSystem.REST, "lying, not flying at the player")
	assert_near(pk.x[i], ground.x, 0.001)
	assert_near(pk.y[i], ground.y, 0.001)
	var blocked := ev.filter(func(e: Dictionary) -> bool: return e.type == "pickup_blocked")
	assert_eq(blocked.size(), 1, "one inventory-full notice while the player stands there")
	if blocked.size() == 1:
		assert_eq(blocked[0].reason, "inventory_full")
		assert_eq(blocked[0].item_id, 1372005)
	assert_eq(_count(ev, "pickup_collected"), 0)
	# walking away and back says it again
	for t in 5:
		pk.step(DT, Vector2(2000, 0), 90.0, fhm, ev, 0)
	for t in 5:
		pk.step(DT, ground, 90.0, fhm, ev, 0)
	assert_eq(_count(ev, "pickup_blocked"), 2)


func test_the_drop_is_collected_once_a_slot_is_free() -> void:
	var pk := PickupSystem.new(8, {"spread": 0.0})
	var fhm := _floor()
	var ev: Array = []
	var i := pk.spawn_equipment(Vector2(500, 0), _wand())
	for t in 60:
		pk.step(DT, Vector2(2000, 0), 90.0, fhm, ev, 0)
	var ground := Vector2(pk.x[i], pk.y[i])
	for t in 60:
		pk.step(DT, ground, 90.0, fhm, ev, 0)
	assert_eq(pk.active[i], 1)
	var got: Array = []
	for t in 120:
		pk.step(DT, ground, 90.0, fhm, ev, 1)
		got.append_array(pk.collected_equipment)
	assert_eq(got, [_wand()], "picked up as soon as there is room")
	assert_eq(pk.active_count(), 0)


func test_the_room_counts_down_within_a_step_and_a_flying_drop_falls_back_when_it_fills() -> void:
	var pk := PickupSystem.new(8, {"spread": 0.0})
	var fhm := _floor()
	var ev: Array = []
	pk.spawn_equipment(Vector2(560, 0), _wand())
	pk.spawn_equipment(Vector2(562, 0), _wand())
	var room := 1
	var got := 0
	for t in 240:
		pk.step(DT, Vector2(570, 0), 90.0, fhm, ev, room)
		got += pk.collected_equipment.size()
		room -= pk.collected_equipment.size()
	assert_eq(got, 1, "one slot, one item")
	assert_eq(pk.active_count(), 1, "the second item is still on the ground")
	assert_true(_count(ev, "pickup_blocked") >= 1, "and the player was told")


# --- HUD notices ---

func test_the_hud_shows_the_item_and_inventory_full_notices() -> void:
	var hud := Hud.new()
	hud.show_item_gain("Wooden Wand")
	hud.show_item_gain("")
	hud.show_inventory_full()
	var texts := hud.messages().map(func(m: Dictionary) -> String: return m.text)
	assert_eq(texts, ["You have gained an item (Wooden Wand)", "You have gained an item", "You can't get anymore items."])
	hud.free()


# --- RunWorld: kills and bosses drop equipment, the magnet collects it into the Equip tab ---

func _fit(setup: Dictionary) -> Dictionary:
	for id: int in INFO:
		var merged: Dictionary = setup.equipment_info.get(id, {}).duplicate()
		merged.merge(INFO[id], true)
		setup.equipment_info[id] = merged
	return setup


func _world(chance: float, job: int, p_seed: int = 31) -> RunWorld:
	var data := RF.quiet_data()
	data.equipment_drops.items = INFO.keys()
	data.equipment_drops.chance = chance
	var setup := _fit(RF.setup("quiet", p_seed, data))
	setup["job"] = job # no start skills; 0 is a (test-only) Beginner
	var w := RunWorld.new(setup)
	RF.place_player(w, 400)
	w.god = true
	if job != 0:
		RF.as_job(w, job) # the weapon the removed advancement granted (the Magician's Wooden Wand)
	return w


func _kill_at(w: RunWorld, mob_id: int, x: float) -> void:
	var slot := RF.put_mob(w, mob_id, x)
	w.hit_mob(slot, {"damage_min": 1000000.0, "damage_max": 1000000.0, "magic": false, "crit": 0.0,
		"crit_mult": 1.5, "skill": "three_snails"}, -1)


func _equip_spawns(events: Array) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return e.type == "pickup_spawned" and e.kind == "equip")


func _equip_drops(w: RunWorld) -> Array:
	var out := []
	for i in w.pickups.capacity():
		if w.pickups.active[i] != 0 and w.pickups.kind[i] == PickupSystem.EQUIP:
			out.append(w.pickups.equip_instance[i])
	return out


func test_kills_drop_only_what_the_job_can_wear_inside_the_tier_band() -> void:
	var beginner := _world(1.0, 0)
	beginner.drain_events()
	for i in 80:
		_kill_at(beginner, 100100, 405)
	var ids := {}
	for e: Dictionary in _equip_spawns(beginner.drain_events()):
		ids[int(e.item_id)] = true
	assert_eq(ids.keys().size(), 2, "a Beginner: the two all-job armour items (no weapon family, no wand)")
	for id: int in ids:
		assert_true(id in [1002001, 1040002], "%d is an all-job item in 0..30" % id)
	var magician := _world(1.0, 212)
	magician.drain_events()
	for i in 120:
		_kill_at(magician, 100100, 405)
	var m_ids := {}
	for e: Dictionary in _equip_spawns(magician.drain_events()):
		m_ids[int(e.item_id)] = true
	for id: int in m_ids:
		assert_true(id in [1002001, 1040002, 1002017, 1072006, 1082019, 1050001, 1372005, 1372004],
			"%d is a Magician or all-job item of reqLevel 0..30 (not the Lv38 wand or Lv40 staff)" % id)
	assert_true(m_ids.has(1002017) and m_ids.has(1082019) and m_ids.has(1372005), "Magician-only items and wands drop at Lv1")


func test_drops_carry_rolled_stats_and_upgrade_slots_equal_tuc() -> void:
	var w := _world(1.0, 212)
	for i in 60:
		_kill_at(w, 100100, 405)
	var drops := _equip_drops(w)
	assert_eq(drops.size(), 60)
	for d: Dictionary in drops:
		var info: Dictionary = INFO[int(d.id)]
		assert_eq(int(d.slots), int(info.tuc), "slots equal tuc")
		assert_eq(int(d.scrolls), 0)
		for key: String in d.stats:
			var base := int(info.get(key, 0))
			assert_between(float(d.stats[key]), float(maxi(0, base - 5)), float(base + 5), "%s of %d" % [key, int(d.id)])
	var mads := {}
	for d: Dictionary in drops:
		if int(d.id) == 1372005 and d.stats.has("incMAD"):
			mads[int(d.stats.incMAD)] = true
	assert_true(mads.size() > 1, "the same wand rolls different M.ATT")


func test_chance_zero_drops_no_ordinary_equipment() -> void:
	var w := _world(0.0, 212)
	w.drain_events()
	for i in 40:
		_kill_at(w, 100100, 405)
	assert_eq(_equip_spawns(w.drain_events()).size(), 0)


func test_the_configured_chance_is_the_drop_rate() -> void:
	var w := _world(0.1, 212, 5)
	w.drain_events()
	var drops := 0
	for i in 1000:
		_kill_at(w, 100100, 405)
		drops += _equip_spawns(w.drain_events()).size()
		for p in w.pickups.capacity():
			w.pickups.despawn(p)
	# Binomial(1000, 0.1): mean 100, sd 9.5; within four sd.
	assert_between(float(drops), 62.0, 138.0, "about 10% of kills drop equipment")
	assert_eq(w.equips_dropped, drops)


func _boss_world(chance: float, p_seed: int = 20) -> RunWorld:
	var data := RF.quiet_data()
	data.equipment_drops.items = INFO.keys()
	data.equipment_drops.chance = chance
	data.jobs_survivor.jobs["212"]["starting_skill"] = ""; data.jobs_survivor.jobs["212"]["mobility_skill"] = ""
	RF.set_bosses(data.stages.stages.quiet, [{"time": 0.1, "mob_id": 2220000, "hp_mult": 1.0,
		"rewards": {"exp_mult": 5, "exp_drops": 2, "spread": 100, "potions": {"hp": 1, "mp": 1}, "bonus_choices": 1}}])
	var w := RunWorld.new(_fit(RF.setup("quiet", p_seed, data)))
	RF.place_player(w, 400)
	w.god = true
	RF.change_job_bare(w, 212)
	for i in 6:
		w.step(DT, MoveInput.new())
	w.drain_events()
	return w


func _kill_boss(w: RunWorld) -> void:
	w.hit_mob(int(w.bosses.records[0].slot), {"damage_min": 1000000.0, "damage_max": 1000000.0,
		"magic": false, "crit": 0.0, "crit_mult": 1.5, "skill": "three_snails"}, -1)


func test_every_boss_kill_drops_exactly_two_items_from_the_top_third() -> void:
	for p_seed in [20, 21, 22, 23, 24, 25]:
		var w := _boss_world(0.0, p_seed)  # chance 0: ordinary kills drop nothing, the boss still does
		_kill_boss(w)
		var spawned := _equip_spawns(w.drain_events())
		assert_eq(spawned.size(), 2, "exactly two items (seed %d)" % p_seed)
		for drop: Dictionary in spawned:
			# tier 1 band 0..30, top third 20..30 -> the reqLevel 23 overall or Ice Wand
			assert_true(int(drop.item_id) in [1050001, 1372004], "from the top third, got %d" % drop.item_id)


func test_a_boss_drop_is_deterministic_per_seed() -> void:
	var a := _boss_world(0.0, 41)
	var b := _boss_world(0.0, 41)
	_kill_boss(a)
	_kill_boss(b)
	assert_eq(_equip_drops(a).size(), 2)
	assert_eq(_equip_drops(a), _equip_drops(b), "same seed, same boss drop with the same stats")


func test_each_scheduled_boss_death_drops_two_equipment_items_and_no_potions() -> void:
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["212"]["starting_skill"] = ""; data.jobs_survivor.jobs["212"]["mobility_skill"] = ""
	data.balance.bosses.rewards.bonus_choices = 0
	data.equipment_drops.items = INFO.keys()
	data.equipment_drops.chance = 0.0
	var entries := []
	var ids := [2220000, 6130101, 9400205]
	for i in ids.size():
		entries.append({"time": float(i + 1), "mob_id": ids[i]})
	RF.set_bosses(data.stages.stages.quiet, entries)
	var w := RunWorld.new(_fit(RF.setup("quiet", 238, data)))
	w.god = true
	RF.place_player(w, 400)
	var killed := 0
	for tick in 240:
		RF.auto_choose(w)
		w.step(DT, MoveInput.new())
		var arrivals := w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "boss_spawned")
		for arrival: Dictionary in arrivals:
			w.hit_mob(int(arrival.mob), {"damage_min": 1000000.0, "damage_max": 1000000.0,
				"magic": false, "crit": 0.0, "crit_mult": 1.5, "skill": "three_snails"}, -1)
			var events := w.drain_events()
			assert_eq(_equip_spawns(events).size(), 2, "boss %d" % int(arrival.mob_id))
			assert_true(events.filter(func(e: Dictionary) -> bool:
				return e.type == "pickup_spawned" and e.kind == "potion").is_empty())
			killed += 1
	assert_eq(killed, 3, "all three scheduled bosses were killed")


func test_same_seed_same_drops_and_another_seed_differs() -> void:
	var runs := []
	for p_seed in [77, 77, 78]:
		var w := _world(0.3, 212, p_seed)
		for i in 100:
			_kill_at(w, 100100, 405)
		runs.append(_equip_drops(w))
	assert_true(runs[0].size() > 10)
	assert_eq(runs[0], runs[1], "the same seed gives the same drops, ids and stats")
	assert_ne(runs[0], runs[2], "another seed gives others")


func test_the_magnet_collects_a_drop_into_the_inventory_and_counts_it() -> void:
	var w := _world(1.0, 212)
	w.drain_events()
	_kill_at(w, 100100, 405)
	var dropped: Dictionary = _equip_drops(w)[0]
	var before: int = Equipment.held_ids(w.equipment).size()
	var changed := 0
	var blocked := 0
	for i in 180:
		RF.auto_choose(w)
		w.step(DT, MoveInput.new())
		for e: Dictionary in w.drain_events():
			if e.type == "equipment_changed" and e.action == "pickup":
				changed += 1
				assert_eq(int(e.item_id), int(dropped.id))
			elif e.type == "pickup_blocked":
				blocked += 1
	assert_eq(Equipment.held_ids(w.equipment).size(), before + 1)
	var held: Array = w.equipment.inventory + w.equipment.worn.values()
	assert_true(held.has(dropped), "the exact instance, stats included (worn at once when its slot is empty and the job fits, #222)")
	assert_eq([changed, blocked], [1, 0])
	assert_eq(w.equips_collected, 1)
	assert_eq(w.equips_dropped, 1)


func test_with_a_full_equip_tab_the_drop_stays_until_a_slot_is_freed() -> void:
	var w := _world(1.0, 212)
	var cap := w.inventory_slots()
	while w.equipment.inventory.size() < cap:
		w.equipment.inventory.append(Equipment.create(1002001, INFO[1002001]))
	w.drain_events()
	_kill_at(w, 100100, 405)
	assert_eq(_equip_drops(w).size(), 1)
	var blocked := 0
	for i in 240:
		RF.auto_choose(w)
		w.step(DT, MoveInput.new())
		for e: Dictionary in w.drain_events():
			if e.type == "pickup_blocked":
				blocked += 1
				assert_eq(e.reason, "inventory_full")
	assert_eq(w.equipment.inventory.size(), cap, "nothing was added")
	assert_eq(_equip_drops(w).size(), 1, "the item is still on the ground")
	assert_eq(blocked, 1, "told once while standing next to it")
	assert_eq(w.equips_collected, 0)
	var before_held := Equipment.held_ids(w.equipment).size()
	assert_eq(w.discard_item(0), "")
	for i in 120:
		RF.auto_choose(w)
		w.step(DT, MoveInput.new())
	assert_eq(Equipment.held_ids(w.equipment).size(), before_held,
		"one discarded, one picked up (worn at once when its slot is empty and the job fits)")
	assert_eq(_equip_drops(w).size(), 0, "off the ground")
	assert_eq(w.equips_collected, 1)
