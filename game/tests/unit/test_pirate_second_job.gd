extends TestCase
## Brawler 510 and Gunslinger 520 playable at Lv 30 (spec #168 ticket #189, docs/GAME_DESIGN.md sections 7.17 and 9):
## +325 Max HP / +175 Max MP, one advancement weapon per branch (Prime Hands 1482004, Cold Mind 1492004), the auto-AP rows
## that follow the branch's weapon whichever first-job path was taken, Improve MaxHP, the two Masteries and the two
## Boosters (each only while its weapon family is held), and the Gunslinger's Split Bullet / Mighty Bullet. Seeded
## worlds with fixed ticks; the original-data checks at the end use the private asset cache and SKIP without it.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const STEEL_KNUCKLER := 1482000
const PISTOL := 1492000
const PRIME_HANDS := 1482004
const COLD_MIND := 1492004
## Synthetic Character.wz info: the four Pirate weapons with their original v83 requirements and PAD.
const INFO := {
	STEEL_KNUCKLER: {"incPAD": 18, "attackSpeed": 5, "tuc": 7},
	PISTOL: {"incPAD": 13, "attackSpeed": 5, "tuc": 7},
	PRIME_HANDS: {"reqJob": 16, "reqLevel": 30, "reqSTR": 60, "reqDEX": 30, "incPAD": 34, "attackSpeed": 5, "tuc": 7},
	COLD_MIND: {"reqJob": 16, "reqLevel": 30, "reqSTR": 30, "reqDEX": 70, "incPAD": 31, "attackSpeed": 5, "tuc": 7},
}


## A Pirate (first job 500, `path`) at Lv 29 with `free` free Equip slots and the Lv 30 window one EXP away.
func _pirate(path := "knuckle", free := 24, p_seed := 189) -> RunWorld:
	var data := RF.quiet_data()
	data.balance.player.skills = []
	var setup := RF.with_basic_attack(RF.setup("quiet", p_seed, data))
	setup.equipment_info.merge(INFO, true)
	var w0 := RunWorld.new(setup)
	w0.change_job(500, path)
	var character := w0.character_snapshot()
	character.equipment.inventory = []
	for i in 24 - free:
		character.equipment.inventory.append(Equipment.create(1040002, {"incPDD": 3, "tuc": 7}))
	setup.character = character
	var w := RunWorld.new(setup)
	RF.place_player(w, 400)
	w.god = true
	return w


## Lifts the Pirate to Lv 30 and opens the advancement window (the level-up card draw waits behind it).
func _open_window(w: RunWorld) -> void:
	w.progression.level = 29
	w.progression.add_exp(w.progression.exp_to_next())
	w.step(DT, MoveInput.new())
	assert_eq(w.state, RunWorld.CHOOSING_JOB, "the Lv 30 advancement window is open")
	w.drain_events()


func _advance(w: RunWorld, job: int) -> void:
	_open_window(w)
	assert_true(w.apply_job(job), "job %d is on offer" % job)


## A branch character already past the window: first job `path`, the second job `job`, no window or card pending.
func _branch(job: int, path := "knuckle", level := 30) -> RunWorld:
	var w := _pirate(path)
	w.progression.level = level
	w.change_job(job)
	# One spare of each first-job weapon, so the tests can swap families by hand.
	for id in [STEEL_KNUCKLER, PISTOL]:
		w.equipment.inventory.append(Equipment.create(id, INFO[id]))
	w.pending_cards = []
	w.state = RunWorld.PLAYING
	w.drain_events()
	return w


func _inventory_ids(w: RunWorld) -> Array:
	return w.equipment.inventory.map(func(i: Dictionary) -> int: return int(i.id))


func _spilled(w: RunWorld) -> Array:
	var ids: Array = w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "pickup_spawned") \
		.map(func(e: Dictionary) -> int: return int(e.item_id))
	ids.sort()
	return ids


func _wear(w: RunWorld, id: int) -> void:
	var index := _inventory_ids(w).find(id)
	assert_true(index >= 0, "item %d is in the Equip tab" % id)
	assert_eq(w.equip_item(index), "", "wearing %d" % id)


