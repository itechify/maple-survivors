extends TestCase
## Flying bosses, Dispel (MobSkill 127) and Reflect (143/144/145) (ticket #461 of spec #448, B6; docs/GAME_DESIGN.md
## "Constants and provenance"). Seeded RunWorld, fixed ticks, a synthetic boss and MobSkill.img levels with the v83
## values of Papulatus's clock (127/1: interval 1, prop 100, box +-300 x 120) and Lilynouch (145/1: x2000, y1500,
## hp<=50, interval 60, time 10); the flying form is Papulatus 8500002's shape (a `fly` stance, touch only).

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const BOSS := 2220000
const PATH := "Skill.wz/MobSkill.img/%d/level/%d"
const FORM := "test_form"
## The flying final form of a grounded shell (Papulatus 8500001 -> 8500002's shape).
const FLY_FORM := 8500002


func _anim(frames: int, delay: float) -> Dictionary:
	var out := {}
	for i in frames:
		out[str(i)] = {"delay": delay}
	return out


## MobSkill.img levels. `opts`: `prop` (Dispel's chance), `reflect_interval`, `weapon_interval` (140).
func _skill_img(opts: Dictionary) -> Dictionary:
	return {
		"127": {"level": {"1": {"interval": 1.0, "prop": float(opts.get("prop", 100.0)),
			"lt": {"$v": [-300.0, -120.0]}, "rb": {"$v": [300.0, 120.0]}, "affected": _anim(4, 120.0)}}},
		"140": {"level": {"12": {"x": 1.0, "interval": float(opts.get("weapon_interval", 30.0)), "time": 10.0,
			"mob": _anim(1, 100.0)}}},
		"143": {"level": {"1": {"x": 2000.0, "y": 1500.0, "interval": 60.0, "time": 10.0, "mob": _anim(1, 100.0)}}},
		"144": {"level": {"1": {"x": 2000.0, "y": 1500.0, "interval": 60.0, "time": 10.0, "mob": _anim(1, 100.0)}}},
		"145": {"level": {"1": {"x": 2000.0, "y": 1500.0, "hp": 50.0, "interval": float(opts.get("reflect_interval", 60.0)),
			"time": 10.0, "mob": _anim(1, 100.0)}}},
	}


## A quiet seeded world whose one scheduled boss lists `skills` ([[id, level], ...]). `opts`: `fly` (the boss has a `fly`
## stance and no foothold), `attack` (a type-0 attack1, box (-300,-60)-(300,160), every 4 s), `touch` (PADamage, default
## 800) and see _skill_img. The player has 100000 HP, stands at x = 400, and the boss is at (600, 200).
func _world(skills: Array, opts := {}) -> RunWorld:
	var data := RF.quiet_data()
	if not bool(opts.get("keep_skills", false)):
		data.jobs_survivor.jobs["212"]["starting_skill"] = ""; data.jobs_survivor.jobs["212"]["mobility_skill"] = ""
	data.balance.player.hp = 100000
	data.balance.regen.hp = 0
	data.balance.bosses.teleport_stall = 10000.0
	data.balance.mob_motion.push_px = 0
	data.balance.magnet_radius = 0
	data.balance.mob_skills.enabled_ids = [BOSS, FLY_FORM]
	var entry := {"time": float(opts.get("boss_time", 0.0)), "mob_id": BOSS}
	if bool(opts.get("final_form", false)):
		entry.final_form = FLY_FORM
	if bool(opts.get("level_scale", false)):
		data.stages.stages.quiet["level_scale"] = {"keyframes": [{"t": 0, "level": 10}, {"t": 600, "level": 70}]}
		var curve := {"_doc": "synthetic", "levels": [], "hp": [], "pad": [], "mad": [], "pdd": [], "mdd": [], "exp": []}
		for level in range(1, 201):
			curve.levels.append(level)
			curve.hp.append(100.0 * level * level)
			curve.pad.append(10.0 * level)
			curve.mad.append(20.0 * level + 100.0)
			curve.pdd.append(5.0 * level)
			curve.mdd.append(8.0 * level + 40.0)
			curve.exp.append(3.0 * level * level)
		data["level_curve"] = curve
	if bool(opts.get("attack", false)):
		entry.attacks = ["attack1"]
		entry.attack_interval = 4.0
	RF.set_bosses(data.stages.stages.quiet, [entry])
	var setup := RF.setup("quiet", int(opts.get("seed", 461)), data)
	setup.map_img = RF.map_from_segments([{"x1": -3000, "y1": 200, "x2": 3000, "y2": 200}], [Vector2.ZERO])
	setup.map_img.info = {"VRLeft": -3000, "VRRight": 3000, "VRTop": -1500, "VRBottom": 400}
	var img: Dictionary = setup.mob_imgs[100100].duplicate(true)
	img.info = {"boss": 1.0, "level": 20.0, "maxHP": 2000.0, "PADamage": float(opts.get("touch", 800.0)),
		"MADamage": 500.0, "PDDamage": 20.0, "MDDamage": 30.0, "speed": -100.0, "bodyAttack": 1.0, "acc": 10000.0,
		"skill": {}}
	img.skill1 = _anim(2, 750.0)
	if bool(opts.get("fly", false)):
		img.info.flySpeed = float(opts.get("fly_speed", 100.0))
		img.fly = img.move
		img.erase("move")
		img.erase("stand")
	if bool(opts.get("attack", false)):
		img.attack1 = _anim(3, 300.0)
		img.attack1.info = {"type": 0.0, "attackAfter": 300.0, "effectAfter": 0.0, "PADamage": 300.0,
			"range": {"lt": {"$v": [-300.0, -60.0]}, "rb": {"$v": [300.0, 160.0]}}}
	for pair: Array in skills:
		img.info.skill[str(img.info.skill.size())] = {"skill": float(pair[0]), "level": float(pair[1]),
			"action": 1.0, "effectAfter": 0.0}
	setup.mob_imgs[BOSS] = img
	if bool(opts.get("final_form", false)):
		img.info.revive = {"0": float(FLY_FORM)}
		var form: Dictionary = img.duplicate(true)
		form.info.erase("revive")
		form.info.skill = {}
		form.info.level = 40.0
		form.info.speed = 60.0
		form.fly = form.move
		form.erase("move")
		form.erase("stand")
		setup.mob_imgs[FLY_FORM] = form
	setup.mob_skill_img = _skill_img(opts)
	var w := RunWorld.new(setup)
	w.progression.job_id = 999
	RF.place_player(w, 400)
	w.step(DT, MoveInput.new())
	if w.transfer_pending:
		w.advance_map()
	if bool(opts.get("relocate", true)):
		w.relocate_mob(_boss(w), Vector2(600, 200), w.fhm.find_below(600, 190))
	w.book.defs[FORM] = {"skill_id": 9991001, "book": "999", "kind": "form", "slot": "active",
		"damage": "none", "cooldown": 3.0, "ranks": [1], "cast": {"rule": "form", "mob_within": 400},
		"form": {"duration": 100.0, "exclusive_group": "test", "effects": {"element": "f"}, "subs": []}}
	w.book.skill_imgs["999"] = {"skill": {"9991001": {"level": {"1": {"damage": 120}}}}}
	w.loadout.add_skill(FORM)
	if not bool(opts.get("keep_skills", false)):
		w.loadout.order.clear() # the Form is started by hand, never auto-cast again after a Dispel
	w.drain_events()
	return w


