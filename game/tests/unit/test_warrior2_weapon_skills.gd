extends TestCase
## Warrior second job weapon skills (spec #165 ticket #181, docs/GAME_DESIGN.md 7.9): the six Masteries, six Final
## Attacks and six Boosters of Fighter 110, Page 120 and Spearman 130 with their real survivor data, their cards, the
## Spread card, and the advancement draw. Level tables are the exact v83 formulas (RF skill fixtures; the one cache test
## reads the real Skill.wz and SKIPs without the cache). Seeded, fixed ticks.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const SWORD := 1302008
const AXE := 1312005
const BLUNT := 1322014
const SPEAR := 1432002
const POLEARM := 1442001
const WEAPONS := [SWORD, AXE, BLUNT, SPEAR, POLEARM]
const MOB := 1110100

## [branch job, family, mastery key, final attack key, booster key, weapon] of all twelve weapon rows.
const ROWS := [
	[110, "sword", "sword_mastery_fighter", "final_attack_sword_fighter", "sword_booster_fighter", SWORD],
	[110, "axe", "axe_mastery", "final_attack_axe", "axe_booster", AXE],
	[120, "sword", "sword_mastery_page", "final_attack_sword_page", "sword_booster_page", SWORD],
	[120, "blunt", "bw_mastery", "final_attack_bw", "bw_booster", BLUNT],
	[130, "spear", "spear_mastery", "final_attack_spear", "spear_booster", SPEAR],
	[130, "polearm", "polearm_mastery", "final_attack_polearm", "polearm_booster", POLEARM],
]


## Synthetic Character.wz nodes of the five weapons: no requirements, the swing art of an existing afterimage fixture.
func _info() -> Dictionary:
	var out := {}
	for id: int in WEAPONS:
		var after := "spear" if id == SPEAR else "mace" if id == BLUNT else "swordOL"
		out[id] = {"incPAD": 40.0, "attackSpeed": 6.0, "afterImage": after, "sfx": after}
	return out


## A job 110 / 120 / 130 Warrior wearing `weapon`, the other four weapons in the Equip tab, nothing learned, standing at
## x 400 with 1000 MP. Mobs never move, so the tests are about hits, not contact.
func _world(job := 110, weapon := SWORD, p_seed := 181) -> RunWorld:
	var data := RF.quiet_data()
	data.balance.player.mp = 1000
	data.balance.player.skills = []
	data.balance.magnet_radius = 0
	var setup := RF.with_basic_attack(RF.setup("quiet", p_seed, data))
	setup.equipment_info.merge(_info(), true)
	var w0 := RunWorld.new(setup)
	w0.change_job(job)
	var character := w0.character_snapshot()
	character.equipment.worn.weapon = Equipment.create(weapon, setup.equipment_info[weapon])
	character.equipment.inventory = []
	for id: int in WEAPONS:
		if id != weapon:
			character.equipment.inventory.append(Equipment.create(id, setup.equipment_info[id]))
	setup.character = character
	var w := RunWorld.new(setup)
	for mk: MobKind in w.mob_kinds:
		mk.hitbox = Rect2(-5, -10, 10, 10)
		mk.move_speed = 0.0
	RF.place_player(w, 400)
	w.loadout.order.clear()
	w.god = true
	w.drain_events()
	return w


func _wear(w: RunWorld, id: int) -> void:
	for i in w.equipment.inventory.size():
		if int(w.equipment.inventory[i].id) == id:
			assert_eq(w.equip_item(i), "", "wearing %d" % id)
			return
	assert_true(false, "item %d is in the inventory" % id)


func _learn(w: RunWorld, key: String, rank := 1) -> void:
	assert_true(w.learn_skill(key), "%s is learned" % key)
	w.loadout.set_rank(key, rank)
	w.refresh_player_stats()


## A mob that cannot die, `dx` px in front of the player.
func _dummy(w: RunWorld, dx := 60.0, dy := 0.0) -> int:
	var m := RF.put_mob(w, MOB, w.player.pos.x + dx, 190.0 + dy, 1000000.0)
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	return m


## A physical trigger line such as a basic attack or skill hit reports.
func _trigger(w: RunWorld, mob: int) -> void:
	w.hit_mob(mob, {"skill": "fixture", "damage_type": "physical", "magic": false, "damage_min": 100.0,
		"damage_max": 100.0, "damage_pct": 1.0, "player_level": 1, "crit": 0.0, "crit_mult": 1.5}, -1)


