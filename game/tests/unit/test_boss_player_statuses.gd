extends TestCase
## Boss player statuses Darkness 121, Weakness 122, Curse 124, Seduce 128 and Confuse 132 (#458) through seeded synthetic
## RunWorld ticks, independent of the asset cache. The level specs are the v83 MobSkill.img shapes of docs/research/v83-mob-skills-ii.md.
const MF := preload("res://tests/fixtures/mano_fixtures.gd")
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const CF := preload("res://tests/fixtures/combat_mechanics_fixtures.gd")
const DT := 1.0 / 60.0
const AFFECTED := {"0": {"delay": 70.0}}
const BOX_120 := {"lt": {"$v": [-300.0, -120.0]}, "rb": {"$v": [300.0, 120.0]}}

## id -> [level, spec]: tier A, Alishar 121/1, Fox 122/10, Thanatos 124/1, Lyka 128/7, Leviathan 132/2 (its `inteval` key).
const SPECS := {
	121: [1, {"interval": 10.0, "time": 30.0, "prop": 50.0, "lt": {"$v": [-300.0, -120.0]}, "rb": {"$v": [300.0, 120.0]}}],
	122: [10, {"interval": 30.0, "time": 10.0, "prop": 80.0, "lt": {"$v": [-200.0, -120.0]}, "rb": {"$v": [200.0, 30.0]}}],
	124: [1, {"interval": 10.0, "time": 60.0, "prop": 50.0, "lt": {"$v": [-300.0, -120.0]}, "rb": {"$v": [300.0, 120.0]}}],
	128: [7, {"interval": 20.0, "time": 10.0, "prop": 80.0, "x": 6.0, "lt": {"$v": [-310.0, -400.0]}, "rb": {"$v": [500.0, 300.0]}}],
	132: [2, {"inteval": 60.0, "time": 15.0, "prop": 100.0, "x": 1.0, "lt": {"$v": [-300.0, -120.0]}, "rb": {"$v": [300.0, 120.0]}}],
}
const KEYS := {121: "darkness", 122: "weakness", 124: "curse", 128: "seduce", 132: "confuse"}


## A world whose boss casts only status `id`, with `patch` merged over the v83 level (prop 100 unless patched).
func _world(id: int, patch := {}, seed_value := 22, rules := {}, skills: Array = []) -> RunWorld:
	var setup := MF.setup([126], seed_value)
	var list := {}
	var tables := {}
	for sid: int in (skills if not skills.is_empty() else [id]):
		var level: int = SPECS[sid][0]
		var spec: Dictionary = (SPECS[sid][1] as Dictionary).duplicate(true)
		spec.merge({"prop": 100.0, "affected": AFFECTED}, true)
		if sid == id:
			spec.merge(patch, true)
		list[str(list.size())] = {"skill": float(sid), "level": float(level), "action": 1.0, "effectAfter": 0.0}
		tables[str(sid)] = {"level": {str(level): spec}}
	setup.mob_imgs[2220000].info.skill = list
	setup.mob_skill_img = tables
	setup.mob_imgs[2220000].skill1 = {"0": {"delay": 10.0}}
	setup.data.balance.mob_skills.merge(rules, true)
	var w := RunWorld.new(setup)
	w.god = true
	RF.place_player(w, 450)
	w.step(DT, MoveInput.new())
	var slot := int(w.bosses.records[0].slot)
	w.relocate_mob(slot, Vector2(600, 200), w.fhm.find_below(600, 190))
	w.drain_events()
	return w


func _ticks(w: RunWorld, n: int, input: MoveInput = null) -> void:
	for tick in n:
		w.step(DT, input if input != null else MoveInput.new())


func _on(w: RunWorld, id: int) -> bool:
	return not w.player_state.get(KEYS[id], {}).is_empty()


func _interval(id: int) -> int:
	var spec: Dictionary = SPECS[id][1]
	return roundi(float(spec.get("interval", spec.get("inteval", 0.0))) * 60.0)


