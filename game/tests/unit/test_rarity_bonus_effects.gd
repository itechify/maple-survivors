extends TestCase
## Every rarity bonus of every Hero and F/P skill changes the resolved cast, not just a stat number (spec #296, H7 audit).
## For each effect of each tier the same seeded world is cast twice, with and without the effect, against a field of mobs
## laid out to expose that one stat: damage (damage dealt over 12 s), cooldown (casts in 66 s), attack_count (hit events), count and
## pierce (mobs affected), summon_count (allies), meter_keep (orbs left after a finisher), and area / range (a mob just beyond the base reach is only affected with
## the effect). A bonus whose stat the skill's cast rule never reads fails here as a no-op.
## Hero books (111/112) are synthetic generic tables; the F/P books come from the shared run fixtures. Bowmaster's Hurricane
## (B10 #342) runs as a Bowmaster holding a bow with a synthetic damage table; on the burst rule `count` is arrows, so it shows
## in the hit lines on the one target it stream-fires at, not in the number of mobs affected.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const MOB := 1110100
const CASTER_X := 2000.0
const BOW := 1452051
const FLAT := [{"x1": 0, "y1": 200, "x2": 4000, "y2": 200}]
const TIERS := ["rare", "epic", "unique", "legendary"]
const CORE_STATS := ["damage", "cooldown", "attack_count", "count", "pierce", "summon_count", "area", "range", "meter_keep"]


## Generic Skill.wz levels: a centred box, six mobs, one line, a 300 px range, a certain proc (the shape test_fp_high_actives uses).
func _generic_levels() -> Dictionary:
	var levels := {}
	for lv in range(1, 31):
		levels[str(lv)] = {"damage": 100 + lv, "mad": 30.0, "mobCount": 6, "attackCount": 1, "range": 300, "prop": 100,
			"time": 4, "lt": {"$v": [-200, -150]}, "rb": {"$v": [200, 150]}}
	return levels


func _skills_with_bonuses() -> Array:
	var skills: Dictionary = DataRepo.load_all().skills.skills
	var keys := []
	for key: String in skills:
		if (skills[key] as Dictionary).has("rarity_bonuses") and (int(skills[key].job) < 300 or int(skills[key].job) == 312):
			keys.append(key)
	return keys


func _world(key: String) -> RunWorld:
	var data := RF.quiet_data()
	var job := 112 if int(data.skills.skills[key].job) in [100, 110, 111, 112] else 212
	if int(data.skills.skills[key].job) == 312:
		job = 312
	data.jobs_survivor.jobs["112"]["playable"] = true
	var setup := RF.with_basic_attack(RF.setup("quiet", 296, data))
	var imgs: Dictionary = setup.skill_imgs
	if job == 312:
		var levels := {}
		for lv in range(1, 31):
			levels[str(lv)] = {"hs": "h%d" % lv, "damage": float(51 + lv)}
		imgs["312"] = {"skill": {"3121004": {"level": levels}}}
		setup.equipment_info.merge({BOW: {"incPAD": 28, "attackSpeed": 6, "tuc": 7}}, true)
	# Hero books are synthetic; the F/P box and crowd skills get the same generic table (their fixtures carry no box).
	for k: String in data.skills.skills:
		var d: Dictionary = data.skills.skills[k]
		var id := int(d.skill_id)
		if int(d.job) in [111, 112] or id in [2111002, 2111003, 2111006, 2121001, 2121003, 2121006, 2121007]:
			var book := String(d.book)
			if not imgs.has(book):
				imgs[book] = {"skill": {}}
			var node: Dictionary = imgs[book].skill.get("%07d" % id, imgs[book].skill.get(str(id), {}))
			node["level"] = _generic_levels()
			imgs[book].skill[str(id) if id >= 1000000 else "%07d" % id] = node
	var w := RunWorld.new(setup)
	if job == 312:
		assert_eq(w.wear_new_item(BOW), "")
		RF.change_job_bare(w, 312)
	else:
		w.set_job(job)
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


## The base horizontal reach of skill `key` in px: the box's far edge, a range, the weapon envelope or the summon's attack box.
func _reach(w: RunWorld, key: String) -> float:
	var st := w.loadout.stats(key)
	if String(st.kind) == "summon":
		return 200.0 # the fixture summon's attack box (run_fixtures.gd, #291)
	match String(st.cast_rule):
		"box":
			return maxf(absf((st.box as Rect2).position.x), absf((st.box as Rect2).end.x))
		"weapon_reach":
			return SkillRunner.reach_of(st, w)
		_:
			return float(st.range)


