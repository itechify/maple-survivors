extends TestCase
## Weapon attack speed and Boosters (spec #151 ticket #160, docs/GAME_DESIGN.md 6.1.1 and 7.7): the v83 speed table,
## the weapon's swing timing (WeaponReach.action_spec; the automatic basic attack is gone, #284) and attack-skill timing
## under a Booster, which counts whatever weapon is held (weapons gate no skill, #284). Every skill here is
## synthetic (no cache); the Booster is a stand-in for the class specs' real ones.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
## Synthetic info nodes: the creation Sword (speed 4, family sword) and a Wand (speed 6, family wand).
const SWORD := 1302000
const WAND := 1372005


## A quiet world wearing the creation Sword (speed 4) with the wand in the inventory, plus two synthetic skills:
## sword_booster (+2 attack speed steps for 10 s, sword only) and probe (a fixed-damage active skill, cooldown 1 s,
## action 0.8 s, any weapon).
func _world(p_seed := 160) -> RunWorld:
	var data := RF.quiet_data()
	data.upgrades.cards = []
	data.jobs_survivor.jobs["212"]["starting_skill"] = ""; data.jobs_survivor.jobs["212"]["mobility_skill"] = ""
	data.balance.magnet_radius = 0
	data.skills.skills["sword_booster"] = {"skill_id": 9991100, "book": "999", "kind": "buff", "slot": "passive",
		"name": "Booster", "damage": "none", "ranks": [1], "action": "", "action_time": 0.0,
		"weapon_families": ["sword"], "icon": "Skill.wz/999.img/skill/9991100/icon",
		"buff": {"duration_field": "time", "effects": [{"stat": "attack_speed", "field": "x"}]}}
	data.skills.skills["probe"] = {"skill_id": 9991101, "book": "999", "kind": "instant", "slot": "active",
		"name": "Probe", "damage": "fixed", "ranks": [1], "cooldown": 1.0, "range": 300, "count": 1,
		"action": "swingO1", "action_time": 0.8, "icon": "Skill.wz/999.img/skill/9991101/icon"}
	var setup := RF.with_basic_attack(RF.setup("quiet", p_seed, data))
	setup.skill_imgs["999"] = {"skill": {
		"9991100": {"level": {"1": {"x": 2, "time": 10, "mpCon": 0}}},
		"9991101": {"level": {"1": {"fixdamage": 5, "mpCon": 0}}}}}
	var character := RunWorld.new(setup).character_snapshot()
	character.equipment.inventory.append(Equipment.create(WAND, setup.equipment_info[WAND]))
	setup.character = character
	var w := RunWorld.new(setup)
	RF.place_player(w, 400)
	w.player.facing = 1
	w.god = true
	w.drain_events()
	return w


func _wear(w: RunWorld, id: int) -> void:
	for i in w.equipment.inventory.size():
		if int(w.equipment.inventory[i].id) == id:
			assert_eq(w.equip_item(i), "", "wearing %d" % id)
			return
	assert_true(false, "item %d is in the inventory" % id)


## A mob that neither moves nor dies, within the swing and the probe's range.
func _dummy(w: RunWorld, x := 450.0) -> int:
	w.mob_kinds[int(w.kind_of_id[100100])].move_speed = 0
	return RF.put_mob(w, 100100, x, 190, 100000)


func _first(w: RunWorld, type: String, phase := "") -> Dictionary:
	for e: Dictionary in w.drain_events():
		if e.type == type and (phase == "" or e.get("phase", "") == phase):
			return e
	return {}


# --- The speed table ---------------------------------------------------------------------------------------------

func test_the_speed_table_gives_the_v83_delay_and_swing_interval_of_each_step() -> void:
	# tier B: 50 ms per step on 500 ms (speed 6 is the normal 800 ms), the swing interval rounded up to 30 ms.
	for row: Array in [[2, 600, 0.60], [3, 650, 0.66], [4, 700, 0.72], [5, 750, 0.75], [6, 800, 0.81],
			[7, 850, 0.87], [8, 900, 0.90], [9, 950, 0.96]]:
		assert_eq(WeaponInfo.speed_delay_ms(int(row[0])), float(row[1]), "delay of speed %d" % row[0])
		assert_near(WeaponInfo.attack_interval({"attackSpeed": row[0]}), float(row[2]), 1e-9, "interval of speed %d" % row[0])


