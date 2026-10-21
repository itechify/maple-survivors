extends TestCase
## Brawler Oak Barrel 5101007 (#194 of spec #168, docs/GAME_DESIGN.md 7.18): the shipped skill definition over a Skill.wz
## 510 book written with the v83 level values, through seeded RunWorld ticks. It auto-casts only below 30% HP with a mob
## in reach and the cooldown ready, fails at the Skill.wz `prop` chance rolled on the Pirate stream 16, hides and morphs
## the character into Morph 1002 for the canonical time, and ends early once HP is back above 60%.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const SNAIL := 100100
const KEY := "oak_barrel"
## Skill.wz/510.img/skill/5101007/level/1..10 (tier A, read from the owner's v83 files).
const MP := [11, 12, 13, 14, 15, 16, 17, 18, 19, 20]
const TIME := [12, 14, 16, 18, 20, 22, 24, 26, 28, 30]
const PROP := [37, 34, 31, 28, 25, 22, 19, 16, 13, 10]
const COOLTIME := [35, 35, 30, 30, 25, 25, 20, 20, 15, 15]


## A world with Oak Barrel learned at `rank`, 1000 HP at `hp_fraction`, 500 MP, one still mob `mob_dx` px to the right.
func _world(p_seed := 194, rank := 1, hp_fraction := 0.25, mob_dx := 100.0) -> RunWorld:
	var data := RF.quiet_data()
	data.balance.player.hp = 1000
	data.balance.player.mp = 500
	data.balance.player.skills = []
	data.balance.regen.hp = 0
	data.balance.regen.mp = 0
	data.balance.magnet_radius = 0
	data.balance.mob_motion.push_px = 0
	var setup := RF.with_basic_attack(RF.setup("quiet", p_seed, data))
	var w := RunWorld.new(setup)
	RF.place_player(w, 400)
	w.player.facing = 1
	assert_true(w.learn_skill(KEY))
	w.loadout.set_rank(KEY, rank)
	w.heal_fraction("hp", -1.0)
	w.heal_fraction("hp", hp_fraction)
	if mob_dx > 0.0:
		_mob(w, 400.0 + mob_dx)
	w.drain_events()
	return w


func _mob(w: RunWorld, x: float) -> int:
	w.mob_kinds[int(w.kind_of_id[SNAIL])].move_speed = 0.0
	var m := RF.put_mob(w, SNAIL, x, 190.0, 1000.0)
	w.swarm.alpha[m] = 1.0
	w.swarm.hp[m] = 1000000
	w.swarm.max_hp[m] = 1000000
	return m


func _run(w: RunWorld, ticks: int) -> Array:
	var out: Array = []
	for i in ticks:
		w.step(DT, MoveInput.new())
		out.append_array(w.drain_events())
	return out


func _of(events: Array, type: String) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return e.type == type)


func _casts(events: Array) -> Array:
	return _of(events, "cast").filter(func(e: Dictionary) -> bool: return e.skill == KEY)


## The first seed, from 1, whose first Oak Barrel roll at `rank` has the wanted outcome (true = it fails).
func _seed_whose_first_roll(fails: bool, rank := 1) -> int:
	for s in range(1, 400):
		var ref := RandomNumberGenerator.new()
		ref.seed = s * 1000003 + 16 * 7919
		if (ref.randf() < PROP[rank - 1] / 100.0) == fails:
			return s
	fail("no seed found")
	return 1


func _reset_for_next_cast(w: RunWorld) -> void:
	w.runner.cooldowns[KEY] = 0.0
	w.buffs.clear()
	w.heal_fraction("mp", 1.0)


# --- the definition --------------------------------------------------------------------------------------------------

func test_stats_come_from_the_skill_wz_levels() -> void:
	var w := _world()
	for rank in range(1, 11):
		var st := w.loadout.stats(KEY, rank)
		assert_eq(st.kind, "buff")
		assert_true(bool(st.hidden))
		assert_eq(st.morph, 1002)
		assert_eq(st.mp_cost, MP[rank - 1])
		assert_near(float(st.duration), float(TIME[rank - 1]))
		assert_near(float(st.fail_chance), PROP[rank - 1] / 100.0)
		assert_near(float(st.buff_cooldown), float(COOLTIME[rank - 1]))
		assert_near(float(st.hp_threshold), 0.3)
		assert_near(float(st.end_hp_above), 0.6)
		assert_near(SkillRunner.restart_cooldown(st), float(COOLTIME[rank - 1]), 1e-6, "the 35 -> 15 s cooldown")
	assert_eq(w.book.max_rank(KEY), 10)
	assert_eq(w.book.skill_id(KEY), 5101007)