func _time(id: int) -> int:
	return roundi(float(SPECS[id][1].time) * 60.0)


func _casts(events: Array, id: int) -> int:
	return events.filter(func(e: Dictionary) -> bool: return e.type == "boss_skill" and int(e.skill_id) == id).size()


## Each status starts at its interval and lasts exactly its `time` in ticks (Seduce is capped, below).
func test_interval_and_exact_duration_of_each_status() -> void:
	for id: int in [121, 122, 124, 132]:
		var w := _world(id)
		_ticks(w, _interval(id) - 1)
		assert_false(_on(w, id), "%d: not before its interval" % id)
		_ticks(w, 1)
		assert_true(_on(w, id), "%d: active on the interval tick" % id)
		assert_eq(w.player_state[KEYS[id]].skill_id, id)
		assert_eq(w.player_state[KEYS[id]].visual, "Skill.wz/MobSkill.img/%d/level/%d/affected" % [id, SPECS[id][0]])
		w.swarm.despawn(int(w.bosses.records[0].slot))
		_ticks(w, _time(id) - 1)
		assert_true(_on(w, id), "%d: still active one tick before expiry" % id)
		_ticks(w, 1)
		assert_false(_on(w, id), "%d: gone exactly after %d ticks" % [id, _time(id)])


## Confuse 132 level 2 spells its interval `inteval`: the cast is at 60 s, not at 0 or never.
func test_the_inteval_spelling_of_132_is_read() -> void:
	assert_eq(MobSkillRunner.interval_of({"inteval": 60.0}), 60.0)
	assert_eq(MobSkillRunner.interval_of({"interval": 15.0, "inteval": 60.0}), 15.0, "the right spelling wins")
	assert_eq(MobSkillRunner.interval_of({}), 0.0)
	var w := _world(132)
	_ticks(w, 3599)
	assert_false(_on(w, 132))
	_ticks(w, 1)
	assert_true(_on(w, 132), "the first cast comes one `inteval` (60 s) after the boss arrives")


## The box (mirrored by the boss's facing) decides who is hit; outside it nothing happens and the interval is still spent.
func test_area_decides_and_a_miss_still_spends_the_interval() -> void:
	for id: int in [121, 122, 124, 132]:
		var box: Dictionary = SPECS[id][1]
		var lt: Array = box.lt["$v"]
		var rb: Array = box.rb["$v"]
		for offset in [Vector2(lt[0] - 2.0, 0), Vector2(rb[0] + 2.0, 0), Vector2(0, lt[1] - 2.0), Vector2(0, rb[1] + 2.0)]:
			var w := _world(id)
			_ticks(w, _interval(id) - 1)
			w.player.place(Vector2(600, 200) + offset, w.fhm)
			_ticks(w, 1)
			assert_false(_on(w, id), "%d outside the box at %s" % [id, offset])
		var inside := _world(id)
		_ticks(inside, _interval(id) - 1)
		inside.player.place(Vector2(600, 200) + Vector2(0, (float(lt[1]) + float(rb[1])) * 0.5 - 1.0), inside.fhm)
		_ticks(inside, 1)
		assert_true(_on(inside, id), "%d control: inside the box" % id)
	var missed := _world(121)
	_ticks(missed, 599)
	missed.player.place(Vector2(600, 200) + Vector2(400, 0), missed.fhm)
	_ticks(missed, 1)
	missed.player.place(Vector2(600, 200), missed.fhm)
	_ticks(missed, 599)
	assert_false(_on(missed, 121), "a cast that missed spent its interval; the next is 10 s later")
	_ticks(missed, 1)
	assert_true(_on(missed, 121))


