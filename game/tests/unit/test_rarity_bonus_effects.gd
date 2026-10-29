extends TestCase
## Every rarity bonus of every Hero, F/P, I/L Arch Mage, Bishop and Buccaneer skill changes the resolved cast, not just a stat number (spec
## #296, H7 audit; the I/L skills joined it in spec #319, I6 #325 / the merge of redesign; the Bishop's core bolts in spec #372, BS5 #377;
## the five Buccaneer Brawler skills in spec #412, B4 #416).
## For each effect of each tier the same seeded world is cast twice, with and without the effect, against a field of mobs
## laid out to expose that one stat: damage (damage dealt over 12 s), cooldown (casts in 66 s), crit (critical hit events in 66 s), attack_count (hit events), count and
## pierce (mobs affected), summon_count (allies), meter_keep (orbs left after a finisher), and area / range (a mob just beyond the base reach is only affected with
## the effect). The HP-risk stats (spec #348, D3 seam) are read off HP: self_damage (recoil paid per damage dealt over 12 s),
## low_hp_damage (damage dealt over 12 s from 40% HP) and hp_cost (HP paid per cast). Dragon Fury and Sacrifice are probed in a
## job 132 world with a huge HP pool (the 10% recoil cap and the "never the last HP" rule stay out of the way) and a heavy weapon
## (floors cannot hide a x0.6). For a support summon (the Beholder) support_heal (HP restored over 30 s) and support_rate (pulses in 30 s)
## are read. A bonus whose stat the skill's cast rule never reads fails here as a no-op.
## Hero and Paladin books (111/112, 121/122) and the Dark Knight books (131/132) are synthetic generic tables; the F/P books come from the shared run fixtures. The I/L skills (books
## 220/221/222) have their own synthetic Skill.wz tables (`il_fixtures.books()`, Ice Demon and Element Composition use the
## small tables `_demon_levels` builds) and are cast at their top rank, so the probes below are the same and only `_world` differs.
## Ifrit (I9) is a summon that needs allies settled behind the player: it stays in test_ifrit.gd (IL_AUDITED_ELSEWHERE).
## Paladin's skills (Blast, Monster Magnet) run as job 122 (P5 #313). The Buccaneer's five (books 500/510, synthetic fixture tables, a
## knuckler in hand) run as job 512 at their top rank.
## A Form (Paladin's Charges, spec #308) has its own probe: its bonuses change the Charge's multiplier (`form_power`: the hits of a
## Paladin skill inside the window), duration (`form_time`: ticks the window lasts), cooldown (windows started in 66 s) and its
## sub-skill's damage (`damage`: Charged Blow's hits inside the window).

const BF := preload("res://tests/fixtures/bishop_bolt_fixtures.gd")
const IL := preload("res://tests/fixtures/il_fixtures.gd")
const RS := preload("res://tests/fixtures/resurrection_fixtures.gd")
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const BLIZZARD := preload("res://tests/unit/test_il_blizzard.gd")
const BIG_BANG := preload("res://tests/unit/test_il_big_bang.gd")
const TRANSFORMATION := preload("res://tests/unit/test_buccaneer_transformation.gd")
const DT := 1.0 / 60.0
const MOB := 1110100
const CASTER_X := 2000.0
const FLAT := [{"x1": 0, "y1": 200, "x2": 4000, "y2": 200}]
const TIERS := ["rare", "epic", "unique", "legendary"]
const CORE_STATS := ["damage", "cooldown", "attack_count", "count", "pierce", "summon_count", "area", "range", "meter_keep", "crit",
	"self_damage", "low_hp_damage", "hp_cost", "support_heal", "support_rate", "form_power", "form_time"]
## The Buccaneer skills this audit casts (B4 #416 the five Brawler skills, B7 #419 Energy Orb, B8 #420 Barrage and Dragon Strike, B9 #421 Transformation, B10 #422 Super Transformation; B6 appends its own).
const BUCCANEER_SKILLS := ["flash_fist", "somersault_kick", "backspin_blow", "double_uppercut", "corkscrew_blow",
		"barrage", "dragon_strike", "energy_orb", "transformation", "super_transformation"]
const BARRAGE_DRAGON := preload("res://tests/unit/test_buccaneer_barrage_dragon.gd")
const ORB := preload("res://tests/unit/test_buccaneer_orb.gd")
const SUPER := preload("res://tests/unit/test_buccaneer_super_transformation.gd")
const KNUCKLE := 1482000
## The I/L skills this audit casts (books 220/221/222); I8-I10 appended theirs.
const IL_SKILLS := ["cold_beam", "thunder_bolt", "ice_strike", "thunder_spear", "ice_demon", "element_composition_il",
	"chain_lightning", "blizzard", "big_bang_il"]
