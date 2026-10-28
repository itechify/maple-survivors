extends TestCase
## Crossbowman (#203): combat, cards and presentation contracts with fixed seeded ticks. The character is set up directly
## (#284: no advancement), with the HP/MP the removed Bowman and Crossbowman grants used to add in its base pools.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const SKILLS := ["crossbow_mastery", "final_attack_crossbow", "crossbow_booster", "power_knockback_crossbow", "iron_arrow"]


func _bowman(crossbow := false, fixed_damage := false) -> RunWorld:
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["212"]["start_skills"] = []
	data.balance.player.hp = 50 + 125 + 325
	data.balance.player.mp = 5 + 37 + 175
	if fixed_damage:
		data.skills.skills.iron_arrow.damage = "fixed"
	var setup := RF.with_basic_attack(RF.setup("quiet", 203, data))
	if fixed_damage:
		for row: Dictionary in setup.skill_imgs["320"].skill["3201005"].level.values():
			row.fixdamage = 100
	setup.equipment_info.merge({1452051: {"incPAD": 28, "attackSpeed": 6},
		1462001: {"incPAD": 29, "attackSpeed": 6},
		1462000: {"incPAD": 44, "attackSpeed": 6, "reqLevel": 28, "reqJob": 4, "reqSTR": 28, "reqDEX": 80}}, true)
	var w := RunWorld.new(setup)
	RF.as_job(w, 300, "bow")
	if crossbow:
		w.equipment.inventory.append(Equipment.create(1462001, setup.equipment_info[1462001]))
		assert_eq(w.equip_item(_inventory(w).find(1462001)), "")
	RF.place_player(w, 400)
	w.god = true
	return w


func _inventory(w: RunWorld) -> Array:
	return w.equipment.inventory.map(func(item: Dictionary) -> int: return int(item.id))


func _combat(key := "", rank_value := 1, fixed_damage := false) -> RunWorld:
	var w := _bowman(false, fixed_damage)
	w.progression.level = 40
	RF.as_job(w, 320)
	w.heal_fraction("mp", 1.0)
	for mk: MobKind in w.mob_kinds:
		mk.hitbox = Rect2(-2, -10, 4, 10)
		mk.move_speed = 0
	if key != "":
		assert_true(w.learn_skill(key))
		w.loadout.set_rank(key, rank_value)
		w.refresh_player_stats()
	w.drain_events()
	return w


func test_iron_arrow_casts_one_own_ball_and_hits_six_in_order_with_linear_falloff() -> void:
	var w := _combat("iron_arrow", 30, true)
	var st := w.loadout.stats("iron_arrow")
	assert_eq(st.mp_cost, 28)
	assert_near(_combat("iron_arrow", 30).loadout.stats("iron_arrow").damage_pct, 1.8)
	assert_eq(st.pierce, 5)
	assert_eq(st.count, 1)
	assert_near(st.pierce_falloff, 0.1)
	# Fix only the combat roll, retaining the real cast, projectile cap and per-contact fall-off.
	w.loadout.add_skill_mod("iron_arrow", "crit", "add", -1.0)
	var slots: Array[int] = []
	for i in 7:
		slots.append(RF.put_mob(w, 1110100, 470 + i * 30, 190, 10000))
		w.swarm.y[slots[-1]] = w.cast_origin().y + 5.0
	w.mob_kinds[w.swarm.kind[slots[0]]].pdd = 0
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	var mp: int = w.player_state.mp
	w.runner.step(DT, w)
	assert_eq(w.player_state.mp, mp - 28)
	assert_eq(w.projectiles.active_count(), 1)
	for p in w.projectiles.capacity():
		if w.projectiles.active[p] != 0:
			assert_eq(w.projectiles.visual[p], w.visual_index("Skill.wz/320.img/skill/3201005/ball"))
	for tick in 40:
		w.projectiles.step(DT, w.swarm, w.mob_grid, w.events)
	var hits := w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "mob_hit" and e.skill == "iron_arrow")
	assert_eq(hits.map(func(e: Dictionary) -> int: return int(e.mob)), slots.slice(0, 6))
	assert_eq(hits.map(func(e: Dictionary) -> int: return int(e.damage)), [100, 90, 80, 70, 60, 50])
	assert_eq(w.swarm.hp[slots[6]], w.swarm.max_hp[slots[6]])