## mob_hit events of skill `key` among the world's pending events (drains them).
func _hits(w: RunWorld, key: String) -> Array:
	return w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "mob_hit" and String(e.skill) == key)


# --- Masteries -----------------------------------------------------------------------------------------------------

func test_every_mastery_raises_min_damage_and_acc_only_while_its_family_is_held() -> void:
	for row: Array in ROWS:
		var key := String(row[2])
		var w := _world(int(row[0]), int(row[5]))
		var base_acc := w.loadout.acc
		var untrained := w.loadout.mastery
		assert_eq(untrained, 0.10, "%s: untrained mastery is 10%%" % key)
		_learn(w, key, 1)
		# Skill.wz: levels 1 and 2 are both mastery step 1 (15%), accuracy x = level.
		assert_near(w.loadout.mastery, 0.15, 1e-6, "%s level 1: 15%%" % key)
		assert_near(w.loadout.acc, base_acc + 1.0, 1e-6, "%s level 1: +1 ACC" % key)
		w.loadout.set_rank(key, 2)
		w.refresh_player_stats()
		assert_near(w.loadout.mastery, 0.15, 1e-6, "%s level 2 is still 15%%" % key)
		assert_near(w.loadout.acc, base_acc + 2.0, 1e-6, "%s level 2: +2 ACC" % key)
		w.loadout.set_rank(key, 20)
		w.refresh_player_stats()
		assert_near(w.loadout.mastery, 0.60, 1e-6, "%s level 20: 60%%" % key)
		assert_near(w.loadout.acc, base_acc + 20.0, 1e-6, "%s level 20: +20 ACC" % key)
		var held := CombatMath.physical_damage_range(100, 50, 20, 100, int(row[5]), "swing", 110, w.loadout.mastery)
		var plain := CombatMath.physical_damage_range(100, 50, 20, 100, int(row[5]), "swing", 110, untrained)
		assert_true(held.x > plain.x, "%s: minimum damage rises" % key)
		assert_eq(held.y, plain.y, "%s: the maximum does not" % key)
		for other: int in WEAPONS:
			if WeaponInfo.family(other) == String(row[1]):
				continue
			_wear(w, other)
			assert_eq(w.loadout.mastery, 0.10, "%s: a %s gets no mastery" % [key, WeaponInfo.family(other)])
			assert_near(w.loadout.acc, base_acc, 1e-6, "%s: and no ACC" % key)
			_wear(w, int(row[5]))
			assert_near(w.loadout.mastery, 0.60, 1e-6, "%s: back in hand" % key)


# --- Boosters ------------------------------------------------------------------------------------------------------

func test_every_booster_pays_hp_and_mp_speeds_the_held_family_and_recasts_on_expiry() -> void:
	for row: Array in ROWS:
		var key := String(row[4])
		var w := _world(int(row[0]), int(row[5]))
		assert_true(w.learn_skill("power_strike"), "an attack skill whose timing the Booster shortens")
		var before := w.loadout.stats("power_strike")
		var hp := int(w.player_state.hp)
		var mp := int(w.player_state.mp)
		assert_true(w.learn_skill(key))
		w.step(DT, MoveInput.new())
		assert_true(w.buffs.has(key), "%s was cast" % key)
		# Skill.wz level 1: HP -29, MP -29, x -2 (v83 speed steps, negative = faster).
		assert_eq(int(w.player_state.hp), hp - 29, "%s pays its canonical HP" % key)
		assert_eq(int(w.player_state.mp), mp - 29, "%s pays its canonical MP" % key)
		assert_eq(w.loadout.speed_steps, 2, "%s: two speed steps" % key)
		var after := w.loadout.stats("power_strike")
		assert_true(float(after.action_time) < float(before.action_time), "%s shortens the attack stance" % key)
		assert_true(float(after.cooldown) < float(before.cooldown), "%s shortens the cooldown" % key)
		assert_near(float(w.buffs.active[key].remaining), 10.0, 0.1, "level 1 lasts 10 s")
		# Another family's weapon gets nothing from it.
		for other: int in WEAPONS:
			if WeaponInfo.family(other) != String(row[1]):
				_wear(w, other)
				assert_eq(w.loadout.speed_steps, 0, "%s: a %s is not sped up" % [key, WeaponInfo.family(other)])
				break
		_wear(w, int(row[5]))
		assert_eq(w.loadout.speed_steps, 2, "%s: back in hand" % key)
		# Expiry recasts it (and pays again).
		w.buffs.active[key].remaining = DT * 0.5
		w.runner.cooldowns[key] = 0.0
		var hp_before := int(w.player_state.hp)
		w.step(DT, MoveInput.new())
		assert_true(w.buffs.has(key), "%s recasts on expiry" % key)
		assert_eq(int(w.player_state.hp), hp_before - 29, "and pays its HP again")


