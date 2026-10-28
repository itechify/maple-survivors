extends TestCase
## Hero's data seam (spec #296, ticket H2 #298): the `hero` data line loads and is discovered after the fixed Adventurer lines, the job entry
## `survivor/jobs/hero.json` (112, playable alongside 212), its AP row, the `default_job` pin that keeps tools, tests and
## oracles on 212 whatever is playable, and the weapon families of its equipment drops (sword and axe, one- and two-handed;
## armour and shields by the Warrior class bit). Seeded RNG; item info is synthetic unless a test says "real cache".

const RF := preload("res://tests/fixtures/run_fixtures.gd")

## Synthetic items: id -> info. Warrior-bit weapons of every family, a Warrior shield, all-job armour, other jobs' gear.
const INFO := {
	1002001: {"reqLevel": 0, "reqJob": 0, "incPDD": 4, "tuc": 7}, # hat, all jobs
	1040002: {"reqLevel": 30, "reqJob": 0, "incPDD": 3, "tuc": 7}, # top, all jobs
	1302008: {"reqLevel": 30, "reqJob": 1, "incPAD": 47, "tuc": 7}, # one-handed sword
	1402002: {"reqLevel": 30, "reqJob": 1, "incPAD": 50, "tuc": 7}, # two-handed sword
	1312005: {"reqLevel": 30, "reqJob": 1, "incPAD": 47, "tuc": 7}, # one-handed axe
	1412006: {"reqLevel": 30, "reqJob": 1, "incPAD": 52, "tuc": 7}, # two-handed axe
	1322014: {"reqLevel": 30, "reqJob": 1, "incPAD": 49, "tuc": 7}, # one-handed blunt weapon
	1422001: {"reqLevel": 30, "reqJob": 1, "incPAD": 52, "tuc": 7}, # two-handed blunt weapon
	1432002: {"reqLevel": 30, "reqJob": 1, "incPAD": 52, "tuc": 7}, # spear
	1442001: {"reqLevel": 30, "reqJob": 1, "incPAD": 52, "tuc": 7}, # polearm
	1092002: {"reqLevel": 30, "reqJob": 1, "incPDD": 40, "tuc": 7}, # Warrior shield
	1372004: {"reqLevel": 30, "reqJob": 2, "incPAD": 24, "incMAD": 38, "tuc": 7}, # wand
	1050001: {"reqLevel": 30, "reqJob": 2, "incPDD": 20, "incMDD": 12, "tuc": 10}, # Magician overall
}
const RULES := {"boss_top_parts": 3}
const BAND := [0, 70]
const HERO_WEAPONS := [1302008, 1402002, 1312005, 1412006]
const NOT_HERO_WEAPONS := [1322014, 1422001, 1432002, 1442001]


func _data() -> Dictionary:
	return DataRepo.load_all()


func _jobs(data: Dictionary) -> JobTree:
	return JobTree.from_data(data.jobs, data.jobs_survivor)


func _ids() -> Array:
	var ids := INFO.keys()
	ids.sort()
	return ids


