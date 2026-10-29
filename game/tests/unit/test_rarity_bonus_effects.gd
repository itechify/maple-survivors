extends TestCase
## Every rarity bonus of every Hero, F/P and I/L Arch Mage skill changes the resolved cast, not just a stat number (spec #296, H7
## audit; the I/L skills joined it in spec #319, I6 #325 / the merge of redesign).
## For each effect of each tier the same seeded world is cast twice, with and without the effect, against a field of mobs
## laid out to expose that one stat: damage (damage dealt over 12 s), cooldown (casts in 66 s), attack_count (hit events), count and
## pierce (mobs affected), summon_count (allies), meter_keep (orbs left after a finisher), and area / range (a mob just beyond the base reach is only affected with
## the effect). A bonus whose stat the skill's cast rule never reads fails here as a no-op.
## Hero books (111/112) are synthetic generic tables; the F/P and Bowman books come from the shared run fixtures. The Bowmaster
## core arrows (B7 #339) are probed as a Bowmaster holding a bow: an arrow stops at the first monster on its line, so the
## `count` probe counts hit lines, a `range` probe leaves only monsters beyond the base reach, and an
## `impact_blast` skill (Arrow Bomb, Inferno) shows `area` and `blast_targets` in a cluster around the first monster it reaches.
## Inferno (B9 #341) adds `burn_damage`: the fire a single cast leaves behind (`MobSwarm.burn_dealt` over 3.5 s) must grow.
## Hurricane (B10 #342) is a burst: its `count` is arrows, so it shows in the hit lines on the one target it stream-fires at, not
## in the number of mobs affected.
## The I/L skills (books 220/221/222) have their own synthetic Skill.wz tables (`il_fixtures.books()`, Ice Demon and Element
## Composition use the small tables `_demon_levels` builds) and are cast at their top rank, so the probes below are the same and
## only `_world` differs. Ifrit (I9) is a summon that needs allies settled behind the player: it stays in test_ifrit.gd
## (IL_AUDITED_ELSEWHERE).

const IL := preload("res://tests/fixtures/il_fixtures.gd")
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const BLIZZARD := preload("res://tests/unit/test_il_blizzard.gd")
const BIG_BANG := preload("res://tests/unit/test_il_big_bang.gd")
const DT := 1.0 / 60.0
const MOB := 1110100
const CASTER_X := 2000.0
const FLAT := [{"x1": 0, "y1": 200, "x2": 4000, "y2": 200}]
const TIERS := ["rare", "epic", "unique", "legendary"]
const FOLLOWERS := preload("res://tests/unit/test_bowmaster_followers.gd")
const CORE_STATS := ["damage", "cooldown", "attack_count", "count", "pierce", "summon_count", "area", "range", "meter_keep",
	"blast_targets", "burn_damage"]
const BOW := 1452051
## The Bowmaster skills this audit knows how to probe (tickets B7-B11 add theirs; B8 added Arrow Rain and Dragon's Breath, B9 Inferno, B10 Hurricane).
const BOWMASTER_KEYS := ["arrow_blow", "bow_double_shot", "arrow_bomb", "strafe", "arrow_rain", "dragons_breath", "inferno", "hurricane"]
## The I/L skills this audit casts (books 220/221/222); I8-I10 appended theirs.
const IL_SKILLS := ["cold_beam", "thunder_bolt", "ice_strike", "thunder_spear", "ice_demon", "element_composition_il",
	"chain_lightning", "blizzard", "big_bang_il"]
## The I/L skills with bonuses that another test audits: Ifrit is a summon (test_ifrit.gd).
const IL_AUDITED_ELSEWHERE := ["ifrit"]
const IL_BOOKS := [220, 221, 222]

var _resolved_skills := {}


## Generic Skill.wz levels: a centred box, six mobs, one line, a 300 px range, a certain proc (the shape test_fp_high_actives uses).
func _generic_levels() -> Dictionary:
	var levels := {}
	for lv in range(1, 31):
		levels[str(lv)] = {"damage": 100 + lv, "mad": 30.0, "mobCount": 6, "attackCount": 1, "range": 300, "prop": 100,
			"time": 4, "lt": {"$v": [-200, -150]}, "rb": {"$v": [200, 150]}}
	return levels


## The skills with rarity bonuses of the Magician, Warrior and I/L lines (job < 300), templates resolved: a skill that `extends`
## another inherits its lists, and the raw data would silently leave it out.
func _skills_with_bonuses() -> Array:
	var skills: Dictionary = _resolved()
	var keys := []
	for key: String in skills:
		if (skills[key] as Dictionary).has("rarity_bonuses") \
				and ((int(skills[key].job) < 300 and key not in IL_AUDITED_ELSEWHERE) or key in BOWMASTER_KEYS):
			keys.append(key)
	return keys