## The I/L skills with bonuses that another test audits: Ifrit is a summon (test_ifrit.gd).
const IL_AUDITED_ELSEWHERE := ["ifrit"]
## The Bishop skills whose bonuses another test audits (book 230+; Heal's `heal_power` / `heal_threshold` are test_bishop_heal's).  The dragons (BS7) are summons: test_bishop_dragons.
const BISHOP_AUDITED_ELSEWHERE := ["heal", "summon_dragon", "bahamut"]
const IL_BOOKS := [220, 221, 222]
## The Bishop's reaction skills (BS8 #380): audited by the revive probe below, not by a cast (they never auto-cast).
const REVIVE_SKILLS := ["resurrection"]
const REVIVE_STATS := ["cooldown", "revive_hp", "revive_guard"]
## The Bishop skills this audit casts (books 230/231/232, BS5 #377): Holy Arrow, Shining Ray, Angel Ray. They have their own synthetic
## Skill.wz tables (`bishop_bolt_fixtures.gd`) and are cast at their top rank, like the I/L ones.
const BISHOP_SKILLS := ["holy_arrow", "shining_ray", "angel_ray"]
## The Bishop's Genesis and its Big Bang template child (BS6 #378): book 232 tables from test_bishop_genesis.gd (the Genesis box and
## 15 mobs; Big Bang's no-box table), cast at their top rank like the other Bishop and I/L skills.
const BISHOP_NOVAS := ["genesis", "big_bang_bishop"]
const BISHOP_GENESIS := preload("res://tests/fixtures/bishop_genesis_fixtures.gd")

## The stats probed over a 12 s window of repeated casts (the others stop after the first cast).
const HP_STATS := ["self_damage", "low_hp_damage", "hp_cost"]
## Skills with their own synthetic levels (Skill.wz fields they read, no table box), the HP pool and the weapon of their world.
const HP_RISK_SKILLS := ["dragon_fury", "sacrifice"]
const DK_HP := 1000000
const DK_WEAPON := 1302000

var _resolved_skills := {}


## Generic Skill.wz levels: a centred box, six mobs, one line, a 300 px range, a certain proc (the shape test_fp_high_actives uses).
## `extra` is merged into every level (Dragon Roar's `x` = 40 % of max HP and `y` stun seconds).
func _generic_levels(extra: Dictionary = {}) -> Dictionary:
	var levels := {}
	for lv in range(1, 31):
		levels[str(lv)] = {"damage": 100 + lv, "mad": 30.0, "mobCount": 6, "attackCount": 1, "range": 300, "prop": 100,
			"time": 4, "lt": {"$v": [-200, -150]}, "rb": {"$v": [200, 150]}}
		levels[str(lv)].merge(extra, true)
	return levels


## Levels of an HP-risk skill: no box (Dragon Fury's reach is its literal cast box, not a table), the HP fields it reads
## (Sacrifice `x`, Fury `hpCon`) and one line per cast.
func _hp_risk_levels(key: String) -> Dictionary:
	var levels := {}
	for lv in range(1, 31):
		levels[str(lv)] = {"damage": 200, "mobCount": 6 if key == "dragon_fury" else 1, "attackCount": 1}
		if key == "sacrifice":
			levels[str(lv)]["x"] = 18
		elif key == "dragon_fury":
			levels[str(lv)]["hpCon"] = 20
	return levels


## A support summon's sub-skill (Aura, Hex) levels: 50 HP every 10 s, a 20 s defence buff every 10 s (the Beholder's own tables
## are covered by test_beholder; here only the cast differs with and without the bonus).
func _sub_levels() -> Dictionary:
	var levels := {}
	for lv in range(1, 31):
		levels[str(lv)] = {"hp": 50.0, "x": 10.0, "time": 20.0, "pdd": 10.0}
	return levels


func _anim(frames: int) -> Dictionary:
	var out := {}
	for i in frames:
		out[str(i)] = {"delay": 100.0}
	return out


## The skills with rarity bonuses of the Magician, Warrior and I/L lines (job < 300), templates resolved: a skill that `extends`
## another inherits its lists, and the raw data would silently leave it out.
func _skills_with_bonuses() -> Array:
	var skills: Dictionary = _resolved()
	var keys := []
	for key: String in skills:
		if (skills[key] as Dictionary).has("rarity_bonuses") and (int(skills[key].job) < 300 or key in BUCCANEER_SKILLS) \
				and key not in IL_AUDITED_ELSEWHERE and key not in BISHOP_AUDITED_ELSEWHERE:
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


## A Buccaneer (512, made playable in the data copy) holding a knuckler on the flat field, the five Brawler skills read from the
## synthetic books 500/510 of the run fixtures, Barrage and Dragon Strike from book 512 of test_buccaneer_barrage_dragon.
func _buccaneer_world(key: String) -> RunWorld:
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["512"]["playable"] = true
	var setup := RF.with_basic_attack(RF.setup("quiet", 416, data))
	setup.skill_imgs["511"] = TRANSFORMATION.book_node()
	setup.equipment_info[KNUCKLE] = {"incPAD": 18, "attackSpeed": 5, "tuc": 7, "afterImage": "mace", "sfx": "mace"}
	# One book-512 dictionary with every key: B8 #420 Barrage and Dragon Strike, B7 #419 Energy Orb, B10 #422 Super Transformation, Demolition and Snatch.
	var book512 := BARRAGE_DRAGON.book_node()
	book512.skill.merge(ORB.book_node().skill)
	book512.skill.merge(SUPER.book_node().skill)
	setup.skill_imgs["512"] = book512
	var w := RunWorld.new(setup)
	w.set_job(512)
	if w.weapon_id() != KNUCKLE:
		w.wear_new_item(KNUCKLE)
	return _finish_world(w, key, true)


