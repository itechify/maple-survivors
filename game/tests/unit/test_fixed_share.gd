extends TestCase
## Fixed-share hits through synthetic seeded worlds; no cache or Snipe definition required (MS3 #363).

const CF := preload("res://tests/fixtures/combat_mechanics_fixtures.gd")
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const BLOCK := {"share": [0.2, 0.45], "cap_mult": 20.0, "boss": {"share_scale": 0.1, "cap_mult": 6.0}}
const DT := 1.0 / 60.0


func _world(extra := {}) -> RunWorld:
	var def := {"damage": "physical", "fixed_share": BLOCK, "cast": {"rule": "nearest", "prefer": "max_hp"}}
	def.merge(extra, true)
	return CF.world(def)


func _mob(w: RunWorld, x := 400.0, hp := 1000) -> int:
	var m := RF.put_mob(w, 1110100, x, 190)
	w.swarm.max_hp[m] = hp
	w.swarm.hp[m] = hp
	w.swarm.alpha[m] = 1.0
	return m


func _hits(w: RunWorld) -> Array:
	return w.events.filter(func(e: Dictionary) -> bool: return e.type == "mob_hit")


func test_fixed_hit_uses_hp_share_without_rng_crit_defence_or_element() -> void:
	var w := _world()
	var twin := _world()
	var m := _mob(w)
	_mob(twin)
	var st := w.loadout.stats("synthetic")
	st.damage_min = 10000.0
	st.damage_max = 10000.0
	st.crit = 100.0
	st.damage_pct = 99.0
	st.element = "F"
	w.swarm.mob_kind(m).elements["F"] = 0.0
	st.fixed_share = {"share": 0.2, "cap": 2000.0, "boss": {"share_scale": 0.1, "cap": 600.0}, "damage_mult": 1.0}
	w.swarm.mob_kind(m).pdd = 999999
	w.hit_mob(m, st, -1)
	assert_eq(w.swarm.hp[m], 800)
	assert_eq(_hits(w)[0].damage, 200)
	assert_false(_hits(w)[0].crit)
	assert_eq(_hits(w)[0].skill, "synthetic")
	assert_eq(w.rng.randi(), twin.rng.randi(), "fixed hit consumes no combat draw")


func test_resolved_share_rank_caps_and_damage_modifiers_use_unmodified_physical_bounds() -> void:
	var w := _world()
	w.loadout.weapon_id = 1462001
	w.loadout.str_stat = 10
	w.loadout.dex_stat = 100
	w.loadout.watk = 50
	var st := w.loadout.stats("synthetic")
	assert_true(st.has("fixed_share"))
	if not st.has("fixed_share"):
		return
	assert_near(st.fixed_share.share, 0.2)
	assert_near(st.fixed_share.cap, (st.damage_min + st.damage_max) * 10.0)
	var cap: float = st.fixed_share.cap
	w.loadout.set_rank("synthetic", 2)
	assert_near(w.loadout.stats("synthetic").fixed_share.share, 0.45)
	w.loadout.add_skill_mod("synthetic", "damage", "mul", 1.2)
	st = w.loadout.stats("synthetic")
	assert_near(st.fixed_share.cap, cap, 0.01, "rarity multiplies the capped amount, not the cap")
	assert_near(st.fixed_share.damage_mult, 1.2)
	w.loadout.watk = 100
	assert_near(w.loadout.stats("synthetic").fixed_share.cap, cap * 2.0, 0.01)
	var plain := CF.world({"damage": "physical", "cast": {"rule": "nearest", "prefer": "max_hp"}})
	var with_block := _world().loadout.stats("synthetic")
	with_block.erase("fixed_share")
	assert_eq(var_to_bytes(plain.loadout.stats("synthetic")), var_to_bytes(with_block),
		"the optional block adds only its resolved key; all other stats retain their bytes")



func test_prefer_max_hp_selects_distinct_nonbosses_then_bosses_by_hp_distance_slot() -> void:
	var w := _world({"count": 6})
	var near := _mob(w, 250, 1000)
	var strong := _mob(w, 450, 2000)
	var tie := _mob(w, 450, 2000)
	var far := _mob(w, 500, 2000)
	var boss := _mob(w, 300, 99999)
	w.swarm.steady[boss] = 1
	var canonical := RF.put_mob(w, 2220000, 400, 190)
	w.swarm.max_hp[canonical] = 100000
	w.swarm.hp[canonical] = 100000
	_mob(w, 2000, 999999)
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	var st := w.runner.stats_of(w, "synthetic")
	assert_near(SkillRunner.reach_of(st, w), 600.0)
	assert_true(w.runner.has_target(w, "synthetic", st, w.player.pos))
	w.drain_events()
	w.runner.step(DT, w)
	assert_eq(_hits(w).map(func(e: Dictionary) -> int: return int(e.mob)), [strong, tie, far, near, canonical, boss])
	for slot: int in [strong, tie, far, near]:
		w.swarm.active[slot] = 0
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	var fallback := w.runner.prepare_cast(w, "synthetic", st, w.player.pos)
	assert_eq(fallback.targets, PackedInt32Array([canonical, boss]), "boss fallback when only bosses remain")
	assert_eq(var_to_bytes(w.runner.prepare_cast(w, "synthetic", st, w.player.pos)), var_to_bytes(fallback),
		"repeat admission is deterministic")
	w.loadout.add_skill_mod("synthetic", "range", "mul", 0.001)
	st = w.runner.stats_of(w, "synthetic")
	assert_false(w.runner.has_target(w, "synthetic", st, w.player.pos))