func _resolved() -> Dictionary:
	if _resolved_skills.is_empty():
		_resolved_skills = SkillTemplate.resolve(DataRepo.load_all().skills.skills)
	return _resolved_skills


## Synthetic Skill.wz levels 1..30 for Ice Demon (`box`: the canonical forward box) and Element Composition (I7 #326).
func _demon_levels(box: bool) -> Dictionary:
	var levels := {}
	for lv in range(1, 31):
		levels[str(lv)] = {"mad": 60.0 + lv, "mobCount": 6.0, "time": 4.0}
		if box:
			levels[str(lv)]["lt"] = {"$v": [-300, -100]}
			levels[str(lv)]["rb"] = {"$v": [-15, 0]}
	return levels


## An I/L world: job 222 with the I/L synthetic books, Blizzard (I10 #329: the WZ box, 15 mobs) and Big Bang I/L (no lt/rb, as in
## the WZ: the survivor box applies).
func _il_setup() -> Dictionary:
	var setup := RF.setup("quiet", 325, RF.quiet_data())
	var books := IL.books()
	setup.job = 222
	setup.skill_imgs["220"].skill["2201004"] = books.cold
	setup.skill_imgs["220"].skill["2201005"] = books.thunder
	setup.skill_imgs["221"] = {"skill": {"2211002": books.strike, "2211003": books.spear,
		"2211006": {"level": _demon_levels(false)}}}
	setup.skill_imgs["222"] = {"skill": {"2221003": {"level": _demon_levels(true)},
		"2221006": IL.chain_node(),
		"2221007": {"level": BLIZZARD.levels(120.0, 1.0)}, "2221001": {"level": BIG_BANG.levels(120.0, 1.0)}}}
	return setup


func _world(key: String) -> RunWorld:
	var il: bool = int(_resolved()[key].job) in IL_BOOKS
	if il:
		return _finish_world(RunWorld.new(_il_setup()), key, true)
	var data := RF.quiet_data()
	var job := 112 if int(data.skills.skills[key].job) in [100, 110, 111, 112] else 212
	if key in BOWMASTER_KEYS:
		job = 312
	data.jobs_survivor.jobs["112"]["playable"] = true
	data.jobs_survivor.jobs["312"]["playable"] = true
	var setup := RF.with_basic_attack(RF.setup("quiet", 296, data))
	setup.equipment_info.merge({BOW: {"incPAD": 28, "attackSpeed": 6, "tuc": 7}}, true)
	for action: String in ["shoot1", "shoot2"]:
		setup.body_img[action] = {"0": {"delay": 100.0}, "1": {"delay": 100.0}}
	var imgs: Dictionary = setup.skill_imgs
	if job == 312:
		var levels := {}
		for lv in range(1, 31):
			levels[str(lv)] = {"hs": "h%d" % lv, "damage": float(51 + lv)}
		# Hurricane's synthetic damage table joins book 312; Dragon's Breath keeps the fixture's table beside it.
		if not imgs.has("312"):
			imgs["312"] = {"skill": {}}
		imgs["312"].skill["3121004"] = {"level": levels}
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
	return _finish_world(w, key, false)


