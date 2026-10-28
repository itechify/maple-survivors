extends TestCase


## Canonical Mano timers, areas and status effects through the public seeded RunWorld seam.
const MF := preload("res://tests/fixtures/mano_fixtures.gd")
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0


func _ticks(w: RunWorld, n: int) -> void:
	for tick in n:
		w.step(DT, MoveInput.new())


func _skills(w: RunWorld) -> Array:
	return w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "boss_skill")


func test_slow_waits_fifteen_seconds_retains_eighty_percent_and_expires() -> void:
	var w := MF.world()
	_ticks(w, 899)
	assert_eq(_skills(w).size(), 0, "no cast before canonical interval")
	assert_eq(w.player.speed_stat, 100)
	_ticks(w, 1)
	var cast := _skills(w)
	assert_eq(cast.size(), 1, "slow casts at fifteen seconds after spawn")
	assert_eq(w.player.speed_stat, 80, "tier C x80 retains eighty percent speed")
	if not cast.is_empty():
		assert_eq(cast[0].skill_id, 126)
		assert_eq(cast[0].level, 7)
		assert_eq(cast[0].action, "skill1")
		assert_near(float(cast[0].duration), 15.0, 0.000001)
	w.swarm.despawn(int(w.bosses.records[0].slot))
	_ticks(w, 899)
	assert_eq(w.player.speed_stat, 80)
	_ticks(w, 1)
	assert_eq(w.player.speed_stat, 100, "canonical fifteen-second slow expires without a recast")



func test_slow_respects_canonical_area_and_composes_with_speed_upgrades() -> void:
	for sample: Array in [[Vector2(-299, 0), true], [Vector2(299, 0), true], [Vector2(-301, 0), false], [Vector2(301, 0), false], [Vector2(0, -119), true], [Vector2(0, -121), false]]:
		var w := MF.world()
		_ticks(w, 899)
		w.player.place(Vector2(600, 200) + sample[0], w.fhm)
		_ticks(w, 1)
		assert_eq(w.player.speed_stat, 80 if sample[1] else 100, "slow canonical area at %s" % sample[0])
	var w := MF.world()
	w.loadout.add_player_mod("speed", "add", 25)
	w.refresh_player_stats()
	_ticks(w, 900)
	assert_eq(w.player.speed_stat, 100, "125 upgraded speed times retained 80%")
	w.loadout.add_player_mod("speed", "add", 10)
	w.refresh_player_stats()
	assert_eq(w.player.speed_stat, 108, "refreshing stats preserves the timed slow (135 x 80%)")
	w.loadout.add_player_mod("speed", "add", 25)
	w.refresh_player_stats()
	assert_eq(w.player.speed_stat, 112, "the slow applies after the v83 speed cap (160 -> 140, x 80%)")



func test_ready_skills_wait_for_hp_gate_then_fire_on_the_first_eligible_tick() -> void:
	for id in [126, 112, 113]:
		var setup := MF.setup([id])
		setup.mob_skill_img[str(id)].level[str(MF.LEVELS[id])].hp = 50.0 # Synthetic gate case; Mano's real slow omits hp => 100%.
		setup.data.jobs_survivor.jobs["212"]["start_skills"] = [] # no auto-cast may touch the boss's HP (#284 + #285)
		var w := RunWorld.new(setup)
		w.god = true
		RF.place_player(w, 400)
		w.step(DT, MoveInput.new())
		var slot := int(w.bosses.records[0].slot)
		w.relocate_mob(slot, Vector2(600, 200), w.fhm.find_below(600, 190))
		_ticks(w, 960)
		assert_eq(_skills(w).size(), 0, "full health fails the canonical hp% gate even after cooldown")
		w.hit_mob(slot, {"damage_min":999.0, "damage_max":999.0, "magic":false, "crit":0.0, "crit_mult":1.0, "skill":"probe"}, -1)
		_ticks(w, 1)
		assert_eq(_skills(w).size(), 0, "50.05% health remains above the gate")
		w.hit_mob(slot, {"damage_min":1.0, "damage_max":1.0, "magic":false, "crit":0.0, "crit_mult":1.0, "skill":"probe"}, -1)
		_ticks(w, 1)
		assert_eq(_skills(w).size(), 1, "exactly 50% health allows the already-ready skill")



func _hurt_to_summon_gate(w: RunWorld) -> int:
	var slot := int(w.bosses.records[0].slot)
	w.hit_mob(slot, {"damage_min":200.0, "damage_max":200.0, "magic":false, "crit":0.0, "crit_mult":1.0, "skill":"probe"}, -1)
	return slot


func _summon_spawns(w: RunWorld) -> Array:
	return w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "mob_spawned" and e.mob_id != 2220000)


