extends TestCase
## Paladin Blast and Monster Magnet (spec #308, P5 #313), with their rarity bonuses, and the checks that a Paladin really
## shares Hero's Power Strike and Slash Blast and gets nothing from the Combo meter. The behaviour tests run on synthetic
## 112/122 books shaped like Skill.wz; the real-cache tests at the end assert the mapped WZ levels of all eight ranks and
## SKIP without the cache (a SKIP proves nothing about the art or the numbers).

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const MOB := 1110100
const BOSS := 2220000
const FLYER := 9300063
const CASTER_X := 1000.0
const FLAT := [{"x1": 0, "y1": 200, "x2": 2000, "y2": 200}]
const TIERS := ["rare", "epic", "unique", "legendary"]

## Rank -> WZ level: ceil(rank x 30 / 8) for both 30-level skills (spec D4, tier A reading).
const LEVELS := [4, 8, 12, 15, 19, 23, 27, 30]
## Real Skill.wz values read in P1 (#309): Blast damage and Magnet range / chance per rank, level 1 in the notes.
const BLAST_DAMAGE := [230, 310, 370, 400, 440, 480, 520, 550]
const MAGNET_RANGE := [200, 200, 300, 300, 300, 400, 400, 400]
const MAGNET_PROP := [48, 56, 64, 70, 78, 86, 92, 95]
const BLAST_USE := ["Sound.wz/Skill.img/1221009/Use", "Sound.wz/Skill.img/1221009/Use2",
	"Sound.wz/Skill.img/1221009/Use3", "Sound.wz/Skill.img/1221009/Use4", "Sound.wz/Skill.img/1221009/Use5"]


## Synthetic Blast levels: one `damage` field only (no mobCount or attackCount), 173 at level 1 up to 550 at level 30.
func _blast_levels() -> Dictionary:
	var levels := {}
	for lv in range(1, 31):
		levels[str(lv)] = {"damage": 160 + 13 * lv}
	return levels


## Synthetic Magnet levels (the same table in Hero's 112 book and Paladin's 122 book, as in the WZ).
func _magnet_levels() -> Dictionary:
	var levels := {}
	for lv in range(1, 31):
		levels[str(lv)] = {"mobCount": 6, "prop": 40 + 2 * lv, "range": 160 + 8 * lv}
	return levels


## A quiet world as `job` on a flat floor with the caster at x 1000 and a held sword, holding only `key` at rank 1 (none when
## `key` is ""), god mode on. The 112 and 122 books both carry Magnet's table; Hero's Power Strike and Slash Blast come
## from the shared fixtures.
func _world(key: String, job := 122, p_seed := 313) -> RunWorld:
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["112"]["playable"] = true
	data.jobs_survivor.jobs["122"]["playable"] = true
	var setup := RF.with_basic_attack(RF.setup("quiet", p_seed, data))
	setup.skill_imgs["112"] = {"skill": {"1121001": {"level": _magnet_levels()}}}
	setup.skill_imgs["122"] = {"skill": {"1221001": {"level": _magnet_levels()}, "1221009": {"level": _blast_levels()}}}
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


# --- Blast: the definition ---------------------------------------------------------------------------------------------

func test_blast_is_a_pool_active_with_eight_ranks_reading_the_standard_30_level_table() -> void:
	var w := _world("blast")
	assert_true(w.book.has("blast"), "blast is defined")
	var d := w.book.def("blast")
	assert_eq([int(d.skill_id), String(d.book), int(d.job), String(d.slot)], [1221009, "122", 122, "active"])
	assert_eq(w.book.rank_table("blast").map(func(v: Variant) -> int: return int(v)), LEVELS)
	assert_eq(w.book.max_rank("blast"), 8)
	assert_true(w.book.weapon_families("blast").is_empty(), "no weapon gate: families drive drops, never skills")
	assert_eq(String(d.damage), "physical")
	assert_eq(String(d.cast.rule), "weapon_reach")
	for rank in range(1, 9):
		var st := w.loadout.stats("blast", rank)
		assert_eq(st.level, LEVELS[rank - 1], "rank %d" % rank)
		assert_near(st.damage_pct, float(160 + 13 * LEVELS[rank - 1]) / 100.0, 0.0001, "rank %d damage" % rank)
		assert_eq(st.attack_count, 1, "one line, no attackCount field")
		assert_eq(st.mob_count, 1, "one target, no mobCount field")


