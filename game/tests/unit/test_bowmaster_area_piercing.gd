extends TestCase
## Bowmaster's area and piercing skills (spec #332, ticket B8 #340): Arrow Rain (a delayed box strike around the caster)
## and Dragon's Breath (a piercing, knocking-back arrow with its own ball). Fixed 1/60 s ticks, seeded RNG; the Skill.wz
## levels are the synthetic fixture tables (endpoints and steps recorded from v83) unless a test says "real cache"
## (those call require_cache() and SKIP without it).

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const BOW := 1452051
const RAIN := "arrow_rain"
const BREATH := "dragons_breath"


## A quiet round of a Bowmaster holding a bow, `key` learned at `rank_value`, mobs frozen and snail-sized.
func _world(key: String, rank_value := 1, p_seed := 340) -> RunWorld:
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["312"]["playable"] = true # in this test's data only: its pool cards exist (B12 ships the flip)
	var setup := RF.with_basic_attack(RF.setup("quiet", p_seed, data))
	setup.equipment_info.merge({BOW: {"incPAD": 28, "attackSpeed": 6, "tuc": 7}}, true)
	for action: String in ["shoot1", "shoot2"]:
		setup.body_img[action] = {"0": {"delay": 100.0}, "1": {"delay": 100.0}}
	setup["job"] = 312
	var w := RunWorld.new(setup)
	RF.place_player(w, 400)
	if w.weapon_id() != BOW:
		w.wear_new_item(BOW)
	for mk: MobKind in w.mob_kinds:
		mk.hitbox = Rect2(-20, -50, 40, 50)
		mk.move_speed = 0
	w.god = true
	w.loadout.ranks.clear() # not the start skill (Arrow Blow): only `key` casts
	w.loadout.order.clear()
	assert_true(w.learn_skill(key), "%s is learnable by a Bowmaster" % key)
	w.loadout.set_rank(key, rank_value)
	w.refresh_player_stats()
	w.drain_events()
	return w


func _mob(w: RunWorld, dx: float, boss := false) -> int:
	var slot := RF.put_mob(w, 2220000 if boss else 1110100, w.player.pos.x + dx, 190, 100000)
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	return slot


func _hits(events: Array, key: String) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return e.type == "mob_hit" and e.skill == key)


func _run(w: RunWorld, ticks: int) -> Array:
	var events := []
	for tick in ticks:
		w.step(DT, MoveInput.new())
		events.append_array(w.drain_events())
	return events


func _mod(w: RunWorld, key: String, stat: String, op: String, value: float) -> void:
	w.loadout.add_skill_mod(key, stat, op, value)


# --- Arrow Rain --------------------------------------------------------------------------------------------------------

func test_arrow_rain_strikes_half_a_second_after_the_cast_at_the_spot_the_caster_stood() -> void:
	var w := _world(RAIN)
	var near := _mob(w, 100)
	w.step(DT, MoveInput.new()) # the cast
	assert_eq(w.runner.casts, 1)
	var cast_at := w.time
	var cast_x := w.player.pos.x
	var events := w.drain_events()
	assert_true(_hits(events, RAIN).is_empty(), "nothing is struck on the cast tick")
	w.player.pos.x += 700.0 # the caster walks away: the rain stays where it was called
	var far := _mob(w, 100)
	var first_hit := -1.0
	for tick in 60:
		w.step(DT, MoveInput.new())
		var hits := _hits(w.drain_events(), RAIN)
		if not hits.is_empty() and first_hit < 0.0:
			first_hit = w.time
			assert_eq(hits.size(), 1, "only the monster in the box at the cast position is struck")
			assert_eq(int(hits[0].mob), near)
			assert_true(int(hits[0].mob) != far)
	assert_near(first_hit - cast_at, 0.5, DT * 1.5, "the strike lands 0.5 s after the cast")
	assert_near(cast_x, 400.0, 0.5)


