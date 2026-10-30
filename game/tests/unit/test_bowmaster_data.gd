extends TestCase
## Bowmaster's data seam (spec #332, ticket B2 #334): the `bowmaster` data line is discovered from its files, the job entry
## `survivor/jobs/bowmaster.json` (312, playable, NO mobility skill: ruling D1), its AP row, the `default_job` pin, the
## weapon families of its equipment drops (bows only; armour by the Bowman class bit) and the code paths that have never met
## a job without a mobility skill (start skills, the learned skills, the quick slot, Key Config and the bot).
## Seeded RNG and fixed dt; item info is synthetic unless a test says "real cache".

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0

## Synthetic items: id -> info. Bows and crossbows, the other weapon families, Bowman-bit and other classes' gear.
const INFO := {
	1002001: {"reqLevel": 0, "reqJob": 0, "incPDD": 4, "tuc": 7}, # hat, all jobs
	1040002: {"reqLevel": 30, "reqJob": 4, "incPDD": 3, "tuc": 7}, # top, Bowman bit (synthetic)
	1452000: {"reqLevel": 30, "reqJob": 4, "incPAD": 40, "tuc": 7}, # bow
	1452002: {"reqLevel": 30, "reqJob": 4, "incPAD": 25, "tuc": 7}, # War Bow (creation weapon)
	1462000: {"reqLevel": 30, "reqJob": 4, "incPAD": 44, "tuc": 7}, # crossbow
	1462001: {"reqLevel": 30, "reqJob": 4, "incPAD": 29, "tuc": 7}, # crossbow
	1302008: {"reqLevel": 30, "reqJob": 1, "incPAD": 47, "tuc": 7}, # one-handed sword
	1312005: {"reqLevel": 30, "reqJob": 1, "incPAD": 47, "tuc": 7}, # one-handed axe
	1322014: {"reqLevel": 30, "reqJob": 1, "incPAD": 49, "tuc": 7}, # one-handed blunt weapon
	1432002: {"reqLevel": 30, "reqJob": 1, "incPAD": 52, "tuc": 7}, # spear
	1472000: {"reqLevel": 30, "reqJob": 8, "incPAD": 50, "tuc": 7}, # claw
	1492000: {"reqLevel": 30, "reqJob": 4, "incPAD": 52, "tuc": 7}, # gun (synthetic Bowman bit)
	1092002: {"reqLevel": 30, "reqJob": 1, "incPDD": 40, "tuc": 7}, # Warrior shield
	1372004: {"reqLevel": 30, "reqJob": 2, "incPAD": 24, "incMAD": 38, "tuc": 7}, # wand
	1050001: {"reqLevel": 30, "reqJob": 2, "incPDD": 20, "incMDD": 12, "tuc": 10}, # Magician overall
}
const RULES := {"boss_top_parts": 3}
const BAND := [0, 70]
const BOW_WEAPONS := [1452000, 1452002]
const NOT_BOW_WEAPONS := [1462000, 1462001, 1302008, 1312005, 1322014, 1432002, 1472000, 1492000]
const POOL := ["arrow_blow", "bow_double_shot", "arrow_bomb", "strafe", "inferno", "arrow_rain", "dragons_breath",
	"hurricane", "silver_hawk", "phoenix"]


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


## A quiet world that starts a round of job `job_id` (its own start skills), without making the job playable.
func _world(job_id: int, p_seed := 334) -> RunWorld:
	var setup := RF.setup("quiet", p_seed, RF.quiet_data())
	setup["job"] = job_id
	var w := RunWorld.new(setup)
	RF.place_player(w, 400)
	return w


# --- the line ---------------------------------------------------------------------------------------------------------

func test_bowmaster_line_is_discovered_without_a_shared_registration() -> void:
	assert_true("bowmaster" in DataRepo.lines())
	assert_eq(DataRepo.fragment_path("jobs_survivor", "bowmaster", "res://data"),
		"res://data/survivor/jobs/bowmaster.json")
	assert_eq(DataRepo.fragment_path("skills", "bowmaster", "res://data"), "res://data/survivor/skills/bowmaster.json")