func test_blast_cools_down_two_seconds_and_holds_the_blast_stance() -> void:
	var w := _world("blast")
	RF.put_mob(w, MOB, CASTER_X + 40, 190.0, 100000.0)
	_tick(w)
	var casts := _events(w, "cast")
	assert_eq(casts.size(), 1)
	assert_eq(String(casts[0].action), "blast", "the WZ stance: two body frames, 540 + 300 ms")
	assert_near(w.runner.cooldowns["blast"], 2.0, 0.02, "2.0 s (tier C) less the tick that cast it")
	assert_near(float(w.book.def("blast").action_time), 0.84, 0.0001)


func test_blast_art_is_the_no_charge_element_node() -> void:
	# tier A (P1 element art index): key 0 = no Charge. The Charge-aware pick arrives with P7.
	var d := _world("blast").book.def("blast")
	assert_eq(String(d.hit), "Skill.wz/122.img/skill/1221009/hit/0/0")
	assert_eq(String(d.effect), "Skill.wz/122.img/skill/1221009/effect/0")
	assert_eq(String(d.icon), "Skill.wz/122.img/skill/1221009/icon")


# --- Blast: the cast ---------------------------------------------------------------------------------------------------

func test_blast_strikes_the_nearest_mob_in_the_swing_with_exactly_one_line() -> void:
	var w := _world("blast")
	var far := RF.put_mob(w, MOB, CASTER_X + 70, 190.0, 100000.0)
	var near := RF.put_mob(w, MOB, CASTER_X + 40, 190.0, 100000.0)
	var beyond := RF.put_mob(w, MOB, CASTER_X + 400, 190.0, 100000.0)
	_tick(w)
	var hits := _events(w, "mob_hit")
	assert_eq(hits.size(), 1, "one physical line")
	assert_eq(int(hits[0].mob), near, "the nearest")
	assert_eq(w.swarm.hp[far], w.swarm.max_hp[far], "the second mob in the swing is untouched")
	assert_eq(w.swarm.hp[beyond], w.swarm.max_hp[beyond])
	assert_true(w.swarm.hp[near] < w.swarm.max_hp[near])


func test_blast_casts_with_a_single_mob_and_not_with_none_in_the_swing() -> void:
	var w := _world("blast")
	RF.put_mob(w, MOB, CASTER_X + 600, 190.0, 100000.0)
	_tick(w)
	assert_eq(w.runner.casts, 0, "nothing in the weapon's reach")
	RF.put_mob(w, MOB, CASTER_X + 50, 190.0, 100000.0)
	_tick(w)
	assert_eq(w.runner.casts, 1, "min_targets 1")


func test_final_attack_adds_a_second_line_on_the_same_mob() -> void:
	var w := _world("", 122)
	w.upgrades.apply("blast_new", w, "unique")
	RF.put_mob(w, MOB, CASTER_X + 40, 190.0, 100000.0)
	_tick(w)
	assert_eq(_events(w, "mob_hit").size(), 2, "+1 hit (attack_count)")
	assert_eq(w.loadout.rank("blast"), 1)


# --- Blast: five sounds in order --------------------------------------------------------------------------------------

func test_blast_use_sounds_rotate_in_order_with_no_rng() -> void:
	var w := _world("blast")
	var picks := []
	for n in 12:
		picks.append(w.book.use_sound("blast", n, "sword"))
	assert_eq(picks, BLAST_USE + BLAST_USE + [BLAST_USE[0], BLAST_USE[1]], "Use .. Use5, then round again")
	assert_eq(String(w.book.def("blast").sounds.use), BLAST_USE[0], "the plain Use stays the fallback")
	# A skill with no cycle plays its one sound whatever the cast number.
	assert_eq(w.book.use_sound("power_strike", 3, "sword"), "Sound.wz/Skill.img/1001004/Use")
	assert_eq(w.book.use_sound("not_a_skill", 0, "sword"), "")


