extends TestCase
## Hero crowd control (spec #296, H7 #303): Shout (box, `min_targets 3`, stun, the explicit rank table) and Monster Magnet
## (`range_around`, `min_targets 3`, the shared pull block of #300), with their rarity bonuses. The behaviour tests run on
## synthetic 111/112 books shaped like Skill.wz (including the missing `prop` of Shout level 4); the real-cache tests at the
## end assert the mapped WZ levels against the cache and SKIP without it.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const MOB := 1110100
const BOSS := 2220000
const FLYER := 9300063
const CASTER_X := 1000.0
const FLAT := [{"x1": 0, "y1": 200, "x2": 2000, "y2": 200}]

## Rank -> WZ level of Shout (spec D4) and of the standard 30-level table Monster Magnet uses (tier A reading, H1 #297).
const SHOUT_LEVELS := [5, 8, 12, 15, 19, 23, 27, 30]
const MAGNET_LEVELS := [4, 8, 12, 15, 19, 23, 27, 30]


## Synthetic Skill.wz levels of Shout: prop 40 + 2 x level and time 3 + level / 6, except level 4, which like the real node
## stores its chance under the stray key "58" instead of `prop`.
func _shout_levels() -> Dictionary:
	var levels := {}
	for lv in range(1, 31):
		var node := {"damage": 10 + lv, "mobCount": 6, "time": 3 + lv / 6, "prop": 40 + 2 * lv,
			"lt": {"$v": [-100 - 3 * lv, -80 - 2 * lv]}, "rb": {"$v": [100 + 3 * lv, 80 + 2 * lv]}}
		if lv == 4:
			node.erase("prop")
			node["58"] = 38
		levels[str(lv)] = node
	return levels


## Synthetic levels of Monster Magnet: range 160 + 8 x level, prop 40 + 2 x level, mobCount 6.
func _magnet_levels() -> Dictionary:
	var levels := {}
	for lv in range(1, 31):
		levels[str(lv)] = {"mobCount": 6, "prop": 40 + 2 * lv, "range": 160 + 8 * lv}
	return levels


## A quiet world as job 112 on a flat floor with the caster at x 1000, holding only `key` at rank 1, god mode on.
func _world(key: String, p_seed := 303, learn := true) -> RunWorld:
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["112"]["playable"] = true # Hero is flipped playable by H9/H10; this makes its cards exist
	var setup := RF.setup("quiet", p_seed, data)
	setup.skill_imgs["111"] = {"skill": {"1111008": {"level": _shout_levels()}}}
	setup.skill_imgs["112"] = {"skill": {"1121001": {"level": _magnet_levels()}}}
	var w := RunWorld.new(setup)
	w.set_job(112)
	w.bounds = Rect2(0, -500, 2000, 1000)
	w.fhm = FootholdMap.from_segments(FLAT)
	w.swarm.fhm = w.fhm
	RF.place_player(w, CASTER_X)
	w.loadout.order.clear()
	if learn:
		w.learn_skill(key)
	w.god = true
	w.drain_events()
	return w


func _tick(w: RunWorld) -> void:
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	w.runner.step(DT, w)


func _stuns(w: RunWorld) -> Array:
	return w.events.filter(func(e: Dictionary) -> bool: return e.type == "mob_status_applied")


# --- Shout: the rank table --------------------------------------------------------------------------------------------

func test_shout_rank_1_reads_level_5_because_level_4_has_no_prop() -> void:
	var w := _world("shout")
	assert_true(w.book.has("shout"), "Shout is defined")
	assert_eq(w.book.rank_table("shout").map(func(v: Variant) -> int: return int(v)), SHOUT_LEVELS)
	assert_eq(w.book.max_rank("shout"), 8)
	var st := w.loadout.stats("shout")
	assert_eq(st.level, 5, "rank 1 skips the corrupted level 4")
	assert_eq(w.book.canonical("shout", st.level, "prop"), 50.0, "level 5's prop, not a missing field")
	for rank in range(1, 9):
		assert_eq(w.loadout.stats("shout", rank).level, SHOUT_LEVELS[rank - 1])
		assert_true(w.book.level_node("shout", w.loadout.stats("shout", rank).level).has("prop"),
			"rank %d has a prop" % rank)