func test_summon_interval_hp_gate_and_exact_two_of_each_canonical_snail() -> void:
	var w := MF.world([200])
	_ticks(w, 600)
	assert_eq(_summon_spawns(w).size(), 0, "summon requires at most 90% HP")
	_hurt_to_summon_gate(w)
	_ticks(w, 1)
	var first := _summon_spawns(w)
	assert_eq(first.size(), 6, "ready summon fires on first eligible tick")
	var counts := {}
	for e: Dictionary in first:
		counts[e.mob_id] = int(counts.get(e.mob_id, 0)) + 1
	assert_eq(counts, {100100:2, 100101:2, 130101:2}, "canonical ordered summon list")
	_ticks(w, 599)
	assert_eq(_summon_spawns(w).size(), 0, "no summon before the ten-second interval")
	_ticks(w, 1)
	assert_eq(_summon_spawns(w).size(), 6, "a second list at exactly ten seconds")


func test_summon_limit_survives_relocation_and_ordinary_slot_reuse() -> void:
	var w := MF.world([200])
	# The 212 start skills cast freely without MP (#284 + #285) and would kill the summons: this test is about the cap.
	w.loadout.order.clear()
	w.loadout.version += 1
	_hurt_to_summon_gate(w)
	var summoned: Array = []
	for wave in 5:
		_ticks(w, 600)
		summoned.append_array(_summon_spawns(w))
	assert_eq(summoned.size(), 30, "five lists reach the canonical 30 summoned alive")
	if summoned.size() != 30:
		return
	for e: Dictionary in summoned:
		w.relocate_mob(int(e.mob), Vector2(700, 200), w.fhm.find_below(700, 190))
	w.drain_events()
	_ticks(w, 600)
	assert_eq(_summon_spawns(w).size(), 0, "ordinary relocation cannot lose summon ownership and bypass the cap")
	var freed := int(summoned[0].mob)
	w.swarm.despawn(freed)
	var ordinary := w.spawn_mob(int(w.kind_of_id[100100]), Vector2(750, 200), w.fhm.find_below(750, 190), 1.0, false)
	assert_eq(ordinary, freed, "fixture exercises immediate slot reuse")
	w.drain_events()
	_ticks(w, 1)
	assert_eq(_summon_spawns(w).size(), 1, "one free summon place remains despite an ordinary mob reusing the slot")
	_ticks(w, 600)
	assert_eq(_summon_spawns(w).size(), 0, "the replenished owned summon restores the limit")



func test_defense_skills_wait_ten_seconds_buff_their_area_and_expire_at_thirty() -> void:
	for id in [112, 113]:
		var w := MF.world([id])
		var source := int(w.bosses.records[0].slot)
		var near := w.spawn_mob(int(w.kind_of_id[2220000]), Vector2(850, 200), w.fhm.find_below(850, 190), 100, false)
		var outside := w.spawn_mob(int(w.kind_of_id[2220000]), Vector2(950, 200), w.fhm.find_below(950, 190), 100, false)
		var magic: bool = id == 113
		var canonical := 30.0 if magic else 20.0
		_ticks(w, 599)
		assert_eq(w.mob_defense(source, magic), canonical, "not before the canonical interval")
		assert_eq(_skills(w).size(), 0)
		_ticks(w, 1)
		assert_eq(_skills(w).size(), 1, "defense skill starts at ten seconds")
		assert_eq(w.mob_defense(source, magic), canonical+85, "tier C canonical x85 adds defense")
		assert_eq(w.mob_defense(near, magic), canonical+85, "nearby mob inside the canonical area is buffed")
		assert_eq(w.mob_defense(outside, magic), canonical, "mob outside canonical area is unaffected")
		assert_eq(w.mob_kinds[int(w.kind_of_id[2220000])].mdd, 30, "immutable canonical kind MDD")
		assert_eq(w.mob_kinds[int(w.kind_of_id[2220000])].pdd, 20, "immutable canonical kind PDD")
		w.swarm.despawn(source)
		_ticks(w, 1799)
		assert_eq(w.mob_defense(near, magic), canonical+85, "still active before thirty seconds")
		_ticks(w, 1)
		assert_eq(w.mob_defense(near, magic), canonical, "expires at exactly canonical thirty seconds")


func _magic_hit(w: RunWorld, slot: int, projectile: bool) -> int:
	w.drain_events()
	if projectile:
		w.projectiles.spawn({"x":w.swarm.x[slot]-100, "y":w.swarm.y[slot]-20, "vx":600.0, "vy":0.0,
			"range":200.0, "radius":10.0, "dmg_min":100.0, "dmg_max":100.0, "magic":true, "skill":"probe"})
		_ticks(w, 20)
	else:
		w.hit_mob(slot, {"damage_min":100.0, "damage_max":100.0, "magic":true, "crit":0.0, "crit_mult":1.0, "skill":"probe"}, -1)
	var hits := w.drain_events().filter(func(e:Dictionary)->bool:return e.type == "mob_hit" and e.skill == "probe")
	assert_eq(hits.size(), 1, "one test magic hit landed")
	return int(hits[0].damage) if not hits.is_empty() else 0