func test_skill_text_names_the_canonical_numbers() -> void:
	var w := _world()
	var text := SkillText.new(w.book)
	assert_eq(text.level_line(KEY, 1, w.loadout.stats(KEY, 1)),
		"MP -11; barrel for 12 sec.; 37% chance to fail; 35 sec. between uses")
	assert_eq(text.level_line(KEY, 10, w.loadout.stats(KEY, 10)),
		"MP -20; barrel for 30 sec.; 10% chance to fail; 15 sec. between uses")
	assert_true(text.desc(KEY).begins_with("Transform into an oak barrel"))


func test_no_weapon_is_required() -> void:
	var w := _world()
	for family in ["", "knuckle", "gun", "sword", "any"]:
		assert_true(w.book.usable_with(KEY, family), family)


# --- when it casts ---------------------------------------------------------------------------------------------------

func test_it_casts_only_below_thirty_percent_hp() -> void:
	for fraction: float in [1.0, 0.6, 0.31, 0.3]:
		var w := _world(194, 1, fraction)
		assert_true(_casts(_run(w, 30)).is_empty(), "no cast at %d%% HP" % roundi(fraction * 100.0))
	var low := _world(194, 1, 0.29)
	assert_eq(_casts(_run(low, 30)).size(), 1, "29% HP casts")


func test_it_needs_a_mob_within_reach() -> void:
	var cast_at := func(dx: float) -> int:
		return _casts(_run(_world(194, 1, 0.2, dx), 30)).size()
	assert_eq(cast_at.call(0.0), 0, "no mob at all")
	assert_eq(cast_at.call(300.0), 0, "a mob beyond the 250 px reach")
	assert_eq(cast_at.call(240.0), 1, "a mob inside it")
	assert_eq(cast_at.call(60.0), 1)
	var behind := _world(194, 1, 0.2, 0.0)
	_mob(behind, 400.0 - 150.0)
	assert_eq(_casts(_run(behind, 30)).size(), 1, "reach covers both sides")


func test_it_waits_for_its_cooldown_and_pays_its_mp_each_cast() -> void:
	var w := _world(_seed_whose_first_roll(true), 1)
	var mp := int(w.player_state.mp)
	assert_eq(_casts(_run(w, 5)).size(), 1)
	assert_eq(int(w.player_state.mp), mp - MP[0], "the canonical mpCon is paid")
	assert_eq(_casts(_run(w, 60 * 34)).size(), 0, "35 s cooldown, still below 30% HP with a mob near")
	assert_eq(_casts(_run(w, 60 * 2)).size(), 1, "ready again after 35 s")


func test_it_does_not_recast_while_its_barrel_is_up() -> void:
	# Rank 10: a 30 s barrel and a 15 s cooldown, so the cooldown is over while the barrel still stands.
	var w := _world(_seed_whose_first_roll(false, 10), 10)
	assert_eq(_casts(_run(w, 5)).size(), 1)
	assert_true(w.is_hidden())
	var events := _run(w, 60 * 20)
	assert_true(_casts(events).is_empty(), "no second cast at 15 s or after")
	assert_true(w.is_hidden())
	events = _run(w, 60 * 11)
	assert_eq(_of(events, "buff_expired").size(), 1, "the 30 s barrel is over")
	assert_eq(_casts(events).size(), 1, "and a new one is cast at once, HP still low")


# --- failure on stream 16 --------------------------------------------------------------------------------------------

func test_failure_follows_the_skill_wz_chance_on_stream_16() -> void:
	for rank in [1, 5, 10]:
		var w := _world(7 + rank, rank)
		var other_streams := [w.rng.state, w.basic_rng.state, w.spawn_rng.state, w.card_rng.state, w.drop_rng.state]
		var ref := RandomNumberGenerator.new()
		ref.seed = (7 + rank) * 1000003 + 16 * 7919
		var fails := 0
		var casts := 0
		for n in 200:
			_reset_for_next_cast(w)
			var events := _run(w, 1)
			if _casts(events).is_empty():
				fail("cast %d did not happen" % n)
				break
			casts += 1
			var expect_fail: bool = ref.randf() < PROP[rank - 1] / 100.0
			var failed := not _of(events, "buff_failed").is_empty()
			assert_eq(failed, expect_fail, "rank %d cast %d: the stream-16 roll decides" % [rank, n])
			assert_eq(not _of(events, "buff_cast").is_empty(), not expect_fail)
			assert_eq(w.is_hidden(), not expect_fail)
			fails += 1 if failed else 0
		assert_eq(casts, 200)
		assert_eq(w.pirate_rng.state, ref.state, "exactly one draw per cast, nothing else uses the stream")
		var expected: float = PROP[rank - 1] * 2.0
		assert_between(float(fails), expected * 0.6, expected * 1.4, "about %d%% of 200 casts fail" % PROP[rank - 1])
		# Every other stream is untouched by the casts (no mob dies, no skill damages anything).
		assert_eq([w.rng.state, w.basic_rng.state, w.spawn_rng.state, w.card_rng.state, w.drop_rng.state], other_streams)


