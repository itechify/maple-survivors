extends TestCase
## Equipment drops (spec #33, #109): v83 random stats, the job and level filters, the boss "top of the window" rule,
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
const RULES := {"below": 10, "above": 5, "falloff": 0.25, "boss_top": 5}


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


# --- job and level filters ---

func test_a_beginner_only_gets_all_job_items_and_a_magician_both() -> void:
	var beginner := EquipmentDrops.eligible(_ids(), INFO, 0, 8, RULES)
	for id: int in beginner:
		assert_eq(int(INFO[id].reqJob), 0, "%d is for every job" % id)
	assert_true(1372005 in beginner and 1002001 in beginner and 1040002 in beginner)
	assert_false(1002017 in beginner, "a Magician hat never drops for a Beginner")
	var magician := EquipmentDrops.eligible(_ids(), INFO, 200, 12, RULES)
	assert_true(1002017 in magician and 1372005 in magician and 1072006 in magician, "Magician and all-job")
	for job in [210, 220, 230, 211, 232]:
		assert_true(1002017 in EquipmentDrops.eligible(_ids(), INFO, job, 12, RULES), "job %d wears Magician gear" % job)
	assert_false(1002017 in EquipmentDrops.eligible(_ids(), INFO, 100, 12, RULES), "a Warrior line is not playable and not eligible")


func test_the_level_window_is_ten_below_to_five_above() -> void:
	var at_30 := EquipmentDrops.eligible(_ids(), INFO, 200, 30, RULES)
	assert_eq(at_30, [1050001, 1372004], "reqLevel 20..35 for level 30: the overall (23) and the Ice Wand (23)")
	var edge_low := EquipmentDrops.eligible(_ids(), INFO, 200, 33, RULES)
	assert_true(1050001 in edge_low, "exactly 10 below (23) is inside")
	var edge_out := EquipmentDrops.eligible(_ids(), INFO, 200, 34, RULES)
	assert_false(1050001 in edge_out, "11 below is outside")
	var edge_high := EquipmentDrops.eligible(_ids(), INFO, 200, 35, RULES)
	assert_true(1372000 in edge_high, "exactly 3 above is inside")
	assert_true(1382019 in EquipmentDrops.eligible(_ids(), INFO, 200, 35, RULES), "exactly 5 above (40) is inside")
	assert_false(1382019 in EquipmentDrops.eligible(_ids(), INFO, 200, 34, RULES), "6 above is outside")


func test_items_missing_from_the_info_table_never_drop() -> void:
	assert_eq(EquipmentDrops.eligible([1372005, 9999999], {1372005: INFO[1372005]}, 0, 8, RULES), [1372005])


func test_nearer_items_are_likelier() -> void:
	var rng := _rng(5)
	var counts := {}
	for i in 4000:
		var id := EquipmentDrops.pick(_ids(), INFO, 200, 20, RULES, rng)
		counts[id] = int(counts.get(id, 0)) + 1
	# level 20: 1002017 (10, d=-10), 1072006 (10), 1082019 (15), 1050001 (23, d=+3), 1372005 (8, out), 1372004 (23)
	assert_true(counts[1050001] > counts[1002017], "+3 away beats -10 away")
	assert_true(counts[1082019] > counts[1072006], "-5 away beats -10 away")
	assert_false(counts.has(1372005), "level 8 is 12 below: outside the window")
	assert_false(counts.has(1372000), "level 38 is outside")


func test_pick_returns_nothing_for_an_empty_window_and_is_deterministic() -> void:
	assert_eq(EquipmentDrops.pick(_ids(), INFO, 0, 60, RULES, _rng(1)), 0, "nothing for a level-60 Beginner")
	var a: Array = []
	var b: Array = []
	var ra := _rng(9)
	var rb := _rng(9)
	for i in 50:
		a.append(EquipmentDrops.pick(_ids(), INFO, 200, 25, RULES, ra))
		b.append(EquipmentDrops.pick(_ids(), INFO, 200, 25, RULES, rb))
	assert_eq(a, b)


# --- bosses: the top of the window ---