func test_booster_steps_lower_the_speed_number_and_stop_at_the_fastest_step() -> void:
	assert_eq(WeaponInfo.effective_speed(6, 2), 4)
	assert_eq(WeaponInfo.effective_speed(4, 2), 2)
	assert_eq(WeaponInfo.effective_speed(4, 5), 2, "nothing is faster than speed 2")
	assert_eq(WeaponInfo.effective_speed(7, 0), 7)
	assert_eq(WeaponInfo.effective_speed(9, -3), 9, "nothing is slower than speed 9")
	assert_near(WeaponInfo.attack_interval({"attackSpeed": 6}, 2), 0.72, 1e-9, "a Booster on a Wand swings like a Sword")
	assert_near(WeaponInfo.attack_interval({"attackSpeed": 4}, 2), 0.60, 1e-9)
	assert_near(WeaponInfo.speed_factor(6, 2), 700.0 / 800.0, 1e-12, "timing scales by the delay ratio")
	assert_near(WeaponInfo.speed_factor(4, 2), 600.0 / 700.0, 1e-12)
	assert_eq(WeaponInfo.speed_factor(6, 0), 1.0, "no Booster: exactly today's timing")


func test_the_weapon_speed_is_the_attack_speed_step_and_bare_hands_keep_six() -> void:
	var w := _world()
	assert_eq(w.loadout.weapon_speed, 4, "the creation Sword")
	_wear(w, WAND)
	assert_eq(w.loadout.weapon_speed, 6, "the Wand")
	assert_eq(w.unequip_item("weapon"), "")
	assert_eq(w.loadout.weapon_speed, WeaponInfo.NORMAL_SPEED, "bare hands")
	assert_eq(WeaponInfo.NORMAL_SPEED, 6)


# --- Weapon swing timing ---------------------------------------------------------------------------------------------

func test_the_swing_timing_without_a_booster_is_canonical() -> void:
	var w := _world()
	var spec := w.weapon_reach.action_spec(SWORD, w.weapon_info(), "swingO1", w.loadout.speed_steps)
	assert_near(float(spec.interval), 0.72, 1e-9)
	assert_near(float(spec.hit_after), 0.45, 1e-9, "canonical body delays")
	assert_near(float(spec.action_time), 0.8, 1e-9, "the canonical stance length")
	assert_eq(float(spec.scale), 1.0)


func test_a_booster_shortens_the_swing_interval_impact_and_stance_by_two_steps() -> void:
	var w := _world()
	w.learn_skill("sword_booster")
	w.step(DT, MoveInput.new())
	assert_true(w.buffs.has("sword_booster"))
	assert_eq(w.loadout.speed_steps, 2)
	var spec := w.weapon_reach.action_spec(SWORD, w.weapon_info(), "swingO1", w.loadout.speed_steps)
	# Sword speed 4 - 2 = 2: 600 ms -> 0.60 s interval; body delays x 600/700.
	assert_near(float(spec.interval), 0.60, 1e-9)
	assert_near(float(spec.hit_after), 0.45 * 600.0 / 700.0, 1e-9)
	assert_near(float(spec.action_time), 0.8 * 600.0 / 700.0, 1e-9)
	assert_near(float(spec.scale), 600.0 / 700.0, 1e-9, "the avatar plays its frames faster")


func test_a_booster_gives_the_wand_the_swords_normal_interval() -> void:
	# The same buff on a speed-6 weapon (6 - 2 = 4 -> 0.72 s).
	var w := _world()
	_wear(w, WAND)
	w.learn_skill("sword_booster")
	w.step(DT, MoveInput.new())
	var spec := w.weapon_reach.action_spec(WAND, w.weapon_info(), "swingO1", w.loadout.speed_steps)
	assert_near(float(spec.interval), 0.72, 1e-9)


# --- Attack skills ---------------------------------------------------------------------------------------------------

func test_an_attack_skill_keeps_its_cooldown_and_action_time_without_a_booster() -> void:
	var w := _world()
	w.learn_skill("probe")
	var st := w.loadout.stats("probe")
	assert_eq(st.cooldown, 1.0)
	assert_eq(st.action_time, 0.8)
	assert_eq(st.speed_factor, 1.0)


