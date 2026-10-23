extends TestCase
## Mob Attack Up (MobSkill 100 self, 110 area; ticket #255 of spec #253, docs/GAME_DESIGN.md "Constants and provenance"):
## a timed balance.mob_skills.attack_up_mult on the weapon attack of the buffed mobs' touch and physical attackN damage.
## Seeded RunWorld, fixed ticks, a synthetic boss and MobSkill.img levels with the v83 100/1 and 110/2 values
## (x115, time 30, interval 40 / 35, mpCon 5, the 110/2 box lt(-300,-200) rb(300,200)).

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const BOSS := 2220000
## A large synthetic weapon attack, so the ×1.15 difference stands well clear of rounding.
const PAD := 1000.0
const SKILL_PATH := "Skill.wz/MobSkill.img/%d/level/%d"


func _anim(frames: int, delay: float) -> Dictionary:
	var out := {}
	for i in frames:
		out[str(i)] = {"delay": delay}
	return out


## v83-shaped MobSkill.img levels 100/1 and 110/2; `intervals` ({"<id>": s}) lets the refresh test recast inside the buff.
func _skill_img(intervals := {}) -> Dictionary:
	return {
		"100": {"level": {"1": {"x": 115.0, "mpCon": 5.0, "interval": float(intervals.get("100", 40.0)), "time": 30.0,
			"effect": _anim(6, 100.0), "mob": _anim(1, 100.0)}}},
		"110": {"level": {"2": {"x": 115.0, "mpCon": 5.0, "interval": float(intervals.get("110", 35.0)), "time": 30.0,
			"lt": {"$v": [-300.0, -200.0]}, "rb": {"$v": [300.0, 200.0]},
			"mob": _anim(1, 100.0), "mob0": _anim(6, 100.0)}}},
	}


## A quiet seeded world whose one scheduled boss (standing still at x = 600) lists `skills` ([[id, level], ...]).
## `mult` is balance.mob_skills.attack_up_mult; `attack` gives the boss a huge-box type-0 attack1 every 4 s (magic when
## `magic`). The player has 1,000,000 HP, stands at x = 400 and is not in god mode.
func _world(skills: Array, mult := 1.15, attack := false, magic := false, intervals := {},
		p_seed := 255) -> RunWorld:
	var data := RF.quiet_data()
	data.balance.player.skills = []
	data.balance.player.hp = 1000000
	data.balance.regen.hp = 0
	data.balance.bosses.teleport_stall = 10000.0
	data.balance.mob_motion.push_px = 0
	data.balance.magnet_radius = 0
	data.balance.mob_skills.enabled_ids = [BOSS]
	data.balance.mob_skills.attack_up_mult = mult
	var entry := {"time": 0.0, "mob_id": BOSS}
	if attack:
		entry.attacks = ["attack1"]
		entry.attack_interval = 4.0
	RF.set_bosses(data.stages.stages.quiet, [entry])
	var setup := RF.setup("quiet", p_seed, data)
	var img: Dictionary = setup.mob_imgs[100100].duplicate(true)
	img.info = {"boss": 1.0, "level": 20.0, "maxHP": 2000.0, "PADamage": PAD, "MADamage": PAD, "PDDamage": 20.0,
		"MDDamage": 30.0, "speed": -100.0, "skill": {}}
	img.skill1 = _anim(2, 750.0)
	if attack:
		img.attack1 = _anim(3, 300.0)
		img.attack1.info = {"type": 0.0, "attackAfter": 300.0, "effectAfter": 0.0,
			"range": {"lt": {"$v": [-3000.0, -600.0]}, "rb": {"$v": [3000.0, 100.0]}}}
		if magic:
			img.attack1.info.magic = 1.0
			img.attack1.info.MADamage = PAD
		else:
			img.attack1.info.PADamage = PAD
	for pair: Array in skills:
		img.info.skill[str(img.info.skill.size())] = {"skill": float(pair[0]), "level": float(pair[1]),
			"action": 1.0, "effectAfter": 0.0}
	setup.mob_imgs[BOSS] = img
	setup.mob_skill_img = _skill_img(intervals)
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


