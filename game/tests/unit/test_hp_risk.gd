extends TestCase
## HP-risk seam (M17, spec #348 ticket D3): percentage HP cost, HP gate, recoil, low-HP damage and the `hp_spent` event,
## on a SYNTHETIC skill ("risky", book 999) that uses no Dark Knight data. This file is the template a later job's HP-risk
## tests copy: build the skill with `_world(def_extra, level_extra)`, set HP with `_hp`, cast with `_cast`. Seeded, fixed ticks.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
## Base HP of the synthetic world (balance.player.hp).
const MAX_HP := 275
## Mob 1110100's body is shrunk to a 10 px square so every placement below is about the box.
const MOB := 1110100


## A world with the synthetic "risky" skill learned. `def_extra` is merged over the skill definition (hp_cost, hp_gate,
## self_damage ...), `level_extra` over the level-1 canonical numbers (x = 33 is the percentage the blocks read).
func _world(def_extra: Dictionary = {}, level_extra: Dictionary = {}, p_seed := 31) -> RunWorld:
	var data := RF.quiet_data()
	data.balance.player.hp = MAX_HP
	data.balance.magnet_radius = 0
	var def := {"skill_id": 9991000, "book": "999", "kind": "instant", "damage": "fixed", "ranks": [1, 2],
		"cooldown": 1.0, "range": 400.0, "cast": {"rule": "box"}}
	def.merge(def_extra, true)
	data.skills.skills["risky"] = def
	var setup := RF.setup("quiet", p_seed, data)
	var level := {"lt": {"$v": [-100.0, -60.0]}, "rb": {"$v": [20.0, 0.0]}, "mobCount": 3.0,
		"attackCount": 2.0, "fixdamage": 10.0, "x": 33.0}
	level.merge(level_extra, true)
	setup.skill_imgs["999"] = {"skill": {"9991000": {"level": {"1": level, "2": level}}}}
	var w := RunWorld.new(setup)
	for mk: MobKind in w.mob_kinds:
		mk.hitbox = Rect2(-5, -10, 10, 10)
		mk.move_speed = 0.0
	w.loadout.order.clear()
	w.learn_skill("risky")
	RF.place_player(w, 400)
	w.player.facing = -1
	w.god = false
	w.drain_events()
	return w


func _mob(w: RunWorld, dx: float) -> int:
	return RF.put_mob(w, MOB, w.player.pos.x + dx, 190.0, 1000.0)


## Sets the HP pool directly and refreshes the published player_state.
func _hp(w: RunWorld, hp: float) -> void:
	w._hp = hp
	w._write_player_state(0.0)


## One runner step with the grid rebuilt: the events it produced.
func _cast(w: RunWorld) -> Array:
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	w.drain_events()
	w.runner.step(DT, w)
	return w.drain_events()


func _of(events: Array, type: String) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return e.type == type)


# --- percentage HP cost ---------------------------------------------------------------------------------------

func test_a_percentage_cost_is_the_floor_of_the_share_of_max_hp() -> void:
	var w := _world({"hp_cost": {"field": "x", "of": "max_hp"}})
	assert_eq(int(w.player_state.max_hp), MAX_HP, "the fixture's max HP")
	assert_eq(w.loadout.stats("risky").hp_cost, 90, "floor(33% of 275) = floor(90.75)")


func test_a_flat_cost_block_and_no_block_both_keep_the_canonical_number() -> void:
	var w := _world({"hp_cost": {"field": "x", "of": "flat"}})
	assert_eq(w.loadout.stats("risky").hp_cost, 33, "of: flat reads the named field as is")
	w = _world({}, {"hpCon": 12.0})
	assert_eq(w.loadout.stats("risky").hp_cost, 12, "no block: today's hpCon")


func test_the_percentage_follows_max_hp_when_it_changes() -> void:
	var w := _world({"hp_cost": {"field": "x", "of": "max_hp"}})
	w.loadout.add_player_mod("max_hp", "add", 125.0)
	w.refresh_player_stats()
	assert_eq(int(w.player_state.max_hp), 400)
	assert_eq(w.loadout.stats("risky").hp_cost, 132, "33% of 400, resolved again after the refresh")


