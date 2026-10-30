extends TestCase
## Boss self-buffs MobSkill 101 (magic attack up, self), 111 (magic attack up, area), 102 (PDD up, self) and 103 (MDD up,
## self), and the magic immunity 141 that never overlaps 140 (ticket #457 of spec #448, B2; docs/GAME_DESIGN.md "Constants
## and provenance"). Seeded RunWorld, fixed ticks, a synthetic boss and MobSkill.img levels with the v83 values of
## Chimera (101/1 x115 35 s/30 s, 103/2 x60 40 s/30 s, 111/5 x140 60 s/30 s box (-400,-350)-(400,250)), Dodo (102/3 x85
## 30 s/20 s) and Timer (141/3 x1 hp<=50 30 s/10 s, 140/12 30 s/10 s).

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const BOSS := 2220000
## A large synthetic attack, so a x1.15 difference stands well clear of rounding.
const ATTACK := 1000.0
const SKILL_PATH := "Skill.wz/MobSkill.img/%d/level/%d"


func _anim(frames: int, delay: float) -> Dictionary:
	var out := {}
	for i in frames:
		out[str(i)] = {"delay": delay}
	return out


## v83-shaped MobSkill.img levels. `opts`: `x101` (the 101/1 x), `hp_gate` (an hp field on every level), `intervals`
## ({"<id>": s}).
func _skill_img(opts: Dictionary) -> Dictionary:
	var gate: float = float(opts.get("hp_gate", -1.0))
	var intervals: Dictionary = opts.get("intervals", {})
	var img := {
		"101": {"level": {"1": {"x": float(opts.get("x101", 115.0)), "interval": 35.0, "time": 30.0,
			"effect": _anim(6, 100.0), "mob": _anim(1, 100.0)}}},
		"102": {"level": {"3": {"x": 85.0, "interval": 30.0, "time": 20.0,
			"effect": _anim(6, 100.0), "mob": _anim(1, 100.0)}}},
		"103": {"level": {"2": {"x": 60.0, "interval": 40.0, "time": 30.0,
			"effect": _anim(6, 100.0), "mob": _anim(1, 100.0)}}},
		"111": {"level": {"5": {"x": 140.0, "interval": 60.0, "time": 30.0,
			"lt": {"$v": [-400.0, -350.0]}, "rb": {"$v": [400.0, 250.0]},
			"effect": _anim(6, 100.0), "mob": _anim(1, 100.0), "mob0": _anim(6, 100.0)}}},
		"140": {"level": {"12": {"x": 1.0, "interval": 30.0, "time": 10.0, "mob": _anim(1, 100.0)}}},
		"141": {"level": {"3": {"x": 1.0, "interval": 30.0, "time": 10.0, "hp": 50.0, "mob": _anim(1, 100.0)}}},
	}
	for id: String in intervals:
		for level: Dictionary in img[id].level.values():
			level.interval = float(intervals[id])
	if gate >= 0.0:
		for skill: Dictionary in img.values():
			for level: Dictionary in skill.level.values():
				level.hp = gate
	return img