const KILL := {"damage_min": 1000000000, "damage_max": 1000000000, "magic": true, "crit": 0.0, "crit_mult": 1.5,
	"skill": "energy_bolt"}


func _boss(w: RunWorld) -> int:
	return int(w.bosses.records[0].slot)


func _ticks(w: RunWorld, n: int, input: MoveInput = null) -> Array:
	var out: Array = []
	for tick in n:
		w.step(DT, input if input != null else MoveInput.new())
		out.append_array(w.drain_events())
	return out


func _of(events: Array, type: String) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return e.type == type)


func _casts(events: Array, id: int) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return e.type == "boss_skill" and int(e.skill_id) == id)


func _start_form(w: RunWorld) -> void:
	w.runner.forms.start(w, FORM, w.loadout.stats(FORM))


func _start_buff(w: RunWorld, key: String, slot := "") -> void:
	if slot != "":
		w.book.defs[key] = {"slot": slot}
	w.start_buff(key, {"skill_id": 9991002, "level": 1, "icon": "", "duration": 100.0, "buff_stat": "pdd",
		"buff_value": 10.0, "pulse_interval": 0.0, "buff_effects": {"pdd": 10.0}})


func _hp(w: RunWorld) -> int:
	return int(w.player_state.hp)


func _set_hp_percent(w: RunWorld, slot: int, percent: float) -> void:
	w.swarm.hp[slot] = int(float(w.swarm.max_hp[slot]) * percent / 100.0)


func _physical_hit(w: RunWorld, slot: int, amount := 1000.0) -> void:
	w.hit_mob(slot, {"damage_min": amount, "damage_max": amount, "magic": false, "crit": 0.0, "crit_mult": 1.5,
		"skill": "three_snails"}, -1)


func _magic_hit(w: RunWorld, slot: int, amount := 1000.0) -> void:
	w.hit_mob(slot, {"damage_min": amount, "damage_max": amount, "magic": true, "crit": 0.0, "crit_mult": 1.5,
		"skill": "energy_bolt"}, -1)


# --- flying bosses --------------------------------------------------------------------------------------------------