# --- the window, the Max HP / MP and the weapons -------------------------------------------------------------------------

func test_a_lv30_pirate_is_offered_both_branches_on_either_path_and_each_adds_325_hp_and_175_mp() -> void:
	for path in ["knuckle", "gun"]:
		for job in [510, 520]:
			var w := _pirate(path)
			_open_window(w)
			var offered: Array = w.pending_jobs.filter(func(o: Dictionary) -> bool: return bool(o.available)) \
				.map(func(o: Dictionary) -> int: return int(o.job_id))
			assert_eq(offered, [510, 520], "both Pirate branches on offer to a %s Pirate" % path)
			var hp0: int = w.player_state.max_hp
			var mp0: int = w.player_state.max_mp
			assert_true(w.apply_job(job))
			assert_eq(w.progression.job_id, job)
			assert_eq(w.weapon_path, path, "the first-job path stays recorded")
			assert_eq(w.player_state.max_hp, hp0 + 325, "second-job Max HP grant (tier B midpoint)")
			assert_eq(w.player_state.max_mp, mp0 + 175, "second-job Max MP grant (tier B midpoint)")


func test_pirate_growth_stays_25_hp_and_20_5_mp_per_level_after_the_second_job() -> void:
	var w := _branch(510)
	var hp0: int = w.player_state.max_hp
	var mp0: int = w.player_state.max_mp
	for level in range(31, 41):
		w._gain_exp(w.progression.exp_to_next())
		assert_eq(w.progression.level, level)
	assert_eq(w.player_state.max_hp - hp0, 250, "25 HP x 10 levels")
	assert_between(w.player_state.max_mp - mp0, 204, 206, "20.5 MP x 10 levels, accumulated before rounding")


func test_each_branch_wears_its_advancement_weapon_and_the_tab_gets_the_old_one() -> void:
	var want := {510: PRIME_HANDS, 520: COLD_MIND}
	var held := {"knuckle": STEEL_KNUCKLER, "gun": PISTOL}
	for path in ["knuckle", "gun"]:
		for job in [510, 520]:
			var w := _pirate(path)
			_advance(w, job)
			assert_eq(w.weapon_id(), want[job], "%s-path branch %d wears its advancement weapon" % [path, job])
			assert_eq(w.held_weapon_family(), "knuckle" if job == 510 else "gun")
			assert_eq(_inventory_ids(w), [held[path]], "the displaced first-job weapon is in the Equip tab")
			assert_eq(_spilled(w), [])


func test_a_full_equip_tab_drops_the_displaced_weapon_at_the_feet_and_advancing_does_not_fail() -> void:
	for job in [510, 520]:
		var w := _pirate("knuckle", 0)
		_advance(w, job)
		assert_eq(w.weapon_id(), PRIME_HANDS if job == 510 else COLD_MIND, "advancing never fails")
		assert_eq(w.equipment.inventory.size(), 24, "the tab is unchanged")
		assert_eq(_spilled(w), [STEEL_KNUCKLER], "the old weapon lies at the player's feet")
	var one := _pirate("gun", 1)
	_advance(one, 510)
	assert_eq(_inventory_ids(one).slice(23), [PISTOL], "the one free slot takes the displaced weapon")
	assert_eq(_spilled(one), [])


func test_the_grant_checks_no_requirement_but_the_lv30_auto_ap_meets_it() -> void:
	# Requirements are checked as normal when wearing by hand (#180: a grant itself never checks); the auto-AP rows give a
	# Lv 30 character of the matching branch exactly the stats the weapons need.
	var w := _pirate("knuckle")
	_advance(w, 510)
	assert_eq(w.weapon_id(), PRIME_HANDS, "worn although a fresh Lv 29 fixture has 12 STR")
	for entry in [[510, "knuckle", PRIME_HANDS], [520, "gun", COLD_MIND]]:
		var fixture := _pirate(entry[1])
		fixture.god = true
		for level in range(30, 31):
			fixture.progression.level = level
		fixture._earned_ap = 5 * 29
		fixture.change_job(entry[0])
		var info: Dictionary = INFO[entry[2]]
		assert_eq(Equipment.requirement_error(info, fixture.player_state), "", "branch %d meets its Lv 30 weapon" % entry[0])


