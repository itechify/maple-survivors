extends TestCase
## Dark Sight (#211): shipping skill data through seeded RunWorld ticks, cards and public player state.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const MF := preload("res://tests/fixtures/mob_attack_fixtures.gd")
const BF := preload("res://tests/fixtures/boss_attack_fixtures.gd")
const DT := 1.0 / 60.0
const KEY := "dark_sight"


func _world(hp_fraction := 0.25, mob_dx := 100.0, rank := 1, seed_value := 211) -> RunWorld:
	var data := RF.quiet_data()
	data.balance.player.hp = 1000
	data.balance.player.mp = 500
	data.balance.regen.hp = 0
	data.balance.regen.mp = 0
	data.balance.magnet_radius = 0
	var setup := RF.with_basic_attack(RF.setup("quiet", seed_value, data))
	setup["job"] = 400 # a Thief with no start skills (#284)
	var w := RunWorld.new(setup)
	RF.place_player(w, 400)
	w.player.facing = 1
	assert_true(w.learn_skill(KEY))
	w.loadout.set_rank(KEY, rank)
	w.heal_fraction("hp", -1.0)
	w.heal_fraction("hp", hp_fraction)
	if mob_dx != 0.0:
		w.mob_kinds[int(w.kind_of_id[100100])].move_speed = 0.0
		var m := RF.put_mob(w, 100100, 400.0 + mob_dx, 190.0, 1000000.0)
		w.swarm.alpha[m] = 1.0
	w.drain_events()
	return w


func _run(w: RunWorld, ticks: int) -> Array:
	var events: Array = []
	for i in ticks:
		w.step(DT, MoveInput.new())
		events.append_array(w.drain_events())
	return events


func _of(events: Array, type: String) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return e.type == type)


func test_cast_requires_low_hp_nearby_mob_and_affordable_mp() -> void:
	for hp: float in [1.0, 0.6, 0.3]:
		var w := _world(hp)
		assert_true(_of(_run(w, 30), "buff_cast").is_empty(), "no cast at or above 30% HP")
	for dx: float in [0.0, 300.0]:
		var w := _world(0.29, dx)
		assert_true(_of(_run(w, 30), "buff_cast").is_empty(), "needs a mob inside Oak Barrel's reach")
	for dx: float in [-240.0, 240.0]:
		var w := _world(0.29, dx)
		assert_eq(_of(_run(w, 1), "buff_cast").size(), 1)
		assert_true(w.is_hidden())
		assert_eq(int(w.player_state.mp), 476, "rank 1 pays 24 MP once")
	var empty := _world()
	empty.heal_fraction("mp", -1.0)
	assert_true(_of(_run(empty, 30), "buff_cast").is_empty())
	assert_false(empty.is_hidden())


func test_recovery_ends_hidden_but_cooldown_still_counts_thirty_seconds_from_cast() -> void:
	var w := _world()
	_run(w, 1)
	w.heal_fraction("hp", 0.35)
	_run(w, 1)
	assert_true(w.is_hidden(), "exactly 60% HP keeps Hidden")
	w.heal_fraction("hp", 0.01)
	assert_eq(_of(_run(w, 1), "buff_expired").size(), 1)
	assert_false(w.is_hidden(), "above 60% HP ends it")
	w.heal_fraction("hp", -0.36)
	assert_true(_of(_run(w, 60 * 29), "buff_cast").is_empty(), "early recovery must not reset the cooldown")
	assert_eq(_of(_run(w, 60 * 2), "buff_cast").size(), 1, "ready again 30 seconds from the original cast")
	assert_eq(int(w.player_state.mp), 452)
	var long_buff := _world(0.25, 100.0, 20)
	assert_eq(_of(_run(long_buff, 1), "buff_cast").size(), 1)
	assert_near(float(long_buff.skill_readiness(KEY).total), 30.0)
	assert_true(_of(_run(long_buff, 60 * 31), "buff_cast").is_empty(), "an active 200-second buff blocks recasts")
	assert_true(long_buff.is_hidden())


func test_learn_and_rank_cards_are_on_the_thief_line_with_any_weapon() -> void:
	var w := RF.quiet_world(400.0, 211)
	for job in [0, 100, 200, 212, 400, 410, 420, 500, 510]:
		w.progression.job_id = job
		assert_eq("dark_sight_new" in w.upgrades.eligible(w), job in [400, 410, 420], "job %d" % job)
	w.progression.job_id = 400
	assert_eq(w.upgrades.apply("dark_sight_new", w), 1)
	assert_true(w.loadout.has(KEY))
	assert_false("dark_sight_new" in w.upgrades.eligible(w))
	assert_has(w.upgrades.eligible(w), "dark_sight_rank")
	assert_eq(w.upgrades.apply("dark_sight_rank", w), 1)
	assert_eq(w.loadout.rank(KEY), 2)
	w.loadout.set_rank(KEY, 20)
	assert_false("dark_sight_rank" in w.upgrades.eligible(w))