# --- Shout: the cast --------------------------------------------------------------------------------------------------

func test_shout_needs_three_mobs_in_the_box_and_strikes_at_most_six() -> void:
	var w := _world("shout")
	RF.put_mob(w, MOB, CASTER_X + 60, 190.0, 1000.0)
	RF.put_mob(w, MOB, CASTER_X - 60, 190.0, 1000.0)
	_tick(w)
	assert_eq(w.runner.casts, 0, "two mobs in the box do not admit the cast")
	RF.put_mob(w, MOB, CASTER_X + 80, 190.0, 1000.0)
	_tick(w)
	assert_eq(w.runner.casts, 1, "the third mob admits it")
	w = _world("shout")
	for i in 9:
		RF.put_mob(w, MOB, CASTER_X - 80 + i * 20, 190.0, 1000.0)
	var far := RF.put_mob(w, MOB, CASTER_X + 900, 190.0, 1000.0)
	_tick(w)
	var hits := w.events.filter(func(e: Dictionary) -> bool: return e.type == "mob_hit")
	assert_eq(hits.size(), 6, "mobCount 6 caps the mobs struck")
	assert_eq(w.swarm.hp[far], w.swarm.max_hp[far], "a mob outside the box is untouched")


func test_shout_box_is_centred_and_grows_with_the_rank() -> void:
	var w := _world("shout")
	var one: Rect2 = w.loadout.stats("shout", 1).box
	assert_near(one.position.x, -one.end.x, 0.001, "centred on the caster")
	assert_true(w.loadout.stats("shout", 8).box.size.x > one.size.x)
	var wide := _world("shout", 303, false)
	wide.upgrades.apply("shout_new", wide, "rare")
	assert_near(wide.loadout.stats("shout").box.size.x, one.size.x * 1.2, 0.01, "Rare area x1.2")


func _stun_rate(rank: int, casts: int) -> Array:
	var w := _world("shout")
	w.loadout.set_rank("shout", rank)
	var mobs := []
	for i in 6:
		mobs.append(RF.put_mob(w, MOB, CASTER_X - 100 + i * 40, 190.0, 100000.0))
	var landed := 0
	var time := 0.0
	for n in casts:
		w.runner.cooldowns["shout"] = 0.0
		w.drain_events()
		_tick(w)
		for e: Dictionary in _stuns(w):
			landed += 1
			time = w.swarm.status_time(int(e.mob), MobSwarm.STUN)
	return [float(landed) / float(casts * 6), time]


func test_shout_stun_chance_and_seconds_follow_the_mapped_level() -> void:
	# Synthetic tables: rank 1 = level 5 (prop 50, time 3), rank 8 = level 30 (prop 100 -> always, time 8).
	var low := _stun_rate(1, 60)
	assert_near(low[0], 0.50, 0.06, "rank 1 stuns at level 5's 50 %")
	assert_near(low[1], 3.0, 0.05, "for level 5's seconds")
	var top := _stun_rate(8, 20)
	assert_eq(top[0], 1.0, "rank 8 (level 30, prop 100) always stuns")
	assert_near(top[1], 8.0, 0.05)
	assert_eq(_stun_rate(1, 60), low, "same seed, same outcome")


# --- Rarity bonuses ---------------------------------------------------------------------------------------------------

const BONUS_STATS := {
	"shout": {"rare": ["area"], "epic": ["cooldown"], "unique": ["cooldown"], "legendary": ["cooldown", "area"]},
	"monster_magnet": {"rare": ["range"], "epic": ["count"], "unique": ["cooldown"], "legendary": ["cooldown", "count"]},
}


