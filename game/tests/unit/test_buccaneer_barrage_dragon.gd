extends TestCase
## Barrage (5121007) and Dragon Strike (5121001) of the `buccaneer` line (spec #412, ticket B8 #420, GAME_DESIGN 7.93), plus
## the `bot.reach` data key they introduce. Synthetic WZ-shaped book 512 (`book_node`, with the real values at the eight mapped
## levels 4/8/12/15/19/23/27/30) cast through RunWorld on a flat ground, seeded and fixed-tick; the original-table checks at the
## end use the private asset cache and SKIP without it (a SKIP proves nothing).

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const MOB := 1110100
const KNUCKLE := 1482000
const LEVELS := [4, 8, 12, 15, 19, 23, 27, 30]
const BARRAGE_DAMAGE := [106, 122, 148, 160, 176, 202, 218, 230]
const DRAGON_DAMAGE := [320, 380, 490, 535, 595, 705, 765, 810]
const DRAGON_MOBS := [4, 4, 5, 5, 5, 6, 6, 6]
const FLAT := [{"x1": 0, "y1": 200, "x2": 4000, "y2": 200}]
const BASE := "Skill.wz/512.img/skill/"


## The 512 fixture book: the real damage (and Dragon Strike's mobCount) at the eight mapped levels, a filler row elsewhere.
static func book_node() -> Dictionary:
	return preload("res://tests/fixtures/buccaneer_barrage_dragon_book.gd").book_node()


func _data() -> Dictionary:
	return DataRepo.load_all()


func _defining_lines(key: String) -> Array:
	var out := []
	for line: String in DataRepo.lines():
		var path := DataRepo.fragment_path("skills", line)
		if FileAccess.file_exists(path) and DataRepo.load_json(path).get("skills", {}).has(key):
			out.append(line)
	return out


## A 512 round on a flat ground (y = 200 in the fixture) facing right (or `facing`), holding a knuckle, knowing only `key` at
## `rank`; mobs are 1 px wide and still. Job 512 is made playable in the data copy only (B11 ships the flip).
func _world(key: String, rank := 1, facing := 1) -> RunWorld:
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["512"]["playable"] = true
	data.balance.magnet_radius = 0
	var setup := RF.with_basic_attack(RF.setup("quiet", 420, data))
	setup.equipment_info[KNUCKLE] = {"incPAD": 18, "attackSpeed": 5, "tuc": 7, "afterImage": "mace", "sfx": "mace"}
	setup.skill_imgs["512"] = book_node()
	var w := RunWorld.new(setup)
	w.set_job(512)
	if w.weapon_id() != KNUCKLE:
		w.wear_new_item(KNUCKLE)
	w.progression.level = 30
	for mk: MobKind in w.mob_kinds:
		mk.hitbox = Rect2(-0.5, -10, 1, 10)
		mk.move_speed = 0.0
	w.bounds = Rect2(0, -500, 4000, 1000)
	w.fhm = FootholdMap.from_segments(FLAT)
	w.swarm.fhm = w.fhm
	RF.place_player(w, 2000.0)
	w.player.facing = facing
	w.update_view()
	w.god = true
	w.loadout.ranks.clear()
	w.loadout.order.clear()
	assert_true(w.learn_skill(key), "learn " + key)
	w.loadout.set_rank(key, rank)
	w.refresh_player_stats()
	w.drain_events()
	return w


func _mob(w: RunWorld, dx: float) -> int:
	return RF.put_mob(w, MOB, w.player.pos.x + dx, 190.0, 100000.0)


## Runs one tick and returns its events (the grid is rebuilt first, as the run does).
func _tick(w: RunWorld) -> Array:
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	w.runner.step(DT, w)
	w.time += DT
	return w.drain_events()


func _hits(events: Array) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return e.type == "mob_hit")


## Every mob_hit of `seconds` of ticks as [tick index, event].
func _run(w: RunWorld, seconds: float) -> Array:
	var out := []
	for t in int(ceil(seconds / DT)):
		for e: Dictionary in _hits(_tick(w)):
			out.append([t, e])
	return out


