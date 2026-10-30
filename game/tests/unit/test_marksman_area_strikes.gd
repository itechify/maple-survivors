extends TestCase
## Marksman's area strikes (spec #360, ticket MS6 #366): Blizzard (a delayed box strike that can freeze) and Arrow Eruption (a wider
## delayed box strike), both data on the delayed-strike seam of Arrow Rain. Fixed 1/60 s ticks, seeded RNG; the Skill.wz levels
## are the synthetic fixture tables (endpoints and steps recorded from v83) unless a test says "real cache" (those call
## require_cache() and SKIP without it).

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const CROSSBOW := 1462001
const BLIZZARD := "blizzard_crossbow"
const ERUPTION := "arrow_eruption"
const KEYS := [BLIZZARD, ERUPTION]
const TIERS := ["rare", "epic", "unique", "legendary"]


## A quiet round of a Marksman holding a crossbow, `key` learned at `rank_value`, mobs frozen in place and snail-sized.
func _world(key: String, rank_value := 1, p_seed := 366) -> RunWorld:
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["322"]["playable"] = true # in this test's data only: MS11 ships the flip
	var setup := RF.with_basic_attack(RF.setup("quiet", p_seed, data))
	setup.equipment_info.merge({CROSSBOW: {"incPAD": 29, "attackSpeed": 6, "tuc": 7}}, true)
	for action: String in ["shoot1", "shoot2"]:
		setup.body_img[action] = {"0": {"delay": 100.0}, "1": {"delay": 100.0}}
	setup["job"] = 322
	var w := RunWorld.new(setup)
	RF.place_player(w, 400)
	if w.weapon_id() != CROSSBOW:
		w.wear_new_item(CROSSBOW)
	for mk: MobKind in w.mob_kinds:
		mk.hitbox = Rect2(-20, -50, 40, 50)
		mk.move_speed = 0
	w.god = true
	w.loadout.ranks.clear() # not the start skill (Iron Arrow): only `key` casts
	w.loadout.order.clear()
	assert_true(w.learn_skill(key), "%s is learnable by a Marksman" % key)
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


func _struck(w: RunWorld, key: String, ticks := 60) -> Dictionary:
	var struck := {}
	for e: Dictionary in _hits(_run(w, ticks), key):
		struck[int(e.mob)] = int(struck.get(int(e.mob), 0)) + 1
	return struck


func _mod(w: RunWorld, key: String, stat: String, op: String, value: float) -> void:
	w.loadout.add_skill_mod(key, stat, op, value)


## Blizzard's freeze always lands (the chance leg removed), so the rank's seconds and the refusals are exact.
func _sure_freeze(w: RunWorld) -> void:
	w.book.defs[BLIZZARD].on_hit.erase("chance_field")


# --- definitions -------------------------------------------------------------------------------------------------------

func test_the_two_skills_are_defined_in_the_321_book_on_the_delayed_strike_path() -> void:
	var w := _world(BLIZZARD)
	for row: Array in [[BLIZZARD, 3211003, 4.0, 0.6], [ERUPTION, 3211004, 5.0, 0.5]]:
		var d := w.book.def(String(row[0]))
		assert_eq(int(d.skill_id), int(row[1]))
		assert_eq(String(d.book), "321")
		assert_eq(int(d.job), 321)
		assert_eq(String(d.slot), "active")
		assert_eq(String(d.damage), "physical")
		assert_eq(String(d.cast.rule), "box")
		assert_eq(int(d.cast.min_targets), 1)
		assert_near(float(d.cooldown), float(row[2]), 0.0001)
		assert_near(float(d.pending.delay), float(row[3]), 0.0001)
		assert_true(not d.has("weapon_families"), "weapons gate nothing")
		assert_false(d.has("ranks"), "the default 30-level rank table")
		assert_true(d.has("rarity_bonuses"))
	assert_eq(String(w.book.def(BLIZZARD).element), "i")
	assert_false(w.book.def(ERUPTION).has("element"))
	assert_false(w.book.def(ERUPTION).has("on_hit"), "Arrow Eruption applies no status")


# --- Blizzard ---------------------------------------------------------------------------------------------------------

