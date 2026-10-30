extends TestCase
## Marksman's data seam (spec #360, ticket MS2 #362): the `marksman` data line is discovered from its files, the job entry
## `survivor/jobs/marksman.json` (322, not playable yet, NO mobility skill: ruling D1), its AP row and bot card scores, the
## `default_job` pin, the weapon families of its equipment drops (crossbows only; armour by the Bowman class bit), the code
## paths that have never met a job without a mobility skill (start skills, the quick slot, Key Config, the bot) and the
## crossbow ammo schedule that Bowmaster's B3 already wrote (verified here, not rewritten).
## Seeded RNG and fixed dt; item info is synthetic unless a test says "real cache".

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0

## Synthetic items: id -> info. Crossbows and bows, the other weapon families, Bowman-bit and other classes' gear.
const INFO := {
	1002001: {"reqLevel": 0, "reqJob": 0, "incPDD": 4, "tuc": 7}, # hat, all jobs
	1040002: {"reqLevel": 30, "reqJob": 4, "incPDD": 3, "tuc": 7}, # top, Bowman bit (synthetic)
	1462000: {"reqLevel": 30, "reqJob": 4, "incPAD": 44, "tuc": 7}, # crossbow
	1462001: {"reqLevel": 12, "reqJob": 4, "incPAD": 29, "tuc": 7}, # crossbow (creation weapon)
	1452000: {"reqLevel": 30, "reqJob": 4, "incPAD": 40, "tuc": 7}, # bow
	1452002: {"reqLevel": 30, "reqJob": 4, "incPAD": 25, "tuc": 7}, # War Bow
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
const CROSSBOW_WEAPONS := [1462000, 1462001]
const NOT_CROSSBOW_WEAPONS := [1452000, 1452002, 1302008, 1312005, 1322014, 1432002, 1472000, 1492000]
const POOL := ["iron_arrow", "arrow_blow", "strafe_crossbow", "dragons_breath_crossbow", "blizzard_crossbow",
	"arrow_eruption", "piercing_arrow", "snipe", "golden_eagle", "frostprey"]
const OWN_KEYS := ["iron_arrow", "strafe_crossbow", "dragons_breath_crossbow", "blizzard_crossbow", "arrow_eruption",
	"piercing_arrow", "snipe", "golden_eagle", "frostprey"]
const BOW := 1452051
const CROSSBOW := 1462001


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
func _world(job_id: int, p_seed := 362) -> RunWorld:
	var setup := RF.setup("quiet", p_seed, RF.quiet_data())
	setup["job"] = job_id
	var w := RunWorld.new(setup)
	RF.place_player(w, 400)
	return w


# --- the line ---------------------------------------------------------------------------------------------------------

func test_marksman_line_is_discovered_without_a_shared_registration() -> void:
	assert_true("marksman" in DataRepo.lines())
	assert_false("marksman" in DataRepo.CLASS_LINES, "discovered from its files; no shared list was edited")
	assert_eq(DataRepo.fragment_path("jobs_survivor", "marksman", "res://data"), "res://data/survivor/jobs/marksman.json")
	assert_eq(DataRepo.fragment_path("skills", "marksman", "res://data"), "res://data/survivor/skills/marksman.json")


func test_marksman_follows_the_registered_classes_in_the_shipped_order() -> void:
	var lines := Array(DataRepo.lines())
	assert_eq(lines.slice(0, 7), ["common", "beginner", "warrior", "magician", "bowman", "thief", "pirate"])
	assert_true(lines.find("marksman") > lines.find("bowmaster"), "after the registered class lines")
	assert_eq(lines.slice(7), ["hero", "il_arch_mage", "bowmaster", "bishop", "paladin", "dark_knight", "buccaneer", "marksman"])


func test_the_marksman_line_loads_without_errors_and_adds_its_job_and_only_crossbowman_books() -> void:
	var errors := PackedStringArray()
	var d := DataRepo.load_all(DataRepo.DATA_ROOT, errors)
	assert_true(errors.is_empty(), "%s" % [errors])
	assert_true(d.jobs_survivor.jobs.has("322"), "jobs/marksman.json is merged into the survivor job data")
	var frag: Dictionary = DataRepo.load_json(DataRepo.fragment_path("skills", "marksman"))
	assert_true(frag.has("_doc"))
	for key: String in frag.skills:
		assert_true(key in OWN_KEYS, "%s: every key in the fragment is a Marksman pool skill (arrow_blow is Bowmaster's)" % key)
		assert_true(String(frag.skills[key].book) in ["320", "321", "322"], "%s is in a Crossbowman book" % key)
	assert_eq(Array(DataRepo.unknown_line_files()), [])


# --- the job entry ----------------------------------------------------------------------------------------------------

func test_job_322_has_the_spec_fields_and_is_not_playable_yet() -> void:
	var jobs := _jobs(_data())
	var rec := jobs.job(322)
	assert_eq(String(rec.name), "Marksman")
	assert_eq(jobs.starting_skill(322), "iron_arrow")
	assert_eq(jobs.skill_pool(322), POOL)
	assert_eq(jobs.skill_pool(322).size(), 10)
	assert_eq(jobs.weapon_families(322), ["crossbow"])
	assert_eq(jobs.creation_weapon(322), 1462001)
	assert_false(bool(rec.playable), "Marksman is not selectable until MS11")
	assert_false(322 in jobs.playable_jobs())
	assert_ne(jobs.job_error(322), "", "forcing --job=322 is refused while playable is false")


func test_job_322_declares_no_mobility_skill_key() -> void:
	# D1: the raw entry has no `mobility_skill` key at all, so no lineage or default can supply one.
	var raw: Dictionary = DataRepo.load_json(DataRepo.fragment_path("jobs_survivor", "marksman")).jobs["322"]
	assert_false(raw.has("mobility_skill"), "no mobility_skill key (D1)")
	assert_true(raw.has("starting_skill"))
	assert_eq(_jobs(_data()).mobility_skill(322), "")


func test_pool_keys_that_are_defined_belong_to_the_crossbowman_or_shared_archer_books() -> void:
	# Each Marksman ticket (MS5-MS9) defines its own keys; an undefined key stays inert, a defined one is a 300-322 skill.
	var defined: Dictionary = _data().skills.skills
	for key: String in POOL:
		if defined.has(key):
			assert_true(int(defined[key].job) in [300, 320, 321, 322], "%s belongs to a Crossbowman book" % key)


func test_no_pool_key_is_defined_in_two_files() -> void:
	# A repeated skill key across line files is a load error; iron_arrow moves from bowman.json in MS5, never copies.
	var seen := {}
	for line: String in DataRepo.lines():
		var frag: Dictionary = DataRepo.load_json(DataRepo.fragment_path("skills", line))
		for key: String in frag.get("skills", {}):
			assert_false(seen.has(key), "%s defined in %s and %s" % [key, seen.get(key, ""), line])
			seen[key] = line


func test_the_other_jobs_keep_their_entries_unchanged() -> void:
	var jobs := _jobs(_data())
	assert_eq(jobs.starting_skill(212), "energy_bolt")
	assert_eq(jobs.mobility_skill(212), "teleport_fp")
	assert_eq(jobs.starting_skill(112), "power_strike")
	assert_eq(jobs.mobility_skill(112), "rush_hero")
	assert_eq(jobs.starting_skill(312), "arrow_blow")
	assert_eq(jobs.skill_pool(312).size(), 10, "Bowmaster's pool is unchanged")
	assert_eq(jobs.weapon_families(312), ["bow"])


# --- AP row, bot scores and default job -------------------------------------------------------------------------------

func test_the_322_ap_row_is_dex_primary_str_secondary_with_the_300_keyframes_verbatim() -> void:
	var data := _data()
	var row: Dictionary = data.balance.player.ap["322"]
	assert_eq([String(row.primary), String(row.secondary)], ["dex", "str"])
	assert_eq(row.keyframes, data.balance.player.ap["300"].keyframes, "copied verbatim from the Bowman row")
	assert_eq(row.keyframes, [
		{"level": 1.0, "target": 6.0}, {"level": 30.0, "target": 35.0}, {"level": 34.0, "target": 35.0},
		{"level": 35.0, "target": 40.0}, {"level": 70.0, "target": 75.0}])


func test_the_ap_row_and_card_scores_live_in_the_line_file_and_not_in_the_shared_balance() -> void:
	var raw: Dictionary = DataRepo.load_json(DataRepo.fragment_path("jobs_survivor", "marksman"))
	assert_true(raw.balance.player.ap.has("322"), "the row is class-owned (ARCHITECTURE 4.4.4)")
	assert_true(raw.balance.bot.card_scores.has("golden_eagle_new"))
	var shared: Dictionary = DataRepo.load_json("res://data/survivor/balance.json")
	assert_false(shared.player.ap.has("322"), "no shared AP row for Marksman")
	for key: String in raw.balance.bot.card_scores:
		assert_false(shared.get("bot", {}).get("card_scores", {}).has(key), "%s is not in the shared balance" % key)


func test_the_followers_score_explicitly_and_so_does_every_other_pool_skill_since_ms10() -> void:
	var data := _data()
	var scores: Dictionary = data.balance.bot.card_scores
	for key in ["golden_eagle", "frostprey"]:
		assert_eq(float(scores[key + "_new"]), 100.0, "%s learn card" % key)
		assert_eq(float(scores[key + "_rank"]), 74.0, "%s rank card" % key)
	var own: Dictionary = DataRepo.load_json(DataRepo.fragment_path("jobs_survivor", "marksman")).balance.bot.card_scores
	assert_eq(own.keys().size(), 20, "MS10 #370 lists all ten pool skills, new and rank (MS2 listed only the two summons)")
	for key: String in _jobs(data).skill_pool(322):
		assert_eq(float(own[key + "_new"]), 100.0, key)
		assert_eq(float(own[key + "_rank"]), 74.0, key)


func test_default_job_is_still_212_with_marksman_loaded() -> void:
	var data := _data()
	assert_eq(int(data.jobs_survivor.default_job), 212)
	assert_eq(_jobs(data).default_job(), 212)


func test_default_job_stays_212_even_if_marksman_became_playable() -> void:
	var data := _data()
	data.jobs_survivor.jobs["322"]["playable"] = true
	var jobs := _jobs(data)
	assert_true(322 in jobs.playable_jobs())
	assert_eq(jobs.default_job(), 212, "the pin, not the first playable job")
	assert_eq(jobs.job_error(322), "")


# --- drops: crossbows only --------------------------------------------------------------------------------------------

func test_a_marksman_drop_pool_holds_only_crossbows_and_bowman_armour() -> void:
	var families: Array = _jobs(_data()).weapon_families(322)
	var ids := EquipmentDrops.eligible(_ids(), INFO, 322, BAND, families)
	var weapons := ids.filter(func(id: int) -> bool: return Equipment.slot_of(id) == "weapon")
	weapons.sort()
	var want := CROSSBOW_WEAPONS.duplicate()
	want.sort()
	assert_eq(weapons, want, "crossbows, never bows, swords, axes, blunt weapons, spears, claws or guns")
	assert_true(1040002 in ids, "Bowman-bit armour drops")
	assert_true(1002001 in ids, "all-job armour drops")
	assert_false(1092002 in ids or 1050001 in ids, "Warrior and Magician gear never drops for a Marksman")


func test_a_bowmaster_pool_never_holds_a_crossbow() -> void:
	var families: Array = _jobs(_data()).weapon_families(312)
	var ids := EquipmentDrops.eligible(_ids(), INFO, 312, BAND, families)
	for id: int in ids:
		assert_false(id in CROSSBOW_WEAPONS, "%d is a crossbow" % id)
	assert_true(1452000 in ids and 1452002 in ids, "Bowmaster still drops bows")


func test_a_seeded_marksman_roll_sample_never_yields_another_weapon_family() -> void:
	var families: Array = _jobs(_data()).weapon_families(322)
	var rng := _rng(362)
	var seen := {}
	for i in 400:
		var id := EquipmentDrops.pick(_ids(), INFO, 322, BAND, RULES, rng, families) if i % 2 == 0 \
			else EquipmentDrops.pick_boss(_ids(), INFO, 322, BAND, RULES, rng, families)
		assert_true(id > 0)
		seen[id] = true
		for other: int in NOT_CROSSBOW_WEAPONS:
			assert_false(id == other, "%d is another family" % id)
		if Equipment.slot_of(id) == "weapon":
			assert_eq(WeaponInfo.family(id), "crossbow", "%d" % id)
	for id: int in CROSSBOW_WEAPONS:
		assert_true(seen.has(id), "%d dropped in the sample" % id)


func test_requirement_error_accepts_bowman_bit_gear_only() -> void:
	var marksman := {"job_id": 322}
	assert_eq(Equipment.requirement_error({"reqJob": 4}, marksman), "", "Bowman bit")
	assert_eq(Equipment.requirement_error({"reqJob": 0}, marksman), "", "all jobs")
	assert_eq(Equipment.requirement_error({"reqJob": 5}, marksman), "", "Warrior and Bowman")
	for bit in [1, 2, 8, 16]:
		assert_eq(Equipment.requirement_error({"reqJob": bit}, marksman), "reqJob", "reqJob %d is another class" % bit)
	for id: int in CROSSBOW_WEAPONS:
		assert_eq(Equipment.requirement_error(INFO[id], marksman), "", "%d is Bowman gear" % id)
	for id: int in [1302008, 1472000, 1092002, 1372004]:
		assert_eq(Equipment.requirement_error(INFO[id], marksman), "reqJob", "%d is another class's gear" % id)
	assert_eq(Equipment.requirement_error({"reqJob": 4}, {"job_id": 212}), "reqJob", "and a 212 cannot wear it")


func test_the_creation_crossbow_is_wearable_with_the_level_requirement_no_longer_enforced() -> void:
	# The Crossbow 1462001 has reqLevel 12 in Item.wz; #292 dropped level requirements, so a Lv1 Marksman wears it.
	var jobs := _jobs(_data())
	assert_eq(WeaponInfo.family(jobs.creation_weapon(322)), "crossbow")
	assert_eq(Equipment.requirement_error(INFO[1462001], {"job_id": 322, "level": 1}), "")
	var w := _world(322)
	w.setup.equipment_info.merge({CROSSBOW: {"incPAD": 29, "attackSpeed": 6, "reqJob": 4, "reqLevel": 12, "tuc": 7}}, true)
	assert_eq(w.wear_new_item(CROSSBOW), "")


## Needs the real asset cache (SKIPs without it, which proves nothing).
func test_real_cache_the_crossbow_is_wearable_and_the_shipped_pool_holds_only_crossbows() -> void:
	if not require_cache():
		return
	var data := _data()
	var jobs := _jobs(data)
	var lib := AssetLibrary.new()
	lib.open()
	var infos := {}
	var ids: Array = data.equipment_drops.items.duplicate()
	ids.append(jobs.creation_weapon(322))
	for raw: Variant in ids:
		var img := lib.img(AvatarRenderer.part_img_path(int(raw)))
		if img != null:
			infos[int(raw)] = img.root.get("info", {})
	lib.free()
	var crossbow := jobs.creation_weapon(322)
	assert_eq(crossbow, 1462001)
	assert_true(infos.has(crossbow), "the Crossbow is in the cache")
	assert_eq(WeaponInfo.family(crossbow), "crossbow")
	assert_eq(Equipment.requirement_error(infos[crossbow], {"job_id": 322}), "", "the creation weapon is wearable")
	var ed: Dictionary = data.equipment_drops
	for tier in data.stages.tiers.size():
		var band := EquipmentDrops.band_of(data.stages, tier)
		var families := {}
		var rng := _rng(362 + tier)
		for i in 300:
			var id := EquipmentDrops.pick(ed.items, infos, 322, band, ed, rng, jobs.weapon_families(322))
			assert_true(id > 0)
			assert_eq(Equipment.requirement_error(infos[id], {"job_id": 322}), "", "%d is wearable by a Marksman" % id)
			if Equipment.slot_of(id) == "weapon":
				families[WeaponInfo.family(id)] = true
		assert_eq(families.keys(), ["crossbow"], "tier %d: crossbows only" % (tier + 1))


# --- a job with no mobility skill -------------------------------------------------------------------------------------

func test_a_round_starts_with_iron_arrow_and_nothing_else() -> void:
	var jobs := _jobs(_data())
	assert_eq(Array(jobs.start_skills(322)), ["iron_arrow"], "no mobility skill to learn")
	var w := _world(322)
	assert_eq(w.job_id(), 322)
	assert_eq(Array(w.loadout.order), ["iron_arrow"])


func test_no_manual_skill_key_or_quick_slot_movement_cell_is_offered() -> void:
	var w := _world(322)
	var keys := w.manual_skill_keys()
	assert_eq(keys, [], "no skill key: Key Config and the quick slot list nothing")
	assert_eq(HudQuickSlot.movement_skill_of(keys), {}, "the movement cell is empty")
	var cells := HudQuickSlot.cells({}, {}, HudQuickSlot.movement_skill_of(keys))
	var movement: Dictionary = cells[HudQuickSlot.ORDER.find(HudQuickSlot.MOVEMENT)]
	assert_eq(String(movement.action), "", "the movement cell has no action")
	assert_eq(String(movement.icon_path), "", "and no icon")
	for cell: Dictionary in cells:
		assert_false(String(cell.action) in ["teleport", "dash", "rush"], "no movement action in any cell")


func test_key_config_lists_no_skill_row_for_a_marksman() -> void:
	var w := _world(322)
	var settings := GameSettings.new("user://marksman_key_config_test.cfg")
	var bindings := KeyBindings.from_settings(settings, w.manual_skill_keys().map(
		func(k: Dictionary) -> String: return String(k.action)))
	assert_eq(bindings.skill_keys.size(), 0)
	for action: String in ["teleport", "dash", "rush"]:
		assert_false(bindings.actions().has(action), "%s is not listed" % action)
	settings.free()


func test_the_bot_never_presses_a_skill_key_for_a_marksman() -> void:
	var w := _world(322, 363)
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
	assert_true(casts > 0, "the bot did fight: its auto-cast Iron Arrow fired (%d casts)" % casts)


func test_a_run_scene_of_a_marksman_reports_iron_arrow_and_no_movement_skill() -> void:
	var scene := RunScene.new()
	scene.world = _world(322)
	var info := scene.run_info()
	assert_eq(info.movement_skill, {}, "the HUD's movement cell is empty")
	assert_eq(info.skills.size(), 1, "Iron Arrow is the only owned skill")
	assert_eq(String(info.skills[0].icon), String(scene.world.book.def("iron_arrow").get("icon", "")))
	scene.free()


# --- ammo (D9): the 322 schedule Bowmaster's B3 wrote -----------------------------------------------------------------

## A quiet world holding both a bow and a crossbow, the crossbow worn, as job `job`.
func _ammo_world(job := 322) -> RunWorld:
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["212"]["starting_skill"] = ""; data.jobs_survivor.jobs["212"]["mobility_skill"] = ""
	var setup := RF.with_basic_attack(RF.setup("quiet", 362, data))
	setup.equipment_info.merge({BOW: {"incPAD": 28, "attackSpeed": 6, "tuc": 7},
		CROSSBOW: {"incPAD": 29, "attackSpeed": 6, "tuc": 7}}, true)
	for action: String in ["shoot1", "shoot2"]:
		setup.body_img[action] = {"0": {"delay": 100.0}, "1": {"delay": 100.0}}
	var w := RunWorld.new(setup)
	assert_eq(w.wear_new_item(CROSSBOW), "")
	assert_eq(w.wear_new_item(BOW), "")
	assert_eq(w.equip_item(_item_ids(w).find(CROSSBOW)), "")
	RF.place_player(w, 400)
	for mk: MobKind in w.mob_kinds:
		mk.hitbox = Rect2(-2, -10, 4, 10)
		mk.move_speed = 0
	w.player.facing = 1
	w.god = true
	w.pending_cards = []
	w.state = RunWorld.PLAYING
	RF.change_job_bare(w, job)
	w.drain_events()
	return w


func _item_ids(w: RunWorld) -> Array:
	return w.equipment.inventory.map(func(item: Dictionary) -> int: return int(item.id))


func _upgrades(w: RunWorld) -> Array:
	return w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "ammo_upgraded")


