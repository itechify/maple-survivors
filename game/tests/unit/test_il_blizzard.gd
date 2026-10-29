extends TestCase
## I/L Blizzard (spec #319 I10 #329): Meteor Shower's mirror with the freeze its WZ `time` carries. Seeded fixed-tick
## casts at the RunWorld boundary on a synthetic book 222: the 1.6 s delay, the live query at impact, the 15-mob cap, the
## freeze (bosses and ice-immune mobs refuse it), the tile placement and the transfer clear.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const IlBigBang := preload("res://tests/unit/test_il_big_bang.gd")
const DT := 1.0 / 60.0
const BLIZZARD := 2221007


## A synthetic 222 level table in the WZ shape of Blizzard: the (-400,-350)..(400,250) box, 15 mobs, one freeze `time`.
static func levels(mad: float, attack_count: float, time: float = 2.0) -> Dictionary:
	var out := {}
	for lv in range(1, 31):
		out[str(lv)] = {"mad": mad, "mobCount": 15.0, "attackCount": attack_count, "time": time,
			"lt": {"$v": [-400, -350]}, "rb": {"$v": [400, 250]}}
	return out


func _world(attack_count: float = 1.0, mad: float = 120.0) -> RunWorld:
	var setup := RF.setup("quiet", 329, RF.quiet_data())
	setup.skill_imgs["222"] = {"skill": {str(BLIZZARD): {"level": levels(mad, attack_count)}}}
	var w := RunWorld.new(setup)
	RF.place_player(w, 200)
	w.loadout.order.clear()
	w.learn_skill("blizzard")
	w.loadout.set_caster(100.0, 0.0, 30)
	return w


func _mob(w: RunWorld, x: float = 250.0, hp: int = 100000, id: int = 1110100) -> int:
	var m := RF.put_mob(w, id, x, 195, 100000.0)
	w.swarm.hp[m] = hp
	w.swarm.max_hp[m] = hp
	w.swarm.mob_kind(m).move_speed = 0.0
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	return m


func _advance(w: RunWorld, seconds: float) -> Array:
	w.loadout.order.clear()
	for tick in ceili(seconds / DT):
		w.runner.tick_cooldowns(DT, w)
	return w.drain_events()


func _hit_events(events: Array) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return e.type == "mob_hit")


func test_blizzard_is_defined_as_the_222_book_skill() -> void:
	var w := _world()
	var d := w.book.def("blizzard")
	assert_eq(int(d.skill_id), 2221007)
	assert_eq(String(d.book), "222")
	assert_eq(int(d.job), 222)
	assert_eq(String(d.slot), "active")
	assert_eq(String(d.element), "i")
	assert_eq(String(d.action), "blizzard")
	assert_near(float(d.cooldown), 4.8)


func test_no_damage_before_1_6_seconds_then_the_impact_lands() -> void:
	var w := _world()
	var m := _mob(w)
	w.runner.step(DT, w)
	assert_eq(w.swarm.hp[m], 100000, "nothing on the cast tick")
	_advance(w, 1.5)
	assert_eq(w.swarm.hp[m], 100000, "nothing before the WZ hitAfter of 1600 ms")
	var events := _advance(w, 0.12)
	assert_true(w.swarm.hp[m] < 100000, "the impact has landed")
	assert_true(events.any(func(e: Dictionary) -> bool: return e.type == "skill_impact" and e.skill == "blizzard"))


func test_targets_are_queried_at_impact_a_late_arrival_is_hit_and_a_departed_mob_is_not() -> void:
	var w := _world()
	var leaves := _mob(w, 250)
	var arrives := _mob(w, 1500)  # outside the box (400 px) at the cast
	w.runner.step(DT, w)
	_advance(w, 1.0)
	w.swarm.x[leaves] = 1500.0
	w.swarm.x[arrives] = 300.0
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	_advance(w, 0.7)
	assert_eq(w.swarm.hp[leaves], 100000, "it left the box before the impact")
	assert_true(w.swarm.hp[arrives] < 100000, "it arrived during the delay")


func test_a_mob_that_dies_during_the_delay_is_skipped_without_error() -> void:
	var w := _world()
	var dies := _mob(w, 250)
	var lives := _mob(w, 300)
	w.runner.step(DT, w)
	_advance(w, 1.0)
	w.swarm.apply_hit(dies, 1000000, 1)
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	_advance(w, 0.7)
	assert_true(w.swarm.hp[lives] < 100000)
	assert_eq(w.swarm.hp[dies], 0)


func test_the_impact_strikes_at_most_fifteen_mobs() -> void:
	var w := _world()
	var mobs := []
	for k in 20:
		mobs.append(_mob(w, 20.0 * k - 100.0 + 200.0))
	w.runner.step(DT, w)
	_advance(w, 1.5)
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