func test_the_cast_pays_the_percentage_and_reports_it_as_a_cost() -> void:
	var w := _world({"hp_cost": {"field": "x", "of": "max_hp"}})
	_mob(w, -50.0)
	var events := _cast(w)
	assert_eq(_of(events, "cast").size(), 1)
	assert_eq(int(w.player_state.hp), MAX_HP - 90)
	var spent := _of(events, "hp_spent")
	assert_eq(spent.size(), 1)
	assert_eq(spent[0].amount, 90)
	assert_eq(spent[0].kind, "cost")
	assert_eq(spent[0].skill, "risky")
	assert_eq(spent[0].skill_id, 9991000)


func test_a_cast_that_would_leave_no_hp_waits_and_spends_nothing() -> void:
	var w := _world({"hp_cost": {"field": "x", "of": "max_hp"}})
	var m := _mob(w, -50.0)
	_hp(w, 90.0) # exactly the cost: paying it would kill
	var events := _cast(w)
	assert_eq(_of(events, "cast").size(), 0)
	assert_eq(_of(events, "hp_spent").size(), 0, "nothing paid, nothing reported")
	assert_eq(int(w.player_state.hp), 90)
	assert_eq(w.swarm.hp[m], w.swarm.max_hp[m])
	assert_true(float(w.runner.cooldowns.get("risky", 0.0)) <= 1e-6, "a refused cast takes no cooldown")
	_hp(w, 91.0)
	events = _cast(w)
	assert_eq(_of(events, "cast").size(), 1, "one HP to spare is enough")
	assert_eq(int(w.player_state.hp), 1)


func test_a_flat_hpcon_skill_keeps_its_exact_cost_and_now_reports_it() -> void:
	var w := _world({}, {"hpCon": 12.0})
	_mob(w, -50.0)
	var events := _cast(w)
	assert_eq(int(w.player_state.hp), MAX_HP - 12)
	var spent := _of(events, "hp_spent")
	assert_eq(spent.size(), 1)
	assert_eq(spent[0].amount, 12)
	assert_eq(spent[0].kind, "cost")


func test_a_skill_that_costs_no_hp_reports_no_hp_spent() -> void:
	var w := _world()
	_mob(w, -50.0)
	var events := _cast(w)
	assert_eq(_of(events, "cast").size(), 1)
	assert_eq(_of(events, "hp_spent").size(), 0, "never at zero")


# --- HP gate --------------------------------------------------------------------------------------------------

func test_the_gate_blocks_at_exactly_the_threshold_and_passes_one_hp_above() -> void:
	var w := _world({"hp_gate": {"above": 0.4}}) # 40% of 275 = 110
	var m := _mob(w, -50.0)
	_hp(w, 110.0)
	var events := _cast(w)
	assert_eq(_of(events, "cast").size(), 0, "exactly 40%: not strictly above")
	assert_eq(w.swarm.hp[m], w.swarm.max_hp[m])
	assert_true(float(w.runner.cooldowns.get("risky", 0.0)) <= 1e-6, "a gated cast takes no cooldown")
	assert_eq(int(w.player_state.hp), 110, "and spends nothing")
	_hp(w, 111.0)
	assert_eq(_of(_cast(w), "cast").size(), 1, "one HP above passes")


func test_a_cast_that_drops_hp_to_the_gate_blocks_the_next_until_hp_recovers() -> void:
	var w := _world({"hp_gate": {"above": 0.5}, "hp_cost": {"field": "x", "of": "max_hp"}}) # gate 137.5, cost 90
	_mob(w, -50.0)
	_hp(w, 200.0)
	assert_eq(_of(_cast(w), "cast").size(), 1, "above the gate: casts")
	assert_eq(int(w.player_state.hp), 110, "and pays 90")
	w.runner.cooldowns["risky"] = 0.0
	assert_eq(_of(_cast(w), "cast").size(), 0, "now below the gate: blocked although the cooldown is over")
	_hp(w, 138.0)
	assert_eq(_of(_cast(w), "cast").size(), 1, "recovered past 137.5")


func test_the_gate_and_the_never_lethal_rule_both_have_to_pass() -> void:
	var w := _world({"hp_gate": {"above": 0.0001}, "hp_cost": {"field": "x", "of": "max_hp"}})
	_mob(w, -50.0)
	_hp(w, 90.0) # above the gate, but paying 90 would leave 0
	assert_eq(_of(_cast(w), "cast").size(), 0)
	assert_eq(int(w.player_state.hp), 90)