func test_power_knockback_uses_canonical_range_count_cost_and_nonboss_chance() -> void:
	for rank_value in [1, 20]:
		var w := _combat("power_knockback_crossbow", rank_value)
		var st := w.loadout.stats("power_knockback_crossbow")
		assert_eq(st.cast_rule, "range_around")
		assert_eq(st.mob_count, 2 if rank_value == 1 else 6)
		assert_eq(st.range, 130.0 if rank_value == 1 else 150.0)
		assert_near(st.damage_pct, 1.05 if rank_value == 1 else 2.0)
		assert_eq(st.knockback_chance, 13.0 if rank_value == 1 else 70.0)
		assert_eq(st.mp_cost, 8 if rank_value == 1 else 15)
		w.runner.step(DT, w)
		assert_eq(w.runner.casts, 0, "no target, no cost")
		var slots: Array[int] = []
		for dx: float in [-90, -60, 60, 90, 110, 130, 250]:
			slots.append(RF.put_mob(w, 1110100, w.player.pos.x + dx, 190, 10000))
		w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
		var mp: int = w.player_state.mp
		w.runner.step(DT, w)
		assert_eq(w.player_state.mp, mp - int(st.mp_cost))
		var hits := w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "mob_hit" and e.skill == "power_knockback_crossbow")
		assert_eq(hits.size(), 2 if rank_value == 1 else 6)
		assert_eq(w.swarm.hp[slots[-1]], w.swarm.max_hp[slots[-1]], "out of reach")
	var chance := _combat("power_knockback_crossbow", 20)
	var normal := RF.put_mob(chance, 1110100, 470, 190, 10000)
	var boss := RF.put_mob(chance, 2220000, 500, 190, 10000)
	var moved := 0
	for trial in 100:
		chance.swarm.x[normal] = 470
		chance.hit_mob(normal, chance.loadout.stats("power_knockback_crossbow"), -1)
		if chance.swarm.x[normal] > 470:
			moved += 1
			assert_near(chance.swarm.x[normal], 590)
		chance.hit_mob(boss, chance.loadout.stats("power_knockback_crossbow"), -1)
		assert_near(chance.swarm.x[boss], 500)
	assert_between(moved, 50, 90, "seeded canonical 70% knock-back, never bosses")


func test_pierce_card_reaches_seventh_mob_at_forty_percent_and_shots_card_fires_two() -> void:
	var w := _combat("iron_arrow", 30, true)
	w.loadout.add_skill_mod("iron_arrow", "crit", "add", -1.0)
	assert_true(w.upgrades.apply("iron_arrow_pierce", w))
	for i in 7:
		var slot := RF.put_mob(w, 1110100, 470 + i * 30, 190, 10000)
		w.swarm.y[slot] = w.cast_origin().y + 5.0
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	w.runner.step(DT, w)
	for tick in 40:
		w.projectiles.step(DT, w.swarm, w.mob_grid, w.events)
	var hits := w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "mob_hit" and e.skill == "iron_arrow")
	assert_eq(hits.map(func(e: Dictionary) -> int: return int(e.damage)), [100, 90, 80, 70, 60, 50, 40])
	var shots := _combat("iron_arrow")
	assert_true(shots.upgrades.apply("iron_arrow_shots", shots))
	RF.put_mob(shots, 1110100, 500, 190, 10000)
	shots.mob_grid.rebuild(shots.swarm.x, shots.swarm.y, shots.swarm.active)
	shots.runner.step(DT, shots)
	assert_eq(shots.projectiles.active_count(), 2)


