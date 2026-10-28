extends TestCase
## Shared passives and buffs of the physical foundation (spec #151 ticket #161, docs/GAME_DESIGN.md 7.6): weapon Mastery
## (mastery + ACC), Critical Shot-style crit passives, Improved MaxHP Increase per level-up, Rage-style W.Att buffs with a
## WDEF side effect, and the Final Attack follow-up on RNG stream 12. Every skill here is synthetic (no cache). Since #284
## weapons gate no skill or passive: a skill's `weapon_families` no longer switches it off for another weapon.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
## Synthetic Character.wz info nodes: no requirements, so any of them can be worn.
const INFO := {
	1302000: {"incPAD": 17, "attackSpeed": 4, "tuc": 7},
	1332063: {"incPAD": 20, "attackSpeed": 4, "tuc": 7},
	1452000: {"incPAD": 20, "attackSpeed": 4, "tuc": 7},
}


## One passive skill entry of skills.json shape.
func _passive(id: int, families: Array, passive: Dictionary, ranks := 2) -> Dictionary:
	var out := {"skill_id": id, "book": "999", "job": 0, "kind": "passive", "slot": "passive", "name": "P%d" % id,
		"damage": "none", "ranks": range(1, ranks + 1), "passive": passive, "action": "", "action_time": 0.0,
		"icon": "Skill.wz/999.img/skill/%d/icon" % id}
	if not families.is_empty():
		out["weapon_families"] = families
	return out


## A quiet world wearing the creation sword, with a dagger and a bow in the inventory and these synthetic skills known
## (not learned): sword_mastery (mastery N and ACC x, sword only), crit_blade (crit_chance prop and crit_damage damage,
## sword only), improved_hp (max_hp_per_level x, any weapon).
func _world(p_seed := 161, mutate: Callable = Callable()) -> RunWorld:
	var data := RF.quiet_data()
	data.skills.skills["sword_mastery"] = _passive(9991000, ["sword"], {"stat": "mastery", "field": "mastery",
		"effects": [{"stat": "acc", "field": "x"}]})
	data.skills.skills["crit_blade"] = _passive(9991001, ["sword"], {"stat": "crit_chance", "field": "prop",
		"effects": [{"stat": "crit_damage", "field": "damage"}]})
	data.skills.skills["improved_hp"] = _passive(9991002, [], {"stat": "max_hp_per_level", "field": "x"}, 3)
	if mutate.is_valid():
		mutate.call(data)
	var setup := RF.setup("quiet", p_seed, data)
	setup.equipment_info = INFO.duplicate(true)
	setup.skill_imgs["999"] = {"skill": {
		"9991000": {"level": {"1": {"mastery": 2, "x": 5}, "2": {"mastery": 10, "x": 20}}},
		"9991001": {"level": {"1": {"prop": 20, "damage": 150}, "2": {"prop": 40, "damage": 200}}},
		"9991002": {"level": {"1": {"x": 4}, "2": {"x": 8}, "3": {"x": 12}}}}}
	var character := RunWorld.new(setup).character_snapshot()
	for id: int in [1332063, 1452000]:
		character.equipment.inventory.append(Equipment.create(id, INFO[id]))
	setup.character = character
	var w := RunWorld.new(setup)
	RF.place_player(w, 200)
	w.loadout.order.clear()
	w.drain_events()
	return w


func _wear(w: RunWorld, id: int) -> void:
	for i in w.equipment.inventory.size():
		if int(w.equipment.inventory[i].id) == id:
			assert_eq(w.equip_item(i), "", "wearing %d" % id)
			return
	assert_true(false, "item %d is in the inventory" % id)


# --- Mastery and ACC ----------------------------------------------------------------------------------------------