func test_a_flying_boss_has_no_foothold_and_chases_the_character() -> void:
	var w := _world([], {"fly": true})
	var slot := _boss(w)
	assert_eq(w.swarm.fh[slot], -1, "a boss with a fly stance spawns and relocates without a foothold")
	w.player.place(Vector2(-1500, 200), w.fhm)
	w.update_view()
	_ticks(w, 120)
	var start_x := w.swarm.x[slot]
	_ticks(w, 60)
	assert_true(w.swarm.x[slot] < start_x - 30.0, "it moves toward the character a second later: %s -> %s" % [start_x, w.swarm.x[slot]])
	assert_eq(w.swarm.fh[slot], -1, "and never lands on a foothold")
	assert_true(w.bounds.has_point(w.swarm.pos(slot)), "inside the map's bounds")


func test_a_flying_boss_climbs_to_a_character_above_any_foothold() -> void:
	var w := _world([], {"fly": true})
	var slot := _boss(w)
	# The character stands on the floor, the boss is high in the air: it descends without a path or a platform.
	w.relocate_mob(slot, Vector2(600, -600), -1)
	_ticks(w, 240)
	assert_true(w.swarm.y[slot] > -300.0, "it flew down toward the character: y=%s" % w.swarm.y[slot])


func test_a_flying_boss_stays_inside_the_bounds_it_flies_in() -> void:
	var w := _world([], {"fly": true})
	var slot := _boss(w)
	w.player.place(Vector2(2990, 200), w.fhm)
	w.update_view()
	_ticks(w, 600)
	assert_true(w.bounds.has_point(w.swarm.pos(slot)), "clamped to the map's bounds: %s" % w.swarm.pos(slot))


func test_a_flying_boss_deals_contact_damage() -> void:
	var w := _world([], {"fly": true})
	w.relocate_mob(_boss(w), w.player.pos + Vector2(0, -20), -1)
	var before := _hp(w)
	var events := _ticks(w, 180)
	var touches := _of(events, "player_hit").filter(func(e: Dictionary) -> bool:
		return String(e.source_kind) == "touch" and bool(e.boss) and not bool(e.miss))
	assert_true(touches.size() >= 1, "the flying boss's touch hits the character")
	assert_true(_hp(w) < before, "and costs HP")


func test_a_flying_boss_attacks_from_its_own_position_in_the_air() -> void:
	var w := _world([], {"fly": true, "attack": true, "touch": 0.0})
	var slot := _boss(w)
	w.relocate_mob(slot, Vector2(450, 60), -1)
	var before := _hp(w)
	var events := _ticks(w, 60 * 3)
	var starts := _of(events, "boss_attack").filter(func(e: Dictionary) -> bool: return e.phase == "start")
	assert_true(starts.size() >= 1, "a boss without a foothold starts its attack")
	if starts.is_empty():
		return
	assert_true(float(starts[0].pos.y) < w.player.pos.y - 100.0, "from the air, not from a floor: %s" % starts[0].pos)
	assert_eq(w.swarm.fh[slot], -1, "still without a foothold")
	var hits := _of(events, "player_hit").filter(func(e: Dictionary) -> bool: return String(e.source_kind) == "attack")
	assert_true(hits.size() >= 1 and _hp(w) < before, "and it lands: the character is hit by the attack")


func test_a_flying_boss_hovers_while_its_attack_plays() -> void:
	var w := _world([], {"fly": true, "attack": true, "touch": 0.0})
	var slot := _boss(w)
	w.relocate_mob(slot, Vector2(1000, 60), -1)
	w.player.place(Vector2(750, 200), w.fhm)
	w.update_view()
	var events := _ticks(w, 60 * 3)
	var starts := _of(events, "boss_attack").filter(func(e: Dictionary) -> bool: return e.phase == "start")
	var impacts := _of(events, "boss_attack").filter(func(e: Dictionary) -> bool: return e.phase == "impact")
	assert_true(starts.size() >= 1 and impacts.size() >= 1, "an attack was played")
	if starts.is_empty() or impacts.is_empty():
		return
	assert_eq(impacts[0].pos, starts[0].pos, "the boss held its place between the windup and the impact")


func test_a_grounded_boss_still_needs_a_foothold_to_attack() -> void:
	var w := _world([], {"attack": true, "touch": 0.0})
	var slot := _boss(w)
	w.player.place(Vector2(-1500, 200), w.fhm) # out of range while the boss's regen fade-in finishes
	w.update_view()
	_ticks(w, 180)
	w.player.place(Vector2(400, 200), w.fhm)
	w.update_view()
	# Falling a few pixels above the floor: no foothold for a few ticks, like a boss knocked off its platform.
	w.swarm.y[slot] = 150.0
	w.swarm.fh[slot] = -1
	var starts := _of(_ticks(w, 4), "boss_attack").filter(func(e: Dictionary) -> bool: return e.phase == "start")
	assert_true(starts.is_empty() and w.swarm.fh[slot] < 0, "a grounded boss in the air does not attack, as before")


