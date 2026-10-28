extends TestCase
## Warrior second job weapon skills (spec #165 ticket #181, docs/GAME_DESIGN.md 7.9): the six Masteries, six Final
## Attacks and six Boosters of Fighter 110, Page 120 and Spearman 130 with their real survivor data, their cards, the
## Spread card. Weapons gate none of them (#284: a Mastery, Booster or Final Attack works whatever is held), and the job is
## set directly (no advancement draw). Level tables are the exact v83 formulas (RF skill fixtures; the one cache test
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
	data.balance.player.hp = 600 # the base 50 plus the +225 / +325 HP the removed Warrior advancements granted (#284)
	data.jobs_survivor.jobs["212"]["start_skills"] = []
	data.balance.magnet_radius = 0
	var setup := RF.with_basic_attack(RF.setup("quiet", p_seed, data))
	setup.equipment_info.merge(_info(), true)
	var w0 := RunWorld.new(setup)
	RF.as_job(w0, job)
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

func test_every_mastery_raises_min_damage_and_acc_whatever_weapon_is_held() -> void:
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
			assert_near(w.loadout.mastery, 0.60, 1e-6, "%s: a %s gets the mastery too (#284)" % [key, WeaponInfo.family(other)])
			assert_near(w.loadout.acc, base_acc + 20.0, 1e-6, "%s: and the ACC" % key)
			_wear(w, int(row[5]))
			assert_near(w.loadout.mastery, 0.60, 1e-6, "%s: back in hand" % key)


# --- Boosters ------------------------------------------------------------------------------------------------------

func test_every_booster_pays_hp_and_mp_speeds_any_weapon_and_recasts_on_expiry() -> void:
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
		# Another family's weapon is sped up too: weapons gate no skill (#284).
		for other: int in WEAPONS:
			if WeaponInfo.family(other) != String(row[1]):
				_wear(w, other)
				assert_eq(w.loadout.speed_steps, 2, "%s: a %s is sped up too" % [key, WeaponInfo.family(other)])
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

func test_every_final_attack_follows_a_hit_whatever_weapon_is_held() -> void:
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
		var other_procs := 0
		for hit in 100:
			_trigger(w, mob)
			w.step(DT, MoveInput.new())
			other_procs += _hits(w, key).size()
		assert_between(other_procs, 40, 80, "%s: follow-ups with a %s too (expected 60, #284)" % [key, other_family])


func test_a_fighter_holding_an_axe_follows_up_with_both_final_attacks() -> void:
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
	assert_between(sword_procs, 150, 210, "the sword Final Attack fires with an axe too (expected 180, #284)")
	assert_between(axe_procs, 150, 210, "and so does the axe one")


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
	var reach := probe.weapon_reach.reach(probe)
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
	var reach := probe.weapon_reach.reach(probe)
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


func test_spread_hits_a_boss_before_nearer_monsters() -> void:
	var d := _spread_world(1, [20.0, 40.0])
	var w: RunWorld = d.w
	w.mob_boss[d.others[40.0]] = 0 # a scheduled boss (RunWorld.targets_before: bosses first)
	var struck := _struck(_follow_up(w, d.primary))
	assert_has(struck, d.others[40.0], "the boss takes the one extra hit")
	assert_false(d.others[20.0] in struck, "ahead of the nearer monster")


func test_spread_with_one_candidate_strikes_it_once_and_the_target_once() -> void:
	var d := _spread_world(3, [20.0])
	var struck := _struck(_follow_up(d.w, d.primary))
	assert_eq(struck.size(), 2, "the target and the only candidate, each once")
	assert_eq(struck.count(d.primary), 1)


# --- Cards ---------------------------------------------------------------------------------------------------------

## The eligible cards of `skills`.
func _cards_of(w: RunWorld, skills: Array) -> Array:
	return w.upgrades.eligible(w).filter(func(id: String) -> bool: return String(w.upgrades.card(id).skill) in skills)


