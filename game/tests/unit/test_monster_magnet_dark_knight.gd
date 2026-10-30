extends TestCase
## Dark Knight's Monster Magnet (spec #348 D8, #356; WZ 1321001, book 132): a data copy of Hero's Monster Magnet (1121001) on
## the shared `pull` block, with its own ids, art and sound. The behaviour tests run on a synthetic 112/132 pair shaped like
## Skill.wz; the real-cache tests at the end assert the mapped WZ levels of all eight ranks and SKIP without the cache (a SKIP
## proves nothing about the art or the numbers).

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const KEY := "monster_magnet_dark_knight"
const HERO := "monster_magnet"
const MOB := 1110100
const BOSS := 2220000
const CASTER_X := 1000.0
const FLAT := [{"x1": 0, "y1": 200, "x2": 2000, "y2": 200}]

## Rank -> WZ level: ceil(rank x 30 / 8) for a 30-level skill (the survivor rank table, as Hero's).
const LEVELS := [4, 8, 12, 15, 19, 23, 27, 30]
## Real Skill.wz/132.img/1321001 values read in D1 (#349): range and prop per rank; mobCount 6 at every level.
const MAGNET_RANGE := [200, 200, 300, 300, 300, 400, 400, 400]
const MAGNET_PROP := [48, 56, 64, 70, 78, 86, 92, 95]


## Synthetic levels: the same table in Hero's 112 book and Dark Knight's 132 book, as in the WZ (the real one is read below).
func _magnet_levels() -> Dictionary:
	var levels := {}
	for lv in range(1, 31):
		levels[str(lv)] = {"mobCount": 6, "prop": 40 + 2 * lv, "range": 160 + 8 * lv}
	return levels


## A quiet world as `job` (112 Hero or 132 Dark Knight) on a flat floor with the caster at x 1000, holding only `key` at
## rank 1 when `key` is not "" (`learn`), god mode on. Mobs do not move, so a pull is the only change in their x.
func _world(key: String, job := 132, p_seed := 313) -> RunWorld:
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["112"]["playable"] = true
	data.jobs_survivor.jobs["132"]["playable"] = true
	var setup := RF.with_basic_attack(RF.setup("quiet", p_seed, data))
	setup.skill_imgs["112"] = {"skill": {"1121001": {"level": _magnet_levels()}}}
	setup.skill_imgs["132"] = {"skill": {"1321001": {"level": _magnet_levels()}}}
	var w := RunWorld.new(setup)
	w.set_job(job)
	w.bounds = Rect2(0, -500, 2000, 1000)
	w.fhm = FootholdMap.from_segments(FLAT)
	w.swarm.fhm = w.fhm
	RF.place_player(w, CASTER_X)
	w.loadout.ranks.clear()
	w.loadout.order.clear()
	if key != "":
		w.learn_skill(key)
	w.god = true
	for mk: MobKind in w.mob_kinds:
		mk.hitbox = Rect2(-5, -10, 10, 10)
		mk.move_speed = 0.0
	w.drain_events()
	return w


func _tick(w: RunWorld) -> void:
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	w.runner.step(DT, w)


func _events(w: RunWorld, type: String) -> Array:
	return w.events.filter(func(e: Dictionary) -> bool: return e.type == type)


func _pulled(w: RunWorld) -> Array:
	return _events(w, "mob_pulled")


# --- Definition -----------------------------------------------------------------------------------------------------------

## Dark Knight's Magnet is Hero's Magnet with its own key, book, ids, art and sound: cast, pull, damage, stance, cooldown
## and the rarity lists are the same values (#356 "a copy of Hero's"), the cooldown is Hero's 4 s.
func test_magnet_is_hero_magnet_with_its_own_key_book_and_ids() -> void:
	var w := _world(KEY)
	var d := w.book.def(KEY)
	var h := w.book.def(HERO)
	assert_eq([int(d.skill_id), String(d.book), int(d.job), String(d.slot)], [1321001, "132", 132, "active"])
	assert_eq(d.cast, h.cast, "range_around, min_targets 3")
	assert_eq(d.pull, h.pull, "the same pull block")
	assert_eq(d.damage, "none")
	assert_eq(d.action, h.action, "alert2, Hero's choice (the node names none)")
	assert_eq(d.action_time, h.action_time)
	assert_eq(d.rarity_bonuses, h.rarity_bonuses, "the same four rarity lists")
	assert_eq(String(d.effect), "Skill.wz/132.img/skill/1321001/effect")
	assert_eq(String(d.sounds.use), "Sound.wz/Skill.img/1321001/Use")
	assert_eq(String(d.icon), "Skill.wz/132.img/skill/1321001/icon")
	assert_near(float(d.cooldown), 4.0, 0.0001, "Hero's tuned 4 s (#346), copied")
	assert_eq(w.book.rank_table(KEY), w.book.rank_table(HERO))