func _mult(w: RunWorld, slot: int) -> float:
	return w.mob_skills.attack_multiplier(slot, w.time)


## Whole damage after the canonical defense subtraction: with the same seeded roll, a ×1.15 weapon attack gives
## 1.15 × (unbuffed + c) − c (c = floor(0.75 × player PDD)), within the two roundings.
func _assert_times_115(buffed: int, plain: int, w: RunWorld, what: String) -> void:
	var c := floorf(0.75 * float(w.hit_defense().pdd))
	assert_true(absf(float(buffed) - (1.15 * (float(plain) + c) - c)) <= 1.1,
		"%s: %d is the same roll's %d at ×1.15 (c %d)" % [what, buffed, plain, int(c)])
	assert_true(buffed > plain + 100, "%s: clearly above the unbuffed hit" % what)


# --- data -----------------------------------------------------------------------------------------------------------

func test_the_runner_supports_both_attack_up_skills() -> void:
	assert_true(MobSkillRunner.SKILL_ATTACK_UP in MobSkillRunner.SUPPORTED)
	assert_true(MobSkillRunner.SKILL_ATTACK_UP_AREA in MobSkillRunner.SUPPORTED)
	assert_eq(MobSkillRunner.SKILL_ATTACK_UP, 100)
	assert_eq(MobSkillRunner.SKILL_ATTACK_UP_AREA, 110)


func test_the_shipped_multiplier_is_1_15_and_matches_the_code_default() -> void:
	var balance: Dictionary = DataRepo.load_all().balance
	assert_eq(float(balance.mob_skills.attack_up_mult), 1.15)
	assert_eq(float(balance.mob_skills.attack_up_mult), MobSkillRunner.DEFAULT_ATTACK_UP_MULT)
	var bare := MobSkillRunner.new({}, {"enabled_ids": []})
	bare.resize(4)
	assert_eq(bare.attack_multiplier(0, 0.0), 1.0, "no buff, no change")


# --- casting --------------------------------------------------------------------------------------------------------

func test_attack_up_casts_on_its_wz_interval_and_buffs_only_the_caster() -> void:
	var w := _world([[100, 1]])
	var boss := _boss(w)
	var near := _ordinary(w, 650)
	w.drain_events()
	assert_eq(_casts(_ticks(w, 2399)).size(), 0, "no cast before the 40 s interval")
	assert_eq(_mult(w, boss), 1.0)
	var cast := _casts(_ticks(w, 1))
	assert_eq(cast.size(), 1, "Attack Up casts at 40 s")
	if cast.is_empty():
		return
	assert_eq(int(cast[0].skill_id), 100)
	assert_eq(int(cast[0].level), 1)
	assert_eq(String(cast[0].action), "skill1")
	assert_near(float(cast[0].duration), 30.0, 1e-6)
	assert_eq(cast[0].targets, [boss], "100 targets the caster only")
	assert_eq(String(cast[0].effect), SKILL_PATH % [100, 1] + "/effect", "the v83 100/1 effect art plays")
	assert_near(_mult(w, boss), 1.15, 1e-6, "the caster is buffed")
	assert_eq(_mult(w, near), 1.0, "a mob next to it is not")
	assert_eq(_casts(_ticks(w, 2399)).size(), 0, "no recast before another 40 s")
	assert_eq(_casts(_ticks(w, 1)).size(), 1, "the second cast at 80 s")