func test_arrow_rain_strikes_around_the_caster_not_in_front_of_it() -> void:
	var w := _world(RAIN)
	var left := _mob(w, -150)
	var right := _mob(w, 150)
	var outside := _mob(w, 260)
	var struck := {}
	for e: Dictionary in _hits(_run(w, 40), RAIN):
		struck[int(e.mob)] = true
	assert_true(struck.has(left) and struck.has(right), "both sides of the caster are inside the symmetric box")
	assert_false(struck.has(outside), "beyond the +-170 px box at rank 1")
	var st := w.loadout.stats(RAIN)
	assert_eq(st.box, Rect2(-170, -100, 340, 200))


func test_arrow_rain_hits_at_most_six_monsters_nearest_first() -> void:
	var w := _world(RAIN)
	var slots := []
	for k in 9:
		slots.append(_mob(w, 20.0 + 15.0 * k))
	var struck := {}
	for e: Dictionary in _hits(_run(w, 40), RAIN):
		struck[int(e.mob)] = int(struck.get(int(e.mob), 0)) + 1
	assert_eq(struck.size(), 6, "mobCount 6")
	for k in 6:
		assert_true(struck.has(slots[k]), "the six nearest to the caster are struck")


func test_arrow_rain_needs_a_monster_in_the_box_and_has_a_five_second_cooldown() -> void:
	var w := _world(RAIN)
	_mob(w, 300) # outside the box
	w.step(DT, MoveInput.new())
	assert_eq(w.runner.casts, 0, "min_targets 1: nothing in the box, no cast")
	_mob(w, 80)
	w.step(DT, MoveInput.new())
	assert_eq(w.runner.casts, 1)
	assert_near(float(w.runner.cooldowns[RAIN]), 5.0 - DT, 0.001)
	assert_near(w.loadout.stats(RAIN).cooldown, 5.0, 0.0001)
	var d := w.book.def(RAIN)
	assert_eq(String(d.cast.rule), "box")
	assert_eq(int(d.cast.min_targets), 1)
	assert_near(float(d.pending.delay), 0.5, 0.0001)
	assert_eq(String(d.damage), "physical")
	assert_true(not d.has("weapon_families"), "weapons gate nothing")
	assert_false(d.has("ranks"), "the default 30-level rank table")


func test_arrow_rain_area_widens_the_box_by_the_wide_rain_bonus() -> void:
	var plain := _world(RAIN)
	_mob(plain, 80)
	var wide := _world(RAIN)
	_mob(wide, 80)
	_mod(wide, RAIN, "area", "mul", 1.2)
	var edge_plain := _mob(plain, 190) # past +-170, inside +-204
	var edge_wide := _mob(wide, 190)
	assert_near(wide.loadout.stats(RAIN).box.size.x, 340.0 * 1.2, 0.01)
	var struck_plain := {}
	for e: Dictionary in _hits(_run(plain, 40), RAIN):
		struck_plain[int(e.mob)] = true
	var struck_wide := {}
	for e: Dictionary in _hits(_run(wide, 40), RAIN):
		struck_wide[int(e.mob)] = true
	assert_false(struck_plain.has(edge_plain))
	assert_true(struck_wide.has(edge_wide))


func test_arrow_rain_final_attack_adds_a_second_volley_line_per_target() -> void:
	var base := _world(RAIN)
	var second := _world(RAIN)
	for w: RunWorld in [base, second]:
		_mob(w, 60)
		_mob(w, -60)
	_mod(second, RAIN, "attack_count", "add", 1)
	var plain_lines := _hits(_run(base, 40), RAIN)
	var double_lines := _hits(_run(second, 40), RAIN)
	assert_eq(plain_lines.size(), 2, "one line on each of the two monsters")
	assert_eq(double_lines.size(), 4, "a second line on each")
	assert_eq(second.loadout.stats(RAIN).attack_count, 2)