## The flat 4000 px field with the caster in the middle and only `key` learned; an I/L skill is taken to its top rank (low-rank
## hits are so small that a x1.2 rounds away).
func _finish_world(w: RunWorld, key: String, top_rank: bool) -> RunWorld:
	w.bounds = Rect2(0, -500, 4000, 1000)
	w.fhm = FootholdMap.from_segments(FLAT)
	w.swarm.fhm = w.fhm
	if key in BOWMASTER_KEYS:
		# A knock-back (Dragon's Breath) slides the mob along its foothold, and the swarm steps on the context's map.
		w._ctx["fhm"] = w.fhm
	RF.place_player(w, CASTER_X)
	if key in BOWMASTER_KEYS:
		w.wear_new_item(BOW)
	w.loadout.ranks.clear()
	w.loadout.order.clear()
	w.learn_skill(key)
	if top_rank:
		w.loadout.set_rank(key, w.book.max_rank(key))
	w.god = true
	for mk: MobKind in w.mob_kinds:
		# A volley is spread a few px vertically (Strafe), so the bow probes use a snail-tall body.
		mk.hitbox = Rect2(-5, -50, 10, 50) if key in BOWMASTER_KEYS else Rect2(-5, -10, 10, 10)
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
func _layout(stat: String, reach: float, blast := false, edge_only := false) -> Dictionary:
	var xs := []
	var edge := []
	if blast and stat == "area":
		# The arrow lands on the nearest monster (x 100); the blast box is +-130 around it (+-156 widened): 140 px away
		# is inside only the widened box.
		return {"xs": [100.0, 240.0], "edge": [240.0]}
	if blast and stat == "blast_targets":
		# Ten monsters 12 px apart, all inside the blast box around the first (nearest) one: the cap decides how many.
		for k in 10:
			xs.append(20.0 + 12.0 * k)
		return {"xs": xs, "edge": edge}
	if edge_only and stat == "range":
		# A two-arrow skill shoots the nearest monsters, so the only monsters are the ones beyond the base reach.
		return {"xs": [reach * 1.1, -reach * 1.1], "edge": [reach * 1.1, -reach * 1.1]}
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
	# Poison pulses (hp lost) and knock-back (x moved) count as "affected" for the poison skills; an I/L skill only counts the
	# mobs its own hit events name (its audit before the fold, and a chain's neighbours are shoved by soft collision).
	var il: bool = int(_resolved()[key].job) in IL_BOOKS
	var reach := _reach(w, key)
	var layout := _layout(stat, reach, w.book.def(key).has("impact_blast"), key in BOWMASTER_KEYS)
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
	# A bow's `range` probe stops before the spawn director relocates a monster that sits off screen (about 3.3 s): a shot at
	# 550 px lands within a second.
	var window := 66.0 if stat == "cooldown" else 12.0 if stat == "damage" \
		else 1.5 if stat == "range" and key in BOWMASTER_KEYS else 3.5
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
				if not il:
					affected[s] = true # a poison pulse
				w.swarm.hp[s] = w.swarm.max_hp[s]
	for s: int in slots:
		if not il and absf(w.swarm.x[s] - float(x0[s])) > 1.0:
			affected[s] = true
	var edge_hit := false
	for s: int in edge_slots:
		edge_hit = edge_hit or affected.has(s)
	var direct_damage: bool = String(w.loadout.stats(key).damage_type) != "none"
	return {"casts": w.runner.casts, "dealt": w.damage_dealt - w.swarm.poison_dealt if direct_damage else w.swarm.poison_dealt, "lines": lines, "affected": affected.size(), "edge": edge_hit,
		"summons": w.runner.summons.active.count(1), "orbs_left": orbs_left, "burn": w.swarm.burn_dealt}


func test_every_pool_skill_with_bonuses_was_found() -> void:
	var keys := _skills_with_bonuses()
	for key in ["power_strike", "slash_blast", "brandish", "shout", "monster_magnet", "panic", "coma", "energy_bolt", "explosion",
			"elquines"]:
		assert_true(key in keys, key)
	for key in BOWMASTER_KEYS:
		assert_true(key in keys, key)
	assert_true(keys.size() >= 27 + IL_SKILLS.size(), "seven Hero, twelve F/P, eight Bowmaster and %d I/L skills: %d" % [IL_SKILLS.size(), keys.size()])
	for key in IL_SKILLS:
		assert_true(key in keys, "%s (I/L) is audited" % key)


func test_every_il_skill_with_bonuses_is_audited_here_or_named_as_audited_elsewhere() -> void:
	# The job < 300 filter takes books 220/221/222 in; nothing of the I/L line may drop out of it unnoticed.
	var il_line: Dictionary = IL.skill_file("il_arch_mage")
	var resolved := _resolved()
	for key: String in il_line:
		if not resolved[key].has("rarity_bonuses"):
			continue
		assert_true(int(resolved[key].job) in IL_BOOKS, "%s is a book 220/221/222 skill" % key)
		assert_true(key in IL_SKILLS or key in IL_AUDITED_ELSEWHERE, "%s: audited here or named in IL_AUDITED_ELSEWHERE" % key)
	for key: String in IL_SKILLS:
		assert_true(il_line.has(key), "%s is in the I/L line file" % key)
		assert_true(resolved[key].has("rarity_bonuses"), key)


func test_the_audits_cover_the_whole_shipped_il_pool() -> void:
	# I12 #331: Energy Bolt and Magic Claw are the F/P audit's (shared skills, found by _skills_with_bonuses); Ifrit is audited by test_ifrit.
	var pool: Array = DataRepo.load_all().jobs_survivor.jobs["222"].skill_pool.duplicate()
	var keys := _skills_with_bonuses()
	var covered: Array = IL_SKILLS.duplicate()
	for key: String in ["energy_bolt", "magic_claw"]:
		assert_true(key in keys, "%s (shared with F/P) is audited" % key)
		covered.append(key)
	covered.append_array(IL_AUDITED_ELSEWHERE)
	pool.sort()
	covered.sort()
	assert_eq(covered, pool, "a new I/L pool skill needs a resolved-cast audit")