## Plays the round to `level` with real EXP drops (the ordinary level-up path), collecting every ammo_upgraded.
func _level_to(w: RunWorld, level: int, notices: Array) -> void:
	while w.progression.level < level:
		w.pickups.spawn(w.player.pos, w.progression.exp_to_next(), 4000019)
		for tick in 120:
			w.step(DT, MoveInput.new())
			BotInput.auto_choose(w, false)
		notices.append_array(_upgrades(w))


func test_a_marksman_round_starts_on_the_plain_crossbow_arrow_and_announces_nothing() -> void:
	var w := _ammo_world()
	assert_eq(w.progression.level, 1)
	assert_eq(w.ammo_id(), 2061000, "Arrow for Crossbow at Lv1")
	assert_eq(w.ammo_attack(), 0.0)
	for tick in 30:
		w.step(DT, MoveInput.new())
	assert_eq(_upgrades(w).size(), 0, "no notice at the start of the round")


func test_the_crossbow_arrows_step_at_15_30_and_45_with_exactly_one_notice_each() -> void:
	var w := _ammo_world()
	var notices: Array = []
	_level_to(w, 14, notices)
	assert_eq(w.ammo_id(), 2061000)
	assert_eq(notices.size(), 0, "nothing before Lv15")
	_level_to(w, 45, notices)
	assert_eq(notices.size(), 3, "Bronze, Steel and Blue: one notice per step, no repeats")
	var want := [[15, 2061000, 2061001], [30, 2061001, 2061002], [45, 2061002, 2061003]]
	for i in mini(notices.size(), want.size()):
		assert_eq(notices[i].level, want[i][0], "the step's own round level")
		assert_eq(notices[i].from_item_id, want[i][1])
		assert_eq(notices[i].item_id, want[i][2])
		assert_eq(notices[i].family, "crossbow")
	assert_eq(w.ammo_id(), 2061003, "Blue Arrow for Crossbow at Lv45")


