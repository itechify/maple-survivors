extends TestCase
## Dark Knight's data seam (spec #348, ticket D2 #350): the `dark_knight` data line loads and is discovered in sorted class
## order, the job entry `survivor/jobs/dark_knight.json` (132, not playable, so `default_job` stays 212), its AP and growth
## rows (copied from Hero's tier C survivability baseline, #346), and the weapon families of its equipment drops (spear and
## pole arm, both two-handed; armour by the Warrior class bit). Seeded RNG; item info is synthetic unless a test says
## "real cache". The Hero and F/P oracles are not touched by this data.

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
	1432000: {"reqLevel": 0, "reqJob": 13, "incPAD": 20, "tuc": 7}, # the creation Spear (reqJob 13 includes the Warrior bit)
	1432002: {"reqLevel": 30, "reqJob": 1, "incPAD": 52, "tuc": 7}, # spear
	1442001: {"reqLevel": 30, "reqJob": 1, "incPAD": 52, "tuc": 7}, # polearm
	1092002: {"reqLevel": 30, "reqJob": 1, "incPDD": 40, "tuc": 7}, # Warrior shield
	1372004: {"reqLevel": 30, "reqJob": 2, "incPAD": 24, "incMAD": 38, "tuc": 7}, # wand
	1050001: {"reqLevel": 30, "reqJob": 2, "incPDD": 20, "incMDD": 12, "tuc": 10}, # Magician overall
}
const RULES := {"boss_top_parts": 3}
const BAND := [0, 70]
const DK_WEAPONS := [1432000, 1432002, 1442001]
const NOT_DK_WEAPONS := [1302008, 1402002, 1312005, 1412006, 1322014, 1422001]
## The Hero skills this line shares by key (DK-13): defined once, in skills/hero.json.
const SHARED_KEYS := ["power_strike", "slash_blast"]
const POOL := ["spear_crusher", "power_strike", "slash_blast", "dragon_fury", "sacrifice", "dragon_roar",
		"monster_magnet_dark_knight", "beholder"]


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


## Every skill key a skills fragment (or the base file) defines, with the file it came from.
func _defined_in_files() -> Dictionary:
	var out := {}
	var paths := {"res://data/survivor/skills.json": "base"}
	for line in DataRepo.lines():
		paths[DataRepo.fragment_path("skills", line)] = line
	for path: String in paths:
		var frag: Dictionary = DataRepo.load_json(path)
		for key: String in frag.get("skills", {}):
			if not out.has(key):
				out[key] = []
			out[key].append(paths[path])
	return out


# --- the line ---------------------------------------------------------------------------------------------------------

func test_dark_knight_line_is_discovered_without_a_shared_registration() -> void:
	assert_true("dark_knight" in DataRepo.lines())
	assert_eq(DataRepo.fragment_path("jobs_survivor", "dark_knight", "res://data"),
		"res://data/survivor/jobs/dark_knight.json")
	assert_eq(DataRepo.fragment_path("skills", "dark_knight", "res://data"),
		"res://data/survivor/skills/dark_knight.json")


func test_the_dark_knight_line_loads_and_merges_its_job_in_sorted_class_order() -> void:
	var errors := PackedStringArray()
	var d := DataRepo.load_all(DataRepo.DATA_ROOT, errors)
	assert_true(errors.is_empty(), "%s" % [errors])
	assert_true(FileAccess.file_exists(DataRepo.fragment_path("jobs_survivor", "dark_knight")))
	assert_true(FileAccess.file_exists(DataRepo.fragment_path("skills", "dark_knight")))
	assert_true(d.jobs_survivor.jobs.has("132"), "jobs/dark_knight.json is merged into the survivor job data")
	assert_eq(d.jobs_survivor.jobs.keys(), ["0", "200", "212", "132", "112"],
		"base entries, then lines in sorted class order (dark_knight before hero)")
	assert_eq(Array(DataRepo.unknown_line_files()), [])