func _rng(p_seed: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = p_seed
	return rng


# --- the line ---------------------------------------------------------------------------------------------------------

func test_hero_line_is_discovered_without_a_shared_registration() -> void:
	assert_true("hero" in DataRepo.lines())
	assert_eq(DataRepo.fragment_path("jobs_survivor", "hero", "res://data"), "res://data/survivor/jobs/hero.json")
	assert_eq(DataRepo.fragment_path("skills", "hero", "res://data"), "res://data/survivor/skills/hero.json")


func test_the_hero_line_loads_without_errors_and_adds_its_job_and_core_skills() -> void:
	var errors := PackedStringArray()
	var d := DataRepo.load_all(DataRepo.DATA_ROOT, errors)
	assert_true(errors.is_empty(), "%s" % [errors])
	assert_true(FileAccess.file_exists(DataRepo.fragment_path("jobs_survivor", "hero")))
	assert_true(FileAccess.file_exists(DataRepo.fragment_path("skills", "hero")))
	assert_true(d.jobs_survivor.jobs.has("112"), "jobs/hero.json is merged into the survivor job data")
	# Class lines merge in sorted discovery order (ARCHITECTURE 4.4.4): bowmaster (B2 #334) sorts before hero.
	assert_eq(d.jobs_survivor.jobs.keys(), ["0", "200", "212", "312", "112"], "base entries, then lines in discovered line order")
	var frag: Dictionary = DataRepo.load_json(DataRepo.fragment_path("skills", "hero"))
	for key: String in ["power_strike", "slash_blast", "brandish"]:
		assert_true(frag.skills.has(key), "H5 ports " + key)
	assert_true(frag.skills.has("rush_hero"), "H6 defines Rush")
	assert_eq(Array(DataRepo.unknown_line_files()), [])


# --- the job entry ----------------------------------------------------------------------------------------------------

func test_job_112_has_the_spec_fields_and_is_playable() -> void:
	var data := _data()
	var jobs := _jobs(data)
	var rec := jobs.job(112)
	assert_eq(String(rec.name), "Hero")
	assert_eq(jobs.starting_skill(112), "power_strike")
	assert_eq(jobs.mobility_skill(112), "rush_hero")
	assert_eq(Array(jobs.start_skills(112)), ["power_strike", "rush_hero"])
	assert_eq(jobs.skill_pool(112), ["power_strike", "slash_blast", "brandish", "shout", "monster_magnet", "panic", "coma"])
	assert_eq(jobs.skill_pool(112).size(), 7)
	assert_false("rush_hero" in jobs.skill_pool(112), "Rush is the mobility skill, not a pool entry")
	assert_eq(jobs.weapon_families(112), ["sword", "axe"])
	assert_eq(jobs.creation_weapon(112), 1302000)
	assert_true(bool(rec.playable))
	assert_eq(jobs.job_error(112), "")
	assert_eq(jobs.playable_jobs(), [112, 212] as Array[int])
	var meter: Dictionary = data.jobs_survivor.jobs["112"].meter
	assert_eq(String(meter.id), "combo")
	assert_eq(int(meter.max), 10)
	assert_eq(meter.gain, {"event": "cast_landed", "amount": 1.0, "exclude": "finisher"})
	assert_eq(meter.per_unit, {"stat": "damage", "value": 0.05})
	assert_eq(String(meter.art), "Skill.wz/111.img/skill/1111002/state")


func test_212_keeps_its_entry_unchanged() -> void:
	var jobs := _jobs(_data())
	assert_eq(jobs.starting_skill(212), "energy_bolt")
	assert_eq(jobs.mobility_skill(212), "teleport_fp")
	assert_eq(jobs.weapon_families(212), ["wand", "staff"])
	assert_eq(jobs.creation_weapon(212), 1372005)
	assert_true(bool(jobs.job(212).playable))


func test_pool_keys_that_are_defined_belong_to_the_hero_books() -> void:
	# Each Hero ticket (H5-H8) defines its own keys; a key still undefined stays inert, a defined one is a 100/110/111/112 skill.
	var data := _data()
	var defined: Dictionary = data.skills.skills
	for key: String in ["brandish", "shout", "monster_magnet", "panic", "coma", "rush_hero"]:
		if defined.has(key):
			assert_true(int(defined[key].job) in [100, 110, 111, 112], "%s belongs to a Hero book" % key)


# --- AP row -----------------------------------------------------------------------------------------------------------

func test_the_112_ap_row_is_str_primary_dex_secondary() -> void:
	var row: Dictionary = _data().balance.player.ap["112"]
	assert_eq([String(row.primary), String(row.secondary)], ["str", "dex"])
	assert_eq(row.keyframes, [{"level": 1.0, "target": 4.0}, {"level": 200.0, "target": 204.0}])
	var growth: Dictionary = _data().balance.growth
	assert_eq(int(growth["112"].hp), 65, "H11 Hero-only melee HP growth")
	assert_eq(int(row.hp), 600, "H11 melee starting HP")
	assert_eq(int(growth["100"].hp), 26)


func test_a_hero_spends_its_auto_ap_on_str_and_dex() -> void:
	var w := RF.quiet_world()
	w.set_job(112)
	var base: Dictionary = w.balance.player.stats
	for lv in 20:
		w._gain_exp(w.progression.exp_to_next())
	var level := int(w.player_state.level)
	var earned := (level - 1) * int(w.balance.player.ap_per_level)
	var row: Dictionary = w.balance.player.ap["112"]
	var dex_ap := AutoAp.secondary_ap(earned, level, float(base.dex), row.keyframes)
	assert_true(dex_ap > 0, "DEX takes its share")
	assert_eq(int(w.player_state.dex), int(base.dex) + dex_ap)
	assert_eq(int(w.player_state.str), int(base.str) + earned - dex_ap, "the rest goes to STR")
	assert_eq(int(w.player_state.int), int(base.int))
	assert_eq(int(w.player_state.luk), int(base.luk))


# --- default_job pin --------------------------------------------------------------------------------------------------

func test_default_job_is_pinned_to_212() -> void:
	var data := _data()
	assert_eq(int(data.jobs_survivor.default_job), 212)
	assert_eq(_jobs(data).default_job(), 212)


func test_default_job_stays_212_after_hero_becomes_playable() -> void:
	var data := _data()
	data.jobs_survivor.jobs["112"]["playable"] = true
	var jobs := _jobs(data)
	assert_eq(jobs.playable_jobs(), [112, 212] as Array[int], "Hero is listed first in canonical order")
	assert_eq(jobs.default_job(), 212, "the pin, not the first playable job")
	assert_eq(jobs.job_error(112), "")
	data.jobs_survivor["default_job"] = 112
	assert_eq(_jobs(data).default_job(), 112, "the owner can flip it with one line")


func test_without_a_pin_or_with_an_unplayable_pin_the_first_playable_job_is_the_default() -> void:
	var data := _data()
	data.jobs_survivor.jobs["112"]["playable"] = false
	data.jobs_survivor.erase("default_job")
	assert_eq(_jobs(data).default_job(), 212, "data without the pin behaves as before")
	data.jobs_survivor.jobs["112"]["playable"] = true
	assert_eq(_jobs(data).default_job(), 112)
	data.jobs_survivor["default_job"] = 100
	assert_eq(_jobs(data).default_job(), 112, "a pin on an unplayable job is ignored")
	data.jobs_survivor.jobs["112"]["playable"] = false
	data.jobs_survivor.jobs["212"]["playable"] = false
	assert_eq(_jobs(data).default_job(), 0, "nothing playable")


func test_a_fresh_world_is_still_212_with_hero_playable() -> void:
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["112"]["playable"] = true
	var w := RunWorld.new(RF.setup("quiet", 7, data))
	assert_eq(w.job_id(), 212)
	assert_eq(Array(w.loadout.order), ["energy_bolt", "teleport_fp"])


# --- weapon families and drops ----------------------------------------------------------------------------------------

func test_a_hero_drop_pool_holds_swords_and_axes_of_both_hands_and_no_other_weapon() -> void:
	var families: Array = _jobs(_data()).weapon_families(112)
	var ids := EquipmentDrops.eligible(_ids(), INFO, 112, BAND, families)
	var weapons := ids.filter(func(id: int) -> bool: return Equipment.slot_of(id) == "weapon")
	weapons.sort()
	var want := HERO_WEAPONS.duplicate()
	want.sort()
	assert_eq(weapons, want, "one- and two-handed swords and axes")
	assert_true(1092002 in ids, "the Warrior shield drops by the class bit")
	assert_true(1002001 in ids and 1040002 in ids, "all-job armour drops")
	assert_false(1372004 in ids or 1050001 in ids, "Magician gear never drops for a Hero")


func test_a_seeded_hero_roll_sample_never_yields_a_spear_blunt_or_polearm() -> void:
	var families: Array = _jobs(_data()).weapon_families(112)
	var rng := _rng(298)
	var seen := {}
	for i in 400:
		var id := EquipmentDrops.pick(_ids(), INFO, 112, BAND, RULES, rng, families) if i % 2 == 0 \
			else EquipmentDrops.pick_boss(_ids(), INFO, 112, BAND, RULES, rng, families)
		assert_true(id > 0)
		seen[id] = true
		assert_false(id in NOT_HERO_WEAPONS, "%d is a blunt weapon, spear or polearm" % id)
		if Equipment.slot_of(id) == "weapon":
			assert_true(WeaponInfo.family(id) in ["sword", "axe"], "%d" % id)
	for id: int in HERO_WEAPONS:
		assert_true(seen.has(id), "%d dropped in the sample" % id)


func test_requirement_error_accepts_warrior_bit_gear_only() -> void:
	var hero := {"job_id": 112}
	assert_eq(Equipment.requirement_error({"reqJob": 1}, hero), "", "Warrior bit")
	assert_eq(Equipment.requirement_error({"reqJob": 0}, hero), "", "all jobs")
	assert_eq(Equipment.requirement_error({"reqJob": 3}, hero), "", "Warrior and Magician")
	for bit in [2, 4, 8, 16]:
		assert_eq(Equipment.requirement_error({"reqJob": bit}, hero), "reqJob", "reqJob %d is another class" % bit)
	for id: int in HERO_WEAPONS + NOT_HERO_WEAPONS + [1092002]:
		assert_eq(Equipment.requirement_error(INFO[id], hero), "", "%d is Warrior gear" % id)
	for id: int in [1372004, 1050001]:
		assert_eq(Equipment.requirement_error(INFO[id], hero), "reqJob", "%d is Magician gear" % id)
	assert_eq(Equipment.requirement_error({"reqJob": 1}, {"job_id": 212}), "reqJob", "and a 212 cannot wear it")


## Needs the real asset cache (SKIPs without it, which proves nothing).
func test_real_cache_the_creation_sword_is_wearable_and_the_shipped_pool_holds_swords_and_axes_of_each_hand() -> void:
	if not require_cache():
		return
	var data := _data()
	var jobs := _jobs(data)
	var lib := AssetLibrary.new()
	lib.open()
	var infos := {}
	var ids: Array = data.equipment_drops.items.duplicate()
	ids.append(jobs.creation_weapon(112))
	for raw: Variant in ids:
		var img := lib.img(AvatarRenderer.part_img_path(int(raw)))
		if img != null:
			infos[int(raw)] = img.root.get("info", {})
	lib.free()
	var sword := jobs.creation_weapon(112)
	assert_true(infos.has(sword), "the creation sword is in the cache")
	assert_eq(WeaponInfo.family(sword), "sword")
	assert_eq(Equipment.requirement_error(infos[sword], {"job_id": 112}), "")
	var ed: Dictionary = data.equipment_drops
	for tier in data.stages.tiers.size():
		var band := EquipmentDrops.band_of(data.stages, tier)
		var hands := {}
		var rng := _rng(112 + tier)
		for i in 300:
			var id := EquipmentDrops.pick(ed.items, infos, 112, band, ed, rng, jobs.weapon_families(112))
			assert_true(id > 0)
			assert_eq(Equipment.requirement_error(infos[id], {"job_id": 112}), "", "%d is wearable by a Hero" % id)
			if Equipment.slot_of(id) == "weapon":
				var family := WeaponInfo.family(id)
				assert_true(family in ["sword", "axe"], "%d is a %s" % [id, family])
				hands["%s_%s" % [family, "2h" if WeaponInfo.is_two_handed(id) else "1h"]] = true
		assert_eq(hands.size(), 4, "tier %d: sword and axe, one- and two-handed (%s)" % [tier + 1, hands.keys()])


func test_class_owned_balance_rows_are_absent_from_shared_defaults() -> void:
	var shared: Dictionary = DataRepo.load_json("res://data/survivor/balance.json")
	assert_false(shared.player.ap.has("112"), "Hero AP belongs only to jobs/hero.json")
	for key: String in DataRepo.jobs(DataRepo.load_all()).skill_pool(112):
		assert_false(shared.bot.card_scores.has(key + "_new"), key)
		assert_false(shared.bot.card_scores.has(key + "_rank"), key)