func test_blizzard_strikes_six_tenths_of_a_second_after_the_cast_at_the_spot_the_caster_stood() -> void:
	var w := _world(BLIZZARD)
	var near := _mob(w, 100)
	w.step(DT, MoveInput.new()) # the cast
	assert_eq(w.runner.casts, 1)
	var cast_at := w.time
	assert_true(_hits(w.drain_events(), BLIZZARD).is_empty(), "nothing is struck on the cast tick")
	w.player.pos.x += 700.0 # the caster walks away: the blizzard stays where it was called
	var far := _mob(w, 100)
	var first_hit := -1.0
	for tick in 80:
		w.step(DT, MoveInput.new())
		var hits := _hits(w.drain_events(), BLIZZARD)
		if not hits.is_empty() and first_hit < 0.0:
			first_hit = w.time
			assert_eq(hits.size(), 1, "only the monster in the box at the cast position is struck")
			assert_eq(int(hits[0].mob), near)
			assert_true(int(hits[0].mob) != far)
	assert_near(first_hit - cast_at, 0.6, DT * 1.5, "the strike lands 0.6 s after the cast")


func test_blizzard_strikes_around_the_caster_and_takes_the_six_nearest() -> void:
	var w := _world(BLIZZARD)
	var left := _mob(w, -120)
	var right := _mob(w, 120)
	var outside := _mob(w, 160) # the 40 px body starts at 140: past +-130
	var struck := _struck(w, BLIZZARD)
	assert_true(struck.has(left) and struck.has(right), "both sides of the caster are inside the symmetric box")
	assert_false(struck.has(outside), "beyond the +-130 px box at rank 1")
	assert_eq(w.loadout.stats(BLIZZARD).box, Rect2(-130, -100, 260, 200))
	var crowd := _world(BLIZZARD)
	var slots := []
	for k in 9:
		slots.append(_mob(crowd, 20.0 + 12.0 * k))
	var hit := _struck(crowd, BLIZZARD)
	assert_eq(hit.size(), 6, "mobCount 6")
	for k in 6:
		assert_true(hit.has(slots[k]), "the six nearest to the caster are struck")


func test_blizzard_needs_a_monster_in_the_box_and_has_a_four_second_cooldown() -> void:
	var w := _world(BLIZZARD)
	_mob(w, 300)
	w.step(DT, MoveInput.new())
	assert_eq(w.runner.casts, 0, "min_targets 1: nothing in the box, no cast")
	_mob(w, 80)
	w.step(DT, MoveInput.new())
	assert_eq(w.runner.casts, 1)
	assert_near(float(w.runner.cooldowns[BLIZZARD]), 4.0 - DT, 0.001)
	assert_near(w.loadout.stats(BLIZZARD).cooldown, 4.0, 0.0001)


func test_blizzard_area_widens_the_box_and_a_final_attack_adds_a_second_volley() -> void:
	var plain := _world(BLIZZARD)
	var wide := _world(BLIZZARD)
	_mod(wide, BLIZZARD, "area", "mul", 1.2)
	var edge := {}
	for w: RunWorld in [plain, wide]:
		_mob(w, 80)
		edge[w] = _mob(w, 165) # body from 145: past +-130, inside +-156
	assert_near(wide.loadout.stats(BLIZZARD).box.size.x, 260.0 * 1.2, 0.01)
	assert_false(_struck(plain, BLIZZARD).has(edge[plain]))
	assert_true(_struck(wide, BLIZZARD).has(edge[wide]))
	var base := _world(BLIZZARD)
	var second := _world(BLIZZARD)
	for w: RunWorld in [base, second]:
		_mob(w, 60)
		_mob(w, -60)
	_mod(second, BLIZZARD, "attack_count", "add", 1)
	assert_eq(_hits(_run(base, 60), BLIZZARD).size(), 2, "one line on each of the two monsters")
	assert_eq(_hits(_run(second, 60), BLIZZARD).size(), 4, "a second line on each")