func test_the_magician_branches_grant_no_weapon_and_advance_as_before() -> void:
	for job in [210, 220, 230]:
		var setup := RF.with_basic_attack(RF.setup("quiet", 5, RF.quiet_data()))
		var w0 := RunWorld.new(setup)
		w0.change_job(200)
		var character := w0.character_snapshot()
		setup.character = character
		var w := RunWorld.new(setup)
		RF.place_player(w, 400)
		w.progression.level = 29
		w.progression.add_exp(w.progression.exp_to_next())
		w.step(DT, MoveInput.new())
		assert_eq(w.state, RunWorld.CHOOSING_JOB)
		w.drain_events()
		var weapon := w.weapon_id()
		var inventory := _inventory_ids(w)
		var hp0: int = w.player_state.max_hp
		var mp0: int = w.player_state.max_mp
		assert_eq(w.jobs.paths_of(job), [], "no advancement weapon for %d" % job)
		assert_true(w.apply_job(job))
		assert_eq(w.weapon_id(), weapon, "the Magician keeps its wand")
		assert_eq(_inventory_ids(w), inventory)
		assert_eq(w.player_state.max_hp, hp0)
		assert_eq(w.player_state.max_mp, mp0 + 475)
		assert_eq(w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "equipment_changed").size(), 0)


# --- auto-AP ----------------------------------------------------------------------------------------------------------

## Levels a first-job Pirate of `path` to Lv 29, then through the Lv 30 window as `job` (the bot forced to it).
func _climb_to_30(path: String, job: int) -> RunWorld:
	var w := _pirate(path)
	w.progression.level = 1
	w.change_job(500, path)
	w.god = true
	for target in range(2, 31):
		var needed := w.progression.curve.total_to(target) - w.progression.curve.total_to(w.progression.level) \
			- w.progression.exp
		w.pickups.spawn(w.player.pos, needed, 4000019)
		for tick in 120:
			w.step(DT, MoveInput.new())
			if w.state != RunWorld.PLAYING:
				BotInput.auto_choose(w, false, job, path)
			if w.progression.level == target:
				break
		assert_eq(w.progression.level, target)
	return w


func test_ap_rows_follow_the_branch_whichever_path_was_taken() -> void:
	for path in ["knuckle", "gun"]:
		for job in [510, 520]:
			var w := _climb_to_30(path, job)
			assert_eq(w.progression.job_id, job)
			assert_eq(w.weapon_path, path)
			var secondary: String = "dex" if job == 510 else "str"
			var primary: String = "str" if job == 510 else "dex"
			assert_eq(w.player_state[secondary], 30, "%s-path %d: the secondary stat sits at the level" % [path, job])
			assert_true(w.player_state[primary] > 100, "%s-path %d: the rest goes to %s" % [path, job, primary])
			var weapon: int = PRIME_HANDS if job == 510 else COLD_MIND
			assert_eq(Equipment.requirement_error(INFO[weapon], w.player_state), "", "Prime Hands / Cold Mind are wearable")


func test_a_knuckle_path_gunslinger_switches_to_dex_with_a_str_secondary() -> void:
	var w := _pirate("knuckle")
	w._earned_ap = 5 * 29
	w.progression.level = 30
	w.refresh_player_stats(false)
	assert_eq(w.player_state.dex, 30, "the knuckle path's secondary DEX target is the level")
	var str_before: int = w.player_state.str
	w.change_job(520)
	assert_eq(w.weapon_path, "knuckle")
	assert_eq(w.player_state.str, 30, "STR becomes the secondary stat")
	assert_true(w.player_state.dex > 100, "DEX takes the earned AP")
	assert_true(str_before > 100)


# --- skills: Improve MaxHP, Masteries, Boosters ---------------------------------------------------------------------------

