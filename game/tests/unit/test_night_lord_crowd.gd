extends TestCase
## Night Lord's crowd skills (spec #383, ticket NL8 #407): Ninja Storm (a box nova that pushes each struck monster back by
## rank, `knockback.distance_by_rank`) and Ninja Ambush (a damaging ground zone, `ground.strike`, `GroundStrike`), with
## their rarity bonuses. Fixed 1/60 s ticks, seeded RNG, a claw in hand. The behaviour tests run on synthetic book-412 level
## tables shaped like Skill.wz (box, damage, time, prop step at levels 11 and 21 as in the WZ); the real-cache test at the end
## calls require_cache() and SKIPS without the cache.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const CLAW := 1472000
const STORM := "ninja_storm"
const AMBUSH := "ninja_ambush"
const PUSH_BY_RANK := [100.0, 100.0, 200.0, 200.0, 200.0, 300.0, 300.0, 300.0]
const LEVELS := [4, 8, 12, 15, 19, 23, 27, 30]


## Synthetic Skill.wz levels 1..30 of Ninja Storm (damage 42 -> 80, prop 42 -> 100, +-100 / 150 / 200 by (-70, 30)).
func _storm_levels() -> Dictionary:
	var levels := {}
	for lv in range(1, 31):
		var extent := 100.0 if lv <= 10 else 150.0 if lv <= 20 else 200.0
		levels[str(lv)] = {"hs": "h%d" % lv, "damage": roundf(lerpf(42.0, 80.0, (lv - 1) / 29.0)),
			"prop": roundf(lerpf(42.0, 100.0, (lv - 1) / 29.0)), "mobCount": 6.0, "time": 1.0,
			"range": 200.0 if lv == 30 else 150.0,
			"lt": {"$v": [-extent, -70.0]}, "rb": {"$v": [extent, 30.0]}}
	return levels


## Synthetic levels of Ninja Ambush (damage 62 -> 100, time 4 / 8 / 12 s, +-120 / 150 / 200 by (-130, 70), mobCount 6).
func _ambush_levels() -> Dictionary:
	var levels := {}
	for lv in range(1, 31):
		var extent := 120.0 if lv <= 10 else 150.0 if lv <= 20 else 200.0
		levels[str(lv)] = {"hs": "h%d" % lv, "damage": roundf(lerpf(62.0, 100.0, (lv - 1) / 29.0)),
			"mobCount": 6.0, "time": 4.0 if lv <= 10 else 8.0 if lv <= 20 else 12.0,
			"lt": {"$v": [-extent, -130.0]}, "rb": {"$v": [extent, 70.0]}}
	return levels


## A quiet round of a Night Lord holding a claw with `key` learned at `rank_value`; god mode, frozen snail-sized mobs.
func _world(key: String, rank_value := 1, p_seed := 407) -> RunWorld:
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["412"]["playable"] = true # in this test's data only: NL12 ships the flip
	var setup := RF.with_basic_attack(RF.setup("quiet", p_seed, data))
	setup.equipment_info.merge({CLAW: {"incPAD": 22, "attackSpeed": 6, "tuc": 7}}, true)
	for action: String in ["ninjastorm", "alert3", "swingO1"]:
		setup.body_img[action] = {"0": {"delay": 100.0}, "1": {"delay": 100.0}}
	setup.skill_imgs["412"] = {"skill": {
		"4121008": {"weapon": 47, "level": _storm_levels()},
		"4121004": {"level": _ambush_levels()}}}
	setup["job"] = 412
	var w := RunWorld.new(setup)
	RF.place_player(w, 300)
	if w.weapon_id() != CLAW:
		w.wear_new_item(CLAW)
	for mk: MobKind in w.mob_kinds:
		mk.hitbox = Rect2(-20, -50, 40, 50)
		mk.move_speed = 0
	w.god = true
	w.loadout.ranks.clear() # not the start skill: only `key` casts
	w.loadout.order.clear()
	assert_true(w.learn_skill(key), "%s is learnable by a Night Lord" % key)
	w.loadout.set_rank(key, rank_value)
	w.refresh_player_stats()
	w.drain_events()
	return w


func _mob(w: RunWorld, dx: float, boss := false, dy := 0.0) -> int:
	var slot := RF.put_mob(w, 2220000 if boss else 1110100, w.player.pos.x + dx, 190.0 + dy, 100000.0)
	w.swarm.hp[slot] = 100000000
	w.swarm.max_hp[slot] = 100000000
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	return slot


