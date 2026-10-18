extends TestCase
## Warrior second job opens (spec #165 ticket #180, docs/GAME_DESIGN.md sections 8 and 9): Fighter 110, Page 120 and
## Spearman 130 at Lv 30 with +325 Max HP, two advancement weapons per branch (worn: the held family's, else the first
## family's; the other and the displaced weapon join the Equip tab, spilling at the player's feet when it is full), and the
## Warrior's first-job attack cards kept on offer after the advancement (never in the advancement draw). Seeded, fixed ticks.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const GLADIUS := 1302008
const FIREMANS_AXE := 1312005
const WAR_HAMMER := 1322014
const FORKED_SPEAR := 1432002
const MITHRIL_POLE_ARM := 1442001
const ADVANCEMENT_WEAPONS := [GLADIUS, FIREMANS_AXE, WAR_HAMMER, FORKED_SPEAR, MITHRIL_POLE_ARM]


## Synthetic Character.wz info of the five advancement weapons (Lv 30 requirements the ticket quotes: STR 95-100).
func _info() -> Dictionary:
	return {
		1302000: {"incPAD": 17.0, "attackSpeed": 4.0},
		1302077: {"reqJob": 1, "reqLevel": 10, "reqSTR": 35, "incPAD": 30.0, "attackSpeed": 4.0},
		1432000: {"reqJob": 13, "reqLevel": 10, "incPAD": 32.0, "attackSpeed": 8.0},
		1322006: {"reqJob": 0, "reqLevel": 10, "incPAD": 29.0, "attackSpeed": 5.0},
		1312004: {"reqLevel": 20, "reqSTR": 30, "incPAD": 20.0, "attackSpeed": 6.0},
		1040002: {"incPDD": 3, "tuc": 7},
		GLADIUS: {"reqJob": 1, "reqLevel": 30, "reqSTR": 95, "incPAD": 42.0, "attackSpeed": 4.0},
		FIREMANS_AXE: {"reqJob": 1, "reqLevel": 30, "reqSTR": 100, "incPAD": 44.0, "attackSpeed": 6.0},
		WAR_HAMMER: {"reqJob": 1, "reqLevel": 30, "reqSTR": 100, "incPAD": 44.0, "attackSpeed": 6.0},
		FORKED_SPEAR: {"reqJob": 1, "reqLevel": 30, "reqSTR": 95, "incPAD": 44.0, "attackSpeed": 6.0},
		MITHRIL_POLE_ARM: {"reqJob": 1, "reqLevel": 30, "reqSTR": 100, "incPAD": 45.0, "attackSpeed": 6.0},
	}


## A Warrior (job 100) wearing `weapon` with `free` free Equip slots, at Lv 29 with the Lv 30 window one EXP away.
func _warrior(weapon := 1302077, free := 24, p_seed := 5) -> RunWorld:
	var data := RF.quiet_data()
	var setup := RF.with_basic_attack(RF.setup("quiet", p_seed, data))
	setup.equipment_info.merge(_info(), true)
	var w0 := RunWorld.new(setup)
	w0.change_job(100)
	var character := w0.character_snapshot()
	character.equipment.worn.weapon = Equipment.create(weapon, setup.equipment_info[weapon])
	character.equipment.inventory = []
	for i in 24 - free:
		character.equipment.inventory.append(Equipment.create(1040002, setup.equipment_info[1040002]))
	setup.character = character
	var w := RunWorld.new(setup)
	RF.place_player(w, 400)
	w.god = true
	return w


## Lifts the Warrior to Lv 30 and opens the advancement window (the level-up card draw waits behind it).
func _open_window(w: RunWorld) -> void:
	w.progression.level = 29
	w.progression.add_exp(w.progression.exp_to_next())
	w.step(DT, MoveInput.new())
	assert_eq(w.state, RunWorld.CHOOSING_JOB, "the Lv 30 advancement window is open")
	w.drain_events()


func _advance(w: RunWorld, job: int) -> void:
	_open_window(w)
	assert_true(w.apply_job(job), "job %d is on offer" % job)


func _inventory_ids(w: RunWorld) -> Array:
	return w.equipment.inventory.map(func(i: Dictionary) -> int: return int(i.id))


func _spilled(w: RunWorld) -> Array:
	var ids: Array = w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "pickup_spawned") \
		.map(func(e: Dictionary) -> int: return int(e.item_id))
	ids.sort()
	return ids


# --- the window and the Max HP ----------------------------------------------------------------------------------------

