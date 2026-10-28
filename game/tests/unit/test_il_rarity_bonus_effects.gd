extends TestCase
## Every rarity bonus of every I/L Arch Mage skill changes the resolved cast, not just a stat number (spec #319, I6 #325;
## Hero's H7 audit, `test_rarity_bonus_effects` on spec/296-hero, is the model and is not on this branch yet).
## For each effect of each tier the same seeded world is cast twice, with and without the effect, against a field of mobs
## laid out to expose that one stat: damage (damage dealt over 12 s), cooldown (casts in 66 s), attack_count (hit events), count
## and pierce (mobs affected), summon_count (allies), and area / range (a mob just beyond the base reach is only affected with
## the effect). A bonus whose stat the skill's cast rule never reads fails here as a no-op.
## SKILLS lists the I/L skills covered; I8-I10 append theirs, with a fixture level table in the test's `_books()` if the
## skill needs one. Skill.wz tables are synthetic (test_il_bolts.gd `_books()`; Ice Demon and Element Composition use the
## small tables `_demon_levels` builds). Ifrit (I9) is a summon: its audit needs allies settled behind the player, so it
## stays in test_ifrit.gd.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const BOLTS := preload("res://tests/unit/test_il_bolts.gd")
const CHAIN := preload("res://tests/unit/test_il_chain_lightning.gd")
const BLIZZARD := preload("res://tests/unit/test_il_blizzard.gd")
const BIG_BANG := preload("res://tests/unit/test_il_big_bang.gd")
const DT := 1.0 / 60.0
const MOB := 1110100
const CASTER_X := 2000.0
const FLAT := [{"x1": 0, "y1": 200, "x2": 4000, "y2": 200}]
const TIERS := ["rare", "epic", "unique", "legendary"]
const CORE_STATS := ["damage", "cooldown", "attack_count", "count", "pierce", "summon_count", "area", "range"]
const SKILLS := ["energy_bolt", "magic_claw", "cold_beam", "thunder_bolt", "ice_strike", "thunder_spear", "ice_demon", "element_composition_il", "chain_lightning", "blizzard", "big_bang_il"]


## Synthetic Skill.wz levels 1..30 for Ice Demon (`box`: the canonical forward box) and Element Composition (I7 #326).
func _demon_levels(box: bool) -> Dictionary:
	var levels := {}
	for lv in range(1, 31):
		levels[str(lv)] = {"mad": 60.0 + lv, "mobCount": 6.0, "time": 4.0}
		if box:
			levels[str(lv)]["lt"] = {"$v": [-300, -100]}
			levels[str(lv)]["rb"] = {"$v": [-15, 0]}
	return levels


func _world(key: String) -> RunWorld:
	var data := RF.quiet_data()
	var setup := RF.setup("quiet", 325, data)
	var books := BOLTS._books()
	setup.job = 222
	setup.skill_imgs["220"].skill["2201004"] = books.cold
	setup.skill_imgs["220"].skill["2201005"] = books.thunder
	setup.skill_imgs["221"] = {"skill": {"2211002": books.strike, "2211003": books.spear,
		"2211006": {"level": _demon_levels(false)}}}
	# Blizzard (I10 #329: the WZ box, 15 mobs) and Big Bang I/L (no lt/rb, as in the WZ: the survivor box applies).
	setup.skill_imgs["222"] = {"skill": {"2221003": {"level": _demon_levels(true)},
		"2221006": CHAIN.book_node(),
		"2221007": {"level": BLIZZARD.levels(120.0, 1.0)}, "2221001": {"level": BIG_BANG.levels(120.0, 1.0)}}}
	var w := RunWorld.new(setup)
	w.bounds = Rect2(0, -500, 4000, 1000)
	w.fhm = FootholdMap.from_segments(FLAT)
	w.swarm.fhm = w.fhm
	RF.place_player(w, CASTER_X)
	w.loadout.ranks.clear()
	w.loadout.order.clear()
	w.learn_skill(key)
	w.loadout.set_rank(key, w.book.max_rank(key)) # the top rank: low-rank hits are so small that a x1.2 rounds away
	w.god = true
	for mk: MobKind in w.mob_kinds:
		mk.hitbox = Rect2(-5, -10, 10, 10)
		mk.move_speed = 0.0
	w.drain_events()
	return w


## The base horizontal reach of skill `key` in px: the box's far edge or the range.
func _reach(w: RunWorld, key: String) -> float:
	var st := w.loadout.stats(key)
	if String(st.cast_rule) == "box":
		return maxf(absf((st.box as Rect2).position.x), absf((st.box as Rect2).end.x))
	return float(st.range)


## Mob x offsets from the caster for `stat`'s probe; `edge` marks the mobs just beyond the base reach.
func _layout(stat: String, reach: float) -> Dictionary:
	var xs := []
	var edge := []
	match stat:
		"count":
			for k in 16:
				xs.append(reach * (0.3 + 0.6 * k / 15.0))
				xs.append(-reach * (0.3 + 0.6 * k / 15.0))
		"pierce":
			for k in 10:
				xs.append(reach * (0.15 + 0.7 * k / 9.0))
		"area", "range":
			xs.append_array([reach * 0.5, -reach * 0.5, reach * 0.6])
			edge = [reach * 1.1, -reach * 1.1]
			xs.append_array(edge)
		_:
			xs.append_array([reach * 0.5, -reach * 0.5, reach * 0.6, -reach * 0.8])
	return {"xs": xs, "edge": edge}


