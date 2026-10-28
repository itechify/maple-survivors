extends TestCase
## The I/L Arch Mage's data seam (spec #319, ticket I2 #321): the `il_arch_mage` data line loads and is the last of the
## class lines, the job entry `survivor/jobs/il_arch_mage.json` (222, playable false until I12), its AP row, the pool
## keys that are defined belonging to the 200/220/221/222 books, and the weapon families of its equipment drops (wands
## and staves only; armour by the Magician class bit). Seeded RNG; item info is synthetic unless a test says "real cache".

const RF := preload("res://tests/fixtures/run_fixtures.gd")

## Synthetic items: id -> info. Magician wands and staves (the creation wand included), Magician armour, a Warrior sword,
## a Warrior axe and a Warrior shield, and all-job armour.
const INFO := {
	1002001: {"reqLevel": 0, "reqJob": 0, "incPDD": 4, "tuc": 7}, # hat, all jobs
	1040002: {"reqLevel": 30, "reqJob": 0, "incPDD": 3, "tuc": 7}, # top, all jobs
	1372005: {"reqLevel": 0, "reqJob": 2, "incPAD": 24, "incMAD": 38, "tuc": 7}, # creation wand
	1372004: {"reqLevel": 30, "reqJob": 2, "incPAD": 24, "incMAD": 38, "tuc": 7}, # wand
	1382012: {"reqLevel": 30, "reqJob": 2, "incMAD": 45, "tuc": 7}, # staff
	1050001: {"reqLevel": 30, "reqJob": 2, "incPDD": 20, "incMDD": 12, "tuc": 10}, # Magician overall
	1302008: {"reqLevel": 30, "reqJob": 1, "incPAD": 47, "tuc": 7}, # one-handed sword
	1312005: {"reqLevel": 30, "reqJob": 1, "incPAD": 47, "tuc": 7}, # one-handed axe
	1092002: {"reqLevel": 30, "reqJob": 1, "incPDD": 40, "tuc": 7}, # Warrior shield
}
const RULES := {"boss_top_parts": 3}
const BAND := [0, 70]
const IL_WEAPONS := [1372005, 1372004, 1382012]
const NOT_IL_WEAPONS := [1302008, 1312005]
const POOL := ["energy_bolt", "magic_claw", "cold_beam", "thunder_bolt", "ice_strike", "thunder_spear",
	"element_composition_il", "ice_demon", "ifrit", "chain_lightning", "blizzard", "big_bang_il"]


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

func test_il_arch_mage_is_a_class_line_after_the_seven_adventurer_lines() -> void:
	var lines := Array(DataRepo.LINES)
	assert_eq(lines.slice(0, 7), ["common", "beginner", "warrior", "magician", "bowman", "thief", "pirate"],
		"the lines before it keep their merge order")
	assert_true("il_arch_mage" in lines.slice(7), "appended after pirate")
	var class_lines: Array = lines.slice(7)
	for line: String in class_lines:
		assert_true(line in ["hero", "il_arch_mage"], "%s is a class line this spec knows" % line)
	assert_eq(DataRepo.fragment_path("jobs_survivor", "il_arch_mage", "res://data"),
		"res://data/survivor/jobs/il_arch_mage.json")
	assert_eq(DataRepo.fragment_path("skills", "il_arch_mage", "res://data"),
		"res://data/survivor/skills/il_arch_mage.json")


func test_the_line_loads_without_errors_and_adds_a_job_but_no_skill_yet() -> void:
	var errors := PackedStringArray()
	var d := DataRepo.load_all(DataRepo.DATA_ROOT, errors)
	assert_true(errors.is_empty(), "%s" % [errors])
	assert_true(FileAccess.file_exists(DataRepo.fragment_path("jobs_survivor", "il_arch_mage")))
	assert_true(FileAccess.file_exists(DataRepo.fragment_path("skills", "il_arch_mage")))
	assert_true(d.jobs_survivor.jobs.has("222"), "jobs/il_arch_mage.json is merged into the survivor job data")
	assert_true(d.jobs_survivor.jobs.keys().find("222") > d.jobs_survivor.jobs.keys().find("212"),
		"base, then lines in LINES order: 222 after 212")
	var frag: Dictionary = DataRepo.load_json(DataRepo.fragment_path("skills", "il_arch_mage"))
	assert_eq(frag.skills, {}, "I2 ships an empty skill skeleton; I6-I10 fill it")
	assert_false(FileAccess.file_exists("res://data/asset_manifest.d/il_arch_mage.json"), "I1 owns the manifest fragment")
	assert_eq(Array(DataRepo.unknown_line_files()), [])


