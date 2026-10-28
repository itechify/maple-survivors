extends TestCase
## Hunter #202: real-data skill contracts and fixed-tick combat through public interfaces. The Hunter is set up directly
## (#284: no advancement), with the HP/MP the removed Bowman and Hunter grants used to add in its base pools.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const KEYS := ["bow_mastery", "final_attack_bow", "bow_booster", "power_knockback_bow", "arrow_bomb"]


func _world() -> RunWorld:
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["212"]["starting_skill"] = ""; data.jobs_survivor.jobs["212"]["mobility_skill"] = ""
	data.balance.player.hp = 50 + 125 + 325
	var setup := RF.with_basic_attack(RF.setup("quiet", 202, data))
	setup.equipment_info.merge({1452051: {"incPAD": 28, "attackSpeed": 6, "tuc": 7},
		1462001: {"incPAD": 29, "attackSpeed": 6, "tuc": 7},
		1452005: {"incPAD": 45, "attackSpeed": 6, "tuc": 7}}, true)
	var w := RunWorld.new(setup)
	RF.as_job(w, 300, "bow")
	# Weapon-switch tests own an acquired crossbow; it is no longer an advancement spare.
	w.equipment.inventory.append(Equipment.create(1462001, setup.equipment_info[1462001]))
	RF.place_player(w, 400)
	w.drain_events()
	return w


func _ids(w: RunWorld) -> Array:
	return w.equipment.inventory.map(func(item: Dictionary) -> int: return int(item.id))


func test_power_knockback_formula_uses_150_divisor_and_fixed_mastery() -> void:
	var w := _world()
	w.progression.level = 30
	RF.as_job(w, 310)
	assert_true(w.learn_skill("power_knockback_bow"))
	w.loadout.str_stat = 35
	w.loadout.dex_stat = 100
	w.loadout.watk = 50
	var st := w.loadout.stats("power_knockback_bow")
	# Worked ticket example: max (340+35)*50/150 =125; min (340*.09+35)*50/150=21.8666667.
	assert_near(st.damage_max, 125, 0.0001)
	assert_near(st.damage_min, 21.8666667, 0.0001)
	w.loadout.mastery = 0.6
	assert_near(w.loadout.stats("power_knockback_bow").damage_min, 21.8666667, 0.0001,
		"the melee swing ignores Bow Mastery")


func _hunter(key := "", rank_value := 1) -> RunWorld:
	var w := _world()
	w.progression.level = 30
	RF.as_job(w, 310)
	for kind: MobKind in w.mob_kinds:
		kind.move_speed = 0
		kind.hitbox = Rect2(-2, -10, 4, 10)
	if key != "":
		assert_true(w.learn_skill(key))
		w.loadout.set_rank(key, rank_value)
		w.refresh_player_stats()
	w.drain_events()
	return w


func _mob(w: RunWorld, dx: float, boss := false) -> int:
	var slot := RF.put_mob(w, 2220000 if boss else 1110100, w.player.pos.x + dx, 190, 100000)
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	return slot


func test_knockback_waits_for_range_casts_once_faces_nearest_caps_and_pushes_nonbosses() -> void:
	var w := _hunter("power_knockback_bow")
	var far := _mob(w, 170)
	w.runner.step(DT, w)
	assert_eq(w.runner.casts, 0)
	var near := _mob(w, -60)
	var second := _mob(w, 80)
	var boss := _mob(w, 100, true)
	w.runner.step(DT, w)
	assert_eq(w.runner.casts, 1)
	assert_eq(w.player.facing, -1)
	var hits := w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "mob_hit" and e.skill == "power_knockback_bow")
	assert_eq(hits.size(), 2, "canonical rank-one mobCount")
	assert_false(hits.any(func(e: Dictionary) -> bool: return int(e.mob) == far))
	w.loadout.set_rank("power_knockback_bow", 20)
	var pushed := false
	for tick in 20:
		w.swarm.x[near] = w.player.pos.x - 60
		w.hit_mob(near, w.loadout.stats("power_knockback_bow"), -1)
		pushed = pushed or is_equal_approx(w.swarm.x[near], w.player.pos.x - 180)
		w.hit_mob(boss, w.loadout.stats("power_knockback_bow"), -1)
	assert_true(pushed, "seeded 70% chance pushes the non-boss away by 120px")
	assert_near(w.swarm.x[boss], w.player.pos.x + 100)
	assert_eq(w.swarm.status_time(boss, MobSwarm.STUN), 0.0)
	assert_true(w.swarm.active[second] != 0)