# --- Blast: rarity bonuses --------------------------------------------------------------------------------------------

const BONUS_STATS := {
	"blast": {"rare": ["damage"], "epic": ["cooldown"], "unique": ["attack_count"], "legendary": ["attack_count", "damage"]},
	"monster_magnet_paladin": {"rare": ["range"], "epic": ["count"], "unique": ["cooldown"], "legendary": ["cooldown", "count"]},
}
const BONUS_IDS := {"blast": ["mastery", "booster", "final_attack", "final_attack"],
	"monster_magnet_paladin": ["reach", "grab", "booster", "booster"]}


func test_both_skills_declare_all_four_rarity_lists_and_legendary_shares_the_uniques_id() -> void:
	var w := _world("", 122)
	for key: String in BONUS_STATS:
		var bonuses: Dictionary = w.book.def(key).rarity_bonuses
		for i in TIERS.size():
			var tier: String = TIERS[i]
			assert_eq(bonuses[tier].size(), 1, "%s %s" % [key, tier])
			assert_eq(String(bonuses[tier][0].id), BONUS_IDS[key][i], "%s %s id" % [key, tier])
			var stats: Array = bonuses[tier][0].effects.map(func(e: Dictionary) -> String: return e.stat)
			assert_eq(stats, BONUS_STATS[key][tier], "%s %s effects" % [key, tier])
			assert_ne(String(bonuses[tier][0].text), "", "%s %s has a name" % [key, tier])
		assert_eq(bonuses.legendary[0].id, bonuses.unique[0].id, "%s: Legendary shares the Unique's repeats" % key)
		assert_false(w.upgrades.card(key + "_new").is_empty(), "%s has a pool card" % key)
		assert_false(w.upgrades.card(key + "_rank").is_empty())


func test_a_rare_or_better_card_adds_one_rank_and_its_bonus() -> void:
	for key: String in BONUS_STATS:
		for tier: String in TIERS:
			var a := _world("", 122)
			var b := _world("", 122)
			var c := a.upgrades.choice_card(key + "_new", a, tier)
			assert_false(c.get("rarity_bonus", {}).is_empty(), "%s %s offers a bonus" % [key, tier])
			assert_eq(c, a.upgrades.choice_card(key + "_new", a, tier), "the preview is stable")
			a.upgrades.apply(key + "_new", a, tier)
			b.upgrades.apply(key + "_new", b, tier)
			assert_eq(a.loadout.rank(key), 1, "%s %s: exactly one rank" % [key, tier])
			assert_eq(a.loadout.skill_mods.get(key, {}), b.loadout.skill_mods.get(key, {}), "same bonus in both runs")
			assert_eq(a.loadout.skill_mods[key].keys(), BONUS_STATS[key][tier], "%s %s" % [key, tier])


func test_blast_bonus_values() -> void:
	var base := _world("", 122)
	base.upgrades.apply("blast_new", base, "normal")
	var b0 := base.loadout.stats("blast")
	var rare := _world("", 122)
	rare.upgrades.apply("blast_new", rare, "rare")
	assert_near(rare.loadout.stats("blast").damage_max, b0.damage_max * 1.2, 0.001, "Mastery: damage x1.2")
	var epic := _world("", 122)
	epic.upgrades.apply("blast_new", epic, "epic")
	assert_near(epic.loadout.stats("blast").cooldown, 2.0 * 0.88, 0.0001, "Booster: cooldown x0.88")
	var unique := _world("", 122)
	unique.upgrades.apply("blast_new", unique, "unique")
	assert_eq(unique.loadout.stats("blast").attack_count, 2, "Final Attack: +1 hit")
	assert_near(unique.loadout.stats("blast").damage_max, b0.damage_max, 0.001)
	var legendary := _world("", 122)
	legendary.upgrades.apply("blast_new", legendary, "legendary")
	assert_eq(legendary.loadout.stats("blast").attack_count, 2)
	assert_near(legendary.loadout.stats("blast").damage_max, b0.damage_max * 1.2, 0.001, "Legendary adds damage x1.2")


