extends TestCase
## Assassin / Bandit (#212): seeded public-world advancement, weapon gates, recovery and star tiers.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const INFO := {
	1472061: {"incPAD": 11, "attackSpeed": 5, "tuc": 7},
	1332063: {"incPAD": 28, "attackSpeed": 3, "tuc": 7},
	1472008: {"reqLevel": 30, "reqDEX": 60, "incPAD": 18, "attackSpeed": 4, "tuc": 7},
	1332012: {"reqLevel": 30, "reqDEX": 60, "incPAD": 45, "attackSpeed": 4, "tuc": 7},
}


## Seeded first-job Thief of either path; tests set its advancement level. Grants deliberately exceed its DEX.
func _thief(path := "claw") -> RunWorld:
	var data := RF.quiet_data()
	data.balance.player.skills = []
	data.balance.regen.hp = 0
	data.balance.regen.mp = 0
	var setup := RF.with_basic_attack(RF.setup("quiet", 212, data))
	setup.equipment_info.merge(INFO, true)
	var w := RunWorld.new(setup)
	w.change_job(400, path)
	RF.place_player(w, 400)
	w.god = true
	w.pending_cards = []
	w.state = RunWorld.PLAYING
	return w


## Branch fixture for downstream Drain / Bandit attack tests, with both first-job weapons available to swap.
func _branch(job: int, path := "claw", level := 30) -> RunWorld:
	var w := _thief(path)
	w.progression.level = level
	w.change_job(job)
	w.pending_cards = []
	w.state = RunWorld.PLAYING
	w.drain_events()
	return w


func _inventory(w: RunWorld) -> Array:
	return w.equipment.inventory.map(func(item: Dictionary) -> int: return int(item.id))


func _wear(w: RunWorld, id: int) -> void:
	# Weapon-switch tests own an independently acquired alternative; advancement grants only its chosen weapon.
	if id not in _inventory(w):
		w.equipment.inventory.append(Equipment.create(id, INFO.get(id, {})))
	assert_eq(w.equip_item(_inventory(w).find(id)), "")


func test_lv30_offers_both_branches_grants_pools_and_wears_the_branch_weapon_without_requirements() -> void:
	for path in ["claw", "dagger"]:
		for job in [410, 420]:
			var w := _thief(path)
			w.progression.level = 29
			w.progression.add_exp(w.progression.exp_to_next())
			w.step(DT, MoveInput.new())
			assert_eq(w.state, RunWorld.CHOOSING_JOB)
			assert_eq(w.pending_jobs.filter(func(o: Dictionary) -> bool: return o.available).map(
				func(o: Dictionary) -> int: return int(o.job_id)), [410, 420])
			var hp: int = w.player_state.max_hp
			var mp: int = w.player_state.max_mp
			assert_true(w.apply_job(job))
			assert_eq(w.weapon_id(), 1472008 if job == 410 else 1332012)
			assert_has(_inventory(w), 1472061 if path == "claw" else 1332063)
			assert_eq(w.player_state.max_hp, hp + 325)
			assert_eq(w.player_state.max_mp, mp + 175)
			assert_eq(w.weapon_path, path)


func test_masteries_and_critical_throw_follow_the_held_weapon() -> void:
	for job in [410, 420]:
		var w := _branch(job)
		var key := "claw_mastery" if job == 410 else "dagger_mastery"
		var acc: float = w.player_state.acc
		assert_true(w.learn_skill(key))
		assert_near(w.loadout.mastery, 0.15)
		assert_near(w.player_state.acc, acc + 1)
		w.loadout.set_rank(key, 20)
		w.refresh_player_stats(false)
		assert_near(w.loadout.mastery, 0.60)
		assert_near(w.player_state.acc, acc + 20)
		if job == 410:
			assert_true(w.learn_skill("critical_throw"))
			assert_near(w.loadout.crit_bonus, 0.21)
			assert_near(w.loadout.crit_damage_bonus, 13.0)
			w.loadout.set_rank("critical_throw", 30)
			w.refresh_player_stats(false)
			assert_near(w.loadout.crit_bonus, 0.50)
			assert_near(w.loadout.crit_damage_bonus, 100.0)
		_wear(w, 1332063 if job == 410 else 1472061)
		assert_near(w.loadout.mastery, Loadout.BASE_MASTERY)
		assert_near(w.loadout.crit_bonus, 0.0)
		assert_near(w.loadout.crit_damage_bonus, 0.0)
		assert_near(w.player_state.acc, acc)