func test_improve_maxhp_adds_x_per_level_up_at_the_skills_rank_then_and_is_never_retroactive() -> void:
	var w := _branch(510)
	w.learn_skill("improve_maxhp")
	var hp0: int = w.player_state.max_hp
	w._gain_exp(w.progression.exp_to_next())
	assert_eq(w.player_state.max_hp - hp0, 25 + 3, "Lv 31: growth plus x = 3 at rank 1")
	w.loadout.set_rank("improve_maxhp", 10)
	assert_eq(w.player_state.max_hp - hp0, 25 + 3, "raising the rank adds nothing by itself")
	hp0 = w.player_state.max_hp
	w._gain_exp(w.progression.exp_to_next())
	assert_eq(w.player_state.max_hp - hp0, 25 + 30, "Lv 32: x = 30 at rank 10")


func test_improve_maxhp_works_with_either_weapon() -> void:
	var w := _branch(510, "gun")
	_wear(w, PISTOL)
	w.learn_skill("improve_maxhp")
	var hp0: int = w.player_state.max_hp
	w._gain_exp(w.progression.exp_to_next())
	assert_eq(w.player_state.max_hp - hp0, 25 + 3, "no weapon requirement")


func test_knuckler_mastery_applies_only_with_a_knuckle_held() -> void:
	var w := _branch(510)
	var acc0: float = w.player_state.acc
	assert_near(w.loadout.mastery, Loadout.BASE_MASTERY)
	assert_true(w.learn_skill("knuckler_mastery"))
	assert_near(w.loadout.mastery, 0.15, 1e-6, "rank 1: mastery N = 1 is 15%")
	assert_near(w.player_state.acc, acc0 + 1.0, 1e-6, "rank 1: ACC +1")
	w.loadout.set_rank("knuckler_mastery", 20)
	w.refresh_player_stats(false)
	assert_near(w.loadout.mastery, 0.60, 1e-6, "rank 20: mastery N = 10 is 60%")
	assert_near(w.player_state.acc, acc0 + 20.0, 1e-6, "rank 20: ACC +20")
	_wear(w, STEEL_KNUCKLER) # still a knuckle
	assert_near(w.loadout.mastery, 0.60, 1e-6)
	var gun_world := _branch(510, "gun")
	gun_world.learn_skill("knuckler_mastery")
	gun_world.loadout.set_rank("knuckler_mastery", 20)
	_wear(gun_world, PISTOL)
	assert_eq(gun_world.held_weapon_family(), "gun")
	assert_near(gun_world.loadout.mastery, Loadout.BASE_MASTERY, 1e-6, "a gun gets no knuckle mastery")
	assert_near(gun_world.player_state.acc, acc0 + 0.0, 1e-6, "nor its ACC")


func test_gun_mastery_applies_only_with_a_gun_held() -> void:
	var w := _branch(520, "gun")
	var acc0: float = w.player_state.acc
	assert_true(w.learn_skill("gun_mastery"))
	assert_near(w.loadout.mastery, 0.15, 1e-6)
	assert_near(w.player_state.acc, acc0 + 1.0, 1e-6)
	w.loadout.set_rank("gun_mastery", 20)
	w.refresh_player_stats(false)
	assert_near(w.loadout.mastery, 0.60, 1e-6)
	assert_near(w.player_state.acc, acc0 + 20.0, 1e-6)
	_wear(w, STEEL_KNUCKLER)
	assert_near(w.loadout.mastery, Loadout.BASE_MASTERY, 1e-6, "a knuckle gets no gun mastery")
	assert_near(w.player_state.acc, acc0 + 0.0, 1e-6)
	_wear(w, PISTOL) # Cold Mind needs STR 30, which this Lv 29 fixture lacks
	assert_near(w.loadout.mastery, 0.60, 1e-6, "and it returns with the gun")


func _cast_booster(w: RunWorld, key: String) -> Array:
	w.heal_fraction("hp", 1.0)
	w.heal_fraction("mp", 1.0)
	w.drain_events()
	var events: Array = []
	for tick in 90:
		w.step(DT, MoveInput.new())
		events.append_array(w.drain_events())
		if w.buffs.has(key):
			break
	return events