func test_flight_is_deterministic() -> void:
	var trace: Array = []
	for run in 2:
		var w := _world([], {"fly": true, "attack": true})
		_ticks(w, 300)
		trace.append([w.swarm.pos(_boss(w)), _hp(w)])
	assert_eq(trace[0], trace[1], "same seed, same outcome")


# --- Dispel 127 -----------------------------------------------------------------------------------------------------

func test_the_runner_supports_dispel_and_the_reflects() -> void:
	for id in [127, 143, 144, 145]:
		assert_true(id in MobSkillRunner.SUPPORTED, "%d is cast" % id)
	assert_eq(MobSkillRunner.SKILL_DISPEL, 127)
	assert_eq(MobSkillRunner.REFLECT_IDS, [143, 144, 145])
	assert_true(MobSkillRunner.DISPEL_LOCKOUT >= 20.0)


func test_dispel_ends_the_forms_and_timed_buffs_and_nothing_else() -> void:
	var w := _world([[127, 1]])
	_start_form(w)
	_start_buff(w, "timed_buff")
	_start_buff(w, "summon_pulse_buff", "summon_sub")
	w.runner.cooldowns["other_skill"] = 7.5
	var rank_before := w.loadout.ranks.duplicate()
	assert_true(w.can_dispel())
	var events := _ticks(w, 61)
	var dispels := _of(events, "player_dispelled")
	assert_eq(dispels.size(), 1, "one Dispel within its 1 s interval")
	if dispels.is_empty():
		return
	assert_eq(dispels[0].skills, [FORM, "timed_buff"], "the Form first, then the timed buff")
	assert_eq(int(dispels[0].skill_id), 127)
	assert_eq(String(dispels[0].effect), PATH % [127, 1] + "/affected", "the level's affected art")
	assert_true(w.runner.forms.snapshot().is_empty(), "the Form ended")
	assert_false(w.buffs.has(FORM), "with its buff")
	assert_false(w.buffs.has("timed_buff"), "the timed self-buff ended")
	assert_true(w.buffs.has("summon_pulse_buff"), "a support summon's pulse buff stays")
	assert_true(_of(events, "form_ended").any(func(e: Dictionary) -> bool: return e.reason == "dispelled"))
	assert_eq(w.loadout.ranks, rank_before, "passives and ranks are untouched")
	assert_true(float(w.runner.cooldowns["other_skill"]) > 0.0, "cooldowns keep running")
	assert_eq(_casts(events, 127).size(), 1, "the boss cast it (its skill stance)")


func test_dispel_leaves_the_boss_statuses_on_the_character() -> void:
	var w := _world([[127, 1]])
	_start_form(w)
	var statuses := w.mob_skills.statuses
	for id in [MobSkillRunner.SKILL_STUN, MobSkillRunner.SKILL_DARKNESS, MobSkillRunner.SKILL_CONFUSE]:
		statuses.apply(id, w.time, 30.0, {})
	statuses.apply(MobSkillRunner.SKILL_SLOW, w.time, 30.0, {"multiplier": 0.8}, false)
	var events := _ticks(w, 61)
	assert_eq(_of(events, "player_dispelled").size(), 1, "the Form is ended")
	for id in [MobSkillRunner.SKILL_STUN, MobSkillRunner.SKILL_DARKNESS, MobSkillRunner.SKILL_CONFUSE, MobSkillRunner.SKILL_SLOW]:
		assert_true(statuses.is_active(id, w.time), "boss status %d is a debuff, not a self-effect: it stays" % id)
	# With only debuffs on the character there is nothing to dispel: the boss waits.
	assert_false(w.can_dispel())


func test_dispel_waits_while_there_is_nothing_to_end() -> void:
	var w := _world([[127, 1]])
	assert_false(w.can_dispel())
	assert_eq(_casts(_ticks(w, 300), 127).size(), 0, "nothing to end: no cast, no lockout spent")
	_start_form(w)
	assert_eq(_of(_ticks(w, 2), "player_dispelled").size(), 1, "a Form cast later is ended on the next tick")


func test_dispel_has_a_lockout_of_at_least_twenty_seconds() -> void:
	var w := _world([[127, 1]])
	_start_form(w)
	var first := _of(_ticks(w, 61), "player_dispelled")
	assert_eq(first.size(), 1)
	var cast_time := float(first[0].time)
	_start_form(w)
	var early := _ticks(w, 60 * 19)
	assert_eq(_of(early, "player_dispelled").size(), 0, "19 s after the cast the Form is still up")
	assert_eq(w.runner.forms.snapshot().size(), 1)
	var late := _ticks(w, 60 * 2)
	var again := _of(late, "player_dispelled")
	assert_eq(again.size(), 1, "and it is ended again once the floor has passed")
	assert_true(float(again[0].time) - cast_time >= 20.0 - 1e-6, "no sooner than 20 s: %s" % (float(again[0].time) - cast_time))
	assert_true(float(again[0].time) - cast_time < 20.0 + 0.1, "and at once after it")