# --- placement and data -------------------------------------------------------------------------------------------------------

func test_both_skills_are_defined_in_the_buccaneer_line_only() -> void:
	var skills: Dictionary = _data().skills.skills
	for pair in [["barrage", 5121007], ["dragon_strike", 5121001]]:
		var key: String = pair[0]
		assert_eq(_defining_lines(key), ["buccaneer"], key)
		assert_eq(int(skills[key].skill_id), pair[1], key)
		assert_eq(String(skills[key].book), "512", key)
		assert_eq(int(skills[key].job), 512, key)
		assert_eq(String(skills[key].slot), "active", key)
		assert_false(skills[key].has("weapon_families"), key + " has no weapon gate")
		assert_false(skills[key].has("ranks"), key + " uses the default level-30 table")
		assert_true(String(skills[key]._tier).contains("Tier C"), key + " notes its tier C choices")


func test_cadence_holds_and_actions_are_the_spec_values() -> void:
	var w := _world("barrage")
	var st := w.loadout.stats("barrage")
	assert_near(float(st.cooldown), 1.2, 1e-9, "Barrage cooldown")
	assert_eq(String(st.action), "fist")
	assert_near(float(st.action_time), 0.9, 1e-9, "Barrage hold")
	var d := _world("dragon_strike").loadout.stats("dragon_strike")
	assert_near(float(d.cooldown), 4.8, 1e-9, "Dragon Strike cooldown")
	assert_eq(String(d.action), "dragonstrike")
	assert_near(float(d.action_time), 0.8, 1e-9, "Dragon Strike hold")


func test_the_default_level_30_table_reads_levels_4_to_30_for_both() -> void:
	var w := _world("barrage")
	for key in ["barrage", "dragon_strike"]:
		assert_eq(w.book.max_level(key), 30, key)
		assert_eq(w.book.max_rank(key), 8, key)
		for r in range(1, 9):
			assert_eq(w.book.canonical_level(key, r), LEVELS[r - 1], "%s rank %d" % [key, r])


# --- Barrage ------------------------------------------------------------------------------------------------------------------

func test_barrage_damage_is_106_160_230_percent_at_ranks_1_4_8_with_six_lines_on_one_target() -> void:
	var w := _world("barrage")
	for i in 3:
		var r: int = [1, 4, 8][i]
		var st := w.loadout.stats("barrage", r)
		assert_near(st.damage_pct, [1.06, 1.60, 2.30][i], 1e-9, "damage at rank %d" % r)
		assert_eq(st.attack_count, 6, "six lines at rank %d" % r)
		assert_eq(SkillRunner.strike_count(st), 1, "one target at rank %d" % r)


func test_barrage_lands_six_lines_on_the_one_nearest_mob_and_none_on_a_second() -> void:
	for r in [1, 8]:
		var w := _world("barrage", r)
		var near := _mob(w, 60.0)
		var other := _mob(w, 75.0)
		var events := _tick(w)
		var hits := _hits(events)
		assert_eq(hits.size(), 6, "rank %d: six lines" % r)
		assert_eq(hits.filter(func(e: Dictionary) -> bool: return int(e.mob) == near).size(), 6, "all on the nearest mob")
		assert_eq(hits.filter(func(e: Dictionary) -> bool: return int(e.mob) == other).size(), 0, "none on the other")
		assert_eq(events.filter(func(e: Dictionary) -> bool: return e.type == "cast").size(), 1)


func test_barrage_needs_a_mob_inside_the_knuckles_reach() -> void:
	var w := _world("barrage")
	_mob(w, 400.0)
	assert_eq(_tick(w).filter(func(e: Dictionary) -> bool: return e.type == "cast").size(), 0, "400 px is far out of reach")
	var behind := _world("barrage")
	_mob(behind, -40.0)
	assert_eq(_hits(_tick(behind)).size(), 6, "the weapon-reach rule turns toward a mob behind it")