func test_both_skills_declare_all_four_rarity_lists_and_legendary_shares_the_uniques_id() -> void:
	var w := _world(KEY)
	var d := w.book.def(KEY)
	for tier: String in ["rare", "epic", "unique", "legendary"]:
		assert_true(d.rarity_bonuses.has(tier), tier)
	assert_eq(String(d.rarity_bonuses.unique[0].id), String(d.rarity_bonuses.legendary[0].id), "same id, same counter")


# --- Behaviour --------------------------------------------------------------------------------------------------------------

func test_magnet_needs_three_mobs_in_range_and_ignores_the_far_ones() -> void:
	var w := _world(KEY)
	w.loadout.set_rank(KEY, 8)
	RF.put_mob(w, MOB, CASTER_X + 150)
	RF.put_mob(w, MOB, CASTER_X - 150)
	RF.put_mob(w, MOB, CASTER_X + 900)
	_tick(w)
	assert_eq(w.runner.casts, 0, "two in range (the far one is not counted) do not admit the cast")
	RF.put_mob(w, MOB, CASTER_X + 170)
	_tick(w)
	assert_eq(w.runner.casts, 1, "the third mob in range admits it")
	assert_eq(_pulled(w).size(), 3)


func test_magnet_range_chance_and_mob_cap_follow_the_mapped_level() -> void:
	for rank in [1, 4, 8]:
		var w := _world(KEY)
		w.loadout.set_rank(KEY, rank)
		var st := w.loadout.stats(KEY)
		assert_eq(st.level, LEVELS[rank - 1])
		assert_eq(st.range, float(160 + 8 * st.level))
		assert_eq(st.mob_count, 6)
		assert_eq(st.pull_chance, float(40 + 2 * st.level))
		assert_eq(st.pull_gap, 60.0)
	var w := _world(KEY)
	w.loadout.set_rank(KEY, 8) # range 400, prop 100: every candidate is pulled
	var ids := []
	for i in 8:
		ids.append(RF.put_mob(w, MOB, CASTER_X + 150 + i * 30))
	_tick(w)
	assert_eq(_pulled(w).size(), 6, "the six farthest are pulled")
	for e: Dictionary in _pulled(w):
		assert_false(int(e.mob) in [ids[0], ids[1]], "the two nearest keep their place")
		assert_near(w.swarm.x[int(e.mob)], CASTER_X + 60.0, 0.01, "pulled to the 60 px gap")


func test_magnet_deals_no_damage_and_cools_down_for_four_seconds() -> void:
	var w := _world(KEY)
	var ids := []
	for x in [150.0, 170.0, 180.0]:
		ids.append(RF.put_mob(w, MOB, CASTER_X + x, 190.0, 100.0))
	_tick(w)
	assert_eq(w.runner.casts, 1)
	for m: int in ids:
		assert_eq(w.swarm.hp[m], w.swarm.max_hp[m])
	assert_true(_events(w, "mob_hit").is_empty())
	assert_near(w.runner.cooldowns[KEY], 4.0, 0.02, "4 s less the tick that cast it")


func test_the_bot_does_not_count_magnet_as_a_reach() -> void:
	var w := _world(KEY)
	assert_eq(SkillRunner.reach_of(w.loadout.stats(KEY), w), 0.0)


## The pull outcome of a rank-5 cast over a fixed crowd: slot -> final x, for the world's `key` and `job`.
func _pull_positions(job: int, key: String, p_seed: int) -> Array:
	var w := _world(key, job, p_seed)
	w.loadout.set_rank(key, 5) # prop 78 -> 70: a real roll for every mob
	var ids := []
	for i in 6:
		ids.append(RF.put_mob(w, MOB, CASTER_X + 130 + i * 28))
		ids.append(RF.put_mob(w, MOB, CASTER_X - 140 - i * 25))
	ids.append(RF.put_mob(w, BOSS, CASTER_X + 250))
	_tick(w)
	return ids.map(func(slot: int) -> float: return snappedf(w.swarm.x[slot], 0.001))


## Same chance rolls, same targets and the same spots as Hero's key over several seeds (the pull is the shared block).
func test_the_dark_knight_key_and_heros_key_pull_identically() -> void:
	for p_seed in [1, 2, 313]:
		var hero := _pull_positions(112, HERO, p_seed)
		var dk := _pull_positions(132, KEY, p_seed)
		assert_eq(dk, hero, "seed %d: same chance rolls, same targets, same spots" % p_seed)
		assert_true(dk.any(func(x: float) -> bool: return absf(x - (CASTER_X + 60.0)) < 0.01), "something was pulled")