func test_arrow_rain_ranks_widen_the_box_and_raise_the_damage() -> void:
	var w := _world(RAIN)
	var lo := w.loadout
	assert_eq(lo.stats(RAIN, 1).box.size.x, 340.0, "WZ level 4: +-170")
	assert_eq(lo.stats(RAIN, 4).box.size.x, 380.0, "WZ level 15: +-190")
	assert_eq(lo.stats(RAIN, 8).box.size.x, 420.0, "WZ level 30: +-210")
	assert_true(lo.stats(RAIN, 8).damage_pct > lo.stats(RAIN, 4).damage_pct)
	assert_true(lo.stats(RAIN, 4).damage_pct > lo.stats(RAIN, 1).damage_pct)
	assert_eq(lo.stats(RAIN, 1).mob_count, 6)


func test_arrow_rain_draws_the_eight_falling_arrows_across_the_box() -> void:
	var w := _world(RAIN)
	var d := w.book.def(RAIN)
	assert_eq(String(d.effect), "Skill.wz/311.img/skill/3111004/effect", "the caster's flourish")
	assert_eq(String(d.hit), "Skill.wz/311.img/skill/3111004/hit/0")
	assert_eq(String(d.sounds.use), "Sound.wz/Skill.img/3111004/Use")
	assert_eq(String(d.sounds.hit), "Sound.wz/Skill.img/3111004/Hit")
	var visuals: Array = d.cast_visuals
	assert_eq(visuals.size(), 1)
	var plan := CastVisualPlan.expand(visuals, w.loadout.stats(RAIN).box)
	assert_eq(plan.size(), 8)
	for k in 8:
		assert_eq(String(plan[k].path), "Skill.wz/311.img/skill/3111004/special/0")
		assert_near(float(plan[k].delay), 0.09 * k, 0.0001, "one arrow every 90 ms")
		assert_eq(float(plan[k].fall), 230.0)
	var xs := plan.map(func(p: Dictionary) -> float: return float(p.x))
	assert_near(xs[0], -170.0 + 340.0 / 16.0, 0.01, "eight arrows spread over the box")
	assert_near(xs[7], 170.0 - 340.0 / 16.0, 0.01)
	var wide := CastVisualPlan.expand(visuals, Rect2(-210, -100, 420, 200))
	assert_true(float(wide[7].x) > float(plan[7].x), "a wider box spreads them wider")


func test_cast_visuals_with_a_literal_x_pass_through_unchanged() -> void:
	var plan := CastVisualPlan.expand([{"path": "a", "x": -360}, {"path": "b", "x": 180}], Rect2(-100, -100, 200, 200))
	assert_eq(plan.size(), 2)
	assert_eq(float(plan[0].x), -360.0)
	assert_eq(float(plan[0].delay), 0.0)
	assert_eq(float(plan[0].fall), 0.0)
	assert_eq(float(plan[1].x), 180.0)


# --- Dragon's Breath --------------------------------------------------------------------------------------------------

func _line_world(rank_value: int, knockback := false) -> RunWorld:
	var w := _world(BREATH, rank_value)
	# The arrow leaves the hand (about 30 px above the feet) and flies straight at the nearest monster's centre, so a row of
	# bodies whose centre is 30 px up is a level line; a taller or shorter body would be flown over or under.
	for mk: MobKind in w.mob_kinds:
		mk.hitbox = Rect2(-20, -60, 40, 60)
	if not knockback:
		w.book.defs[BREATH].erase("knockback") # isolate the pierce from the pushes of the monsters already hit
		w.loadout.version += 1
	return w


func _distinct_hits(w: RunWorld, ticks: int) -> Dictionary:
	var struck := {}
	for e: Dictionary in _hits(_run(w, ticks), BREATH):
		struck[int(e.mob)] = int(struck.get(int(e.mob), 0)) + 1
	return struck


func test_dragons_breath_pierces_three_four_and_five_extra_monsters_by_rank() -> void:
	for row: Array in [[1, 3], [4, 4], [8, 5]]:
		var w := _line_world(int(row[0]))
		for k in 8:
			_mob(w, 40.0 + 45.0 * k)
		assert_eq(w.loadout.stats(BREATH).pierce, int(row[1]), "rank %d: mobCount - 1" % int(row[0]))
		var struck := _distinct_hits(w, 90)
		assert_eq(struck.size(), int(row[1]) + 1, "rank %d strikes 1 + %d monsters" % [int(row[0]), int(row[1])])
		for count: int in struck.values():
			assert_eq(count, 1, "a shot hits each monster once")