func test_each_step_is_announced_exactly_once_when_the_level_changes() -> void:
	var w := _ammo_world()
	for row: Array in [[14, 2061000, 0], [15, 2061001, 1], [29, 2061001, 0], [30, 2061002, 1], [44, 2061002, 0],
			[45, 2061003, 1]]:
		w.progression.level = row[0]
		w.refresh_player_stats()
		assert_eq(w.ammo_id(), row[1], "Lv %d" % row[0])
		assert_eq(_upgrades(w).size(), row[2], "Lv %d notices" % row[0])
		w.refresh_player_stats()
		assert_eq(_upgrades(w).size(), 0, "a second refresh at Lv %d announces nothing" % row[0])


func test_the_notice_text_names_the_new_crossbow_arrow() -> void:
	assert_eq(Ammo.notice(Ammo.noun(_data().ammo, "crossbow"), "Bronze Arrow for Crossbow"),
		"Your arrows are now Bronze Arrow for Crossbow")


func test_the_incpad_of_the_current_arrow_adds_to_ranged_attack_only() -> void:
	var w := _ammo_world()
	w.setup.ammo_info = RF.ammo_info()
	var plain := w.weapon_attack(true)
	assert_eq(w.weapon_attack(false), plain, "the Lv1 arrow adds +0")
	for row: Array in [[15, 1.0], [30, 2.0], [45, 4.0]]:
		w.progression.level = row[0]
		w.refresh_player_stats()
		assert_eq(w.weapon_attack(true), plain + row[1], "Lv %d: incPAD +%d" % [row[0], int(row[1])])
		assert_eq(w.weapon_attack(false), plain, "melee attack ignores ammo")