func test_both_skills_declare_all_four_rarity_lists_and_legendary_shares_the_uniques_id() -> void:
	var w := _world("shout", 303, false)
	for key: String in BONUS_STATS:
		var bonuses: Dictionary = w.book.def(key).rarity_bonuses
		for tier: String in BONUS_STATS[key]:
			assert_eq(bonuses[tier].size(), 1, "%s %s" % [key, tier])
			var stats: Array = bonuses[tier][0].effects.map(func(e: Dictionary) -> String: return e.stat)
			assert_eq(stats, BONUS_STATS[key][tier], "%s %s effects" % [key, tier])
		assert_eq(bonuses.legendary[0].id, bonuses.unique[0].id, "%s: Legendary shares the Unique's repeats" % key)
		assert_false(w.upgrades.card(key + "_new").is_empty(), "%s has a pool card" % key)
		assert_false(w.upgrades.card(key + "_rank").is_empty())


func test_a_rare_or_better_card_adds_one_rank_and_its_bonus() -> void:
	for key: String in BONUS_STATS:
		for tier: String in BONUS_STATS[key]:
			var a := _world(key, 303, false)
			var b := _world(key, 303, false)
			var c := a.upgrades.choice_card(key + "_new", a, tier)
			assert_false(c.get("rarity_bonus", {}).is_empty(), "%s %s offers a bonus" % [key, tier])
			assert_eq(c, a.upgrades.choice_card(key + "_new", a, tier), "the preview is stable")
			a.upgrades.apply(key + "_new", a, tier)
			b.upgrades.apply(key + "_new", b, tier)
			assert_eq(a.loadout.rank(key), 1, "%s %s: exactly one rank" % [key, tier])
			assert_eq(a.loadout.skill_mods.get(key, {}), b.loadout.skill_mods.get(key, {}), "same bonus in both runs")
			assert_eq(a.loadout.skill_mods[key].keys(), BONUS_STATS[key][tier], "%s %s" % [key, tier])


func test_shout_bonus_values() -> void:
	var base := _world("shout", 303, false)
	base.upgrades.apply("shout_new", base, "normal")
	var rare := _world("shout", 303, false)
	rare.upgrades.apply("shout_new", rare, "rare")
	assert_near(rare.loadout.stats("shout").area, 1.2)
	var epic := _world("shout", 303, false)
	epic.upgrades.apply("shout_new", epic, "epic")
	assert_near(epic.loadout.stats("shout").cooldown, 12.0 * 0.88, 0.0001)
	var unique := _world("shout", 303, false)
	unique.upgrades.apply("shout_new", unique, "unique")
	assert_near(unique.loadout.stats("shout").cooldown, 9.0, 0.0001, "Echo Shout: x0.75")
	var legendary := _world("shout", 303, false)
	legendary.upgrades.apply("shout_new", legendary, "legendary")
	assert_near(legendary.loadout.stats("shout").cooldown, 9.0, 0.0001)
	assert_near(legendary.loadout.stats("shout").area, 1.2)
	assert_near(legendary.loadout.stats("shout").damage_max, base.loadout.stats("shout").damage_max, 0.0001,
		"Legendary adds area, not damage")
	legendary.upgrades.apply("shout_rank", legendary, "unique")
	assert_near(legendary.loadout.skill_stat("shout", "cooldown", 1.0), 0.75 * (1.0 - 0.25 * 0.8), 0.0001,
		"Unique and Legendary share the Echo counter, the repeat shrinks x0.8")