func test_arrow_bomb_flys_before_blast_caps_at_six_uses_x_and_stuns_except_bosses() -> void:
	var w := _hunter("arrow_bomb", 30)
	var slots: Array[int] = []
	for dx in [80, 100, 120, 140, 160, 180, 200, 400]:
		slots.append(_mob(w, dx))
	w.runner.step(DT, w)
	assert_eq(w.projectiles.active_count(), 1)
	assert_eq(w.swarm.hp[slots[0]], w.swarm.max_hp[slots[0]], "no blast until projectile impact")
	assert_near(w.loadout.stats("arrow_bomb").damage_pct, 1.3)
	for tick in 30:
		w.step(DT, MoveInput.new())
	var hits := w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "mob_hit" and e.skill == "arrow_bomb")
	assert_eq(hits.size(), 6, "primary included in canonical blast cap")
	assert_eq(w.projectiles.active_count(), 0)
	assert_eq(w.swarm.hp[slots[6]], w.swarm.max_hp[slots[6]], "seventh target excluded by cap")
	assert_eq(w.swarm.hp[slots[7]], w.swarm.max_hp[slots[7]], "distant mob excluded by box")
	assert_true(slots.slice(0, 6).any(func(slot: int) -> bool: return w.swarm.status_time(slot, MobSwarm.STUN) > 0))
	var boss := _mob(w, -80, true)
	for hit in 20:
		w.hit_mob(boss, w.loadout.stats("arrow_bomb"), -1)
	assert_eq(w.swarm.status_time(boss, MobSwarm.STUN), 0.0)
	assert_near(w.swarm.x[boss], w.player.pos.x - 80)


func test_booster_refuses_lethal_hp_then_pays_hp_and_recasts() -> void:
	var w := _hunter("bow_booster")
	assert_true(w.spend_hp(int(w.player_state.hp) - 29))
	w.runner.step(DT, w)
	assert_eq(w.runner.casts, 0)
	assert_eq(w.player_state.hp, 29)
	w.restore_player("hp", 71, "fixture")
	assert_eq(w.player_state.hp, 100)
	w.runner.step(DT, w)
	assert_eq(w.player_state.hp, 71)
	assert_eq(w.attack_speed_boost(), 2)
	w.runner.step(DT, w)
	assert_eq(w.runner.casts, 1, "no recast while active")
	w.god = true
	for tick in 602:
		w.step(DT, MoveInput.new())
	assert_eq(w.runner.casts, 2, "recast after canonical ten-second duration")
	assert_eq(w.attack_speed_boost(), 2, "refresh never stacks")