func test_class_lines_follow_the_adventurers_in_registration_order() -> void:
	# CLASS_LINES is append-only (ARCHITECTURE 4.4.4): Hero, I/L, then Bowmaster, all after the seven Adventurers; the unregistered
	# Bishop and the later classes retain their subsequent registration order.
	var lines := DataRepo.lines()
	assert_eq(Array(lines.slice(0, 7)), ["common", "beginner", "warrior", "magician", "bowman", "thief", "pirate"])
	assert_eq(Array(lines.slice(7)), ["hero", "il_arch_mage", "bowmaster", "bishop", "paladin", "dark_knight", "buccaneer"])


func test_the_bowmaster_line_loads_without_errors_and_adds_its_job_and_its_skills() -> void:
	var errors := PackedStringArray()
	var d := DataRepo.load_all(DataRepo.DATA_ROOT, errors)
	assert_true(errors.is_empty(), "%s" % [errors])
	assert_true(d.jobs_survivor.jobs.has("312"), "jobs/bowmaster.json is merged into the survivor job data")
	var frag: Dictionary = DataRepo.load_json(DataRepo.fragment_path("skills", "bowmaster"))
	for key: String in frag.skills:
		assert_true(key in POOL, "%s: every key in the fragment is a pool skill" % key)
	assert_true(frag.has("_doc"))
	assert_eq(Array(DataRepo.unknown_line_files()), [])


# --- the job entry ----------------------------------------------------------------------------------------------------

func test_job_312_has_the_spec_fields_and_is_playable() -> void:
	var jobs := _jobs(_data())
	var rec := jobs.job(312)
	assert_eq(String(rec.name), "Bowmaster")
	assert_eq(jobs.starting_skill(312), "arrow_blow")
	assert_eq(jobs.skill_pool(312), POOL)
	assert_eq(jobs.skill_pool(312).size(), 10)
	assert_eq(jobs.weapon_families(312), ["bow"])
	assert_eq(jobs.creation_weapon(312), 1452002)
	assert_true(bool(rec.playable), "Bowmaster is selectable")
	assert_eq(jobs.job_error(312), "")
	assert_eq(jobs.playable_jobs(), [112, 122, 132, 212, 222, 232, 312, 512] as Array[int], "all eight playable jobs")


func test_job_312_declares_no_mobility_skill_key() -> void:
	# D1: the raw entry has no `mobility_skill` key at all, so no lineage or default can supply one.
	var raw: Dictionary = DataRepo.load_json(DataRepo.fragment_path("jobs_survivor", "bowmaster")).jobs["312"]
	assert_false(raw.has("mobility_skill"), "no mobility_skill key (D1)")
	assert_true(raw.has("starting_skill"))
	assert_eq(_jobs(_data()).mobility_skill(312), "")


func test_pool_keys_that_are_defined_belong_to_the_bowman_books() -> void:
	# Each Bowmaster ticket (B7-B11) defines its own keys; an undefined key stays inert, a defined one is a 300-312 skill.
	var defined: Dictionary = _data().skills.skills
	for key: String in POOL:
		if defined.has(key):
			assert_true(int(defined[key].job) in [300, 310, 311, 312], "%s belongs to a Bowman book" % key)


func test_212_and_112_keep_their_entries_unchanged() -> void:
	var jobs := _jobs(_data())
	assert_eq(jobs.starting_skill(212), "energy_bolt")
	assert_eq(jobs.mobility_skill(212), "teleport_fp")
	assert_eq(jobs.starting_skill(112), "power_strike")
	assert_eq(jobs.mobility_skill(112), "rush_hero")


# --- AP row and default job -------------------------------------------------------------------------------------------

func test_the_312_ap_row_is_dex_primary_str_secondary_with_the_300_keyframes_verbatim() -> void:
	var data := _data()
	var row: Dictionary = data.balance.player.ap["312"]
	assert_eq([String(row.primary), String(row.secondary)], ["dex", "str"])
	assert_eq(row.keyframes, data.balance.player.ap["300"].keyframes, "copied verbatim from the Bowman row")
	assert_eq(row.keyframes, [
		{"level": 1.0, "target": 6.0}, {"level": 30.0, "target": 35.0}, {"level": 34.0, "target": 35.0},
		{"level": 35.0, "target": 40.0}, {"level": 70.0, "target": 75.0}])


func test_the_312_ap_row_lives_in_its_own_line_and_not_in_the_shared_balance() -> void:
	var raw: Dictionary = DataRepo.load_json(DataRepo.fragment_path("jobs_survivor", "bowmaster"))
	assert_true(raw.balance.player.ap.has("312"), "the row is class-owned (ARCHITECTURE 4.4.4)")
	var shared: Dictionary = DataRepo.load_json("res://data/survivor/balance.json")
	assert_false(shared.player.ap.has("312"), "no shared row for Bowmaster")