## A quiet seeded world whose one scheduled boss (standing still at x = 600) lists `skills` ([[id, level], ...]).
## `opts`: see _skill_img, plus `attack` (a huge-box type-0 attack1 every 4 s) and `magic` (that attack is magic).
## The player has 1,000,000 HP and stands at x = 400.
func _world(skills: Array, opts := {}) -> RunWorld:
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["212"]["starting_skill"] = ""; data.jobs_survivor.jobs["212"]["mobility_skill"] = ""
	data.balance.player.hp = 1000000
	data.balance.regen.hp = 0
	data.balance.bosses.teleport_stall = 10000.0
	data.balance.mob_motion.push_px = 0
	data.balance.magnet_radius = 0
	data.balance.mob_skills.enabled_ids = [BOSS]
	var entry := {"time": 0.0, "mob_id": BOSS}
	if bool(opts.get("attack", false)):
		entry.attacks = ["attack1"]
		entry.attack_interval = 4.0
	RF.set_bosses(data.stages.stages.quiet, [entry])
	var setup := RF.setup("quiet", int(opts.get("seed", 457)), data)
	var img: Dictionary = setup.mob_imgs[100100].duplicate(true)
	img.info = {"boss": 1.0, "level": 20.0, "maxHP": 2000.0, "PADamage": ATTACK, "MADamage": ATTACK, "PDDamage": 20.0,
		"MDDamage": 30.0, "speed": -100.0, "skill": {}}
	img.skill1 = _anim(2, 750.0)
	if bool(opts.get("attack", false)):
		img.attack1 = _anim(3, 300.0)
		img.attack1.info = {"type": 0.0, "attackAfter": 300.0, "effectAfter": 0.0,
			"range": {"lt": {"$v": [-3000.0, -600.0]}, "rb": {"$v": [3000.0, 100.0]}}}
		if bool(opts.get("magic", false)):
			img.attack1.info.magic = 1.0
			img.attack1.info.MADamage = ATTACK
		else:
			img.attack1.info.PADamage = ATTACK
	for pair: Array in skills:
		img.info.skill[str(img.info.skill.size())] = {"skill": float(pair[0]), "level": float(pair[1]),
			"action": 1.0, "effectAfter": 0.0}
	setup.mob_imgs[BOSS] = img
	setup.mob_skill_img = _skill_img(opts)
	var w := RunWorld.new(setup)
	RF.place_player(w, 400)
	w.step(DT, MoveInput.new())
	if w.transfer_pending:
		w.advance_map()
	w.relocate_mob(_boss(w), Vector2(600, 200), w.fhm.find_below(600, 190))
	w.drain_events()
	return w


func _boss(w: RunWorld) -> int:
	return int(w.bosses.records[0].slot)


## An ordinary (unscheduled) still mob of the boss's kind at x.
func _ordinary(w: RunWorld, x: float) -> int:
	return w.spawn_mob(int(w.kind_of_id[BOSS]), Vector2(x, 200), w.fhm.find_below(x, 190), 1.0, false)


func _ticks(w: RunWorld, n: int) -> Array:
	var out: Array = []
	for tick in n:
		w.step(DT, MoveInput.new())
		out.append_array(w.drain_events())
	return out


func _casts(events: Array) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return e.type == "boss_skill")


func _magic_mult(w: RunWorld, slot: int) -> float:
	return w.mob_skills.magic_attack_multiplier(slot, w.time)


func _set_hp_percent(w: RunWorld, slot: int, percent: float) -> void:
	w.swarm.hp[slot] = int(float(w.swarm.max_hp[slot]) * percent / 100.0)


func _magic_hit(w: RunWorld, slot: int, amount := 40.0) -> void:
	w.hit_mob(slot, {"damage_min": amount, "damage_max": amount, "magic": true, "crit": 0.0, "crit_mult": 1.5,
		"skill": "energy_bolt"}, -1)


func _physical_hit(w: RunWorld, slot: int, amount := 40.0) -> void:
	w.hit_mob(slot, {"damage_min": amount, "damage_max": amount, "magic": false, "crit": 0.0, "crit_mult": 1.5,
		"skill": "three_snails"}, -1)


# --- data -----------------------------------------------------------------------------------------------------------

func test_the_runner_supports_every_buff_and_the_magic_immunity() -> void:
	for id in [101, 102, 103, 111, 141]:
		assert_true(id in MobSkillRunner.SUPPORTED, "%d is cast" % id)
	assert_eq(MobSkillRunner.SKILL_MAGIC_ATTACK_UP, 101)
	assert_eq(MobSkillRunner.SKILL_PDD_UP, 102)
	assert_eq(MobSkillRunner.SKILL_MDD_UP, 103)
	assert_eq(MobSkillRunner.SKILL_MAGIC_ATTACK_UP_AREA, 111)
	assert_eq(MobSkillRunner.SKILL_MAGIC_IMMUNITY, 141)


# --- 101 / 111: magic attack up -------------------------------------------------------------------------------------