func test_knuckler_booster_speeds_a_held_knuckle_by_two_steps_and_pays_hp_and_mp() -> void:
	var w := _branch(510)
	assert_true(w.learn_skill("knuckler_booster"))
	var hp0: int = w.player_state.max_hp
	w.heal_fraction("hp", 1.0)
	var hp_full: int = w.player_state.hp
	var mp_full: int = w.player_state.max_mp
	assert_eq(w.attack_speed_boost(), 0)
	var events := _cast_booster(w, "knuckler_booster")
	assert_true(w.buffs.has("knuckler_booster"), "it auto-casts while inactive")
	assert_eq(events.filter(func(e: Dictionary) -> bool: return e.type == "buff_cast").size(), 1)
	assert_eq(w.attack_speed_boost(), 2, "x = -2 is two steps faster")
	assert_eq(w.loadout.speed_steps, 2)
	assert_eq(w.player_state.hp, hp_full - 29, "canonical hpCon 29 at rank 1")
	assert_eq(w.player_state.mp, mp_full - 29, "canonical mpCon 29 at rank 1")
	assert_true(hp0 > 0)
	_wear(w, STEEL_KNUCKLER)
	assert_eq(w.attack_speed_boost(), 2)
	# The buff keeps running through a weapon change and just stops counting.
	var gun_world := _branch(510, "gun")
	gun_world.learn_skill("knuckler_booster")
	_wear(gun_world, PISTOL)
	assert_eq(gun_world.held_weapon_family(), "gun")
	_cast_booster(gun_world, "knuckler_booster")
	assert_eq(gun_world.buffs.has("knuckler_booster"), false, "a gun-wielding Brawler never casts the knuckle Booster")
	assert_eq(gun_world.attack_speed_boost(), 0)


func test_gun_booster_speeds_a_held_gun_and_stops_counting_when_a_knuckle_is_held() -> void:
	var w := _branch(520, "gun")
	assert_true(w.learn_skill("gun_booster"))
	_cast_booster(w, "gun_booster")
	assert_true(w.buffs.has("gun_booster"))
	assert_eq(w.attack_speed_boost(), 2)
	assert_eq(w.loadout.speed_steps, 2)
	_wear(w, STEEL_KNUCKLER)
	assert_eq(w.attack_speed_boost(), 0, "the buff runs on but a knuckle gets no gun speed")
	assert_true(w.buffs.has("gun_booster"))
	_wear(w, PISTOL) # Cold Mind needs STR 30, which this Lv 29 fixture lacks
	assert_eq(w.attack_speed_boost(), 2)


func test_the_booster_shortens_the_gun_basic_attack_interval() -> void:
	var w := _branch(520, "gun")
	w.setup.equipment_info[COLD_MIND] = INFO[COLD_MIND]
	var plain := WeaponInfo.attack_interval(w.weapon_info(), 0)
	var boosted := WeaponInfo.attack_interval(w.weapon_info(), 2)
	assert_true(boosted < plain, "two steps faster than the weapon's own speed 5")


# --- cards ----------------------------------------------------------------------------------------------------------------

const BRAWLER_CARDS := ["improve_maxhp_new", "improve_maxhp_rank", "knuckler_mastery_new", "knuckler_mastery_rank",
	"knuckler_booster_new", "knuckler_booster_rank"]
const GUNSLINGER_CARDS := ["gun_mastery_new", "gun_mastery_rank", "gun_booster_new", "gun_booster_rank"]


func test_each_branchs_cards_are_offered_only_to_that_branch_and_its_weapon() -> void:
	var brawler := _branch(510)
	var eligible: Array = brawler.upgrades.eligible(brawler)
	for id in ["improve_maxhp_new", "knuckler_mastery_new", "knuckler_booster_new"]:
		assert_has(eligible, id, "%s is on offer to a knuckle-wielding Brawler" % id)
	for id in GUNSLINGER_CARDS:
		assert_false(id in eligible, "%s is the Gunslinger's" % id)
	var gunslinger := _branch(520, "gun")
	eligible = gunslinger.upgrades.eligible(gunslinger)
	for id in ["gun_mastery_new", "gun_booster_new"]:
		assert_has(eligible, id)
	for id in BRAWLER_CARDS:
		assert_false(id in eligible, "%s is the Brawler's" % id)
	var first := _pirate("knuckle")
	for id in BRAWLER_CARDS + GUNSLINGER_CARDS:
		assert_false(id in first.upgrades.eligible(first), "%s needs a second job" % id)
	var mage := RF.quiet_world()
	mage.change_job(210)
	for id in BRAWLER_CARDS + GUNSLINGER_CARDS:
		assert_false(id in mage.upgrades.eligible(mage), id)


