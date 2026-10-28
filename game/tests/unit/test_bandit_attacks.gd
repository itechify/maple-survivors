extends TestCase
## Bandit attacks (#214): seeded casting, extra loot and per-logical-mob Stolen lifecycle.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const INFO := {
	1472061: {"incPAD": 11, "attackSpeed": 5, "tuc": 7},
	1332063: {"incPAD": 28, "attackSpeed": 3, "tuc": 7},
	1472008: {"reqLevel": 30, "reqDEX": 60, "incPAD": 18, "attackSpeed": 4, "tuc": 7},
	1332012: {"reqLevel": 30, "reqDEX": 60, "incPAD": 45, "attackSpeed": 4, "tuc": 7},
}


## A Lv30 Bandit (420) set directly (#284: no advancement) wearing the Reef Claw dagger, with the HP the removed
## first- and second-job grants used to add (+125, +325) folded into the base pool (no MP, #285).
func _bandit() -> RunWorld:
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["212"]["starting_skill"] = ""; data.jobs_survivor.jobs["212"]["mobility_skill"] = ""
	data.balance.player.hp = 50 + 125 + 325
	data.balance.regen.hp = 0
	var setup := RF.with_basic_attack(RF.setup("quiet", 212, data))
	setup.equipment_info.merge(INFO, true)
	var w := RunWorld.new(setup)
	w.progression.level = 30
	RF.as_job(w, 420)
	RF.place_player(w, 400)
	w.god = true
	w.drain_events()
	return w


func _wear(w: RunWorld, id: int) -> void:
	var ids: Array = w.equipment.inventory.map(func(item: Dictionary) -> int: return int(item.id))
	if id not in ids:
		w.equipment.inventory.append(Equipment.create(id, INFO.get(id, {})))
		ids.append(id)
	assert_eq(w.equip_item(ids.find(id)), "")


func _world() -> RunWorld:
	var w := _bandit()
	# Synthetic afterimage permits a real dagger weapon_reach cast.
	w.setup.equipment_info[1332012] = w.setup.equipment_info[1332012].merged({"afterImage": "swordOS"})
	return w


func _target(w: RunWorld) -> int:
	var m := RF.put_mob(w, 1110100, 450, 190, 10000)
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	return m


func _hits(w: RunWorld, key: String) -> Array:
	return w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "mob_hit" and e.skill == key)


func test_bandit_without_steal_preserves_event_and_player_bytes() -> void:
	var w := _world()
	var thief_state := w.thief_rng.state
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	for tick in 600:
		if tick % 60 == 0:
			RF.put_mob(w, 1110100, 450)
		w.step(DT, MoveInput.new())
		digest.update(var_to_bytes(w.drain_events()))
		digest.update(var_to_bytes(w.player_state))
	assert_eq(w.thief_rng.state, thief_state)
	# Captured before #214 on #212 c30848d; re-captured for #238 (cooldown snapshot replaces stock).
	# This fixture learns neither new attack; stream 15 remains untouched. Re-captured for #284 (no basic attack, the
	# Bandit set directly) with #285 (no MP: player_state has no mp/max_mp/mp_short and casts pay no MP).
	assert_eq(digest.finish().hex_encode(), "a1ab34c5cd8709e9a7546996f1c3813a98a3a3b5cbc13e6c416a46f90794124d")


func test_savage_blow_casts_four_five_or_six_lines_with_any_weapon() -> void:
	for pair: Array in [[1, 4, 15], [10, 4, 15], [11, 5, 18], [20, 5, 18], [21, 6, 27], [30, 6, 27]]:
		var w := _world()
		assert_true(w.learn_skill("savage_blow"))
		w.loadout.set_rank("savage_blow", pair[0])
		_target(w)
		w.runner.step(DT, w)
		assert_eq(_hits(w, "savage_blow").size(), pair[1])
	# #284: weapons gate no skill, so a claw casts it too.
	var claw := _world()
	claw.learn_skill("savage_blow")
	_wear(claw, 1472061)
	_target(claw)
	claw.runner.step(DT, claw)
	assert_eq(_hits(claw, "savage_blow").size(), 4)