func _hits(events: Array, key: String) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return e.type == "mob_hit" and e.skill == key)


## Runs `ticks` ticks and returns [[time, mob_hit event]...] in order.
func _timed(w: RunWorld, ticks: int, key: String) -> Array:
	var out := []
	for tick in ticks:
		w.step(DT, MoveInput.new())
		for e: Dictionary in _hits(w.drain_events(), key):
			out.append([w.time, e])
	return out


func _mod(w: RunWorld, key: String, stat: String, op: String, value: float) -> void:
	w.loadout.add_skill_mod(key, stat, op, value)


func _struck(hits: Array) -> Dictionary:
	var out := {}
	for pair: Array in hits:
		out[int(pair[1].mob)] = int(out.get(int(pair[1].mob), 0)) + 1
	return out


# --- Ninja Storm ------------------------------------------------------------------------------------------------------

func test_ninja_storm_is_a_box_nova_with_the_claw_stance_and_art() -> void:
	var w := _world(STORM)
	var d := w.book.def(STORM)
	assert_eq(int(d.skill_id), 4121008)
	assert_eq(String(d.book), "412")
	assert_eq(int(d.job), 412)
	assert_eq(String(d.kind), "instant")
	assert_eq(String(d.slot), "active")
	assert_eq(String(d.cast.rule), "box")
	assert_eq(int(d.cast.min_targets), 1)
	assert_eq(String(d.damage), "physical")
	assert_eq(String(d.action), "ninjastorm")
	assert_eq(String(d.effect), "Skill.wz/412.img/skill/4121008/effect")
	assert_eq(String(d.hit), "Skill.wz/412.img/skill/4121008/hit/0")
	assert_eq(String(d.knockback.effect), "Skill.wz/412.img/skill/4121008/mob", "the status art of a pushed monster")
	assert_eq(String(d.sounds.use), "Sound.wz/Skill.img/4121008/Use")
	assert_eq(String(d.sounds.hit), "Sound.wz/Skill.img/4121008/Hit")
	assert_eq(String(d.knockback.chance_field), "prop")
	assert_eq(d.knockback.distance_by_rank, PUSH_BY_RANK)
	assert_false(d.knockback.has("distance"), "the list replaces the scalar")
	assert_false(d.has("weapon_families"), "weapons gate nothing")
	assert_false(d.has("ranks"), "the default 30-level rank table")
	assert_near(w.loadout.stats(STORM).cooldown, 4.0, 0.0001)


func test_ninja_storm_waits_for_a_monster_in_its_box() -> void:
	var w := _world(STORM)
	_mob(w, 150) # box is +-100 at rank 1
	w.step(DT, MoveInput.new())
	assert_eq(w.runner.casts, 0, "min_targets 1: nothing inside the box, no cast")
	_mob(w, 80)
	w.step(DT, MoveInput.new())
	assert_eq(w.runner.casts, 1)
	assert_near(float(w.runner.cooldowns[STORM]), 4.0 - DT, 0.001)


func test_ninja_storm_hits_at_most_six_monsters_nearest_first() -> void:
	var w := _world(STORM, 8)
	var slots := []
	for k in 9:
		slots.append(_mob(w, 20.0 + 15.0 * k))
	var struck := _struck(_timed(w, 5, STORM))
	assert_eq(struck.size(), 6, "mobCount 6")
	for k in 6:
		assert_true(struck.has(slots[k]), "the six nearest to the caster")
		assert_eq(int(struck[slots[k]]), 1, "one line each")


func test_ninja_storm_strikes_both_sides_and_the_box_widens_by_rank() -> void:
	var lo := _world(STORM).loadout
	assert_eq(lo.stats(STORM, 1).box, Rect2(-100, -70, 200, 100), "WZ level 4")
	assert_eq(lo.stats(STORM, 4).box, Rect2(-150, -70, 300, 100), "WZ level 15")
	assert_eq(lo.stats(STORM, 8).box, Rect2(-200, -70, 400, 100), "WZ level 30")
	var w := _world(STORM)
	var left := _mob(w, -90)
	var right := _mob(w, 90)
	var outside := _mob(w, 130)
	var struck := _struck(_timed(w, 5, STORM))
	assert_true(struck.has(left) and struck.has(right))
	assert_false(struck.has(outside), "past the +-100 box of rank 1")


func test_the_resolved_push_distance_is_100_200_300_by_rank() -> void:
	var lo := _world(STORM).loadout
	for r in range(1, 9):
		assert_eq(lo.stats(STORM, r).knockback_distance, float(PUSH_BY_RANK[r - 1]), "rank %d" % r)


