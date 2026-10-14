extends TestCase
## Tree bosses through the seeded fixed-tick world, including immunity at live impact time.
const TF := preload("res://tests/fixtures/tree_boss_fixtures.gd")
const DT := 1.0 / 60.0
const BF := preload("res://tests/fixtures/basic_attack_fixtures.gd")


func _until(w: RunWorld, t: float) -> void:
	while w.time < t - 1e-6:
		w.step(DT, MoveInput.new())


func _world(id: int = 6220000, skills: Array = [140], attacks: Array = []) -> RunWorld:
	var w := RunWorld.new(TF.setup(id, skills, attacks))
	w.god = true
	_until(w, 1.0)
	w.drain_events()
	return w


func _hit(w: RunWorld, slot: int, amount: float, magic: bool = false) -> void:
	w.hit_mob(slot, {"damage_min": amount, "damage_max": amount, "magic": magic,
		"crit": 0.0, "crit_mult": 1.5, "skill": "energy_bolt" if magic else "three_snails"}, -1)


func test_dyle_weapon_immunity_blocks_instant_physical_but_allows_magic_and_expires() -> void:
	var w := _world()
	var slot := int(w.bosses.records[0].slot)
	_hit(w, slot, 12000)
	_until(w, 30.5)
	assert_false(w.physical_hit_allowed(slot), "canonical skill140/8 starts once interval30 and HP80 gate permit")
	var hp := w.swarm.hp[slot]
	_hit(w, slot, 40)
	assert_eq(w.swarm.hp[slot], hp, "physical impact is blocked")
	_hit(w, slot, 1000, true)
	assert_true(w.swarm.hp[slot] < hp, "magic still damages the immune boss")
	_until(w, 35.5)
	assert_true(w.physical_hit_allowed(slot), "canonical five-second status expires")
	var expired_hp := w.swarm.hp[slot]
	_hit(w, slot, 40)
	assert_eq(w.swarm.hp[slot], expired_hp - 40)


func _shell(w: RunWorld, slot: int, distance: float = 200.0, magic: bool = false) -> void:
	var mk: MobKind = w.mob_kinds[w.swarm.kind[slot]]
	var box := mk.hitbox_at(w.swarm.x[slot], w.swarm.y[slot], w.swarm.facing[slot])
	w.projectiles.spawn({"x": box.position.x - distance, "y": box.get_center().y,
		"vx": 100.0, "vy": 0.0, "range": 1000, "radius": 0,
		"dmg_min": 40, "dmg_max": 40, "magic": magic, "skill": "three_snails"})


func test_shell_immunity_is_checked_at_impact_not_at_launch() -> void:
	var w := _world()
	var slot := int(w.bosses.records[0].slot)
	_hit(w, slot, 12000)
	_until(w, 29.5)
	assert_true(w.physical_hit_allowed(slot))
	_shell(w, slot)
	var hp := w.swarm.hp[slot]
	_until(w, 32.0)
	assert_eq(w.projectiles.active_count(), 0, "blocked shell is consumed by contact")
	assert_eq(w.swarm.hp[slot], hp, "shell launched before immunity lands during it and is blocked")
	_until(w, 34.5)
	assert_false(w.physical_hit_allowed(slot))
	_shell(w, slot)
	_until(w, 37.0)
	assert_eq(w.swarm.hp[slot], hp - 40, "shell launched while immune lands after expiry and damages")


func test_basic_swings_are_blocked_during_immunity_then_resume() -> void:
	var setup := TF.setup()
	var basic := BF.world()
	setup.body_img = basic.setup.body_img
	setup.afterimage_imgs = basic.setup.afterimage_imgs
	setup.equipment_info = basic.setup.equipment_info
	var w := RunWorld.new(setup)
	w.god = true
	_until(w, 1.0)
	var slot := int(w.bosses.records[0].slot)
	_hit(w, slot, 12000)
	_until(w, 30.5)
	w.player.facing = 1 if w.swarm.x[slot] >= w.player.pos.x else -1
	w.drain_events()
	var hp := w.swarm.hp[slot]
	_until(w, 34.5)
	var events := w.drain_events()
	assert_true(events.any(func(e: Dictionary) -> bool: return e.type == "basic_attack"), "real basic swings occur")
	assert_false(events.any(func(e: Dictionary) -> bool: return e.type == "mob_hit" and e.skill == "basic_attack"))
	assert_eq(w.swarm.hp[slot], hp)
	_until(w, 37.0)
	assert_true(w.swarm.hp[slot] < hp, "basic attacks resume once the timed status expires")


