extends TestCase
## Corsair's data seam (spec #384, ticket C2 #386): the `corsair` line (registered in CLASS_LINES at its redesign merge, D15), its job entry
## `survivor/jobs/corsair.json` (522, playable since C15 #399) names the thirteen-key pool, the Pistol and the guns-only families,
## its AP row copies the 520 row (tier C), and its drops are guns only (Pirate-bit gear). Undefined pool keys stay inert; no
## other job's file names job 522. Seeded RNG; item info is synthetic unless a test says "real cache".

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const CF := preload("res://tests/fixtures/corsair_fixtures.gd")

const POOL := ["double_shot", "burst_fire", "invisible_shot", "recoil_shot", "grenade", "flamethrower", "ice_splitter",
	"octopus", "gaviota", "homing_beacon", "aerial_strike", "rapid_fire", "battleship"]
## Synthetic item info (reqJob bits as in the v83 Item.wz): guns and knucklers carry the Pirate bit (16), the rest belong to
## other lines, so the family filter alone decides which Pirate-bit weapons drop.
const INFO := {
	1492000: {"reqLevel": 0, "reqJob": 16, "incPAD": 20, "tuc": 7}, # Pistol
	1492005: {"reqLevel": 0, "reqJob": 16, "incPAD": 30, "tuc": 7}, # gun
	1492012: {"reqLevel": 0, "reqJob": 16, "incPAD": 40, "tuc": 7}, # gun
	1482000: {"reqLevel": 0, "reqJob": 16, "incPAD": 20, "tuc": 7}, # Steel Knuckler
	1302008: {"reqLevel": 0, "reqJob": 1, "incPAD": 47, "tuc": 7}, # one-handed sword
	1312005: {"reqLevel": 0, "reqJob": 1, "incPAD": 47, "tuc": 7}, # one-handed axe
	1452000: {"reqLevel": 0, "reqJob": 4, "incPAD": 20, "tuc": 7}, # bow
	1462000: {"reqLevel": 0, "reqJob": 4, "incPAD": 20, "tuc": 7}, # crossbow
	1372004: {"reqLevel": 0, "reqJob": 2, "incPAD": 24, "incMAD": 38, "tuc": 7}, # wand
	1472000: {"reqLevel": 0, "reqJob": 8, "incPAD": 20, "tuc": 7}, # claw
	1002001: {"reqLevel": 0, "reqJob": 0, "incPDD": 4, "tuc": 7}, # hat, all jobs
	1082002: {"reqLevel": 0, "reqJob": 16, "incPDD": 2, "tuc": 5}, # Pirate-bit gloves
	1092002: {"reqLevel": 0, "reqJob": 1, "incPDD": 40, "tuc": 7}, # Warrior shield
}
const RULES := {"boss_top_parts": 3}
const BAND := [0, 70]
const NON_GUN_WEAPONS := [1482000, 1302008, 1312005, 1452000, 1462000, 1372004, 1472000]


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

func test_corsair_line_is_registered_after_the_shipped_classes() -> void:
	var lines := Array(DataRepo.lines())
	assert_true("corsair" in lines, "loaded from its files")
	# Ruling D15: a shipped class line is appended to CLASS_LINES in redesign-merge order, so a later line never moves it.
	assert_eq(Array(DataRepo.CLASS_LINES).back(), "corsair")
	assert_eq(lines.find("corsair"), lines.find("buccaneer") + 1, "pinned right after the last earlier registration")
	assert_true(lines.find("corsair") > lines.find("hero"), "a class line follows the Adventurer lines and hero")
	assert_true(lines.find("corsair") > lines.find("pirate"))
	assert_eq(DataRepo.fragment_path("jobs_survivor", "corsair", "res://data"), "res://data/survivor/jobs/corsair.json")
	assert_eq(DataRepo.fragment_path("skills", "corsair", "res://data"), "res://data/survivor/skills/corsair.json")


func test_the_corsair_line_loads_without_errors_and_adds_its_job_and_its_skills() -> void:
	var errors := PackedStringArray()
	var d := DataRepo.load_all(DataRepo.DATA_ROOT, errors)
	assert_true(errors.is_empty(), "%s" % [errors])
	assert_true(d.jobs_survivor.jobs.has("522"), "jobs/corsair.json is merged into the survivor job data")
	var keys: Array = d.jobs_survivor.jobs.keys()
	assert_eq(keys.slice(0, 3), ["0", "200", "212"], "base entries and the Magician line first")
	assert_true(keys.find("522") > keys.find("212"), "then the class lines in discovered line order")
	var frag: Dictionary = DataRepo.load_json(DataRepo.fragment_path("skills", "corsair"))
	assert_true(frag.has("_doc"), "the skill file names its owning tickets")
	assert_true(frag.has("skills"))
	for key: String in frag.skills:
		assert_true(String(frag.skills[key].book) in ["500", "520", "521", "522"], "%s is a Corsair-line book skill" % key)
	assert_eq(Array(DataRepo.unknown_line_files()), [])