func test_magnet_bonus_values_and_the_extra_targets_are_pulled() -> void:
	var rare := _world("monster_magnet", 303, false)
	rare.upgrades.apply("monster_magnet_new", rare, "rare")
	assert_near(rare.loadout.stats("monster_magnet").range, 192.0 * 1.2, 0.0001)
	var epic := _world("monster_magnet", 303, false)
	epic.upgrades.apply("monster_magnet_new", epic, "epic")
	assert_eq(epic.loadout.stats("monster_magnet").mob_count, 8, "Bigger Grab: +2 targets")
	epic.loadout.set_rank("monster_magnet", 8)
	for i in 10:
		RF.put_mob(epic, MOB, CASTER_X + 150 + i * 20)
	_tick(epic)
	assert_eq(_pulled(epic).size(), 8, "eight mobs are pulled")
	var unique := _world("monster_magnet", 303, false)
	unique.upgrades.apply("monster_magnet_new", unique, "unique")
	assert_near(unique.loadout.stats("monster_magnet").cooldown, 7.5, 0.0001, "Booster: x0.75")
	var legendary := _world("monster_magnet", 303, false)
	legendary.upgrades.apply("monster_magnet_new", legendary, "legendary")
	assert_near(legendary.loadout.stats("monster_magnet").cooldown, 7.5, 0.0001)
	assert_eq(legendary.loadout.stats("monster_magnet").mob_count, 8)


func test_mastery_after_rank_8_is_never_a_dead_pick_for_either_skill() -> void:
	for key: String in BONUS_STATS:
		var w := _world(key, 303, false)
		w.upgrades.apply(key + "_new", w, "normal")
		w.loadout.set_rank(key, 8)
		var normal := w.upgrades.choice_card(key + "_rank", w)
		var rare := w.upgrades.choice_card(key + "_rank", w, "rare")
		assert_eq(normal.card_kind, "mastery")
		assert_true(BotInput.card_score(w, normal) > 0.0, "%s: Normal Mastery is not dead" % key)
		assert_true(BotInput.card_score(w, rare) > BotInput.card_score(w, normal), key)


# --- Monster Magnet ---------------------------------------------------------------------------------------------------

func _pulled(w: RunWorld) -> Array:
	return w.events.filter(func(e: Dictionary) -> bool: return e.type == "mob_pulled")


func test_magnet_needs_three_mobs_in_range() -> void:
	var w := _world("monster_magnet")
	w.loadout.set_rank("monster_magnet", 8) # prop 100: every candidate is pulled
	RF.put_mob(w, MOB, CASTER_X + 150)
	RF.put_mob(w, MOB, CASTER_X - 150)
	_tick(w)
	assert_eq(w.runner.casts, 0, "two mobs in range do not admit the cast")
	RF.put_mob(w, MOB, CASTER_X + 170)
	_tick(w)
	assert_eq(w.runner.casts, 1, "the third mob admits it")
	assert_eq(_pulled(w).size(), 3)


func test_magnet_ignores_mobs_beyond_its_range_when_counting() -> void:
	var w := _world("monster_magnet")
	for x in [150.0, 170.0]:
		RF.put_mob(w, MOB, CASTER_X + x)
	RF.put_mob(w, MOB, CASTER_X + 600.0)
	_tick(w)
	assert_eq(w.runner.casts, 0, "rank 1 reaches 192 px: the far third mob is not counted")


func test_magnet_range_chance_and_mob_cap_follow_the_mapped_level() -> void:
	for rank in [1, 8]:
		var w := _world("monster_magnet")
		w.loadout.set_rank("monster_magnet", rank)
		var st := w.loadout.stats("monster_magnet")
		assert_eq(st.level, MAGNET_LEVELS[rank - 1])
		assert_eq(st.range, float(160 + 8 * st.level))
		assert_eq(st.mob_count, 6)
		assert_eq(st.pull_chance, float(40 + 2 * st.level))
		assert_eq(st.pull_gap, 60.0)
	var w := _world("monster_magnet")
	w.loadout.set_rank("monster_magnet", 8) # range 400, prop 100: always
	var ids := []
	for i in 8:
		ids.append(RF.put_mob(w, MOB, CASTER_X + 150 + i * 30))
	_tick(w)
	assert_eq(_pulled(w).size(), 6, "the six farthest are pulled")
	assert_false(_pulled(w).any(func(e: Dictionary) -> bool: return e.mob == ids[0] or e.mob == ids[1]),
		"the two nearest keep their place")
	for e: Dictionary in _pulled(w):
		assert_near(w.swarm.x[int(e.mob)], CASTER_X + 60.0, 0.01, "pulled to the 60 px gap")