func test_steal_rolls_canonical_chance_on_stream_15_and_retries_until_one_drop() -> void:
	for rank_value in [1, 30]:
		var w := _world()
		assert_true(w.learn_skill("steal"))
		w.loadout.set_rank("steal", rank_value)
		var st := w.runner.stats_of(w, "steal")
		var expected := RandomNumberGenerator.new()
		expected.state = w.thief_rng.state
		var failures := 0
		var successes := 0
		for trial in 200:
			var m := _target(w)
			var should_succeed := expected.randf() * 100.0 < (11.0 if rank_value == 1 else 40.0)
			w.drain_events()
			w.hit_mob(m, st, -1)
			var drops := w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "pickup_spawned")
			assert_eq(w.swarm.stolen[m], 1 if should_succeed else 0)
			assert_eq(drops.size(), 1 if should_succeed else 0)
			assert_eq(w.thief_rng.state, expected.state, "exactly one stream-15 success roll per eligible line")
			if should_succeed:
				successes += 1
				var state := w.thief_rng.state
				for repeat_hit in 3:
					w.hit_mob(m, st, -1)
				assert_eq(w.thief_rng.state, state, "Stolen consumes no further rolls")
				assert_eq(w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "pickup_spawned").size(), 0)
			else:
				failures += 1
				# The same mob remains eligible; later lines must eventually succeed.
				for retry in 100:
					var success := expected.randf() * 100.0 < (11.0 if rank_value == 1 else 40.0)
					w.hit_mob(m, st, -1)
					assert_eq(w.swarm.stolen[m], 1 if success else 0)
					if success:
						break
				assert_eq(w.swarm.stolen[m], 1)
				assert_eq(w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "pickup_spawned").size(), 1)
			w.swarm.despawn(m)
		assert_true(successes > 0 and failures > 0, "both roll outcomes exercised")


func test_steal_autocasts_in_melee_with_any_weapon_and_never_throws_a_star() -> void:
	for claw in [false, true]:
		var w := _world()
		if claw:
			_wear(w, 1472061)
		assert_true(w.learn_skill("steal"))
		_target(w)
		w.runner.step(DT, w)
		assert_eq(_hits(w, "steal").size(), 1)
		assert_eq(w.projectiles.active_count(), 0)
		assert_eq(w.runner.casts, 1)
	var far := _world()
	far.learn_skill("steal")
	RF.put_mob(far, 1110100, 650)
	far.mob_grid.rebuild(far.swarm.x, far.swarm.y, far.swarm.active)
	far.runner.step(DT, far)
	assert_eq(far.runner.casts, 0, "claw range does not turn Steal into a ranged attack")


func _steal_until_success(w: RunWorld, m: int, st: Dictionary) -> void:
	for attempt in 100:
		w.hit_mob(m, st, -1)
		if w.swarm.stolen[m] != 0:
			break
	assert_eq(w.swarm.stolen[m], 1)


func test_bosses_can_be_stolen_once_relocation_preserves_it_and_fresh_slots_reset_it() -> void:
	var w := _world()
	w.learn_skill("steal")
	var m := _target(w)
	# A canonical boss and the scheduled-boss guard both reject statuses; neither rejects Steal.
	w.swarm.mob_kind(m).boss = true
	w.swarm.steady[m] = 1
	assert_false(w.swarm.accepts_status(m, "stun"))
	var st := w.runner.stats_of(w, "steal")
	w.drain_events()
	_steal_until_success(w, m, st)
	assert_eq(w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "pickup_spawned").size(), 1)
	var identity := w.swarm.identity[m]
	var moved := w.relocate_mob(m, Vector2(460, 190), w.swarm.fh[m])
	assert_eq(w.swarm.identity[moved], identity)
	assert_eq(w.swarm.stolen[moved], 1)
	var rng_state := w.thief_rng.state
	w.hit_mob(moved, st, -1)
	assert_eq(w.thief_rng.state, rng_state)
	assert_eq(w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "pickup_spawned").size(), 0)
	w.swarm.despawn(moved)
	var fresh := _target(w)
	assert_eq(fresh, moved, "reused slot")
	assert_ne(w.swarm.identity[fresh], identity)
	assert_eq(w.swarm.stolen[fresh], 0)
	_steal_until_success(w, fresh, st)
	# Force growth while the Stolen slot is occupied; new slots must also start eligible.
	for i in w.swarm.capacity() + 1:
		var next := _target(w)
		assert_eq(w.swarm.stolen[next], 0)


func test_steal_extra_equipment_follows_job_and_weapon_families_with_meso_fallback() -> void:
	for claw in [false, true]:
		var w := _world()
		if claw:
			_wear(w, 1472061)
		w.learn_skill("steal")
		w.data.equipment_drops = w.data.equipment_drops.duplicate(true)
		w.data.equipment_drops.chance = 1.0
		w.data.equipment_drops.items = [1332012, 1472008, 1372005]
		w.setup.equipment_info = w.setup.equipment_info.duplicate(true)
		w.setup.equipment_info[1332012].reqJob = 8
		w.setup.equipment_info[1472008].reqJob = 8
		w.setup.equipment_info[1372005].reqJob = 2
		var survivor: Dictionary = w.data.jobs_survivor.duplicate(true)
		survivor.jobs[str(w.progression.job_id)] = {"weapon_families": ["claw" if claw else "dagger"]}
		w.jobs = JobTree.from_data(w.data.jobs, survivor) # the job's weapon family, not the held weapon, picks (#292)
		var m := _target(w)
		w.drain_events()
		var st := w.runner.stats_of(w, "steal")
		_steal_until_success(w, m, st)
		var drops := w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "pickup_spawned")
		assert_eq(drops.size(), 1)
		assert_eq(drops[0].kind, "equip")
		assert_eq(drops[0].item_id, 1472008 if claw else 1332012)
		# Empty admitted equipment pool still yields one meso bundle, never an empty successful Steal.
		w.data.equipment_drops.items = [1372005]
		var second := _target(w)
		w.drain_events()
		_steal_until_success(w, second, st)
		drops = w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "pickup_spawned")
		assert_eq(drops.size(), 1)
		assert_eq(drops[0].kind, "meso")
		assert_true(int(drops[0].count) > 0)