func test_legendary_shares_the_uniques_counter_and_mastery_repeats_shrink() -> void:
	var w := _world("", 122)
	w.upgrades.apply("blast_new", w, "unique")
	w.upgrades.apply("blast_rank", w, "legendary")
	assert_eq(int(w.loadout.card_ranks["bonus:blast:final_attack"]), 2, "one counter for Unique and Legendary")
	assert_near(w.loadout.skill_stat("blast", "attack_count", 0.0), 1.8, 0.0001, "the second Final Attack repeat is x0.8")
	assert_near(w.loadout.skill_stat("blast", "damage", 1.0), 1.0 + 0.2 * 0.8, 0.0001,
		"Legendary's damage x1.2 is scaled by the same repeat")
	var m := _world("", 122)
	m.upgrades.apply("blast_new", m, "rare")
	m.upgrades.apply("blast_rank", m, "rare")
	assert_near(m.loadout.skill_stat("blast", "damage", 1.0), 1.2 * (1.0 + 0.2 * 0.8), 0.0001, "Mastery repeat x0.8")
	assert_eq(int(m.loadout.card_ranks["bonus:blast:mastery"]), 2)


func test_normal_mastery_after_rank_8_gives_blast_damage_and_magnet_a_shorter_cooldown() -> void:
	# Blast deals damage: Normal Mastery is +5 % damage (#288). Magnet has damage "none": cooldown x0.95 (#346).
	var b := _world("blast")
	b.loadout.set_rank("blast", 8)
	var before := b.loadout.stats("blast")
	var card := b.upgrades.choice_card("blast_rank", b)
	assert_eq(card.card_kind, "mastery")
	b.upgrades.apply("blast_rank", b, "normal")
	assert_near(b.loadout.stats("blast").damage_max, before.damage_max * 1.05, 0.001)
	var m := _world("monster_magnet_paladin")
	m.loadout.set_rank("monster_magnet_paladin", 8)
	var cd := float(m.loadout.stats("monster_magnet_paladin").cooldown)
	var mcard := m.upgrades.choice_card("monster_magnet_paladin_rank", m)
	assert_eq(mcard.card_kind, "mastery")
	m.upgrades.apply("monster_magnet_paladin_rank", m, "normal")
	assert_near(m.loadout.stats("monster_magnet_paladin").cooldown, cd * 0.95, 0.0001, "cooldown x0.95")
	assert_near(m.loadout.stats("monster_magnet_paladin").damage_max, 0.0, 0.0001, "and still no damage")
	assert_true(BotInput.card_score(m, mcard) > 0.0, "not a dead pick for the bot")


# --- Monster Magnet ----------------------------------------------------------------------------------------------------

func test_magnet_is_hero_magnet_with_its_own_key_book_and_ids() -> void:
	var w := _world("monster_magnet_paladin")
	var p := w.book.def("monster_magnet_paladin")
	var h := w.book.def("monster_magnet")
	assert_eq([int(p.skill_id), String(p.book), int(p.job), String(p.slot)], [1221001, "122", 122, "active"])
	assert_eq(p.cast, h.cast, "range_around, min_targets 3")
	assert_eq(p.pull, h.pull, "the same pull block")
	assert_eq(p.damage, "none")
	assert_eq(p.action, h.action)
	assert_eq(p.action_time, h.action_time)
	assert_eq(String(p.effect), "Skill.wz/122.img/skill/1221001/effect")
	assert_eq(String(p.sounds.use), "Sound.wz/Skill.img/1221001/Use")
	assert_eq(String(p.icon), "Skill.wz/122.img/skill/1221001/icon")
	assert_eq(w.book.rank_table("monster_magnet_paladin"), w.book.rank_table("monster_magnet"))
	assert_near(float(p.cooldown), 10.0, 0.0001, "tier C, spec #308: 10 s")