func test_blizzard_box_damage_and_freeze_follow_the_rank() -> void:
	var w := _world(BLIZZARD)
	var lo := w.loadout
	assert_eq(lo.stats(BLIZZARD, 1).box.size.x, 260.0, "WZ level 4: +-130")
	assert_eq(lo.stats(BLIZZARD, 4).box.size.x, 260.0, "WZ level 15: +-130")
	assert_eq(lo.stats(BLIZZARD, 8).box.size.x, 300.0, "WZ level 30: +-150")
	assert_true(lo.stats(BLIZZARD, 8).damage_pct > lo.stats(BLIZZARD, 4).damage_pct)
	assert_true(lo.stats(BLIZZARD, 4).damage_pct > lo.stats(BLIZZARD, 1).damage_pct)
	assert_eq(lo.stats(BLIZZARD, 1).mob_count, 6)
	var chances := []
	for rank_value in [1, 4, 8]:
		chances.append(w.book.canonical(BLIZZARD, w.book.canonical_level(BLIZZARD, rank_value), "x"))
	assert_true(chances[0] < chances[1] and chances[1] < chances[2], "the freeze chance rises with the rank: %s" % [chances])
	assert_eq(chances[2], 50.0, "x at the last level")


func test_blizzard_freezes_for_the_seconds_of_the_rank() -> void:
	for row: Array in [[1, 1.0], [4, 2.0], [8, 3.0]]:
		var w := _world(BLIZZARD, int(row[0]))
		_sure_freeze(w)
		var mob := _mob(w, 60)
		_run(w, 40)
		var left := w.swarm.status_time(mob, MobSwarm.FREEZE)
		assert_true(left > float(row[1]) - 0.6 and left <= float(row[1]), "rank %d freezes for %s s (%s left)" % [int(row[0]), row[1], left])


func test_bosses_and_ice_immune_monsters_take_the_damage_but_not_the_freeze() -> void:
	var w := _world(BLIZZARD, 8)
	_sure_freeze(w)
	var boss := _mob(w, 40, true)
	var immune := _mob(w, 70)
	w.swarm.mob_kind(immune).element_codes = {"I": "1"}
	var plain := _mob(w, 100)
	_run(w, 50)
	# One MobKind per mob id: `immune` and `plain` share a kind in the fixture, so re-check plain on a world of its own.
	assert_eq(w.swarm.status_time(boss, MobSwarm.FREEZE), 0.0, "a boss refuses the freeze")
	assert_true(w.swarm.hp[boss] < w.swarm.max_hp[boss], "but takes the damage")
	assert_eq(w.swarm.status_time(immune, MobSwarm.FREEZE), 0.0, "an ice-immune monster refuses it")
	var alone := _world(BLIZZARD, 8)
	_sure_freeze(alone)
	var p := _mob(alone, 100)
	_run(alone, 50)
	assert_true(alone.swarm.status_time(p, MobSwarm.FREEZE) > 0.0, "an ordinary monster freezes")
	assert_true(plain >= 0)


func test_the_freeze_chance_is_rolled_once_per_hit_line_on_stream_one() -> void:
	var with_freeze := _world(BLIZZARD, 8)
	var without := _world(BLIZZARD, 8)
	without.book.defs[BLIZZARD].erase("on_hit")
	without.loadout.version += 1
	for w: RunWorld in [with_freeze, without]:
		for k in 5:
			_mob(w, 20.0 + 25.0 * k)
		_mob(w, 150.0, true) # a boss still takes the roll: the status layer refuses it afterwards
	_struck(with_freeze, BLIZZARD)
	_struck(without, BLIZZARD)
	# A PCG stream's state depends only on how many numbers were drawn: the plain world's advanced by one draw per hit line.
	var reference := RandomNumberGenerator.new()
	reference.state = without.rng.state
	for k in 6:
		reference.randf()
	assert_eq(with_freeze.rng.state, reference.state, "six hit lines, six chance draws on stream 1")


func test_the_freeze_chance_is_the_rank_chance_not_a_certainty() -> void:
	var frozen := {1: 0, 8: 0}
	var trials := 24
	for rank_value: int in frozen:
		for s in trials:
			var w := _world(BLIZZARD, rank_value, 1000 + s)
			var slots := []
			for k in 6:
				slots.append(_mob(w, 20.0 + 20.0 * k))
			_run(w, 50)
			for m: int in slots:
				if w.swarm.status_time(m, MobSwarm.FREEZE) > 0.0:
					frozen[rank_value] += 1
	var n := float(trials * 6)
	var low := float(frozen[1]) / n
	var high := float(frozen[8]) / n
	assert_true(low > 0.08 and low < 0.42, "rank 1 (about 24%%) froze %.2f" % low)
	assert_true(high > 0.32 and high < 0.68, "rank 8 (50%%) froze %.2f" % high)
	assert_true(high > low)