func test_a_booster_is_not_cast_when_its_hp_cost_would_leave_no_hp() -> void:
	var w := _world()
	w.learn_skill("sword_booster_fighter")
	w._hp = 20.0 # the level 1 cost is 29 HP
	w._write_player_state(0.0)
	w.step(DT, MoveInput.new())
	assert_false(w.buffs.has("sword_booster_fighter"), "no cast that would kill the player")


func test_the_booster_levels_follow_the_canonical_table() -> void:
	var w := _world()
	w.learn_skill("sword_booster_fighter")
	w.loadout.set_rank("sword_booster_fighter", 20)
	var st := w.loadout.stats("sword_booster_fighter")
	assert_eq(st.hp_cost, 10, "level 20: HP -10")
	assert_eq(st.mp_cost, 10, "and MP -10")
	assert_eq(float(st.duration), 200.0, "for 200 s")


# --- Final Attacks --------------------------------------------------------------------------------------------------

func test_every_final_attack_follows_only_a_hit_with_its_family() -> void:
	for row: Array in ROWS:
		var key := String(row[3])
		var w := _world(int(row[0]), int(row[5]))
		_learn(w, key, 30) # prop 60%, damage 250%
		var mob := _dummy(w)
		var procs := 0
		for hit in 500:
			_trigger(w, mob)
			w.step(DT, MoveInput.new())
			procs += _hits(w, key).size()
		assert_between(procs, 255, 345, "%s: prop 60%% over 500 hits (expected 300)" % key)
		var other_family := ""
		for other: int in WEAPONS:
			if WeaponInfo.family(other) != String(row[1]):
				_wear(w, other)
				other_family = WeaponInfo.family(other)
				break
		for hit in 100:
			_trigger(w, mob)
			w.step(DT, MoveInput.new())
			procs += _hits(w, key).size()
		assert_between(procs, 255, 345, "%s: no follow-up with a %s" % [key, other_family])


func test_a_fighter_holding_an_axe_follows_up_only_with_the_axe_final_attack() -> void:
	var w := _world(110, AXE)
	_learn(w, "final_attack_sword_fighter", 30)
	_learn(w, "final_attack_axe", 30)
	var mob := _dummy(w)
	var sword_procs := 0
	var axe_procs := 0
	for hit in 300:
		_trigger(w, mob)
		w.step(DT, MoveInput.new())
		for e: Dictionary in w.drain_events():
			if e.type == "mob_hit":
				sword_procs += 1 if String(e.skill) == "final_attack_sword_fighter" else 0
				axe_procs += 1 if String(e.skill) == "final_attack_axe" else 0
	assert_eq(sword_procs, 0, "the sword Final Attack never fires with an axe")
	assert_between(axe_procs, 150, 210, "the axe one does (expected 180)")


func test_a_final_attack_hits_for_its_canonical_damage_percent_with_the_held_weapons_stance() -> void:
	var w := _world(110, SWORD)
	_learn(w, "final_attack_sword_fighter", 30)
	w.loadout.set_rank("final_attack_sword_fighter", 1)
	assert_near(w.loadout.stats("final_attack_sword_fighter").damage_pct, 1.05, 1e-9, "level 1: damage 105%")
	w.loadout.set_rank("final_attack_sword_fighter", 30)
	assert_near(w.loadout.stats("final_attack_sword_fighter").damage_pct, 2.5, 1e-9, "level 30: damage 250%")
	var mob := _dummy(w)
	var announced: Array = []
	for hit in 40:
		_trigger(w, mob)
		w.step(DT, MoveInput.new())
		announced.append_array(w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "final_attack"))
		if not announced.is_empty():
			break
	assert_false(announced.is_empty(), "a follow-up was announced")
	if not announced.is_empty():
		assert_eq(announced[0].action, WeaponInfo.skill_action(SWORD), "the held weapon's attack stance")


# --- Spread -----------------------------------------------------------------------------------------------------------