func test_mastery_raises_min_damage_and_acc_whatever_weapon_is_held() -> void:
	var w := _world()
	var base_acc := w.loadout.acc
	assert_eq(w.loadout.mastery, 0.10, "untrained mastery is 10%")
	var untrained := w.loadout.clone()
	assert_true(w.learn_skill("sword_mastery"))
	# tier B: the WZ mastery value N means (10 + 5N)%, as for the magic masteries (v83-facts section 3).
	assert_near(w.loadout.mastery, 0.20, 0.00001, "N=2 is 20%")
	assert_near(w.loadout.acc, base_acc + 5.0, 0.00001, "Mastery's x adds ACC")
	assert_near(w.player_state.acc, base_acc + 5.0, 0.00001, "the Stat window shows the total")
	var attacker := w.loadout
	attacker.str_stat = 100.0
	attacker.dex_stat = 50.0
	attacker.luk_stat = 200.0
	attacker.watk = 100.0
	var with_mastery := CombatMath.physical_damage_range(100, 50, 200, 100, 1302000, "swing", 0, attacker.mastery)
	var without := CombatMath.physical_damage_range(100, 50, 200, 100, 1302000, "swing", 0, untrained.mastery)
	assert_true(with_mastery.x > without.x, "min damage rises with mastery")
	assert_eq(with_mastery.y, without.y, "max damage does not")
	_wear(w, 1332063) # a dagger: weapons gate no passive (#284)
	assert_near(w.loadout.mastery, 0.20, 0.00001, "a dagger keeps the sword mastery")
	assert_near(w.loadout.acc, base_acc + 5.0, 0.00001, "and its ACC")
	w.unequip_item("weapon")
	assert_near(w.loadout.mastery, 0.20, 0.00001, "bare hands too")
	_wear(w, 1302000)
	assert_near(w.loadout.mastery, 0.20, 0.00001, "the sword is back")
	w.loadout.set_rank("sword_mastery", 2)
	w.refresh_player_stats()
	assert_near(w.loadout.mastery, 0.60, 0.00001, "N=10 is 60%")
	assert_near(w.loadout.acc, base_acc + 20.0, 0.00001)


func test_the_mastery_input_reaches_resolved_physical_skill_bounds() -> void:
	var w := _world(161, func(data: Dictionary) -> void:
		data.skills.skills["strike"] = {"skill_id": 9991003, "book": "999", "kind": "instant", "damage": "physical",
			"action": "swingO1", "ranks": [1], "cooldown": 1.0, "range": 100.0})
	w.setup.skill_imgs["999"].skill["9991003"] = {"level": {"1": {"damage": 100}}}
	w.loadout.add_skill("strike")
	var before: Dictionary = w.loadout.stats("strike")
	w.learn_skill("sword_mastery")
	w.loadout.set_rank("sword_mastery", 2)
	w.refresh_player_stats()
	var after: Dictionary = w.loadout.stats("strike")
	assert_true(after.damage_min > before.damage_min, "the held family's mastery lifts the skill's minimum")
	assert_eq(after.damage_max, before.damage_max)


# --- Crit passives --------------------------------------------------------------------------------------------------

func test_crit_passives_raise_chance_and_damage_whatever_weapon_is_held() -> void:
	var w := _world()
	assert_eq(w.loadout.crit_bonus, 0.0)
	assert_eq(w.loadout.crit_damage_bonus, 0.0)
	var base_crit: float = w.loadout.stats("three_snails").crit
	w.learn_skill("crit_blade")
	assert_near(w.loadout.crit_bonus, 0.20, 0.00001, "prop 20 is a 20% chance")
	assert_near(w.loadout.crit_damage_bonus, 50.0, 0.00001, "damage 150 adds crit% - 100 skill-% points (tier B)")
	assert_near(w.loadout.stats("three_snails").crit, base_crit + 0.20, 0.00001, "every damage type crits more")
	assert_near(w.loadout.stats("three_snails").crit_damage_bonus, 50.0, 0.00001)
	_wear(w, 1452000) # a bow: weapons gate no passive (#284)
	assert_near(w.loadout.crit_bonus, 0.20, 0.00001, "a bow keeps the sword's crit passive")
	assert_near(w.loadout.crit_damage_bonus, 50.0, 0.00001)
	_wear(w, 1302000)
	w.loadout.set_rank("crit_blade", 2)
	w.refresh_player_stats()
	assert_near(w.loadout.crit_bonus, 0.40, 0.00001)
	assert_near(w.loadout.crit_damage_bonus, 100.0, 0.00001)