func _world(key: String) -> RunWorld:
	if key in BUCCANEER_SKILLS:
		return _buccaneer_world(key)
	var il: bool = int(_resolved()[key].job) in IL_BOOKS
	if il:
		return _finish_world(RunWorld.new(_il_setup()), key, true)
	if key in BISHOP_SKILLS:
		return _finish_world(RunWorld.new(BF.setup(RF.quiet_data(), 377)), key, true)
	if key in BISHOP_NOVAS:
		return _finish_world(RunWorld.new(BISHOP_GENESIS.add_books(BF.setup(RF.quiet_data(), 378))), key, true)
	var data := RF.quiet_data()
	var skill_job := int(data.skills.skills[key].job)
	var job := 122 if skill_job in [120, 121, 122] else 112 if skill_job in [100, 110, 111, 112] else 132 if skill_job in [130, 131, 132] else 212
	data.jobs_survivor.jobs["112"]["playable"] = true
	data.jobs_survivor.jobs["132"]["playable"] = true
	if key in HP_RISK_SKILLS:
		data.balance.player.hp = DK_HP
	data.jobs_survivor.jobs["122"]["playable"] = true
	var setup := RF.with_basic_attack(RF.setup("quiet", 296, data))
	var imgs: Dictionary = setup.skill_imgs
	# Hero books are synthetic; the F/P box and crowd skills get the same generic table (their fixtures carry no box).
	for k: String in data.skills.skills:
		var d: Dictionary = data.skills.skills[k]
		var id := int(d.skill_id)
		if k in HP_RISK_SKILLS:
			var risk_book := String(d.book)
			if not imgs.has(risk_book):
				imgs[risk_book] = {"skill": {}}
			imgs[risk_book].skill[str(id)] = {"level": _hp_risk_levels(k)}
		elif int(d.job) in [111, 112, 121, 122, 131, 132] or id in [2111002, 2111003, 2111006, 2121001, 2121003, 2121006, 2121007]:
			var book := String(d.book)
			if not imgs.has(book):
				imgs[book] = {"skill": {}}
			var node: Dictionary = imgs[book].skill.get("%07d" % id, imgs[book].skill.get(str(id), {}))
			node["level"] = _sub_levels() if String(d.get("slot", "")) == "summon_sub" else _generic_levels({"x": 40, "y": 4} if id == 1311006 else {})
			if d.get("summon", {}).has("support"):
				node["summon"] = {"summoned": _anim(3), "stand": _anim(4), "move": _anim(2), "die": _anim(2),
					"skill1": _anim(3), "skill2": _anim(3), "skill3": _anim(3), "skill4": _anim(3), "skill5": _anim(3), "skill6": _anim(3)}
			imgs[book].skill[str(id) if id >= 1000000 else "%07d" % id] = node
	var w := RunWorld.new(setup)
	w.set_job(job)
	return _finish_world(w, key, false)