func test_dragons_breath_pierces_a_knocked_back_line_too() -> void:
	var w := _line_world(8, true)
	for k in 8:
		_mob(w, 40.0 + 45.0 * k)
	assert_eq(_distinct_hits(w, 120).size(), 6, "rank 8 still strikes six monsters while pushing each one")


func test_a_pierce_card_adds_to_the_monsters_in_the_field() -> void:
	var w := _line_world(1)
	_mod(w, BREATH, "pierce", "add", 2)
	assert_eq(w.loadout.stats(BREATH).pierce, 5, "3 from mobCount 4, plus Dragon's Spirit 2")
	for k in 9:
		_mob(w, 40.0 + 45.0 * k)
	assert_eq(_distinct_hits(w, 120).size(), 6)
	assert_eq(w.loadout.stats(BREATH).mob_count, 4, "mob_count itself is unchanged")


## A twin of the Dragon's Breath world without its knock-back, so the 180 px shows as the difference to the ordinary hit nudge.
func _plain_twin(w_rank: int) -> RunWorld:
	var plain := _world(BREATH, w_rank)
	plain.book.defs[BREATH].erase("knockback")
	plain.loadout.version += 1
	return plain


func test_dragons_breath_knocks_every_struck_monster_back_180_px_both_ways() -> void:
	for side in [-1, 1]:
		var pushed := _world(BREATH, 8)
		var plain := _plain_twin(8)
		var slots := {}
		for w: RunWorld in [pushed, plain]:
			slots[w] = [_mob(w, 80.0 * side), _mob(w, 140.0 * side)]
			_distinct_hits(w, 60)
		for k in 2:
			var delta: float = pushed.swarm.x[slots[pushed][k]] - plain.swarm.x[slots[plain][k]]
			assert_near(delta, 180.0 * side, 1.5, "side %d, monster %d: 180 px away from the caster" % [side, k])


func test_dragons_breath_damages_a_boss_but_never_moves_it() -> void:
	var pushed := _world(BREATH, 8)
	var plain := _plain_twin(8)
	var boss := {}
	var other := {}
	for w: RunWorld in [pushed, plain]:
		other[w] = _mob(w, 60)
		boss[w] = _mob(w, 120, true)
		assert_true(_distinct_hits(w, 90).has(boss[w]), "the boss is struck")
	assert_eq(pushed.swarm.x[boss[pushed]], plain.swarm.x[boss[plain]], "the boss is not pushed")
	assert_near(pushed.swarm.x[other[pushed]] - plain.swarm.x[other[plain]], 180.0, 1.5, "while the monster beside it is")


func test_dragons_breath_rolls_stream_one_once_per_struck_non_boss() -> void:
	var with_push := _world(BREATH, 8)
	var without := _world(BREATH, 8)
	without.book.defs[BREATH].erase("knockback")
	without.loadout.version += 1
	for w: RunWorld in [with_push, without]:
		_mob(w, 70)
		_mob(w, 120)
		_mob(w, 170, true) # a boss: damaged, no roll
		_mob(w, 220)
	_distinct_hits(with_push, 90)
	_distinct_hits(without, 90)
	# A PCG stream's state depends only on how many numbers were drawn: advance the plain world's by the three pushes.
	var reference := RandomNumberGenerator.new()
	reference.state = without.rng.state
	for k in 3:
		reference.randf()
	assert_eq(with_push.rng.state, reference.state, "three non-boss pushes, three draws; the boss drew none")


func test_dragons_breath_reaches_440_px_and_not_further() -> void:
	var w := _world(BREATH)
	_mob(w, 450)
	w.step(DT, MoveInput.new())
	assert_eq(w.runner.casts, 0, "450 px is out of reach")
	_mob(w, 430)
	w.step(DT, MoveInput.new())
	assert_eq(w.runner.casts, 1)
	var st := w.loadout.stats(BREATH)
	assert_eq(st.range, 440.0)
	assert_eq(st.speed, 700.0)
	assert_eq(st.radius, 16.0)
	assert_near(st.cooldown, 3.5, 0.0001)
	assert_near(float(w.runner.cooldowns[BREATH]), 3.5 - DT, 0.001)