func test_barrage_shows_the_four_jab_set_then_the_two_finisher_sets_on_its_six_lines() -> void:
	var w := _world("barrage")
	_mob(w, 50.0)
	var paths := _hits(_tick(w)).map(func(e: Dictionary) -> String: return String(e.hit_visual))
	assert_eq(paths, [BASE + "5121007/hit/0", "", "", "", BASE + "5121007/hit0/0", BASE + "5121007/hit1/0"],
		"hit/0 already holds four jabs: it plays once; hit0 and hit1 are the fifth and sixth lines")


func test_barrage_cadence_is_1_2_seconds() -> void:
	var w := _world("barrage", 8)
	var slot := _mob(w, 40.0)
	var x0: float = w.swarm.x[slot]
	for t in int(6.0 / DT):
		w.step(DT, MoveInput.new())
		w.swarm.hp[slot] = w.swarm.max_hp[slot]
		w.swarm.x[slot] = x0
	assert_true(w.runner.casts >= 5 and w.runner.casts <= 6, "1.2 s cadence: %d casts in 6 s" % w.runner.casts)


func test_barrage_rarity_bonuses_each_change_a_resolved_stat() -> void:
	var d: Dictionary = _data().skills.skills.barrage
	var want := {"rare": ["mastery", [["damage", "mul", 1.2]]], "epic": ["booster", [["cooldown", "mul", 0.88]]],
		"unique": ["endless", [["attack_count", "add", 2.0]]],
		"legendary": ["endless", [["attack_count", "add", 2.0], ["damage", "mul", 1.2]]]}
	for tier: String in want:
		var list: Array = d.rarity_bonuses[tier]
		assert_eq(list.size(), 1, tier)
		assert_eq(String(list[0].id), want[tier][0], tier)
		assert_eq((list[0].effects as Array).map(func(e: Dictionary) -> Array: return [e.stat, e.op, float(e.value)]), want[tier][1], tier)
	assert_eq(String(d.rarity_bonuses.unique[0].text), "Endless Barrage")
	var w := _world("barrage")
	var base := w.loadout.stats("barrage")
	w.loadout.add_skill_mod("barrage", "attack_count", "add", 2.0)
	assert_eq(w.loadout.stats("barrage").attack_count, 8, "Endless Barrage: +2 lines")
	w.loadout.add_skill_mod("barrage", "damage", "mul", 1.2)
	assert_near(w.loadout.stats("barrage").damage_max, base.damage_max * 1.2, 1e-6)
	w.loadout.add_skill_mod("barrage", "cooldown", "mul", 0.88)
	assert_near(float(w.loadout.stats("barrage").cooldown), 1.2 * 0.88, 1e-6)
	_mob(w, 50.0)
	var hits := _hits(_tick(w))
	assert_eq(hits.size(), 8, "eight lines land")
	assert_eq(hits.slice(6).map(func(e: Dictionary) -> String: return String(e.hit_visual)), ["", ""], "extra lines draw no extra set")


# --- Dragon Strike: the data ------------------------------------------------------------------------------------------------

func test_dragon_strike_damage_is_320_535_810_percent_on_4_5_6_mobs_at_ranks_1_4_8() -> void:
	var w := _world("dragon_strike")
	for i in 3:
		var r: int = [1, 4, 8][i]
		var st := w.loadout.stats("dragon_strike", r)
		assert_near(st.damage_pct, [3.20, 5.35, 8.10][i], 1e-9, "damage at rank %d" % r)
		assert_eq(SkillRunner.strike_count(st), [4, 5, 6][i], "cap at rank %d" % r)
		assert_eq(st.box, Rect2(-400, -100, 425, 120), "the canonical box at rank %d" % r)
		assert_eq(st.attack_count, 1)
	var d: Dictionary = _data().skills.skills.dragon_strike
	assert_eq(float(d.bot.reach), 0.0, "BU-21: the bot does not think it is ranged")
	assert_near(float(d.pending.delay), 0.84, 1e-9, "WZ hitAfter, orchestrator ruling")
	assert_near(float(d.pending.stagger), 0.12, 1e-9, "0.12 s per target")
	assert_eq(int(d.cast.min_targets), 1)