func test_attack_skills_wait_for_mp_and_targets_without_spending_or_casting() -> void:
	for key: String in ["power_knockback_crossbow", "iron_arrow"]:
		var w := _combat(key)
		var mp: int = w.player_state.mp
		w.runner.step(DT, w)
		assert_eq(w.runner.casts, 0)
		assert_eq(w.player_state.mp, mp)
		RF.put_mob(w, 1110100, 470, 190, 10000)
		w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
		assert_true(w.spend_mp(w.player_state.mp))
		w.runner.step(DT, w)
		assert_eq(w.runner.casts, 0)
		assert_eq(w.projectiles.active_count(), 0)
		w.heal_fraction("mp", 1.0)
		w.runner.step(DT, w)
		assert_eq(w.runner.casts, 1)


func test_mastery_and_booster_use_canonical_levels_costs_and_recast_without_stacking() -> void:
	for rank_value in [1, 20]:
		var w := _combat("crossbow_mastery", rank_value)
		assert_near(w.loadout.mastery, 0.15 if rank_value == 1 else 0.60)
		assert_eq(w.loadout.passive_total("acc"), 1.0 if rank_value == 1 else 20.0)
		assert_true(w.learn_skill("crossbow_booster"))
		w.loadout.set_rank("crossbow_booster", rank_value)
		w.refresh_player_stats()
		var st := w.loadout.stats("crossbow_booster")
		assert_eq(st.duration, 10.0 if rank_value == 1 else 200.0)
		assert_eq(st.buff_effects, {"attack_speed": 2.0})
		var cost := 29 if rank_value == 1 else 10
		assert_eq(st.hp_cost, cost)
		assert_eq(st.mp_cost, cost)
		assert_true(w.spend_hp(w.player_state.hp - cost))
		w.runner.step(DT, w)
		assert_false(w.buffs.has("crossbow_booster"), "HP cost must never kill")
		w.heal_fraction("hp", 1.0)
		w.spend_mp(w.player_state.mp)
		w.runner.step(DT, w)
		assert_false(w.buffs.has("crossbow_booster"), "needs MP too")
		w.heal_fraction("mp", 1.0)
		var hp: int = w.player_state.hp
		var mp: int = w.player_state.mp
		w.runner.step(DT, w)
		assert_eq(w.player_state.hp, hp - cost)
		assert_eq(w.player_state.mp, mp - cost)
		assert_eq(w.loadout.speed_steps, 2)
		w.runner.step(DT, w)
		assert_eq(w.player_state.mp, mp - cost, "no early recast")
		for tick in int(st.duration * 60) + 5:
			w.step(DT, MoveInput.new())
		assert_eq(w.runner.casts, 2, "recasts on expiry without a target")
		assert_eq(w.loadout.speed_steps, 2, "never stacks")


func test_final_attack_rolls_canonical_chance_on_physical_hits_and_draws_current_arrow() -> void:
	var w := _combat("final_attack_crossbow", 30)
	assert_near(w.loadout.stats("final_attack_crossbow").damage_pct, 2.5)
	assert_eq(w.book.canonical("final_attack_crossbow", 1, "prop"), 2.0)
	assert_eq(w.book.canonical("final_attack_crossbow", 30, "prop"), 60.0)
	var slot := RF.put_mob(w, 1110100, 510, 190, 10000)
	w.swarm.steady[slot] = 1
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	for trial in 100:
		w.hit_mob(slot, {"skill": "basic_attack", "damage_type": "physical", "damage_min": 1,
			"damage_max": 1, "crit": 0, "crit_mult": 1.5}, -1)
		w.step(DT, MoveInput.new())
	var events := w.drain_events()
	var hits := events.filter(func(e: Dictionary) -> bool: return e.type == "mob_hit" and e.skill == "final_attack_crossbow")
	assert_between(hits.size(), 40, 80)
	var shots := events.filter(func(e: Dictionary) -> bool: return e.type == "ammo_shot")
	assert_eq(shots.size(), hits.size())
	for shot: Dictionary in shots:
		assert_eq(shot.ball, Ammo.bullet_path(2061002))
		assert_eq(shot.to, w.mob_center(slot))