func test_magnet_pulls_from_both_sides_and_never_bosses_or_flyers() -> void:
	var w := _world("monster_magnet")
	w.loadout.set_rank("monster_magnet", 8)
	var boss := RF.put_mob(w, BOSS, CASTER_X + 300)
	var flyer := RF.put_mob(w, FLYER, CASTER_X + 280)
	w.swarm.fh[flyer] = -1
	var a := RF.put_mob(w, MOB, CASTER_X + 250)
	var b := RF.put_mob(w, MOB, CASTER_X - 250)
	var c := RF.put_mob(w, MOB, CASTER_X + 220)
	var boss_x := float(w.swarm.x[boss])
	var flyer_x := float(w.swarm.x[flyer])
	_tick(w)
	assert_eq(w.runner.casts, 1)
	assert_near(w.swarm.x[boss], boss_x, 0.001, "a boss is never pulled")
	assert_near(w.swarm.x[flyer], flyer_x, 0.001, "a flyer is never pulled")
	assert_near(w.swarm.x[a], CASTER_X + 60.0, 0.01)
	assert_near(w.swarm.x[c], CASTER_X + 60.0, 0.01)
	assert_near(w.swarm.x[b], CASTER_X - 60.0, 0.01)


func test_magnet_deals_no_damage_and_stuns_nothing() -> void:
	var w := _world("monster_magnet")
	var ids := []
	for x in [150.0, 170.0, 180.0]:
		ids.append(RF.put_mob(w, MOB, CASTER_X + x, 190.0, 100.0))
	_tick(w)
	assert_eq(w.runner.casts, 1)
	for m: int in ids:
		assert_eq(w.swarm.hp[m], w.swarm.max_hp[m])
	assert_true(w.events.filter(func(e: Dictionary) -> bool: return e.type == "mob_hit").is_empty())


func test_magnet_cooldown_is_ten_seconds() -> void:
	var w := _world("monster_magnet")
	for x in [150.0, 170.0, 180.0]:
		RF.put_mob(w, MOB, CASTER_X + x)
	_tick(w)
	assert_near(w.runner.cooldowns["monster_magnet"], 10.0, 0.02, "10 s less the tick that cast it")


func test_the_bot_does_not_count_magnet_as_a_reach() -> void:
	# tier C: a damage "none" skill has no reach (SkillRunner.reach_of), so a pull never makes the melee bot hold its distance.
	var w := _world("monster_magnet")
	assert_eq(SkillRunner.reach_of(w.loadout.stats("monster_magnet"), w), 0.0)
	var s := _world("shout")
	assert_true(SkillRunner.reach_of(s.loadout.stats("shout"), s) > 100.0, "Shout reaches its box's far edge")


# --- Text -------------------------------------------------------------------------------------------------------------

func test_magnet_text_says_how_many_monsters_and_from_how_far() -> void:
	var w := _world("monster_magnet")
	w.loadout.set_rank("monster_magnet", 8)
	var text := SkillText.new(w.book, {})
	var line := text.level_line("monster_magnet", w.loadout.stats("monster_magnet").level, w.loadout.stats("monster_magnet"))
	assert_true(line.contains("Pulls up to 6 monsters from 400 px"), line)
	assert_true(line.contains("100% chance"), line)
	w.upgrades.apply("monster_magnet_rank", w, "epic")
	var wider := text.level_line("monster_magnet", 30, w.loadout.stats("monster_magnet"))
	assert_true(wider.contains("Pulls up to 8 monsters"), "Bigger Grab shows in the text: " + wider)


func test_shout_text_shows_damage_targets_stun_chance_and_seconds() -> void:
	var w := _world("shout")
	var line := SkillText.new(w.book, {}).level_line("shout", 5, w.loadout.stats("shout"))
	assert_true(line.contains("up to 6 monsters"), line)
	assert_true(line.contains("50% chance each to stun for 3 sec"), line)


# --- Real cache (SKIPs without it: a SKIP proves nothing) ---------------------------------------------------------------