## A 0% or 50% roll draws on stream 19 only, repeats for a seed and a failed roll still spends the interval.
func test_prop_rolls_use_stream_19_and_repeat_for_a_seed() -> void:
	var zero := _world(121, {"prop": 0.0})
	_ticks(zero, 600 * 3)
	assert_false(_on(zero, 121), "0% never applies")
	var runs: Array = []
	for run in 2:
		var w := _world(121, {"prop": 50.0, "time": 1.0})
		var combat := w.rng.state
		var ground := w.ground_rng.state
		var results: Array = []
		for cast in 30:
			_ticks(w, 600)
			results.append(_on(w, 121))
		assert_eq(w.rng.state, combat, "stream 1 untouched")
		assert_eq(w.ground_rng.state, ground, "stream 18 untouched")
		assert_true(true in results and false in results, "a 50% roll succeeds and fails")
		runs.append(results)
	assert_eq(runs[0], runs[1], "same seed, same outcomes")


## Hidden characters are never targeted, and the boss does not even cast.
func test_hidden_skips_every_status() -> void:
	for id: int in [121, 122, 124, 128, 132]:
		var w := _world(id, {"lt": {"$v": [-400.0, -400.0]}, "rb": {"$v": [400.0, 400.0]}})
		w.start_buff("synthetic_hide", {"skill_id": 9991001, "level": 1, "icon": "", "duration": 400.0,
			"buff_stat": "", "buff_value": 0.0, "pulse_interval": 0.0, "hidden": true, "buff_effects": {}})
		_ticks(w, _interval(id) * 3 + 60)
		assert_false(_on(w, id), "%d: Hidden skips it" % id)
		assert_eq(_casts(w.drain_events(), id), 0, "%d: and the boss does not cast it" % id)


## A status never stacks with itself: a recast while it lasts, or inside its lockout, neither refreshes nor extends it.
func test_no_stacking_and_the_lockout_floor() -> void:
	var w := _world(122, {"interval": 1.0, "time": 3.0})
	var windows: Array = []
	var was := false
	for tick in 20 * 60:
		w.step(DT, MoveInput.new())
		var now := _on(w, 122)
		if now != was:
			windows.append(snappedf(w.time, 0.05))
			was = now
	# weakened 1 s .. 4 s, immune 4 s .. 8 s (max(4, 3)), again 8 s .. 11 s, immune .. 15 s, again 15 s .. 18 s
	assert_eq(windows, [1.0, 4.0, 8.0, 11.0, 15.0, 18.0])
	var long := _world(121, {"interval": 5.0, "time": 30.0})
	_ticks(long, 30 * 60 + 5)
	assert_true(float(long.player_state.darkness.remaining) < 5.0, "the cast at 5 s was not refreshed by later ones")
	_ticks(long, 5 * 60)
	assert_false(_on(long, 121), "it is over at 35 s")
	_ticks(long, 29 * 60)
	assert_false(_on(long, 121), "and its 30 s lockout refuses every cast until 65 s")
	_ticks(long, 70)
	assert_true(_on(long, 121), "then it applies again")


## Statuses are independent: different ones are active together, with no cap.
func test_different_statuses_stack_without_a_cap() -> void:
	var wide := {"lt": {"$v": [-400.0, -400.0]}, "rb": {"$v": [400.0, 400.0]}, "interval": 1.0, "time": 20.0}
	var w := _world(121, wide, 22, {}, [121, 122, 124, 132])
	# Each boss cast spends only its own skill's interval but the boss casts one skill per tick; give them all room.
	_ticks(w, 60 * 12)
	var active := 0
	for id: int in [121, 122, 124, 132]:
		w.mob_skills.statuses.apply(id, w.time, 20.0, {"visual": ""}, false)
		active += 1 if w.mob_skills.statuses.is_active(id, w.time) else 0
	assert_eq(active, 4)
	w.step(DT, MoveInput.new())
	for id: int in [121, 122, 124, 132]:
		assert_true(_on(w, id), "%d active alongside the others" % id)
	w.mob_skills.statuses.clear(121)
	w.step(DT, MoveInput.new())
	assert_false(_on(w, 121))
	assert_true(_on(w, 122) and _on(w, 124) and _on(w, 132), "ending one leaves the rest")