func _ticks(w: RunWorld, count: int) -> void:
	for tick in count:
		w.step(DT, MoveInput.new())


func test_boosters_pay_both_costs_speed_the_branch_weapon_and_stop_counting_on_a_swap() -> void:
	for job in [410, 420]:
		var w := _branch(job)
		var key := "claw_booster" if job == 410 else "dagger_booster"
		assert_true(w.learn_skill(key))
		w.heal_fraction("hp", 1)
		w.heal_fraction("mp", 1)
		var hp: int = w.player_state.hp
		var mp: int = w.player_state.mp
		_ticks(w, 1)
		assert_true(w.buffs.has(key))
		assert_eq(w.attack_speed_boost(), 2)
		assert_eq(w.player_state.hp, hp - 29)
		assert_eq(w.player_state.mp, mp - 29)
		_wear(w, 1332063 if job == 410 else 1472061)
		assert_true(w.buffs.has(key))
		assert_eq(w.attack_speed_boost(), 0)
		w.buffs.clear()
		_ticks(w, 120)
		assert_false(w.buffs.has(key), "the wrong weapon cannot cast a Booster")


func test_haste_auto_casts_with_either_weapon_and_caps_speed_and_jump() -> void:
	for job in [410, 420]:
		for swap in [false, true]:
			var w := _branch(job)
			if swap:
				_wear(w, 1332063 if job == 410 else 1472061)
			var key := "haste_assassin" if job == 410 else "haste_bandit"
			assert_true(w.learn_skill(key))
			w.heal_fraction("mp", 1)
			_ticks(w, 1)
			assert_true(w.buffs.has(key), "self auto-cast without a mob")
			assert_eq(w.player.speed_stat, 102)
			assert_eq(w.player.jump_stat, 101)
			w.buffs.clear()
			w.loadout.set_rank(key, 20)
			# Synthetic shoes exercise the existing caps with canonical Haste at its maximum.
			w.equipment.worn["shoes"] = Equipment.create(1072001, {"incSpeed": 20, "incJump": 10})
			w.refresh_player_stats(false)
			w.heal_fraction("mp", 1)
			_ticks(w, 610)
			assert_true(w.buffs.has(key))
			assert_eq(w.player.speed_stat, 140)
			assert_eq(w.player.jump_stat, 123)


func test_endure_pulses_both_pools_anywhere_on_its_own_clock_from_learning() -> void:
	for job in [410, 420]:
		for rank_value in [1, 20]:
			var w := _branch(job)
			_wear(w, 1332063 if job == 410 else 1472061)
			_ticks(w, 180)
			var key := "endure_assassin" if job == 410 else "endure_bandit"
			assert_true(w.learn_skill(key))
			w.loadout.set_rank(key, rank_value)
			w.heal_fraction("hp", 1)
			w.spend_hp(int(w.player_state.hp) - 1)
			w.spend_mp(int(w.player_state.mp))
			var interval := 29 if rank_value == 1 else 10
			_ticks(w, interval * 60 - 1)
			assert_eq(w.player_state.hp, 1, "no shared 10s pulse or early own pulse")
			assert_eq(w.player_state.mp, 0)
			_ticks(w, 1)
			assert_eq(w.player_state.hp, 4 if rank_value == 1 else 61)
			assert_eq(w.player_state.mp, 1 if rank_value == 1 else 20)
			_ticks(w, interval * 60)
			assert_eq(w.player_state.hp, 7 if rank_value == 1 else 121)
			assert_eq(w.player_state.mp, 2 if rank_value == 1 else 40)