func test_a_failed_cast_pays_mp_and_the_cooldown_but_hides_nothing() -> void:
	var w := _world(_seed_whose_first_roll(true))
	var mp := int(w.player_state.mp)
	var events := _run(w, 1)
	var failed := _of(events, "buff_failed")
	assert_eq(failed.size(), 1)
	assert_eq(failed[0].skill, KEY)
	assert_eq(failed[0].skill_id, 5101007)
	assert_true(_of(events, "buff_cast").is_empty())
	assert_eq(_casts(events)[0].effect, "", "a failed cast plays no effect")
	assert_false(w.is_hidden())
	assert_eq(w.morph_id(), 0)
	assert_eq(int(w.player_state.morph), 0)
	assert_eq(int(w.player_state.mp), mp - MP[0])
	assert_near(w.runner.cooldowns[KEY], 35.0, 0.1)
	assert_true(w.player_state.buffs.is_empty())


# --- success, morph and the early end --------------------------------------------------------------------------------

func test_success_hides_and_morphs_for_the_canonical_time() -> void:
	for rank in [1, 4, 10]:
		var seed_value := 1
		var w: RunWorld
		while true:
			w = _world(seed_value, rank)
			var ref := RandomNumberGenerator.new()
			ref.seed = seed_value * 1000003 + 16 * 7919
			if ref.randf() >= PROP[rank - 1] / 100.0:
				break
			seed_value += 1
		var events := _run(w, 1)
		var cast := _of(events, "buff_cast")
		assert_eq(cast.size(), 1)
		assert_near(float(cast[0].duration), float(TIME[rank - 1]))
		assert_eq(_casts(events)[0].effect, "Skill.wz/510.img/skill/5101007/effect")
		assert_true(w.is_hidden())
		assert_true(bool(w.player_state.hidden))
		assert_eq(int(w.player_state.morph), 1002)
		assert_eq(w.player_state.buffs.size(), 1)
		var seconds: int = TIME[rank - 1]
		for i in w.swarm.capacity():
			w.swarm.despawn(i) # nothing left to trigger a new cast
		_run(w, seconds * 60 - 5)
		assert_true(w.is_hidden(), "rank %d still a barrel just before %d s" % [rank, seconds])
		_run(w, 10)
		assert_false(w.is_hidden(), "rank %d over after %d s" % [rank, seconds])
		assert_eq(int(w.player_state.morph), 0, "the avatar is back")


func test_it_ends_early_once_hp_is_above_sixty_percent_and_not_before() -> void:
	var w := _world(_seed_whose_first_roll(false), 1)
	_run(w, 2)
	assert_true(w.is_hidden())
	w.heal_fraction("hp", 0.30) # 55%
	_run(w, 30)
	assert_true(w.is_hidden(), "55% HP: still a barrel")
	w.heal_fraction("hp", 0.04) # 59%
	_run(w, 30)
	assert_true(w.is_hidden(), "59% HP: still a barrel")
	w.heal_fraction("hp", 0.03)
	var events := _run(w, 2)
	assert_false(w.is_hidden(), "62% HP ends it")
	assert_eq(_of(events, "buff_expired").size(), 1)
	assert_eq(int(w.player_state.morph), 0)
	assert_true(w.runner.cooldowns[KEY] > 30.0, "the cooldown from the cast keeps running")
	assert_true(_casts(_run(w, 600)).is_empty(), "no recast above 30% HP and during the cooldown")


func test_a_barrel_is_not_attacked_and_does_not_attack() -> void:
	var w := _world(_seed_whose_first_roll(false), 1)
	w.mob_kinds[int(w.kind_of_id[SNAIL])].move_speed = 40.0
	w.drain_events()
	var hp := int(w.player_state.hp)
	var events := _run(w, 60 * 10)
	assert_true(w.is_hidden())
	assert_true(_of(events, "player_hit").is_empty(), "the snail by the barrel hurts nobody")
	assert_eq(int(w.player_state.hp), hp)
	assert_true(_of(events, "mob_hit").is_empty(), "and the barrel strikes nothing")
	assert_true(_of(events, "basic_attack").is_empty())


# --- cards -----------------------------------------------------------------------------------------------------------