func test_magic_defense_changes_both_instant_and_in_flight_projectile_damage() -> void:
	for projectile in [false, true]:
		var w := MF.world([113])
		var slot := int(w.bosses.records[0].slot)
		assert_eq(_magic_hit(w, slot, projectile), 83, "100 raw magic against canonical MDD30")
		while w.time < 10.0:
			_ticks(w, 1)
		_ticks(w, 1)
		assert_eq(_magic_hit(w, slot, projectile), 57, "100 raw magic against active MDD115 on either hit path")


func test_weapon_defense_reduces_physical_hits_without_mutating_weapon_or_mob_stats() -> void:
	var setup := MF.setup([112])
	var basic_setup: Dictionary = preload("res://tests/fixtures/basic_attack_fixtures.gd").world().setup
	setup.equipment_info = basic_setup.equipment_info
	var w := RunWorld.new(setup)
	w.god = true
	RF.place_player(w, 400)
	w.player.facing = 1
	w.loadout.add_player_mod("str", "add", 100.0)
	w.refresh_player_stats()
	_ticks(w, 1)
	var slot := int(w.bosses.records[0].slot)
	w.relocate_mob(slot, Vector2(450, 200), w.fhm.find_below(450, 190))
	# The held Sword's physical swing line (#284 removed the basic attack that used to land it), struck every 30 ticks.
	var lo := w.loadout
	var swing := CombatMath.physical_damage_range(lo.str_stat, lo.dex_stat, lo.luk_stat, w.weapon_attack(false),
		w.weapon_id(), "swing", lo.job_id, lo.mastery)
	var line := {"skill": "probe", "damage_type": "physical", "magic": false, "damage_min": swing.x,
		"damage_max": swing.y, "damage_pct": 1.0, "player_level": lo.char_level, "crit": 0.0, "crit_mult": 1.5}
	var before := []
	var after := []
	for tick in 60*15:
		if tick % 30 == 0 and w.swarm.active[slot] != 0:
			w.hit_mob(slot, line, -1)
		w.step(DT, MoveInput.new())
		for e: Dictionary in w.drain_events():
			if e.type == "mob_hit" and e.skill == "probe":
				(before if w.time < 10 else after).append(int(e.damage))
	assert_true(before.size() >= 10 and after.size() >= 5, "physical hits landed on both sides of the buff")
	if before.is_empty() or after.is_empty():
		return
	assert_true(before.max() > 40, "known STR112 Sword can hit above 40 before PDD buff")
	# Sword max (4 x 112 STR + 5 DEX) x 17 W.Att / 100 = 77.0, minus 0.5 x 105 PDD = 24.5. No level-gap factor (#285).
	assert_true(after.max() <= 25, "active PDD105 lowers the known physical maximum to 24.5 (got %d)" % after.max())
	assert_eq(w.weapon_info().incPAD, 17.0)
	assert_eq(w.mob_kinds[int(w.kind_of_id[2220000])].pdd, 20)



func test_defense_status_moves_with_relocation_and_clears_when_a_slot_is_reused() -> void:
	var w := MF.world([113])
	_ticks(w, 600)
	var source := int(w.bosses.records[0].slot)
	assert_eq(w.mob_defense(source, true), 115.0)
	var moved := w.relocate_mob(source, Vector2(800, 200), w.fhm.find_below(800, 190))
	assert_eq(w.mob_defense(moved, true), 115.0, "live timed defense follows relocation")
	w.swarm.despawn(moved)
	var fresh := w.spawn_mob(int(w.kind_of_id[2220000]), Vector2(800, 200), w.fhm.find_below(800, 190), 1.0, false)
	assert_eq(fresh, moved, "fixture exercises the previously buffed slot")
	assert_eq(w.mob_defense(fresh, true), 30.0, "new occupant gets only its canonical defense")


func test_hp_ready_skill_waits_until_relocation_regen_is_fully_visible() -> void:
	var w := MF.world([200])
	_ticks(w, 600)
	var source := _hurt_to_summon_gate(w)
	w.relocate_mob(source, Vector2(600, 200), w.fhm.find_below(600, 190))
	w.drain_events()
	_ticks(w, 17)
	assert_eq(_skills(w).size(), 0, "a ready boss skill is harmless during respawn fade")
	_ticks(w, 1)
	assert_eq(_skills(w).size(), 1, "it fires once the canonical survivor regen fade completes")



func test_projectile_launched_before_magic_defense_cast_uses_defense_at_impact() -> void:
	var w := MF.world([113])
	var slot := int(w.bosses.records[0].slot)
	_ticks(w, 599)
	assert_eq(w.mob_defense(slot, true), 30.0)
	assert_eq(_magic_hit(w, slot, true), 57, "already launched projectile reads the new buff at its later impact")