func test_endure_clamps_both_pools_pauses_with_the_world_and_resets_at_round_boundaries() -> void:
	var w := _branch(410)
	w.learn_skill("endure_assassin")
	w.loadout.set_rank("endure_assassin", 20)
	w.heal_fraction("hp", 1)
	w.heal_fraction("mp", 1)
	w.spend_hp(1)
	w.spend_mp(1)
	_ticks(w, 599)
	var setup := w.setup.duplicate(true)
	setup.character = w.character_snapshot()
	var restored := RunWorld.new(setup)
	RF.place_player(restored, 400)
	restored.spend_hp(int(restored.player_state.hp) - 1)
	restored.spend_mp(int(restored.player_state.mp))
	_ticks(restored, 1)
	assert_eq(restored.player_state.hp, 1, "the previous round's 599 ticks are not carried")
	assert_eq(restored.player_state.mp, 0)
	w.state = RunWorld.CHOOSING_UPGRADE
	_ticks(w, 120)
	assert_eq(w.player_state.hp, w.player_state.max_hp - 1)
	assert_eq(w.player_state.mp, w.player_state.max_mp - 1)
	w.state = RunWorld.PLAYING
	_ticks(w, 1)
	assert_eq(w.player_state.hp, w.player_state.max_hp)
	assert_eq(w.player_state.mp, w.player_state.max_mp)


const BRANCH_SKILLS := {410: ["claw_mastery", "critical_throw", "endure_assassin", "claw_booster", "haste_assassin"],
	420: ["dagger_mastery", "endure_bandit", "dagger_booster", "haste_bandit"]}


func test_branch_cards_require_the_exact_job_and_weapon_while_attacks_carry_only_in_normal_draws() -> void:
	for job: int in BRANCH_SKILLS:
		var w := _thief()
		w.progression.level = 29
		w.progression.add_exp(w.progression.exp_to_next())
		w.step(DT, MoveInput.new())
		assert_true(w.apply_job(job))
		for card: Dictionary in w.pending_cards:
			assert_eq(int(w.book.def(card.skill).job), job, "advancement draw belongs to the new branch")
		for swap in [false, true]:
			if swap:
				_wear(w, 1332063 if job == 410 else 1472061)
			var held := w.held_weapon_family()
			var eligible := w.upgrades.eligible(w)
			assert_eq("lucky_seven_new" in eligible, held == "claw")
			assert_eq("double_stab_new" in eligible, held == "dagger")
			for branch: int in BRANCH_SKILLS:
				for key: String in BRANCH_SKILLS[branch]:
					assert_eq(key + "_new" in eligible, branch == job and w.book.usable_with(key, held), key)
			w.learn_skill("lucky_seven")
			w.learn_skill("double_stab")
			for key: String in BRANCH_SKILLS[job]:
				w.learn_skill(key)
			eligible = w.upgrades.eligible(w)
			assert_eq("lucky_seven_rank" in eligible, held == "claw")
			assert_eq("lucky_seven_count" in eligible, held == "claw")
			assert_eq("double_stab_rank" in eligible, held == "dagger")
			assert_eq("double_stab_targets" in eligible, held == "dagger")
			for key: String in BRANCH_SKILLS[job]:
				assert_eq(key + "_rank" in eligible, w.book.usable_with(key, held), key)
			# Restore unlearned fixtures for the next held-weapon case.
			if not swap:
				w = _branch(job)
	var first := _thief()
	for keys: Array in BRANCH_SKILLS.values():
		for key: String in keys:
			assert_false(key + "_new" in first.upgrades.eligible(first))


func test_assassin_star_tiers_emit_notices_and_change_the_lucky_seven_sprite_bandits_keep_starters() -> void:
	var w := _branch(410)
	assert_eq(w.ammo_id(), 2070001)
	w.learn_skill("lucky_seven")
	var got := []
	for level in range(31, 56):
		w.progression.add_exp(w.progression.exp_to_next())
		w.step(DT, MoveInput.new())
		while w.state != RunWorld.PLAYING:
			BotInput.auto_choose(w, false, 410)
		for event: Dictionary in w.drain_events():
			if event.type == "ammo_upgraded":
				got.append([level, event.item_id])
				assert_eq(Ammo.bullet_path(w.ammo_id()), "Item.wz/Consume/0207.img/%08d/bullet" % int(event.item_id))
	assert_eq(got, [[35, 2070002], [40, 2070003], [45, 2070004], [50, 2070005], [55, 2070006]])
	var bandit := _branch(420)
	_wear(bandit, 1472061)
	for level in range(31, 56):
		bandit.progression.level = level
		bandit.refresh_player_stats(false)
		assert_eq(bandit.ammo_id(), 2070015)
	assert_eq(bandit.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "ammo_upgraded"), [])