func test_a_monster_is_pushed_away_from_the_caster_on_either_side() -> void:
	for side in [-1, 1]:
		var pushed := _world(STORM, 8)
		var plain := _world(STORM, 8)
		plain.book.defs[STORM].erase("knockback")
		plain.loadout.version += 1
		var a := _mob(pushed, 60.0 * side)
		var b := _mob(plain, 60.0 * side)
		_timed(pushed, 5, STORM)
		_timed(plain, 5, STORM)
		assert_near(pushed.swarm.x[a] - plain.swarm.x[b], 300.0 * side, 1.5, "side %d" % side)


func _push_delta(r: int, seed_value: int) -> float:
	var pushed := _world(STORM, r, seed_value)
	var plain := _world(STORM, r, seed_value)
	plain.book.defs[STORM].erase("knockback")
	plain.loadout.version += 1
	var a := _mob(pushed, 40.0)
	var b := _mob(plain, 40.0)
	_timed(pushed, 5, STORM)
	_timed(plain, 5, STORM)
	return pushed.swarm.x[a] - plain.swarm.x[b]


func test_a_pushed_monster_moves_the_rank_distance_whenever_the_chance_rolls() -> void:
	# At rank 1 the chance is 48%: over many seeds every observed shove is exactly 100 px, and both outcomes occur.
	for r: int in [1, 4, 8]:
		var moved := 0
		var still := 0
		for s in 24:
			var delta := _push_delta(r, 500 + s)
			if absf(delta) < 1.5:
				still += 1
			else:
				moved += 1
				assert_near(delta, float(PUSH_BY_RANK[r - 1]), 1.5, "rank %d seed %d" % [r, 500 + s])
		if r == 8:
			assert_eq(still, 0, "prop 100: every monster is pushed")
		else:
			assert_true(moved > 0 and still > 0, "rank %d: a chance below 100 both pushes and spares (%d / %d)" % [r, moved, still])


func test_ninja_storm_damages_a_boss_but_never_moves_it() -> void:
	var pushed := _world(STORM, 8)
	var plain := _world(STORM, 8)
	plain.book.defs[STORM].erase("knockback")
	plain.loadout.version += 1
	var boss := {}
	var other := {}
	for w: RunWorld in [pushed, plain]:
		other[w] = _mob(w, 60)
		boss[w] = _mob(w, 120, true)
		assert_true(_struck(_timed(w, 5, STORM)).has(boss[w]), "the boss is struck")
	assert_eq(pushed.swarm.x[boss[pushed]], plain.swarm.x[boss[plain]], "the boss is not pushed")
	assert_near(pushed.swarm.x[other[pushed]] - plain.swarm.x[other[plain]], 300.0, 1.5, "while the monster beside it is")


func test_ninja_storm_rolls_stream_one_once_per_struck_non_boss() -> void:
	var with_push := _world(STORM, 8)
	var without := _world(STORM, 8)
	without.book.defs[STORM].erase("knockback")
	without.loadout.version += 1
	for w: RunWorld in [with_push, without]:
		_mob(w, 40)
		_mob(w, 70)
		_mob(w, 90, true) # a boss: damaged, no roll
		_mob(w, 20)
		_timed(w, 5, STORM)
	var reference := RandomNumberGenerator.new()
	reference.state = without.rng.state
	for k in 3:
		reference.randf()
	assert_eq(with_push.rng.state, reference.state, "three non-boss pushes, three draws; the boss drew none")


func test_ninja_storm_shows_the_status_art_on_each_pushed_monster() -> void:
	var w := _world(STORM, 8)
	var a := _mob(w, 40)
	var b := _mob(w, -60)
	_mob(w, 90, true)
	var seen := {}
	for tick in 5:
		w.step(DT, MoveInput.new())
		for e: Dictionary in w.drain_events():
			if e.type == "skill_mob_effect" and e.skill == STORM:
				seen[int(e.mob)] = String(e.effect)
	assert_eq(seen.size(), 2, "the two pushed monsters and not the boss")
	assert_eq(String(seen[a]), "Skill.wz/412.img/skill/4121008/mob")
	assert_true(seen.has(b))