func test_mastery_final_attack_and_a_crossbow_swap_keeps_every_hunter_skill_and_card() -> void:
	var w := _hunter()
	for key: String in KEYS:
		assert_false(key + "_new" in w.upgrades.eligible(w), "#287: unported skills have no pool offers")
		assert_true(w.learn_skill(key))
		w.loadout.set_rank(key, w.book.max_rank(key))
	w.refresh_player_stats()
	assert_near(w.loadout.mastery, 0.6)
	assert_near(w.loadout.passive_total("acc"), 20)
	var mob := _mob(w, 80)
	for hit in 20:
		w.hit_mob(mob, w.loadout.stats("power_knockback_bow"), -1)
	w.step(DT, MoveInput.new())
	var events := w.drain_events()
	assert_true(events.any(func(e: Dictionary) -> bool: return e.type == "final_attack" and e.skill == "final_attack_bow"))
	assert_true(events.any(func(e: Dictionary) -> bool: return e.type == "ammo_shot" and e.skill == "final_attack_bow" and e.ball == Ammo.bullet_path(2060001)))
	for key: String in KEYS:
		w.loadout.set_rank(key, 1)
	w.refresh_player_stats()
	for key: String in KEYS:
		assert_false(key + "_rank" in w.upgrades.eligible(w), "#287: unported skills have no pool offers")
	# #284: weapons gate no skill, card or passive: with a crossbow every Hunter skill still counts and stays on offer.
	var mastery := w.loadout.mastery
	assert_eq(w.equip_item(_ids(w).find(1462001)), "")
	assert_near(w.loadout.mastery, mastery, 1e-6, "Bow Mastery counts with a crossbow")
	for key: String in KEYS:
		assert_eq(w.book.weapon_families(key), PackedStringArray(["bow"]), "the data still names the bow")
		assert_false(key + "_rank" in w.upgrades.eligible(w), "#287: unported skills have no pool offers")
	assert_false(w.book.defs.values().any(func(d: Dictionary) -> bool: return int(d.get("skill_id", 0)) in [3101004, 3201004]))


func test_behavior_cards_add_targets_and_arrows_using_shared_rarity_magnitudes() -> void:
	var w := _hunter("power_knockback_bow")
	assert_eq(w.loadout.stats("power_knockback_bow").mob_count, 2)
	RF.add_modifier_effects(w, w.upgrades.card("power_knockback_bow_targets"))
	assert_eq(w.loadout.stats("power_knockback_bow").mob_count, 3)
	w.learn_skill("arrow_bomb")
	assert_eq(w.loadout.stats("arrow_bomb").count, 1)
	assert_eq(w.loadout.stats("arrow_bomb").blast_targets, 6)
	RF.add_modifier_effects(w, w.upgrades.card("arrow_bomb_shots"))
	RF.add_modifier_effects(w, w.upgrades.card("arrow_bomb_targets"))
	assert_eq(w.loadout.stats("arrow_bomb").count, 2)
	assert_eq(w.loadout.stats("arrow_bomb").blast_targets, 7)
	# The binding first-job carry exception survives; its cards never enter the advancement draw.
	assert_false("arrow_blow_new" in w.upgrades.eligible(w), "#287: unported skills have no pool offers")
	var first := _world()
	for key: String in KEYS:
		assert_false(key + "_new" in first.upgrades.eligible(first))
	var follow := _hunter("final_attack_bow", 30)
	RF.add_modifier_effects(follow, follow.upgrades.card("final_attack_bow_spread"))
	assert_eq(follow.loadout.stats("final_attack_bow").count, 2)
	var primary := _mob(follow, 80)
	var extra := _mob(follow, 180)
	for hit in 20:
		follow.hit_mob(primary, follow.loadout.stats("arrow_blow"), -1)
	follow.step(DT, MoveInput.new())
	var hits := follow.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "mob_hit" and e.skill == "final_attack_bow")
	assert_true(hits.any(func(e: Dictionary) -> bool: return int(e.mob) == primary))
	assert_true(hits.any(func(e: Dictionary) -> bool: return int(e.mob) == extra))


func test_arrow_schedule_changes_at_30_40_50_announces_and_catches_up_on_advancement() -> void:
	var w := _world()
	w.progression.level = 50
	RF.as_job(w, 310)
	assert_eq(w.ammo_id(), 2060003, "late advancement chooses highest reached tier")
	w.drain_events()
	for row: Array in [[29,2060000],[30,2060001],[39,2060001],[40,2060002],[49,2060002],[50,2060003]]:
		w.progression.level = row[0]
		w.refresh_player_stats()
		assert_eq(w.ammo_id(), row[1])
		var notices := w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "ammo_upgraded")
		if int(row[0]) in [30,40,50]:
			assert_eq(notices.size(), 1)
			if not notices.is_empty():
				assert_eq(notices[0].item_id, row[1])