func test_preview_rank_card_and_cosmetic_bolt_use_the_resolved_fixed_share() -> void:
	var w := _world({"ball": "Skill.wz/999.img/skill/9991000/ball"})
	var text := SkillText.new(w.book)
	var st := w.loadout.stats("synthetic")
	assert_eq(text.level_line("synthetic", 1, st), "Deals 20% of a monster's max HP (up to 20x your damage); bosses 2% (up to 6x)")
	var cards := text.dress([{"kind": "skill_rank", "skill": "synthetic", "magnitude": 1}], w.loadout)
	assert_true(String(cards[0].desc).contains("Deals 45%"))
	var m := _mob(w)
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	w.drain_events()
	w.runner.step(DT, w)
	assert_eq(_hits(w).size(), 1, "damage at the cast")
	var bolts := w.events.filter(func(e: Dictionary) -> bool: return e.type == "ammo_shot")
	assert_eq(bolts.size(), 1)
	if not bolts.is_empty():
		assert_eq(bolts[0].ball, st.ball)
		assert_eq(bolts[0].to, w.mob_center(m))
	assert_eq(w.projectiles.active_count(), 0, "cosmetic bolt has no damage projectile")


func test_amount_floor_cap_boss_formula_and_minimum_are_exact() -> void:
	var st := FixedShare.resolve(BLOCK, 1, Vector2(80, 120), 1.0)
	assert_eq(FixedShare.amount(1001, false, st), 200)
	assert_eq(FixedShare.amount(100000, false, st), 2000)
	assert_eq(FixedShare.amount(1001, true, st), 20)
	assert_eq(FixedShare.amount(100000, true, st), 600)
	assert_eq(FixedShare.amount(1, false, st), 1)
	assert_eq(FixedShare.amount(1, true, st), 1)
	st = FixedShare.resolve(BLOCK, 2, Vector2(80, 120), 1.2)
	assert_eq(FixedShare.amount(1000, false, st), 540)
	assert_eq(FixedShare.amount(100000, false, st), 2400)
	assert_eq(FixedShare.amount(1000, true, st), 54)
	assert_eq(FixedShare.amount(100000, true, st), 720)


func test_canonical_and_scheduled_boss_hits_use_the_boss_cap() -> void:
	var w := _world()
	var st := w.loadout.stats("synthetic")
	st.fixed_share = FixedShare.resolve(BLOCK, 1, Vector2(80, 120), 1.0)
	for scheduled: bool in [false, true]:
		var m := RF.put_mob(w, 1110100 if scheduled else 2220000, 400, 190, 100)
		w.swarm.steady[m] = 1 if scheduled else 0
		w.swarm.max_hp[m] = 100000
		w.swarm.hp[m] = 100000
		w.hit_mob(m, st, -1)
		assert_eq(w.swarm.hp[m], 99400)


func test_immunity_and_dead_slots_reject_fixed_hits_and_keep_rng() -> void:
	var fixture := preload("res://tests/fixtures/tree_boss_fixtures.gd")
	var w := RunWorld.new(fixture.setup())
	w.god = true
	for tick in 60:
		w.step(DT, MoveInput.new())
	var m := int(w.bosses.records[0].slot)
	var st := _world().loadout.stats("synthetic")
	st.skill = "energy_bolt"
	st.fixed_share = FixedShare.resolve(BLOCK, 1, Vector2(10000, 10000), 1.0)
	w.hit_mob(m, st, -1) # Cross the boss's HP80 immunity gate with repeated fixed hits.
	for hit in 12:
		w.hit_mob(m, st, -1)
	while w.time < 30.5:
		w.step(DT, MoveInput.new())
	assert_false(w.physical_hit_allowed(m))
	w.drain_events()
	var state := w.rng.state
	var hp := w.swarm.hp[m]
	w.hit_mob(m, st, -1)
	assert_eq(w.swarm.hp[m], hp)
	assert_true(_hits(w).is_empty())
	assert_eq(w.rng.state, state)
	w.mob_skills.reset_slot(m)
	w.swarm.active[m] = 0
	w.hit_mob(m, st, -1)
	assert_true(_hits(w).is_empty())



func test_fixed_hits_keep_on_hit_meter_kill_loot_and_damage_credit() -> void:
	var w := _world({"on_hit": {"status": "stun", "chance_field": "prop", "duration_field": "time"}})
	var m := _mob(w)
	var st := w.loadout.stats("synthetic")
	st.fixed_share = FixedShare.resolve(BLOCK, 1, Vector2(80, 120), 1.0)
	st.meter_receipt = {"landed": false}
	w.meter = PlayerMeter.new({"id": "test", "max": 10, "gain": {"event": "cast_landed", "amount": 1}})
	w.drain_events()
	w.hit_mob(m, st, -1)
	assert_near(w.swarm.status_time(m, MobSwarm.STUN), 3.0)
	assert_eq(w.meter.value, 1)
	assert_eq(w.damage_dealt, 200)
	w.swarm.hp[m] = 1
	w.hit_mob(m, st, -1)
	assert_eq(w.meter.value, 1, "one unit per cast receipt")
	assert_eq(w.kills, 1)
	assert_eq(w.damage_dealt, 400, "same whole-hit credit as ordinary instant hits")
	assert_true(w.events.any(func(e: Dictionary) -> bool: return e.type == "mob_died"))
	assert_true(w.pickups.active_count() > 0, "ordinary kill loot")