func test_dragon_strike_art_nodes_are_tiles_zero_to_two_at_minus_200_k_and_a_hit_per_target_index() -> void:
	var d: Dictionary = _data().skills.skills.dragon_strike
	var tiles: Array = d.cast_visuals
	assert_eq(tiles.size(), 3, "tile/3 lies outside the box: not drawn")
	for k in 3:
		assert_eq(String(tiles[k].path), BASE + "5121001/tile/%d" % k)
		assert_eq(int(tiles[k].x), -200 * k)
		assert_true(bool(tiles[k].facing), "tile %d is mirrored with the caster's facing" % k)
	assert_eq(d.hit_targets, [BASE + "5121001/hit/0", BASE + "5121001/hit/1", BASE + "5121001/hit/2"])
	assert_eq(String(d.effect), BASE + "5121001/effect")
	assert_true(bool(d.hit_at_feet), "the pillar's origin is its base")


# --- Dragon Strike: the strike -------------------------------------------------------------------------------------------------

func test_the_box_reaches_400_px_ahead_and_25_px_behind_facing_right_and_left() -> void:
	for facing in [1, -1]:
		var w := _world("dragon_strike", 1, facing)
		var ahead := _mob(w, 390.0 * facing)
		var edge_ahead := _mob(w, 405.0 * facing)
		var back := _mob(w, -24.0 * facing)
		var past := _mob(w, -26.0 * facing)
		_tick(w)
		var hit := {}
		for h in _run(w, 1.4):
			hit[int(h[1].mob)] = true
		assert_true(hit.has(ahead), "390 px ahead (facing %d)" % facing)
		assert_false(hit.has(edge_ahead), "405 px ahead is outside")
		assert_true(hit.has(back), "24 px behind is inside the 25 px back edge")
		assert_false(hit.has(past), "26 px behind is not hit")


func test_the_damage_lands_after_0_84_seconds_and_each_later_target_0_12_seconds_after_the_one_before() -> void:
	var w := _world("dragon_strike", 8)
	var a := _mob(w, 50.0)
	var b := _mob(w, 120.0)
	var c := _mob(w, 200.0)
	var first := {}
	var cast_events := _tick(w)
	assert_eq(cast_events.filter(func(e: Dictionary) -> bool: return e.type == "cast").size(), 1)
	assert_eq(_hits(cast_events).size(), 0, "nothing lands at the cast")
	for h in _run(w, 1.4):
		var m := int(h[1].mob)
		if not first.has(m):
			first[m] = (int(h[0]) + 1) * DT # seconds after the cast tick
	assert_true(first[a] >= 0.84 - 1e-6 and first[a] <= 0.84 + DT + 1e-6, "target 0 at 0.84 s: %f" % first[a])
	assert_true(first[b] >= 0.96 - 1e-6 and first[b] <= 0.96 + DT + 1e-6, "target 1 at 0.96 s: %f" % first[b])
	assert_true(first[c] >= 1.08 - 1e-6 and first[c] <= 1.08 + DT + 1e-6, "target 2 at 1.08 s: %f" % first[c])


func test_targets_are_chosen_at_the_impact_a_mob_that_walks_in_is_hit_and_one_that_leaves_is_not() -> void:
	var w := _world("dragon_strike")
	var leaver := _mob(w, 100.0)
	var arriver := _mob(w, 900.0)
	_tick(w)
	for t in 30:
		_tick(w)
	w.swarm.x[leaver] = w.player.pos.x + 900.0
	w.swarm.x[arriver] = w.player.pos.x + 100.0
	var hit := {}
	for h in _run(w, 1.4):
		hit[int(h[1].mob)] = true
	assert_true(hit.has(arriver), "walked in after the cast")
	assert_false(hit.has(leaver), "left before the impact")


func test_the_box_is_fixed_where_the_cast_began_even_if_the_caster_moves_and_turns() -> void:
	var w := _world("dragon_strike")
	var ahead := _mob(w, 300.0)
	_tick(w)
	w.player.pos.x += 500.0
	w.player.facing = -1
	var hit := {}
	for h in _run(w, 1.4):
		hit[int(h[1].mob)] = true
	assert_true(hit.has(ahead), "still struck 300 px ahead of where the dragon was raised")