func test_each_assassin_tier_fires_the_current_stars_as_lucky_seven_projectiles() -> void:
	for tier in range(6):
		var w := _branch(410, "claw", 30 + 5 * tier)
		w.learn_skill("lucky_seven")
		w.heal_fraction("mp", 1)
		RF.put_mob(w, 1110100, w.player.pos.x + 100, 190, 10000)
		w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
		w.runner.step(DT, w)
		assert_eq(w.projectiles.active_count(), 2)
		for i in w.projectiles.capacity():
			if w.projectiles.active[i] != 0:
				assert_eq(w.projectiles.paths[w.projectiles.visual[i]],
					"Item.wz/Consume/0207.img/%08d/bullet" % (2070001 + tier))


func test_forced_branch_tools_draw_the_first_job_path_and_take_the_single_family_branch() -> void:
	var data := DataRepo.load_all()
	var jobs := JobTree.from_data(data.jobs, data.jobs_survivor)
	for job in [410, 420]:
		var parsed := SceneFlow.parse_run_args(PackedStringArray(["--run=henesys_hg1", "--job=%d" % job]))
		assert_eq(SceneFlow.forced_job_error(parsed.options, data), "")
		var w := _thief()
		var pick := BotInput.pick_choice(jobs.advancements(0, 10), w.job_rng, job, jobs, "")
		assert_eq(pick.job_id, 400)
		assert_true(pick.path in ["claw", "dagger"])
		assert_eq(BotInput.pick_choice(jobs.advancements(400, 30), w.job_rng, job, jobs, ""), {"job_id": job, "path": ""})


func test_original_branch_tables_costs_art_sounds_and_weapons_resolve_in_the_private_cache() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	var imgs := {}
	for id in ["410", "420"]:
		var img := lib.img("Skill.wz/%s.img" % id)
		assert_true(img != null)
		if img == null:
			lib.free()
			return
		imgs[id] = img.root
	var book := SkillBook.from_data(DataRepo.load_all().skills, imgs)
	var synthetic := SkillBook.from_data(DataRepo.load_all().skills, RF.skill_imgs())
	var lo := Loadout.new(book)
	var text := SkillText.new(book, {})
	assert_eq(text.level_line("haste_assassin", 20, lo.stats("haste_assassin", 20)),
		"MP -30; Speed +40, Jump +20 for 200 sec.")
	assert_eq(text.level_line("endure_bandit", 20, lo.stats("endure_bandit", 20)),
		"Recover +60 HP and +20 MP every 10 sec.")
	for keys: Array in BRANCH_SKILLS.values():
		for key: String in keys:
			assert_eq(book.max_level(key), 30 if key == "critical_throw" else 20)
			assert_eq(book.max_rank(key), book.max_level(key))
			assert_true(lib.node(String(book.def(key).icon)) != null)
			for lv in range(1, book.max_level(key) + 1):
				for field in ["mastery", "x", "prop", "damage", "time", "hp", "mp", "hpCon", "mpCon", "speed", "jump"]:
					assert_eq(synthetic.canonical(key, lv, field), book.canonical(key, lv, field), "%s Lv%d %s fixture" % [key, lv, field])
			if book.kind(key) == "buff":
				assert_false(lib.anim(String(book.def(key).effect)).is_empty())
				assert_true(lib.sound(String(book.def(key).sounds.use)) != null)
			if key.ends_with("booster"):
				for lv in [1, 20]:
					var st := lo.stats(key, lv)
					assert_eq(st.buff_effects.attack_speed, 2.0)
					assert_eq(st.hp_cost, 29 if lv == 1 else 10)
					assert_eq(st.mp_cost, 29 if lv == 1 else 10)
	for item in [1472008, 1332012]:
		var info: Dictionary = lib.node("Character.wz/Weapon/%08d.img/info" % item)
		assert_eq(int(info.reqLevel), 30)
		assert_eq(int(info.incPAD), 18 if item == 1472008 else 45)
	for item in range(2070001, 2070007):
		assert_false(lib.anim(Ammo.bullet_path(item)).is_empty())
	assert_eq(Array(lib.missing), [])
	lib.free()