func test_every_hit_line_attempts_the_freeze_for_the_canonical_time() -> void:
	var w := _world(2.0)
	var m := _mob(w)
	var attempts := [0]
	w.add_hit_listener(func(slot: int, hit: Dictionary) -> void:
		if slot == m and hit.skill == "blizzard":
			attempts[0] += 1)
	w.runner.step(DT, w)
	assert_eq(w.swarm.status_time(m, MobSwarm.FREEZE), 0.0, "no freeze before the impact")
	_advance(w, 1.7)
	assert_eq(attempts[0], 2, "two damaging lines")
	assert_true(w.swarm.status_time(m, MobSwarm.FREEZE) > 1.0, "frozen for about the WZ time of 2 s")
	assert_true(w.swarm.status_time(m, MobSwarm.FREEZE) <= 2.0)


func test_bosses_and_ice_immune_mobs_take_the_damage_but_not_the_freeze() -> void:
	var w := _world()
	# One MobKind per mob: the flags below live on the kind.
	var boss := _mob(w, 250, 100000, 1210100)
	w.swarm.mob_kind(boss).boss = true
	var immune := _mob(w, 300, 100000, 1210102)
	w.swarm.mob_kind(immune).element_codes = {"I": "1"}
	var plain := _mob(w, 350)
	w.runner.step(DT, w)
	_advance(w, 1.7)
	for m: int in [boss, immune, plain]:
		assert_true(w.swarm.hp[m] < 100000)
	assert_eq(w.swarm.status_time(boss, MobSwarm.FREEZE), 0.0)
	assert_eq(w.swarm.status_time(immune, MobSwarm.FREEZE), 0.0)
	assert_true(w.swarm.status_time(plain, MobSwarm.FREEZE) > 0.0)


func test_tiles_sit_at_the_180_px_effect_distance_across_nine_slots() -> void:
	var d := _world().book.def("blizzard")
	var visuals: Array = d.cast_visuals
	assert_eq(visuals.size(), 9)
	for k in 9:
		assert_eq(String(visuals[k].path), "Skill.wz/222.img/skill/2221007/tile/%d" % k)
		assert_eq(int(visuals[k].x), (k - 4) * 180, "tile %d" % k)
	assert_eq(String(d.effect), "Skill.wz/222.img/skill/2221007/effect", "the 25-frame effect plays on the caster")
	assert_eq(String(d.hit), "Skill.wz/222.img/skill/2221007/hit/0")


func test_a_map_transfer_clears_the_pending_blizzard() -> void:
	var w := _world()
	var m := _mob(w)
	w.runner.step(DT, w)
	w.runner.clear_pending()
	_advance(w, 2.0)
	assert_eq(w.swarm.hp[m], 100000)


# --- rarity bonuses (spec #319 "Rarity bonuses", the H7 lesson: every effect must change the resolved cast) --------------

const TIERS := ["rare", "epic", "unique", "legendary"]
const CASTER_X := 2000.0
const FLAT := [{"x1": 0, "y1": 200, "x2": 4000, "y2": 200}]


## A job-222 world (playable flipped in the test copy of the data) with only `key` learned, god mode, a long flat floor.
func _il_world(key: String) -> RunWorld:
	var data := RF.quiet_data()
	var setup := RF.setup("quiet", 329, data)
	setup.skill_imgs["222"] = {"skill": {str(BLIZZARD): {"level": levels(120.0, 1.0)},
		"2221001": {"level": IlBigBang.levels(120.0, 1.0)}}}
	setup.skill_imgs["212"] = {"skill": {"2121001": {"level": IlBigBang.levels(120.0, 1.0)}}}
	var w := RunWorld.new(setup)
	w.set_job(222)
	w.bounds = Rect2(0, -500, 4000, 1000)
	w.fhm = FootholdMap.from_segments(FLAT)
	w.swarm.fhm = w.fhm
	RF.place_player(w, CASTER_X)
	w.loadout.ranks.clear()
	w.loadout.order.clear()
	w.learn_skill(key)
	w.god = true
	for mk: MobKind in w.mob_kinds:
		mk.hitbox = Rect2(-5, -10, 10, 10)
		mk.move_speed = 0.0
	w.drain_events()
	return w


## What one probe cast of `key` with `effects` did: hit lines, mobs struck, damage dealt, and whether the edge mob was struck.
## Mobs stand inside the box; the edge mob stands just beyond the base half-width (400 px Blizzard, 250 px Big Bang).
func _probe(key: String, effects: Array, edge_offset: float) -> Dictionary:
	var w := _il_world(key)
	var slots := []
	for off: float in [60.0, -90.0, 120.0, -150.0]:
		slots.append(RF.put_mob(w, 1110100, CASTER_X + off, 190.0, 100000.0))
	var edge := RF.put_mob(w, 1110100, CASTER_X + edge_offset, 190.0, 100000.0)
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