func test_magic_attack_up_self_casts_on_its_wz_interval_and_buffs_only_the_caster() -> void:
	var w := _world([[101, 1]])
	var boss := _boss(w)
	var near := _ordinary(w, 650)
	w.drain_events()
	assert_eq(_casts(_ticks(w, 2099)).size(), 0, "no cast before the 35 s interval")
	assert_eq(_magic_mult(w, boss), 1.0)
	var cast := _casts(_ticks(w, 1))
	assert_eq(cast.size(), 1, "101/1 casts at 35 s")
	if cast.is_empty():
		return
	assert_eq(int(cast[0].skill_id), 101)
	assert_eq(int(cast[0].level), 1)
	assert_eq(String(cast[0].action), "skill1")
	assert_near(float(cast[0].duration), 30.0, 1e-6)
	assert_eq(cast[0].targets, [boss], "101 targets the caster only")
	assert_eq(String(cast[0].effect), SKILL_PATH % [101, 1] + "/effect", "the cast's effect plays on the caster")
	assert_near(_magic_mult(w, boss), 1.15, 1e-6, "x115 is x1.15")
	assert_eq(_magic_mult(w, near), 1.0, "a mob next to it is not buffed")
	assert_eq(w.mob_skills.attack_multiplier(boss, w.time), 1.0, "weapon attack (100/110) is not touched")
	assert_eq(_casts(_ticks(w, 2099)).size(), 0, "no recast before another 35 s")
	assert_eq(_casts(_ticks(w, 1)).size(), 1, "the second cast at 70 s")


func test_magic_attack_up_lasts_exactly_its_time_in_ticks() -> void:
	var w := _world([[101, 1]])
	var boss := _boss(w)
	_ticks(w, 2100)
	assert_near(_magic_mult(w, boss), 1.15, 1e-6)
	_ticks(w, 1799)
	assert_near(_magic_mult(w, boss), 1.15, 1e-6, "still active just before 30 s")
	_ticks(w, 1)
	assert_eq(_magic_mult(w, boss), 1.0, "over at exactly 30 s")


func test_magic_attack_up_area_buffs_mobs_in_its_box_with_its_own_x() -> void:
	var w := _world([[111, 5]])
	var boss := _boss(w)
	assert_eq(_casts(_ticks(w, 3599)).size(), 0, "no cast before the 60 s interval")
	# Ordinary mobs wander, so they are placed on the tick before the cast.
	var inside := _ordinary(w, 950)
	var outside := _ordinary(w, 1100)
	w.drain_events()
	var cast := _casts(_ticks(w, 1))
	assert_eq(cast.size(), 1, "111/5 casts at 60 s")
	if cast.is_empty():
		return
	assert_eq(int(cast[0].skill_id), 111)
	assert_true(boss in cast[0].targets and inside in cast[0].targets, "the caster and the mob 350 px away")
	assert_false(outside in cast[0].targets, "not the mob 500 px away")
	assert_eq(String(cast[0].recipient_effect), SKILL_PATH % [111, 5] + "/mob0")
	assert_near(_magic_mult(w, boss), 1.4, 1e-6, "x140 is x1.4")
	assert_near(_magic_mult(w, inside), 1.4, 1e-6)
	assert_eq(_magic_mult(w, outside), 1.0)
	_ticks(w, 1799)
	assert_near(_magic_mult(w, inside), 1.4, 1e-6, "still active just before 30 s")
	_ticks(w, 1)
	assert_eq(_magic_mult(w, inside), 1.0, "over at exactly 30 s")


func test_a_recast_replaces_the_multiplier_without_stacking() -> void:
	# A synthetic 25 s interval recasts inside the 30 s buff: casts at 25 s (end 55 s) and 50 s (end 80 s).
	var w := _world([[101, 1]], {"intervals": {"101": 25.0}})
	var boss := _boss(w)
	_ticks(w, 1500)
	assert_near(_magic_mult(w, boss), 1.15, 1e-6)
	_ticks(w, 1500)
	assert_near(_magic_mult(w, boss), 1.15, 1e-6, "x1.15 after the recast at 50 s, not x1.15 squared")
	_ticks(w, 600)
	assert_near(_magic_mult(w, boss), 1.15, 1e-6, "at 60 s, past the first end (55 s): the recast refreshed the end")