func test_a_boss_item_comes_from_the_top_of_the_window() -> void:
	var rng := _rng(6)
	var seen := {}
	for i in 300:
		seen[EquipmentDrops.pick_boss(_ids(), INFO, 200, 20, RULES, rng)] = true
	# level 20: window 10..25, top = reqLevel 20..25: only the reqLevel 23 items (overall, Ice Wand).
	var got := seen.keys()
	got.sort()
	assert_eq(got, [1050001, 1372004])


func test_a_boss_falls_back_to_the_highest_item_in_the_window_then_the_nearest_item() -> void:
	# level 12, top band 12..17: only Gloves (15) of the window 2..17 sit there? hats at 10 are below: gloves only.
	assert_eq(EquipmentDrops.pick_boss(_ids(), INFO, 200, 12, RULES, _rng(1)), 1082019)
	# a custom band with nothing in it: the highest reqLevel in the window wins (15 gloves, not the level-10 items)
	var narrow := {"below": 10, "above": 5, "falloff": 0.25, "boss_top": 0}
	assert_eq(EquipmentDrops.pick_boss(_ids(), INFO, 200, 12, narrow, _rng(1)), 1082019)
	# nothing in the window at all (Beginner Lv 60): the nearest eligible item by level (Wooden Wand, level 8)
	assert_eq(EquipmentDrops.pick_boss(_ids(), INFO, 0, 60, RULES, _rng(1)), 1372005)
	assert_eq(EquipmentDrops.pick_boss([], INFO, 0, 60, RULES, _rng(1)), 0, "no list, no item")


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
			assert_true(id / 10000 in [137, 138], "only wands and staves, not %d" % id)
	for must: int in [1372005, 1372006, 1372004, 1372003, 1372000, 1372007, 1372014, 1372015, 1382000, 1382002,
			1382019, 1382001, 1382006, 1382007, 1002017, 1002102, 1002016, 1002064, 1002141, 1002151, 1002215,
			1002242, 1050008, 1050001, 1050026, 1050002, 1050035, 1050045, 1050053, 1050067, 1072006, 1072136,
			1082019, 1082098]:
		assert_true(seen.has(must), "the ticket's example %d is eligible" % must)
	assert_eq(int(ed.below), 10)
	assert_eq(int(ed.above), 5)
	assert_eq(int(ed.boss_drops), 1)
	assert_true(float(ed.chance) > 0.0 and float(ed.chance) < 0.02, "a small chance")


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


# --- RunWorld: kills and bosses drop equipment, the magnet collects it into the Equip tab ---

func _fit(setup: Dictionary) -> Dictionary:
	for id: int in INFO:
		var merged: Dictionary = setup.equipment_info.get(id, {}).duplicate()
		merged.merge(INFO[id], true)
		setup.equipment_info[id] = merged
	return setup


func _world(chance: float, level: int, job: int, p_seed: int = 31) -> RunWorld:
	var data := RF.quiet_data()
	data.equipment_drops.items = INFO.keys()
	data.equipment_drops.chance = chance
	data.balance.player.skills = []
	var w := RunWorld.new(_fit(RF.setup("quiet", p_seed, data)))
	RF.place_player(w, 400)
	w.god = true
	w.progression.level = level
	if job != 0:
		RF.change_job_bare(w, job)
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


func test_kills_drop_only_what_the_current_job_can_wear_inside_the_level_window() -> void:
	var beginner := _world(1.0, 8, 0)
	beginner.drain_events()
	for i in 80:
		_kill_at(beginner, 100100, 405)
	var ids := {}
	for e: Dictionary in _equip_spawns(beginner.drain_events()):
		ids[int(e.item_id)] = true
	assert_eq(ids.keys().size(), 3, "level 8 Beginner: the wand (8) and the two level-0 items, all-job")
	for id: int in ids:
		assert_true(id in [1372005, 1002001, 1040002], "%d is an all-job item in 0..13" % id)
	var magician := _world(1.0, 12, 200)
	magician.drain_events()
	for i in 120:
		_kill_at(magician, 100100, 405)
	var m_ids := {}
	for e: Dictionary in _equip_spawns(magician.drain_events()):
		m_ids[int(e.item_id)] = true
	for id: int in m_ids:
		assert_true(id in [1002017, 1072006, 1082019, 1372005], "%d fits a level 12 Magician" % id)
	assert_true(m_ids.has(1002017) and m_ids.has(1082019), "Magician-only items drop for a Magician")


