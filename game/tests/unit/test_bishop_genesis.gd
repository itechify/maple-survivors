extends TestCase
## Bishop Genesis (spec #372, BS6 #378): Meteor Shower's holy mirror. Seeded fixed-tick casts at the RunWorld boundary on a
## synthetic book 232: the 1.8 s delay, the live query at impact, the 15-mob cap, the holy element, the tile placement at the
## 150 px effect distance, the transfer clear, and every rarity entry changing the resolved cast (the H7 lesson). The real-cache
## half is in test_bishop_genesis_cache.gd.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const BG := preload("res://tests/fixtures/bishop_genesis_fixtures.gd")
const DT := 1.0 / 60.0
const TIERS := ["rare", "epic", "unique", "legendary"]


func _mob(w: RunWorld, off: float, hp: int = 100000) -> int:
	var m := RF.put_mob(w, 1110100, BG.CASTER_X + off, 190.0, 100000.0)
	w.swarm.hp[m] = hp
	w.swarm.max_hp[m] = hp
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	return m


func _advance(w: RunWorld, seconds: float) -> Array:
	w.loadout.order.clear()
	for tick in ceili(seconds / DT):
		w.runner.tick_cooldowns(DT, w)
	return w.drain_events()


func _hit_events(events: Array) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return e.type == "mob_hit")


func test_genesis_is_defined_as_the_232_book_skill() -> void:
	var d := BG.world("genesis").book.def("genesis")
	assert_eq(int(d.skill_id), BG.GENESIS)
	assert_eq(String(d.book), "232")
	assert_eq(int(d.job), 232)
	assert_eq(String(d.slot), "active")
	assert_eq(String(d.element), "h")
	assert_eq(String(d.action), "genesis")
	assert_eq(String(d.kind), "instant")
	assert_eq(String(d.cast.rule), "box")
	assert_eq(int(d.cast.min_targets), 1)
	assert_near(float(d.cooldown), 6.0)
	assert_near(float(d.pending.delay), 1.8)
	assert_eq(String(d.sounds.use), "Sound.wz/Skill.img/2321008/Use")
	assert_eq(String(d.sounds.hit), "Sound.wz/Skill.img/2321008/Hit")
	assert_eq(String(d.icon), "Skill.wz/232.img/skill/2321008/icon")


func test_it_reads_the_wz_box_the_15_mob_cap_and_the_element_through_the_loadout() -> void:
	var w := BG.world("genesis")
	var st := w.loadout.stats("genesis")
	assert_eq(st.box, Rect2(-400, -350, 800, 600))
	assert_eq(int(st.mob_count), 15)
	assert_eq(String(st.element), "h")
	assert_eq(String(st.cast_rule), "box")


func test_the_skill_is_only_cast_with_a_monster_in_the_box() -> void:
	var w := BG.world("genesis")
	_mob(w, 600.0)  # beyond the 400 px half-width
	w.runner.step(DT, w)
	assert_eq(w.runner.casts, 0, "min_targets 1 and nobody in the box")
	_mob(w, 300.0)
	w.runner.step(DT, w)
	assert_eq(w.runner.casts, 1)


func test_no_damage_before_1_8_seconds_then_the_impact_lands() -> void:
	var w := BG.world("genesis")
	var m := _mob(w, 150.0)
	w.runner.step(DT, w)
	assert_eq(w.swarm.hp[m], 100000, "nothing on the cast tick")
	_advance(w, 1.7)
	assert_eq(w.swarm.hp[m], 100000, "nothing before the WZ hitAfter of 1800 ms")
	var events := _advance(w, 0.12)
	assert_true(w.swarm.hp[m] < 100000, "the impact has landed")
	assert_true(events.any(func(e: Dictionary) -> bool: return e.type == "skill_impact" and e.skill == "genesis"))


func test_targets_are_queried_at_impact_a_late_arrival_is_hit_and_a_departed_mob_is_not() -> void:
	var w := BG.world("genesis")
	var leaves := _mob(w, 250.0)
	var arrives := _mob(w, 1500.0)  # outside the box at the cast
	w.runner.step(DT, w)
	_advance(w, 1.0)
	w.swarm.x[leaves] = BG.CASTER_X + 1500.0
	w.swarm.x[arrives] = BG.CASTER_X + 300.0
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	_advance(w, 0.9)
	assert_eq(w.swarm.hp[leaves], 100000, "it left the box before the impact")
	assert_true(w.swarm.hp[arrives] < 100000, "it arrived during the delay")


func test_a_mob_that_dies_during_the_delay_is_skipped_without_error() -> void:
	var w := BG.world("genesis")
	var dies := _mob(w, 250.0)
	var lives := _mob(w, 300.0)
	w.runner.step(DT, w)
	_advance(w, 1.0)
	w.swarm.apply_hit(dies, 1000000, 1)
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	_advance(w, 0.9)
	assert_true(w.swarm.hp[lives] < 100000)
	assert_eq(w.swarm.hp[dies], 0)