func test_a_lv30_warriors_window_offers_all_three_branches_and_each_adds_325_max_hp() -> void:
	for job in [110, 120, 130]:
		var w := _warrior()
		_open_window(w)
		var offered: Array = w.pending_jobs.filter(func(o: Dictionary) -> bool: return bool(o.available)) \
			.map(func(o: Dictionary) -> int: return int(o.job_id))
		assert_eq(offered, [110, 120, 130], "the three Warrior branches are on offer")
		var hp0: int = w.player_state.max_hp
		var mp0: int = w.player_state.max_mp
		assert_true(w.apply_job(job))
		assert_eq(w.progression.job_id, job)
		assert_eq(w.player_state.max_hp, hp0 + 325, "second-job Max HP grant (tier B midpoint)")
		assert_eq(w.player_state.max_mp, mp0, "no MP grant")


func test_warrior_growth_stays_26_hp_and_5_mp_per_level_after_the_second_job() -> void:
	var w := _warrior()
	_advance(w, 110)
	RF.auto_choose(w)
	var hp0: int = w.player_state.max_hp
	var mp0: int = w.player_state.max_mp
	w.pickups.spawn(w.player.pos, w.progression.exp_to_next(), 4000019)
	for tick in 120:
		w.step(DT, MoveInput.new())
		if w.progression.level > 30:
			break
	RF.auto_choose(w)
	assert_eq(w.progression.level, 31)
	assert_eq(w.player_state.max_hp, hp0 + 26)
	assert_eq(w.player_state.max_mp, mp0 + 5)


# --- advancement weapons -----------------------------------------------------------------------------------------------

func test_a_fighter_holding_a_sword_wears_the_gladius_and_the_tab_gets_the_old_sword_and_the_axe() -> void:
	var w := _warrior(1302077)
	_advance(w, 110)
	assert_eq(w.weapon_id(), GLADIUS)
	assert_eq(w.held_weapon_family(), "sword")
	assert_eq(_inventory_ids(w), [1302077, FIREMANS_AXE], "the displaced sword, then the other advancement weapon")
	assert_eq(_spilled(w), [])


func test_a_fighter_holding_an_axe_wears_the_firemans_axe_and_the_tab_gets_the_axe_and_the_gladius() -> void:
	var w := _warrior(1312004)
	_advance(w, 110)
	assert_eq(w.weapon_id(), FIREMANS_AXE, "the held family is one of the branch's: its weapon is worn")
	assert_eq(_inventory_ids(w), [1312004, GLADIUS])


func test_a_fighter_holding_the_lv10_spear_wears_the_gladius() -> void:
	var w := _warrior(1432000)
	_advance(w, 110)
	assert_eq(w.weapon_id(), GLADIUS, "a spear is no Fighter family: the first family's weapon is worn")
	assert_eq(_inventory_ids(w), [1432000, FIREMANS_AXE])


func test_a_page_holding_a_sword_or_the_steel_pipe_wears_the_matching_weapon() -> void:
	var sword := _warrior(1302077)
	_advance(sword, 120)
	assert_eq(sword.weapon_id(), GLADIUS)
	assert_eq(_inventory_ids(sword), [1302077, WAR_HAMMER])
	var pipe := _warrior(1322006)
	_advance(pipe, 120)
	assert_eq(pipe.weapon_id(), WAR_HAMMER, "the Steel Pipe is blunt: the War Hammer is worn")
	assert_eq(_inventory_ids(pipe), [1322006, GLADIUS])


func test_a_spearman_holding_the_spear_wears_the_forked_spear_and_the_tab_gets_the_pole_arm() -> void:
	var w := _warrior(1432000)
	_advance(w, 130)
	assert_eq(w.weapon_id(), FORKED_SPEAR)
	assert_eq(w.held_weapon_family(), "spear")
	assert_eq(_inventory_ids(w), [1432000, MITHRIL_POLE_ARM])


func test_a_spearman_holding_a_sword_wears_the_forked_spear() -> void:
	var w := _warrior(1302077)
	_advance(w, 130)
	assert_eq(w.weapon_id(), FORKED_SPEAR, "the first family's weapon")
	assert_eq(_inventory_ids(w), [1302077, MITHRIL_POLE_ARM])


func test_a_full_equip_tab_drops_the_grants_at_the_feet_and_advancing_does_not_fail() -> void:
	var w := _warrior(1302077, 0)
	_advance(w, 110)
	assert_eq(w.weapon_id(), GLADIUS, "advancing never fails")
	assert_eq(w.equipment.inventory.size(), 24, "the tab is unchanged")
	assert_eq(_spilled(w), [1302077, FIREMANS_AXE], "the old sword and the axe lie at the player's feet")
	var one := _warrior(1302077, 1)
	_advance(one, 110)
	assert_eq(_inventory_ids(one).slice(23), [1302077], "the displaced weapon has priority for the one free slot")
	assert_eq(_spilled(one), [FIREMANS_AXE])