## The flat 4000 px field with the caster in the middle and only `key` learned; an I/L skill is taken to its top rank (low-rank
## hits are so small that a x1.2 rounds away).
func _finish_world(w: RunWorld, key: String, top_rank: bool) -> RunWorld:
	w.bounds = Rect2(0, -500, 4000, 1000)
	w.fhm = FootholdMap.from_segments(FLAT)
	w.swarm.fhm = w.fhm
	RF.place_player(w, CASTER_X)
	w.loadout.ranks.clear()
	w.loadout.order.clear()
	if key in HP_RISK_SKILLS:
		w.equipment.worn.weapon = Equipment.create(DK_WEAPON, {"incPAD": 1500})
		w.refresh_player_stats()
	w.learn_skill(key)
	if top_rank:
		w.loadout.set_rank(key, w.book.max_rank(key))
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
	if String(st.kind) == "form":
		return 300.0 # a form has no reach of its own: the mobs stand inside its Shockwave strip (330 px) and its 400 px admission radius
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
	# Poison pulses (hp lost) and knock-back (x moved) count as "affected" for the poison skills; an I/L skill only counts the
	# mobs its own hit events name (its audit before the fold, and a chain's neighbours are shoved by soft collision).
	var il: bool = int(_resolved()[key].job) in IL_BOOKS or key in BISHOP_SKILLS or key in BISHOP_NOVAS
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
	var repeating := stat in ["cooldown", "damage", "crit"] or stat in HP_STATS
	var support := stat in ["support_heal", "support_rate"]
	var window := 66.0 if stat in ["cooldown", "crit"] else 12.0 if stat == "damage" or stat in HP_STATS else 30.0 if support else (22.0 if key == "super_transformation" else 14.0) if stat == "form_time" else 3.5
	if stat == "low_hp_damage":
		w._hp = 0.4 * float(w.player_state.max_hp) # at or below half HP (HpRisk.BERSERK_BELOW)
		w._write_player_state(0.0)
	if stat == "support_heal":
		w.loadout.add_player_mod("max_hp", "add", 1000.0) # room for the flat heal (a Lv1 knight has 50 HP)
		w.refresh_player_stats()
		w.spend_hp(int(w.player_state.hp) - 50) # a hurt knight: a 50 HP Aura pulse restores in full
	var recoil := 0
	var cost := 0
	var restored := 0
	var pulses := 0
	var affected := {}
	var lines := 0
	var crits := 0
	# A Combo finisher (Panic, Coma) needs orbs: ten every tick when counting casts or damage, its own minimum once otherwise
	# (5 for Hero, 10 for the Energy Orb), so that `meter_keep` shows in what a single cast leaves behind.
	var finisher: bool = w.book.def(key).has("meter")
	var needed := int(w.book.def(key).get("meter", {}).get("min", 5))
	var orbs_left := -1
	var form_from := -1
	var form_ticks := 0
	for tick in int(window / DT):
		if finisher and (repeating or w.runner.casts == 0):
			w.meter.value = 10 if repeating else needed
		w.step(DT, MoveInput.new())
		if finisher and orbs_left < 0 and w.runner.casts >= 1:
			orbs_left = w.meter.value
		if not repeating and w.runner.casts >= 1:
			w.runner.cooldowns[key] = 1.0e9
		for e: Dictionary in w.drain_events():
			if e.type == "form_started":
				form_from = tick
			elif e.type == "form_ended" and form_from >= 0 and form_ticks == 0:
				form_ticks = tick - form_from
			if e.type == "mob_hit":
				lines += 1
				crits += 1 if bool(e.crit) else 0
				affected[int(e.mob)] = true
			elif e.type == "hp_spent":
				if e.kind == "recoil":
					recoil += int(e.amount)
				else:
					cost += int(e.amount)
			elif e.type == "player_restored":
				restored += int(e.amount)
			elif e.type == "support_pulse":
				pulses += 1
		if repeating and not (w.loadout.stats(key).displacement as Dictionary).is_empty():
			w.player.place(Vector2(CASTER_X, w.player.pos.y), w.fhm) # a charge or a back-off must not walk the caster away between casts
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
	# A form deals no damage itself; its Shockwave sub does (the form's `damage` modifier multiplies it).
	var direct_damage: bool = String(w.loadout.stats(key).damage_type) != "none" or String(w.loadout.stats(key).kind) == "form"
	return {"casts": w.runner.casts, "dealt": w.damage_dealt - w.swarm.poison_dealt if direct_damage else w.swarm.poison_dealt, "lines": lines, "crits": crits, "affected": affected.size(), "edge": edge_hit,
		"summons": w.runner.summons.active.count(1), "orbs_left": orbs_left, "form_seconds": float(form_ticks) * DT, "recoil": recoil, "cost": cost, "restored": restored, "pulses": pulses}


func test_every_pool_skill_with_bonuses_was_found() -> void:
	var keys := _skills_with_bonuses()
	for key in ["power_strike", "slash_blast", "brandish", "shout", "monster_magnet", "panic", "coma", "energy_bolt", "explosion",
			"blast", "monster_magnet_paladin", "fire_charge", "ice_charge", "thunder_charge", "elquines", "spear_crusher", "dragon_roar", "monster_magnet_dark_knight", "beholder"]:
		assert_true(key in keys, key)
	for key in BUCCANEER_SKILLS:
		assert_true(key in keys, "%s (Buccaneer) is audited" % key)
	assert_true(keys.size() >= 24 + IL_SKILLS.size(), "seven Hero, five Paladin, twelve F/P and %d I/L skills: %d" % [IL_SKILLS.size(), keys.size()])
	for key in IL_SKILLS:
		assert_true(key in keys, "%s (I/L) is audited" % key)
	for key in HP_RISK_SKILLS:
		assert_true(key in keys, key)
	for key in BISHOP_SKILLS + BISHOP_NOVAS:
		assert_true(key in keys, "%s (Bishop) is audited" % key)


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
	var revive_checked := 0
	var bishop_checked := 0
	var nova_checked := 0
	for key: String in _skills_with_bonuses():
		var bonuses: Dictionary = skills[key].rarity_bonuses
		for tier: String in TIERS:
			for bonus: Dictionary in bonuses[tier]:
				for effect: Dictionary in bonus.effects:
					if key in REVIVE_SKILLS:
						_assert_effect_changes_the_revive(key, tier, String(bonus.id), effect)
						revive_checked += 1
						continue
					_assert_effect_changes_the_cast(key, tier, String(bonus.id), effect)
					il_checked += 1 if key in IL_SKILLS else 0
					bishop_checked += 1 if key in BISHOP_SKILLS else 0
					nova_checked += 1 if key in BISHOP_NOVAS else 0
	assert_eq(il_checked, IL_SKILLS.size() * 5, "each I/L skill: 1 + 1 + 1 + 2 effects")
	assert_eq(revive_checked, REVIVE_SKILLS.size() * 5, "Resurrection: 1 + 1 + 1 + 2 effects")
	assert_eq(bishop_checked, BISHOP_SKILLS.size() * 5, "each Bishop bolt: 1 + 1 + 1 + 2 effects")
	assert_eq(nova_checked, BISHOP_NOVAS.size() * 5, "Genesis and Big Bang Bishop: 1 + 1 + 1 + 2 effects")