func test_wide_storm_widens_the_box_and_second_wave_adds_a_line() -> void:
	var plain := _world(STORM)
	var wide := _world(STORM)
	_mod(wide, STORM, "area", "mul", 1.2)
	for w: RunWorld in [plain, wide]:
		_mob(w, 50)
	var edge_plain := _mob(plain, 125) # the body (+-20 px) starts at 105: past +-100, inside +-120
	var edge_wide := _mob(wide, 125)
	assert_near(wide.loadout.stats(STORM).box.size.x, 240.0, 0.01)
	assert_false(_struck(_timed(plain, 5, STORM)).has(edge_plain), "past the +-100 box")
	assert_true(_struck(_timed(wide, 5, STORM)).has(edge_wide), "inside +-120")
	var base := _world(STORM)
	var second := _world(STORM)
	_mod(second, STORM, "attack_count", "add", 1)
	for w: RunWorld in [base, second]:
		_mob(w, 50)
		_mob(w, -50)
	assert_eq(_timed(base, 5, STORM).size(), 2)
	assert_eq(_timed(second, 5, STORM).size(), 4, "a second line on each")


func test_the_skill_window_names_the_push_by_rank() -> void:
	var w := _world(STORM)
	var text := SkillText.new(w.book)
	for row: Array in [[1, 4, 48, 100], [4, 15, 70, 200], [8, 30, 100, 300]]:
		var line := text.level_line(STORM, int(row[1]), w.loadout.stats(STORM, int(row[0])))
		assert_true(line.contains("Knock-back: %d%% / %d px" % [int(row[2]), int(row[3])]), line)


# --- Ninja Ambush -----------------------------------------------------------------------------------------------------

func test_ninja_ambush_is_a_box_cast_that_leaves_a_strike_zone() -> void:
	var w := _world(AMBUSH)
	var d := w.book.def(AMBUSH)
	assert_eq(int(d.skill_id), 4121004)
	assert_eq(String(d.kind), "instant")
	assert_eq(String(d.cast.rule), "box")
	assert_eq(int(d.cast.min_targets), 1)
	assert_eq(String(d.damage), "physical")
	assert_eq(d.ground, {"strike": {"interval": 1.0, "first_delay": 0.3}})
	assert_eq(String(d.action), "alert3")
	assert_eq(String(d.effect), "Skill.wz/412.img/skill/4121004/effect")
	assert_eq(String(d.hit), "Skill.wz/412.img/skill/4121004/mob0", "the ninja that strikes each monster")
	assert_eq(String(d.sounds.use), "Sound.wz/Skill.img/4121004/Use")
	assert_false(d.has("knockback"))
	assert_false(d.has("weapon_families"))
	assert_false(d.has("ranks"))
	assert_near(w.loadout.stats(AMBUSH).cooldown, 14.0, 0.0001)
	_mob(w, 80)
	w.step(DT, MoveInput.new())
	assert_eq(w.runner.casts, 1)
	assert_near(float(w.runner.cooldowns[AMBUSH]), 14.0 - DT, 0.001)


func test_ninja_ambush_needs_a_monster_in_the_box() -> void:
	var w := _world(AMBUSH)
	_mob(w, 300) # box +-120
	w.step(DT, MoveInput.new())
	assert_eq(w.runner.casts, 0)
	_mob(w, 100)
	w.step(DT, MoveInput.new())
	assert_eq(w.runner.casts, 1)


func test_the_first_strike_lands_0_3_s_after_the_cast_then_every_second() -> void:
	var w := _world(AMBUSH)
	var m := _mob(w, 80)
	w.step(DT, MoveInput.new()) # the cast
	var cast_at := w.time
	assert_true(_hits(w.drain_events(), AMBUSH).is_empty(), "nothing is struck on the cast tick")
	var hits := _timed(w, 330, AMBUSH)
	assert_eq(hits.size(), 4, "4 strikes in a 4 s zone")
	var expect := [0.3, 1.3, 2.3, 3.3]
	for k in 4:
		assert_near(float(hits[k][0]) - cast_at, float(expect[k]), DT * 1.5, "strike %d" % k)
		assert_eq(int(hits[k][1].mob), m)
		assert_eq(String(hits[k][1].hit_visual), "Skill.wz/412.img/skill/4121004/mob0", "the ninja art rides each hit")


func test_the_zone_lives_four_eight_and_twelve_seconds_by_rank() -> void:
	for row: Array in [[1, 4], [4, 8], [8, 12]]:
		var w := _world(AMBUSH, int(row[0]))
		_mob(w, 80)
		var hits := _timed(w, int(13.5 / DT), AMBUSH)
		assert_eq(hits.size(), int(row[1]), "rank %d: %d strikes" % [int(row[0]), int(row[1])])
		assert_eq(w.runner.casts, 1, "the 14 s cooldown never lets it overlap itself")
		assert_eq(w.loadout.stats(AMBUSH).mob_count, 6)


