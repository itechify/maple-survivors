extends TestCase
## Buccaneer's data seam (spec #412, ticket B2 #414): the `buccaneer` line is discovered from its files, its job entry
## `survivor/jobs/buccaneer.json` (512, not playable yet) names the pool and the Energy Charge meter, its AP and growth rows
## copy Hero's (tier C, #346), and its drops are knuckles only (Pirate-bit gear). Undefined pool keys stay inert; the five
## ported keys are defined in buccaneer.json (B4 #416); Dash stays in pirate.json until B5. Seeded RNG; item info is synthetic unless a test says
## "real cache".

const RF := preload("res://tests/fixtures/run_fixtures.gd")

const POOL := ["flash_fist", "somersault_kick", "backspin_blow", "double_uppercut", "corkscrew_blow", "barrage",
	"dragon_strike", "energy_drain", "energy_orb", "transformation", "super_transformation"]
## Defined in skills/buccaneer.json since B4 #416 (moved from pirate.json); every other pool key is undefined until its ticket.
const DEFINED_IN_BUCCANEER := ["flash_fist", "somersault_kick", "backspin_blow", "double_uppercut", "corkscrew_blow"]
const KNUCKLE := 1482000
## Synthetic item info (reqJob bits as in the v83 Item.wz): knuckles and guns carry the Pirate bit (16), the rest
## belong to other lines, so the family filter alone decides which Pirate-bit weapons drop.
const INFO := {
	1482000: {"reqLevel": 0, "reqJob": 16, "incPAD": 20, "tuc": 7}, # Steel Knuckler
	1482003: {"reqLevel": 0, "reqJob": 16, "incPAD": 30, "tuc": 7}, # knuckle
	1482009: {"reqLevel": 0, "reqJob": 16, "incPAD": 40, "tuc": 7}, # knuckle
	1492000: {"reqLevel": 0, "reqJob": 16, "incPAD": 20, "tuc": 7}, # gun
	1302008: {"reqLevel": 0, "reqJob": 1, "incPAD": 47, "tuc": 7}, # one-handed sword
	1312005: {"reqLevel": 0, "reqJob": 1, "incPAD": 47, "tuc": 7}, # one-handed axe
	1452000: {"reqLevel": 0, "reqJob": 4, "incPAD": 20, "tuc": 7}, # bow
	1372004: {"reqLevel": 0, "reqJob": 2, "incPAD": 24, "incMAD": 38, "tuc": 7}, # wand
	1472000: {"reqLevel": 0, "reqJob": 8, "incPAD": 20, "tuc": 7}, # claw
	1002001: {"reqLevel": 0, "reqJob": 0, "incPDD": 4, "tuc": 7}, # hat, all jobs
	1092002: {"reqLevel": 0, "reqJob": 1, "incPDD": 40, "tuc": 7}, # Warrior shield
}
const RULES := {"boss_top_parts": 3}
const BAND := [0, 70]
const WARRIOR_WEAPON := 1302008


func _data() -> Dictionary:
	return DataRepo.load_all()


func _jobs(data: Dictionary) -> JobTree:
	return JobTree.from_data(data.jobs, data.jobs_survivor)