func test_holy_charge_is_found_with_its_four_rarity_lists() -> void:
	assert_true("holy_charge" in _skills_with_bonuses())
	var bonuses: Dictionary = DataRepo.load_all().skills.skills.holy_charge.rarity_bonuses
	for tier: String in TIERS:
		assert_eq(bonuses[tier].size(), 1, tier)
	assert_false(DataRepo.load_all().skills.skills.heavens_hammer.has("rarity_bonuses"), "a sub-skill has no list of its own")


## Heaven's Hammer is Holy Charge's second sub-skill: every bonus of Holy that reaches a sub changes it. Runs Holy against four
## still mobs inside the generic Hammer box and measures the Hammers cast and the damage they dealt in `seconds`.
func _probe_hammer(effects: Array, seconds: float) -> Dictionary:
	var w := _world("holy_charge")
	var slots := []
	for off: float in [80.0, -80.0, 140.0, -140.0]:
		slots.append(RF.put_mob(w, MOB, CASTER_X + off, 190.0, 1000000.0))
	var x0 := {}
	for s: int in slots:
		x0[s] = w.swarm.x[s]
	for e: Dictionary in effects:
		w.loadout.add_skill_mod("holy_charge", String(e.stat), String(e.op), float(e.value))
	var hammers := 0
	var dealt := 0.0
	for tick in int(seconds / DT):
		w.restore_player("hp", 100, "test")
		w.step(DT, MoveInput.new())
		for s: int in slots:
			w.swarm.x[s] = x0[s]
		for e: Dictionary in w.drain_events():
			if String(e.type) == "cast" and String(e.skill) == "heavens_hammer":
				hammers += 1
			elif String(e.type) == "mob_hit" and String(e.skill) == "heavens_hammer":
				dealt += float(e.damage)
	return {"hammers": hammers, "dealt": dealt}


func test_each_holy_bonus_that_reaches_a_sub_changes_the_hammer() -> void:
	var bonuses: Dictionary = DataRepo.load_all().skills.skills.holy_charge.rarity_bonuses
	var base_short := _probe_hammer([], 16.0)
	var base_long := _probe_hammer([], 66.0)
	assert_eq(base_short.hammers, 1, "one Hammer in the first window")
	assert_true(float(base_short.dealt) > 0.0, "and it lands")
	for tier: String in TIERS:
		for bonus: Dictionary in bonuses[tier]:
			for effect: Dictionary in bonus.effects:
				var label := "holy_charge %s %s (%s)" % [tier, bonus.id, effect.stat]
				match String(effect.stat):
					"damage", "form_power":
						# Advanced Charge's damage multiplies the sub; Mastery's form_power raises every attack of the window.
						var with := _probe_hammer([effect], 16.0)
						assert_true(float(with.dealt) > float(base_short.dealt), "%s: the Hammer %s -> %s" % [label, base_short.dealt, with.dealt])
					"cooldown":
						var with := _probe_hammer([effect], 66.0)
						assert_true(int(with.hammers) > int(base_long.hammers), "%s: Hammers in 66 s %d -> %d" % [label, base_long.hammers, with.hammers])
					"form_time":
						# The window's length is measured by the Form probe above; the Hammer fires once whatever it lasts.
						assert_eq(_probe_hammer([effect], 16.0).hammers, 1, "%s: still one Hammer per window" % label)
					_:
						assert_true(false, "%s: a stat this audit knows" % label)