## Darkness: no critical hits while it lasts, instant and projectile hits alike; crits return after it.
func test_darkness_stops_crits() -> void:
	var w := _world(121)
	var m := RF.put_mob(w, 100100, 300.0, 190, 100000)
	w.mob_kinds[w.swarm.kind[m]].move_speed = 0.0
	w.step(DT, MoveInput.new())
	w.drain_events()
	var st := {"skill": "t", "damage_type": "physical", "damage_min": 5, "damage_max": 5, "crit": 1.0, "crit_mult": 2.0}
	w.hit_mob(m, st, -1)
	assert_true(_crits(w.drain_events())[0], "control: a certain crit crits")
	_ticks(w, 600)
	assert_true(w.mob_skills.is_darkened(w.time))
	assert_true(w.projectiles.crit_suppressed, "projectile hits read the same flag")
	w.hit_mob(m, st, -1)
	assert_false(_crits(w.drain_events())[0], "no crit under Darkness")
	_ticks(w, 1800)
	assert_false(w.mob_skills.is_darkened(w.time))
	assert_false(w.projectiles.crit_suppressed)
	w.hit_mob(m, st, -1)
	assert_true(_crits(w.drain_events())[0], "crits return when it ends")


func _crits(events: Array) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return e.type == "mob_hit").map(
		func(e: Dictionary) -> bool: return bool(e.crit))


## A projectile (the path of arrows and bolts) rolls its certain crit only without Darkness.
func test_darkness_stops_projectile_crits() -> void:
	var crits: Array = []
	for dark in [false, true]:
		var w := _world(121)
		if dark:
			w.mob_skills.statuses.apply(MobSkillRunner.SKILL_DARKNESS, w.time, 30.0, {"visual": ""})
			w.step(DT, MoveInput.new())
		var m := RF.put_mob(w, 100100, 300.0, 190, 100000)
		w.mob_kinds[w.swarm.kind[m]].move_speed = 0.0
		w.step(DT, MoveInput.new())
		var kind: MobKind = w.mob_kinds[w.swarm.kind[m]]
		var body := kind.hitbox_at(w.swarm.x[m], w.swarm.y[m], w.swarm.facing[m])
		w.drain_events()
		w.projectiles.spawn({"x": body.get_center().x - 30.0, "y": body.get_center().y, "vx": 400.0, "vy": 0.0,
			"range": 1000.0, "radius": 10.0, "dmg_min": 5.0, "dmg_max": 5.0, "crit": 1.0, "crit_mult": 2.0,
			"magic": false, "skill": "arrow"})
		var hit: Array = []
		for tick in 30:
			w.step(DT, MoveInput.new())
			hit.append_array(_crits(w.drain_events()))
		assert_false(hit.is_empty(), "the shot hit (darkness %s)" % dark)
		crits.append(hit[0])
	assert_true(crits[0], "control: a certain crit crits without Darkness")
	assert_false(crits[1], "no crit under Darkness")


## Weakness: no jump (no event, no lift), walking speed unchanged, and jumping works again once it ends.
func test_weakness_removes_the_jump_and_keeps_walking_speed() -> void:
	var free := _world(122)
	var weak := _world(122)
	_ticks(weak, _interval(122))
	assert_true(_on(weak, 122))
	assert_eq(weak.player.jump_stat, 0, "the jump stat hook")
	weak.drain_events()
	var floor_y := weak.player.pos.y
	_ticks(weak, 20, MoveInput.make(false, false, false, false, true, true))
	assert_eq(weak.player.pos.y, floor_y, "no lift")
	assert_true(weak.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "player_jump").is_empty())
	var walk := MoveInput.make(false, true)
	var weak_x := weak.player.pos.x
	_ticks(weak, 30, walk)
	var free_x := free.player.pos.x
	_ticks(free, 30, walk)
	assert_near(weak.player.pos.x - weak_x, free.player.pos.x - free_x, 0.001, "walking speed unchanged")
	weak.swarm.despawn(int(weak.bosses.records[0].slot))
	_ticks(weak, _time(122))
	assert_false(_on(weak, 122))
	assert_eq(weak.player.jump_stat, 100)
	_ticks(weak, 2, MoveInput.make(false, false, false, false, true, true))
	assert_true(weak.player.pos.y < floor_y, "after the status the same input jumps")