func test_the_skills_fragment_holds_only_dark_knights_own_skills_with_its_doc() -> void:
	# D2 shipped it empty; D5-D9 append their own skills. Whatever it holds is in the pool and never a shared key.
	var frag: Dictionary = DataRepo.load_json(DataRepo.fragment_path("skills", "dark_knight"))
	for key: String in frag.skills:
		var sub_of := String(frag.skills[key].get("summon_sub_of", ""))
		assert_true(key in POOL or (frag.skills[key].get("slot", "") == "summon_sub" and sub_of in POOL),
			"%s is a pool skill, or a support sub of one (the Beholder's Aura and Hex)" % key)
		assert_false(key in SHARED_KEYS, "%s is Hero's, never defined here (DK-13)" % key)
	assert_true(String(frag._doc).contains("#348"), "the _doc names the spec")


# --- the job entry ----------------------------------------------------------------------------------------------------

func test_job_132_has_the_spec_fields_and_is_not_playable() -> void:
	var data := _data()
	var jobs := _jobs(data)
	var rec := jobs.job(132)
	assert_eq(String(rec.name), "Dark Knight")
	assert_eq(jobs.starting_skill(132), "spear_crusher")
	assert_eq(jobs.mobility_skill(132), "rush_dark_knight")
	assert_eq(Array(jobs.start_skills(132)), ["spear_crusher", "rush_dark_knight"])
	assert_eq(jobs.skill_pool(132), POOL)
	assert_eq(jobs.skill_pool(132).size(), 8, "Rush is the mobility skill, so the pool is eight, not nine")
	assert_false("rush_dark_knight" in jobs.skill_pool(132), "Rush is not a pool entry")
	assert_eq(jobs.weapon_families(132), ["spear", "polearm"])
	assert_eq(jobs.creation_weapon(132), 1432000)
	assert_false(bool(rec.playable), "playable flips in D10, not here")
	assert_true(jobs.job_error(132) != "", "--job=132 is refused while the job is not playable")
	assert_eq(jobs.playable_jobs(), [112, 212] as Array[int], "the creation page still lists only Hero and Arch Mage")


func test_default_job_stays_212_with_dark_knight_playable() -> void:
	var data := _data()
	data.jobs_survivor.jobs["132"]["playable"] = true
	var jobs := _jobs(data)
	assert_eq(jobs.playable_jobs(), [112, 132, 212] as Array[int], "canonical job order (112, 132, 212)")
	assert_eq(jobs.default_job(), 212, "the pin, not the first playable job")
	assert_eq(jobs.job_error(132), "")


func test_every_pool_key_is_defined_only_where_its_file_says() -> void:
	# A pool key with no definition anywhere stays inert: it is never offered (an undefined skill is never a card).
	var defined := _defined_in_files()
	var merged: Dictionary = _data().skills.skills
	for key: String in POOL:
		if defined.has(key):
			assert_eq(defined[key].size(), 1, "%s is defined in exactly one file" % key)
			assert_true(merged.has(key), "%s resolves in the merged skills" % key)
		else:
			assert_false(merged.has(key), "%s is inert until its ticket defines it" % key)


func test_each_shared_key_lives_in_hero_only() -> void:
	# DK-13: Power Strike and Slash Blast are Hero's books (100). Dark Knight lists them and defines nothing for them.
	var defined := _defined_in_files()
	for key: String in SHARED_KEYS:
		assert_eq(defined.get(key, []), ["hero"], "%s is defined only in skills/hero.json" % key)
	var frag: Dictionary = DataRepo.load_json(DataRepo.fragment_path("skills", "dark_knight"))
	for key: String in SHARED_KEYS:
		assert_false(frag.skills.has(key), "%s is not redefined by the Dark Knight line" % key)


func test_a_dark_knight_has_no_hub_kit_or_meter_yet() -> void:
	# hub_kit is D10's; the meter is Hero's Combo. Neither belongs to this data ticket.
	var rec: Dictionary = _data().jobs_survivor.jobs["132"]
	assert_false(rec.has("hub_kit"))
	assert_false(rec.has("meter"))


# --- AP and growth rows -----------------------------------------------------------------------------------------------