func test_canonical_speed_duration_and_cost_at_every_rank_and_no_failure_roll() -> void:
	var w := _world()
	var speed := [-30, -28, -26, -24, -22, -20, -18, -16, -14, -12, -10, -8, -7, -6, -5, -4, -3, -2, -1, 0]
	for rank in range(1, 21):
		var st := w.loadout.stats(KEY, rank)
		assert_eq(int(st.mp_cost), 25 - rank)
		assert_near(float(st.duration), float(rank * 10))
		assert_near(float(st.buff_effects.speed), float(speed[rank - 1]))
		assert_near(float(st.fail_chance), 0.0)
		assert_near(float(st.buff_cooldown), 30.0)
	for rank in [1, 12, 13, 20]:
		var ranked := _world(0.25, 100.0, rank)
		var before := ranked.player_speed_stat()
		var thief_state := ranked.thief_rng.state
		var pirate_state := ranked.pirate_rng.state
		var events := _run(ranked, 1)
		assert_eq(_of(events, "buff_cast").size(), 1)
		assert_true(_of(events, "buff_failed").is_empty())
		assert_near(ranked.player_speed_stat(), before + speed[rank - 1])
		assert_eq(ranked.player.speed_stat, int(before) + speed[rank - 1])
		assert_eq(ranked.thief_rng.state, thief_state, "no Thief failure roll")
		assert_eq(ranked.pirate_rng.state, pirate_state, "no Oak Barrel failure roll")
	_run(w, 595)
	assert_true(w.is_hidden(), "rank 1 lasts 10 seconds")
	_run(w, 10)
	assert_false(w.is_hidden())
	assert_near(w.player_speed_stat(), 100.0, 1e-6, "the speed penalty ends with Hidden")
	var text := SkillText.new(w.book)
	assert_eq(text.level_line(KEY, 1, w.loadout.stats(KEY, 1)),
		"MP -24; Hidden for 10 sec.; Speed -30; 30 sec. between uses")
	assert_eq(text.level_line(KEY, 20, w.loadout.stats(KEY, 20)),
		"MP -5; Hidden for 200 sec.; Speed 0; 30 sec. between uses")


func test_dark_sight_blocks_contact_and_skill_attacks() -> void:
	var w := _world(0.25, 1.0, 20)
	assert_true(w.learn_skill("energy_bolt"))
	var hp := int(w.player_state.hp)
	var events := _run(w, 120)
	assert_true(w.is_hidden())
	assert_true(_of(events, "player_hit").is_empty(), "contact cannot hurt a Hidden Thief")
	assert_eq(int(w.player_state.hp), hp)
	assert_true(_of(events, "mob_hit").is_empty())
	assert_true(_of(events, "cast").all(func(e: Dictionary) -> bool: return e.skill == KEY))


func test_dark_sight_blocks_ordinary_mob_attacks_and_boss_attacks() -> void:
	for setup: Dictionary in [MF.setup(211), BF.setup(6130101, 211)]:
		setup.data.balance.player.mp = 500
		setup.data.balance.regen.hp = 0
		setup.data.balance.regen.mp = 0
		var w := RunWorld.new(setup)
		assert_true(w.learn_skill(KEY))
		w.loadout.set_rank(KEY, 20)
		w.heal_fraction("hp", -1.0)
		w.heal_fraction("hp", 0.25)
		var ordinary: bool = setup.mob_imgs.has(MF.TAURO)
		if ordinary:
			RF.place_player(w, 400)
			RF.put_mob(w, MF.TAURO, 600)
		else:
			RF.put_mob(w, 100100, w.player.pos.x + 100, w.player.pos.y)
		w.drain_events()
		var events := _run(w, 60 * 30)
		assert_true(w.is_hidden())
		assert_true(_of(events, "player_hit").is_empty(), "mob and boss attacks cannot hurt a Hidden Thief")
		assert_true(_of(events, "mob_attack").is_empty())
		assert_true(_of(events, "boss_attack").is_empty())
		if not ordinary:
			assert_false(_of(events, "boss_spawned").is_empty(), "a scheduled boss was present")


func test_real_cache_matches_every_canonical_level_and_cast_art() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	assert_true(lib.open(AssetCachePaths.resolve_cache_root()))
	var fixture: Dictionary = RF.skill_imgs()["400"].skill["4001003"]
	for rank in range(1, 21):
		var level: Dictionary = lib.node("Skill.wz/400.img/skill/4001003/level/%d" % rank)
		for field: String in ["mpCon", "time", "speed"]:
			assert_eq(int(level[field]), int(fixture.level[str(rank)][field]), "rank %d %s" % [rank, field])
	assert_true(lib.find_anim("Skill.wz/400.img/skill/4001003/effect") != null)
	lib.free()