func test_final_attack_spread_card_strikes_one_more_mob_and_draws_both_arrows() -> void:
	var w := _combat("final_attack_crossbow", 30)
	assert_true(w.upgrades.apply("final_attack_crossbow_spread", w))
	var first := RF.put_mob(w, 1110100, 510, 190, 10000)
	var second := RF.put_mob(w, 1110100, 560, 190, 10000)
	w.swarm.steady[first] = 1
	w.swarm.steady[second] = 1
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	var hits: Array = []
	var shots: Array = []
	for trial in 30:
		w.hit_mob(first, {"skill": "basic_attack", "damage_type": "physical", "damage_min": 1,
			"damage_max": 1, "crit": 0, "crit_mult": 1.5}, -1)
		w.step(DT, MoveInput.new())
		var events := w.drain_events()
		hits = events.filter(func(e: Dictionary) -> bool: return e.type == "mob_hit" and e.skill == "final_attack_crossbow")
		shots = events.filter(func(e: Dictionary) -> bool: return e.type == "ammo_shot")
		if not hits.is_empty():
			break
	assert_eq(hits.map(func(e: Dictionary) -> int: return int(e.mob)), [first, second])
	assert_eq(shots.size(), 2)


func test_crossbowman_cards_casts_with_any_weapon_skill_window_and_no_soul_arrow() -> void:
	var w := _combat()
	for key: String in SKILLS:
		assert_has(w.upgrades.eligible(w), key + "_new")
		assert_true(w.upgrades.apply(key + "_new", w))
		assert_has(w.upgrades.eligible(w), key + "_rank")
	for key: String in ["power_knockback_crossbow_targets", "iron_arrow_pierce", "iron_arrow_shots"]:
		assert_has(w.upgrades.eligible(w), key)
		assert_true(w.upgrades.apply(key, w))
	assert_eq(w.loadout.stats("power_knockback_crossbow").mob_count, 3)
	assert_eq(w.loadout.stats("iron_arrow").pierce, 6)
	assert_eq(w.loadout.stats("iron_arrow").count, 2)
	# #284: weapons gate no skill, card or passive: with a bow the crossbow skills stay on offer and still cast.
	assert_eq(w.equip_item(_inventory(w).find(1452051)), "")
	var model := SkillWindowModel.new(w.book, w.upgrades, w.loadout, w.jobs, 320, SkillText.new(w.book, {}))
	var rows: Array = model.tabs[1].rows
	assert_eq(rows.size(), 5)
	for key: String in SKILLS:
		assert_has(w.upgrades.eligible(w), key + "_rank", "on offer with a bow")
	assert_eq(w.loadout.passive_total("acc"), 1.0, "Crossbow Mastery counts with a bow")
	RF.put_mob(w, 1110100, 470, 190, 10000)
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	w.drain_events()
	for tick in 120:
		w.step(DT, MoveInput.new())
	var casts := w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "cast" and e.skill in SKILLS)
	assert_true(casts.size() > 0, "a crossbow skill casts with a bow")
	for def: Dictionary in w.book.defs.values():
		assert_false(int(def.get("skill_id", 0)) in [3101004, 3201004])
	for card: Dictionary in w.upgrades.cards:
		assert_false("soul_arrow" in String(card.get("skill", "")))
	var first := _bowman(true)
	for key: String in SKILLS:
		assert_false(key + "_new" in first.upgrades.eligible(first), "exact branch only")


func test_arrow_tiers_emit_notices_at_thirty_forty_and_fifty() -> void:
	var w := _bowman(true)
	w.progression.level = 29
	RF.as_job(w, 320)
	assert_eq(w.ammo_id(), 2061000)
	w.drain_events()
	for pair: Array in [[30, 2061001], [40, 2061002], [50, 2061003]]:
		w.progression.level = int(pair[0])
		w.refresh_player_stats()
		assert_eq(w.ammo_id(), pair[1])
		var notices := w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "ammo_upgraded")
		assert_eq(notices.size(), 1)
		assert_eq(notices[0].item_id, pair[1])
		assert_eq(notices[0].level, pair[0])
		w.refresh_player_stats()
		assert_false(w.drain_events().any(func(e: Dictionary) -> bool: return e.type == "ammo_upgraded"))