func test_the_132_ap_row_copies_hero_s_row_exactly() -> void:
	var data := _data()
	var hero_row: Dictionary = data.balance.player.ap["112"]
	var row: Dictionary = data.balance.player.ap["132"]
	# Compare the values, not the `_hp` provenance note: the note names this ticket.
	assert_eq(int(row.hp), int(hero_row.hp), "the same melee survivability HP as Hero (#346, DK-10)")
	assert_eq(row.keyframes, hero_row.keyframes, "the same AP keyframes")
	assert_eq([String(row.primary), String(row.secondary)], [String(hero_row.primary), String(hero_row.secondary)])
	assert_eq([String(row.primary), String(row.secondary)], ["str", "dex"])
	assert_eq(row.keyframes, [{"level": 1.0, "target": 4.0}, {"level": 200.0, "target": 204.0}])
	assert_eq(int(row.hp), 600, "starting HP copied from Hero (tier C, orchestrator ruling)")


func test_the_132_growth_row_copies_hero_s_hp_growth() -> void:
	var growth: Dictionary = _data().balance.growth
	assert_eq(int(growth["132"].hp), 65, "HP growth copied from Hero (tier C)")
	assert_eq(int(growth["132"].hp), int(growth["112"].hp))


func test_the_growth_row_resolves_for_a_dark_knight_through_its_own_entry() -> void:
	# The lineage of 132 is 132, 131, 130, 100, 0: its own row wins over the Warrior row the lineage used to resolve to.
	var jobs := _jobs(_data())
	var lineage := Array(jobs.lineage(132))
	assert_eq(lineage[0], 132)
	assert_true(100 in lineage)
	assert_eq(int(_data().balance.growth["100"].hp), 26, "the Warrior row a Dark Knight no longer inherits")


func test_class_owned_rows_are_absent_from_shared_defaults() -> void:
	var shared: Dictionary = DataRepo.load_json("res://data/survivor/balance.json")
	assert_false(shared.player.ap.has("132"), "Dark Knight AP belongs only to jobs/dark_knight.json")
	assert_false(shared.growth.has("132"), "Dark Knight growth belongs only to jobs/dark_knight.json")
	assert_false(shared.bot.card_scores.has("spear_crusher_new"), "bot scores stay the default (D10 makes them explicit)")


# --- weapon families and drops ----------------------------------------------------------------------------------------

func test_a_dark_knight_drop_pool_holds_spears_and_pole_arms_and_no_other_weapon() -> void:
	var families: Array = _jobs(_data()).weapon_families(132)
	var ids := EquipmentDrops.eligible(_ids(), INFO, 132, BAND, families)
	var weapons := ids.filter(func(id: int) -> bool: return Equipment.slot_of(id) == "weapon")
	weapons.sort()
	var want := DK_WEAPONS.duplicate()
	want.sort()
	assert_eq(weapons, want, "the spear and the pole arm")
	assert_true(1092002 in ids, "the Warrior shield drops by the class bit (DK-10: accepted, a wasted drop for a two-hander)")
	assert_true(1002001 in ids and 1040002 in ids, "all-job armour drops")
	assert_false(1372004 in ids or 1050001 in ids, "Magician gear never drops for a Dark Knight")


func test_a_seeded_dark_knight_roll_sample_never_yields_a_sword_axe_or_blunt_weapon() -> void:
	var families: Array = _jobs(_data()).weapon_families(132)
	var rng := _rng(350)
	var seen := {}
	for i in 400:
		var id := EquipmentDrops.pick(_ids(), INFO, 132, BAND, RULES, rng, families) if i % 2 == 0 \
			else EquipmentDrops.pick_boss(_ids(), INFO, 132, BAND, RULES, rng, families)
		assert_true(id > 0)
		seen[id] = true
		assert_false(id in NOT_DK_WEAPONS, "%d is a sword, axe or blunt weapon" % id)
		if Equipment.slot_of(id) == "weapon":
			assert_true(WeaponInfo.family(id) in ["spear", "polearm"], "%d" % id)
	for id: int in DK_WEAPONS:
		assert_true(seen.has(id), "%d dropped in the sample" % id)