func test_blizzard_draws_five_ice_arrows_across_the_box_and_uses_its_own_art() -> void:
	var w := _world(BLIZZARD)
	var d := w.book.def(BLIZZARD)
	assert_eq(String(d.effect), "Skill.wz/321.img/skill/3211003/effect", "the caster's flourish")
	assert_eq(String(d.hit), "Skill.wz/321.img/skill/3211003/hit/0")
	assert_eq(String(d.sounds.use), "Sound.wz/Skill.img/3211003/Use")
	assert_eq(String(d.sounds.hit), "Sound.wz/Skill.img/3211003/Hit")
	var plan := CastVisualPlan.expand(d.cast_visuals, w.loadout.stats(BLIZZARD).box)
	assert_eq(plan.size(), 5)
	for k in 5:
		assert_eq(String(plan[k].path), "Skill.wz/321.img/skill/3211003/special/0")
		assert_near(float(plan[k].delay), 0.09 * k, 0.0001, "one arrow every 90 ms")
		assert_eq(float(plan[k].fall), 400.0)
	assert_near(float(plan[4].delay) + float(plan[4].fall_time), 0.6, 0.02, "the last arrow lands with the strike")
	var wide := CastVisualPlan.expand(d.cast_visuals, Rect2(-156, -100, 312, 200))
	assert_true(float(wide[4].x) > float(plan[4].x), "a wider box spreads them wider")


func test_a_map_transfer_clears_the_pending_blizzard() -> void:
	var w := _world(BLIZZARD)
	var m := _mob(w, 60)
	w.step(DT, MoveInput.new())
	w.runner.clear_pending(w)
	_run(w, 80)
	assert_eq(w.swarm.hp[m], w.swarm.max_hp[m])


# --- Arrow Eruption ---------------------------------------------------------------------------------------------------

func test_arrow_eruption_strikes_half_a_second_after_the_cast_at_the_spot_the_caster_stood() -> void:
	var w := _world(ERUPTION)
	var near := _mob(w, 160) # inside +-170, outside Blizzard's +-130
	w.step(DT, MoveInput.new())
	assert_eq(w.runner.casts, 1)
	var cast_at := w.time
	assert_true(_hits(w.drain_events(), ERUPTION).is_empty())
	w.player.pos.x += 700.0
	var first_hit := -1.0
	for tick in 60:
		w.step(DT, MoveInput.new())
		var hits := _hits(w.drain_events(), ERUPTION)
		if not hits.is_empty() and first_hit < 0.0:
			first_hit = w.time
			assert_eq(int(hits[0].mob), near)
	assert_near(first_hit - cast_at, 0.5, DT * 1.5, "the strike lands 0.5 s after the cast")


func test_arrow_eruption_strikes_around_the_caster_and_takes_the_six_nearest() -> void:
	var w := _world(ERUPTION)
	var left := _mob(w, -160)
	var right := _mob(w, 160)
	var outside := _mob(w, 200) # body from 180: past +-170
	var struck := _struck(w, ERUPTION)
	assert_true(struck.has(left) and struck.has(right))
	assert_false(struck.has(outside))
	assert_eq(w.loadout.stats(ERUPTION).box, Rect2(-170, -100, 340, 200))
	var crowd := _world(ERUPTION)
	var slots := []
	for k in 9:
		slots.append(_mob(crowd, 20.0 + 15.0 * k))
	var hit := _struck(crowd, ERUPTION)
	assert_eq(hit.size(), 6, "mobCount 6")
	for k in 6:
		assert_true(hit.has(slots[k]))


func test_arrow_eruption_needs_a_monster_in_the_box_and_has_a_five_second_cooldown() -> void:
	var w := _world(ERUPTION)
	_mob(w, 300)
	w.step(DT, MoveInput.new())
	assert_eq(w.runner.casts, 0)
	_mob(w, 80)
	w.step(DT, MoveInput.new())
	assert_eq(w.runner.casts, 1)
	assert_near(float(w.runner.cooldowns[ERUPTION]), 5.0 - DT, 0.001)
	assert_near(w.loadout.stats(ERUPTION).cooldown, 5.0, 0.0001)