func test_magnet_needs_three_mobs_in_range_and_ignores_the_far_ones() -> void:
	var w := _world("monster_magnet_paladin")
	w.loadout.set_rank("monster_magnet_paladin", 8)
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
		var w := _world("monster_magnet_paladin")
		w.loadout.set_rank("monster_magnet_paladin", rank)
		var st := w.loadout.stats("monster_magnet_paladin")
		assert_eq(st.level, LEVELS[rank - 1])
		assert_eq(st.range, float(160 + 8 * st.level))
		assert_eq(st.mob_count, 6)
		assert_eq(st.pull_chance, float(40 + 2 * st.level))
		assert_eq(st.pull_gap, 60.0)
	var w := _world("monster_magnet_paladin")
	w.loadout.set_rank("monster_magnet_paladin", 8) # range 400, prop 100: every candidate is pulled
	var ids := []
	for i in 8:
		ids.append(RF.put_mob(w, MOB, CASTER_X + 150 + i * 30))
	_tick(w)
	assert_eq(_pulled(w).size(), 6, "the six farthest are pulled")
	for e: Dictionary in _pulled(w):
		assert_false(int(e.mob) in [ids[0], ids[1]], "the two nearest keep their place")
		assert_near(w.swarm.x[int(e.mob)], CASTER_X + 60.0, 0.01, "pulled to the 60 px gap")


func test_magnet_deals_no_damage() -> void:
	var w := _world("monster_magnet_paladin")
	var ids := []
	for x in [150.0, 170.0, 180.0]:
		ids.append(RF.put_mob(w, MOB, CASTER_X + x, 190.0, 100.0))
	_tick(w)
	assert_eq(w.runner.casts, 1)
	for m: int in ids:
		assert_eq(w.swarm.hp[m], w.swarm.max_hp[m])
	assert_true(_events(w, "mob_hit").is_empty())
	assert_near(w.runner.cooldowns["monster_magnet_paladin"], 10.0, 0.02, "10 s less the tick that cast it")


## The pull outcome of a rank-8 cast over a fixed crowd: slot -> final x, for the world's `key`.
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


func test_the_paladin_key_and_heros_key_pull_identically() -> void:
	for p_seed in [1, 2, 313]:
		var hero := _pull_positions(112, "monster_magnet", p_seed)
		var pal := _pull_positions(122, "monster_magnet_paladin", p_seed)
		assert_eq(pal, hero, "seed %d: same chance rolls, same targets, same spots" % p_seed)
		assert_true(pal.any(func(x: float) -> bool: return absf(x - (CASTER_X + 60.0)) < 0.01), "something was pulled")


func test_magnet_bonus_values_and_the_extra_targets_are_pulled() -> void:
	var rare := _world("", 122)
	rare.upgrades.apply("monster_magnet_paladin_new", rare, "rare")
	assert_near(rare.loadout.stats("monster_magnet_paladin").range, 192.0 * 1.2, 0.0001, "Reach: x1.2")
	var epic := _world("", 122)
	epic.upgrades.apply("monster_magnet_paladin_new", epic, "epic")
	assert_eq(epic.loadout.stats("monster_magnet_paladin").mob_count, 8, "Bigger Grab: +2 targets")
	epic.loadout.set_rank("monster_magnet_paladin", 8)
	for i in 10:
		RF.put_mob(epic, MOB, CASTER_X + 150 + i * 20)
	_tick(epic)
	assert_eq(_pulled(epic).size(), 8, "eight mobs are pulled")
	var unique := _world("", 122)
	unique.upgrades.apply("monster_magnet_paladin_new", unique, "unique")
	assert_near(unique.loadout.stats("monster_magnet_paladin").cooldown, 7.5, 0.0001, "Booster: x0.75")
	var legendary := _world("", 122)
	legendary.upgrades.apply("monster_magnet_paladin_new", legendary, "legendary")
	assert_near(legendary.loadout.stats("monster_magnet_paladin").cooldown, 7.5, 0.0001)
	assert_eq(legendary.loadout.stats("monster_magnet_paladin").mob_count, 8)