func test_a_gun_in_hand_hides_the_knuckle_cards_and_improve_maxhp_stays() -> void:
	var w := _branch(510, "gun")
	_wear(w, PISTOL)
	var eligible: Array = w.upgrades.eligible(w)
	assert_has(eligible, "improve_maxhp_new", "any weapon")
	assert_false("knuckler_mastery_new" in eligible)
	assert_false("knuckler_booster_new" in eligible)


func test_the_first_job_cards_stay_on_offer_to_both_branches_but_not_in_their_advancement_draw() -> void:
	var first_job := ["flash_fist_new", "flash_fist_rank", "somersault_kick_new", "double_shot_new", "bullet_time_new",
		"bullet_time_rank"]
	for job in [510, 520]:
		var w := _pirate("knuckle")
		_open_window(w)
		assert_true(w.apply_job(job))
		for c: Dictionary in w.pending_cards:
			assert_false(String(c.id) in first_job, "%s is not a second-job advancement offer" % c.id)
		w.pending_cards = []
		w.state = RunWorld.PLAYING
		var eligible: Array = w.upgrades.eligible(w)
		# Flash Fist needs a knuckle and Double Shot a gun: the branch's weapon is worn.
		for id in ["flash_fist_new" if job == 510 else "double_shot_new", "somersault_kick_new", "bullet_time_new"]:
			assert_has(eligible, id, "%s stays on offer after the second job (job %d)" % [id, job])
	var lv10 := _pirate("knuckle")
	lv10.progression.job_id = 500
	assert_has(lv10.upgrades.eligible(lv10), "flash_fist_new")


func test_the_advancement_draw_offers_the_branchs_own_skills() -> void:
	var w := _pirate("knuckle")
	_open_window(w)
	assert_true(w.apply_job(510))
	var ids: Array = w.pending_cards.map(func(c: Dictionary) -> String: return String(c.id))
	# The draw offers power cards first: the Brawler's three attacks (#191), then its other cards.
	assert_true(ids.any(func(id: String) -> bool: return id in BRAWLER_CARDS or id.ends_with("_new")), "a Brawler card is offered: %s" % [ids])


# --- ammo ---------------------------------------------------------------------------------------------------------------------

func test_a_gunslinger_gets_split_bullets_at_lv30_and_mighty_bullets_at_lv50_a_brawler_never() -> void:
	var w := _pirate("gun")
	assert_eq(w.ammo_id(), 2330000)
	_open_window(w)
	assert_true(w.apply_job(520))
	var upgrades: Array = w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "ammo_upgraded")
	assert_eq(upgrades.size(), 1, "one notice, at the advancement")
	assert_eq(upgrades[0].item_id, 2330001)
	assert_eq(upgrades[0].from_item_id, 2330000)
	assert_eq(w.ammo_id(), 2330001, "Split Bullet at Lv 30")
	w.pending_cards = []
	w.state = RunWorld.PLAYING
	var got := []
	for level in range(31, 51):
		w._gain_exp(w.progression.exp_to_next())
		assert_eq(w.progression.level, level)
		for event: Dictionary in w.drain_events():
			if event.type == "ammo_upgraded":
				got.append([level, event.from_item_id, event.item_id])
	assert_eq(got, [[50, 2330001, 2330002]], "Mighty Bullet at Lv 50, no other change")
	assert_eq(w.ammo_id(), 2330002)
	var brawler := _pirate("gun")
	_open_window(brawler)
	assert_true(brawler.apply_job(510))
	_wear(brawler, PISTOL)
	assert_eq(brawler.held_weapon_family(), "gun")
	brawler.pending_cards = []
	brawler.state = RunWorld.PLAYING
	brawler.progression.level = 55
	brawler.refresh_player_stats(false)
	assert_eq(brawler.ammo_id(), 2330000, "a Brawler holding a gun keeps the basic Bullet")
	assert_eq(brawler.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "ammo_upgraded").size(), 0)