func test_a_two_handed_advancement_weapon_takes_the_shield_off_into_the_tab() -> void:
	var w := _warrior(1302077)
	w.equipment.worn["shield"] = Equipment.create(1092000, {"incPDD": 5, "tuc": 7})
	_advance(w, 130)
	assert_eq(w.weapon_id(), FORKED_SPEAR)
	assert_false(w.equipment.worn.has("shield"), "a two-handed weapon never keeps a shield")
	assert_eq(_inventory_ids(w), [1302077, 1092000, MITHRIL_POLE_ARM], "the sword, the shield, then the pole arm")


# --- the data shape and the preload -------------------------------------------------------------------------------------

func test_the_shipped_rows_pair_each_family_with_its_advancement_weapon() -> void:
	var data := DataRepo.load_all()
	var jobs := JobTree.from_data(data.jobs, data.jobs_survivor)
	var want := {
		110: [["sword", GLADIUS], ["axe", FIREMANS_AXE]],
		120: [["sword", GLADIUS], ["blunt", WAR_HAMMER]],
		130: [["spear", FORKED_SPEAR], ["polearm", MITHRIL_POLE_ARM]],
	}
	for id: int in want:
		var row := jobs.job(id)
		assert_true(bool(row.playable), "%d is playable" % id)
		assert_eq(int(row.level), 30, "canonical Lv 30")
		assert_eq(int(row.grants.max_hp), 325)
		var weapons: Array = jobs.branch_grant(id).get("weapons", [])
		assert_eq(weapons.map(func(x: Dictionary) -> Array: return [x.family, x.item_id]), want[id], "branch %d" % id)
		assert_eq(jobs.weapon_families(id), want[id].map(func(x: Array) -> String: return x[0]))


func test_every_advancement_weapon_is_in_the_starter_equipment_preload() -> void:
	var ids := DataRepo.starter_equipment_ids(DataRepo.load_all())
	for id: int in ADVANCEMENT_WEAPONS:
		assert_true(id in ids, "%d loads its canonical info with the setup" % id)
	# A row that lists a weapon the collector does not read would pass silently on a warm cache: prove the collector
	# follows the data by adding a synthetic playable branch.
	var data := DataRepo.load_all()
	data.jobs_survivor.jobs["999"] = {"playable": true, "weapon_families": ["bow"], "grant_items": [1452999]}
	assert_true(1452999 in DataRepo.starter_equipment_ids(data), "the collector reads grant_items")


func test_branch_grant_reads_one_weapon_per_family_and_nothing_without_items() -> void:
	var survivor := {"jobs": {
		"110": {"weapon_families": ["sword", "axe"], "grant_items": [GLADIUS, FIREMANS_AXE]},
		"310": {"weapon_families": ["bow"], "grant_items": [1452000]},
		"410": {"weapon_families": ["claw"]},
		"420": {"weapon_families": ["dagger"], "grant_items": [0]},
		"430": {"weapon_families": ["dagger", "claw"], "grant_items": [1332000]}}}
	var jobs := JobTree.from_data({"jobs": []}, survivor)
	assert_eq(jobs.branch_grant(110), {"weapons": [{"family": "sword", "item_id": GLADIUS},
		{"family": "axe", "item_id": FIREMANS_AXE}]})
	assert_eq(jobs.branch_grant(310), {"weapons": [{"family": "bow", "item_id": 1452000}]}, "one family: one entry")
	assert_eq(jobs.branch_grant(410), {}, "no items: nothing is granted")
	assert_eq(jobs.branch_grant(420), {}, "an item id of 0 is no grant")
	assert_eq(jobs.branch_grant(430), {"weapons": [{"family": "dagger", "item_id": 1332000}]},
		"a family without an item is skipped")
	assert_eq(jobs.branch_grant(999), {})


# --- the first-job attack cards after the second job --------------------------------------------------------------------

const KEPT := ["power_strike_new", "power_strike_rank", "power_strike_targets", "power_strike_damage",
	"power_strike_cooldown", "slash_blast_new", "slash_blast_rank", "slash_blast_targets", "slash_blast_range",
	"slash_blast_cooldown"]
const DROPPED := ["iron_body_new", "iron_body_rank", "improved_hp_recovery_new", "improved_hp_recovery_rank",
	"improved_max_hp_new", "improved_max_hp_rank"]