func test_arrow_eruption_area_widens_the_box_and_a_final_attack_adds_a_second_volley() -> void:
	var plain := _world(ERUPTION)
	var wide := _world(ERUPTION)
	_mod(wide, ERUPTION, "area", "mul", 1.2)
	var edge := {}
	for w: RunWorld in [plain, wide]:
		_mob(w, 80)
		edge[w] = _mob(w, 205) # body from 185: past +-170, inside +-204
	assert_near(wide.loadout.stats(ERUPTION).box.size.x, 340.0 * 1.2, 0.01)
	assert_false(_struck(plain, ERUPTION).has(edge[plain]))
	assert_true(_struck(wide, ERUPTION).has(edge[wide]))
	var base := _world(ERUPTION)
	var second := _world(ERUPTION)
	for w: RunWorld in [base, second]:
		_mob(w, 60)
		_mob(w, -60)
	_mod(second, ERUPTION, "attack_count", "add", 1)
	assert_eq(_hits(_run(base, 60), ERUPTION).size(), 2)
	assert_eq(_hits(_run(second, 60), ERUPTION).size(), 4)


func test_arrow_eruption_box_and_damage_follow_the_rank() -> void:
	var w := _world(ERUPTION)
	var lo := w.loadout
	assert_eq(lo.stats(ERUPTION, 1).box.size.x, 340.0, "WZ level 4: +-170")
	assert_eq(lo.stats(ERUPTION, 4).box.size.x, 380.0, "WZ level 15: +-190")
	assert_eq(lo.stats(ERUPTION, 8).box.size.x, 420.0, "WZ level 30: +-210")
	assert_true(lo.stats(ERUPTION, 8).damage_pct > lo.stats(ERUPTION, 4).damage_pct)
	assert_true(lo.stats(ERUPTION, 4).damage_pct > lo.stats(ERUPTION, 1).damage_pct)
	assert_eq(lo.stats(ERUPTION, 1).mob_count, 6)


func test_arrow_eruption_applies_no_freeze_and_draws_three_arrows_around_the_caster() -> void:
	var w := _world(ERUPTION)
	var mob := _mob(w, 60)
	_run(w, 50)
	assert_eq(w.swarm.status_time(mob, MobSwarm.FREEZE), 0.0)
	var d := w.book.def(ERUPTION)
	assert_eq(String(d.effect), "Skill.wz/321.img/skill/3211004/effect")
	assert_eq(String(d.hit), "Skill.wz/321.img/skill/3211004/hit/0")
	assert_eq(String(d.sounds.use), "Sound.wz/Skill.img/3211004/Use")
	assert_false(d.sounds.has("hit"), "the book has no Hit sound")
	var plan := CastVisualPlan.expand(d.cast_visuals, w.loadout.stats(ERUPTION).box)
	assert_eq(plan.size(), 3)
	for k in 3:
		assert_eq(String(plan[k].path), "Skill.wz/321.img/skill/3211004/special/0")
		assert_near(float(plan[k].delay), 0.09 * k, 0.0001)
		assert_eq(float(plan[k].fall), 150.0)
	assert_true(float(plan[0].delay) + float(plan[0].fall_time) <= 0.5 and float(plan[2].delay) + float(plan[2].fall_time) <= 0.5,
		"all three have landed by the strike")


# --- rarity bonuses ---------------------------------------------------------------------------------------------------

func test_the_catalog_lists_the_specs_bonuses_for_both_skills() -> void:
	var skills: Dictionary = DataRepo.load_all().skills.skills
	var epic := {BLIZZARD: ["wide_blizzard", "Wide Blizzard"], ERUPTION: ["wide_eruption", "Wide Eruption"]}
	for key: String in KEYS:
		var bonuses: Dictionary = skills[key].rarity_bonuses
		for tier: String in TIERS:
			assert_eq(bonuses[tier].size(), 1, "%s %s" % [key, tier])
		var rare: Dictionary = bonuses.rare[0]
		assert_eq([String(rare.id), String(rare.text)], ["crossbow_mastery", "Crossbow Mastery"], key)
		assert_eq(rare.effects, [{"stat": "damage", "op": "mul", "value": 1.2}], key)
		var wide: Dictionary = bonuses.epic[0]
		assert_eq([String(wide.id), String(wide.text)], epic[key], key)
		assert_eq(wide.effects, [{"stat": "area", "op": "mul", "value": 1.2}], key)
		var unique: Dictionary = bonuses.unique[0]
		assert_eq([String(unique.id), String(unique.text)], ["final_attack", "Final Attack"], key)
		assert_eq(unique.effects, [{"stat": "attack_count", "op": "add", "value": 1.0}], key)
		var legendary: Dictionary = bonuses.legendary[0]
		assert_eq(String(legendary.id), String(unique.id), "%s: Legendary shares the Unique's repeat counter" % key)
		assert_eq(legendary.effects, [{"stat": "attack_count", "op": "add", "value": 1.0}, {"stat": "damage", "op": "mul", "value": 1.2}], key)