func test_dispel_needs_the_character_in_its_box_and_not_hidden() -> void:
	for offset in [Vector2(-301, 0), Vector2(301, 0)]:
		var w := _world([[127, 1]])
		_start_form(w)
		w.player.place(Vector2(600, 200) + offset, w.fhm)
		w.update_view()
		assert_eq(_of(_ticks(w, 120), "player_dispelled").size(), 0, "outside the box: %s" % offset)
	# 125 px above and below the boss's feet are outside the +-120 box (its 2 px bob included): a flier that holds still.
	for dy in [-125.0, 125.0]:
		var flier := _world([[127, 1]], {"fly": true, "fly_speed": -100.0})
		_start_form(flier)
		flier.relocate_mob(_boss(flier), Vector2(400, 200 + dy), -1)
		assert_eq(_of(_ticks(flier, 240), "player_dispelled").size(), 0, "%s px from the boss's feet" % dy)
		flier.relocate_mob(_boss(flier), Vector2(400, 200 + dy * 0.8), -1)
		assert_eq(_of(_ticks(flier, 240), "player_dispelled").size(), 1, "control: %s px" % (dy * 0.8))
	var inside := _world([[127, 1]])
	_start_form(inside)
	inside.player.place(Vector2(600 - 299, 200), inside.fhm)
	inside.update_view()
	assert_eq(_of(_ticks(inside, 120), "player_dispelled").size(), 1, "control: inside the box")
	var hidden := _world([[127, 1]])
	_start_form(hidden)
	hidden.start_buff("synthetic_hide", {"skill_id": 9991003, "level": 1, "icon": "", "duration": 100.0,
		"buff_stat": "", "buff_value": 0.0, "pulse_interval": 0.0, "hidden": true, "buff_effects": {}})
	assert_true(hidden.is_hidden())
	assert_eq(_casts(_ticks(hidden, 240), 127).size(), 0, "Hidden skips Dispel")


func test_a_failed_prop_roll_spends_the_interval_and_ends_nothing() -> void:
	var w := _world([[127, 1]], {"prop": 0.0})
	_start_form(w)
	var events := _ticks(w, 150)
	assert_true(_casts(events, 127).size() >= 1, "the boss still casts (and spends its interval)")
	assert_eq(_of(events, "player_dispelled").size(), 0, "but nothing ends")
	assert_eq(w.runner.forms.snapshot().size(), 1)


func test_dispel_rolls_repeat_for_the_same_seed() -> void:
	var results: Array = []
	for run in 2:
		var w := _world([[127, 1]], {"prop": 50.0, "seed": 9})
		var casts := 0
		var ended := 0
		for round in 8:
			_start_form(w)
			var events := _ticks(w, 60 * 21)
			casts += _casts(events, 127).size()
			ended += _of(events, "player_dispelled").size()
			w.runner.forms.clear(w)
		results.append([casts, ended])
	assert_eq(results[0], results[1], "same seed, same rolls")
	assert_true(results[0][1] > 0 and results[0][0] > results[0][1], "a half-chance roll both succeeds and fails: %s" % [results[0]])


# --- Reflect 143 / 144 / 145 ----------------------------------------------------------------------------------------

## A world whose boss is at 40% health and has just cast reflect `id` (every 5 s for 145; 143/144 wait their 60 s).
func _reflecting(id := 145, opts := {}) -> RunWorld:
	var w := _world([[id, 1]], opts.merged({"reflect_interval": 5.0}))
	_set_hp_percent(w, _boss(w), 40.0)
	for tick in 60 * 70:
		w.step(DT, MoveInput.new())
		if not _casts(w.drain_events(), id).is_empty():
			break
	return w


func test_reflect_145_waits_for_its_hp_gate_and_shows_its_icon() -> void:
	var full := _world([[145, 1]], {"reflect_interval": 5.0})
	assert_eq(_casts(_ticks(full, 60 * 12), 145).size(), 0, "full health: above hp<=50")
	var w := _reflecting()
	var slot := _boss(w)
	assert_eq(w.time > 4.9 and w.time < 5.2, true, "cast on its 5 s interval: %s" % w.time)
	var state := w.mob_skills.reflect_state(slot, w.time)
	assert_eq(String(state.visual), PATH % [145, 1] + "/mob", "its mob icon")
	assert_true(bool(state.physical) and bool(state.magic))
	assert_true(w.mob_skills.status_visuals(slot, w.time).has(PATH % [145, 1] + "/mob"), "drawn over the boss")
	assert_true(float(state.remaining) <= 10.0 and float(state.remaining) > 9.9, "for its 10 s: %s" % state.remaining)