func test_dragons_breath_has_its_own_ball_and_no_ammo_sprite() -> void:
	var w := _world(BREATH)
	var d := w.book.def(BREATH)
	assert_eq(String(d.ball), "Skill.wz/312.img/skill/3121003/ball")
	assert_eq(String(d.hit), "Skill.wz/312.img/skill/3121003/hit/0")
	assert_eq(String(d.sounds.use), "Sound.wz/Skill.img/3121003/Use")
	assert_eq(String(d.sounds.hit), "Sound.wz/Skill.img/3121003/Hit")
	assert_false(bool(d.get("ammo_shot", false)))
	assert_eq(String(d.pierce_field), "mobCount")
	assert_false(d.has("weapon_families"))
	assert_false(d.has("ranks"))
	_mob(w, 100)
	w.runner.step(DT, w)
	var own := w.visual_index(String(d.ball))
	var seen := 0
	for i in w.projectiles.capacity():
		if w.projectiles.active[i] != 0:
			seen += 1
			assert_eq(w.projectiles.visual[i], own)
	assert_eq(seen, 1)


func test_dragons_breath_eye_of_amazon_extends_the_reach() -> void:
	var w := _world(BREATH)
	_mod(w, BREATH, "range", "mul", 1.25)
	assert_eq(w.loadout.stats(BREATH).range, 550.0)
	_mob(w, 500)
	w.step(DT, MoveInput.new())
	assert_eq(w.runner.casts, 1, "500 px is inside 550")


func test_the_skill_window_line_names_the_pierce_and_the_knock_back() -> void:
	var w := _world(BREATH)
	var text := SkillText.new(w.book)
	for row: Array in [[1, 4, 3], [4, 15, 4], [8, 30, 5]]:
		var line := text.level_line(BREATH, int(row[1]), w.loadout.stats(BREATH, int(row[0])))
		assert_true(line.contains("Pierces up to %d more monsters" % int(row[2])), line)
		assert_true(line.contains("Knock-back: 100% / 180 px"), line)
	assert_false(text.level_line(RAIN, 4, w.loadout.stats(RAIN, 1)).contains("Pierces"))


# --- both skills: rarity tables ---------------------------------------------------------------------------------------

func test_the_rarity_tables_follow_the_spec() -> void:
	var w := _world(RAIN)
	var table := {
		RAIN: [["bow_mastery", "damage", "mul", 1.2], ["wide_rain", "area", "mul", 1.2], ["final_attack", "attack_count", "add", 1.0]],
		BREATH: [["bow_expert", "damage", "mul", 1.2], ["eye", "range", "mul", 1.25], ["dragons_spirit", "pierce", "add", 2.0]],
	}
	for key: String in table:
		var bonuses: Dictionary = w.book.def(key).rarity_bonuses
		var rows: Array = table[key]
		for t in 3:
			var tier: String = ["rare", "epic", "unique"][t]
			assert_eq(bonuses[tier].size(), 1, "%s %s" % [key, tier])
			assert_eq(String(bonuses[tier][0].id), String(rows[t][0]), "%s %s" % [key, tier])
			var effect: Dictionary = bonuses[tier][0].effects[0]
			assert_eq(String(effect.stat), String(rows[t][1]))
			assert_eq(String(effect.op), String(rows[t][2]))
			assert_near(float(effect.value), float(rows[t][3]), 0.0001)
		var legendary: Dictionary = bonuses.legendary[0]
		assert_eq(String(legendary.id), String(rows[2][0]), "%s: Legendary shares the Unique's id (and its repeat counter)" % key)
		assert_eq(legendary.effects.size(), 2)
		assert_eq(String(legendary.effects[0].stat), String(rows[2][1]))
		assert_eq(String(legendary.effects[1].stat), "damage")
		assert_near(float(legendary.effects[1].value), 1.2, 0.0001)