func test_default_job_is_still_212_with_bowmaster_loaded() -> void:
	var data := _data()
	assert_eq(int(data.jobs_survivor.default_job), 212)
	assert_eq(_jobs(data).default_job(), 212)


func test_default_job_stays_212_even_if_bowmaster_became_playable() -> void:
	var data := _data()
	data.jobs_survivor.jobs["312"]["playable"] = true
	var jobs := _jobs(data)
	assert_eq(jobs.playable_jobs(), [112, 122, 132, 212, 222, 232, 312, 512] as Array[int], "canonical order of all eight playable jobs")
	assert_eq(jobs.default_job(), 212, "the pin, not the first playable job")
	assert_eq(jobs.job_error(312), "")


# --- drops: bows only -------------------------------------------------------------------------------------------------

func test_a_bowmaster_drop_pool_holds_only_bows_and_bowman_armour() -> void:
	var families: Array = _jobs(_data()).weapon_families(312)
	var ids := EquipmentDrops.eligible(_ids(), INFO, 312, BAND, families)
	var weapons := ids.filter(func(id: int) -> bool: return Equipment.slot_of(id) == "weapon")
	weapons.sort()
	var want := BOW_WEAPONS.duplicate()
	want.sort()
	assert_eq(weapons, want, "bows, never crossbows, swords, axes, blunt weapons, spears, claws or guns (the gun is Bowman-bit here)")
	assert_true(1040002 in ids, "Bowman-bit armour drops")
	assert_true(1002001 in ids, "all-job armour drops")
	assert_false(1092002 in ids or 1050001 in ids, "Warrior and Magician gear never drops for a Bowmaster")


func test_a_seeded_bowmaster_roll_sample_never_yields_another_weapon_family() -> void:
	var families: Array = _jobs(_data()).weapon_families(312)
	var rng := _rng(334)
	var seen := {}
	for i in 400:
		var id := EquipmentDrops.pick(_ids(), INFO, 312, BAND, RULES, rng, families) if i % 2 == 0 \
			else EquipmentDrops.pick_boss(_ids(), INFO, 312, BAND, RULES, rng, families)
		assert_true(id > 0)
		seen[id] = true
		for other: int in NOT_BOW_WEAPONS:
			assert_false(id == other, "%d is another family" % id)
		if Equipment.slot_of(id) == "weapon":
			assert_eq(WeaponInfo.family(id), "bow", "%d" % id)
	for id: int in BOW_WEAPONS:
		assert_true(seen.has(id), "%d dropped in the sample" % id)


func test_requirement_error_accepts_bowman_bit_gear_only() -> void:
	var bowmaster := {"job_id": 312}
	assert_eq(Equipment.requirement_error({"reqJob": 4}, bowmaster), "", "Bowman bit")
	assert_eq(Equipment.requirement_error({"reqJob": 0}, bowmaster), "", "all jobs")
	assert_eq(Equipment.requirement_error({"reqJob": 5}, bowmaster), "", "Warrior and Bowman")
	for bit in [1, 2, 8, 16]:
		assert_eq(Equipment.requirement_error({"reqJob": bit}, bowmaster), "reqJob", "reqJob %d is another class" % bit)
	for id: int in BOW_WEAPONS:
		assert_eq(Equipment.requirement_error(INFO[id], bowmaster), "", "%d is Bowman gear" % id)
	for id: int in [1302008, 1472000, 1092002, 1372004]:
		assert_eq(Equipment.requirement_error(INFO[id], bowmaster), "reqJob", "%d is another class's gear" % id)
	assert_eq(Equipment.requirement_error({"reqJob": 4}, {"job_id": 212}), "reqJob", "and a 212 cannot wear it")