func test_each_strike_is_one_ordinary_hit_on_the_six_nearest_to_the_anchor() -> void:
	var w := _world(AMBUSH, 8)
	var slots := []
	for k in 9:
		slots.append(_mob(w, 20.0 + 15.0 * k))
	var hits := _timed(w, 60, AMBUSH) # the first strike only
	var struck := _struck(hits)
	assert_eq(hits.size(), 6, "mobCount 6: one hit each")
	assert_eq(struck.size(), 6)
	for k in 6:
		assert_true(struck.has(slots[k]), "the six nearest to the anchor")


func test_the_zone_is_anchored_where_the_caster_stood() -> void:
	var w := _world(AMBUSH)
	var near := _mob(w, 80)
	w.step(DT, MoveInput.new())
	w.drain_events()
	w.player.pos.x += 900.0 # the caster walks away: the zone stays
	var far := _mob(w, 80)
	var struck := _struck(_timed(w, 100, AMBUSH))
	assert_true(struck.has(near), "the monster inside the anchored box is struck")
	assert_false(struck.has(far), "the one beside the caster's new position is not")


func test_a_monster_that_leaves_or_dies_is_not_struck() -> void:
	var w := _world(AMBUSH, 8)
	var leaver := _mob(w, 60)
	var dier := _mob(w, 70)
	var stayer := _mob(w, 80)
	w.step(DT, MoveInput.new())
	w.drain_events()
	var first := _struck(_timed(w, 24, AMBUSH)) # through the 0.3 s strike
	assert_eq(first.size(), 3)
	w.swarm.x[leaver] = 1700.0 # out of the 400 px box
	w.swarm.apply_hit(dier, 1.0e9, 1)
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	var later := _struck(_timed(w, 70, AMBUSH)) # through the 1.3 s strike
	assert_eq(later.size(), 1, "only the monster still inside is struck")
	assert_true(later.has(stayer))


func test_ambush_squad_adds_two_monsters_and_area_widens_the_box() -> void:
	var plain := _world(AMBUSH)
	var squad := _world(AMBUSH)
	_mod(squad, AMBUSH, "count", "add", 2)
	for w: RunWorld in [plain, squad]:
		for k in 9:
			_mob(w, 10.0 + 12.0 * k)
	assert_eq(squad.loadout.stats(AMBUSH).mob_count, 8)
	assert_eq(_struck(_timed(plain, 60, AMBUSH)).size(), 6)
	assert_eq(_struck(_timed(squad, 60, AMBUSH)).size(), 8, "two more monsters per strike")
	var narrow := _world(AMBUSH)
	var wide := _world(AMBUSH)
	_mod(wide, AMBUSH, "area", "mul", 1.2)
	_mob(narrow, 60)
	_mob(wide, 60)
	var edge_narrow := _mob(narrow, 145) # the body starts at 125: past +-120, inside +-144
	var edge_wide := _mob(wide, 145)
	assert_near(wide.loadout.stats(AMBUSH).box.size.x, 288.0, 0.01)
	assert_false(_struck(_timed(narrow, 60, AMBUSH)).has(edge_narrow))
	assert_true(_struck(_timed(wide, 60, AMBUSH)).has(edge_wide))


func test_a_second_cast_makes_a_second_zone() -> void:
	var w := _world(AMBUSH)
	var m := _mob(w, 80)
	w.step(DT, MoveInput.new())
	w.drain_events()
	for tick in 30:
		w.step(DT, MoveInput.new())
	w.drain_events()
	w.runner.cooldowns[AMBUSH] = 0.0 # the 14 s cooldown is a tier C lever; a second cast is what is tested
	w.step(DT, MoveInput.new())
	assert_eq(w.runner.casts, 2)
	w.drain_events()
	var hits := _timed(w, 150, AMBUSH)
	var per_tick := {}
	for pair: Array in hits:
		per_tick[snappedf(float(pair[0]), 0.001)] = int(per_tick.get(snappedf(float(pair[0]), 0.001), 0)) + 1
	assert_true(hits.size() > 0)
	assert_true(_struck(hits).has(m))
	# both zones are alive: over 2.5 s the monster is struck by two clocks, offset by about half a second
	assert_true(hits.size() >= 4, "two interleaved clocks, got %d" % hits.size())