func test_the_cap_is_four_mobs_at_rank_1_and_six_at_rank_8_nearest_first() -> void:
	for pair in [[1, 4], [8, 6]]:
		var w := _world("dragon_strike", pair[0])
		var slots := []
		for i in 8:
			slots.append(_mob(w, 40.0 + 40.0 * i))
		_tick(w)
		var hit := {}
		for h in _run(w, 1.6):
			hit[int(h[1].mob)] = true
		assert_eq(hit.size(), pair[1], "rank %d" % pair[0])
		for i in 8:
			assert_eq(hit.has(slots[i]), i < pair[1], "rank %d slot %d" % [pair[0], i])


func test_the_hit_art_is_hit_0_1_2_by_target_index_and_cycles_for_the_fourth() -> void:
	var w := _world("dragon_strike")
	for i in 4:
		_mob(w, 40.0 + 40.0 * i)
	_tick(w)
	var paths := _run(w, 1.6).map(func(h: Array) -> String: return String(h[1].hit_visual))
	assert_eq(paths, [BASE + "5121001/hit/0", BASE + "5121001/hit/1", BASE + "5121001/hit/2", BASE + "5121001/hit/0"])


func test_a_map_transfer_drops_the_pending_strike_like_meteor_shower() -> void:
	var w := _world("dragon_strike")
	var m := _mob(w, 100.0)
	_tick(w)
	w.runner.clear_pending()
	assert_eq(_run(w, 2.0).size(), 0, "no strike after the transfer")
	assert_eq(w.swarm.hp[m], w.swarm.max_hp[m], "untouched")


func test_one_cast_grants_one_energy_however_many_targets_and_lines_it_hits() -> void:
	var w := _world("dragon_strike", 8)
	for i in 5:
		_mob(w, 40.0 + 40.0 * i)
	_tick(w)
	assert_eq(w.meter.value, 0, "nothing before the impact")
	_run(w, 1.6)
	assert_eq(w.meter.value, 1, "the first landed hit pays the cast's one energy")
	var b := _world("barrage", 8)
	_mob(b, 50.0)
	_tick(b)
	assert_eq(b.meter.value, 1, "Barrage's six lines grant one energy")


func test_dragon_strike_rarity_bonuses_each_change_a_resolved_stat() -> void:
	var d: Dictionary = _data().skills.skills.dragon_strike
	var want := {"rare": ["mastery", [["damage", "mul", 1.2]]], "epic": ["wide_dragon", [["area", "mul", 1.2]]],
		"unique": ["roaring", [["attack_count", "add", 1.0]]],
		"legendary": ["roaring", [["attack_count", "add", 1.0], ["damage", "mul", 1.2]]]}
	for tier: String in want:
		var list: Array = d.rarity_bonuses[tier]
		assert_eq(list.size(), 1, tier)
		assert_eq(String(list[0].id), want[tier][0], tier)
		assert_eq((list[0].effects as Array).map(func(e: Dictionary) -> Array: return [e.stat, e.op, float(e.value)]), want[tier][1], tier)
	assert_eq(String(d.rarity_bonuses.epic[0].text), "Wide Dragon")
	assert_eq(String(d.rarity_bonuses.unique[0].text), "Roaring Dragon")
	var w := _world("dragon_strike")
	w.loadout.add_skill_mod("dragon_strike", "area", "mul", 1.2)
	assert_true((w.loadout.stats("dragon_strike").box as Rect2).is_equal_approx(Rect2(-480, -120, 510, 144)), "Wide Dragon scales the box")
	var wide := _mob(w, 440.0)
	var back := _mob(w, -29.0)
	_tick(w)
	var hit := {}
	for h in _run(w, 1.4):
		hit[int(h[1].mob)] = true
	assert_true(hit.has(wide) and hit.has(back), "a wider strip reaches 440 px and 29 px behind")
	var r := _world("dragon_strike")
	r.loadout.add_skill_mod("dragon_strike", "attack_count", "add", 1.0)
	var m := _mob(r, 100.0)
	_tick(r)
	assert_eq(_run(r, 1.4).filter(func(h: Array) -> bool: return int(h[1].mob) == m).size(), 2, "Roaring Dragon: two lines per target")