func test_magnet_bonus_values_and_the_extra_targets_are_pulled() -> void:
	var rare := _world("", 132)
	rare.upgrades.apply(KEY + "_new", rare, "rare")
	assert_near(rare.loadout.stats(KEY).range, 192.0 * 1.2, 0.0001, "Reach: x1.2 (rank 1 = level 4 = 192 px here)")
	var epic := _world("", 132)
	epic.upgrades.apply(KEY + "_new", epic, "epic")
	assert_eq(epic.loadout.stats(KEY).mob_count, 8, "Bigger Grab: +2 targets")
	epic.loadout.set_rank(KEY, 8)
	for i in 10:
		RF.put_mob(epic, MOB, CASTER_X + 150 + i * 20)
	_tick(epic)
	assert_eq(_pulled(epic).size(), 8, "eight mobs are pulled")
	var unique := _world("", 132)
	unique.upgrades.apply(KEY + "_new", unique, "unique")
	assert_near(unique.loadout.stats(KEY).cooldown, 3.0, 0.0001, "Booster: x0.75")
	var legendary := _world("", 132)
	legendary.upgrades.apply(KEY + "_new", legendary, "legendary")
	assert_near(legendary.loadout.stats(KEY).cooldown, 3.0, 0.0001)
	assert_eq(legendary.loadout.stats(KEY).mob_count, 8)


func test_normal_mastery_after_rank_8_shortens_the_cooldown_x0_95_and_deals_no_damage() -> void:
	# Magnet has damage "none": Normal Mastery is the cooldown x0.95 (#346), never a damage bonus.
	var m := _world(KEY)
	m.loadout.set_rank(KEY, 8)
	var cd := float(m.loadout.stats(KEY).cooldown)
	var card := m.upgrades.choice_card(KEY + "_rank", m)
	assert_eq(card.card_kind, "mastery")
	m.upgrades.apply(KEY + "_rank", m, "normal")
	assert_near(m.loadout.stats(KEY).cooldown, cd * 0.95, 0.0001, "cooldown x0.95")
	assert_near(m.loadout.stats(KEY).damage_max, 0.0, 0.0001, "and still no damage")
	assert_true(BotInput.card_score(m, card) > 0.0, "not a dead pick for the bot")


# --- Real cache ------------------------------------------------------------------------------------------------------------

func _real_world(key: String, lib: AssetLibrary) -> RunWorld:
	var w := _world(key)
	w.book.skill_imgs["132"] = lib.img("Skill.wz/132.img").root
	w.book.skill_imgs["112"] = lib.img("Skill.wz/112.img").root
	return w


## Needs the real asset cache (SKIPs without it): ranks 1..8 read the mapped WZ levels, with the range and chance of the
## node, and equal Hero's Magnet at every rank.
func test_real_cache_magnet_ranks_read_the_eight_mapped_levels_and_equal_heros() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	assert_true(lib.open(AssetCachePaths.resolve_cache_root()))
	var w := _real_world(KEY, lib)
	w.learn_skill(HERO)
	for rank in range(1, 9):
		var st := w.loadout.stats(KEY, rank)
		assert_eq(st.level, LEVELS[rank - 1], "rank %d" % rank)
		assert_eq(int(st.range), MAGNET_RANGE[rank - 1], "rank %d range" % rank)
		assert_eq(int(st.pull_chance), MAGNET_PROP[rank - 1], "rank %d chance" % rank)
		assert_eq(st.mob_count, 6)
		var hero := w.loadout.stats(HERO, rank)
		for field in ["level", "range", "pull_chance", "pull_gap", "mob_count"]:
			assert_eq(st[field], hero[field], "rank %d %s equals Hero's" % [rank, field])
	assert_eq(int(w.book.level_node(KEY, 1).prop), 42)
	assert_false(w.book.skill_node(KEY).has("action"), "the node names no action: alert2 is our choice")
	lib.free()


## The icon, the 18-frame effect (Hero's horseshoe art) and the Use sound through its UOL all resolve.
func test_real_cache_art_and_sound_resolve() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	assert_true(lib.open(AssetCachePaths.resolve_cache_root()))
	var w := _real_world(KEY, lib)
	var d := w.book.def(KEY)
	assert_true(lib.frame(String(d.icon)) != null, "icon")
	assert_eq(lib.anim(String(d.effect)).frames.size(), 18, "Magnet effect: 18 frames")
	assert_true(lib.sound(String(d.sounds.use)) != null, "Use (a UOL to Hero's 1121001/Use)")
	assert_true(lib.missing.is_empty(), str(lib.missing))
	lib.free()