func test_map_transfer_and_clear_drop_the_zones() -> void:
	var w := _world(AMBUSH)
	_mob(w, 80)
	w.step(DT, MoveInput.new())
	w.drain_events()
	w.runner.clear_pending(w) # what advance_map and a stage clear call
	assert_true(_timed(w, 300, AMBUSH).is_empty(), "no strike after the zones are cleared")


func test_ambush_damage_scales_by_rank_and_with_the_damage_bonus() -> void:
	var lo := _world(AMBUSH).loadout
	assert_true(lo.stats(AMBUSH, 8).damage_pct > lo.stats(AMBUSH, 4).damage_pct)
	assert_true(lo.stats(AMBUSH, 4).damage_pct > lo.stats(AMBUSH, 1).damage_pct)
	assert_eq(lo.stats(AMBUSH, 1).box, Rect2(-120, -130, 240, 200))
	assert_eq(lo.stats(AMBUSH, 8).box, Rect2(-200, -130, 400, 200))
	var base := _world(AMBUSH, 8)
	var strong := _world(AMBUSH, 8)
	_mod(strong, AMBUSH, "damage", "mul", 1.2)
	var totals := []
	for w: RunWorld in [base, strong]:
		_mob(w, 80)
		var sum := 0.0
		for pair: Array in _timed(w, 60, AMBUSH):
			sum += float(pair[1].damage)
		totals.append(sum)
	assert_true(totals[1] > totals[0])


func test_the_skill_window_names_the_zone() -> void:
	var w := _world(AMBUSH)
	var text := SkillText.new(w.book)
	for row: Array in [[1, 4, 4], [4, 15, 8], [8, 30, 12]]:
		var line := text.level_line(AMBUSH, int(row[1]), w.loadout.stats(AMBUSH, int(row[0])))
		assert_true(line.contains("Strikes up to 6 monsters every 1 s for %d s" % int(row[2])), line)


func test_the_zone_event_carries_no_tile_art() -> void:
	var w := _world(AMBUSH)
	_mob(w, 80)
	w.step(DT, MoveInput.new())
	var zone := w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "skill_ground")
	assert_eq(zone.size(), 1)
	assert_eq(String(zone[0].effect), "", "no tile: the effect plays once at the cast, the strikes bring their own ninjas")
	assert_eq(float(zone[0].duration), 4.0)


# --- both skills: rarity tables ---------------------------------------------------------------------------------------

const RARITY := {
	STORM: [["ninja_arts", "damage", "mul", 1.2], ["wide_storm", "area", "mul", 1.2], ["second_wave", "attack_count", "add", 1.0]],
	AMBUSH: [["ninja_arts", "damage", "mul", 1.2], ["wide_ambush", "area", "mul", 1.2], ["ambush_squad", "count", "add", 2.0]],
}


func test_the_rarity_tables_follow_the_spec() -> void:
	var w := _world(STORM)
	for key: String in RARITY:
		var bonuses: Dictionary = w.book.def(key).rarity_bonuses
		var rows: Array = RARITY[key]
		for t in 3:
			var tier: String = ["rare", "epic", "unique"][t]
			assert_eq(bonuses[tier].size(), 1, "%s %s" % [key, tier])
			assert_eq(String(bonuses[tier][0].id), String(rows[t][0]), "%s %s" % [key, tier])
			assert_true(String(bonuses[tier][0].text) != "", "%s %s has card text" % [key, tier])
			assert_eq(bonuses[tier][0].effects.size(), 1)
			var effect: Dictionary = bonuses[tier][0].effects[0]
			assert_eq(String(effect.stat), String(rows[t][1]))
			assert_eq(String(effect.op), String(rows[t][2]))
			assert_near(float(effect.value), float(rows[t][3]), 0.0001)
		var legendary: Dictionary = bonuses.legendary[0]
		assert_eq(String(legendary.id), String(rows[2][0]), "%s: Legendary shares the Unique's id (and its repeat counter)" % key)
		assert_eq(legendary.effects.size(), 2)
		assert_eq(String(legendary.effects[0].stat), String(rows[2][1]))
		assert_near(float(legendary.effects[0].value), float(rows[2][3]), 0.0001)
		assert_eq(String(legendary.effects[1].stat), "damage")
		assert_near(float(legendary.effects[1].value), 1.2, 0.0001)
		assert_eq(bonuses.keys().size(), 4, "%s: exactly the four tiers" % key)