func _pickup_exp(w: RunWorld, amounts: Array) -> int:
	var before := w.progression.exp
	for amount: int in amounts:
		w.pickups.spawn(w.player.pos, amount, 4000019)
		_ticks(w, 3)
	return w.progression.exp - before


## Steps until status `id` is active (the cast tick), within `limit` ticks.
func _until_on(w: RunWorld, id: int, limit := 4000) -> void:
	for tick in limit:
		if _on(w, id):
			return
		w.step(DT, MoveInput.new())


## Curse: EXP is halved at the pickup while it lasts (fractions carry), and full before and after.
func test_curse_halves_pickup_exp() -> void:
	var w := _world(124)
	assert_eq(_pickup_exp(w, [2]), 2, "control: full before the cast")
	_until_on(w, 124)
	assert_true(_on(w, 124))
	assert_eq(_pickup_exp(w, [4]), 2, "halved at the pickup")
	assert_eq(_pickup_exp(w, [1, 1, 1, 1]), 2, "small orbs add up to half through the carry")
	w.swarm.despawn(int(w.bosses.records[0].slot))
	_ticks(w, _time(124))
	assert_false(_on(w, 124))
	assert_eq(_pickup_exp(w, [3]), 3, "full again after it ends")
	# The curse acts when the orb is picked up, not when the mob dropped it.
	var early := _world(124)
	var orb := early.player.pos + Vector2(-150, 0)
	early.pickups.spawn(orb, 6, 4000019)
	early.mob_skills.statuses.apply(MobSkillRunner.SKILL_CURSE, early.time, 10.0, {"visual": ""})
	_ticks(early, 2)
	var kept := early.progression.exp
	assert_eq(kept, 0, "the orb is not within reach")
	early.player.place(orb, early.fhm)
	_ticks(early, 5)
	assert_eq(early.progression.exp - kept, 3, "dropped before the curse, picked up under it: halved")


## Seduce: the horizontal input is replaced by a walk toward the caster, for min(time, seduce_cap) s; the cap is configurable.
func test_seduce_walks_toward_the_caster_for_the_capped_time() -> void:
	var w := _world(128)
	_ticks(w, _interval(128))
	assert_true(_on(w, 128))
	assert_near(float(w.player_state.seduce.remaining), 4.0, 0.02, "min(10 s, 4 s cap)")
	var boss := int(w.bosses.records[0].slot)
	w.drain_events()
	var start := w.player.pos.x
	# Pressing away from the caster is replaced; the character walks toward it.
	var dir := signf(w.swarm.x[boss] - w.player.pos.x)
	var away := MoveInput.make(dir > 0, dir < 0)
	_ticks(w, 30, away)
	assert_true((w.player.pos.x - start) * dir > 0.0, "walked toward the caster against the input")
	# The caster moves: the pull follows its current x each tick.
	w.relocate_mob(boss, Vector2(w.player.pos.x - dir * 200.0, 200), w.fhm.find_below(w.player.pos.x, 190))
	var before := w.player.pos.x
	_ticks(w, 15, MoveInput.new())
	assert_true((w.player.pos.x - before) * -dir > 0.0, "re-read the caster's x: it now pulls the other way")
	assert_eq(w.player_state.seduce.boss_index, 0)
	# Exactly 4 s (240 ticks) after the cast.
	var left := roundi(float(w.player_state.seduce.remaining) * 60.0)
	_ticks(w, left - 1)
	assert_true(_on(w, 128))
	_ticks(w, 1)
	assert_false(_on(w, 128), "over exactly at the cap")
	var long := _world(128, {}, 22, {"seduce_cap": 8})
	_ticks(long, _interval(128))
	assert_near(float(long.player_state.seduce.remaining), 8.0, 0.02, "balance.mob_skills.seduce_cap")
	var short := _world(128, {"time": 2.0})
	_ticks(short, _interval(128))
	assert_near(float(short.player_state.seduce.remaining), 2.0, 0.02, "a time under the cap is kept")