func test_the_shared_defaults_hold_no_corsair_rows() -> void:
	var shared: Dictionary = DataRepo.load_json("res://data/survivor/balance.json")
	assert_false(shared.player.ap.has("522"), "the Corsair AP row lives in jobs/corsair.json")
	assert_false(shared.get("growth", {}).has("522"), "no Corsair growth row: it inherits the 500 row")
	assert_false(DataRepo.load_json("res://data/survivor/jobs.json").jobs.has("522"), "no shared job entry")


## No other line's file names job 522 or its AP row: the class touches no other class's file.
func test_no_other_line_file_names_corsair_rows() -> void:
	for line: String in DataRepo.lines():
		var path := DataRepo.fragment_path("jobs_survivor", line)
		if line == "corsair" or not FileAccess.file_exists(path):
			continue
		var frag: Dictionary = DataRepo.load_json(path)
		assert_false(frag.get("jobs", {}).has("522"), "%s names no Corsair job entry" % line)
		assert_false(frag.get("balance", {}).get("player", {}).get("ap", {}).has("522"), "%s has no 522 AP row" % line)
		assert_false(frag.get("balance", {}).get("growth", {}).has("522"), "%s has no 522 growth row" % line)


# --- the job entry ----------------------------------------------------------------------------------------------------

func test_job_522_has_the_spec_fields_and_is_playable() -> void:
	var jobs := _jobs(_data())
	var rec := jobs.job(522)
	assert_eq(String(rec.name), "Corsair")
	assert_eq(jobs.starting_skill(522), "double_shot")
	assert_eq(jobs.mobility_skill(522), "dash")
	assert_eq(Array(jobs.start_skills(522)), ["double_shot", "dash"], "start skills: the starting skill and Dash")
	assert_eq(jobs.skill_pool(522), POOL)
	assert_eq(jobs.skill_pool(522).size(), 13)
	assert_false("dash" in jobs.skill_pool(522), "Dash is the mobility skill, not a pool entry")
	assert_eq(jobs.weapon_families(522), ["gun"])
	assert_eq(jobs.creation_weapon(522), CF.PISTOL)
	assert_true(bool(rec.playable), "C15 flipped playable")
	assert_eq(jobs.job_error(522), "")
	assert_true(522 in jobs.playable_jobs())


func test_the_job_entry_carries_a_hub_kit_and_no_meter() -> void:
	var entry: Dictionary = _data().jobs_survivor.jobs["522"]
	assert_false(entry.has("meter"), "Corsair has no meter: its Form is the ship")
	var kit: Dictionary = entry.hub_kit
	assert_true(kit.fixture is String and kit.scrolls is Array and kit.equipment is Array)
	assert_true(String(kit.fixture) == "" or FileAccess.file_exists(String(kit.fixture)), "the fixture is empty or exists")
	assert_true(int(kit.fallback_item) > 0)
	assert_eq(WeaponInfo.family(int(kit.fallback_item)), "gun", "the diagnostic fallback is a gun")


func test_earlier_jobs_keep_their_entries_unchanged() -> void:
	var jobs := _jobs(_data())
	assert_eq(jobs.starting_skill(212), "energy_bolt")
	assert_eq(jobs.weapon_families(212), ["wand", "staff"])
	assert_eq(jobs.starting_skill(112), "power_strike")
	assert_eq(jobs.mobility_skill(112), "rush_hero")
	assert_eq(jobs.weapon_families(112), ["sword", "axe"])
	assert_eq(jobs.starting_skill(512), "flash_fist")
	assert_eq(jobs.weapon_families(512), ["knuckle"])
	assert_eq(jobs.weapon_families(312), ["bow"])


func test_default_job_stays_212_with_corsair_on_the_line() -> void:
	var data := _data()
	assert_eq(_jobs(data).default_job(), 212)
	assert_true(522 in _jobs(data).playable_jobs(), "shipped playable (C15)")
	assert_eq(_jobs(data).default_job(), 212, "the pin, not the first playable job")


# --- the pool: every key is defined once --------------------------------------------------------------------------------

func test_each_pool_key_and_dash_is_defined_in_at_most_one_file() -> void:
	for key: String in POOL + ["dash"]:
		var lines := _defining_lines(key)
		assert_true(lines.size() <= 1, "%s is defined once at most (%s)" % [key, lines])


func test_every_pool_key_is_defined_in_a_gun_book_in_the_corsair_line() -> void:
	var data := _data()
	for key: String in POOL:
		assert_eq(_defining_lines(key), ["corsair"], "%s is defined in the corsair line" % key)
		var book := String(data.skills.skills[key].book)
		assert_true(book in ["500", "520", "521", "522"], "%s: book %s is a Corsair-lineage book" % [key, book])
	assert_eq(_defining_lines("dash"), ["pirate"], "Dash stays in pirate.json (one definition, Buccaneer and Corsair share it)")