func _assert_effect_changes_the_cast(key: String, tier: String, id: String, effect: Dictionary) -> void:
	var stat := String(effect.stat)
	var label := "%s %s %s (%s)" % [key, tier, id, stat]
	assert_true(stat in CORE_STATS, "%s: a stat this audit knows" % label)
	# A Paladin Charge (a Form with an element) has the Form probe; Buccaneer's morphs (no element) run the cast probe.
	if String(_resolved()[key].get("kind", "")) == "form" and (_resolved()[key].form.get("effects", {}) as Dictionary).has("element"):
		_assert_form_effect_changes_the_cast(key, label, stat, effect)
		return
	var base := _probe(key, [], stat)
	var with := _probe(key, [effect], stat)
	match stat:
		"cooldown":
			assert_true(int(with.casts) > int(base.casts), "%s: casts %d -> %d" % [label, base.casts, with.casts])
		"damage":
			assert_true(int(with.dealt) > int(base.dealt), "%s: damage dealt %d -> %d" % [label, base.dealt, with.dealt])
		"crit":
			assert_true(int(with.crits) > int(base.crits), "%s: critical hits %d -> %d" % [label, base.crits, with.crits])
		"attack_count":
			assert_true(int(with.lines) > int(base.lines), "%s: hit lines %d -> %d" % [label, base.lines, with.lines])
		"count", "pierce":
			assert_true(int(with.affected) > int(base.affected), "%s: mobs affected %d -> %d" % [label, base.affected, with.affected])
		"form_time":
			assert_true(float(base.form_seconds) > 0.0 and float(with.form_seconds) > float(base.form_seconds),
				"%s: form seconds %.2f -> %.2f" % [label, base.form_seconds, with.form_seconds])
		"summon_count":
			assert_true(int(with.summons) > int(base.summons), "%s: allies %d -> %d" % [label, base.summons, with.summons])
		"support_heal":
			assert_true(int(base.restored) > 0 and int(with.restored) > int(base.restored),
				"%s: HP restored in 30 s %d -> %d" % [label, base.restored, with.restored])
		"support_rate":
			assert_true(int(base.pulses) > 0 and int(with.pulses) > int(base.pulses),
				"%s: pulses in 30 s %d -> %d" % [label, base.pulses, with.pulses])
		"meter_keep":
			assert_true(int(base.orbs_left) >= 0 and int(with.orbs_left) > int(base.orbs_left),
				"%s: orbs left after the cast %d -> %d" % [label, base.orbs_left, with.orbs_left])
		"self_damage":
			assert_true(int(base.recoil) > 0 and int(base.dealt) > 0, "%s: the base cast pays a recoil (%d of %d)" % [label, base.recoil, base.dealt])
			assert_true(float(with.recoil) / float(with.dealt) < float(base.recoil) / float(base.dealt),
				"%s: recoil per damage dealt %d/%d -> %d/%d" % [label, base.recoil, base.dealt, with.recoil, with.dealt])
		"low_hp_damage":
			assert_true(int(with.dealt) > int(base.dealt), "%s: damage dealt at 40%% HP %d -> %d" % [label, base.dealt, with.dealt])
		"hp_cost":
			assert_true(int(base.cost) > 0 and int(with.cost) * int(base.casts) < int(base.cost) * int(with.casts),
				"%s: HP paid per cast %d/%d -> %d/%d" % [label, base.cost, base.casts, with.cost, with.casts])
		"area", "range":
			assert_false(bool(base.edge), "%s: the mob beyond the base reach is outside it" % label)
			assert_true(bool(with.edge), "%s: the mob beyond the base reach is inside the widened one" % label)


## Runs a Form `key` with Power Strike beside it against four still mobs inside its 400 px admission, with `effects` applied.
## `seconds` bounds the run: the first window's hits, length and the windows started in it are measured.
func _probe_form(key: String, effects: Array, seconds: float) -> Dictionary:
	var w := _world(key)
	w.learn_skill("power_strike")
	w.loadout.add_skill_mod("power_strike", "damage", "mul", 100.0) # big hits: whole-number rounding cannot hide a +10 %
	var slots := []
	for off: float in [80.0, -80.0, 140.0, -140.0]:
		slots.append(RF.put_mob(w, MOB, CASTER_X + off, 190.0, 1000000.0))
	var x0 := {}
	for s: int in slots:
		x0[s] = w.swarm.x[s]
	for e: Dictionary in effects:
		w.loadout.add_skill_mod(key, String(e.stat), String(e.op), float(e.value))
	var starts := 0
	var start_tick := -1
	var length := -1
	var strikes := 0.0
	var blows := 0.0
	for tick in int(seconds / DT):
		w.restore_player("hp", 100, "test") # Charged Blow pays HP and waits when it cannot
		w.step(DT, MoveInput.new())
		var inside := start_tick >= 0 and length < 0
		for s: int in slots:
			w.swarm.x[s] = x0[s] # knockback must not walk the mobs out of Charged Blow's reach
		for e: Dictionary in w.drain_events():
			match String(e.type):
				"form_started":
					starts += 1
					start_tick = tick if start_tick < 0 else start_tick
				"form_ended":
					length = tick - start_tick if length < 0 else length
				"mob_hit":
					if inside and String(e.skill) == "power_strike":
						strikes += float(e.damage)
					elif inside and String(e.skill) == "charged_blow":
						blows += float(e.damage)
	return {"starts": starts, "length": length, "strikes": strikes, "blows": blows}


func _assert_form_effect_changes_the_cast(key: String, label: String, stat: String, effect: Dictionary) -> void:
	var seconds := 66.0 if stat == "cooldown" else 16.0
	var base := _probe_form(key, [], seconds)
	var with := _probe_form(key, [effect], seconds)
	assert_true(int(base.length) > 0 and float(base.strikes) > 0.0 and float(base.blows) > 0.0, "%s: the baseline Charge runs" % label)
	match stat:
		"form_power":
			assert_true(float(with.strikes) > float(base.strikes), "%s: Power Strike inside the window %s -> %s" % [label, base.strikes, with.strikes])
		"form_time":
			assert_true(int(with.length) > int(base.length), "%s: window ticks %d -> %d" % [label, base.length, with.length])
		"cooldown":
			assert_true(int(with.starts) > int(base.starts), "%s: windows in 66 s %d -> %d" % [label, base.starts, with.starts])
		"damage":
			assert_true(float(with.blows) > float(base.blows), "%s: Charged Blow inside the window %s -> %s" % [label, base.blows, with.blows])
			assert_near(float(with.strikes), float(base.strikes), 0.0001, "%s: the Charge's own multiplier is not the damage modifier" % label)
		_:
			assert_true(false, "%s: a Form's bonus reads form_power, form_time, cooldown or damage" % label)