func test_drops_carry_rolled_stats_and_upgrade_slots_equal_tuc() -> void:
	var w := _world(1.0, 12, 200)
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
	var w := _world(0.0, 12, 200)
	w.drain_events()
	for i in 40:
		_kill_at(w, 100100, 405)
	assert_eq(_equip_spawns(w.drain_events()).size(), 0)


func test_the_configured_chance_is_the_drop_rate() -> void:
	var w := _world(0.1, 12, 200, 5)
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


func _boss_world(chance: float, level: int, p_seed: int = 20) -> RunWorld:
	var data := RF.quiet_data()
	data.equipment_drops.items = INFO.keys()
	data.equipment_drops.chance = chance
	data.balance.player.skills = []
	data.stages.stages.quiet.bosses = [{"time": 0.1, "mob_id": 2220000, "hp_mult": 1.0,
		"rewards": {"exp_mult": 5, "exp_drops": 2, "spread": 100, "potions": {"hp": 1, "mp": 1}, "bonus_choices": 1}}]
	var w := RunWorld.new(_fit(RF.setup("quiet", p_seed, data)))
	RF.place_player(w, 400)
	w.god = true
	w.progression.level = level
	RF.change_job_bare(w, 200)
	for i in 6:
		w.step(DT, MoveInput.new())
	w.drain_events()
	return w


func _kill_boss(w: RunWorld) -> void:
	w.hit_mob(int(w.bosses.records[0].slot), {"damage_min": 1000000.0, "damage_max": 1000000.0,
		"magic": false, "crit": 0.0, "crit_mult": 1.5, "skill": "three_snails"}, -1)


func test_every_boss_kill_drops_exactly_one_item_from_the_top_of_the_window() -> void:
	for p_seed in [20, 21, 22, 23, 24, 25]:
		var w := _boss_world(0.0, 20, p_seed)  # chance 0: ordinary kills drop nothing, the boss still does
		_kill_boss(w)
		var spawned := _equip_spawns(w.drain_events())
		assert_eq(spawned.size(), 1, "exactly one item (seed %d)" % p_seed)
		if spawned.size() == 1:
			# level 20: window 10..25, top 20..25 -> the reqLevel 23 overall or Ice Wand
			assert_true(int(spawned[0].item_id) in [1050001, 1372004], "from the top of the window, got %d" % spawned[0].item_id)


func test_a_boss_drop_is_deterministic_per_seed() -> void:
	var a := _boss_world(0.0, 20, 41)
	var b := _boss_world(0.0, 20, 41)
	_kill_boss(a)
	_kill_boss(b)
	assert_eq(_equip_drops(a).size(), 1)
	assert_eq(_equip_drops(a), _equip_drops(b), "same seed, same boss drop with the same stats")


func test_same_seed_same_drops_and_another_seed_differs() -> void:
	var runs := []
	for p_seed in [77, 77, 78]:
		var w := _world(0.3, 12, 200, p_seed)
		for i in 100:
			_kill_at(w, 100100, 405)
		runs.append(_equip_drops(w))
	assert_true(runs[0].size() > 10)
	assert_eq(runs[0], runs[1], "the same seed gives the same drops, ids and stats")
	assert_ne(runs[0], runs[2], "another seed gives others")


func test_the_magnet_collects_a_drop_into_the_inventory_and_counts_it() -> void:
	var w := _world(1.0, 12, 200)
	w.drain_events()
	_kill_at(w, 100100, 405)
	var dropped: Dictionary = _equip_drops(w)[0]
	var before: int = w.equipment.inventory.size()
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
	assert_eq(w.equipment.inventory.size(), before + 1)
	assert_eq(w.equipment.inventory[before], dropped, "the exact instance, stats included")
	assert_eq([changed, blocked], [1, 0])
	assert_eq(w.equips_collected, 1)
	assert_eq(w.equips_dropped, 1)


func test_with_a_full_equip_tab_the_drop_stays_until_a_slot_is_freed() -> void:
	var w := _world(1.0, 12, 200)
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
	assert_eq(w.discard_item(0), "")
	for i in 120:
		RF.auto_choose(w)
		w.step(DT, MoveInput.new())
	assert_eq(w.equipment.inventory.size(), cap, "the freed slot took the dropped item")
	assert_eq(_equip_drops(w).size(), 0, "off the ground")
	assert_eq(w.equips_collected, 1)