## A world with the real 111/112 books in place of the synthetic ones.
func _real_world(key: String, lib: AssetLibrary) -> RunWorld:
	var w := _world(key)
	w.book.skill_imgs["111"] = lib.img("Skill.wz/111.img").root
	w.book.skill_imgs["112"] = lib.img("Skill.wz/112.img").root
	return w


func test_real_cache_shout_ranks_map_to_the_eight_levels_and_level_4_still_lacks_prop() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	assert_true(lib.open(AssetCachePaths.resolve_cache_root()))
	var w := _real_world("shout", lib)
	# Tier A literals read from Skill.wz 111.img (H1 #297): rank -> level -> damage, prop, time, mobCount.
	var want := {1: [5, 15, 60, 5], 4: [15, 22, 80, 7], 8: [30, 30, 95, 10]}
	assert_false(w.book.level_node("shout", 4).has("prop"), "the corrupted level 4 has no prop: the override stays needed")
	assert_eq(int(w.book.level_node("shout", 4).get("58", 0)), 38, "its chance sits under the stray key 58")
	var last_prop := 0.0
	for rank in range(1, 9):
		var st := w.loadout.stats("shout", rank)
		assert_eq(st.level, SHOUT_LEVELS[rank - 1], "rank %d" % rank)
		var node := w.book.level_node("shout", st.level)
		assert_true(node.has("prop") and node.has("time") and node.has("damage"), "level %d has every field" % st.level)
		assert_true(float(node.prop) > last_prop, "prop rises with the rank")
		last_prop = float(node.prop)
		assert_eq(st.mob_count, 6)
		assert_true(st.has_box and -st.box.position.x == st.box.end.x, "rank %d: a centred box" % rank)
		if want.has(rank):
			assert_eq(st.level, want[rank][0])
			assert_eq(int(node.damage), want[rank][1], "rank %d damage" % rank)
			assert_eq(int(node.prop), want[rank][2], "rank %d prop" % rank)
			assert_eq(int(node.time), want[rank][3], "rank %d stun seconds" % rank)
	assert_eq(w.loadout.stats("shout", 8).box, Rect2(-200, -150, 400, 300))
	lib.free()


func test_real_cache_magnet_ranks_map_to_the_standard_table() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	assert_true(lib.open(AssetCachePaths.resolve_cache_root()))
	var w := _real_world("monster_magnet", lib)
	var want := {1: [4, 200, 48], 4: [15, 300, 70], 8: [30, 400, 95]}
	for rank in range(1, 9):
		var st := w.loadout.stats("monster_magnet", rank)
		assert_eq(st.level, MAGNET_LEVELS[rank - 1], "rank %d" % rank)
		assert_eq(st.mob_count, 6)
		assert_eq(st.pull_gap, 60.0)
		if want.has(rank):
			assert_eq(st.level, want[rank][0])
			assert_eq(int(st.range), want[rank][1], "rank %d range" % rank)
			assert_eq(int(st.pull_chance), want[rank][2], "rank %d chance" % rank)
	assert_false(w.book.skill_node("monster_magnet").has("action"), "the node names no action: alert2 is our choice")
	lib.free()


func test_real_cache_art_and_sounds_of_both_skills_resolve() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	assert_true(lib.open(AssetCachePaths.resolve_cache_root()))
	for key: String in ["shout", "monster_magnet"]:
		var w := _real_world(key, lib)
		var d := w.book.def(key)
		assert_true(lib.frame(String(d.icon)) != null, key + " icon")
		assert_true(lib.sound(String(d.sounds.use)) != null, key + " Use sound")
		var effect := lib.anim(String(w.loadout.stats(key).effect))
		assert_true(effect != null, key + " effect")
		assert_eq(effect.frames.size(), 17 if key == "shout" else 18, key + " effect frames")
	assert_true(lib.anim("Skill.wz/111.img/skill/1111008/hit/0") != null, "Shout hit burst")
	assert_true(lib.anim("Skill.wz/111.img/skill/1111008/mob") != null, "Shout stun stars")
	lib.free()