func test_a_reflected_hit_deals_nothing_to_the_boss_and_hurts_the_character_by_the_formula() -> void:
	var w := _reflecting()
	var slot := _boss(w)
	assert_true(w.mob_skills.reflect_state(slot, w.time).size() > 0)
	var boss_hp := w.swarm.hp[slot]
	var dealt := w.damage_dealt
	var before := _hp(w)
	_physical_hit(w, slot, 100.0)
	var events := w.drain_events()
	assert_eq(w.swarm.hp[slot], boss_hp, "the boss takes 0")
	assert_eq(w.damage_dealt, dealt, "and none counts as dealt")
	assert_true(_of(events, "mob_hit").is_empty(), "no mob_hit for a reflected hit")
	var reflects := _of(events, "boss_reflect")
	assert_eq(reflects.size(), 1)
	var rolled := int(reflects[0].damage)
	assert_true(rolled > 0)
	# x2000 is 20% of the hit; the cap is y1500 x cap_mult (0.03) = 45 HP.
	var expected := roundi(minf(rolled * 0.2 * 1.0, 1500.0 * 0.03))
	assert_eq(int(reflects[0].amount), expected)
	assert_eq(before - _hp(w), expected, "the character loses exactly that")
	var hit := _of(events, "player_hit")
	assert_eq(hit.size(), 1)
	assert_eq(String(hit[0].source_kind), "reflect")


func test_a_big_hit_is_capped_by_y() -> void:
	var w := _reflecting()
	var slot := _boss(w)
	var before := _hp(w)
	_magic_hit(w, slot, 50000.0)
	assert_eq(before - _hp(w), 45, "min(damage x 20%, 1500 x 0.03) = 45")


func test_reflect_is_limited_to_one_hurt_per_half_second() -> void:
	var w := _reflecting()
	var slot := _boss(w)
	var boss_hp := w.swarm.hp[slot]
	var before := _hp(w)
	_magic_hit(w, slot, 50000.0)
	_magic_hit(w, slot, 50000.0)
	_physical_hit(w, slot, 50000.0)
	assert_eq(before - _hp(w), 45, "three hits in one tick hurt once")
	assert_eq(w.swarm.hp[slot], boss_hp, "yet all three deal 0 to the boss")
	_ticks(w, 29)
	_magic_hit(w, slot, 50000.0)
	assert_eq(before - _hp(w), 45, "29 ticks later it is still inside 0.5 s")
	_ticks(w, 1)
	_magic_hit(w, slot, 50000.0)
	assert_eq(before - _hp(w), 90, "at 0.5 s it hurts again")


func test_143_reflects_only_physical_and_144_only_magic() -> void:
	for pair: Array in [[143, false, true], [144, true, false]]:
		var w := _world([[pair[0], 1]], {"reflect_interval": 5.0})
		var slot := _boss(w)
		# 143 and 144 have no hp gate in this data; they cast on the first 60 s interval.
		var cast := _casts(_ticks(w, 60 * 61), pair[0])
		assert_true(cast.size() >= 1, "%d is cast" % pair[0])
		var before := _hp(w)
		var boss_hp := w.swarm.hp[slot]
		_physical_hit(w, slot, 500.0)
		var physical_reflected := w.swarm.hp[slot] == boss_hp
		boss_hp = w.swarm.hp[slot]
		_ticks(w, 60)
		_magic_hit(w, slot, 500.0)
		var magic_reflected := w.swarm.hp[slot] == boss_hp
		assert_eq(physical_reflected, pair[2] as bool, "%d physical" % pair[0])
		assert_eq(magic_reflected, pair[1] as bool, "%d magic" % pair[0])
		assert_true(_hp(w) < before, "the reflected type hurt the character")


func test_reflect_ends_after_its_time() -> void:
	var w := _reflecting()
	var slot := _boss(w)
	var cast_time := w.time
	w.mob_skills._ready["0/145/1"] = w.time + 1000.0 # no recast: let it run out
	while w.time < cast_time + 10.0 - 3.0 * DT:
		w.step(DT, MoveInput.new())
	assert_false(w.mob_skills.reflect_state(slot, w.time).is_empty(), "still reflecting just before 10 s")
	_ticks(w, 6)
	assert_true(w.mob_skills.reflect_state(slot, w.time).is_empty(), "over after 10 s")
	var boss_hp := w.swarm.hp[slot]
	_magic_hit(w, slot, 500.0)
	assert_true(w.swarm.hp[slot] < boss_hp, "hits land again")