func test_a_crit_passive_changes_what_a_critical_hit_deals() -> void:
	var w := _world()
	w.learn_skill("crit_blade")
	w.loadout.set_rank("crit_blade", 2)
	w.refresh_player_stats()
	var mob := RF.put_mob(w, 100100, 550, 190, 10000)
	var st := w.loadout.stats("three_snails")
	st.damage_type = "physical"
	st.magic = false
	st.damage_min = 100.0
	st.damage_max = 100.0
	st.damage_pct = 1.5
	st.crit = 1.0
	w.hit_mob(mob, st, -1)
	var hit: Dictionary = w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "mob_hit")[0]
	assert_true(hit.crit)
	assert_eq(hit.damage, 250, "skill 150% plus the passive's 100 points, not x1.5")


# --- Improved MaxHP Increase ----------------------------------------------------------------------------------------

func test_max_hp_per_level_applies_at_each_level_up_after_learning_and_not_retroactively() -> void:
	var w := _world()
	var control := _world()
	w.learn_skill("improved_hp")
	assert_eq(w.player_state.max_hp, control.player_state.max_hp, "learning grants nothing retroactively (v83, tier B)")
	for world: RunWorld in [w, control]:
		world._on_level_up(world.progression.level + 1)
	assert_eq(float(w.player_state.max_hp), float(control.player_state.max_hp) + 4.0, "skill level 1: +4 per level-up")
	w.loadout.set_rank("improved_hp", 3)
	for world: RunWorld in [w, control]:
		world._on_level_up(world.progression.level + 1)
	assert_eq(float(w.player_state.max_hp), float(control.player_state.max_hp) + 4.0 + 12.0, "rank 3 pays 12 more")


# --- W.Att buffs ------------------------------------------------------------------------------------------------------

## A Rage-style buff: W.Att from `pad`, and a weapon-defence penalty from the positive WZ `pdd` taken with scale -1.
func _rage_data(data: Dictionary) -> void:
	data.skills.skills["rage"] = {"skill_id": 9991004, "book": "999", "kind": "buff", "slot": "passive", "name": "Rage",
		"damage": "none", "ranks": [1, 2], "action": "", "action_time": 0.0, "weapon_families": ["sword"],
		"icon": "Skill.wz/999.img/skill/9991004/icon",
		"buff": {"duration_field": "time", "effects": [{"stat": "watk", "field": "pad"},
			{"stat": "pdd", "field": "pdd", "scale": -1}]}}


func test_a_watk_buff_raises_damage_and_its_pdd_side_effect_lowers_defence() -> void:
	var w := _world(161, _rage_data)
	w.setup.skill_imgs["999"].skill["9991004"] = {"level": {"1": {"pad": 3, "pdd": 3, "time": 46, "mpCon": 0},
		"2": {"pad": 6, "pdd": 6, "time": 50, "mpCon": 0}}}
	w.loadout.order.clear()
	var pdd_before: float = w.hit_defense().pdd
	var watk_before := w.weapon_attack()
	var bounds_before: Vector2 = CombatMath.physical_damage_range(w.loadout.str_stat, w.loadout.dex_stat,
		w.loadout.luk_stat, w.loadout.watk, 1302000, "swing", 0, w.loadout.mastery)
	assert_true(w.learn_skill("rage"))
	w.loadout.set_rank("rage", 2)
	w.step(DT, MoveInput.new())
	assert_true(w.buffs.has("rage"), "the buff was cast")
	assert_eq(w.weapon_attack(), watk_before + 6.0, "pad adds to W.Att")
	assert_eq(w.loadout.watk, watk_before + 6.0, "and to the caster's W.Att")
	var bounds_after: Vector2 = CombatMath.physical_damage_range(w.loadout.str_stat, w.loadout.dex_stat,
		w.loadout.luk_stat, w.loadout.watk, 1302000, "swing", 0, w.loadout.mastery)
	assert_true(bounds_after.y > bounds_before.y, "damage bounds rise")
	assert_eq(w.hit_defense().pdd, pdd_before - 6.0, "the WDEF side effect lowers weapon defence")
	w.buffs.active.rage.remaining = DT * 0.5 # its cooldown (50 s) is still running, so it cannot recast
	w.step(DT, MoveInput.new())
	assert_false(w.buffs.has("rage"), "the buff ran out")
	assert_eq(w.weapon_attack(), watk_before, "expiry removes the W.Att")
	assert_eq(w.hit_defense().pdd, pdd_before, "and the defence penalty")