func test_every_new_skill_waits_for_its_hp_gate() -> void:
	for pair: Array in [[101, 1], [102, 3], [103, 2], [111, 5]]:
		var w := _world([pair], {"hp_gate": 50.0, "intervals": {str(pair[0]): 5.0}})
		var boss := _boss(w)
		assert_eq(_casts(_ticks(w, 600)).size(), 0, "%d: no cast at full health" % pair[0])
		_set_hp_percent(w, boss, 50.0)
		assert_eq(_casts(_ticks(w, 60)).size(), 1, "%d: casts at exactly the gate" % pair[0])


func test_magic_attack_up_still_casts_while_the_character_is_hidden() -> void:
	var w := _world([[101, 1]])
	_ticks(w, 2040)
	assert_true(w.start_buff("synthetic_hide", {"skill_id": 9991001, "level": 1, "icon": "", "duration": 5.0,
		"buff_stat": "", "buff_value": 0.0, "pulse_interval": 0.0, "hidden": true, "buff_effects": {}}))
	assert_true(w.is_hidden())
	assert_eq(_casts(_ticks(w, 60)).size(), 1, "a buff on the mob is not aimed at the character")


## Every boss attack1 hit on the player until `until` s: [[time, damage], ...], plus the buff's cast time.
func _attack_hits(x101: float, magic: bool, until := 70.0, p_seed := 457) -> Dictionary:
	var w := _world([[101, 1]], {"x101": x101, "attack": true, "magic": magic, "seed": p_seed})
	var hits: Array = []
	var cast := -1.0
	while w.time < until:
		w.step(DT, MoveInput.new())
		for e: Dictionary in w.drain_events():
			if e.type == "player_hit" and String(e.source_kind) == "attack" and not bool(e.get("miss", false)):
				hits.append([w.time, int(e.damage)])
			elif e.type == "boss_skill" and cast < 0.0:
				cast = w.time
	return {"hits": hits, "cast": cast, "world": w}


func test_magic_attack_damage_is_x_percent_only_while_buffed() -> void:
	var plain := _attack_hits(100.0, true)
	var buffed := _attack_hits(115.0, true)
	var cast := float(buffed.cast)
	assert_near(cast, float(plain.cast), 1e-6, "both worlds cast at the same tick")
	assert_eq(buffed.hits.size(), plain.hits.size())
	var c := floorf(0.75 * float(buffed.world.hit_defense().mdd))
	var during := 0
	var outside := 0
	for i in mini(buffed.hits.size(), plain.hits.size()):
		var t := float(buffed.hits[i][0])
		if t >= cast and t < cast + 30.0:
			during += 1
			var expected := 1.15 * (float(plain.hits[i][1]) + c) - c
			assert_true(absf(float(buffed.hits[i][1]) - expected) <= 1.1,
				"magic attack1 at %.2f s: %d is the same roll's %d at x1.15" % [t, buffed.hits[i][1], plain.hits[i][1]])
			assert_true(int(buffed.hits[i][1]) > int(plain.hits[i][1]) + 100, "clearly above the unbuffed hit")
		else:
			outside += 1
			assert_eq(buffed.hits[i][1], plain.hits[i][1], "magic attack1 at %.2f s is unbuffed" % t)
	assert_true(during >= 3 and outside >= 3, "hits both inside (%d) and outside (%d) the buff cast at %.2f s" % [during, outside, cast])


func test_physical_attack_damage_is_unchanged() -> void:
	var plain := _attack_hits(100.0, false)
	var buffed := _attack_hits(115.0, false)
	assert_true(plain.hits.size() >= 10, "physical attacks landed")
	assert_eq(buffed.hits, plain.hits, "Magic Attack Up raises magic attacks only")


func test_touch_damage_is_unchanged_by_magic_attack_up() -> void:
	var w := _world([[101, 1]])
	var boss := _boss(w)
	w.drain_events()
	w._player_hit(boss, w.mob_kinds[w.swarm.kind[boss]])
	var before := w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "player_hit")
	_ticks(w, 2100)
	assert_near(_magic_mult(w, boss), 1.15, 1e-6)
	assert_eq(w.mob_weapon_attack(boss, 100.0), 100.0, "weapon attack takes no magic multiplier")
	assert_near(w.mob_magic_attack(boss, 100.0), 115.0, 1e-4)
	assert_eq(before.size(), 1)