## What a cast of `key` did in the field below: the total damage, the hit lines, the monsters struck and whether the far
## monster (just beyond the base box) was struck; `effects` are applied as skill modifiers first.
func _probe(key: String, effects: Array) -> Dictionary:
	var w := _world(key, 8)
	for effect: Dictionary in effects:
		_mod(w, key, String(effect.stat), String(effect.op), float(effect.value))
	var reach := 200.0 # rank 8: +-200 for both skills
	# Three monsters well inside the box (the cap of six would otherwise crowd the edge one out), ten when `count` is probed.
	var crowd := 10 if effects.any(func(e: Dictionary) -> bool: return String(e.stat) == "count") else 3
	for k in crowd:
		_mob(w, 10.0 + 10.0 * k)
	var edge := _mob(w, reach + 25.0) # the body starts at reach + 5: outside the base box, inside x1.2
	var hits := _timed(w, 64 if key == AMBUSH else 6, key)
	var dealt := 0.0
	for pair: Array in hits:
		dealt += float(pair[1].damage)
	var struck := _struck(hits)
	return {"dealt": dealt, "lines": hits.size(), "mobs": struck.size(), "edge": struck.has(edge)}


func test_every_bonus_changes_the_resolved_cast() -> void:
	var skills := _world(STORM).book
	for key: String in RARITY:
		var bonuses: Dictionary = skills.def(key).rarity_bonuses
		var base := _probe(key, [])
		for tier: String in ["rare", "epic", "unique", "legendary"]:
			for effect: Dictionary in bonuses[tier][0].effects:
				var with_effect := _probe(key, [effect])
				var label := "%s %s %s" % [key, tier, String(effect.stat)]
				match String(effect.stat):
					"damage":
						assert_true(float(with_effect.dealt) > float(base.dealt), label)
					"area":
						assert_false(bool(base.edge), label + ": the edge monster is outside the base box")
						assert_true(bool(with_effect.edge), label)
					"attack_count":
						assert_true(int(with_effect.lines) > int(base.lines), label)
					"count":
						assert_true(int(with_effect.mobs) > int(base.mobs), label)
					_:
						assert_true(false, label + ": unprobed stat")


func test_a_rare_or_better_card_adds_one_rank_plus_its_bonus() -> void:
	for key: String in RARITY:
		for tier: String in ["rare", "epic", "unique", "legendary"]:
			var w := _world(key)
			var card := w.upgrades.choice_card(key + "_rank", w, tier)
			assert_false(card.get("rarity_bonus", {}).is_empty(), "%s %s carries a bonus" % [key, tier])
			w.upgrades.apply(key + "_rank", w, tier)
			assert_eq(w.loadout.rank(key), 2, "%s %s: one rank, whatever the rarity" % [key, tier])
			var st := w.loadout.stats(key)
			match tier:
				"rare":
					assert_near(w.loadout.skill_stat(key, "damage", 1.0), 1.2, 0.0001)
				"epic":
					assert_near(st.area, 1.2, 0.0001)
				"unique", "legendary":
					if key == STORM:
						assert_eq(st.attack_count, 2)
					else:
						assert_eq(st.mob_count, 8)
					assert_near(w.loadout.skill_stat(key, "damage", 1.0), 1.2 if tier == "legendary" else 1.0, 0.0001)


func test_legendary_shares_the_uniques_counter_and_mastery_repeats_shrink() -> void:
	for key: String in RARITY:
		var w := _world(key)
		var unique_id: String = RARITY[key][2][0]
		w.upgrades.apply(key + "_rank", w, "unique")
		w.upgrades.apply(key + "_rank", w, "legendary")
		assert_eq(int(w.loadout.card_ranks["bonus:%s:%s" % [key, unique_id]]), 2, "%s: one shared counter" % key)
		var m := _world(key)
		m.loadout.set_rank(key, 8)
		var c := m.upgrades.choice_card(key + "_rank", m, "rare")
		assert_eq(c.card_kind, "mastery", "%s: at rank 8 the rank card is a Mastery card" % key)
		m.upgrades.apply(key + "_rank", m, "rare")
		m.upgrades.apply(key + "_rank", m, "rare")
		assert_near(m.loadout.skill_stat(key, "damage", 1.0), 1.2 * (1.0 + 0.2 * 0.8), 0.00001, "%s: the repeat is x0.8" % key)
		assert_eq(m.loadout.rank(key), 8)