func test_the_gate_is_part_of_the_resolved_stats_for_previews() -> void:
	var w := _world({"hp_gate": {"above": 0.5}})
	assert_near(float(w.loadout.stats("risky").hp_gate), 0.5, 1e-9)
	assert_near(float(_world().loadout.stats("risky").hp_gate), 0.0, 1e-9, "no block: no gate")


# --- recoil (self_damage) ---------------------------------------------------------------------------------------

const RECOIL := {"field": "x", "of": "damage_dealt", "cap_max_hp": 0.5}


## Three mobs in the box, two lines each (mobCount 3, attackCount 2 of the synthetic level).
func _crowd(w: RunWorld) -> Array[int]:
	return [_mob(w, -40.0), _mob(w, -50.0), _mob(w, -60.0)]


func _dealt(events: Array) -> int:
	var total := 0
	for e: Dictionary in _of(events, "mob_hit"):
		total += int(e.damage)
	return total


func test_recoil_is_a_share_of_the_damage_applied_over_every_line_and_target() -> void:
	var w := _world({"self_damage": RECOIL})
	_crowd(w)
	var events := _cast(w)
	assert_eq(_of(events, "mob_hit").size(), 6, "three targets, two lines each")
	var dealt := _dealt(events)
	assert_eq(dealt, 60, "fixed 10 per line")
	var spent := _of(events, "hp_spent")
	assert_eq(spent.size(), 1)
	assert_eq(spent[0].kind, "recoil")
	assert_eq(spent[0].amount, 19, "floor(33% of 60) = floor(19.8)")
	assert_eq(int(w.player_state.hp), MAX_HP - 19)


func test_recoil_is_capped_at_a_share_of_max_hp() -> void:
	var w := _world({"self_damage": {"field": "x", "of": "damage_dealt", "cap_max_hp": 0.05}}) # floor(13.75) = 13
	_crowd(w)
	var spent := _of(_cast(w), "hp_spent")
	assert_eq(spent.size(), 1)
	assert_eq(spent[0].amount, 13)
	assert_eq(int(w.player_state.hp), MAX_HP - 13)


func test_recoil_never_takes_the_last_hp() -> void:
	var w := _world({"self_damage": RECOIL})
	_crowd(w)
	_hp(w, 10.0)
	var spent := _of(_cast(w), "hp_spent")
	assert_eq(int(w.player_state.hp), 1, "the cast still happened; the recoil stops at 1 HP")
	assert_eq(spent[0].amount, 9, "the report names what was actually paid")
	_hp(w, 1.0)
	w.runner.cooldowns["risky"] = 0.0
	var events := _cast(w)
	assert_eq(_of(events, "cast").size(), 1, "at 1 HP the cast still fires")
	assert_eq(_of(events, "hp_spent").size(), 0, "with nothing left to pay, nothing is reported")
	assert_eq(int(w.player_state.hp), 1)


func test_recoil_is_zero_when_the_cast_hit_nothing() -> void:
	var st := {"self_damage": 33.0, "self_damage_cap": 0.5}
	assert_eq(HpRisk.recoil(st, 0, 275.0, 275.0), 0, "no damage applied, no recoil")
	assert_eq(HpRisk.recoil({"self_damage": 0.0, "self_damage_cap": 1.0}, 500, 275.0, 275.0), 0, "no self_damage block")
	assert_eq(HpRisk.recoil(st, 60, 275.0, 275.0), 19, "the same stats with damage")
	assert_eq(HpRisk.recoil(st, 60, 1.5, 275.0), 0, "floor(hp - 1) of a fractional 1.5 HP is 0")


func test_cost_and_recoil_are_two_reports_in_that_order() -> void:
	var w := _world({"self_damage": RECOIL, "hp_cost": {"field": "x", "of": "max_hp"}})
	_crowd(w)
	var spent := _of(_cast(w), "hp_spent")
	assert_eq(spent.map(func(e: Dictionary) -> String: return e.kind), ["cost", "recoil"])
	assert_eq(spent.map(func(e: Dictionary) -> int: return e.amount), [90, 19])
	assert_eq(int(w.player_state.hp), MAX_HP - 90 - 19)