func test_power_knockback_uses_shared_hunter_formula_with_fixed_mastery() -> void:
	var w := _combat("power_knockback_crossbow", 20)
	w.loadout.str_stat = 20
	w.loadout.dex_stat = 100
	w.loadout.watk = 30
	# Independently worked example: (100*3.4+20)*30/150 = 72;
	# minimum (100*3.4*.9*.1+20)*30/150 = 10.12, regardless of trained mastery.
	for mastery: float in [0.1, 0.6]:
		w.loadout.mastery = mastery
		var st := w.loadout.stats("power_knockback_crossbow")
		assert_near(st.damage_min, 10.12)
		assert_near(st.damage_max, 72)


func test_original_crossbowman_tables_icons_art_sounds_and_weapon_resolve() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	var img := lib.img("Skill.wz/320.img")
	assert_true(img != null)
	if img == null:
		lib.free()
		return
	var book := SkillBook.from_data(DataRepo.load_all().skills, {"320": img.root})
	var lo := Loadout.new(book)
	lo.weapon_family = "crossbow"
	for index in SKILLS.size():
		var key: String = SKILLS[index]
		var cap := 30 if index in [1, 4] else 20
		assert_eq(book.max_level(key), cap)
		assert_eq(book.max_rank(key), cap)
		for suffix: String in ["icon", "iconDisabled", "iconMouseOver"]:
			assert_true(lib.frame(book.wz_path(key) + "/" + suffix) != null)
		for field: String in ["ball", "hit", "effect"]:
			var path := book.visual(key, field, 1, 40)
			if path != "":
				assert_false(lib.anim(path).is_empty(), path)
		for sound: String in book.def(key).sounds.values():
			if sound != "":
				assert_true(lib.sound(sound) != null)
	for rank_value in [1, 30]:
		var iron := lo.stats("iron_arrow", rank_value)
		assert_eq(iron.mp_cost, 23 if rank_value == 1 else 28)
		assert_near(iron.damage_pct, 1.22 if rank_value == 1 else 1.80)
		assert_eq(iron.pierce, 5)
		assert_eq(book.canonical("iron_arrow", rank_value, "mobCount"), 6.0)
		assert_eq(book.canonical("final_attack_crossbow", rank_value, "prop"), 2.0 if rank_value == 1 else 60.0)
	for rank_value in [1, 20]:
		var pkb := lo.stats("power_knockback_crossbow", rank_value)
		assert_eq(pkb.mp_cost, 8 if rank_value == 1 else 15)
		assert_eq(pkb.mob_count, 2 if rank_value == 1 else 6)
		assert_eq(pkb.knockback_chance, 13.0 if rank_value == 1 else 70.0)
		assert_eq(pkb.range, 130.0 if rank_value == 1 else 150.0)
		var booster := lo.stats("crossbow_booster", rank_value)
		assert_eq(booster.hp_cost, 29 if rank_value == 1 else 10)
		assert_eq(booster.mp_cost, 29 if rank_value == 1 else 10)
		assert_eq(booster.duration, 10.0 if rank_value == 1 else 200.0)
		assert_eq(booster.buff_effects, {"attack_speed": 2.0})
	var info: Dictionary = lib.node("Character.wz/Weapon/01462000.img/info")
	assert_eq(int(info.incPAD), 44)
	assert_eq(int(info.reqLevel), 28)
	assert_eq(int(info.reqSTR), 28)
	assert_eq(int(info.reqDEX), 80)
	for id in [2061001, 2061002, 2061003]:
		assert_false(lib.anim(Ammo.bullet_path(id)).is_empty())
	assert_eq(Array(lib.missing), [])
	lib.free()