func test_a_fighter_is_offered_its_cards_whatever_weapon_is_held() -> void:
	var w := _world(110, SWORD)
	for key: String in ["axe_mastery", "final_attack_axe", "axe_booster", "sword_mastery_fighter",
			"final_attack_sword_fighter", "sword_booster_fighter"]:
		_learn(w, key, 1)
	for id in ["axe_mastery_rank", "final_attack_axe_rank", "final_attack_axe_spread", "axe_booster_rank",
			"sword_mastery_fighter_rank", "final_attack_sword_fighter_rank", "final_attack_sword_fighter_spread",
			"sword_booster_fighter_rank"]:
		assert_has(_cards_of(w, [w.upgrades.card(id).skill]), id, "%s is on offer with the sword (#284)" % id)


func test_learn_cards_are_offered_for_the_jobs_own_line_only() -> void:
	var w := _world(110, SWORD)
	var ids := w.upgrades.eligible(w)
	for id in ["sword_mastery_fighter_new", "final_attack_sword_fighter_new", "sword_booster_fighter_new",
			"axe_mastery_new", "final_attack_axe_new", "axe_booster_new"]:
		assert_has(ids, id)
	for id in ["sword_mastery_page_new", "bw_mastery_new", "spear_mastery_new"]:
		assert_false(id in ids, "%s is another branch's card" % id)


func test_power_flags_and_requirements_of_the_new_cards() -> void:
	var w := _world()
	for row: Array in ROWS:
		var branch := int(row[0])
		for key: String in [row[2], row[3], row[4]]:
			var power := key != String(row[2])
			for suffix in ["_new", "_rank"]:
				var c: Dictionary = w.upgrades.card(key + suffix)
				assert_false(c.is_empty(), key + suffix)
				assert_eq(UpgradePool.is_power(c), power, "%s: power only for Final Attack and Booster" % c.id)
				assert_eq(c.requires.jobs, [float(branch)], "%s requires its own branch" % c.id)
		var spread: Dictionary = w.upgrades.card(String(row[3]) + "_spread")
		assert_true(UpgradePool.is_power(spread), "the Spread card is a power card")
		assert_eq(spread.kind, "skill_mod")
		assert_eq(spread.effects, [{"stat": "count", "op": "add", "value": 1.0}], "+1 target per step")


func test_the_bot_scores_the_weapon_skills_and_spread_as_attack_cards() -> void:
	for row: Array in ROWS:
		var w := _world(int(row[0]), int(row[5]))
		_learn(w, String(row[3]), 1)
		for i in [2, 3, 4]:
			var key := String(row[i])
			assert_eq(BotInput.card_score(w, {"id": key + "_new"}), BotInput.SCORE_NEW_ATTACK, key + " learn")
			assert_eq(BotInput.card_score(w, {"id": key + "_rank"}), BotInput.SCORE_RANK_ATTACK + BotInput.SCORE_JOB_BONUS,
				key + " rank")
		assert_eq(BotInput.card_score(w, {"id": String(row[3]) + "_spread"}),
			float(BotInput.SCORE_MOD.count) + BotInput.SCORE_JOB_BONUS, "Spread scores as a targets card")
		var picks := BotInput.pick_card_for(w, [{"id": "improved_hp_recovery_new"}, {"id": String(row[2]) + "_new"}])
		assert_eq(picks, String(row[2]) + "_new", "a Mastery beats a plain passive")


func test_rank_cards_preview_what_each_skill_changes_in_the_right_words() -> void:
	var w := _world(110, SWORD)
	_learn(w, "sword_mastery_fighter", 2)
	_learn(w, "final_attack_sword_fighter", 1)
	var mastery := LevelUpWindow.change_lines(w.upgrades.choice_card("sword_mastery_fighter_rank", w))
	assert_eq(Array(mastery), ["Mastery: 15% → 20%", "Accuracy: 2 → 3"], "level 2 -> 3")
	var final := LevelUpWindow.change_lines(w.upgrades.choice_card("final_attack_sword_fighter_rank", w))
	assert_eq(Array(final), ["Damage: 105% → 110%", "Success rate: 2% → 4%"], "level 1 -> 2")