func test_dyle_heal_uses_hp90_interval20_and_zero_effect_delay() -> void:
	var w := _world(6220000, [114])
	var slot := int(w.bosses.records[0].slot)
	_until(w, 21.0)
	assert_false(w.drain_events().any(func(e: Dictionary) -> bool: return e.type == "boss_skill"))
	_hit(w, slot, 10000)
	var hp := w.swarm.hp[slot]
	w.drain_events()
	w.step(DT, MoveInput.new())
	var events := w.drain_events()
	var healed := events.filter(func(e: Dictionary) -> bool: return e.type == "mob_healed")
	assert_eq(healed.size(), 1, "canonical effectAfter0 restores on the casting tick")
	if healed.size() == 1:
		assert_between(int(healed[0].amount), 500, 5000)
		assert_eq(w.swarm.hp[slot], hp + int(healed[0].amount))
		assert_eq(healed[0].level, 17)
		assert_near(healed[0].time, w.time, 1e-9)


func test_king_slime_summons_only_below_hp_gate_and_caps_living_owned_slimes() -> void:
	var w := _world(9300003, [200])
	var slot := int(w.bosses.records[0].slot)
	_until(w, 51.0)
	assert_eq(w.mob_skills.summoned_alive(w, 0), 0, "full HP prevents skill200 even after fifty seconds")
	_hit(w, slot, 6000)
	w.step(DT, MoveInput.new())
	assert_eq(w.mob_skills.summoned_alive(w, 0), 3, "canonical level2 list contains three Slimes")
	_until(w, 303.0)
	assert_eq(w.mob_skills.summoned_alive(w, 0), 15, "five casts fill the canonical living limit, sixth is blocked")
	var owned := -1
	for m in w.swarm.capacity():
		if w.swarm.active[m] != 0 and w.mob_summon_owner[m] == 0:
			owned = m
			break
	assert_true(owned >= 0)
	if owned < 0:
		return
	var moved := w.relocate_mob(owned, Vector2(700, 0), 0)
	assert_eq(w.mob_summon_owner[moved], 0)
	assert_eq(w.mob_skills.summoned_alive(w, 0), 15, "relocation preserves encounter ownership")
	_hit(w, moved, 10000, true)
	w.step(DT, MoveInput.new())
	assert_eq(w.mob_skills.summoned_alive(w, 0), 15, "one death permits one new summon, not a whole over-cap list")


func test_king_slime_death_spawns_its_eleven_canonical_revive_slimes_once() -> void:
	var w := _world(9300003, [])
	var slot := int(w.bosses.records[0].slot)
	_hit(w, slot, 100000, true)
	var revives := w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "mob_revives_spawned")
	assert_eq(revives.size(), 1)
	if revives.is_empty():
		return
	assert_eq(revives[0].mob_id, 9300003)
	assert_eq(revives[0].revives.size(), 11, "the v83 revive list has eleven entries, all210100")
	for child: Dictionary in revives[0].revives:
		assert_eq(child.mob_id, 210100)
		assert_eq(w.swarm.max_hp[int(child.mob)], 50, "revived Slimes keep canonical HP")
		assert_eq(w.mob_boss[int(child.mob)], -1, "offspring are not extra scheduled bosses")
	_hit(w, slot, 100000, true)
	assert_false(w.drain_events().any(func(e: Dictionary) -> bool: return e.type == "mob_revives_spawned"))