func test_the_shipped_drop_list_holds_spears_and_pole_arms_and_no_other_weapon_for_a_dark_knight() -> void:
	# No cache needed: the shipped id list and WeaponInfo's id ranges, with synthetic Warrior-bit info for each weapon.
	var data := _data()
	var families: Array = _jobs(data).weapon_families(132)
	var infos := {}
	for raw: Variant in data.equipment_drops.items:
		var id := int(raw)
		if Equipment.slot_of(id) == "weapon":
			infos[id] = {"reqLevel": 0, "reqJob": 1, "incPAD": 1, "tuc": 7}
	var ids := EquipmentDrops.eligible(infos.keys(), infos, 132, [0, 999], families)
	assert_false(ids.is_empty())
	var fams := {}
	for id: int in ids:
		fams[WeaponInfo.family(id)] = true
	assert_eq(fams.keys().size(), 2, "only spear and polearm survive the filter: %s" % [fams.keys()])
	assert_true(fams.has("spear") and fams.has("polearm"))


func test_requirement_error_accepts_warrior_bit_gear_and_the_creation_spear_only() -> void:
	var dk := {"job_id": 132}
	assert_eq(Equipment.requirement_error({"reqJob": 1}, dk), "", "Warrior bit")
	assert_eq(Equipment.requirement_error({"reqJob": 0}, dk), "", "all jobs")
	assert_eq(Equipment.requirement_error({"reqJob": 13}, dk), "", "the Spear's reqJob 13 includes the Warrior bit")
	for id: int in DK_WEAPONS + NOT_DK_WEAPONS + [1432000, 1092002]:
		assert_eq(Equipment.requirement_error(INFO[id], dk), "", "%d is Warrior gear" % id)
	for bit in [2, 4, 8, 16]:
		assert_eq(Equipment.requirement_error({"reqJob": bit}, dk), "reqJob", "reqJob %d is another class" % bit)
	for id: int in [1372004, 1050001]:
		assert_eq(Equipment.requirement_error(INFO[id], dk), "reqJob", "%d is Magician gear" % id)
	assert_eq(Equipment.requirement_error({"reqJob": 1}, {"job_id": 212}), "reqJob", "and a 212 cannot wear it")


## Needs the real asset cache (SKIPs without it, which proves nothing).
func test_real_cache_the_creation_spear_is_wearable_and_the_shipped_pool_holds_spears_and_pole_arms() -> void:
	if not require_cache():
		return
	var data := _data()
	var jobs := _jobs(data)
	var lib := AssetLibrary.new()
	lib.open()
	var infos := {}
	var ids: Array = data.equipment_drops.items.duplicate()
	ids.append(jobs.creation_weapon(132))
	for raw: Variant in ids:
		var img := lib.img(AvatarRenderer.part_img_path(int(raw)))
		if img != null:
			infos[int(raw)] = img.root.get("info", {})
	lib.free()
	var spear := jobs.creation_weapon(132)
	assert_true(infos.has(spear), "the creation spear is in the cache")
	assert_eq(WeaponInfo.family(spear), "spear")
	assert_eq(Equipment.requirement_error(infos[spear], {"job_id": 132}), "")
	var ed: Dictionary = data.equipment_drops
	for tier in data.stages.tiers.size():
		var band := EquipmentDrops.band_of(data.stages, tier)
		var families := {}
		var rng := _rng(132 + tier)
		for i in 300:
			var id := EquipmentDrops.pick(ed.items, infos, 132, band, ed, rng, jobs.weapon_families(132))
			assert_true(id > 0)
			assert_eq(Equipment.requirement_error(infos[id], {"job_id": 132}), "", "%d is wearable by a Dark Knight" % id)
			if Equipment.slot_of(id) == "weapon":
				var family := WeaponInfo.family(id)
				assert_true(family in ["spear", "polearm"], "%d is a %s" % [id, family])
				families[family] = true
		assert_eq(families.size(), 2, "tier %d: spear and pole arm both drop (%s)" % [tier + 1, families.keys()])