func test_the_probe_catches_a_modifier_the_cast_rule_never_reads() -> void:
	# Shout is a box rule: `range` is not read (its reach is the box). Brandish never reads `pierce`, Power Strike no `summon_count`.
	var reach := {"stat": "range", "op": "mul", "value": 1.2}
	assert_false(bool(_probe("shout", [reach], "range").edge), "a range modifier does not widen a box")
	var pierce := {"stat": "pierce", "op": "add", "value": 1.0}
	assert_eq(_probe("brandish", [pierce], "pierce").affected, _probe("brandish", [], "pierce").affected)
	var allies := {"stat": "summon_count", "op": "add", "value": 1.0}
	assert_eq(_probe("power_strike", [allies], "summon_count").summons, 0)
	# HP stats: Dragon Fury has no recoil to shrink and Sacrifice no HP cost to cut (the audit reports no change).
	var achilles := {"stat": "self_damage", "op": "mul", "value": 0.6}
	assert_eq(_probe("dragon_fury", [achilles], "self_damage").recoil, 0, "Fury pays no recoil, with or without Achilles")
	var blood := {"stat": "hp_cost", "op": "mul", "value": 0.75}
	assert_eq(_probe("sacrifice", [blood], "hp_cost").cost, 0, "Sacrifice pays no cost up front")
	# And the modifiers the shipped bonuses rely on do widen: area on a box, area on a radial range, range on a pull.
	# A support modifier on a skill with no support pulses changes nothing.
	assert_eq(_probe("spear_crusher", [{"stat": "support_rate", "op": "mul", "value": 0.5}], "support_rate").pulses, 0)
	assert_eq(_probe("spear_crusher", [{"stat": "support_heal", "op": "mul", "value": 2.0}], "support_heal").restored, 0)
	var area := {"stat": "area", "op": "mul", "value": 1.2}
	assert_true(bool(_probe("shout", [area], "area").edge))
	assert_true(bool(_probe("slash_blast", [area], "area").edge))
	assert_true(bool(_probe("monster_magnet", [reach], "range").edge))


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


func test_the_form_probe_catches_a_modifier_a_charge_never_reads() -> void:
	# A Charge reads form_power, form_time, cooldown and (through its subs) damage and area: not pierce, not summon_count.
	var base := _probe_form("fire_charge", [], 16.0)
	for stat in ["pierce", "summon_count"]:
		assert_eq(_probe_form("fire_charge", [{"stat": stat, "op": "add", "value": 2.0}], 16.0), base, stat)
	# And each stat the shipped bonuses use does move its own measure.
	assert_true(int(_probe_form("fire_charge", [{"stat": "form_time", "op": "mul", "value": 1.25}], 16.0).length) > int(base.length))
	assert_true(float(_probe_form("fire_charge", [{"stat": "form_power", "op": "add", "value": 0.1}], 16.0).strikes) > float(base.strikes))

func test_the_probe_catches_a_genesis_modifier_the_cast_rule_never_reads() -> void:
	# Genesis' pending box and Big Bang's charge box never read `range` or `pierce`; they do read `area`.
	var reach := {"stat": "range", "op": "mul", "value": 1.5}
	assert_false(bool(_probe("genesis", [reach], "range").edge), "a range modifier does not widen Genesis' box")
	assert_false(bool(_probe("big_bang_bishop", [reach], "range").edge))
	var pierce := {"stat": "pierce", "op": "add", "value": 1.0}
	assert_eq(_probe("genesis", [pierce], "pierce").affected, _probe("genesis", [], "pierce").affected)
	var area := {"stat": "area", "op": "mul", "value": 1.2}
	assert_true(bool(_probe("genesis", [area], "area").edge))
	assert_true(bool(_probe("big_bang_bishop", [area], "area").edge))


func test_the_probe_catches_a_bishop_modifier_the_cast_rule_never_reads() -> void:
	# A box rule never reads `range`; a nearest projectile reads neither `area` nor a shining box's pierce.
	var reach := {"stat": "range", "op": "mul", "value": 1.2}
	assert_false(bool(_probe("shining_ray", [reach], "range").edge), "a range modifier does not widen Shining Ray's box")
	var area := {"stat": "area", "op": "mul", "value": 1.2}
	assert_false(bool(_probe("angel_ray", [area], "area").edge), "an area modifier does not lengthen an Angel Ray shot")
	assert_false(bool(_probe("holy_arrow", [area], "area").edge))
	var pierce := {"stat": "pierce", "op": "add", "value": 1.0}
	assert_eq(_probe("shining_ray", [pierce], "pierce").affected, _probe("shining_ray", [], "pierce").affected)
	# And the modifiers the shipped bonuses rely on do widen.
	assert_true(bool(_probe("shining_ray", [area], "area").edge))
	assert_true(int(_probe("holy_arrow", [pierce], "pierce").affected) > int(_probe("holy_arrow", [], "pierce").affected))