## Final Attack: Sword shape: prop 40% / damage 200% at rank 1, prop 100% / damage 250% at rank 2; sword only.
func _final_data(data: Dictionary) -> void:
	data.balance.crit = {"chance": 0.0, "per_acc": 0.0, "mult": 1.5}
	data.skills.skills["final_blade"] = {"skill_id": 9991005, "book": "999", "kind": "passive", "slot": "passive",
		"name": "Final Attack", "damage": "physical", "ranks": [1, 2], "action": "swingO1", "action_time": 0.0,
		"weapon_families": ["sword"], "final_attack": {"chance_field": "prop"}, "effect": "",
		"icon": "Skill.wz/999.img/skill/9991005/icon"}


func _final_world(p_seed := 161) -> RunWorld:
	var w := _world(p_seed, _final_data)
	w.setup.skill_imgs["999"].skill["9991005"] = {"level": {"1": {"prop": 40, "damage": 200},
		"2": {"prop": 100, "damage": 250}}}
	RF.place_player(w, 200)
	return w


## A mob that cannot die or move, and a physical trigger line like a basic attack or skill hit would report.
func _dummy(w: RunWorld) -> int:
	var mob := RF.put_mob(w, 100100, 260, 190, 1000000)
	w.mob_kinds[w.swarm.kind[mob]].move_speed = 0
	w.god = true
	return mob


func _trigger(w: RunWorld, mob: int, dtype := "physical") -> void:
	w.hit_mob(mob, {"skill": "fixture", "damage_type": dtype, "magic": dtype == "magic", "damage_min": 100.0,
		"damage_max": 100.0, "damage_pct": 1.0, "crit": 0.0, "crit_mult": 1.5}, -1)


func _count(w: RunWorld, skill: String) -> int:
	var n := 0
	for e: Dictionary in w.drain_events():
		if e.type == "mob_hit" and String(e.skill) == skill:
			n += 1
	return n


func test_final_attack_procs_at_its_prop_rate() -> void:
	var w := _final_world()
	var mob := _dummy(w)
	w.learn_skill("final_blade")
	var procs := 0
	for hit in 1000:
		_trigger(w, mob)
		w.step(DT, MoveInput.new())
		procs += _count(w, "final_blade")
	assert_between(procs, 340, 460, "prop 40% over 1000 hits on a fixed seed (expected 400, 5 sigma = 77)")
	w.loadout.set_rank("final_blade", 2)
	var sure := 0
	for hit in 50:
		_trigger(w, mob)
		w.step(DT, MoveInput.new())
		sure += _count(w, "final_blade")
	assert_eq(sure, 50, "prop 100% follows every hit")


func test_final_attack_ignores_magic_and_fixed_hits_and_never_chains_on_itself() -> void:
	var w := _final_world()
	var mob := _dummy(w)
	w.learn_skill("final_blade")
	w.loadout.set_rank("final_blade", 2)
	for dtype: String in ["magic", "fixed"]:
		for hit in 20:
			_trigger(w, mob, dtype)
			w.step(DT, MoveInput.new())
		assert_eq(_count(w, "final_blade"), 0, dtype + " lines get no Final Attack")
	_trigger(w, mob)
	for tick in 5:
		w.step(DT, MoveInput.new())
	assert_eq(_count(w, "final_blade"), 1, "one trigger, one follow-up, no chain (prop is 100%)")


func test_final_attack_hits_for_its_own_percent_through_live_defence() -> void:
	var w := _final_world()
	var mob := _dummy(w)
	w.learn_skill("final_blade")
	w.loadout.set_rank("final_blade", 2)
	var st := w.loadout.stats("final_blade")
	assert_eq(st.damage_pct, 2.5)
	var mk: MobKind = w.mob_kinds[w.swarm.kind[mob]]
	var defended := CombatMath.physical_defense(Vector2(st.damage_min, st.damage_max), mk.pdd)
	_trigger(w, mob)
	w.step(DT, MoveInput.new())
	var follow: Array = w.drain_events().filter(func(e: Dictionary) -> bool:
		return e.type == "mob_hit" and String(e.skill) == "final_blade")
	assert_eq(follow.size(), 1)
	if follow.size() == 1:
		assert_between(follow[0].damage, floori(defended.x * 2.5), ceili(defended.y * 2.5), "bounds x 250%")
		assert_eq(follow[0].mob, mob, "on the same target")