func test_each_bonus_changes_the_resolved_cast() -> void:
	for key: String in KEYS:
		var skills: Dictionary = DataRepo.load_all().skills.skills
		var plain := _world(key, 4)
		var before := plain.loadout.stats(key)
		for tier: String in TIERS:
			var w := _world(key, 4)
			for bonus: Dictionary in skills[key].rarity_bonuses[tier]:
				for effect: Dictionary in bonus.effects:
					_mod(w, key, String(effect.stat), String(effect.op), float(effect.value))
			var after := w.loadout.stats(key)
			var label := "%s %s" % [key, tier]
			assert_true(after.damage_max != before.damage_max or after.box != before.box or after.attack_count != before.attack_count, label)
			match tier:
				"rare": assert_near(float(after.damage_max), float(before.damage_max) * 1.2, 1.0, label)
				"epic": assert_near(after.box.size.x, before.box.size.x * 1.2, 0.01, label)
				"unique": assert_eq(after.attack_count, before.attack_count + 1, label)
				"legendary":
					assert_eq(after.attack_count, before.attack_count + 1, label)
					assert_near(float(after.damage_max), float(before.damage_max) * 1.2, 1.0, label)


func test_a_rare_or_better_card_adds_one_rank_plus_its_bonus() -> void:
	for key: String in KEYS:
		for tier: String in TIERS:
			var a := _world(key)
			var b := _world(key)
			var c := a.upgrades.choice_card(key + "_rank", a, tier)
			assert_false(c.get("rarity_bonus", {}).is_empty(), "%s %s offers a bonus" % [key, tier])
			a.upgrades.apply(key + "_rank", a, tier)
			b.upgrades.apply(key + "_rank", b, tier)
			assert_eq(a.loadout.rank(key), 2, "%s %s: exactly one rank on top" % [key, tier])
			assert_eq(a.loadout.skill_mods.get(key, {}), b.loadout.skill_mods.get(key, {}))
			assert_false(a.loadout.skill_mods.get(key, {}).is_empty(), "%s %s: the bonus is applied" % [key, tier])
			var plain := _world(key)
			plain.loadout.set_rank(key, 2)
			assert_ne(a.loadout.stats(key), plain.loadout.stats(key), "%s %s changes the resolved cast beyond the rank" % [key, tier])


func test_legendary_shares_the_uniques_counter_and_mastery_repeats_shrink() -> void:
	for key: String in KEYS:
		var w := _world(key)
		w.upgrades.apply(key + "_rank", w, "unique")
		w.upgrades.apply(key + "_rank", w, "legendary")
		assert_eq(int(w.loadout.card_ranks["bonus:%s:final_attack" % key]), 2, "%s: one counter for both" % key)
		assert_near(w.loadout.skill_stat(key, "attack_count", 1.0), 1.0 + 1.0 + 0.8, 0.00001, "%s: the second award x0.8" % key)
		var m := _world(key)
		m.loadout.set_rank(key, 8)
		var expected := 1.0
		for n in 3:
			m.upgrades.apply(key + "_rank", m, "normal")
			expected *= 1.0 + 0.05 * pow(0.8, n)
			assert_near(m.loadout.skill_stat(key, "damage", 1.0), expected, 0.00001, "%s Mastery repeat %d" % [key, n])
		assert_eq(m.loadout.rank(key), 8, "Mastery never raises the rank")