func test_every_final_attack_has_a_hit_more_mobs_card() -> void:
	var data := DataRepo.load_all()
	for row: Array in ROWS:
		var found := false
		for c: Dictionary in data.upgrades.cards:
			if String(c.skill) == String(row[3]) and String(c.kind) == "skill_mod":
				for effect: Dictionary in c.effects:
					found = found or (effect.stat in ["count", "pierce"] and float(effect.value) > 0.0)
		assert_true(found, "%s has a card that hits more monsters" % row[3])


func test_the_weapon_skills_are_bound_to_their_families_and_levels() -> void:
	var data := DataRepo.load_all()
	var book := SkillBook.from_data(data.skills, RF.skill_imgs())
	for row: Array in ROWS:
		for i in [2, 3, 4]:
			var key := String(row[i])
			assert_eq(Array(book.weapon_families(key)), [String(row[1])], "%s works with the %s only" % [key, row[1]])
			assert_eq(book.max_rank(key), 30 if i == 3 else 20, "%s: canonical level count" % key)
			assert_eq(int(book.def(key).job), int(row[0]))
		assert_eq(book.def(row[2]).kind, "passive")
		assert_eq(book.def(row[3]).kind, "passive")
		assert_eq(book.def(row[4]).kind, "buff")
		assert_eq(book.def(row[3]).final_attack.chance_field, "prop")


# --- The real Skill.wz ----------------------------------------------------------------------------------------------

func test_the_real_skill_wz_supplies_every_number_art_and_sound() -> void:
	if not require_cache():
		return
	var data := DataRepo.load_all()
	var lib := AssetLibrary.new()
	lib.open()
	var imgs := {}
	for book in ["110", "120", "130"]:
		imgs[book] = lib.img("Skill.wz/%s.img" % book).root
	var book := SkillBook.from_data(data.skills, imgs)
	for row: Array in ROWS:
		var mastery := String(row[2])
		var final := String(row[3])
		var booster := String(row[4])
		assert_eq(book.max_rank(mastery), 20)
		assert_eq(int(book.canonical(mastery, 20, "mastery")), 10, "%s level 20: step 10 (60%%)" % mastery)
		assert_eq(int(book.canonical(mastery, 20, "x")), 20, "and +20 accuracy")
		assert_eq(int(book.canonical(mastery, 1, "mastery")), 1)
		assert_eq(book.max_rank(final), 30)
		assert_eq(int(book.canonical(final, 30, "prop")), 60, "%s level 30: 60%%" % final)
		assert_eq(int(book.canonical(final, 30, "damage")), 250)
		assert_eq(int(book.canonical(final, 1, "prop")), 2)
		assert_eq(int(book.canonical(final, 1, "damage")), 105)
		assert_eq(book.max_rank(booster), 20)
		assert_eq(int(book.canonical(booster, 1, "x")), -2, "%s: v83 speed steps are negative" % booster)
		assert_eq(int(book.canonical(booster, 1, "hpCon")), 29)
		assert_eq(int(book.canonical(booster, 20, "hpCon")), 10)
		assert_eq(int(book.canonical(booster, 20, "time")), 200)
		for key: String in [mastery, final, booster]:
			assert_true(lib.find(String(book.def(key).icon)) != null, "%s icon" % key)
		assert_true(lib.find_anim(String(book.def(final).hit)) != null, "%s hit art" % final)
		assert_true(lib.find_anim(String(book.def(booster).effect)) != null, "%s effect art" % booster)
		assert_true(lib.find(String(book.def(booster).sounds.use)) != null, "%s use sound" % booster)
	lib.free()