# --- Shared skills: a Paladin resolves Hero's definitions -------------------------------------------------------------

func test_a_paladin_resolves_heros_power_strike_and_slash_blast_unchanged() -> void:
	var hero := _world("", 112)
	var pal := _world("", 122)
	for key in ["power_strike", "slash_blast"]:
		assert_true(pal.book.has(key), key)
		assert_eq(pal.book.def(key), hero.book.def(key), "%s: one definition for both jobs" % key)
		assert_eq(pal.book.rank_table(key), hero.book.rank_table(key))
		assert_eq(pal.book.def(key).rarity_bonuses, hero.book.def(key).rarity_bonuses, "%s: the same rarity lists" % key)
		assert_true(key in pal.jobs.skill_pool(122), key)
		for rank in range(1, 9):
			var a := pal.loadout.stats(key, rank) if pal.loadout.has(key) else _stats_at(pal, key, rank)
			var b := _stats_at(hero, key, rank)
			for field in ["level", "damage_pct", "attack_count", "mob_count", "hp_cost", "cooldown", "range", "area"]:
				assert_eq(a.get(field), b.get(field), "%s rank %d %s" % [key, rank, field])
	assert_eq(_defined_in(["power_strike", "slash_blast"]), ["hero", "hero"], "neither is redefined for the Paladin")


func _stats_at(w: RunWorld, key: String, rank: int) -> Dictionary:
	w.learn_skill(key)
	return w.loadout.stats(key, rank)


func _defined_in(keys: Array) -> Array:
	var out := []
	for key: String in keys:
		for line: String in DataRepo.lines():
			var path := DataRepo.fragment_path("skills", line)
			if FileAccess.file_exists(path) and DataRepo.load_json(path).get("skills", {}).has(key):
				out.append(line)
	return out


func test_a_paladin_power_strike_lands_the_same_hit_lines_as_heros() -> void:
	var lines := {}
	for job in [112, 122]:
		var w := _world("power_strike", job)
		RF.put_mob(w, MOB, CASTER_X + 40, 190.0, 100000.0)
		_tick(w)
		lines[job] = _events(w, "mob_hit").size()
	assert_eq(lines[122], lines[112])
	assert_eq(lines[122], 1)


func test_the_combo_meter_does_nothing_for_a_paladin() -> void:
	var hero := _world("power_strike", 112)
	assert_false(hero.meter.config.is_empty(), "the control: Hero owns a Combo meter")
	var w := _world("power_strike", 122)
	assert_true(w.meter.config.is_empty(), "no meter config on a Paladin")
	assert_eq(w.meter.snapshot(), {})
	var first := 0.0
	var landed := 0
	var changes := 0
	for n in 20:
		RF.put_mob(w, MOB, CASTER_X + 40, 190.0, 100000.0)
		w.runner.cooldowns["power_strike"] = 0.0
		w.drain_events()
		_tick(w)
		landed += _events(w, "mob_hit").size()
		changes += _events(w, "meter_changed").size()
		var dmg := float(w.runner.stats_of(w, "power_strike").damage_max)
		if n == 0:
			first = dmg
		assert_near(dmg, first, 0.0001, "no per-orb damage bonus builds up")
	assert_true(landed >= 20, "the casts really landed")
	assert_eq(changes, 0, "no meter_changed event")
	assert_eq(w.meter.value, 0)
	# The cast-local copy the meter builds is the unmodified stats: no Combo bonus on the damage.
	var st := w.runner.stats_of(w, "power_strike")
	assert_eq(w.meter.begin_cast(w, "power_strike", st), st)
	# And Blast, Magnet and Slash Blast leave it alone too.
	for key in ["blast", "slash_blast"]:
		w.learn_skill(key)
		assert_eq(w.meter.begin_cast(w, key, w.runner.stats_of(w, key)), w.runner.stats_of(w, key), key)


# --- Text -------------------------------------------------------------------------------------------------------------