## Jump, casts and potions still work under Seduce (the walk is only the horizontal input).
func test_seduce_keeps_jump_potions_and_manual_skills() -> void:
	var w := _world(128, {"lt": {"$v": [-400.0, -400.0]}, "rb": {"$v": [400.0, 400.0]}})
	_ticks(w, _interval(128))
	assert_true(_on(w, 128))
	w.god = false
	w.take_hit(10.0, false, "", w.player.pos + Vector2(-10, 0), {"accuracy": 10000.0})
	w.god = true
	_ticks(w, 40)
	w.drain_events()
	var low := int(w.player_state.hp)
	var drink := MoveInput.new()
	drink.drink_hp = true
	_ticks(w, 1, drink)
	assert_true(w.drain_events().any(func(e: Dictionary) -> bool: return e.type == "potion_used"), "potions work")
	assert_true(int(w.player_state.hp) >= low)
	assert_true(w.can_cast(), "casts are not blocked")
	var y := w.player.pos.y
	_ticks(w, 3, MoveInput.make(false, false, false, false, true, true))
	assert_true(w.player.pos.y < y, "jump works while seduced")
	assert_true(_on(w, 128))


## Seduce ends early when the caster dies or leaves the map, and a seduced character is left alone afterwards.
func test_seduce_ends_early_when_the_caster_dies() -> void:
	var w := _world(128)
	_ticks(w, _interval(128))
	assert_true(_on(w, 128))
	_ticks(w, 30)
	assert_true(_on(w, 128))
	w.swarm.despawn(int(w.bosses.records[0].slot))
	_ticks(w, 1, MoveInput.make(false, true))
	assert_false(_on(w, 128), "the caster is gone: Seduce ends the same tick")
	var x := w.player.pos.x
	_ticks(w, 10, MoveInput.make(false, true))
	assert_true(w.player.pos.x > x, "the input is the player's again")
	# Dead through the encounter, not only a despawn.
	var killed := _world(128)
	_ticks(killed, _interval(128))
	var slot := int(killed.bosses.records[0].slot)
	killed.swarm.hp[slot] = 0
	killed.hit_mob(slot, {"skill": "t", "damage_type": "physical", "damage_min": 99999, "damage_max": 99999, "crit": 0.0, "crit_mult": 1.0}, -1)
	_ticks(killed, 2)
	assert_false(_on(killed, 128), "a killed caster releases the character")


## The Lyka box (-310..500 in x) is mirrored by the boss's facing, which is toward the character: the character in front is
## inside up to 310 px on either side of the boss and outside beyond.
func test_seduce_area_is_the_mirrored_lyka_box() -> void:
	for side in [-1.0, 1.0]:
		for case in [[300.0, true], [320.0, false]]:
			var w := _world(128)
			_ticks(w, _interval(128) - 1)
			w.player.place(Vector2(600.0 + side * float(case[0]), 200), w.fhm)
			_ticks(w, 1)
			var cast: Array = w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "boss_skill")
			assert_eq(cast.size(), 1, "the boss casts at the interval")
			assert_eq(int(cast[0].facing), int(side), "the boss faces the character")
			assert_eq(_on(w, 128), bool(case[1]), "%d px on side %s" % [int(case[0]), side])