# --- low_hp_damage (Berserk) ------------------------------------------------------------------------------------

func _hit_damages(w: RunWorld) -> Array:
	return _of(_cast(w), "mob_hit").map(func(e: Dictionary) -> int: return int(e.damage))


func test_low_hp_damage_applies_at_or_below_half_hp_and_not_one_hp_above() -> void:
	# Max HP 275: half is 137.5, so 137 is below, 137.5 is exactly at, and 138 is the first whole HP above.
	for case: Array in [[137.0, 15], [137.5, 15], [138.0, 10]]:
		var w := _world()
		w.loadout.add_skill_mod("risky", "low_hp_damage", "add", 0.5)
		_mob(w, -50.0)
		_hp(w, float(case[0]))
		assert_eq(_hit_damages(w), [case[1], case[1]], "two lines at hp %s" % case[0])


func test_low_hp_damage_adds_nothing_without_the_modifier() -> void:
	var w := _world()
	_mob(w, -50.0)
	_hp(w, 20.0)
	assert_eq(_hit_damages(w), [10, 10])


func test_low_hp_damage_reads_hp_at_the_moment_of_the_cast_before_the_cost_is_paid() -> void:
	var w := _world({"hp_cost": {"field": "x", "of": "max_hp"}}) # pays 90
	w.loadout.add_skill_mod("risky", "low_hp_damage", "add", 0.5)
	_mob(w, -50.0)
	_hp(w, 140.0) # above half before paying, 50 after
	assert_eq(_hit_damages(w), [10, 10], "the HP it started with decides, not the HP the cost leaves")


func test_low_hp_damage_stacks_additively_and_is_a_resolved_stat() -> void:
	var w := _world()
	w.loadout.add_skill_mod("risky", "low_hp_damage", "add", 0.5)
	w.loadout.add_skill_mod("risky", "low_hp_damage", "add", 0.2)
	assert_near(float(w.loadout.stats("risky").low_hp_damage), 0.7, 1e-6)
	_mob(w, -50.0)
	_hp(w, 100.0)
	assert_eq(_hit_damages(w), [17, 17], "x1.7 of 10")


# --- modifier stats, previews and text -------------------------------------------------------------------------

func test_the_hp_cost_modifier_scales_a_percentage_and_a_flat_cost() -> void:
	var w := _world({"hp_cost": {"field": "x", "of": "max_hp"}})
	w.loadout.add_skill_mod("risky", "hp_cost", "mul", 0.5)
	assert_eq(w.loadout.stats("risky").hp_cost, 45, "floor(0.5 x 90.75)")
	w = _world({}, {"hpCon": 12.0})
	w.loadout.add_skill_mod("risky", "hp_cost", "mul", 0.8)
	assert_eq(w.loadout.stats("risky").hp_cost, 9, "floor(0.8 x 12)")
	_mob(w, -50.0)
	assert_eq(_of(_cast(w), "hp_spent")[0].amount, 9, "the cast pays the scaled cost")


func test_the_self_damage_modifier_scales_the_recoil() -> void:
	var w := _world({"self_damage": RECOIL})
	w.loadout.add_skill_mod("risky", "self_damage", "mul", 0.5)
	_crowd(w)
	var spent := _of(_cast(w), "hp_spent")
	assert_eq(spent[0].amount, 9, "floor(16.5% of 60) = floor(9.9)")


func _card_world(def_extra: Dictionary, bonus: Dictionary) -> RunWorld:
	var data := RF.quiet_data()
	data.upgrades.cards.append({"id": "risky_rank", "power": true, "kind": "skill_rank", "skill": "risky", "name": "Risky",
		"desc": "+{magnitude}", "icon": "", "max_rank": 8})
	var w := _world(def_extra)
	w.book.defs.risky.rarity_bonuses = {"legendary": [bonus]}
	w.upgrades = UpgradePool.from_data(data.upgrades)
	w.upgrades.add_pool_skills(w.book, w.jobs)
	return w