func test_final_attack_stream_twelve_leaves_every_other_stream_untouched() -> void:
	var with_fa := _final_world()
	var control := _final_world() # same seed, Final Attack never learned
	with_fa.learn_skill("final_blade")
	with_fa.loadout.set_rank("final_blade", 2)
	var a := _dummy(with_fa)
	var b := _dummy(control)
	var twelve := with_fa.final_rng.state
	for tick in 30:
		_trigger(with_fa, a)
		_trigger(control, b)
		with_fa.step(DT, MoveInput.new())
		control.step(DT, MoveInput.new())
	assert_ne(with_fa.final_rng.state, twelve, "the follow-ups rolled on stream 12")
	for stream: String in ["rng", "spawn_rng", "card_rng", "drop_rng", "potion_rng", "reward_rng", "meso_rng", "equip_rng", "scroll_rng"]:
		assert_eq(with_fa.get(stream).state, control.get(stream).state, stream + " is unaffected by Final Attack")


func test_final_attack_is_skipped_when_the_trigger_killed_its_target() -> void:
	var w := _final_world()
	var mob := RF.put_mob(w, 100100, 260, 190, 0.0001)
	w.mob_kinds[w.swarm.kind[mob]].move_speed = 0
	w.god = true
	w.learn_skill("final_blade")
	w.loadout.set_rank("final_blade", 2)
	_trigger(w, mob)
	for tick in 3:
		w.step(DT, MoveInput.new())
	assert_eq(w.swarm.active[mob], 0, "the trigger killed it")
	assert_eq(_count(w, "final_blade"), 0, "a dead target takes no follow-up (tier C)")


func test_final_attack_follows_projectile_hits_and_announces_itself() -> void:
	var w := _final_world()
	var mob := _dummy(w)
	w.learn_skill("final_blade")
	w.loadout.set_rank("final_blade", 2)
	w.drain_events()
	w.projectiles.spawn({"x": 200.0, "y": w.mob_center(mob).y, "vx": 600.0, "range": 400.0, "damage_type": "physical",
		"dmg_min": 100.0, "dmg_max": 100.0, "damage_pct": 1.0, "crit": 0.0, "skill": "fixture"})
	var events := []
	for tick in 30:
		w.step(DT, MoveInput.new())
		events.append_array(w.drain_events())
	var follow := events.filter(func(e: Dictionary) -> bool: return e.type == "mob_hit" and e.skill == "final_blade")
	assert_eq(follow.size(), 1, "an airborne physical shot triggers it too")
	var announced := events.filter(func(e: Dictionary) -> bool: return e.type == "final_attack")
	assert_eq(announced.size(), 1)
	if announced.size() == 1:
		assert_eq(announced[0].skill, "final_blade")
		assert_eq(announced[0].mob, mob)
		assert_eq(announced[0].action, "swingO1")


func test_the_final_attack_follow_up_plays_its_own_stance() -> void:
	var w := _final_world()
	w.book.def("final_blade")["action_time"] = 0.4
	var mob := _dummy(w)
	w.learn_skill("final_blade")
	w.loadout.set_rank("final_blade", 2) # prop 100 %
	assert_eq(w.upkeep.cast_action, "", "no stance yet")
	_trigger(w, mob)
	w.step(DT, MoveInput.new())
	assert_eq(w.upkeep.cast_action, "swingO1", "the follow-up starts the skill's action")
	assert_between(w.upkeep.cast_left, 0.3, 0.4, "for the skill's action time")
	w.drain_events()
	var data_without := _final_world()
	data_without.book.def("final_blade")["action"] = ""
	var other := _dummy(data_without)
	data_without.learn_skill("final_blade")
	data_without.loadout.set_rank("final_blade", 2)
	_trigger(data_without, other)
	data_without.step(DT, MoveInput.new())
	assert_eq(data_without.upkeep.cast_action, "", "a skill without an action starts none")