# --- the job entry ----------------------------------------------------------------------------------------------------

func test_job_222_has_the_spec_fields_and_is_not_playable() -> void:
	var jobs := _jobs(_data())
	var rec := jobs.job(222)
	assert_eq(String(rec.name), "Arch Mage (Ice, Lightning)")
	assert_eq(jobs.starting_skill(222), "cold_beam")
	assert_eq(jobs.mobility_skill(222), "teleport_il")
	assert_eq(Array(jobs.start_skills(222)), ["cold_beam", "teleport_il"])
	assert_eq(jobs.skill_pool(222), POOL)
	assert_eq(jobs.skill_pool(222).size(), 12)
	assert_false("teleport_il" in jobs.skill_pool(222), "Teleport is the mobility skill, not a pool entry")
	assert_eq(jobs.weapon_families(222), ["wand", "staff"])
	assert_eq(jobs.creation_weapon(222), 1372005)
	assert_false(bool(rec.playable))
	assert_ne(jobs.job_error(222), "", "the tools refuse an unplayable job")
	assert_eq(jobs.playable_jobs(), [212] as Array[int])


func test_212_keeps_its_entry_unchanged() -> void:
	var jobs := _jobs(_data())
	assert_eq(jobs.starting_skill(212), "energy_bolt")
	assert_eq(jobs.mobility_skill(212), "teleport_fp")
	assert_eq(jobs.weapon_families(212), ["wand", "staff"])
	assert_eq(jobs.creation_weapon(212), 1372005)
	assert_true(bool(jobs.job(212).playable))


func test_pool_keys_not_yet_defined_stay_inert() -> void:
	var defined: Dictionary = _data().skills.skills
	for key: String in ["ice_strike", "thunder_spear", "element_composition_il", "ice_demon", "ifrit",
			"chain_lightning", "blizzard", "big_bang_il"]:
		assert_false(defined.has(key), "%s is defined by its own ticket, not by I2" % key)


func test_every_defined_pool_key_belongs_to_the_200_220_221_or_222_book() -> void:
	var data := _data()
	var defined: Dictionary = data.skills.skills
	var found := 0
	for key: String in _jobs(data).skill_pool(222):
		if not defined.has(key):
			continue
		found += 1
		assert_true(String(defined[key].book) in ["200", "220", "221", "222"], "%s is book %s" % [key, defined[key].book])
	assert_eq(found, 4, "energy_bolt, magic_claw, cold_beam, thunder_bolt are defined today")


# --- AP row -----------------------------------------------------------------------------------------------------------

func test_the_222_ap_row_is_int_primary_luk_secondary_at_the_212_keyframes() -> void:
	var row: Dictionary = _data().balance.player.ap["222"]
	assert_eq([String(row.primary), String(row.secondary)], ["int", "luk"])
	assert_eq(row.keyframes, [{"level": 1.0, "target": 3.0}, {"level": 200.0, "target": 202.0}])
	assert_eq(row.keyframes, _data().balance.player.ap["212"].keyframes, "the same curve as F/P")


func test_an_il_spends_its_auto_ap_on_int_and_luk() -> void:
	var w := RF.quiet_world()
	w.set_job(222)
	var base: Dictionary = w.balance.player.stats
	for lv in 20:
		w._gain_exp(w.progression.exp_to_next())
	var level := int(w.player_state.level)
	var earned := (level - 1) * int(w.balance.player.ap_per_level)
	var row: Dictionary = w.balance.player.ap["222"]
	var luk_ap := AutoAp.secondary_ap(earned, level, float(base.luk), row.keyframes)
	assert_true(luk_ap > 0, "LUK takes its share")
	assert_eq(int(w.player_state.luk), int(base.luk) + luk_ap)
	assert_eq(int(w.player_state.int), int(base.int) + earned - luk_ap, "the rest goes to INT")
	assert_eq(int(w.player_state.str), int(base.str))
	assert_eq(int(w.player_state.dex), int(base.dex))


# --- default_job ------------------------------------------------------------------------------------------------------

func test_default_job_stays_212_after_il_becomes_playable() -> void:
	var data := _data()
	data.jobs_survivor.jobs["222"]["playable"] = true
	var jobs := _jobs(data)
	assert_eq(jobs.playable_jobs(), [212, 222] as Array[int], "F/P is listed first in canonical order")
	assert_eq(jobs.default_job(), 212, "212 < 222: the first playable job stays the default")