func test_advancing_past_lv50_goes_straight_to_mighty_bullets() -> void:
	var w := _pirate("gun")
	w.progression.level = 52
	w.change_job(520)
	var upgrades: Array = w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "ammo_upgraded")
	assert_eq(upgrades.size(), 1)
	assert_eq(w.ammo_id(), 2330002)


# --- the data, the tools and the snapshot -------------------------------------------------------------------------------------

func test_the_shipped_rows_grant_one_advancement_weapon_each() -> void:
	var data := DataRepo.load_all()
	var jobs := JobTree.from_data(data.jobs, data.jobs_survivor)
	for entry in [[510, "knuckle", PRIME_HANDS], [520, "gun", COLD_MIND]]:
		var row := jobs.job(entry[0])
		assert_true(bool(row.playable))
		assert_eq(int(row.level), 30, "canonical Lv 30")
		assert_eq(int(row.grants.max_hp), 325)
		assert_eq(int(row.grants.max_mp), 175)
		assert_eq(jobs.paths_of(entry[0]).map(func(p: Dictionary) -> Array: return [p.family, p.item_id]),
			[[entry[1], entry[2]]])
	for id in [210, 220, 230]:
		assert_eq(jobs.paths_of(id), [])
	assert_true(PRIME_HANDS in DataRepo.starter_equipment_ids(data))
	assert_true(COLD_MIND in DataRepo.starter_equipment_ids(data))


func test_job_510_and_520_run_in_the_tools_with_either_path() -> void:
	var data := DataRepo.load_all()
	for job in [510, 520]:
		assert_eq(SceneFlow.forced_job_error({"job": job}, data), "", "--job=%d is accepted" % job)
		for path in ["knuckle", "gun"]:
			var parsed := SceneFlow.parse_run_args(PackedStringArray(["--run=henesys", "--job=%d:%s" % [job, path]]))
			assert_eq(parsed.options.job, job)
			assert_eq(parsed.options.job_path, path)
			assert_eq(SceneFlow.forced_job_error(parsed.options, data), "")
	assert_true("no weapon path" in SceneFlow.forced_job_error({"job": 510, "job_path": "bow"}, data))


func test_the_bot_takes_the_forced_branch_at_both_windows() -> void:
	var w := _pirate("knuckle")
	_open_window(w)
	for job in [510, 520]:
		assert_eq(BotInput.pick_choice(w.pending_jobs, w.job_rng, job, w.jobs, "knuckle"), {"job_id": job, "path": "knuckle" if job == 510 else ""})
	var seen := {}
	for seed_value in 12:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var pick := BotInput.pick_choice(w.pending_jobs, rng, 0, w.jobs, "")
		assert_true(pick.job_id in [510, 520])
		seen[pick.job_id] = true
	assert_eq(seen.size(), 2, "without a held family an unforced bot draws its branch on the job stream (#261 keeps a held one)")


func test_the_snapshot_round_trips_both_branches_on_both_paths() -> void:
	for path in ["knuckle", "gun"]:
		for job in [510, 520]:
			var w := _pirate(path)
			_advance(w, job)
			for _i in 4:
				if w.state != RunWorld.PLAYING:
					BotInput.auto_choose(w, false, job, path)
			assert_eq(w.state, RunWorld.PLAYING)
			w.learn_skill("improve_maxhp" if job == 510 else "gun_mastery")
			w.apply_potion_schedule(w.progression.level, false) # the test sets the level directly: no level-up ran the schedule
			var snapshot := w.character_snapshot()
			assert_eq(CharacterSnapshot.validation_error(snapshot), "", "%s %d" % [path, job])
			var setup := w.setup.duplicate(true)
			setup.character = JSON.parse_string(JSON.stringify(snapshot))
			var restored := RunWorld.new(setup)
			assert_eq(restored.character_snapshot(), snapshot)
			assert_eq(restored.progression.job_id, job)
			assert_eq(restored.weapon_path, path)
			assert_eq(restored.weapon_id(), PRIME_HANDS if job == 510 else COLD_MIND)
			assert_eq(restored.player_state.max_hp, w.player_state.max_hp)
			assert_eq(restored.player_state.max_mp, w.player_state.max_mp)