# --- the revive probe (Bishop BS8 #380): a reaction skill never casts, so its bonuses are audited on the revive itself ---

## A Bishop world with `key` learned at rank 2, `effects` applied, hit by a lethal touch hit; returns what the revive did:
## the event's HP, guard and recharge, and whether a second lethal hit 3 s later (past the base 2 s guard) gets through.
func _revive_probe(key: String, effects: Array) -> Dictionary:
	var w := RS.world()
	w.loadout.set_rank(key, 2)
	for e: Dictionary in effects:
		w.loadout.add_skill_mod(key, String(e.stat), String(e.op), float(e.value))
	RS.lethal_hit(w)
	var revived := {}
	for e: Dictionary in w.drain_events():
		if e.type == "player_revived":
			revived = e
	# Walk 3.0 s: past the base 2.0 s guard, inside the Holy Shield's 3.5 s. A hit then lands only if the guard is over.
	for i in 180:
		w.step(DT, MoveInput.new())
	var landed := RS.lethal_hit(w) != 0 or w.revives.size() > 1 or bool(w.player_state.dead)
	return {"event": revived, "recharge": float(revived.get("recharge", -1.0)),
		"revive_hp": int(revived.get("hp", -1)), "guard": float(revived.get("guard", -1.0)), "landed_after_3s": landed}


func _assert_effect_changes_the_revive(key: String, tier: String, id: String, effect: Dictionary) -> void:
	var stat := String(effect.stat)
	var label := "%s %s %s (%s)" % [key, tier, id, stat]
	assert_true(stat in REVIVE_STATS, "%s: a stat the revive probe knows" % label)
	var base := _revive_probe(key, [])
	var with := _revive_probe(key, [effect])
	assert_false(base.event.is_empty() or with.event.is_empty(), "%s: the lethal hit revived" % label)
	match stat:
		"cooldown":
			assert_true(float(with.recharge) < float(base.recharge) - 1.0, "%s: recharge %s -> %s" % [label, base.recharge, with.recharge])
		"revive_hp":
			assert_true(int(with.revive_hp) > int(base.revive_hp), "%s: HP back %d -> %d" % [label, base.revive_hp, with.revive_hp])
		"revive_guard":
			assert_true(float(with.guard) > float(base.guard), "%s: guard %s -> %s" % [label, base.guard, with.guard])
			assert_true(bool(base.landed_after_3s), "%s: the base guard is over after 3 s" % label)
			assert_false(bool(with.landed_after_3s), "%s: the longer guard still blocks at 3 s" % label)


func test_the_revive_probe_catches_a_modifier_the_revive_never_reads() -> void:
	# Damage, area and count are not read by PlayerRevive's plan: the recharge, HP share and guard stay as they were.
	var base := _revive_probe("resurrection", [])
	for effect: Dictionary in [{"stat": "damage", "op": "mul", "value": 1.2}, {"stat": "count", "op": "add", "value": 2.0}]:
		var with := _revive_probe("resurrection", [effect])
		assert_eq(with.revive_hp, base.revive_hp, str(effect))
		assert_eq(with.guard, base.guard, str(effect))
		assert_eq(with.recharge, base.recharge, str(effect))
	# And the shipped modifiers do change it.
	assert_true(float(_revive_probe("resurrection", [{"stat": "revive_guard", "op": "add", "value": 1.5}]).guard) > float(base.guard))


func test_every_buccaneer_bonus_changes_the_resolved_cast_and_all_are_counted() -> void:
	# The file-wide audit above walks them too; this one names the counts so a dropped skill or effect fails here.
	var skills := _resolved()
	var effects := 0
	for key: String in BUCCANEER_SKILLS:
		assert_true((skills[key] as Dictionary).has("rarity_bonuses"), key)
		for tier: String in TIERS:
			for bonus: Dictionary in skills[key].rarity_bonuses[tier]:
				effects += (bonus.effects as Array).size()
	assert_eq(effects, BUCCANEER_SKILLS.size() * 5, "each skill: 1 + 1 + 1 + 2 effects")


func test_the_probe_catches_a_buccaneer_modifier_the_cast_rule_never_reads() -> void:
	# A box cast never reads `pierce` or `summon_count`; `crit` shows only in the hit events' critical flag.
	var pierce := {"stat": "pierce", "op": "add", "value": 1.0}
	assert_eq(_probe("flash_fist", [pierce], "pierce").affected, _probe("flash_fist", [], "pierce").affected, "pierce does nothing on a box")
	var allies := {"stat": "summon_count", "op": "add", "value": 1.0}
	assert_eq(_probe("corkscrew_blow", [allies], "summon_count").summons, 0)
	var crit := {"stat": "crit", "op": "add", "value": 0.15}
	assert_true(int(_probe("backspin_blow", [crit], "crit").crits) > int(_probe("backspin_blow", [], "crit").crits), "crit shows in the hit events")