func test_reflect_never_overlaps_the_immunity_on_the_same_boss() -> void:
	# 145 first (every 5 s, always up), then 140 every 8 s: every 140 cast is skipped.
	var a := _world([[145, 1], [140, 12]], {"reflect_interval": 5.0, "weapon_interval": 8.0})
	_set_hp_percent(a, _boss(a), 40.0)
	var events := _ticks(a, 60 * 40)
	assert_true(_casts(events, 145).size() >= 5, "the reflect keeps being cast")
	assert_eq(_casts(events, 140).size(), 0, "140 is skipped while it reflects")
	assert_true(a.physical_hit_allowed(_boss(a)), "the boss was never weapon-immune")
	# 140 first (every 5 s), then 145 every 8 s: every 145 cast is skipped.
	var b := _world([[140, 12], [145, 1]], {"weapon_interval": 5.0, "reflect_interval": 8.0})
	_set_hp_percent(b, _boss(b), 40.0)
	var again := _ticks(b, 60 * 40)
	assert_true(_casts(again, 140).size() >= 5)
	assert_eq(_casts(again, 145).size(), 0, "145 is skipped while 140 is up")
	assert_true(b.mob_skills.reflect_state(_boss(b), b.time).is_empty())


func test_a_skipped_reflect_spends_its_interval() -> void:
	var w := _world([[140, 12], [145, 1]], {"weapon_interval": 5.0, "reflect_interval": 8.0})
	_set_hp_percent(w, _boss(w), 40.0)
	_ticks(w, 60 * 9)
	assert_eq(int(w.mob_skills._ready["0/145/1"] > w.time), 1, "the skipped cast scheduled its next try")


func test_the_player_projectiles_are_reflected_too() -> void:
	var w := _world([[145, 1]], {"reflect_interval": 5.0, "keep_skills": true})
	var slot := _boss(w)
	_set_hp_percent(w, slot, 40.0)
	var seen := false
	var boss_hp := -1
	var before := _hp(w)
	for tick in 60 * 20:
		w.step(DT, MoveInput.new())
		var events := w.drain_events()
		if boss_hp < 0 and not w.mob_skills.reflect_state(slot, w.time).is_empty():
			boss_hp = w.swarm.hp[slot]
		if boss_hp >= 0 and not _of(events, "boss_reflect").is_empty():
			seen = true
			assert_eq(w.swarm.hp[slot], boss_hp, "a bolt that was reflected did not wound the boss")
			break
	assert_true(seen, "an automatic cast of the character was reflected")
	assert_true(_hp(w) < before, "and cost HP")


func test_reflect_is_deterministic() -> void:
	var trace: Array = []
	for run in 2:
		var w := _world([[145, 1]], {"reflect_interval": 5.0})
		_set_hp_percent(w, _boss(w), 40.0)
		_ticks(w, 60 * 6)
		var hps: Array = []
		for hit in 6:
			_magic_hit(w, _boss(w), 800.0)
			_ticks(w, 20)
			hps.append(_hp(w))
		trace.append(hps)
	assert_eq(trace[0], trace[1], "same seed, same outcome")



# --- flying bosses through the director and a final form ---------------------------------------------------------------

func test_a_scheduled_flyer_arrives_through_the_director_without_a_foothold() -> void:
	var w := _world([], {"fly": true, "boss_time": 2.0, "relocate": false})
	assert_eq(_boss(w), -1, "not there before its schedule")
	var spawned: Array = []
	for tick in 60 * 4:
		w.step(DT, MoveInput.new())
		spawned.append_array(_of(w.drain_events(), "boss_spawned"))
	assert_eq(spawned.size(), 1, "one arrival")
	var slot := _boss(w)
	assert_true(slot >= 0 and float(w.bosses.records[0].spawn_time) >= 2.0 - 1e-6)
	assert_eq(w.swarm.fh[slot], -1, "a flyer arrives with no foothold")
	assert_eq(w.mob_boss[slot], 0)
	assert_eq(w.swarm.steady[slot], 1, "and is as steady as any scheduled boss")
	var distance := absf(w.swarm.x[slot] - w.player.pos.x)
	_ticks(w, 120)
	assert_true(absf(w.swarm.x[slot] - w.player.pos.x) < distance or distance < 60.0, "it closes in on the character")
	assert_true(w.bounds.has_point(w.swarm.pos(slot)))


func test_a_grounded_shell_becomes_a_flying_form_with_its_level_scale_captured() -> void:
	var w := _world([], {"final_form": true, "level_scale": true, "touch": 0.0, "relocate": false})
	_ticks(w, 60)
	var record: Dictionary = w.bosses.records[0]
	var shell := int(record.slot)
	assert_eq(w.mob_kinds[w.swarm.kind[shell]].flies, false)
	assert_true(w.swarm.fh[shell] >= 0, "the shell stands on a foothold")
	var arrival := float(record.level_scale_at)
	_ticks(w, 600)
	w.player.place(Vector2(-1500, 200), w.fhm)
	w.update_view()
	w.hit_mob(shell, KILL, -1)
	var events := w.drain_events()
	assert_eq(_of(events, "mob_revives_spawned").size(), 1)
	var form := int(record.slot)
	assert_ne(form, shell)
	assert_eq(int(record.mob_id), FLY_FORM)
	assert_eq(w.swarm.fh[form], -1, "the grounded shell's form flies: no foothold")
	assert_true(w.mob_kinds[w.swarm.kind[form]].flies)
	assert_eq(w.mob_boss[form], 0, "same encounter")
	assert_false(bool(record.dead))
	var start := w.swarm.pos(form)
	_ticks(w, 120)
	assert_true(w.swarm.pos(form).distance_to(start) > 20.0, "the form moves toward the character: %s -> %s" % [start, w.swarm.pos(form)])
	assert_eq(w.swarm.fh[form], -1)
	var effective := w.level_scale.level_at(w.curve_time())
	var frozen: Array = w._boss_level_damage[0]
	assert_near(float(frozen[0]), w.level_scale.ratio("pad", effective, 40), 0.05, "the form's damage ratios come from its own level")
	assert_eq(float(record.level_scale_at), arrival, "level_scale_at keeps the first arrival")