func test_the_skill_text_hides_the_unused_bullet_recharge() -> void:
	var w := _branch(520, "gun")
	var text := SkillText.new(w.book, {})
	assert_eq(text.level_line("gun_mastery", 5, w.loadout.stats("gun_mastery", 5)), "Gun mastery +25%, Accuracy +5")
	assert_eq(text.level_line("improve_maxhp", 4, w.loadout.stats("improve_maxhp", 4)), "Each level-up gives +12 more Max HP")


# --- original data (private asset cache) ---------------------------------------------------------------------------------------

func test_original_second_job_tables_art_and_sounds_resolve_in_the_private_cache() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	var books := {}
	for book in ["510", "520"]:
		var img := lib.img("Skill.wz/%s.img" % book)
		assert_true(img != null, "import the Pirate manifest fragment")
		if img == null:
			lib.free()
			return
		books[book] = img.root
	var book := SkillBook.from_data(DataRepo.load_all().skills, books)
	var loadout := Loadout.new(book)
	for key in ["improve_maxhp", "knuckler_mastery", "gun_mastery", "knuckler_booster", "gun_booster"]:
		assert_eq(book.max_level(key), 10 if key == "improve_maxhp" else 20, key)
		assert_eq(book.max_rank(key), book.max_level(key))
	for rank_value in [1, 10]:
		assert_eq(book.canonical("improve_maxhp", rank_value, "x", 0.0), 3.0 * rank_value)
	for key in ["knuckler_mastery", "gun_mastery"]:
		assert_eq(book.canonical(key, 1, "mastery", 0.0), 1.0)
		assert_eq(book.canonical(key, 4, "mastery", 0.0), 2.0)
		assert_eq(book.canonical(key, 20, "mastery", 0.0), 10.0)
		assert_eq(book.canonical(key, 20, "x", 0.0), 20.0)
		assert_eq(book.weapon_families(key), PackedStringArray(["knuckle" if key.begins_with("knuckler") else "gun"]))
	for key in ["knuckler_booster", "gun_booster"]:
		for rank_value in [1, 20]:
			var st := loadout.stats(key, rank_value)
			assert_eq(st.mp_cost, 29 if rank_value == 1 else 10, key)
			assert_eq(st.hp_cost, 29 if rank_value == 1 else 10, key)
			assert_eq(st.duration, 10.0 if rank_value == 1 else 200.0, key)
			assert_eq(st.buff_effects.get("attack_speed"), 2.0, "x = -2 with scale -1: two steps faster")
		assert_true(lib.sound(book.def(key).sounds.use) != null, key + " use sound")
		assert_false(lib.anim(String(book.def(key).effect)).is_empty(), key + " effect art")
		assert_true(lib.node("Character.wz/00002000.img/alert2") is Dictionary)
	for key in ["improve_maxhp", "knuckler_mastery", "gun_mastery", "knuckler_booster", "gun_booster"]:
		assert_false(lib.node(String(book.def(key).icon)) == null, key + " icon")
	for item in [PRIME_HANDS, COLD_MIND]:
		var info: Dictionary = lib.node("Character.wz/Weapon/%08d.img/info" % item)
		assert_eq(int(info.get("reqLevel", 0)), 30)
		assert_eq(int(info.get("reqJob", 0)), 16)
	for ammo in [2330001, 2330002]:
		assert_false(lib.anim("Item.wz/Consume/0233.img/%08d/bullet" % ammo).is_empty(), "bullet %d sprite" % ammo)
	assert_eq(Array(lib.missing), [])
	lib.free()