func test_each_bonus_effect_changes_the_resolved_cast() -> void:
	var skills := _resolved()
	var il_checked := 0
	for key: String in _skills_with_bonuses():
		var bonuses: Dictionary = skills[key].rarity_bonuses
		for tier: String in TIERS:
			for bonus: Dictionary in bonuses[tier]:
				for effect: Dictionary in bonus.effects:
					_assert_effect_changes_the_cast(key, tier, String(bonus.id), effect)
					il_checked += 1 if key in IL_SKILLS else 0
	assert_eq(il_checked, IL_SKILLS.size() * 5, "each I/L skill: 1 + 1 + 1 + 2 effects")


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
		"count", "pierce", "blast_targets":
			# An arrow stops at the first monster on its line and a focus volley (Strafe) sends every arrow at one monster, so
			# a bow skill's extra arrows are extra hit lines.
			if key in BOWMASTER_KEYS and stat == "count":
				assert_true(int(with.lines) > int(base.lines), "%s: hit lines %d -> %d" % [label, base.lines, with.lines])
			else:
				assert_true(int(with.affected) > int(base.affected), "%s: mobs affected %d -> %d" % [label, base.affected, with.affected])
		"burn_damage":
			assert_true(int(base.burn) > 0, "%s: the unmodified cast burns" % label)
			assert_true(int(with.burn) > int(base.burn), "%s: burn dealt %d -> %d" % [label, base.burn, with.burn])
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


func test_the_probe_tells_the_bow_skills_stats_apart() -> void:
	# Arrow Blow has no blast to widen, and Strafe's extra arrows stay on one monster (more hit lines, no more monsters).
	var targets := {"stat": "blast_targets", "op": "add", "value": 2.0}
	assert_eq(_probe("arrow_blow", [targets], "blast_targets").affected, _probe("arrow_blow", [], "blast_targets").affected)
	var arrows := {"stat": "count", "op": "add", "value": 2.0}
	var base := _probe("strafe", [], "count")
	var more := _probe("strafe", [arrows], "count")
	assert_eq(more.affected, base.affected, "a focus volley never reaches a second monster")
	assert_true(int(more.lines) > int(base.lines))
	# Arrow Bomb's blast box is what `area` widens: its arrow's own reach does not change.
	var area := {"stat": "area", "op": "mul", "value": 1.2}
	assert_false(bool(_probe("arrow_bomb", [], "area").edge))
	assert_true(bool(_probe("arrow_bomb", [area], "area").edge))


func test_the_probe_tells_arrow_rain_and_dragons_breath_stats_apart() -> void:
	# Arrow Rain strikes a box, so `range` and `pierce` change nothing for it; Dragon's Breath has no box for `area` to widen.
	var range_mod := {"stat": "range", "op": "mul", "value": 1.25}
	assert_false(bool(_probe("arrow_rain", [range_mod], "range").edge))
	var area := {"stat": "area", "op": "mul", "value": 1.2}
	assert_false(bool(_world("dragons_breath").loadout.stats("dragons_breath").has_box), "no box for `area` to widen")
	var pierce := {"stat": "pierce", "op": "add", "value": 2}
	assert_eq(_probe("arrow_rain", [pierce], "pierce").affected, _probe("arrow_rain", [], "pierce").affected)
	assert_true(bool(_probe("arrow_rain", [area], "area").edge))
	assert_true(bool(_probe("dragons_breath", [range_mod], "range").edge))
	assert_true(int(_probe("dragons_breath", [pierce], "pierce").affected) > int(_probe("dragons_breath", [], "pierce").affected))


func test_the_probe_tells_burn_damage_apart() -> void:
	# Only Inferno burns: the same modifier on Arrow Bomb (which stuns) changes nothing, and on Inferno it changes the fire.
	var hellfire := {"stat": "burn_damage", "op": "mul", "value": 1.5}
	assert_eq(_probe("arrow_bomb", [hellfire], "burn_damage").burn, 0)
	assert_true(int(_probe("inferno", [hellfire], "burn_damage").burn) > int(_probe("inferno", [], "burn_damage").burn))


# --- Bowmaster physical followers (spec #332, B11 #343) -------------------------------------------------------------------
# Silver Hawk and Phoenix are job 311/312 skills, so the generic audit above (job < 300) does not see them. Each effect of
# each tier is cast with and without it in a world with the shipped definitions on generic books: damage (damage dealt),
# area (a monster just beyond the base attack box is only struck with the widened one), count (monsters struck in one
# strike) and summon_count (allies).