func test_a_fresh_world_is_still_212_with_il_playable() -> void:
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["222"]["playable"] = true
	var w := RunWorld.new(RF.setup("quiet", 7, data))
	assert_eq(w.job_id(), 212)


# --- weapon families and drops ----------------------------------------------------------------------------------------

func test_an_il_drop_pool_holds_wands_and_staves_and_no_other_weapon() -> void:
	var families: Array = _jobs(_data()).weapon_families(222)
	var ids := EquipmentDrops.eligible(_ids(), INFO, 222, BAND, families)
	var weapons := ids.filter(func(id: int) -> bool: return Equipment.slot_of(id) == "weapon")
	weapons.sort()
	var want := IL_WEAPONS.duplicate()
	want.sort()
	assert_eq(weapons, want, "wands and staves only")
	assert_true(1050001 in ids and 1040002 in ids, "Magician and all-job armour drop")
	assert_false(1092002 in ids, "the Warrior shield never drops for an I/L")
	assert_false(1302008 in ids or 1312005 in ids, "no sword or axe")


func test_a_seeded_il_roll_sample_never_yields_another_weapon_family() -> void:
	var families: Array = _jobs(_data()).weapon_families(222)
	var rng := _rng(321)
	var seen := {}
	for i in 400:
		var id := EquipmentDrops.pick(_ids(), INFO, 222, BAND, RULES, rng, families) if i % 2 == 0 \
			else EquipmentDrops.pick_boss(_ids(), INFO, 222, BAND, RULES, rng, families)
		assert_true(id > 0)
		seen[id] = true
		assert_false(id in NOT_IL_WEAPONS, "%d is a sword or axe" % id)
		if Equipment.slot_of(id) == "weapon":
			assert_true(WeaponInfo.family(id) in ["wand", "staff"], "%d" % id)
	for id: int in IL_WEAPONS:
		assert_true(seen.has(id), "%d dropped in the sample" % id)


func test_requirement_error_accepts_magician_bit_gear_only() -> void:
	var il := {"job_id": 222}
	assert_eq(Equipment.requirement_error({"reqJob": 2}, il), "", "Magician bit")
	assert_eq(Equipment.requirement_error({"reqJob": 0}, il), "", "all jobs")
	assert_eq(Equipment.requirement_error({"reqJob": 3}, il), "", "Warrior and Magician")
	for bit in [1, 4, 8, 16]:
		assert_eq(Equipment.requirement_error({"reqJob": bit}, il), "reqJob", "reqJob %d is another class" % bit)
	for id: int in [1372005, 1372004, 1382012, 1050001]:
		assert_eq(Equipment.requirement_error(INFO[id], il), "", "%d is Magician gear" % id)
	for id: int in [1302008, 1312005, 1092002]:
		assert_eq(Equipment.requirement_error(INFO[id], il), "reqJob", "%d is Warrior gear" % id)


## Needs the real asset cache (SKIPs without it, which proves nothing).
func test_real_cache_the_creation_wand_is_wearable_and_the_shipped_pool_holds_only_wands_and_staves() -> void:
	if not require_cache():
		return
	var data := _data()
	var jobs := _jobs(data)
	var lib := AssetLibrary.new()
	lib.open()
	var infos := {}
	var ids: Array = data.equipment_drops.items.duplicate()
	ids.append(jobs.creation_weapon(222))
	for raw: Variant in ids:
		var img := lib.img(AvatarRenderer.part_img_path(int(raw)))
		if img != null:
			infos[int(raw)] = img.root.get("info", {})
	lib.free()
	var wand := jobs.creation_weapon(222)
	assert_true(infos.has(wand), "the creation wand is in the cache")
	assert_eq(WeaponInfo.family(wand), "wand")
	assert_eq(Equipment.requirement_error(infos[wand], {"job_id": 222}), "")
	var ed: Dictionary = data.equipment_drops
	for tier in data.stages.tiers.size():
		var band := EquipmentDrops.band_of(data.stages, tier)
		var families := {}
		var rng := _rng(222 + tier)
		for i in 300:
			var id := EquipmentDrops.pick(ed.items, infos, 222, band, ed, rng, jobs.weapon_families(222))
			assert_true(id > 0)
			assert_eq(Equipment.requirement_error(infos[id], {"job_id": 222}), "", "%d is wearable by an I/L" % id)
			if Equipment.slot_of(id) == "weapon":
				families[WeaponInfo.family(id)] = true
		assert_eq(families.keys().size(), 2, "tier %d: wands and staves (%s)" % [tier + 1, families.keys()])
		assert_true(families.has("wand") and families.has("staff"), "tier %d" % (tier + 1))