# --- Reflect: who can be hurt, and how often ----------------------------------------------------------------------------

func test_a_hidden_character_is_not_hurt_by_a_reflect_and_the_slot_is_not_spent() -> void:
	var w := _reflecting()
	var slot := _boss(w)
	w.start_buff("synthetic_hide", {"skill_id": 9991003, "level": 1, "icon": "", "duration": 100.0,
		"buff_stat": "", "buff_value": 0.0, "pulse_interval": 0.0, "hidden": true, "buff_effects": {}})
	var boss_hp := w.swarm.hp[slot]
	var before := _hp(w)
	_magic_hit(w, slot, 50000.0)
	assert_eq(_hp(w), before, "Hidden: nothing from a monster lands")
	assert_eq(w.swarm.hp[slot], boss_hp, "the hit still deals 0 to the boss")
	w.buffs.end("synthetic_hide", w.events)
	_magic_hit(w, slot, 50000.0)
	assert_eq(before - _hp(w), 45, "the refused reflect did not spend the 0.5 s slot")


func test_a_blocked_reflect_leaves_the_slot_free() -> void:
	var w := _reflecting()
	var slot := _boss(w)
	var before := _hp(w)
	w.god = true
	_magic_hit(w, slot, 50000.0)
	assert_eq(_hp(w), before, "god mode refuses it")
	w.god = false
	_magic_hit(w, slot, 50000.0)
	assert_eq(before - _hp(w), 45, "and the next one lands at once")
	_magic_hit(w, slot, 50000.0)
	assert_eq(before - _hp(w), 45, "that one spent the slot")


func test_a_lethal_reflect_kills_and_clears_the_hazards() -> void:
	var w := _reflecting()
	var slot := _boss(w)
	w.hazards.spawn({"rect": Rect2(0, 0, 100, 100), "born": 0.0, "until": 1000.0})
	assert_eq(w.hazards.active_count(), 1)
	w._hp = 10.0
	_magic_hit(w, slot, 50000.0)
	assert_eq(w.state, RunWorld.DEAD, "45 HP of reflect kills a character on 10")
	assert_eq(w.hazards.active_count(), 0, "emptied on death, as take_hit's death does")
	assert_true(w.runner.forms.snapshot().is_empty())


func test_several_reflected_hits_in_one_tick_hurt_once_up_to_the_cap() -> void:
	var w := _world([[145, 1]], {"reflect_interval": 5.0, "keep_skills": true})
	var slot := _boss(w)
	_set_hp_percent(w, slot, 40.0)
	# Run to the first reflect that hurt (an automatic bolt), then pile hits on in the same tick: projectiles keep coming
	# and instant hits, one with a second RNG as Final Attack's follow-up uses, all land inside its 0.5 s slot.
	var hurt_at := -1.0
	var before := 0
	for tick in 60 * 20:
		before = _hp(w)
		w.step(DT, MoveInput.new())
		if not _of(w.drain_events(), "player_hit").is_empty() and before > _hp(w):
			hurt_at = w.time
			break
	assert_true(hurt_at > 0.0, "an automatic cast was reflected and hurt")
	var first_loss := before - _hp(w)
	assert_true(first_loss >= 1 and first_loss <= 45, "within y x c")
	var boss_hp := w.swarm.hp[slot]
	var after_first := _hp(w)
	var follow_up_rng := RandomNumberGenerator.new()
	follow_up_rng.seed = 5
	_magic_hit(w, slot, 50000.0)
	_physical_hit(w, slot, 50000.0)
	w.hit_mob(slot, {"damage_min": 50000.0, "damage_max": 50000.0, "magic": false, "crit": 0.0, "crit_mult": 1.5,
		"skill": "three_snails"}, -1, follow_up_rng)
	_ticks(w, 25)
	assert_eq(_hp(w), after_first, "the other hits, the follow-up and the bolts inside the slot cost nothing more")
	assert_eq(w.swarm.hp[slot], boss_hp, "and none wounds the boss")
	_ticks(w, 10)
	assert_true(after_first - _hp(w) <= 45, "past the slot at most one more reflect, capped at 45: %d" % (after_first - _hp(w)))