const FOLLOWER_KEYS := ["silver_hawk", "phoenix"]


func _follower_probe(key: String, effects: Array, stat: String) -> Dictionary:
	var w: RunWorld = FOLLOWERS.new()._world(key)
	for e: Dictionary in effects:
		w.loadout.add_skill_mod(key, String(e.stat), String(e.op), float(e.value))
	w.runner.step(DT, w)
	w.loadout.order.clear()
	for t in 120: # past the summoned animation: the follower stands at its trailing point
		w.runner.tick_cooldowns(DT, w)
	var fx: float = w.runner.summons.x[0]
	var reach := 200.0 if key == "silver_hawk" else 100.0
	var mobs := []
	var edge := []
	match stat:
		"area":
			edge.append(RF.put_mob(w, MOB, fx + reach * 1.1, 195, 100000.0))
			mobs.append(edge[0])
		"count":
			for k in 8:
				mobs.append(RF.put_mob(w, MOB, fx - reach * (0.2 + 0.1 * k), 195, 100000.0))
		_:
			mobs.append(RF.put_mob(w, MOB, fx + reach * 0.5, 195, 100000.0))
	for m: int in mobs:
		w.swarm.hp[m] = 1000000
		w.swarm.max_hp[m] = 1000000
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	var window := 12.0 if stat == "damage" else 4.0 # damage sums several strikes; the others read one strike
	var struck := 0
	for t in int(window / DT):
		w.runner.tick_cooldowns(DT, w)
		w.drain_events()
		if stat == "count" and w.runner.summons.impact[0] < 0.0 and struck == 0:
			for m: int in mobs:
				if w.swarm.hp[m] < w.swarm.max_hp[m]:
					struck += 1
			if struck > 0:
				break
	var hit_edge := false
	for m: int in edge:
		hit_edge = hit_edge or w.swarm.hp[m] < w.swarm.max_hp[m]
	var dealt := 0
	for m: int in mobs:
		dealt += w.swarm.max_hp[m] - w.swarm.hp[m]
	return {"dealt": dealt, "struck": struck, "edge": hit_edge, "summons": w.runner.summons.living_count()}


func test_follower_bonuses_were_found_with_all_four_tiers() -> void:
	var skills: Dictionary = DataRepo.load_all().skills.skills
	for key: String in FOLLOWER_KEYS:
		assert_true(skills[key].has("rarity_bonuses"), key)
		for tier: String in TIERS:
			assert_true(not (skills[key].rarity_bonuses[tier] as Array).is_empty(), "%s %s" % [key, tier])


func test_each_follower_bonus_effect_changes_the_resolved_cast() -> void:
	var skills: Dictionary = DataRepo.load_all().skills.skills
	for key: String in FOLLOWER_KEYS:
		for tier: String in TIERS:
			for bonus: Dictionary in skills[key].rarity_bonuses[tier]:
				for effect: Dictionary in bonus.effects:
					var stat := String(effect.stat)
					var label := "%s %s %s (%s)" % [key, tier, String(bonus.id), stat]
					assert_true(stat in ["damage", "area", "count", "summon_count"], "%s: a stat this audit knows" % label)
					var base := _follower_probe(key, [], stat)
					var with := _follower_probe(key, [effect], stat)
					match stat:
						"damage":
							assert_true(int(base.dealt) > 0 and int(with.dealt) > int(base.dealt),
								"%s: damage dealt %d -> %d" % [label, base.dealt, with.dealt])
						"area":
							assert_false(bool(base.edge), "%s: the monster beyond the base box is outside it" % label)
							assert_true(bool(with.edge), "%s: ... and inside the widened one" % label)
						"count":
							assert_true(int(with.struck) == int(base.struck) + 1,
								"%s: monsters struck in one strike %d -> %d" % [label, base.struck, with.struck])
						"summon_count":
							assert_eq(int(base.summons), 1, label)
							assert_eq(int(with.summons), 2, label)


func test_the_follower_probe_catches_a_modifier_the_cast_never_reads() -> void:
	# The hawk strikes one monster: a `count` modifier on it would be read, but `pierce` is not a summon stat.
	var pierce := {"stat": "pierce", "op": "add", "value": 2.0}
	assert_eq(_follower_probe("phoenix", [pierce], "count").struck, _follower_probe("phoenix", [], "count").struck)
	assert_eq(_follower_probe("phoenix", [], "count").struck, 4, "the base Phoenix strikes four monsters")


func test_the_probe_catches_an_il_modifier_the_cast_rule_never_reads() -> void:
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