func test_dash_is_not_offered_as_a_card() -> void:
	var setup := RF.setup("quiet", 7, RF.quiet_data())
	setup["job"] = 522
	var w := RunWorld.new(setup)
	var ids := Array(w.upgrades.eligible(w))
	assert_false(ids.has("dash_new") or ids.has("dash_rank"), "Dash is not a card")


func test_a_corsair_round_starts_on_the_default_hp_and_inherits_the_pirate_growth() -> void:
	var data := RF.quiet_data()
	var c_setup := RF.setup("quiet", 7, data)
	c_setup["job"] = 522
	var f_setup := RF.setup("quiet", 7, data)
	f_setup["job"] = 212
	var corsair := RunWorld.new(c_setup)
	var fp := RunWorld.new(f_setup)
	assert_eq(int(corsair.player_state.max_hp), int(fp.player_state.max_hp), "no AP-row hp: the shared starting HP")
	var jobs := _jobs(data)
	assert_eq(jobs.lineage(522), [522, 521, 520, 500, 0] as PackedInt32Array)
	assert_eq(float(data.balance.growth["500"].hp), 25.0, "the 500 row the lineage reaches")


# --- AP row ----------------------------------------------------------------------------------------------------------

func test_the_522_ap_row_copies_the_520_row() -> void:
	var data := _data()
	var row: Dictionary = data.balance.player.ap["522"]
	var gunslinger: Dictionary = data.balance.player.ap["520"]
	assert_eq(String(row.primary), "dex")
	assert_eq(String(row.secondary), "str")
	assert_eq(row.keyframes, [{"level": 1.0, "target": 1.0}, {"level": 200.0, "target": 200.0}])
	assert_eq(row.keyframes, gunslinger.keyframes, "the 520 keyframes verbatim")
	assert_eq(String(row.primary), String(gunslinger.primary))
	assert_eq(String(row.secondary), String(gunslinger.secondary))
	assert_false(row.has("hp"), "no starting-HP override")
	assert_eq(data.balance.player.ap["520"], DataRepo.load_json("res://data/survivor/balance.json").player.ap["520"],
		"the shared 520 row is untouched by the merge")


func test_the_job_fragment_balance_patch_merges_without_disturbing_other_rows() -> void:
	var data := _data()
	var ap: Dictionary = data.balance.player.ap
	for job: String in ["212", "112", "512", "312", "510", "520"]:
		assert_true(ap.has(job), "the %s row survives the merge" % job)
	assert_true(ap.has("522"))
	assert_eq(String(ap["512"].primary), "str", "Buccaneer's row is unchanged")
	assert_eq(String(ap["312"].primary), "dex", "Bowmaster's row is unchanged")


func test_a_corsair_spends_its_auto_ap_on_dex_and_str() -> void:
	var w := RF.quiet_world()
	w.set_job(522)
	var base: Dictionary = w.balance.player.stats
	for lv in 20:
		w._gain_exp(w.progression.exp_to_next())
	var level := int(w.player_state.level)
	var earned := (level - 1) * int(w.balance.player.ap_per_level)
	var row: Dictionary = w.balance.player.ap["522"]
	var str_ap := AutoAp.secondary_ap(earned, level, float(base.str), row.keyframes)
	assert_true(str_ap > 0, "STR takes its share")
	assert_eq(int(w.player_state.str), int(base.str) + str_ap)
	assert_eq(int(w.player_state.dex), int(base.dex) + earned - str_ap, "the rest goes to DEX")


# --- weapon families and drops ----------------------------------------------------------------------------------------

func test_a_corsair_drop_pool_holds_guns_only() -> void:
	var families: Array = _jobs(_data()).weapon_families(522)
	var ids := EquipmentDrops.eligible(INFO.keys(), INFO, 522, BAND, families)
	var weapons := ids.filter(func(id: int) -> bool: return Equipment.slot_of(id) == "weapon")
	weapons.sort()
	assert_eq(weapons, [1492000, 1492005, 1492012], "the guns of the synthetic table")
	assert_true(1002001 in ids, "all-job armour drops")
	assert_true(1082002 in ids, "Pirate-bit armour drops")
	assert_false(1092002 in ids, "the Warrior shield is Warrior-bit gear, never a Corsair's")
	for id: int in NON_GUN_WEAPONS:
		assert_false(id in ids, "%d (%s) never drops for a Corsair" % [id, WeaponInfo.family(id)])