## Confuse: left and right are swapped for exactly its time; vertical, jump and the other keys pass; the caller's input is untouched.
func test_confuse_swaps_left_and_right() -> void:
	var w := _world(132, {"time": 2.0, "inteval": 5.0})
	_ticks(w, 300)
	assert_true(_on(w, 132))
	var input := MoveInput.make(false, true)
	var x := w.player.pos.x
	_ticks(w, 20, input)
	assert_true(w.player.pos.x < x, "right becomes left")
	assert_true(input.right and not input.left, "the caller's input object is unchanged")
	x = w.player.pos.x
	_ticks(w, 20, MoveInput.make(true, false))
	assert_true(w.player.pos.x > x, "left becomes right")
	var y := w.player.pos.y
	_ticks(w, 3, MoveInput.make(false, false, false, false, true, true))
	assert_true(w.player.pos.y < y, "jump is not swapped")
	# Exactly 2 s after the cast (300 ticks): 120 ticks later it is over.
	var gone := _world(132, {"time": 2.0, "inteval": 5.0})
	_ticks(gone, 300)
	gone.swarm.despawn(int(gone.bosses.records[0].slot))
	_ticks(gone, 119)
	assert_true(_on(gone, 132))
	_ticks(gone, 1)
	assert_false(_on(gone, 132))
	var after := gone.player.pos.x
	_ticks(gone, 10, MoveInput.make(false, true))
	assert_true(gone.player.pos.x > after, "controls are normal again")


## Confuse applies to a bot-like scripted input deterministically: the same seed and script give the same positions.
func test_confuse_is_deterministic_for_a_scripted_bot() -> void:
	var traces: Array = []
	for run in 2:
		var w := _world(132, {"time": 6.0, "inteval": 5.0, "prop": 100.0})
		var trace := PackedFloat32Array()
		for tick in 900:
			var phase := (tick / 45) % 2
			w.step(DT, MoveInput.make(phase == 0, phase == 1, false, false, tick % 90 == 0, false))
			trace.append(w.player.pos.x)
		traces.append(trace)
	assert_eq(traces[0], traces[1], "same seed and inputs, same walk")
	var plain := _world(132, {"prop": 0.0, "inteval": 5.0})
	var base := PackedFloat32Array()
	for tick in 900:
		var phase := (tick / 45) % 2
		plain.step(DT, MoveInput.make(phase == 0, phase == 1, false, false, tick % 90 == 0, false))
		base.append(plain.player.pos.x)
	assert_ne(traces[0], base, "control: Confuse changes the walk")


## Seduce wins over Confuse (tier C), Stun over both, and a map transfer clears every status with the runner.
func test_precedence_and_map_reset() -> void:
	var w := _world(128, {"lt": {"$v": [-400.0, -400.0]}, "rb": {"$v": [400.0, 400.0]}})
	_ticks(w, _interval(128))
	var boss := int(w.bosses.records[0].slot)
	w.mob_skills.statuses.apply(MobSkillRunner.SKILL_CONFUSE, w.time, 5.0, {"visual": ""})
	var dir := signf(w.swarm.x[boss] - w.player.pos.x)
	var x := w.player.pos.x
	_ticks(w, 15, MoveInput.make(dir > 0, dir < 0))
	assert_true((w.player.pos.x - x) * dir > 0.0, "seduce overrides the swapped input")
	w.mob_skills.statuses.apply(MobSkillRunner.SKILL_STUN, w.time, 2.0, {"visual": ""})
	_ticks(w, 40)
	x = w.player.pos.x
	_ticks(w, 15, MoveInput.make(true, false))
	assert_eq(w.player.pos.x, x, "stun leaves no movement at all, whatever else is active")
	var fresh := MobSkillRunner.new({}, {})
	assert_false(fresh.is_darkened(0.0) or fresh.is_weakened(0.0) or fresh.is_cursed(0.0) or fresh.is_confused(0.0))
	assert_eq(fresh.exp_multiplier(0.0), 1.0)