func test_real_hunter_levels_costs_effects_icons_art_sounds_and_ryden() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	var img := lib.img("Skill.wz/310.img")
	assert_true(img != null)
	if img == null:
		lib.free()
		return
	var book := SkillBook.from_data(DataRepo.load_all().skills, {"310": img.root})
	var lo := Loadout.new(book)
	lo.weapon_family = "bow"
	for row: Array in [["bow_mastery",20],["final_attack_bow",30],["bow_booster",20],["power_knockback_bow",20],["arrow_bomb",30]]:
		var key: String = row[0]
		assert_eq(book.max_level(key), row[1])
		assert_eq(book.max_rank(key), row[1])
		for suffix: String in ["icon", "iconDisabled", "iconMouseOver"]:
			assert_true(lib.frame(book.wz_path(key) + "/" + suffix) != null)
		for field: String in ["ball", "effect", "hit"]:
			var path := book.visual(key, field, 1, 30)
			if path != "":
				assert_false(lib.anim(path).is_empty(), path)
		for sound: String in book.def(key).sounds.values():
			if sound != "":
				assert_true(lib.sound(sound) != null)
	for rank_value in [1,20]:
		var st := lo.stats("power_knockback_bow", rank_value)
		assert_eq(st.mob_count, 2 if rank_value == 1 else 6)
		assert_eq(st.range, 130.0 if rank_value == 1 else 150.0)
		assert_near(st.damage_pct, 1.05 if rank_value == 1 else 2.0)
		assert_eq(st.knockback_chance, 13.0 if rank_value == 1 else 70.0)
		var booster := lo.stats("bow_booster", rank_value)
		assert_eq(booster.hp_cost, 29 if rank_value == 1 else 10)
		assert_eq(booster.duration, 10.0 if rank_value == 1 else 200.0)
		assert_eq(booster.buff_effects, {"attack_speed": 2.0})
	for rank_value in [1,30]:
		var st := lo.stats("arrow_bomb", rank_value)
		assert_eq(st.blast_targets, 6)
		assert_eq(st.count, 1)
		assert_near(st.damage_pct, 0.72 if rank_value == 1 else 1.30)
		assert_eq(st.box, Rect2(-130,-100,260,200) if rank_value == 1 else Rect2(-150,-100,300,200))
		assert_eq(book.canonical("arrow_bomb", rank_value, "prop"), 31.0 if rank_value == 1 else 60.0)
		assert_eq(book.canonical("arrow_bomb", rank_value, "time"), 2.0 if rank_value == 1 else 6.0)
		assert_eq(book.canonical("final_attack_bow", rank_value, "prop"), 2.0 if rank_value == 1 else 60.0)
		assert_near(lo.stats("final_attack_bow", rank_value).damage_pct, 1.05 if rank_value == 1 else 2.50)
	lo.add_skill("bow_mastery")
	assert_eq(lo.passive_total("mastery"), 1.0)
	assert_eq(lo.passive_total("acc"), 1.0)
	lo.set_rank("bow_mastery", 20)
	assert_eq(lo.passive_total("mastery"), 10.0)
	assert_eq(lo.passive_total("acc"), 20.0)
	var info: Dictionary = lib.node("Character.wz/Weapon/01452005.img/info")
	assert_eq(int(info.incPAD), 45)
	assert_eq(int(info.reqLevel), 30)
	assert_eq(int(info.reqSTR), 35)
	assert_eq(int(info.reqDEX), 95)
	for id in [2060001,2060002,2060003]:
		assert_false(lib.anim(Ammo.bullet_path(id)).is_empty())
	assert_eq(Array(lib.missing), [])
	lib.free()