func test_a_seeded_corsair_roll_never_yields_a_non_gun_weapon() -> void:
	var families: Array = _jobs(_data()).weapon_families(522)
	var rng := _rng(386)
	var ids := INFO.keys()
	var seen := {}
	for i in 400:
		var id := EquipmentDrops.pick(ids, INFO, 522, BAND, RULES, rng, families) if i % 2 == 0 \
			else EquipmentDrops.pick_boss(ids, INFO, 522, BAND, RULES, rng, families)
		assert_true(id > 0)
		seen[id] = true
		assert_false(id in NON_GUN_WEAPONS, "%d never drops" % id)
		if Equipment.slot_of(id) == "weapon":
			assert_eq(WeaponInfo.family(id), "gun", "%d" % id)
	for id: int in [1492000, 1492005, 1492012, 1082002, 1002001]:
		assert_true(seen.has(id), "%d dropped in the sample" % id)


## The shipped drop list (every equipment_drops item that is a weapon): the families filter holds on the real ids, not
## only on the synthetic table above. Runs without the cache.
func test_the_shipped_weapon_drops_keep_guns_only_for_a_corsair() -> void:
	var data := _data()
	var weapons: Array = []
	for raw: Variant in data.equipment_drops.items:
		if Equipment.slot_of(int(raw)) == "weapon":
			weapons.append(int(raw))
	assert_false(weapons.is_empty(), "the shipped list has weapons")
	var info := {}
	for id: int in weapons:
		info[id] = {"reqLevel": 0, "reqJob": 16, "tuc": 7}
	var families: Array = _jobs(data).weapon_families(522)
	var ids := EquipmentDrops.eligible(weapons, info, 522, BAND, families)
	var fams := {}
	for id: int in ids:
		fams[WeaponInfo.family(id)] = true
	assert_eq(fams.keys(), ["gun"], "%s" % [fams.keys()])
	var guns := 0
	for id: int in weapons:
		if WeaponInfo.family(id) == "gun":
			assert_true(id in ids, "%d (gun) drops for a Corsair" % id)
			guns += 1
		else:
			assert_false(id in ids, "%d (%s) never drops for a Corsair" % [id, WeaponInfo.family(id)])
	assert_true(guns > 0, "the shipped list holds guns")
	assert_true(CF.PISTOL in weapons, "the creation Pistol is in the shipped list")


func test_requirement_error_accepts_pirate_bit_gear_and_the_pistol_only() -> void:
	var corsair := {"job_id": 522}
	assert_eq(Equipment.requirement_error(INFO[CF.PISTOL], corsair), "", "the Pistol (reqJob 16, the Pirate bit)")
	assert_eq(Equipment.requirement_error(INFO[1082002], corsair), "", "Pirate-bit gloves")
	assert_eq(Equipment.requirement_error({"reqJob": 0}, corsair), "", "all jobs")
	assert_eq(Equipment.requirement_error({"reqJob": 16}, corsair), "", "Pirate bit")
	assert_eq(Equipment.requirement_error(INFO[1302008], corsair), "reqJob", "a Warrior-only sword")
	for bit in [1, 2, 4, 8]:
		assert_eq(Equipment.requirement_error({"reqJob": bit}, corsair), "reqJob", "reqJob %d is another class" % bit)


## Needs the real asset cache (SKIPs without it, which proves nothing).
func test_real_cache_the_pistol_is_wearable_and_each_tier_drops_guns_only() -> void:
	if not require_cache():
		return
	var data := _data()
	var jobs := _jobs(data)
	var lib := AssetLibrary.new()
	lib.open()
	var infos := {}
	var ids: Array = data.equipment_drops.items.duplicate()
	ids.append(jobs.creation_weapon(522))
	for raw: Variant in ids:
		var img := lib.img(AvatarRenderer.part_img_path(int(raw)))
		if img != null:
			infos[int(raw)] = img.root.get("info", {})
	lib.free()
	assert_true(infos.has(CF.PISTOL), "the Pistol is in the cache")
	assert_eq(WeaponInfo.family(CF.PISTOL), "gun")
	assert_eq(Equipment.requirement_error(infos[CF.PISTOL], {"job_id": 522}), "", "a Corsair can wear the creation Pistol")
	var ed: Dictionary = data.equipment_drops
	for tier in data.stages.tiers.size():
		var band := EquipmentDrops.band_of(data.stages, tier)
		var rng := _rng(386 + tier)
		var guns := 0
		for i in 300:
			var id := EquipmentDrops.pick(ed.items, infos, 522, band, ed, rng, jobs.weapon_families(522))
			assert_true(id > 0)
			assert_eq(Equipment.requirement_error(infos[id], {"job_id": 522}), "", "%d is wearable by a Corsair" % id)
			if Equipment.slot_of(id) == "weapon":
				assert_eq(WeaponInfo.family(id), "gun", "%d" % id)
				guns += 1
		assert_true(guns > 0, "tier %d drops guns" % (tier + 1))