func test_a_bow_in_a_marksmans_hand_never_steps() -> void:
	var w := _ammo_world()
	w.progression.level = 45
	w.refresh_player_stats()
	w.drain_events()
	assert_eq(w.ammo_id(), 2061003)
	assert_eq(w.equip_item(_item_ids(w).find(BOW)), "")
	assert_eq(w.ammo_id(), 2060000, "a Marksman holding a bow fires the plain arrow: the Bowmaster's steps are not his")
	assert_eq(_upgrades(w).size(), 0, "a swap down is silent")
	assert_eq(w.equip_item(_item_ids(w).find(CROSSBOW)), "")
	assert_eq(w.ammo_id(), 2061003)
	assert_eq(_upgrades(w).size(), 0, "so is the swap back")
	var notices: Array = []
	var held := _ammo_world()
	assert_eq(held.equip_item(_item_ids(held).find(BOW)), "")
	_level_to(held, 46, notices)
	assert_eq(held.ammo_id(), 2060000)
	assert_eq(notices.size(), 0, "a whole round with the bow announces nothing")


func test_the_shot_sprite_is_the_current_crossbow_arrows_bullet() -> void:
	for level in [1, 15, 30, 45]:
		var w := _ammo_world()
		w.progression.level = level
		w.refresh_player_stats()
		assert_true(w.learn_skill("arrow_blow"))
		RF.put_mob(w, 1110100, w.player.pos.x + 80, 190, 10000)
		w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
		w.drain_events()
		w.runner.step(DT, w)
		var seen := 0
		for i in w.projectiles.capacity():
			if w.projectiles.active[i] != 0:
				seen += 1
				assert_eq(w.projectiles.paths[w.projectiles.visual[i]], Ammo.bullet_path(w.ammo_id()), "Lv %d shot" % level)
		assert_eq(seen, 1, "Lv %d: one arrow in flight" % level)