func test_the_impact_strikes_at_most_fifteen_mobs() -> void:
	var w := BG.world("genesis")
	var mobs := []
	for k in 20:
		mobs.append(_mob(w, 20.0 * k - 100.0))
	w.runner.step(DT, w)
	_advance(w, 1.7)
	var events := _advance(w, 0.2)
	var struck := {}
	for e: Dictionary in _hit_events(events):
		struck[int(e.mob)] = true
	assert_eq(struck.size(), 15)
	var damaged := 0
	for m: int in mobs:
		if w.swarm.hp[m] < 100000:
			damaged += 1
	assert_eq(damaged, 15)


func test_the_damage_is_holy_a_holy_weak_mob_takes_more_and_a_holy_immune_one_none() -> void:
	var dealt := {}
	for label: String in ["neutral", "weak", "immune"]:
		var w := BG.world("genesis")
		var m := _mob(w, 150.0)
		if label != "neutral":
			w.swarm.mob_kind(m).elements = {"H": 1.5 if label == "weak" else 0.0}
		w.runner.step(DT, w)
		_advance(w, 2.0)
		dealt[label] = 100000 - w.swarm.hp[m]
	assert_true(dealt.neutral > 0)
	assert_true(dealt.weak > dealt.neutral, "holy-weak %d vs neutral %d" % [dealt.weak, dealt.neutral])
	assert_eq(dealt.immune, 0, "a holy-immune mob takes nothing")


func test_every_attack_count_line_lands_at_the_impact() -> void:
	var w := BG.world("genesis", 120.0, 3.0)
	var m := _mob(w, 150.0)
	w.runner.step(DT, w)
	var lines := _hit_events(_advance(w, 2.0)).filter(func(e: Dictionary) -> bool: return int(e.mob) == m)
	assert_eq(lines.size(), 3, "attackCount 3 comes from 232.img")


func test_tiles_sit_at_the_150_px_effect_distance_across_nine_slots() -> void:
	var d := BG.world("genesis").book.def("genesis")
	var visuals: Array = d.cast_visuals
	assert_eq(visuals.size(), 10, "nine tiles and effect0")
	for k in 9:
		assert_eq(String(visuals[k].path), "Skill.wz/232.img/skill/2321008/tile/%d" % k)
		assert_eq(int(visuals[k].x), (k - 4) * 150, "tile %d" % k)
	assert_eq(String(visuals[9].path), "Skill.wz/232.img/skill/2321008/effect0")
	assert_eq(int(visuals[9].x), 0, "effect0 sits on the caster")
	assert_eq(String(d.effect), "Skill.wz/232.img/skill/2321008/effect")
	assert_eq(String(d.hit), "Skill.wz/232.img/skill/2321008/hit/0")


func test_a_map_transfer_clears_the_pending_genesis() -> void:
	var w := BG.world("genesis")
	var m := _mob(w, 150.0)
	w.runner.step(DT, w)
	w.runner.clear_pending()
	_advance(w, 2.5)
	assert_eq(w.swarm.hp[m], 100000)


# --- rarity bonuses (spec #372 "Rarity bonuses", the H7 lesson: every effect must change the resolved cast) -----------------

## What one probe cast of `key` with `effects` did: hit lines, mobs struck, damage dealt, and whether the edge mob was struck.
## Mobs stand inside the box; the edge mob stands just beyond the base half-width (400 px Genesis, 250 px Big Bang).
func _probe(key: String, effects: Array, edge_offset: float) -> Dictionary:
	var w := BG.world(key)
	for off: float in [60.0, -90.0, 120.0, -150.0]:
		RF.put_mob(w, 1110100, BG.CASTER_X + off, 190.0, 100000.0)
	var edge := RF.put_mob(w, 1110100, BG.CASTER_X + edge_offset, 190.0, 100000.0)
	for e: Dictionary in effects:
		w.loadout.add_skill_mod(key, String(e.stat), String(e.op), float(e.value))
	var lines := 0
	var struck := {}
	for tick in int(5.0 / DT):
		w.step(DT, MoveInput.new())
		if w.runner.casts >= 1:
			w.runner.cooldowns[key] = 1.0e9
		for e: Dictionary in w.drain_events():
			if e.type == "mob_hit":
				lines += 1
				struck[int(e.mob)] = true
	return {"lines": lines, "struck": struck.size(), "dealt": w.damage_dealt, "edge": struck.has(edge)}