## Mob x offsets from the caster for `stat`'s probe (see the file doc); `edge` marks the mob just beyond the base reach.
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
	# Cooldown counts casts over 66 s (Shout: 6 at 12 s, 7 at 10.56 s); damage sums many casts so that rounding cannot hide a x1.2.
	var repeating := stat in ["cooldown", "damage"]
	var window := 66.0 if stat == "cooldown" else 12.0 if stat == "damage" else 3.5
	var affected := {}
	var lines := 0
	# A Combo finisher (Panic, Coma) needs orbs: ten every tick when counting casts or damage, five once otherwise, so
	# that `meter_keep` shows in what a single cast leaves behind.
	var finisher: bool = w.book.def(key).has("meter")
	var orbs_left := -1
	for tick in int(window / DT):
		if finisher and (repeating or w.runner.casts == 0):
			w.meter.value = 10 if repeating else 5
		w.step(DT, MoveInput.new())
		if finisher and orbs_left < 0 and w.runner.casts >= 1:
			orbs_left = w.meter.value
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
				affected[s] = true # a poison pulse
				w.swarm.hp[s] = w.swarm.max_hp[s]
	for s: int in slots:
		if absf(w.swarm.x[s] - float(x0[s])) > 1.0:
			affected[s] = true
	var edge_hit := false
	for s: int in edge_slots:
		edge_hit = edge_hit or affected.has(s)
	var direct_damage: bool = String(w.loadout.stats(key).damage_type) != "none"
	return {"casts": w.runner.casts, "dealt": w.damage_dealt - w.swarm.poison_dealt if direct_damage else w.swarm.poison_dealt, "lines": lines, "affected": affected.size(), "edge": edge_hit,
		"summons": w.runner.summons.active.count(1), "orbs_left": orbs_left}


func test_every_pool_skill_with_bonuses_was_found() -> void:
	var keys := _skills_with_bonuses()
	for key in ["power_strike", "slash_blast", "brandish", "shout", "monster_magnet", "panic", "coma", "energy_bolt", "explosion",
			"elquines", "hurricane"]:
		assert_true(key in keys, key)
	assert_true(keys.size() >= 19, "seven Hero, twelve F/P and one Bowmaster skills: %d" % keys.size())


func test_each_bonus_effect_changes_the_resolved_cast() -> void:
	var skills: Dictionary = DataRepo.load_all().skills.skills
	for key: String in _skills_with_bonuses():
		var bonuses: Dictionary = skills[key].rarity_bonuses
		for tier: String in TIERS:
			for bonus: Dictionary in bonuses[tier]:
				for effect: Dictionary in bonus.effects:
					_assert_effect_changes_the_cast(key, tier, String(bonus.id), effect)


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
			if stat == "count" and String(DataRepo.load_all().skills.skills[key].get("cast", {}).get("rule", "")) == "burst":
				assert_true(int(with.lines) > int(base.lines), "%s: arrows landed %d -> %d" % [label, base.lines, with.lines])
			else:
				assert_true(int(with.affected) > int(base.affected), "%s: mobs affected %d -> %d" % [label, base.affected, with.affected])
		"summon_count":
			assert_true(int(with.summons) > int(base.summons), "%s: allies %d -> %d" % [label, base.summons, with.summons])
		"meter_keep":
			assert_true(int(base.orbs_left) >= 0 and int(with.orbs_left) > int(base.orbs_left),
				"%s: orbs left after the cast %d -> %d" % [label, base.orbs_left, with.orbs_left])
		"area", "range":
			assert_false(bool(base.edge), "%s: the mob beyond the base reach is outside it" % label)
			assert_true(bool(with.edge), "%s: the mob beyond the base reach is inside the widened one" % label)


func test_the_probe_catches_a_modifier_the_cast_rule_never_reads() -> void:
	# Shout is a box rule: `range` is not read (its reach is the box). Brandish never reads `pierce`, Power Strike no `summon_count`.
	var reach := {"stat": "range", "op": "mul", "value": 1.2}
	assert_false(bool(_probe("shout", [reach], "range").edge), "a range modifier does not widen a box")
	var pierce := {"stat": "pierce", "op": "add", "value": 1.0}
	assert_eq(_probe("brandish", [pierce], "pierce").affected, _probe("brandish", [], "pierce").affected)
	var allies := {"stat": "summon_count", "op": "add", "value": 1.0}
	assert_eq(_probe("power_strike", [allies], "summon_count").summons, 0)
	# And the modifiers the shipped bonuses rely on do widen: area on a box, area on a radial range, range on a pull.
	var area := {"stat": "area", "op": "mul", "value": 1.2}
	assert_true(bool(_probe("shout", [area], "area").edge))
	assert_true(bool(_probe("slash_blast", [area], "area").edge))
	assert_true(bool(_probe("monster_magnet", [reach], "range").edge))