## Needs the real asset cache (SKIPs without it, which proves nothing).
func test_real_cache_the_war_bow_is_wearable_and_the_shipped_pool_holds_only_bows() -> void:
	if not require_cache():
		return
	var data := _data()
	var jobs := _jobs(data)
	var lib := AssetLibrary.new()
	lib.open()
	var infos := {}
	var ids: Array = data.equipment_drops.items.duplicate()
	ids.append(jobs.creation_weapon(312))
	for raw: Variant in ids:
		var img := lib.img(AvatarRenderer.part_img_path(int(raw)))
		if img != null:
			infos[int(raw)] = img.root.get("info", {})
	lib.free()
	var war_bow := jobs.creation_weapon(312)
	assert_eq(war_bow, 1452002)
	assert_true(infos.has(war_bow), "the War Bow is in the cache")
	assert_eq(WeaponInfo.family(war_bow), "bow")
	assert_eq(Equipment.requirement_error(infos[war_bow], {"job_id": 312}), "", "the creation weapon is wearable")
	var ed: Dictionary = data.equipment_drops
	for tier in data.stages.tiers.size():
		var band := EquipmentDrops.band_of(data.stages, tier)
		var families := {}
		var rng := _rng(334 + tier)
		for i in 300:
			var id := EquipmentDrops.pick(ed.items, infos, 312, band, ed, rng, jobs.weapon_families(312))
			assert_true(id > 0)
			assert_eq(Equipment.requirement_error(infos[id], {"job_id": 312}), "", "%d is wearable by a Bowmaster" % id)
			if Equipment.slot_of(id) == "weapon":
				families[WeaponInfo.family(id)] = true
		assert_eq(families.keys(), ["bow"], "tier %d: bows only" % (tier + 1))


# --- a job with no mobility skill -------------------------------------------------------------------------------------

func test_a_round_starts_with_arrow_blow_and_nothing_else() -> void:
	var jobs := _jobs(_data())
	assert_eq(Array(jobs.start_skills(312)), ["arrow_blow"], "no mobility skill to learn")
	var w := _world(312)
	assert_eq(w.job_id(), 312)
	assert_eq(Array(w.loadout.order), ["arrow_blow"])


func test_no_manual_skill_key_or_quick_slot_movement_cell_is_offered() -> void:
	var w := _world(312)
	var keys := w.manual_skill_keys()
	assert_eq(keys, [], "no skill key: Key Config and the quick slot list nothing")
	assert_eq(HudQuickSlot.movement_skill_of(keys), {}, "the movement cell is empty")
	var cells := HudQuickSlot.cells({}, {}, HudQuickSlot.movement_skill_of(keys))
	var movement: Dictionary = cells[HudQuickSlot.ORDER.find(HudQuickSlot.MOVEMENT)]
	assert_eq(String(movement.action), "", "the movement cell has no action")
	assert_eq(String(movement.icon_path), "", "and no icon")
	for cell: Dictionary in cells:
		assert_false(String(cell.action) in ["teleport", "dash", "rush"], "no movement action in any cell")


func test_key_config_lists_no_skill_row_for_a_bowmaster() -> void:
	var w := _world(312)
	var settings := GameSettings.new("user://bowmaster_key_config_test.cfg")
	var bindings := KeyBindings.from_settings(settings, w.manual_skill_keys().map(
		func(k: Dictionary) -> String: return String(k.action)))
	assert_eq(bindings.skill_keys.size(), 0)
	for action: String in ["teleport", "dash", "rush"]:
		assert_false(bindings.actions().has(action), "%s is not listed" % action)
	settings.free()


func test_the_bot_never_presses_a_skill_key_for_a_bowmaster() -> void:
	var w := _world(312, 335)
	w.god = true
	RF.put_mob(w, 100100, 300)
	RF.put_mob(w, 100101, 340)
	RF.put_mob(w, 120100, 520)
	var memo := {}
	var pressed := 0
	var casts := 0
	for i in 60 * 12:
		var mi := BotInput.decide(w, memo)
		pressed += mi.skills_pressed.size() + mi.skills_held.size()
		w.step(DT, mi)
		for e: Dictionary in w.drain_events():
			if e.type == "cast":
				casts += 1
	assert_eq(pressed, 0, "no skill key press in 12 seconds of bot play")
	assert_true(casts > 0, "the bot did fight: its auto-cast Arrow Blow fired (%d casts)" % casts)


func test_a_run_scene_of_a_bowmaster_reports_arrow_blow_and_no_movement_skill() -> void:
	var scene := RunScene.new()
	scene.world = _world(312)
	var info := scene.run_info()
	assert_eq(info.movement_skill, {}, "the HUD's movement cell is empty")
	assert_eq(info.skills.size(), 1, "Arrow Blow is the only owned skill")
	assert_eq(String(info.skills[0].icon), String(scene.world.book.def("arrow_blow").get("icon", "")))
	scene.free()