func test_only_these_skills_use_the_new_blocks_and_poison_mist_is_untouched() -> void:
	var skills: Dictionary = DataRepo.load_all().skills.skills
	for key: String in skills:
		var d: Dictionary = skills[key]
		if d.has("ground") and d.ground.has("strike"):
			assert_true(key in [AMBUSH], "%s: only Ninja Ambush (and later Shadower's copy) strikes" % key)
		if d.has("knockback") and d.knockback.has("distance_by_rank"):
			assert_eq(key, STORM)
	var mist: Dictionary = skills.poison_mist.ground
	assert_eq(mist.status, "poison")
	assert_eq(float(mist.interval), 1.0)
	assert_false(mist.has("strike"))
	assert_eq(float(skills.dragons_breath.knockback.distance), 180.0, "scalar knock-backs keep their distance")


# --- real cache: all eight ranks against Skill.wz ----------------------------------------------------------------------

func test_real_cache_all_eight_ranks_map_to_the_skill_wz_levels() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	assert_true(lib.open())
	var img := lib.img("Skill.wz/412.img")
	assert_true(img != null, "Skill.wz/412.img is in the cache")
	if img == null:
		lib.free()
		return
	var book := SkillBook.from_data(DataRepo.load_all().skills, {"412": img.root})
	var lo := Loadout.new(book)
	lo.weapon_family = "claw"
	var node_of := {STORM: img.root.skill["4121008"], AMBUSH: img.root.skill["4121004"]}
	for key: String in node_of:
		assert_eq(book.max_level(key), 30, key)
		assert_eq(book.max_rank(key), 8, key)
		for rank_value in range(1, 9):
			var lv: int = LEVELS[rank_value - 1]
			var label := "%s rank %d (level %d)" % [key, rank_value, lv]
			assert_eq(book.canonical_level(key, rank_value), lv, label)
			var level: Dictionary = node_of[key].level[str(lv)]
			var st := lo.stats(key, rank_value)
			assert_eq(int(st.level), lv, label)
			assert_near(st.damage_pct, float(level.damage) / 100.0, 0.000001, label)
			var lt: Array = level.lt["$v"]
			var rb: Array = level.rb["$v"]
			assert_eq(st.box, Rect2(float(lt[0]), float(lt[1]), float(rb[0]) - float(lt[0]), float(rb[1]) - float(lt[1])), label)
			assert_eq(st.mob_count, int(level.mobCount), label)
			assert_eq(st.mob_count, 6, label)
			assert_eq(st.attack_count, 1, label)
			if key == STORM:
				assert_eq(st.knockback_chance, float(level.prop), label)
				assert_eq(st.knockback_distance, float(PUSH_BY_RANK[rank_value - 1]), label)
			else:
				assert_eq(book.canonical(key, lv, "time"), float(level.time), label)
	# The spec's worked rank values (rank 1 / 4 / 8) as literals.
	for i in 3:
		var r: int = [1, 4, 8][i]
		assert_near(lo.stats(STORM, r).damage_pct, [0.48, 0.65, 0.80][i], 0.000001, "Ninja Storm damage rank %d" % r)
		assert_eq(lo.stats(STORM, r).knockback_chance, [48.0, 70.0, 100.0][i], "Ninja Storm push chance rank %d" % r)
		assert_eq(lo.stats(STORM, r).knockback_distance, [100.0, 200.0, 300.0][i], "Ninja Storm push rank %d" % r)
		assert_eq(lo.stats(STORM, r).box.size.x, [200.0, 300.0, 400.0][i], "Ninja Storm box rank %d" % r)
		assert_near(lo.stats(AMBUSH, r).damage_pct, [0.68, 0.85, 1.00][i], 0.000001, "Ninja Ambush damage rank %d" % r)
		assert_eq(lo.stats(AMBUSH, r).box.size.x, [240.0, 300.0, 400.0][i], "Ninja Ambush box rank %d" % r)
		assert_eq(book.canonical(AMBUSH, int(LEVELS[[0, 3, 7][i]]), "time"), [4.0, 8.0, 12.0][i], "Ninja Ambush time rank %d" % r)
	# Art and sounds resolve in the cache.
	for key: String in node_of:
		var d := book.def(key)
		var paths: Array = [d.effect, d.ball, d.hit, String(d.get("knockback", {}).get("effect", "")), String(d.get("ground", {}).get("tile", ""))]
		for path: String in paths:
			if path != "":
				assert_true(lib.anim(path).frames.size() > 0, path)
		for path: String in d.sounds.values():
			if path != "":
				assert_true(lib.sound(path) != null, path)
	assert_true(lib.missing.is_empty(), str(lib.missing))
	lib.free()