func test_dragon_strike_cast_goes_through_the_whole_loop_and_recasts_after_4_8_seconds() -> void:
	var w := _world("dragon_strike", 8)
	var m := _mob(w, 100.0)
	var x0: float = w.swarm.x[m]
	for t in int(10.0 / DT):
		w.step(DT, MoveInput.new())
		w.swarm.hp[m] = w.swarm.max_hp[m]
		w.swarm.x[m] = x0
	assert_eq(w.runner.casts, 3, "casts at 0, 4.8 and 9.6 s")


# --- bot.reach in the real definition ------------------------------------------------------------------------------------------

func test_the_dragon_strike_definition_reads_as_zero_reach_to_the_bot() -> void:
	var w := _world("dragon_strike", 8)
	assert_eq(SkillRunner.reach_of(w.loadout.stats("dragon_strike"), w), 0.0)
	w.loadout.add_skill_mod("dragon_strike", "area", "mul", 1.2)
	assert_eq(SkillRunner.reach_of(w.loadout.stats("dragon_strike"), w), 0.0, "Wide Dragon does not change it")
	var b := _world("barrage", 8)
	assert_true(SkillRunner.reach_of(b.loadout.stats("barrage"), b) > 0.0, "Barrage keeps the weapon's reach")


# --- the presentation helper --------------------------------------------------------------------------------------------------

func test_a_facing_cast_visual_mirrors_its_x_and_flips_for_a_right_facing_caster() -> void:
	var v := {"path": "p", "x": -200, "facing": true}
	assert_eq(SkillBook.visual_placement(v, -1), {"x": -200.0, "flip": false})
	assert_eq(SkillBook.visual_placement(v, 1), {"x": 200.0, "flip": true})
	assert_eq(SkillBook.visual_placement({"path": "p", "x": 180}, 1), {"x": 180.0, "flip": false}, "no flag: absolute, as Meteor Shower")


# --- real cache -------------------------------------------------------------------------------------------------------------