func _slam_start(w: RunWorld) -> Dictionary:
	for tick in 180:
		w.step(DT, MoveInput.new())
		for e: Dictionary in w.drain_events():
			if e.type == "boss_attack" and e.phase == "start":
				return e
	fail("King Slime should begin its selected slam")
	return {}


func test_king_slime_canonical_900ms_slam_hits_grounded_but_airborne_player_dodges() -> void:
	for jump in [false, true]:
		var w := RunWorld.new(TF.setup(9300003, [], ["attack1"]))
		var start := _slam_start(w)
		if start.is_empty():
			return
		assert_near(float(start.impact_time) - float(start.time), 0.9, 1e-6)
		assert_eq(start.area.size, Vector2(500, 150))
		var hp := int(w.player_state.hp)
		for tick in 35:
			w.step(DT, MoveInput.new())
			assert_eq(int(w.player_state.hp), hp)
		w.step(DT, MoveInput.make(false, false, false, false, jump, jump))
		for tick in 17:
			w.step(DT, MoveInput.make(false, false, false, false, false, jump))
		assert_eq(int(w.player_state.hp), hp, "no hit before900ms")
		w.step(DT, MoveInput.make(false, false, false, false, false, jump))
		var hits := w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "player_hit")
		if jump:
			assert_true(w.player.fh < 0)
			assert_true((start.area as Rect2).intersects(Rect2(w.player.pos + w.body.position, w.body.size), true))
			assert_eq(hits.size(), 0, "airborne dodge is jumpAttack, not leaving the area")
		else:
			assert_eq(hits.size(), 1)
			if hits.size() == 1:
				assert_between(int(hits[0].damage), 220, 272)
				assert_eq(hits[0].source_kind, "attack")


func test_scheduled_king_slime_does_not_flinch_despite_missing_canonical_boss_flag() -> void:
	var w := _world(9300003, [])
	var slot := int(w.bosses.records[0].slot)
	var mk: MobKind = w.mob_kinds[w.swarm.kind[slot]]
	assert_false(mk.boss, "original info/boss remains absent")
	var vx := w.swarm.vx[slot]
	_hit(w, slot, 1000)
	assert_ne(w.swarm.state[slot], MobSwarm.HIT)
	assert_eq(w.swarm.vx[slot], vx, "scheduled boss survivor no-flinch override prevents knockback")


func test_tree_stage_lists_three_bosses_and_loads_their_summon_and_revive_families() -> void:
	var data := DataRepo.load_all()
	var bosses: Array = data.stages.stages.tree_that_grew_1.bosses
	assert_eq(bosses.map(func(e: Dictionary) -> int: return int(e.mob_id)), [3220000, 9300003, 6220000])
	assert_eq(bosses.map(func(e: Dictionary) -> int: return int(e.time)), [300, 600, 900])
	var ids := DataRepo.stage_mob_ids(data, "tree_that_grew_1")
	assert_true(ids.has(9300003) and ids.has(6220000) and ids.has(210100))


func test_immunity_and_encounter_identity_follow_relocation_but_not_pool_reuse() -> void:
	var w := _world()
	var slot := int(w.bosses.records[0].slot)
	_hit(w, slot, 12000)
	_until(w, 30.5)
	var moved := w.relocate_mob(slot, Vector2(600, 0), 0)
	assert_eq(w.mob_boss[moved], 0)
	assert_false(w.physical_hit_allowed(moved), "live status follows a relocated boss")
	_shell(w, moved, 0, true)
	var hp := w.swarm.hp[moved]
	w.step(DT, MoveInput.new())
	assert_true(w.swarm.hp[moved] < hp, "magic projectile also works during weapon immunity")
	_hit(w, moved, 100000, true)
	w.swarm.despawn(moved)
	var reused := w.spawn_mob(int(w.kind_of_id[210100]), Vector2(600, 0), 0, 1.0, false)
	assert_eq(reused, moved, "exercise actual free-list reuse")
	assert_eq(w.mob_boss[reused], -1)
	assert_eq(w.mob_summon_owner[reused], -1)
	assert_true(w.physical_hit_allowed(reused), "new occupant has no inherited immunity")

