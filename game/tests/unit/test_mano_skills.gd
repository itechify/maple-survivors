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
	for sample: Array in [[Vector2(-299,0),true], [Vector2(299,0),true], [Vector2(-301,0),false], [Vector2(301,0),false], [Vector2(0,-119),true], [Vector2(0,-121),false]]:
		var w := MF.world()
		_ticks(w,899)
		w.player.place(Vector2(600,200) + sample[0],w.fhm)
		_ticks(w,1)
		assert_eq(w.player.speed_stat,80 if sample[1] else 100,"slow canonical area at %s" % sample[0])
	var w := MF.world()
	w.loadout.add_player_mod("speed","add",25)
	w.refresh_player_stats()
	_ticks(w,900)
	assert_eq(w.player.speed_stat,100,"125 upgraded speed times retained 80%")
	w.loadout.add_player_mod("speed","add",25)
	w.refresh_player_stats()
	assert_eq(w.player.speed_stat,120,"refreshing stats preserves the timed slow")

func test_ready_slow_waits_for_its_hp_gate_then_fires_on_the_first_eligible_tick() -> void:
	var setup := MF.setup()
	setup.mob_skill_img["126"].level["7"].hp = 50.0 # Synthetic gate case; Mano's real slow omits hp => 100%.
	var w := RunWorld.new(setup)
	w.god = true
	RF.place_player(w,400)
	w.step(DT,MoveInput.new())
	var slot := int(w.bosses.records[0].slot)
	w.relocate_mob(slot,Vector2(600,200),w.fhm.find_below(600,190))
	_ticks(w,960)
	assert_eq(_skills(w).size(),0,"full health fails the canonical hp% gate even after cooldown")
	w.hit_mob(slot,{"damage_min":999.0,"damage_max":999.0,"magic":false,"crit":0.0,"crit_mult":1.0,"skill":"probe"},-1)
	_ticks(w,1)
	assert_eq(_skills(w).size(),0,"50.05% health remains above the gate")
	w.hit_mob(slot,{"damage_min":1.0,"damage_max":1.0,"magic":false,"crit":0.0,"crit_mult":1.0,"skill":"probe"},-1)
	_ticks(w,1)
	assert_eq(_skills(w).size(),1,"exactly 50% health allows the already-ready skill")

func _hurt_to_summon_gate(w: RunWorld) -> int:
	var slot := int(w.bosses.records[0].slot)
	w.hit_mob(slot,{"damage_min":200.0,"damage_max":200.0,"magic":false,"crit":0.0,"crit_mult":1.0,"skill":"probe"},-1)
	return slot
func _summon_spawns(w: RunWorld) -> Array:
	return w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "mob_spawned" and e.mob_id != 2220000)
func test_summon_interval_hp_gate_and_exact_two_of_each_canonical_snail() -> void:
	var w := MF.world([200])
	_ticks(w,600)
	assert_eq(_summon_spawns(w).size(),0,"summon requires at most 90% HP")
	_hurt_to_summon_gate(w)
	_ticks(w,1)
	var first := _summon_spawns(w)
	assert_eq(first.size(),6,"ready summon fires on first eligible tick")
	var counts := {}
	for e: Dictionary in first:
		counts[e.mob_id] = int(counts.get(e.mob_id,0)) + 1
	assert_eq(counts,{100100:2,100101:2,130101:2},"canonical ordered summon list")
	_ticks(w,599)
	assert_eq(_summon_spawns(w).size(),0,"no summon before the ten-second interval")
	_ticks(w,1)
	assert_eq(_summon_spawns(w).size(),6,"a second list at exactly ten seconds")
func test_summon_limit_survives_relocation_and_ordinary_slot_reuse() -> void:
	var w := MF.world([200])
	_hurt_to_summon_gate(w)
	var summoned: Array = []
	for wave in 5:
		_ticks(w,600)
		summoned.append_array(_summon_spawns(w))
	assert_eq(summoned.size(),30,"five lists reach the canonical 30 summoned alive")
	if summoned.size() != 30:
		return
	for e: Dictionary in summoned:
		w.relocate_mob(int(e.mob),Vector2(700,200),w.fhm.find_below(700,190))
	w.drain_events()
	_ticks(w,600)
	assert_eq(_summon_spawns(w).size(),0,"ordinary relocation cannot lose summon ownership and bypass the cap")
	var freed := int(summoned[0].mob)
	w.swarm.despawn(freed)
	var ordinary := w.spawn_mob(int(w.kind_of_id[100100]),Vector2(750,200),w.fhm.find_below(750,190),1.0,false)
	assert_eq(ordinary,freed,"fixture exercises immediate slot reuse")
	w.drain_events()
	_ticks(w,1)
	assert_eq(_summon_spawns(w).size(),1,"one free summon place remains despite an ordinary mob reusing the slot")
	_ticks(w,600)
	assert_eq(_summon_spawns(w).size(),0,"the replenished owned summon restores the limit")