func test_real_cache_all_eight_ranks_art_nodes_and_sounds() -> void:
	if not require_cache():
		return
	var library := AssetLibrary.new()
	library.open()
	var img := library.img("Skill.wz/512.img")
	assert_true(img != null, "book 512 imported")
	if img == null:
		library.free()
		return
	var b := SkillBook.from_data(_data().skills, {"512": img.root})
	var lo := Loadout.new(b)
	for key in ["barrage", "dragon_strike"]:
		lo.add_skill(key)
		var node: Dictionary = img.root.skill[str(b.skill_id(key))]
		assert_eq(b.max_level(key), 30, key)
		for rank in range(1, 9):
			var lv: int = LEVELS[rank - 1]
			assert_eq(b.canonical_level(key, rank), lv)
			var row: Dictionary = node.level[str(lv)]
			var st := lo.stats(key, rank)
			assert_near(st.damage_pct, float(row.damage) / 100.0, 1e-9, "%s rank %d damage" % [key, rank])
			assert_eq(st.attack_count, int(row.get("attackCount", 1)), "%s rank %d attackCount" % [key, rank])
			assert_eq(st.mob_count, int(row.get("mobCount", 1)), "%s rank %d mobCount" % [key, rank])
			if key == "barrage":
				assert_false(row.has("lt") or row.has("mobCount"), "no box or mobCount in the WZ")
				assert_eq(st.attack_count, 6)
				assert_near(st.damage_pct, BARRAGE_DAMAGE[rank - 1] / 100.0, 1e-9)
			else:
				assert_eq(st.box, Rect2(-400, -100, 425, 120), "rank %d box" % rank)
				assert_near(st.damage_pct, DRAGON_DAMAGE[rank - 1] / 100.0, 1e-9)
				assert_eq(SkillRunner.strike_count(st), DRAGON_MOBS[rank - 1])
	for i in 3:
		assert_near(lo.stats("barrage", [1, 4, 8][i]).damage_pct, [1.06, 1.60, 2.30][i], 1e-9)
		assert_near(lo.stats("dragon_strike", [1, 4, 8][i]).damage_pct, [3.20, 5.35, 8.10][i], 1e-9)
	var frames := {"5121007/effect": 5, "5121007/hit/0": 12, "5121007/hit0/0": 9, "5121007/hit1/0": 17,
		"5121001/effect": 16, "5121001/hit/0": 13, "5121001/hit/1": 13, "5121001/hit/2": 13,
		"5121001/tile/0": 13, "5121001/tile/1": 13, "5121001/tile/2": 13, "5121001/tile/3": 13}
	for tail: String in frames:
		var anim := library.anim(BASE + tail)
		assert_true(anim != null and not anim.is_empty(), tail)
		if anim != null:
			assert_eq(anim.frames.size(), frames[tail], tail + " frames")
	var d := b.def("dragon_strike")
	for v: Dictionary in d.cast_visuals:
		assert_false(library.anim(String(v.path)).is_empty(), String(v.path))
	for path: String in d.hit_targets:
		assert_false(library.anim(path).is_empty(), path)
	for key in ["barrage", "dragon_strike"]:
		var def := b.def(key)
		for field in ["hit", "effect"]:
			assert_false(library.anim(String(def[field])).is_empty(), String(def[field]))
		assert_true(library.sound(def.sounds.use) != null, key + " use sound")
		assert_true(library.sound(def.sounds.hit) != null, key + " hit sound")
		assert_true(library.node("Character.wz/00002000.img/" + String(def.action)) is Dictionary, key + " body action")
	for path: String in b.def("barrage").hit_lines:
		assert_true(path == "" or not library.anim(path).is_empty(), path)
	assert_eq(Array(library.missing), [])
	library.free()


func test_real_cache_a_knuckle_keeps_its_weapon_on_every_frame_of_fist_and_dragonstrike() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.get_default()
	var avatar := AvatarRenderer.new()
	avatar.library = lib
	for weapon: int in [1482000, 1482009]:
		var img := lib.img("Character.wz/Weapon/0%d.img" % weapon)
		if img == null:
			skip("no knuckle %d in the cache" % weapon)
			continue
		assert_false(AvatarLayers.has_art(img, "swingTF"), "premise: knuckle %d has no swingTF" % weapon)
		avatar.set_look({"equips": [1040002, 1060002, 1072001, weapon]})
		for stance in ["fist", "dragonstrike"]:
			var n := avatar.stance_delays(stance).size()
			assert_true(n > 0, stance)
			for index in n:
				var owned := avatar.compose(stance, index).filter(
					func(p: Dictionary) -> bool: return int(p.get("owner", 0)) == weapon)
				assert_false(owned.is_empty(), "%d is drawn at %s frame %d" % [weapon, stance, index])
	avatar.free()

func test_staggered_targets_keep_identity_and_original_timing_after_slot_reuse() -> void:
	var w := _world("dragon_strike", 8)
	_mob(w, 50.0)
	var second := _mob(w, 120.0)
	var third := _mob(w, 180.0)
	for t in 52:
		_tick(w)
	var old_identity: int = w.swarm.identity[second]
	w.swarm.despawn(second)
	var replacement := _mob(w, 1500.0)
	assert_eq(replacement, second, "fixture reuses the selected slot")
	assert_true(w.swarm.identity[replacement] != old_identity)
	var hits := _run(w, 0.3)
	assert_eq(hits.size(), 1, "only the surviving third target lands")
	if hits.size() == 1:
		assert_eq(int(hits[0][1].mob), third)
		assert_eq(int(hits[0][0]), 13, "invalid target keeps its original stagger interval")
	assert_eq(w.swarm.hp[replacement], w.swarm.max_hp[replacement])
