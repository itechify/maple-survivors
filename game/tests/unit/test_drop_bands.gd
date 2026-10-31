extends TestCase
## Equipment drop bands and job weapon families (spec #282, #292, ADR 0006): drops no longer follow the character's
## level. A stage fixes a reqLevel band (its stages.json `drop_band`, per region since ADR 0007), a boss drops from the top third of it, and a
## weapon drops only when it belongs to one of the job's weapon families (survivor/jobs/<line>.json `weapon_families`).
## Item info is synthetic (shaped like Character.wz `info`); seeded RNG.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0

## Synthetic items: id -> info. Magician (reqJob 2) gear at several levels, wands/staves, a Warrior sword and an all-job hat.
const INFO := {
	1002001: {"reqLevel": 0, "reqJob": 0, "incPDD": 4, "tuc": 7}, # hat, all jobs, Lv0
	1040002: {"reqLevel": 5, "reqJob": 0, "incPDD": 3, "tuc": 7}, # top, all jobs, Lv5
	1002017: {"reqLevel": 10, "reqJob": 2, "incPDD": 5, "tuc": 7}, # Magician hat, Lv10
	1072006: {"reqLevel": 19, "reqJob": 2, "incPDD": 3, "tuc": 5}, # Magician shoes, Lv19 (just below the top third)
	1050001: {"reqLevel": 20, "reqJob": 2, "incPDD": 20, "tuc": 10}, # Magician overall, Lv20 (top third starts)
	1372004: {"reqLevel": 25, "reqJob": 2, "incMAD": 38, "tuc": 7}, # wand, Lv25
	1382012: {"reqLevel": 30, "reqJob": 2, "incMAD": 45, "tuc": 7}, # staff, Lv30 (top of the first band)
	1082019: {"reqLevel": 30, "reqJob": 2, "incPDD": 4, "tuc": 5}, # Magician gloves, Lv30 (in both bands)
	1372000: {"reqLevel": 38, "reqJob": 2, "incMAD": 53, "tuc": 7}, # wand, Lv38
	1382019: {"reqLevel": 50, "reqJob": 2, "incMAD": 55, "tuc": 7}, # staff, Lv50 (top third of the second band)
	1382039: {"reqLevel": 60, "reqJob": 2, "incMAD": 70, "tuc": 7}, # staff, Lv60
	1002579: {"reqLevel": 100, "reqJob": 2, "incMDD": 30, "tuc": 5}, # Magician hat, Lv100: outside both bands
	1302008: {"reqLevel": 25, "reqJob": 1, "incPAD": 47, "tuc": 7}, # Warrior sword
	1332000: {"reqLevel": 25, "reqJob": 8, "incPAD": 30, "tuc": 7}, # Thief dagger
}
const RULES := {"chance": 1.0, "boss_drops": 2, "boss_top_parts": 3}
const TIER1 := [0, 30]
const TIER2 := [30, 60]
const MAGE := ["wand", "staff"]