func test_cards_are_offered_to_brawlers_only() -> void:
	var w := _world()
	w.loadout.ranks.erase(KEY)
	w.loadout.order.erase(KEY)
	w.loadout.version += 1
	for job in [510, 500, 520, 100, 0, 200]:
		w.progression.job_id = job
		var ids: Array = w.upgrades.eligible(w)
		assert_eq("oak_barrel_new" in ids, job == 510, "learn card for job %d" % job)
		assert_false("oak_barrel_rank" in ids, "no rank card before it is learned")
	w.progression.job_id = 510
	assert_true(w.learn_skill(KEY))
	var ids: Array = w.upgrades.eligible(w)
	assert_false("oak_barrel_new" in ids)
	assert_true("oak_barrel_rank" in ids)
	var card: Dictionary = w.upgrades.card("oak_barrel_rank")
	assert_eq(int(card.max_rank), 10)
	assert_eq(int(card.requires.jobs[0]), 510)
	assert_eq(card.requires.jobs.size(), 1)
	w.loadout.set_rank(KEY, 10)
	assert_false("oak_barrel_rank" in w.upgrades.eligible(w), "none at the top rank")


## A real Brawler (#189): a knuckle Pirate advanced to 510 at Lv 30 through change_job, as the advancement window does.
func _brawler(p_seed := 194) -> RunWorld:
	var data := RF.quiet_data()
	data.balance.player.hp = 1000
	data.balance.player.mp = 500
	data.balance.player.skills = []
	data.balance.regen.hp = 0
	data.balance.regen.mp = 0
	var setup := RF.with_basic_attack(RF.setup("quiet", p_seed, data))
	setup.equipment_info.merge({1482000: {"incPAD": 18, "attackSpeed": 5, "tuc": 7},
		1482004: {"incPAD": 36, "attackSpeed": 5, "tuc": 7, "reqLevel": 30}}, true)
	var w := RunWorld.new(setup)
	RF.place_player(w, 400)
	w.change_job(500, "knuckle")
	w.progression.level = 30
	w.change_job(510)
	w.pending_cards = []
	w.state = RunWorld.PLAYING
	w.drain_events()
	return w


func test_a_real_brawler_is_offered_the_cards_and_the_barrel_works() -> void:
	var w := _brawler()
	assert_eq(w.progression.job_id, 510)
	assert_true("oak_barrel_new" in w.upgrades.eligible(w), "the learn card reaches a Brawler")
	var gunner := _brawler()
	gunner.progression.job_id = 520
	assert_false("oak_barrel_new" in gunner.upgrades.eligible(gunner), "not a Gunslinger")
	var pirate := _brawler()
	pirate.progression.job_id = 500
	assert_false("oak_barrel_new" in pirate.upgrades.eligible(pirate), "not the first-job Pirate")
	var card: Dictionary = w.upgrades.choice_card("oak_barrel_new", w)
	assert_eq(card.skill_name, "Oak Barrel")
	assert_eq(w.upgrades.apply("oak_barrel_new", w), 1)
	assert_true(w.loadout.has(KEY))
	assert_true("oak_barrel_rank" in w.upgrades.eligible(w))
	# Learned: below 30% HP with a snail by it, the Brawler turns into the barrel (a seed whose roll succeeds).
	var seed_value := _seed_whose_first_roll(false)
	var b := _brawler(seed_value)
	b.learn_skill(KEY)
	b.heal_fraction("hp", -1.0)
	b.heal_fraction("hp", 0.2)
	_mob(b, 500.0)
	var events := _run(b, 5)
	assert_eq(_casts(events).size(), 1)
	assert_true(b.is_hidden(), "the Brawler is Hidden")
	assert_eq(int(b.player_state.morph), 1002)
	assert_eq(_of(events, "player_hit").size(), 0)


func test_the_rank_card_raises_the_skill_level() -> void:
	var w := _world()
	w.progression.job_id = 510
	assert_eq(w.loadout.rank(KEY), 1)
	assert_eq(w.upgrades.apply("oak_barrel_rank", w), 1)
	assert_eq(w.loadout.rank(KEY), 2)
	assert_eq(w.loadout.stats(KEY).level, 2)


# --- real data (SKIP without the cache) -----------------------------------------------------------------------------

func test_real_v83_levels_match_the_fixture_book() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	assert_true(lib.open(AssetCachePaths.resolve_cache_root()))
	for i in 10:
		var node: Variant = lib.node("Skill.wz/510.img/skill/5101007/level/%d" % (i + 1))
		assert_true(node is Dictionary, "level %d is in the cache" % (i + 1))
		if not (node is Dictionary):
			continue
		assert_eq(int(node.mpCon), MP[i])
		assert_eq(int(node.time), TIME[i])
		assert_eq(int(node.prop), PROP[i])
		assert_eq(int(node.cooltime), COOLTIME[i])
		assert_eq(int(node.morph), 1002)
	assert_true(lib.find_anim("Skill.wz/510.img/skill/5101007/effect") != null, "the cast effect is cached")
	assert_true(lib.has_img("Morph.wz/1002.img"), "the barrel morph is cached")
	lib.free()