func test_each_blizzard_bonus_effect_changes_the_resolved_cast() -> void:
	var w := _il_world("blizzard")
	var bonuses: Dictionary = w.book.def("blizzard").rarity_bonuses
	var base := _probe("blizzard", [], 440.0)
	assert_false(bool(base.edge), "the edge mob is outside the base box")
	assert_true(int(base.lines) > 0, "the probe casts")
	var seen := {}
	for tier: String in TIERS:
		assert_eq(bonuses[tier].size(), 1, tier)
		for effect: Dictionary in bonuses[tier][0].effects:
			var with := _probe("blizzard", [effect], 440.0)
			var label := "%s %s" % [tier, effect.stat]
			match String(effect.stat):
				"damage": assert_true(int(with.dealt) > int(base.dealt), "%s: damage dealt %d -> %d" % [label, base.dealt, with.dealt])
				"area": assert_true(bool(with.edge), "%s: the mob beyond the base box is inside the widened one" % label)
				"attack_count": assert_true(int(with.lines) > int(base.lines), "%s: hit lines %d -> %d" % [label, base.lines, with.lines])
				_: fail("%s: a stat this audit does not know" % label)
			seen[String(effect.stat)] = true
	assert_eq(seen.keys().size(), 3, "damage, area and attack_count are all exercised")


func test_each_inherited_big_bang_bonus_effect_changes_the_resolved_cast_for_job_222() -> void:
	var w := _il_world("big_bang_il")
	var bonuses: Dictionary = w.book.def("big_bang_il").rarity_bonuses
	var base := _probe("big_bang_il", [], 275.0)
	assert_false(bool(base.edge))
	assert_true(int(base.lines) > 0)
	for tier: String in TIERS:
		for effect: Dictionary in bonuses[tier][0].effects:
			var with := _probe("big_bang_il", [effect], 275.0)
			match String(effect.stat):
				"damage": assert_true(int(with.dealt) > int(base.dealt), "%s damage" % tier)
				"area": assert_true(bool(with.edge), "%s area" % tier)
				"attack_count": assert_true(int(with.lines) > int(base.lines), "%s attack_count" % tier)
				_: fail("%s: a stat this audit does not know" % tier)


func test_the_probe_catches_a_modifier_blizzard_never_reads() -> void:
	# `range` is a nearest-target stat; the box rule ignores it, so a bonus built on it would be a dead card.
	var reach := {"stat": "range", "op": "mul", "value": 1.5}
	assert_false(bool(_probe("blizzard", [reach], 440.0).edge), "a range modifier does not widen a box")


func test_blizzard_cards_follow_the_rare_plus_rank_rule_the_shared_legendary_counter_and_mastery() -> void:
	for tier: String in TIERS:
		var a := _il_world("blizzard")
		var b := _il_world("blizzard")
		var c := a.upgrades.choice_card("blizzard_rank", a, tier)
		assert_false(c.get("rarity_bonus", {}).is_empty(), "%s offers a bonus" % tier)
		assert_eq(c, a.upgrades.choice_card("blizzard_rank", a, tier), "preview is stable")
		a.upgrades.apply("blizzard_rank", a, tier)
		b.upgrades.apply("blizzard_rank", b, tier)
		assert_eq(a.loadout.rank("blizzard"), 2, "%s: exactly one rank" % tier)
		assert_eq(a.loadout.skill_mods.get("blizzard", {}), b.loadout.skill_mods.get("blizzard", {}), "same bonus both runs")
	var w := _il_world("blizzard")
	w.upgrades.apply("blizzard_rank", w, "epic")
	w.upgrades.apply("blizzard_rank", w, "epic")
	assert_near(w.loadout.stats("blizzard").area, 1.2 * 1.16, 0.00001, "the second Epic is x1.16")
	var hits := _il_world("blizzard")
	var base_lines: int = hits.loadout.stats("blizzard").attack_count
	hits.upgrades.apply("blizzard_rank", hits, "unique")
	hits.upgrades.apply("blizzard_rank", hits, "legendary")
	assert_near(hits.loadout.skill_stat("blizzard", "attack_count", 1.0), 1.0 + 1.0 + 0.8, 0.00001,
		"Unique and Legendary share the echo counter")
	assert_near(hits.loadout.skill_stat("blizzard", "damage", 1.0), 1.0 + 0.2 * 0.8, 0.00001,
		"the Legendary's damage x1.2 shrinks with the repeat of the shared echo counter")
	assert_true(int(hits.loadout.stats("blizzard").attack_count) > base_lines)
	var m := _il_world("blizzard")
	m.loadout.set_rank("blizzard", 8)
	var normal := m.upgrades.choice_card("blizzard_rank", m, "normal")
	assert_eq(normal.card_kind, "mastery")
	m.upgrades.apply("blizzard_rank", m, "normal")
	m.upgrades.apply("blizzard_rank", m, "normal")
	assert_near(m.loadout.skill_stat("blizzard", "damage", 1.0), 1.05 * 1.04, 0.00001, "Mastery repeats shrink x0.8")
	assert_eq(m.loadout.rank("blizzard"), 8)