func _rng(p_seed: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = p_seed
	return rng


func _levels(ids: Array) -> Array:
	var out := []
	for id: int in ids:
		out.append(int(INFO[id].reqLevel))
	out.sort()
	return out


func _hundred(count: int, tier_band: Array, boss: bool, p_seed: int) -> Array:
	var rng := _rng(p_seed)
	var out := []
	for i in count:
		out.append(EquipmentDrops.pick_boss(INFO.keys(), INFO, 212, tier_band, RULES, rng, MAGE) if boss
			else EquipmentDrops.pick(INFO.keys(), INFO, 212, tier_band, RULES, rng, MAGE))
	return out


# --- shipped data ---

func test_the_shipped_regions_carry_their_drop_bands() -> void:
	var stages: Dictionary = DataRepo.load_all().stages
	# Pins only for the five original regions; later regions are held to the rules below (and their own region test pins them).
	var expected := {"henesys": [0, 15], "ellinia": [10, 20], "perion": [15, 25], "kerning": [20, 30], "sleepywood": [30, 40]}
	assert_eq(stages.progression.slice(0, expected.size()), expected.keys(), "the original five come first, in this order")
	for key: String in expected:
		assert_eq(EquipmentDrops.band_of(stages.stages[key]), expected[key], key)
	var last := [-1, -1]
	for key: String in stages.progression:
		var band := EquipmentDrops.band_of(stages.stages[key])
		assert_eq(band.size(), 2, "%s carries a drop_band" % key)
		assert_true(band[0] <= band[1], "%s: min <= max" % key)
		assert_true(band[0] >= last[0] and band[1] >= last[1], "%s: the bands are monotone along the progression" % key)
		last = band


func test_a_stage_without_a_band_has_no_limit() -> void:
	assert_eq(EquipmentDrops.band_of({"drop_band": [30, 60]}), [30, 60])
	var open := EquipmentDrops.band_of({})
	assert_eq(open[0], 0)
	assert_true(int(open[1]) >= 70, "the whole listed range")
	assert_eq(EquipmentDrops.band_of({"drop_band": [5]}), open, "a malformed band is no band")


func test_jobs_list_their_weapon_families() -> void:
	var jobs := JobTree.from_data(DataRepo.load_all().jobs, DataRepo.load_all().jobs_survivor)
	assert_eq(jobs.weapon_families(212), ["wand", "staff"])
	assert_eq(jobs.weapon_families(100), [], "a job without a list has no weapon family")


# --- the pure picks ---

func test_ordinary_drops_stay_inside_the_band() -> void:
	for band: Array in [TIER1, TIER2]:
		for id: int in _hundred(300, band, false, 7):
			var req := int(INFO[id].reqLevel)
			assert_true(req >= band[0] and req <= band[1], "item %d (reqLevel %d) in band %s" % [id, req, band])


func test_a_band_reaches_every_eligible_item_and_nothing_else() -> void:
	var seen := {}
	for id: int in _hundred(600, TIER1, false, 11):
		seen[id] = true
	var ids := seen.keys()
	ids.sort()
	assert_eq(ids, [1002001, 1002017, 1040002, 1050001, 1072006, 1082019, 1372004, 1382012],
		"all-job and Magician items of Lv0-30, incl. both band edges; no Warrior/Thief item, none of Lv38+")


func test_boss_drops_come_from_the_top_third_of_the_band() -> void:
	assert_eq(EquipmentDrops.boss_floor(TIER1, RULES), 20)
	assert_eq(EquipmentDrops.boss_floor(TIER2, RULES), 50)
	for id: int in _hundred(300, TIER1, true, 5):
		assert_true(int(INFO[id].reqLevel) >= 20 and int(INFO[id].reqLevel) <= 30, "tier 1 boss item %d" % id)
	for id: int in _hundred(300, TIER2, true, 5):
		assert_true(int(INFO[id].reqLevel) >= 50 and int(INFO[id].reqLevel) <= 60, "tier 2 boss item %d" % id)


func test_a_boss_falls_back_to_the_highest_item_in_the_band_then_the_nearest_to_it() -> void:
	var sparse := {1002017: INFO[1002017], 1072006: INFO[1072006]} # Lv10, Lv19: nothing in 20..30
	assert_eq(EquipmentDrops.pick_boss(sparse.keys(), sparse, 212, TIER1, RULES, _rng(1), MAGE), 1072006,
		"the highest reqLevel inside the band")
	var far := {1002579: INFO[1002579], 1002017: INFO[1002017]} # Lv100 and Lv10: neither is in 30..60
	assert_eq(EquipmentDrops.pick_boss(far.keys(), far, 212, TIER2, RULES, _rng(1), MAGE), 1002017,
		"an empty band takes the admitted item nearest to it (Lv10 is 20 away, Lv100 is 40)")


func test_the_job_class_still_filters() -> void:
	var ids: Array = EquipmentDrops.eligible(INFO.keys(), INFO, 212, [0, 100], MAGE)
	assert_false(1302008 in ids, "a Warrior sword never drops for a Magician")
	assert_false(1332000 in ids, "a Thief dagger never drops for a Magician")
	assert_true(1002001 in ids and 1002579 in ids)


func test_weapons_follow_the_job_families_not_a_held_weapon() -> void:
	var wands: Array = EquipmentDrops.eligible(INFO.keys(), INFO, 212, TIER1, ["wand"])
	assert_true(1372004 in wands)
	assert_false(1382012 in wands, "a staff is not in a wand-only list")
	var none: Array = EquipmentDrops.eligible(INFO.keys(), INFO, 212, TIER1, [])
	assert_false(1372004 in none or 1382012 in none, "a job with no family gets no weapon")
	assert_true(1050001 in none, "armour does not depend on the families")
	var swords: Array = EquipmentDrops.eligible(INFO.keys(), INFO, 100, TIER1, ["sword"])
	assert_eq(swords, [1002001, 1040002, 1302008], "another job takes its own families (reqJob 1)")


func test_picks_are_deterministic_per_seed() -> void:
	assert_eq(_hundred(40, TIER1, false, 99), _hundred(40, TIER1, false, 99))
	assert_ne(_hundred(40, TIER1, false, 99), _hundred(40, TIER1, false, 100))


# --- RunWorld ---

func _fit(setup: Dictionary) -> Dictionary:
	for id: int in INFO:
		var merged: Dictionary = setup.equipment_info.get(id, {}).duplicate()
		merged.merge(INFO[id], true)
		setup.equipment_info[id] = merged
	return setup


## A quiet world on a stage with drop band `band`, Lv1 (a round always starts there), every kill dropping gear.
func _world(band: Array, p_seed := 31, chance := 1.0) -> RunWorld:
	var data := RF.quiet_data()
	data.equipment_drops.items = INFO.keys()
	data.equipment_drops.chance = chance
	data.stages.stages.quiet["drop_band"] = band
	data.jobs_survivor.jobs["212"]["starting_skill"] = ""; data.jobs_survivor.jobs["212"]["mobility_skill"] = ""
	RF.set_bosses(data.stages.stages.quiet, [{"time": 0.1, "mob_id": 2220000, "hp_mult": 1.0,
		"rewards": {"exp_mult": 1, "spread": 100, "bonus_choices": 0}}])
	var w := RunWorld.new(_fit(RF.setup("quiet", p_seed, data)))
	RF.place_player(w, 400)
	w.god = true
	for i in 6:
		w.step(DT, MoveInput.new())
	w.drain_events()
	return w


func _drops(w: RunWorld) -> Array:
	return w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "pickup_spawned" and e.kind == "equip") \
		.map(func(e: Dictionary) -> int: return int(e.item_id))