func test_same_seed_same_outcome() -> void:
	var a := _attack_hits(115.0, true, 70.0, 11)
	var b := _attack_hits(115.0, true, 70.0, 11)
	assert_eq(a.hits, b.hits)
	assert_eq(a.cast, b.cast)


# --- 102 / 103: self-only defense up --------------------------------------------------------------------------------

func test_pdd_up_is_self_only_with_the_area_arithmetic_and_exact_duration() -> void:
	var w := _world([[102, 3]])
	var boss := _boss(w)
	var near := _ordinary(w, 650)
	var base_pdd := w.mob_defense(boss, false)
	var base_mdd := w.mob_defense(boss, true)
	assert_eq(_casts(_ticks(w, 1799)).size(), 0, "no cast before the 30 s interval")
	var cast := _casts(_ticks(w, 1))
	assert_eq(cast.size(), 1, "102/3 casts at 30 s")
	if cast.is_empty():
		return
	assert_eq(int(cast[0].skill_id), 102)
	assert_near(float(cast[0].duration), 20.0, 1e-6)
	assert_eq(cast[0].targets, [boss], "102 targets the caster only")
	assert_eq(String(cast[0].effect), SKILL_PATH % [102, 3] + "/effect")
	assert_near(w.mob_defense(boss, false), base_pdd + 85.0, 1e-4, "x85 is added flat to PDD, like 112")
	assert_eq(w.mob_defense(boss, true), base_mdd, "MDD is untouched")
	assert_eq(w.mob_skills.defense_bonus(near, false, w.time), 0.0, "the mob next to it gets nothing")
	_ticks(w, 1199)
	assert_near(w.mob_skills.defense_bonus(boss, false, w.time), 85.0, 1e-4, "still active just before 20 s")
	_ticks(w, 1)
	assert_eq(w.mob_skills.defense_bonus(boss, false, w.time), 0.0, "over at exactly 20 s")


func test_mdd_up_is_self_only_with_the_area_arithmetic_and_exact_duration() -> void:
	var w := _world([[103, 2]])
	var boss := _boss(w)
	var near := _ordinary(w, 650)
	assert_eq(_casts(_ticks(w, 2399)).size(), 0, "no cast before the 40 s interval")
	var cast := _casts(_ticks(w, 1))
	assert_eq(cast.size(), 1, "103/2 casts at 40 s")
	if cast.is_empty():
		return
	assert_eq(cast[0].targets, [boss], "103 targets the caster only")
	assert_eq(w.mob_skills.defense_bonus(boss, true, w.time), 60.0, "x60 is added flat to MDD, like 113")
	assert_eq(w.mob_skills.defense_bonus(boss, false, w.time), 0.0, "PDD is untouched")
	assert_eq(w.mob_skills.defense_bonus(near, true, w.time), 0.0, "the mob next to it gets nothing")
	_ticks(w, 1799)
	assert_eq(w.mob_skills.defense_bonus(boss, true, w.time), 60.0)
	_ticks(w, 1)
	assert_eq(w.mob_skills.defense_bonus(boss, true, w.time), 0.0, "over at exactly 30 s")


func test_the_bulk_defense_pass_agrees_with_the_defense_bonus() -> void:
	var w := _world([[102, 3]])
	var boss := _boss(w)
	_ticks(w, 1800)
	w._fill_live_defense()
	assert_near(w._live_pdd[boss], float((w.mob_kinds[w.swarm.kind[boss]] as MobKind).pdd) + 85.0, 1e-3)


# --- icons ----------------------------------------------------------------------------------------------------------

func test_each_buff_shows_its_mob_icon_while_it_lasts() -> void:
	for case: Array in [[101, 1, 2100, 1800], [102, 3, 1800, 1200], [103, 2, 2400, 1800], [111, 5, 3600, 1800]]:
		var w := _world([[case[0], case[1]]])
		var boss := _boss(w)
		_ticks(w, int(case[2]) - 1)
		assert_eq(w.mob_skills.status_visuals(boss, w.time).size(), 0, "%d: no icon before the cast" % case[0])
		_ticks(w, 1)
		assert_eq(w.mob_skills.status_visuals(boss, w.time), [SKILL_PATH % [case[0], case[1]] + "/mob"] as Array[String],
			"%d: the mob icon over the caster" % case[0])
		_ticks(w, int(case[3]) - 1)
		assert_eq(w.mob_skills.status_visuals(boss, w.time).size(), 1, "%d: icon up to the last tick" % case[0])
		_ticks(w, 1)
		assert_eq(w.mob_skills.status_visuals(boss, w.time).size(), 0, "%d: icon gone with the buff" % case[0])