## A Fighter with a sword, Final Attack: Sword at level 30 and `steps` Spread steps, with a primary dummy 60 px ahead and
## one dummy at each offset of `around` px from it (x only, same floor). Returns {w, primary, others: {offset: slot}}.
func _spread_world(steps: int, around: Array, p_seed := 181) -> Dictionary:
	var w := _world(110, SWORD, p_seed)
	_learn(w, "final_attack_sword_fighter", 30)
	for step in steps:
		assert_eq(w.upgrades.apply("final_attack_sword_fighter_spread", w), step + 1, "Spread step %d" % (step + 1))
	assert_eq(w.loadout.stats("final_attack_sword_fighter").count, 1 + steps, "the card adds one target per step")
	var primary := _dummy(w, 60.0)
	var others := {}
	for offset: float in around:
		others[offset] = _dummy(w, 60.0 + offset)
	return {"w": w, "primary": primary, "others": others}


## Triggers hits on `primary` one tick at a time until a Final Attack follow-up is announced; returns the Final Attack
## mob_hit events of that tick's follow-up (every struck mob).
func _follow_up(w: RunWorld, primary: int) -> Array:
	for tick in 200:
		_trigger(w, primary)
		w.step(DT, MoveInput.new())
		var events := w.drain_events()
		if events.any(func(e: Dictionary) -> bool: return e.type == "final_attack"):
			return events.filter(func(e: Dictionary) -> bool:
				return e.type == "mob_hit" and String(e.skill) == "final_attack_sword_fighter")
	return []


func _struck(hits: Array) -> Array:
	return hits.map(func(e: Dictionary) -> int: return int(e.mob))


func test_without_spread_the_follow_up_strikes_only_the_target() -> void:
	var d := _spread_world(0, [20.0, -35.0])
	var hits := _follow_up(d.w, d.primary)
	assert_eq(_struck(hits), [d.primary], "one monster")


func test_spread_strikes_up_to_n_more_monsters_within_reach_of_the_target_nearest_first() -> void:
	var probe := _world()
	var reach := probe.basic.reach(probe)
	assert_true(reach > 40.0, "the fixture sword has a swing reach to measure from")
	var far := reach + 30.0 # beyond reach of the target
	var edge := reach - 6.0 # still inside it
	# Spread 2: the two nearest of four candidates (offsets from the target: 20, -35, edge, far).
	var d := _spread_world(2, [far, edge, -35.0, 20.0])
	var struck := _struck(_follow_up(d.w, d.primary))
	assert_eq(struck.size(), 3, "the target and two more")
	assert_eq(struck[0], d.primary, "the target first")
	assert_has(struck, d.others[20.0], "the nearest candidate (20 px)")
	assert_has(struck, d.others[-35.0], "the second nearest, on the other side (35 px)")
	assert_false(d.others[edge] in struck, "N stops at two")
	assert_false(d.others[far] in struck, "and never beyond reach")
	# Spread 3 reaches the candidate at the edge of reach but still not the one beyond it.
	var e := _spread_world(3, [far, edge, -35.0, 20.0])
	var wide := _struck(_follow_up(e.w, e.primary))
	assert_eq(wide.size(), 4, "the target and three more")
	assert_has(wide, e.others[edge], "inside reach")
	assert_false(e.others[far] in wide, "outside reach, whatever N is")


func test_spread_counts_reach_from_the_struck_target_not_from_the_player() -> void:
	var probe := _world()
	var reach := probe.basic.reach(probe)
	# The candidate is 60 + (reach - 6) px from the player: beyond the player's own reach, within the target's.
	var d := _spread_world(1, [reach - 6.0])
	var hits := _struck(_follow_up(d.w, d.primary))
	assert_has(hits, d.others[reach - 6.0], "a monster beside the target is struck even if the player cannot reach it")


func test_spread_is_deterministic_and_the_follow_up_does_not_chain() -> void:
	var first := _spread_world(3, [20.0, -35.0, 50.0])
	var second := _spread_world(3, [20.0, -35.0, 50.0])
	var a := _follow_up(first.w, first.primary)
	var b := _follow_up(second.w, second.primary)
	assert_eq(_struck(a), _struck(b), "same seed, same targets in the same order")
	assert_eq(a.map(func(e: Dictionary) -> int: return int(e.damage)), b.map(func(e: Dictionary) -> int: return int(e.damage)))
	var announced := 0
	var w: RunWorld = first.w
	for tick in 5:
		w.step(DT, MoveInput.new())
		announced += w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "final_attack").size()
	assert_eq(announced, 0, "the extra hits did not trigger another Final Attack")


func test_spread_with_one_candidate_strikes_it_once_and_the_target_once() -> void:
	var d := _spread_world(3, [20.0])
	var struck := _struck(_follow_up(d.w, d.primary))
	assert_eq(struck.size(), 2, "the target and the only candidate, each once")
	assert_eq(struck.count(d.primary), 1)