func test_the_bowmaster_schedule_is_unchanged_by_the_marksman_line() -> void:
	var data := _data()
	for row: Array in [[1, 2060000], [15, 2060001], [30, 2060002], [45, 2060003]]:
		assert_eq(Ammo.item_for(data.ammo, "bow", 312, row[0]), row[1], "Bowmaster Lv %d" % row[0])
		assert_eq(Ammo.item_for(data.ammo, "bow", 322, row[0]), 2060000, "a Marksman holding a bow at Lv %d" % row[0])
		assert_eq(Ammo.item_for(data.ammo, "crossbow", 312, row[0]), 2061000, "a Bowmaster holding a crossbow at Lv %d" % row[0])


func test_real_cache_the_crossbow_arrows_and_their_string_names_exist() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.get_default()
	var data := _data()
	var missing := PackedStringArray()
	var info := DataRepo.ammo_info(data.ammo, func(path: String) -> Dictionary:
		var img := lib.img(path)
		return img.root if img != null else {}, missing)
	assert_eq(missing, PackedStringArray())
	var names := {2061000: "Arrow for Crossbow", 2061001: "Bronze Arrow for Crossbow", 2061002: "Steel Arrow for Crossbow",
		2061003: "Blue Arrow for Crossbow"}
	var pads := {2061000: 0, 2061001: 1, 2061002: 2, 2061003: 4}
	for id: int in names:
		assert_eq(int(info[id].incPAD), pads[id], "tier A: Item.wz incPAD of %d" % id)
		assert_eq(String(lib.find(InventoryModel.name_path(id))), names[id], "String.wz name of %d" % id)
		assert_true(lib.anim(Ammo.bullet_path(id)) != null, "%d has a flight animation" % id)