# --- 141: magic immunity --------------------------------------------------------------------------------------------

func test_magic_immunity_waits_for_its_gate_and_casts_on_its_interval() -> void:
	var w := _world([[141, 3]])
	var boss := _boss(w)
	assert_eq(_casts(_ticks(w, 1850)).size(), 0, "hp 100% is above the hp<=50 gate: no cast at 30 s")
	assert_true(w.magic_hit_allowed(boss))
	_set_hp_percent(w, boss, 50.0)
	var cast := _casts(_ticks(w, 1))
	assert_eq(cast.size(), 1, "casts the moment the gate opens, the interval being up")
	if cast.is_empty():
		return
	assert_eq(int(cast[0].skill_id), 141)
	assert_eq(int(cast[0].level), 3)
	assert_eq(cast[0].targets, [boss])
	assert_near(float(cast[0].duration), 10.0, 1e-6)
	assert_false(w.magic_hit_allowed(boss))
	assert_eq(String(w.mob_skills.immunity_state(boss, w.time).visual), SKILL_PATH % [141, 3] + "/mob")
	assert_eq(_casts(_ticks(w, 1799)).size(), 0, "the next cast is a full 30 s later")
	assert_eq(_casts(_ticks(w, 1)).size(), 1)


func test_magic_immunity_lasts_exactly_its_time_in_ticks() -> void:
	var w := _world([[141, 3]])
	var boss := _boss(w)
	_set_hp_percent(w, boss, 40.0)
	_ticks(w, 1800)
	assert_false(w.magic_hit_allowed(boss))
	_ticks(w, 599)
	assert_false(w.magic_hit_allowed(boss), "still immune just before 10 s")
	assert_eq(w.mob_skills.status_visuals(boss, w.time).size(), 1)
	_ticks(w, 1)
	assert_true(w.magic_hit_allowed(boss), "over at exactly 10 s")
	assert_true(w.mob_skills.immunity_state(boss, w.time).is_empty())


func test_magic_immunity_blocks_instant_magic_damage_and_lets_physical_land() -> void:
	var w := _world([[141, 3]])
	var boss := _boss(w)
	_set_hp_percent(w, boss, 40.0)
	_ticks(w, 1800)
	assert_false(w.magic_hit_allowed(boss))
	var hp := w.swarm.hp[boss]
	_magic_hit(w, boss, 500.0)
	assert_eq(w.swarm.hp[boss], hp, "zero damage from a magic skill")
	_physical_hit(w, boss, 40.0)
	assert_eq(w.swarm.hp[boss], hp - 40, "physical still lands")
	_ticks(w, 600)
	var after := w.swarm.hp[boss]
	_magic_hit(w, boss, 40.0)
	assert_true(w.swarm.hp[boss] < after, "magic lands again after the immunity")


func test_magic_immunity_consumes_a_magic_shell_without_damage_and_physical_shells_land() -> void:
	var w := _world([[141, 3]])
	var boss := _boss(w)
	_set_hp_percent(w, boss, 40.0)
	_ticks(w, 1800)
	var hp := w.swarm.hp[boss]
	var mk: MobKind = w.mob_kinds[w.swarm.kind[boss]]
	var box := mk.hitbox_at(w.swarm.x[boss], w.swarm.y[boss], w.swarm.facing[boss])
	for magic: bool in [true, false]:
		w.projectiles.spawn({"x": box.position.x - 100.0, "y": box.get_center().y, "vx": 100.0, "vy": 0.0,
			"range": 1000, "radius": 0, "dmg_min": 40, "dmg_max": 40, "magic": magic, "skill": "energy_bolt"})
		_ticks(w, 90)
		assert_eq(w.projectiles.active_count(), 0, "the shell is consumed by contact (magic %s)" % magic)
		if magic:
			assert_eq(w.swarm.hp[boss], hp, "the magic shell did nothing")
	assert_true(w.swarm.hp[boss] < hp, "the physical shell damaged the boss")
	assert_false(w.magic_hit_allowed(boss), "still immune after the shells")
	w._fill_live_defense()
	assert_eq(w._live_magic_allowed[boss], 0, "the bulk pass agrees")