func test_magnet_and_blast_text() -> void:
	var w := _world("monster_magnet_paladin")
	w.loadout.set_rank("monster_magnet_paladin", 8)
	var text := SkillText.new(w.book, {})
	var line := text.level_line("monster_magnet_paladin", 30, w.loadout.stats("monster_magnet_paladin"))
	assert_true(line.contains("Pulls up to 6 monsters from 400 px"), line)
	w.learn_skill("blast")
	var bl := text.level_line("blast", 4, w.loadout.stats("blast", 1))
	assert_true(bl.contains("Damage 2"), bl)


# --- Real cache (SKIPs without it: a SKIP proves nothing) ---------------------------------------------------------------

func _real_world(key: String, lib: AssetLibrary) -> RunWorld:
	var w := _world(key)
	w.book.skill_imgs["122"] = lib.img("Skill.wz/122.img").root
	w.book.skill_imgs["112"] = lib.img("Skill.wz/112.img").root
	return w


func test_real_cache_blast_ranks_read_the_eight_mapped_levels() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	assert_true(lib.open(AssetCachePaths.resolve_cache_root()))
	var w := _real_world("blast", lib)
	assert_eq(w.book.max_level("blast"), 30)
	for rank in range(1, 9):
		var st := w.loadout.stats("blast", rank)
		assert_eq(st.level, LEVELS[rank - 1], "rank %d" % rank)
		var node := w.book.level_node("blast", st.level)
		assert_eq(int(node.damage), BLAST_DAMAGE[rank - 1], "rank %d damage" % rank)
		assert_near(st.damage_pct, float(BLAST_DAMAGE[rank - 1]) / 100.0, 0.0001)
		assert_false(node.has("mobCount") or node.has("attackCount"), "one field only: one line, one mob")
		assert_eq(st.attack_count, 1)
		assert_eq(st.mob_count, 1)
	assert_eq(int(w.book.level_node("blast", 1).damage), 170)
	lib.free()


func test_real_cache_magnet_ranks_read_the_eight_mapped_levels_and_equal_heros() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	assert_true(lib.open(AssetCachePaths.resolve_cache_root()))
	var w := _real_world("monster_magnet_paladin", lib)
	w.learn_skill("monster_magnet")
	for rank in range(1, 9):
		var st := w.loadout.stats("monster_magnet_paladin", rank)
		assert_eq(st.level, LEVELS[rank - 1], "rank %d" % rank)
		assert_eq(int(st.range), MAGNET_RANGE[rank - 1], "rank %d range" % rank)
		assert_eq(int(st.pull_chance), MAGNET_PROP[rank - 1], "rank %d chance" % rank)
		assert_eq(st.mob_count, 6)
		var hero := w.loadout.stats("monster_magnet", rank)
		for field in ["level", "range", "pull_chance", "pull_gap", "mob_count"]:
			assert_eq(st[field], hero[field], "rank %d %s equals Hero's" % [rank, field])
	assert_eq(int(w.book.level_node("monster_magnet_paladin", 1).prop), 42)
	assert_false(w.book.skill_node("monster_magnet_paladin").has("action"), "the node names no action: alert2 is our choice")
	lib.free()


func test_real_cache_art_and_all_five_blast_sounds_resolve() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	assert_true(lib.open(AssetCachePaths.resolve_cache_root()))
	var w := _real_world("blast", lib)
	var d := w.book.def("blast")
	assert_true(lib.frame(String(d.icon)) != null, "icon")
	assert_true(lib.anim(String(d.effect)) != null, "effect/0")
	assert_eq(lib.anim(String(d.effect)).frames.size(), 14, "Blast's cast effect: 14 frames")
	assert_eq(lib.anim(String(d.hit)).frames.size(), 3, "hit/0/0: 3 frames")
	for path: String in BLAST_USE:
		assert_true(lib.sound(path) != null, path)
	var m := w.book.def("monster_magnet_paladin")
	assert_true(lib.frame(String(m.icon)) != null, "Magnet icon")
	assert_eq(lib.anim(String(m.effect)).frames.size(), 18, "Magnet effect: 18 frames")
	assert_true(lib.sound(String(m.sounds.use)) != null, "Magnet Use (a UOL to Hero's)")
	lib.free()