func test_a_booster_shortens_an_attack_skills_action_time_and_cooldown() -> void:
	var w := _world()
	w.learn_skill("sword_booster") # learned first: it casts first, the probe on the next tick
	w.learn_skill("probe")
	_dummy(w)
	w.step(DT, MoveInput.new()) # the Booster
	assert_true(w.buffs.has("sword_booster"))
	var st := w.loadout.stats("probe")
	var f := 600.0 / 700.0
	assert_near(st.cooldown, 1.0 * f, 1e-9)
	assert_near(st.action_time, 0.8 * f, 1e-9)
	var cast := {}
	for tick in 20:
		w.step(DT, MoveInput.new())
		for e: Dictionary in w.drain_events():
			if e.type == "cast" and e.skill == "probe":
				cast = e
		if not cast.is_empty():
			break
	assert_eq(cast.get("skill", ""), "probe", "the probe fires")
	assert_near(w.runner.cooldown_totals.probe, 1.0 * f, DT + 1e-9, "its cooldown restarts shortened")
	# Buffs and passives are not attack skills: the Booster's own cooldown (its duration) is not scaled.
	assert_eq(w.loadout.stats("sword_booster").speed_factor, 1.0)


# --- No family gating (#284) --------------------------------------------------------------------------------------

func test_the_booster_counts_whatever_weapon_is_held() -> void:
	var w := _world()
	w.learn_skill("sword_booster")
	_dummy(w)
	w.step(DT, MoveInput.new())
	assert_eq(w.loadout.speed_steps, 2, "sword held")
	_wear(w, WAND)
	assert_true(w.buffs.has("sword_booster"), "the buff keeps running")
	assert_eq(w.loadout.speed_steps, 2, "a Wand gets the Booster's steps too: weapons gate no skill")
	assert_eq(w.unequip_item("weapon"), "")
	assert_eq(w.loadout.speed_steps, 2, "and so do bare hands")
	assert_eq(w.loadout.weapon_speed, 6)


func test_the_booster_recasts_when_it_expires() -> void:
	var w := _world()
	w.learn_skill("sword_booster")
	w.step(DT, MoveInput.new())
	assert_true(w.buffs.has("sword_booster"))
	assert_eq(w.loadout.speed_steps, 2)
	w.buffs.active.sword_booster.remaining = DT * 0.5
	w.runner.cooldowns["sword_booster"] = 0.0
	w.step(DT, MoveInput.new())
	assert_true(w.buffs.has("sword_booster"), "recast on expiry")
	assert_eq(w.loadout.speed_steps, 2)
	w.buffs.active.sword_booster.remaining = DT * 0.5
	w.runner.cooldowns["sword_booster"] = 100.0
	w.step(DT, MoveInput.new())
	assert_false(w.buffs.has("sword_booster"), "expired while on cooldown")
	assert_eq(w.loadout.speed_steps, 0, "expiry drops the steps and re-resolves the skills")
	assert_eq(w.loadout.stats("sword_booster").speed_factor, 1.0)


# --- Today's timing ------------------------------------------------------------------------------------------------------

func test_magician_wand_skills_and_swings_keep_their_current_timing() -> void:
	# The Wand is speed 6 and there is no Booster: every factor is exactly 1.0, so nothing moves.
	var w := _world()
	RF.as_job(w, 200)
	assert_eq(w.weapon_id(), WAND, "the Magician stands with the Wand (RF.as_job)")
	w.learn_skill("energy_bolt")
	var st := w.loadout.stats("energy_bolt")
	assert_eq(w.loadout.weapon_speed, 6)
	assert_eq(st.speed_factor, 1.0)
	assert_eq(st.cooldown, 0.36, "Energy Bolt's #293 tier C cooldown")
	assert_eq(st.action_time, 0.8, "and its stance")
	var spec := w.weapon_reach.action_spec(WAND, w.weapon_info(), "swingO1")
	assert_near(float(spec.interval), 0.81, 1e-9)
	assert_near(float(spec.hit_after), 0.45, 1e-12)
	assert_near(float(spec.action_time), 0.8, 1e-12)
	assert_eq(float(spec.scale), 1.0)