func test_area_attack_up_buffs_live_mobs_inside_its_box_and_not_outside() -> void:
	var w := _world([[110, 2]])
	var boss := _boss(w)
	var inside := _ordinary(w, 850)
	var outside := _ordinary(w, 950)
	w.drain_events()
	assert_eq(_casts(_ticks(w, 2099)).size(), 0, "no cast before the 35 s interval")
	var cast := _casts(_ticks(w, 1))
	assert_eq(cast.size(), 1, "110/2 casts at 35 s")
	if cast.is_empty():
		return
	assert_eq(int(cast[0].skill_id), 110)
	assert_eq(int(cast[0].level), 2)
	assert_true(boss in cast[0].targets and inside in cast[0].targets, "caster and the mob 250 px away")
	assert_false(outside in cast[0].targets, "not the mob 350 px away")
	assert_eq(String(cast[0].recipient_effect), SKILL_PATH % [110, 2] + "/mob0", "recipients play the v83 mob0 art")
	assert_near(_mult(w, boss), 1.15, 1e-6)
	assert_near(_mult(w, inside), 1.15, 1e-6)
	assert_eq(_mult(w, outside), 1.0)


func test_the_buff_lasts_exactly_its_time_then_ends() -> void:
	var w := _world([[110, 2]])
	var inside := _ordinary(w, 850)
	_ticks(w, 2100)
	assert_near(_mult(w, inside), 1.15, 1e-6)
	_ticks(w, 1799)
	assert_near(_mult(w, inside), 1.15, 1e-6, "still active just before 30 s")
	_ticks(w, 1)
	assert_eq(_mult(w, inside), 1.0, "over at exactly 30 s")


func test_a_recast_refreshes_the_timer_without_stacking() -> void:
	# A synthetic 20 s interval recasts inside the 30 s buff; the recipient leaves the box after the second cast so
	# the third (60 s) cannot reach it.
	var w := _world([[110, 2]], 1.15, false, false, {"110": 20.0})
	var inside := _ordinary(w, 850)
	assert_eq(_casts(_ticks(w, 1200)).size(), 1, "first cast at 20 s, buff until 50 s")
	assert_eq(_casts(_ticks(w, 1200)).size(), 1, "recast at 40 s, inside the buff")
	assert_near(_mult(w, inside), 1.15, 1e-6, "×1.15, not ×1.15²")
	inside = w.relocate_mob(inside, Vector2(1800, 200), w.fhm.find_below(1800, 190))
	_ticks(w, 1500)
	assert_near(_mult(w, inside), 1.15, 1e-6, "the recast moved the end from 50 s to 70 s")
	_ticks(w, 299)
	assert_near(_mult(w, inside), 1.15, 1e-6)
	_ticks(w, 1)
	assert_eq(_mult(w, inside), 1.0, "over 30 s after the recast")


func test_attack_up_still_casts_while_the_character_is_hidden() -> void:
	var w := _world([[100, 1]])
	_ticks(w, 2340)
	assert_true(w.start_buff("synthetic_hide", {"skill_id": 9991001, "level": 1, "icon": "", "duration": 5.0,
		"buff_stat": "", "buff_value": 0.0, "pulse_interval": 0.0, "hidden": true, "buff_effects": {}}))
	assert_true(w.is_hidden())
	assert_eq(_casts(_ticks(w, 60)).size(), 1, "a buff on the mob is not aimed at the character (like 112/113)")
	assert_true(w.is_hidden())
	assert_near(_mult(w, _boss(w)), 1.15, 1e-6)


# --- damage ---------------------------------------------------------------------------------------------------------

## Touch damage of the boss at the given run times, in a world with attack_up_mult `mult`.
func _touch_damage(mult: float, times: Array) -> Array:
	var w := _world([[100, 1]], mult)
	var boss := _boss(w)
	var out: Array = []
	for t: float in times:
		while w.time < t - 1e-6:
			w.step(DT, MoveInput.new())
		w.drain_events()
		w._player_hit(boss, w.mob_kinds[w.swarm.kind[boss]])
		var hits := w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "player_hit")
		assert_eq(hits.size(), 1, "one touch at %.1f s" % t)
		out.append(int(hits[0].damage) if not hits.is_empty() else -1)
	return out