func test_a_low_band_drops_inside_0_to_30_at_level_one() -> void:
	var w := _world(TIER1)
	assert_eq(w.progression.level, 1)
	var got := []
	for i in 120:
		w.drop_mob_loot(RF.put_mob(w, 100100, 400.0))
		got.append_array(_drops(w))
	assert_true(got.size() > 60, "chance 1.0 drops on nearly every kill, got %d" % got.size())
	for id: int in got:
		assert_true(int(INFO[id].reqLevel) <= 30, "low-band drop %d is reqLevel %d" % [id, INFO[id].reqLevel])
		assert_true(INFO[id].reqJob in [0, 2], "only the Magician's class")
	assert_true(1372004 in got or 1382012 in got, "the job's wands and staves drop at Lv1")


func test_a_high_band_drops_inside_30_to_60() -> void:
	var w := _world(TIER2)
	var got := []
	for i in 120:
		w.drop_mob_loot(RF.put_mob(w, 100100, 400.0))
		got.append_array(_drops(w))
	assert_true(got.size() > 20)
	for id: int in got:
		assert_true(int(INFO[id].reqLevel) >= 30 and int(INFO[id].reqLevel) <= 60, "high-band drop %d" % id)


func test_a_boss_kill_drops_two_items_from_the_top_third() -> void:
	for band: Array in [TIER1, TIER2]:
		for p_seed in [20, 21, 22, 23]:
			var w := _world(band, p_seed, 0.0)
			w.hit_mob(int(w.bosses.records[0].slot), {"damage_min": 1000000.0, "damage_max": 1000000.0,
				"magic": false, "crit": 0.0, "crit_mult": 1.5, "skill": "three_snails"}, -1)
			var got := _drops(w)
			assert_eq(got.size(), 2, "band %s seed %d: exactly two boss items" % [band, p_seed])
			for id: int in got:
				var floor_req := 20 if band == TIER1 else 50
				assert_true(int(INFO[id].reqLevel) >= floor_req, "item %d reqLevel %d" % [id, INFO[id].reqLevel])


func test_the_level_no_longer_changes_the_drops() -> void:
	var low := _world(TIER1, 31)
	var high := _world(TIER1, 31)
	high.progression.level = 70
	var a := []
	var b := []
	for i in 40:
		low.drop_mob_loot(RF.put_mob(low, 100100, 400.0))
		high.drop_mob_loot(RF.put_mob(high, 100100, 400.0))
		a.append_array(_drops(low))
		b.append_array(_drops(high))
	assert_eq(a, b, "same seed, same drops at Lv1 and Lv70")


func test_the_held_weapon_no_longer_changes_the_drops() -> void:
	var bare := _world(TIER1, 31)
	var armed := _world(TIER1, 31)
	bare.equipment.worn.erase("weapon")
	var a := []
	var b := []
	for i in 40:
		bare.drop_mob_loot(RF.put_mob(bare, 100100, 400.0))
		armed.drop_mob_loot(RF.put_mob(armed, 100100, 400.0))
		a.append_array(_drops(bare))
		b.append_array(_drops(armed))
	assert_eq(a, b, "wands and staves drop for a bare-handed Magician too")
	assert_true(a.any(func(id: int) -> bool: return id in [1372004, 1382012]))