func _rng(p_seed: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = p_seed
	return rng


## The line names (`skills/<line>.json`) whose file defines `key` in its `skills` map, in discovery order.
func _defining_lines(key: String) -> Array:
	var out := []
	for line: String in DataRepo.lines():
		var path := DataRepo.fragment_path("skills", line)
		if FileAccess.file_exists(path) and DataRepo.load_json(path).get("skills", {}).has(key):
			out.append(line)
	return out


# --- the line ---------------------------------------------------------------------------------------------------------

func test_buccaneer_line_is_discovered_from_its_files_without_a_shared_registration() -> void:
	var lines := Array(DataRepo.lines())
	assert_true("buccaneer" in lines, "discovered from its files")
	assert_true(lines.find("buccaneer") > lines.find("hero"), "a class line follows the Adventurer lines and hero")
	assert_eq(DataRepo.fragment_path("jobs_survivor", "buccaneer", "res://data"), "res://data/survivor/jobs/buccaneer.json")
	assert_eq(DataRepo.fragment_path("skills", "buccaneer", "res://data"), "res://data/survivor/skills/buccaneer.json")


func test_the_buccaneer_line_loads_without_errors_and_adds_its_job_and_the_ported_skill_region() -> void:
	var errors := PackedStringArray()
	var d := DataRepo.load_all(DataRepo.DATA_ROOT, errors)
	assert_true(errors.is_empty(), "%s" % [errors])
	assert_true(d.jobs_survivor.jobs.has("512"), "jobs/buccaneer.json is merged into the survivor job data")
	var keys: Array = d.jobs_survivor.jobs.keys()
	assert_eq(keys.slice(0, 3), ["0", "200", "212"], "base entries and the Magician line first")
	assert_true(keys.find("512") > keys.find("212"), "then the class lines in discovered (sorted) line order")
	var frag: Dictionary = DataRepo.load_json(DataRepo.fragment_path("skills", "buccaneer"))
	assert_true(frag.has("_doc"), "the skill file names its owning tickets")
	assert_eq(frag.skills.keys(), DEFINED_IN_BUCCANEER, "B4 defines the five ported skills; B6-B10 append their own definitions")
	assert_eq(Array(DataRepo.unknown_line_files()), [])


func test_the_shared_defaults_hold_no_buccaneer_rows() -> void:
	var shared: Dictionary = DataRepo.load_json("res://data/survivor/balance.json")
	assert_false(shared.player.ap.has("512"), "the Buccaneer AP row lives in jobs/buccaneer.json")
	assert_false(shared.get("growth", {}).has("512"), "the Buccaneer growth row lives in jobs/buccaneer.json")
	assert_false(DataRepo.load_json("res://data/survivor/jobs.json").jobs.has("512"), "no shared job entry")


## No other line's file names job 512 or its AP and growth rows: the class touches no other class's file.
func test_no_other_line_file_names_buccaneer_rows() -> void:
	for line: String in DataRepo.lines():
		var path := DataRepo.fragment_path("jobs_survivor", line)
		if line == "buccaneer" or not FileAccess.file_exists(path):
			continue
		var frag: Dictionary = DataRepo.load_json(path)
		assert_false(frag.get("jobs", {}).has("512"), "%s names no Buccaneer job entry" % line)
		assert_false(frag.get("balance", {}).get("player", {}).get("ap", {}).has("512"), "%s has no 512 AP row" % line)
		assert_false(frag.get("balance", {}).get("growth", {}).has("512"), "%s has no 512 growth row" % line)


# --- the job entry ----------------------------------------------------------------------------------------------------

func test_job_512_has_the_spec_fields_and_is_not_playable_yet() -> void:
	var jobs := _jobs(_data())
	var rec := jobs.job(512)
	assert_eq(String(rec.name), "Buccaneer")
	assert_eq(jobs.starting_skill(512), "flash_fist")
	assert_eq(jobs.mobility_skill(512), "dash")
	assert_eq(Array(jobs.start_skills(512)), ["flash_fist", "dash"], "start skills: the starting skill and Dash")
	assert_eq(jobs.skill_pool(512), POOL)
	assert_eq(jobs.skill_pool(512).size(), 11)
	assert_false("dash" in jobs.skill_pool(512), "Dash is the mobility skill, not a pool entry")
	assert_eq(jobs.weapon_families(512), ["knuckle"])
	assert_eq(jobs.creation_weapon(512), KNUCKLE)
	assert_false(bool(rec.playable))
	assert_ne(jobs.job_error(512), "", "a tool cannot choose it until B11 flips playable")
	assert_false(512 in jobs.playable_jobs(), "Buccaneer is not in the playable list")
	assert_true(112 in jobs.playable_jobs() and 212 in jobs.playable_jobs(), "Hero and F/P stay playable")


func test_the_job_entry_has_no_hub_kit_yet_and_declares_the_meter() -> void:
	var entry: Dictionary = _data().jobs_survivor.jobs["512"]
	assert_false(entry.has("hub_kit"), "the Buccaneer hub kit is B11")
	assert_true(entry.has("meter"), "the Energy Charge meter block is data here")


func test_212_and_112_keep_their_entries_unchanged() -> void:
	var jobs := _jobs(_data())
	assert_eq(jobs.starting_skill(212), "energy_bolt")
	assert_eq(jobs.weapon_families(212), ["wand", "staff"])
	assert_eq(jobs.starting_skill(112), "power_strike")
	assert_eq(jobs.mobility_skill(112), "rush_hero")
	assert_eq(jobs.weapon_families(112), ["sword", "axe"])


func test_default_job_stays_212_with_buccaneer_on_the_line() -> void:
	var data := _data()
	assert_eq(_jobs(data).default_job(), 212)
	data.jobs_survivor.jobs["512"]["playable"] = true
	assert_eq(_jobs(data).default_job(), 212, "the pin, not the first playable job")


# --- the pool: defined keys resolve, undefined keys stay inert --------------------------------------------------------

func test_each_pool_key_is_defined_in_at_most_one_file() -> void:
	for key: String in POOL:
		var lines := _defining_lines(key)
		assert_true(lines.size() <= 1, "%s is defined once at most (%s)" % [key, lines])


func test_the_ported_keys_are_defined_by_buccaneer_and_nothing_else_is_defined() -> void:
	var defined: Dictionary = _data().skills.skills
	for key: String in POOL:
		if key in DEFINED_IN_BUCCANEER:
			assert_eq(_defining_lines(key), ["buccaneer"], "%s moved to buccaneer.json (B4)" % key)
		else:
			assert_false(defined.has(key), "%s is undefined: an inert key" % key)
	assert_eq(_defining_lines("dash"), ["pirate"], "Dash stays in pirate.json until B5")


func test_an_undefined_pool_key_is_never_offered_as_a_card() -> void:
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["512"]["playable"] = true
	var setup := RF.setup("quiet", 7, data)
	setup["job"] = 512
	var w := RunWorld.new(setup)
	var ids := Array(w.upgrades.eligible(w))
	for key: String in POOL.filter(func(k: String) -> bool: return not data.skills.skills.has(k)):
		assert_false(ids.has(key + "_new") or ids.has(key + "_rank"), "%s is not offered" % key)
	assert_false(ids.has("dash_new") or ids.has("dash_rank"), "Dash is not a card")


func test_flash_fist_takes_slot_one_for_a_buccaneer_and_dash_is_not_a_pool_slot_choice() -> void:
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["512"]["playable"] = true
	var setup := RF.with_basic_attack(RF.setup("quiet", 7, data))
	setup["job"] = 512
	var w := RunWorld.new(setup)
	assert_eq(String(w.loadout.order[0]), "flash_fist", "slot 1")


# --- the meter (Energy Charge) ----------------------------------------------------------------------------------------

func test_the_meter_block_is_the_spec_energy_charge() -> void:
	var meter: Dictionary = _data().jobs_survivor.jobs["512"].meter
	assert_eq(String(meter.id), "energy")
	assert_eq(int(meter.max), 10)
	assert_eq(String(meter.gain.event), "cast_landed")
	assert_eq(int(meter.gain.amount), 1)
	assert_eq(String(meter.gain.exclude), "finisher")
	assert_eq(String(meter.per_unit.stat), "damage")
	assert_near(float(meter.per_unit.value), 0.03, 1e-9, "tier C: +3% damage per held energy")
	assert_eq(String(meter.cue.effect), "Skill.wz/511.img/skill/5110001/affected")
	assert_eq(String(meter.cue.sound), "Sound.wz/Skill.img/5110001/Use")
	assert_false(meter.has("art"), "no state node in book 511: the HUD draws the pip fallback")


func test_run_world_configures_the_energy_meter_for_512_and_leaves_212_empty() -> void:
	var w := RF.quiet_world()
	w.set_job(512)
	assert_eq(String(w.meter.config.id), "energy")
	assert_eq(w.meter.snapshot(), {"id": "energy", "value": 0, "max": 10, "art": ""})
	var f := RF.quiet_world()
	f.set_job(212)
	assert_true(f.meter.config.is_empty(), "F/P has no meter")
	assert_true(f.meter.snapshot().is_empty(), "no HUD meter for F/P")


## Hero's own Combo meter is job 112's, not Buccaneer's: the meter lookup is per job line.
func test_hero_keeps_its_combo_meter_and_buccaneer_does_not_inherit_it() -> void:
	var w := RF.quiet_world()
	w.set_job(112)
	assert_eq(String(w.meter.config.id), "combo")
	var b := RF.quiet_world()
	b.set_job(512)
	assert_false(String(b.meter.config.id) == "combo", "Buccaneer's meter is its own")


# --- AP row and growth ------------------------------------------------------------------------------------------------

func test_the_512_ap_row_copies_hero_s_112_row() -> void:
	var data := _data()
	var row: Dictionary = data.balance.player.ap["512"]
	var hero: Dictionary = data.balance.player.ap["112"]
	assert_eq(String(row.primary), "str")
	assert_eq(String(row.secondary), "dex")
	assert_eq(row.keyframes, [{"level": 1.0, "target": 4.0}, {"level": 200.0, "target": 204.0}])
	assert_eq(row.keyframes, hero.keyframes, "the Hero shape")
	assert_eq(float(row.hp), 600.0, "the Hero starting HP (tier C, #346 survivability baseline)")
	assert_eq(float(row.hp), float(hero.hp), "copied from Hero's 112 row")


func test_the_512_growth_row_copies_hero_s_hp_growth() -> void:
	var data := _data()
	assert_eq(float(data.balance.growth["512"].hp), 65.0, "tier C #346: Hero's melee HP growth")
	assert_eq(float(data.balance.growth["512"].hp), float(data.balance.growth["112"].hp))


func test_buccaneer_lineage_resolves_the_512_rows_not_510() -> void:
	var data := _data()
	assert_eq(_jobs(data).lineage(512), [512, 511, 510, 500, 0] as PackedInt32Array)
	assert_eq(float(data.balance.player.ap["510"].keyframes[1].target), 200.0, "the shared 510 row stays")
	var w := RF.quiet_world()
	w.set_job(512)
	assert_eq(w.balance.player.ap["512"].keyframes, data.balance.player.ap["512"].keyframes)


## The round starts at Hero's HP (the AP row's `hp`, tier C #346), not the shared starter HP.
func test_a_buccaneer_round_starts_with_hero_s_starting_hp() -> void:
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["512"]["playable"] = true
	data.jobs_survivor.jobs["112"]["playable"] = true
	var b_setup := RF.setup("quiet", 7, data)
	b_setup["job"] = 512
	var h_setup := RF.setup("quiet", 7, data)
	h_setup["job"] = 112
	var buccaneer := RunWorld.new(b_setup)
	var hero := RunWorld.new(h_setup)
	assert_eq(int(buccaneer.player_state.max_hp), 600)
	assert_eq(int(buccaneer.player_state.max_hp), int(hero.player_state.max_hp), "the same starting HP as Hero")


func test_a_buccaneer_spends_its_auto_ap_on_str_and_dex() -> void:
	var w := RF.quiet_world()
	w.set_job(512)
	var base: Dictionary = w.balance.player.stats
	for lv in 20:
		w._gain_exp(w.progression.exp_to_next())
	var level := int(w.player_state.level)
	var earned := (level - 1) * int(w.balance.player.ap_per_level)
	var row: Dictionary = w.balance.player.ap["512"]
	var dex_ap := AutoAp.secondary_ap(earned, level, float(base.dex), row.keyframes)
	assert_true(dex_ap > 0, "DEX takes its share")
	assert_eq(int(w.player_state.dex), int(base.dex) + dex_ap)
	assert_eq(int(w.player_state.str), int(base.str) + earned - dex_ap, "the rest goes to STR")


# --- weapon families and drops ----------------------------------------------------------------------------------------

func test_a_buccaneer_drop_pool_holds_knuckles_only() -> void:
	var families: Array = _jobs(_data()).weapon_families(512)
	var ids := EquipmentDrops.eligible(INFO.keys(), INFO, 512, BAND, families)
	var weapons := ids.filter(func(id: int) -> bool: return Equipment.slot_of(id) == "weapon")
	weapons.sort()
	assert_eq(weapons, [1482000, 1482003, 1482009], "the knuckles of the synthetic table")
	assert_true(1002001 in ids, "all-job armour drops")
	assert_false(1092002 in ids, "the Warrior shield is Warrior-bit gear, never a Buccaneer's")
	for id: int in [1492000, WARRIOR_WEAPON, 1312005, 1452000, 1372004, 1472000]:
		assert_false(id in ids, "%d (%s) never drops for a Buccaneer" % [id, WeaponInfo.family(id)])


func test_a_seeded_buccaneer_roll_never_yields_a_non_knuckle_weapon() -> void:
	var families: Array = _jobs(_data()).weapon_families(512)
	var rng := _rng(414)
	var ids := INFO.keys()
	var seen := {}
	for i in 400:
		var id := EquipmentDrops.pick(ids, INFO, 512, BAND, RULES, rng, families) if i % 2 == 0 \
			else EquipmentDrops.pick_boss(ids, INFO, 512, BAND, RULES, rng, families)
		assert_true(id > 0)
		seen[id] = true
		if Equipment.slot_of(id) == "weapon":
			assert_eq(WeaponInfo.family(id), "knuckle", "%d" % id)
	for id: int in [1482000, 1482003, 1482009]:
		assert_true(seen.has(id), "%d dropped in the sample" % id)


## The shipped drop list (every equipment_drops item that is a weapon): the families filter holds on the real ids,
## not only on the synthetic table above. Runs without the cache.
func test_the_shipped_weapon_drops_keep_knuckles_only_for_a_buccaneer() -> void:
	var data := _data()
	var weapons: Array = []
	for raw: Variant in data.equipment_drops.items:
		if Equipment.slot_of(int(raw)) == "weapon":
			weapons.append(int(raw))
	assert_false(weapons.is_empty(), "the shipped list has weapons")
	var info := {}
	for id: int in weapons:
		info[id] = {"reqLevel": 0, "reqJob": 16, "tuc": 7}
	var families: Array = _jobs(data).weapon_families(512)
	var ids := EquipmentDrops.eligible(weapons, info, 512, BAND, families)
	var fams := {}
	for id: int in ids:
		fams[WeaponInfo.family(id)] = true
	assert_eq(fams.keys(), ["knuckle"], "%s" % [fams.keys()])
	for id: int in weapons:
		if WeaponInfo.family(id) == "knuckle":
			assert_true(id in ids, "%d (knuckle) drops for a Buccaneer" % id)
		else:
			assert_false(id in ids, "%d (%s) never drops for a Buccaneer" % [id, WeaponInfo.family(id)])


func test_requirement_error_accepts_pirate_bit_gear_and_the_steel_knuckler_only() -> void:
	var buccaneer := {"job_id": 512}
	assert_eq(Equipment.requirement_error(INFO[KNUCKLE], buccaneer), "", "the Steel Knuckler (reqJob 16, the Pirate bit)")
	assert_eq(Equipment.requirement_error({"reqJob": 0}, buccaneer), "", "all jobs")
	assert_eq(Equipment.requirement_error({"reqJob": 16}, buccaneer), "", "Pirate bit")
	assert_eq(Equipment.requirement_error(INFO[WARRIOR_WEAPON], buccaneer), "reqJob", "a Warrior-only sword")
	for bit in [1, 2, 4, 8]:
		assert_eq(Equipment.requirement_error({"reqJob": bit}, buccaneer), "reqJob", "reqJob %d is another class" % bit)


## Needs the real asset cache (SKIPs without it, which proves nothing).
func test_real_cache_the_steel_knuckler_is_wearable_and_each_tier_drops_knuckles_only() -> void:
	if not require_cache():
		return
	var data := _data()
	var jobs := _jobs(data)
	var lib := AssetLibrary.new()
	lib.open()
	var infos := {}
	var ids: Array = data.equipment_drops.items.duplicate()
	ids.append(jobs.creation_weapon(512))
	for raw: Variant in ids:
		var img := lib.img(AvatarRenderer.part_img_path(int(raw)))
		if img != null:
			infos[int(raw)] = img.root.get("info", {})
	lib.free()
	assert_true(infos.has(KNUCKLE), "the Steel Knuckler is in the cache")
	assert_eq(WeaponInfo.family(KNUCKLE), "knuckle")
	assert_eq(Equipment.requirement_error(infos[KNUCKLE], {"job_id": 512}), "", "a Buccaneer can wear the creation knuckler")
	var ed: Dictionary = data.equipment_drops
	for tier in data.stages.tiers.size():
		var band := EquipmentDrops.band_of(data.stages, tier)
		var rng := _rng(414 + tier)
		var knuckles := 0
		for i in 300:
			var id := EquipmentDrops.pick(ed.items, infos, 512, band, ed, rng, jobs.weapon_families(512))
			assert_true(id > 0)
			assert_eq(Equipment.requirement_error(infos[id], {"job_id": 512}), "", "%d is wearable by a Buccaneer" % id)
			if Equipment.slot_of(id) == "weapon":
				assert_eq(WeaponInfo.family(id), "knuckle", "%d" % id)
				knuckles += 1
		assert_true(knuckles > 0, "tier %d drops knuckles" % (tier + 1))