## Casts `key` with `effects` applied for the stat probe `stat`; returns what the cast did.
func _probe(key: String, effects: Array, stat: String) -> Dictionary:
	var w := _world(key)
	var reach := _reach(w, key)
	var layout := _layout(stat, reach)
	var slots := []
	var edge_slots := []
	for off: float in layout.xs:
		var slot := RF.put_mob(w, MOB, CASTER_X + off, 190.0, 100000.0)
		slots.append(slot)
		if off in layout.edge:
			edge_slots.append(slot)
	var x0 := {}
	for s: int in slots:
		x0[s] = w.swarm.x[s]
	for e: Dictionary in effects:
		w.loadout.add_skill_mod(key, String(e.stat), String(e.op), float(e.value))
	# Cooldown counts casts over 66 s; damage sums many casts so that rounding cannot hide a x1.2.
	var repeating := stat in ["cooldown", "damage"]
	var window := 66.0 if stat == "cooldown" else 12.0 if stat == "damage" else 3.5
	var affected := {}
	var lines := 0
	for tick in int(window / DT):
		w.step(DT, MoveInput.new())
		if not repeating and w.runner.casts >= 1:
			w.runner.cooldowns[key] = 1.0e9
		for e: Dictionary in w.drain_events():
			if e.type == "mob_hit":
				lines += 1
				affected[int(e.mob)] = true
		for s: int in slots:
			if repeating:
				w.swarm.x[s] = x0[s] # knockback must not walk the mobs out of the skill's reach between casts
			if w.swarm.hp[s] < w.swarm.max_hp[s]:
				w.swarm.hp[s] = w.swarm.max_hp[s]
	var edge_hit := false
	for s: int in edge_slots:
		edge_hit = edge_hit or affected.has(s)
	return {"casts": w.runner.casts, "dealt": w.damage_dealt, "lines": lines, "affected": affected.size(), "edge": edge_hit}


func test_every_covered_skill_has_bonuses_and_is_in_the_il_line() -> void:
	var il: Dictionary = BOLTS._skill_file("il_arch_mage")
	var resolved: Dictionary = SkillTemplate.resolve(DataRepo.load_all().skills.skills)  # a templated child inherits its lists
	for key: String in SKILLS:
		assert_true(il.has(key) or key in ["energy_bolt", "magic_claw"], key)
		assert_true(resolved[key].has("rarity_bonuses"), key)


func test_the_catalog_covers_the_whole_shipped_pool_including_the_summon_audit() -> void:
	var data := DataRepo.load_all()
	var pool: Array = data.jobs_survivor.jobs["222"].skill_pool.duplicate()
	var covered: Array = SKILLS.duplicate()
	covered.append("ifrit") # test_ifrit tests each effect with settled allies.
	pool.sort()
	covered.sort()
	assert_eq(covered, pool, "a new pool skill needs a resolved-cast audit")


func test_each_bonus_effect_changes_the_resolved_cast() -> void:
	var skills: Dictionary = SkillTemplate.resolve(DataRepo.load_all().skills.skills)
	var checked := 0
	for key: String in SKILLS:
		var bonuses: Dictionary = skills[key].rarity_bonuses
		for tier: String in TIERS:
			for bonus: Dictionary in bonuses[tier]:
				for effect: Dictionary in bonus.effects:
					_assert_effect_changes_the_cast(key, tier, String(bonus.id), effect)
					checked += 1
	assert_eq(checked, SKILLS.size() * 5, "each skill: 1 + 1 + 1 + 2 effects")


func _assert_effect_changes_the_cast(key: String, tier: String, id: String, effect: Dictionary) -> void:
	var stat := String(effect.stat)
	var label := "%s %s %s (%s)" % [key, tier, id, stat]
	assert_true(stat in CORE_STATS, "%s: a stat this audit knows" % label)
	var base := _probe(key, [], stat)
	var with := _probe(key, [effect], stat)
	match stat:
		"cooldown":
			assert_true(int(with.casts) > int(base.casts), "%s: casts %d -> %d" % [label, base.casts, with.casts])
		"damage":
			assert_true(int(with.dealt) > int(base.dealt), "%s: damage dealt %d -> %d" % [label, base.dealt, with.dealt])
		"attack_count":
			assert_true(int(with.lines) > int(base.lines), "%s: hit lines %d -> %d" % [label, base.lines, with.lines])
		"count", "pierce":
			assert_true(int(with.affected) > int(base.affected), "%s: mobs affected %d -> %d" % [label, base.affected, with.affected])
		"area", "range":
			assert_false(bool(base.edge), "%s: the mob beyond the base reach is outside it" % label)
			assert_true(bool(with.edge), "%s: the mob beyond the base reach is inside the widened one" % label)


func test_the_probe_catches_a_modifier_the_cast_rule_never_reads() -> void:
	# A box rule never reads `range`; a nearest rule reads neither `area` nor `pierce`.
	var reach := {"stat": "range", "op": "mul", "value": 1.2}
	assert_false(bool(_probe("thunder_bolt", [reach], "range").edge), "a range modifier does not widen a box")
	assert_false(bool(_probe("ice_strike", [reach], "range").edge))
	var area := {"stat": "area", "op": "mul", "value": 1.2}
	assert_false(bool(_probe("thunder_spear", [area], "area").edge), "an area modifier does not lengthen a nearest cast")
	var pierce := {"stat": "pierce", "op": "add", "value": 1.0}
	assert_eq(_probe("cold_beam", [pierce], "pierce").affected, _probe("cold_beam", [], "pierce").affected)
	assert_eq(_probe("ice_demon", [pierce], "pierce").affected, _probe("ice_demon", [], "pierce").affected)
	assert_false(bool(_probe("ice_demon", [reach], "range").edge), "a range modifier does not widen Ice Demon's box")
	# And the modifiers the shipped bonuses rely on do widen.
	assert_true(bool(_probe("thunder_bolt", [area], "area").edge))
	assert_true(bool(_probe("ice_strike", [area], "area").edge))
	assert_true(bool(_probe("ice_demon", [area], "area").edge))