func _audit(key: String, edge_offset: float) -> int:
	var bonuses: Dictionary = BG.world(key).book.def(key).rarity_bonuses
	var base := _probe(key, [], edge_offset)
	assert_false(bool(base.edge), "%s: the edge mob is outside the base box" % key)
	assert_true(int(base.lines) > 0, "%s: the probe casts" % key)
	var seen := {}
	for tier: String in TIERS:
		assert_eq(bonuses[tier].size(), 1, "%s %s" % [key, tier])
		for effect: Dictionary in bonuses[tier][0].effects:
			var with := _probe(key, [effect], edge_offset)
			var label := "%s %s %s" % [key, tier, effect.stat]
			match String(effect.stat):
				"damage": assert_true(int(with.dealt) > int(base.dealt), "%s: damage dealt %d -> %d" % [label, base.dealt, with.dealt])
				"area": assert_true(bool(with.edge), "%s: the mob beyond the base box is inside the widened one" % label)
				"attack_count": assert_true(int(with.lines) > int(base.lines), "%s: hit lines %d -> %d" % [label, base.lines, with.lines])
				_: fail("%s: a stat this audit does not know" % label)
			seen[String(effect.stat)] = true
	return seen.size()


func test_the_genesis_rarity_ids_and_effects_are_the_specs() -> void:
	var b: Dictionary = BG.world("genesis").book.def("genesis").rarity_bonuses
	var wanted := {"rare": "power", "epic": "area", "unique": "echo", "legendary": "echo"}
	for tier: String in wanted:
		assert_eq(b[tier].size(), 1, tier)
		assert_eq(String(b[tier][0].id), wanted[tier], tier)
	assert_eq(_effects(b.rare), [["damage", "mul", 1.2]])
	assert_eq(String(b.epic[0].text), "Wider Genesis")
	assert_eq(_effects(b.epic), [["area", "mul", 1.2]])
	assert_eq(_effects(b.unique), [["attack_count", "add", 1.0]])
	assert_eq(_effects(b.legendary), [["attack_count", "add", 1.0], ["damage", "mul", 1.2]])


## [stat, op, value] triples of a tier's single bonus (JSON numbers are floats).
func _effects(bonus: Array) -> Array:
	return bonus[0].effects.map(func(e: Dictionary) -> Array: return [String(e.stat), String(e.op), float(e.value)])


func test_each_genesis_bonus_effect_changes_the_resolved_cast() -> void:
	assert_eq(_audit("genesis", 440.0), 3, "damage, area and attack_count are all exercised")


func test_each_inherited_big_bang_bonus_effect_changes_the_resolved_cast_for_job_232() -> void:
	assert_eq(_audit("big_bang_bishop", 275.0), 3, "damage, area and attack_count are all exercised")


func test_the_probe_catches_a_modifier_genesis_never_reads() -> void:
	# `range` is a nearest-target stat; the box rule ignores it, so a bonus built on it would be a dead card.
	var reach := {"stat": "range", "op": "mul", "value": 1.5}
	assert_false(bool(_probe("genesis", [reach], 440.0).edge), "a range modifier does not widen a box")


func test_genesis_cards_follow_the_rare_plus_rank_rule_the_shared_legendary_counter_and_mastery() -> void:
	for tier: String in TIERS:
		var a := BG.world("genesis")
		var b := BG.world("genesis")
		var c := a.upgrades.choice_card("genesis_rank", a, tier)
		assert_false(c.get("rarity_bonus", {}).is_empty(), "%s offers a bonus" % tier)
		assert_eq(c, a.upgrades.choice_card("genesis_rank", a, tier), "preview is stable")
		a.upgrades.apply("genesis_rank", a, tier)
		b.upgrades.apply("genesis_rank", b, tier)
		assert_eq(a.loadout.rank("genesis"), 2, "%s: exactly one rank" % tier)
		assert_eq(a.loadout.skill_mods.get("genesis", {}), b.loadout.skill_mods.get("genesis", {}), "same bonus both runs")
	var w := BG.world("genesis")
	w.upgrades.apply("genesis_rank", w, "epic")
	w.upgrades.apply("genesis_rank", w, "epic")
	assert_near(w.loadout.stats("genesis").area, 1.2 * 1.16, 0.00001, "the second Epic is x1.16")
	var hits := BG.world("genesis")
	hits.upgrades.apply("genesis_rank", hits, "unique")
	hits.upgrades.apply("genesis_rank", hits, "legendary")
	assert_near(hits.loadout.skill_stat("genesis", "attack_count", 1.0), 1.0 + 1.0 + 0.8, 0.00001,
		"Unique and Legendary share the echo counter")
	assert_near(hits.loadout.skill_stat("genesis", "damage", 1.0), 1.0 + 0.2 * 0.8, 0.00001,
		"the Legendary's damage x1.2 shrinks with the repeat of the shared echo counter")
	var m := BG.world("genesis")
	m.loadout.set_rank("genesis", 8)
	var normal := m.upgrades.choice_card("genesis_rank", m, "normal")
	assert_eq(normal.card_kind, "mastery")
	m.upgrades.apply("genesis_rank", m, "normal")
	m.upgrades.apply("genesis_rank", m, "normal")
	assert_near(m.loadout.skill_stat("genesis", "damage", 1.0), 1.05 * 1.04, 0.00001, "Mastery repeats shrink x0.8")
	assert_eq(m.loadout.rank("genesis"), 8)