func test_the_rarity_cards_change_what_a_cast_strikes_in_play() -> void:
	for key: String in KEYS:
		var base_extent: float = 130.0 if key == BLIZZARD else 170.0
		var plain := _world(key)
		var wide := _world(key)
		_mod(wide, key, "area", "mul", 1.2)
		var edge := {}
		for w: RunWorld in [plain, wide]:
			_mob(w, 40)
			edge[w] = _mob(w, base_extent + 30.0) # the 40 px body starts 10 px past the plain box
		assert_false(_struck(plain, key).has(edge[plain]), key)
		assert_true(_struck(wide, key).has(edge[wide]), key)
		var strong := _world(key)
		_mod(strong, key, "damage", "mul", 1.2)
		var base := _world(key)
		for w: RunWorld in [base, strong]:
			w.loadout.add_player_mod("damage", "mul", 100.0) # the fixture monster's defence would floor both hits
			w.refresh_player_stats()
			_mob(w, 40)
		var base_damage := 0
		for e: Dictionary in _hits(_run(base, 60), key):
			base_damage += int(e.damage)
		var strong_damage := 0
		for e: Dictionary in _hits(_run(strong, 60), key):
			strong_damage += int(e.damage)
		assert_true(base_damage > 0 and strong_damage > base_damage, "%s: Crossbow Mastery hits harder (%d vs %d)" % [key, strong_damage, base_damage])


# --- presentation -----------------------------------------------------------------------------------------------------

func test_the_skill_window_states_the_freeze_of_blizzard() -> void:
	var w := _world(BLIZZARD, 8)
	var line := SkillText.new(w.book).level_line(BLIZZARD, 30, w.loadout.stats(BLIZZARD))
	assert_true(line.contains("Damage 140%") and line.contains("50% chance to freeze for 3 sec"), line)


# --- real cache: all eight ranks against Skill.wz ----------------------------------------------------------------------

func test_real_cache_all_eight_ranks_map_to_the_skill_wz_levels() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	assert_true(lib.open())
	var img := lib.img("Skill.wz/321.img")
	assert_true(img != null, "Skill.wz/321.img is in the cache")
	if img == null:
		lib.free()
		return
	var book := SkillBook.from_data(DataRepo.load_all().skills, {"321": img.root})
	var lo := Loadout.new(book)
	lo.weapon_family = "crossbow"
	var levels := [4, 8, 12, 15, 19, 23, 27, 30]
	var ids := {BLIZZARD: 3211003, ERUPTION: 3211004}
	for key: String in KEYS:
		var node: Dictionary = img.root.skill["%07d" % int(ids[key])]
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
			var lt: Array = level.lt["$v"]
			var rb: Array = level.rb["$v"]
			assert_eq(st.box, Rect2(float(lt[0]), float(lt[1]), float(rb[0]) - float(lt[0]), float(rb[1]) - float(lt[1])), label)
			assert_eq(st.mob_count, int(level.mobCount), label)
			assert_eq(st.mob_count, 6, label)
			assert_eq(st.attack_count, 1, label)
			if key == BLIZZARD:
				assert_eq(book.canonical(key, lv, "x"), float(level.x), label)
				assert_eq(book.canonical(key, lv, "time"), float(level.time), label)
				assert_false(level.has("prop"), "%s: the node has no prop" % label)
	for i in 3:
		var r: int = [1, 4, 8][i]
		assert_near(lo.stats(BLIZZARD, r).damage_pct, [1.06, 1.28, 1.40][i], 0.000001, "Blizzard rank %d" % r)
		assert_eq(lo.stats(BLIZZARD, r).box.size.x, [260.0, 260.0, 300.0][i], "Blizzard box rank %d" % r)
		assert_eq(book.canonical(BLIZZARD, book.canonical_level(BLIZZARD, r), "x"), [24.0, 35.0, 50.0][i], "freeze chance rank %d" % r)
		assert_eq(book.canonical(BLIZZARD, book.canonical_level(BLIZZARD, r), "time"), [1.0, 2.0, 3.0][i], "freeze seconds rank %d" % r)
		assert_near(lo.stats(ERUPTION, r).damage_pct, [0.75, 1.22, 1.60][i], 0.000001, "Arrow Eruption rank %d" % r)
		assert_eq(lo.stats(ERUPTION, r).box.size.x, [340.0, 380.0, 420.0][i], "Arrow Eruption box rank %d" % r)
	for key: String in KEYS:
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