func test_cards_preview_the_three_hp_risk_stats_before_and_after() -> void:
	var w := _card_world({"hp_cost": {"field": "x", "of": "max_hp"}, "self_damage": RECOIL},
		{"id": "b", "name": "Careful", "effects": [{"stat": "hp_cost", "op": "mul", "value": 0.5},
			{"stat": "self_damage", "op": "mul", "value": 0.5}, {"stat": "low_hp_damage", "op": "add", "value": 0.5}]})
	var c := w.upgrades.choice_card("risky_rank", w, "legendary")
	assert_eq(c.skill_mod_changes.hp_cost, {"before": 90, "after": 45})
	assert_eq(c.skill_mod_changes.self_damage, {"before": 33.0, "after": 16.5})
	assert_eq(c.skill_mod_changes.low_hp_damage, {"before": 0, "after": 50})
	w.upgrades.apply(c.id, w, "legendary")
	var st := w.loadout.stats("risky")
	assert_eq(st.hp_cost, 45)
	assert_near(float(st.self_damage), 16.5, 1e-3)
	assert_near(float(st.low_hp_damage), 0.5, 1e-6)


func test_the_skill_text_names_the_gate_the_recoil_and_the_low_hp_bonus() -> void:
	var w := _world({"hp_gate": {"above": 0.5}, "self_damage": RECOIL})
	w.loadout.add_skill_mod("risky", "low_hp_damage", "add", 0.5)
	var line := SkillText.new(w.book).level_line("risky", 1, w.loadout.stats("risky"))
	assert_true("Needs more than 50% HP" in line, line)
	assert_true("Recoil: 33% of damage dealt" in line, line)
	assert_true("+50% damage at 50% HP or less" in line, line)


# --- consumers and determinism -----------------------------------------------------------------------------------

func test_the_bot_counts_a_gated_skill_ready_only_while_its_gate_is_open() -> void:
	var w := _world({"hp_gate": {"above": 0.5}})
	assert_true(BotInput._reach_profile(w, float(BotInput._engage_config(w).kite_reach)).x > 0.0, "the skill has a reach the bot knows")
	assert_eq(BotInput._reach_profile(w, float(BotInput._engage_config(w).kite_reach)).y, BotInput._reach_profile(w, float(BotInput._engage_config(w).kite_reach)).x, "ready at full HP")
	_hp(w, 137.5)
	assert_eq(BotInput._reach_profile(w, float(BotInput._engage_config(w).kite_reach)).y, 0.0, "not ready at exactly the gate")


func test_admission_asks_the_gate_and_the_cost_together() -> void:
	var w := _world({"hp_gate": {"above": 0.5}})
	var st := w.runner.stats_of(w, "risky")
	_hp(w, 100.0)
	assert_false(HpRisk.admits(w, st), "the shared admission the meter's preferred() also asks")
	_hp(w, 200.0)
	assert_true(HpRisk.admits(w, st))


func test_hp_risk_draws_no_random_numbers() -> void:
	var plain := _world({}, {}, 77)
	var risky := _world({"hp_gate": {"above": 0.1}, "hp_cost": {"field": "x", "of": "max_hp"},
		"self_damage": RECOIL}, {}, 77)
	risky.loadout.add_skill_mod("risky", "low_hp_damage", "add", 0.5)
	for w: RunWorld in [plain, risky]:
		_crowd(w)
		_hp(w, 200.0)
	_cast(plain)
	_cast(risky)
	assert_eq(risky.rng.state, plain.rng.state, "same stream state after the same cast")
	assert_eq(int(risky.player_state.hp), 200 - 90 - 19, "while the risk itself happened")


func test_low_hp_threshold_comes_from_each_skill_definition() -> void:
	var w := _world({"low_hp_damage": {"at_or_below": 0.25}})
	w.loadout.add_skill_mod("risky", "low_hp_damage", "add", 0.5)
	_mob(w, -50.0)
	_hp(w, 100.0)
	assert_eq(_hit_damages(w), [10, 10], "above this skill's quarter-HP threshold")
	w = _world({"low_hp_damage": {"at_or_below": 0.25}})
	w.loadout.add_skill_mod("risky", "low_hp_damage", "add", 0.5)
	_mob(w, -50.0)
	_hp(w, 68.75)
	assert_eq(_hit_damages(w), [15, 15], "exactly a quarter of 275 HP")
	var line := SkillText.new(w.book).level_line("risky", 1, w.loadout.stats("risky"))
	assert_true("25% HP or less" in line, line)