func test_a_lethal_steal_can_take_extra_loot_without_replacing_the_death_roll() -> void:
	var w := _world()
	w.learn_skill("steal")
	var st := w.runner.stats_of(w, "steal")
	# Find a real success-roll state without changing canonical prop or consuming any content stream.
	var oracle := RandomNumberGenerator.new()
	oracle.state = w.thief_rng.state
	for attempt in 100:
		var before := oracle.state
		if oracle.randf() * 100.0 < 11.0:
			w.thief_rng.state = before
			break
	var m := _target(w)
	w.swarm.hp[m] = 1
	w.balance.mesos.chance = 1.0
	w.data.equipment_drops.chance = 0.0
	var kills := w.kills
	w.drain_events()
	w.hit_mob(m, st, -1)
	assert_eq(w.swarm.stolen[m], 1)
	assert_false(w.swarm.is_live(m))
	assert_eq(w.kills, kills + 1)
	var events := w.drain_events()
	var mesos := events.filter(func(e: Dictionary) -> bool: return e.type == "pickup_spawned" and e.kind == "meso")
	assert_eq(mesos.size(), 2, "one extra Steal bundle plus the unchanged death bundle")
	assert_eq(events.filter(func(e: Dictionary) -> bool: return e.type == "mob_died").size(), 1)


func test_learning_steal_does_not_add_steal_rolls_to_other_attacks() -> void:
	var w := _world()
	w.learn_skill("steal")
	w.learn_skill("double_stab")
	var st := w.runner.stats_of(w, "double_stab")
	var m := _target(w)
	var before := w.thief_rng.state
	w.drain_events()
	for hit in 20:
		w.hit_mob(m, st, -1)
	assert_eq(w.thief_rng.state, before)
	assert_eq(w.swarm.stolen[m], 0)
	assert_eq(w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "pickup_spawned").size(), 0)


func test_bandit_attack_cards_are_branch_only_power_cards_with_three_target_steps() -> void:
	for key in ["savage_blow", "steal"]:
		var w := _world()
		assert_false(key + "_new" in w.upgrades.eligible(w), "#287: unported skills have no pool offers")
		assert_true(w.upgrades.card(key + "_new").power)
		assert_true(w.upgrades.apply(key + "_new", w) > 0)
		assert_eq(w.upgrades.card(key + "_rank").max_rank, 30)
		assert_eq(w.upgrades.card(key + "_targets").max_rank, 3)
		for step in 3:
			assert_true(w.upgrades.apply(key + "_targets", w) > 0)
		assert_eq(SkillRunner.strike_count(w.runner.stats_of(w, key)), 4)
		assert_false(key + "_targets" in w.upgrades.eligible(w))
		# Cast all four targets; Savage Blow deals four lines to each at rank 1, Steal one.
		for i in 4:
			_target(w)
		w.runner.step(DT, w)
		assert_eq(_hits(w, key).size(), 16 if key == "savage_blow" else 4)
		for job in [400, 410]:
			w.progression.job_id = job
			assert_false(key + "_rank" in w.upgrades.eligible(w))


func test_original_bandit_attack_tables_and_art_match_the_synthetic_fixture() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	var img := lib.img("Skill.wz/420.img")
	assert_true(img != null)
	if img == null:
		lib.free()
		return
	var defs: Dictionary = DataRepo.load_all().skills
	var book := SkillBook.from_data(defs, {"420": img.root})
	var fixture := SkillBook.from_data(defs, RF.skill_imgs())
	for key in ["savage_blow", "steal"]:
		assert_eq(book.max_level(key), 30)
		for lv in range(1, 31):
			for field in ["damage", "attackCount", "mpCon", "prop"]:
				assert_eq(fixture.canonical(key, lv, field), book.canonical(key, lv, field), "%s Lv%d %s" % [key, lv, field])
		assert_true(lib.node(String(book.def(key).icon)) != null)
		assert_false(lib.anim(String(book.def(key).effect)).is_empty())
		assert_true(lib.sound(String(book.def(key).sounds.use)) != null)
		if key == "savage_blow":
			assert_false(lib.anim(String(book.def(key).hit)).is_empty())
			assert_true(lib.sound(String(book.def(key).sounds.hit)) != null)
	assert_eq(Array(book.weapon_families("savage_blow")), ["dagger"])
	assert_eq(Array(book.weapon_families("steal")), [])
	assert_eq(Array(lib.missing), [])
	lib.free()