# --- real cache: all eight ranks against Skill.wz ----------------------------------------------------------------------

func test_real_cache_all_eight_ranks_map_to_the_skill_wz_levels() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	assert_true(lib.open())
	var imgs := {}
	for book: String in ["311", "312"]:
		var img := lib.img("Skill.wz/%s.img" % book)
		assert_true(img != null, "Skill.wz/%s.img is in the cache" % book)
		if img == null:
			lib.free()
			return
		imgs[book] = img.root
	var book := SkillBook.from_data(DataRepo.load_all().skills, imgs)
	var lo := Loadout.new(book)
	lo.weapon_family = "bow"
	var levels := [4, 8, 12, 15, 19, 23, 27, 30]
	var rows := {RAIN: ["311", 3111004], BREATH: ["312", 3121003]}
	for key: String in rows:
		var row: Array = rows[key]
		var node: Dictionary = imgs[row[0]].skill["%07d" % int(row[1])]
		assert_eq(book.max_level(key), 30, key)
		assert_eq(book.max_rank(key), 8, key)
		for rank_value in range(1, 9):
			var lv: int = levels[rank_value - 1]
			var label := "%s rank %d (level %d)" % [key, rank_value, lv]
			assert_eq(book.canonical_level(key, rank_value), lv, label)
			var level: Dictionary = node.level[str(lv)]
			var st := lo.stats(key, rank_value)
			assert_eq(int(st.level), lv, label)
			assert_near(st.damage_pct, float(level.damage) / 100.0, 0.000001, label)
			if key == RAIN:
				var lt: Array = level.lt["$v"]
				var rb: Array = level.rb["$v"]
				assert_eq(st.box, Rect2(float(lt[0]), float(lt[1]), float(rb[0]) - float(lt[0]), float(rb[1]) - float(lt[1])), label)
				assert_eq(st.mob_count, int(level.mobCount), label)
				assert_eq(st.mob_count, 6, label)
				assert_eq(st.attack_count, 1, label)
			else:
				assert_eq(st.range, float(level.range), label)
				assert_eq(st.range, 440.0, label)
				assert_eq(st.mob_count, int(level.mobCount), label)
				assert_eq(st.pierce, int(level.mobCount) - 1, label)
				assert_eq(book.canonical(key, lv, "prop"), 100.0, label)
				assert_eq(st.knockback_chance, 100.0, label)
				assert_eq(st.knockback_distance, 180.0, label)
	# The spec's worked rank values (rank 1 / 4 / 8) as literals.
	for i in 3:
		var r: int = [1, 4, 8][i]
		assert_near(lo.stats(RAIN, r).damage_pct, [0.75, 1.22, 1.60][i], 0.000001, "Arrow Rain rank %d" % r)
		assert_eq(lo.stats(RAIN, r).box.size.x, [340.0, 380.0, 420.0][i], "Arrow Rain box rank %d" % r)
		assert_near(lo.stats(BREATH, r).damage_pct, [0.48, 0.70, 1.00][i], 0.000001, "Dragon's Breath rank %d" % r)
		assert_eq(lo.stats(BREATH, r).mob_count, [4, 5, 6][i], "Dragon's Breath monsters rank %d" % r)
		assert_eq(lo.stats(BREATH, r).pierce, [3, 4, 5][i], "Dragon's Breath pierce rank %d" % r)
	# Art and sounds resolve in the cache.
	for key: String in rows:
		var d := book.def(key)
		var paths: Array = [d.effect, d.ball, d.hit]
		for visual: Dictionary in d.get("cast_visuals", []):
			paths.append(visual.path)
		for path: String in paths:
			if path != "":
				assert_true(lib.anim(path).frames.size() > 0, path)
		for path: String in d.sounds.values():
			if path != "":
				assert_true(lib.sound(path) != null, path)
	assert_true(lib.missing.is_empty(), str(lib.missing))
	lib.free()