func test_power_strike_and_slash_blast_cards_stay_eligible_after_every_second_job_and_stay_power() -> void:
	for job in [110, 120, 130]:
		var w := _warrior(1432000 if job == 130 else 1302077)
		w.learn_skill("power_strike")
		w.learn_skill("slash_blast")
		_advance(w, job)
		w.pending_cards = []
		w.state = RunWorld.PLAYING
		var ids: Array = w.upgrades.eligible(w)
		for id in ["power_strike_rank", "power_strike_targets", "power_strike_damage", "power_strike_cooldown",
				"slash_blast_rank", "slash_blast_targets", "slash_blast_range", "slash_blast_cooldown"]:
			assert_has(ids, id, "%s stays on offer for job %d" % [id, job])
		for id in KEPT:
			assert_true(UpgradePool.is_power(w.upgrades.card(id)), "%s still counts as a power card" % id)
		for id in DROPPED:
			assert_false(id in ids, "%s stops at Lv 30 (job %d)" % [id, job])


func test_unlearned_first_job_attacks_can_still_be_learned_after_the_second_job() -> void:
	var w := _warrior(1302077)
	_advance(w, 110)
	w.pending_cards = []
	w.state = RunWorld.PLAYING
	var ids: Array = w.upgrades.eligible(w)
	assert_has(ids, "power_strike_new")
	assert_has(ids, "slash_blast_new")
	assert_eq(w.upgrades.apply("power_strike_new", w), 1)
	assert_true(w.loadout.has("power_strike"))


func test_the_advancement_draw_never_offers_the_kept_first_job_cards() -> void:
	for job in [110, 120, 130]:
		var w := _warrior(1302077)
		_open_window(w)
		assert_true(w.apply_job(job))
		for c: Dictionary in w.pending_cards:
			assert_false(String(c.id) in KEPT, "%s is not an advancement offer" % c.id)
			assert_false(String(c.id) in DROPPED, "%s is not an advancement offer" % c.id)


func test_a_draw_after_the_second_job_can_offer_the_kept_cards_and_they_reset_pity() -> void:
	var w := _warrior(1302077)
	w.learn_skill("power_strike")
	_advance(w, 110)
	RF.auto_choose(w)
	assert_eq(w.state, RunWorld.PLAYING)
	w.upgrades.pity_draws = 3
	w.power_dry = 3
	var rng := RandomNumberGenerator.new()
	rng.seed = 91
	var offers: Array = w.upgrades.roll_choices(w, rng)
	assert_true(UpgradePool.is_power(w.upgrades.card(String(offers[0].id))), "pity forces a power card first")
	assert_has(KEPT, String(offers[0].id), "and the only power cards left are the kept first-job ones")
	assert_eq(w.power_dry, 0, "offering a kept power card counts for pity")


func test_a_job_100_warrior_is_unaffected_and_a_magician_never_sees_warrior_cards() -> void:
	var w := _warrior(1302077)
	assert_has(w.upgrades.eligible(w), "iron_body_new", "Lv 29 Warrior: Iron Body still on offer")
	var magician := RF.quiet_world()
	magician.change_job(210)
	for id in KEPT + DROPPED:
		assert_false(id in magician.upgrades.eligible(magician), id)


# --- the tools --------------------------------------------------------------------------------------------------------

func test_job_110_120_130_can_be_forced_and_an_unknown_second_job_still_fails() -> void:
	var data := DataRepo.load_all()
	for job in [110, 120, 130]:
		assert_eq(SceneFlow.forced_job_error({"job": job}, data), "", "--job=%d is accepted" % job)
	assert_true("not playable" in SceneFlow.forced_job_error({"job": 310}, data), "the Hunter's line is still locked")
	assert_true("not in the canonical" in SceneFlow.forced_job_error({"job": 150}, data), "a job the tree lacks fails")


func test_the_bot_takes_the_forced_warrior_branch_and_an_unforced_one_draws_on_the_job_stream() -> void:
	var w := _warrior()
	_open_window(w)
	for job in [110, 120, 130]:
		assert_eq(BotInput.pick_choice(w.pending_jobs, w.job_rng, job, w.jobs, ""), {"job_id": job, "path": ""})
	var seen := {}
	for seed_value in 12:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var pick := BotInput.pick_choice(w.pending_jobs, rng, 0, w.jobs, "")
		assert_true(pick.job_id in [110, 120, 130])
		seen[pick.job_id] = true
	assert_eq(seen.size(), 3, "all three branches come up over seeds")