func test_touch_damage_is_115_percent_only_while_buffed() -> void:
	# Touches at least 5 s apart, well clear of the hit window.
	var times := [30.0, 45.0, 69.5, 75.0, 80.0]
	var plain := _touch_damage(1.0, times)
	var buffed := _touch_damage(1.15, times)
	var w := _world([[100, 1]])
	assert_eq(buffed[0], plain[0], "before the cast: the same seeded hit")
	_assert_times_115(buffed[1], plain[1], w, "touch at 45 s")
	_assert_times_115(buffed[2], plain[2], w, "touch at 69.5 s")
	assert_eq(buffed[3], plain[3], "after the 30 s buff: back to normal")
	assert_eq(buffed[4], plain[4])


## Every boss attack1 hit on the player until `until` s: [[time, damage], ...], plus the Attack Up cast time.
func _attack_hits(mult: float, magic: bool, until := 80.0) -> Dictionary:
	var w := _world([[100, 1]], mult, true, magic)
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


func test_physical_attack_damage_is_115_percent_only_while_buffed() -> void:
	var plain := _attack_hits(1.0, false)
	var buffed := _attack_hits(1.15, false)
	var cast := float(buffed.cast)
	assert_near(cast, float(plain.cast), 1e-6, "both worlds cast at the same tick")
	assert_eq(buffed.hits.size(), plain.hits.size())
	var during := 0
	var outside := 0
	for i in mini(buffed.hits.size(), plain.hits.size()):
		var t := float(buffed.hits[i][0])
		if t >= cast and t < cast + 30.0:
			during += 1
			_assert_times_115(int(buffed.hits[i][1]), int(plain.hits[i][1]), buffed.world, "attack1 at %.2f s" % t)
		else:
			outside += 1
			assert_eq(buffed.hits[i][1], plain.hits[i][1], "attack1 at %.2f s is unbuffed" % t)
	assert_true(during >= 3 and outside >= 3, "hits both inside (%d) and outside (%d) the buff cast at %.2f s" % [during, outside, cast])


func test_magic_attack_damage_is_unchanged() -> void:
	var plain := _attack_hits(1.0, true, 60.0)
	var buffed := _attack_hits(1.15, true, 60.0)
	assert_true(plain.hits.size() >= 10, "magic attacks landed")
	assert_eq(buffed.hits, plain.hits, "Attack Up (100/110) raises weapon attack only")


# --- slot lifecycle -------------------------------------------------------------------------------------------------

func test_the_buff_moves_with_relocation_and_never_reaches_a_reused_slot() -> void:
	var w := _world([[110, 2]])
	var inside := _ordinary(w, 850)
	_ticks(w, 2100)
	assert_near(_mult(w, inside), 1.15, 1e-6)
	var moved := w.relocate_mob(inside, Vector2(1500, 200), w.fhm.find_below(1500, 190))
	assert_near(_mult(w, moved), 1.15, 1e-6, "the live buff follows the relocation")
	w.swarm.despawn(moved)
	var fresh := _ordinary(w, 1700)
	assert_eq(fresh, moved, "fixture reuses the buffed slot")
	assert_eq(_mult(w, fresh), 1.0, "a new occupant starts unbuffed")


func test_moving_a_slot_carries_the_buff_and_leaves_the_old_slot_clean() -> void:
	# RunWorld.relocate_mob hands the runner (from, to); the swarm's free list usually gives the same slot back, so the
	# move to a different slot is driven through the runner's own hook.
	var w := _world([[110, 2]])
	var inside := _ordinary(w, 850)
	var spare := _ordinary(w, 1500)
	_ticks(w, 2100)
	assert_near(_mult(w, inside), 1.15, 1e-6)
	assert_eq(_mult(w, spare), 1.0)
	w.mob_skills.move_slot(inside, spare)
	assert_near(_mult(w, spare), 1.15, 1e-6, "the buff moved with its mob")
	assert_eq(_mult(w, inside), 1.0, "the former slot keeps no stale buff")
	_ticks(w, 1799)
	assert_near(_mult(w, spare), 1.15, 1e-6, "the moved buff keeps its end time")
	_ticks(w, 1)
	assert_eq(_mult(w, spare), 1.0)