func test_magic_immunity_follows_relocation_and_never_reaches_a_reused_slot() -> void:
	var w := _world([[141, 3]])
	var boss := _boss(w)
	_set_hp_percent(w, boss, 40.0)
	_ticks(w, 1800)
	var moved := w.relocate_mob(boss, Vector2(900, 200), w.fhm.find_below(900, 190))
	assert_false(w.magic_hit_allowed(moved), "the live status follows a relocated boss")
	w.swarm.despawn(moved)
	var fresh := _ordinary(w, 1100)
	assert_eq(fresh, moved, "fixture reuses the slot")
	assert_true(w.magic_hit_allowed(fresh), "a new occupant has no inherited immunity")
	assert_eq(w.mob_skills.status_visuals(fresh, w.time).size(), 0)


# --- 140 / 141 exclusivity ------------------------------------------------------------------------------------------

func test_141_is_skipped_while_140_is_active_and_spends_its_interval() -> void:
	var w := _world([[140, 12], [141, 3]])
	var boss := _boss(w)
	_set_hp_percent(w, boss, 40.0)
	var first := _casts(_ticks(w, 1800))
	assert_eq(first.size(), 1, "one cast at 30 s")
	assert_eq(int(first[0].skill_id), 140, "140 is listed first and casts")
	assert_false(w.physical_hit_allowed(boss))
	assert_true(w.magic_hit_allowed(boss), "never invulnerable to everything")
	assert_eq(_casts(_ticks(w, 1)).size(), 0, "141 is ready the same tick but skipped under 140")
	assert_true(w.magic_hit_allowed(boss), "no magic immunity was started")
	_ticks(w, 598)
	assert_true(w.magic_hit_allowed(boss))
	_ticks(w, 1)
	assert_true(w.physical_hit_allowed(boss), "140 over at 10 s")
	assert_eq(_casts(_ticks(w, 1199)).size(), 0, "141 spent its interval at 30.02 s: not ready again before 60 s")
	assert_true(w.magic_hit_allowed(boss))
	assert_true(w.physical_hit_allowed(boss))
	var second := _casts(_ticks(w, 1))
	assert_eq(second.size(), 1, "the tick at 60 s casts again")
	assert_eq(int(second[0].skill_id), 140, "140 ready again at 60 s; it comes first")


func test_140_is_skipped_while_141_is_active_and_spends_its_interval() -> void:
	var w := _world([[141, 3], [140, 12]])
	var boss := _boss(w)
	_set_hp_percent(w, boss, 40.0)
	var first := _casts(_ticks(w, 1800))
	assert_eq(first.size(), 1)
	assert_eq(int(first[0].skill_id), 141, "141 is listed first and casts")
	assert_false(w.magic_hit_allowed(boss))
	assert_true(w.physical_hit_allowed(boss))
	assert_eq(_casts(_ticks(w, 1)).size(), 0, "140 is ready the same tick but skipped under 141")
	assert_true(w.physical_hit_allowed(boss), "no weapon immunity was started")
	_ticks(w, 599)
	assert_true(w.magic_hit_allowed(boss), "141 over at 10 s")
	assert_eq(_casts(_ticks(w, 1199)).size(), 0, "140 spent its interval: not ready again until 60 s")
	assert_true(w.physical_hit_allowed(boss))
	assert_true(w.magic_hit_allowed(boss))


func test_immunity_icon_is_the_active_immunity_only() -> void:
	var w := _world([[140, 12], [141, 3]])
	var boss := _boss(w)
	_set_hp_percent(w, boss, 40.0)
	_ticks(w, 1801)
	assert_eq(w.mob_skills.status_visuals(boss, w.time), [SKILL_PATH % [140, 12] + "/mob"] as Array[String])
