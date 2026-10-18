extends TestCase
## The generic stunned mob status (#187 of spec #168): a stunned mob stands still, starts no attacks or mob skills,
## deals no touch damage and still takes damage; a new stun keeps the longer time; bosses and steady bosses resist it;
## a skill's on_hit block requests it with prop/time. Synthetic inputs, seeded RNG, fixed dt.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const MF := preload("res://tests/fixtures/mob_attack_fixtures.gd")
const DT := 1.0 / 60.0


func _ctx(w: RunWorld) -> Dictionary:
	return {"fhm": w.fhm, "target": w.player.pos, "target_fh": w.player.fh, "bounds": w.bounds,
		"events": w.events}


## A world whose skill "synthetic" hits the mob and carries the given on_hit block (level 1: prop 30, time 3).
func _skill_world(on_hit: Dictionary) -> RunWorld:
	var data := RF.quiet_data()
	data.balance.player.mp = 100
	data.skills.skills["synthetic"] = {"skill_id": 9991000, "book": "999", "kind": "instant",
		"damage": "fixed", "ranks": [1, 2], "cooldown": 1.0, "range": 400.0, "speed": 400.0,
		"cast": {}, "on_hit": on_hit}
	var setup := RF.setup("quiet", 31, data)
	setup.skill_imgs["999"] = {"skill": {"9991000": {"level": {
		"1": {"lt": {"$v": [-100.0, -60.0]}, "rb": {"$v": [20.0, 0.0]}, "mobCount": 2.0,
			"attackCount": 2.0, "fixdamage": 10.0, "mpCon": 7.0, "time": 1.0, "prop": 30.0},
		"2": {"lt": {"$v": [-120.0, -60.0]}, "rb": {"$v": [30.0, 0.0]}, "mobCount": 3.0,
			"attackCount": 2.0, "fixdamage": 20.0, "mpCon": 9.0, "time": 4.0, "prop": 100.0},
	}}}}
	var w := RunWorld.new(setup)
	RF.place_player(w, 200)
	w.loadout.order.clear()
	w.learn_skill("synthetic")
	w.drain_events()
	return w


func test_stun_is_a_status_name_with_its_own_table_row() -> void:
	assert_eq(MobSwarm.STATUS_NAMES[MobSwarm.STUN], "stun")
	assert_eq(MobSwarm.STATUS_NAMES.size(), MobSwarm.STATUS_COUNT)
	assert_eq(MobSwarm.STATUS_ELEMENTS.size(), MobSwarm.STATUS_COUNT)


func test_stun_and_threatened_coexist_and_expire_independently_across_slots() -> void:
	var w := RF.quiet_world()
	var m := RF.put_mob(w, 1110100, 700)
	var other := RF.put_mob(w, 1110100, 800)
	w.swarm.alpha[m] = 1.0
	w.swarm.alpha[other] = 1.0
	assert_eq(MobSwarm.THREATENED, 3, "keep the shipped Threaten table index")
	assert_ne(MobSwarm.STUN, MobSwarm.THREATENED)
	assert_true(w.swarm.apply_status(m, "threatened", {"x": -30, "y": -10, "time": 2}, w.events))
	assert_true(w.swarm.apply_status(m, "stun", {"time": 1}, w.events))
	assert_true(w.swarm.apply_status(other, "stun", {"time": 3}, w.events))
	assert_near(w.swarm.threatened_pad(m, 82), 52)
	assert_near(w.swarm.threatened_pdd(m, 12), 2)
	assert_near(w.swarm.threatened_pad(other, 82), 82, 1e-6, "the next slot has no Threaten cut")
	assert_false(w.swarm.can_act(m))
	var ctx := _ctx(w)
	for tick in 60:
		w.swarm.step(DT, ctx)
	assert_near(w.swarm.status_time(m, MobSwarm.STUN), 0)
	assert_near(w.swarm.status_time(m, MobSwarm.THREATENED), 1)
	assert_near(w.swarm.status_time(other, MobSwarm.STUN), 2)
	assert_true(w.swarm.can_act(m), "Threaten alone does not stop attacks")
	assert_false(w.swarm.can_act(other), "the next slot is still stunned")
	assert_near(w.swarm.threatened_pad(m, 82), 52, 1e-6, "stun expiry keeps the cut")
	for tick in 60:
		w.swarm.step(DT, ctx)
	assert_near(w.swarm.threatened_pad(m, 82), 82)
	assert_near(w.swarm.threatened_pdd(m, 12), 12)
	assert_near(w.swarm.status_time(other, MobSwarm.STUN), 1)
	assert_true(w.swarm.has_statuses(), "the other slot's stun outlives Threaten")
	for tick in 60:
		w.swarm.step(DT, ctx)
	assert_false(w.swarm.has_statuses())


func test_stunned_mob_does_not_move_for_the_duration_then_resumes() -> void:
	var w := RF.quiet_world()
	var m := RF.put_mob(w, 1110100, 700)
	w.swarm.alpha[m] = 1.0
	var ctx := _ctx(w)
	w.swarm.step(DT, ctx)
	var start := w.swarm.pos(m)
	assert_true(w.swarm.apply_status(m, "stun", {"time": 1.0}, w.events))
	assert_false(w.swarm.can_act(m), "a stunned mob cannot start attacks or skills")
	for tick in 59:
		w.swarm.step(DT, ctx)
		assert_eq(w.swarm.pos(m), start, "no movement while stunned")
	assert_true(w.swarm.status_time(m, MobSwarm.STUN) > 0.0)
	w.swarm.step(DT, ctx)
	assert_near(w.swarm.status_time(m, MobSwarm.STUN), 0.0)
	assert_eq(w.swarm.pos(m), start)
	assert_eq(w.swarm.state[m], MobSwarm.STAND, "the stunned mob stands")
	assert_true(w.swarm.can_act(m))
	for tick in 5:
		w.swarm.step(DT, ctx)
	assert_true(w.swarm.x[m] < start.x, "it walks toward the character again")
	assert_eq(w.swarm.state[m], MobSwarm.MOVE)
	var types := w.events.filter(func(e: Dictionary) -> bool: return String(e.type).begins_with("mob_status"))
	assert_eq(types.map(func(e: Dictionary) -> String: return e.type), ["mob_status_applied", "mob_status_expired"])
	assert_eq(types[0].status, "stun")
	assert_near(float(types[0].duration), 1.0)
	assert_false(w.swarm.has_statuses())


func test_stun_stops_a_pushed_mob_and_a_hit_does_not_restart_it() -> void:
	var w := RF.quiet_world()
	var m := RF.put_mob(w, 1110100, 700)
	w.swarm.alpha[m] = 1.0
	var ctx := _ctx(w)
	w.swarm.step(DT, ctx)
	assert_true(w.swarm.apply_status(m, "stun", {"time": 1.0}, w.events))
	var hp := w.swarm.hp[m]
	var start := w.swarm.pos(m)
	assert_false(w.swarm.apply_hit(m, 5, 1))
	assert_eq(w.swarm.hp[m], hp - 5, "a stunned mob still takes damage")
	for tick in 30:
		w.swarm.step(DT, ctx)
	assert_eq(w.swarm.pos(m), start, "no hit push while stunned")
	assert_ne(w.swarm.state[m], MobSwarm.HIT)
	assert_true(w.swarm.apply_hit(m, 99999, 1), "and can be killed")
	assert_eq(w.swarm.status_time(m, MobSwarm.STUN), 0.0, "death clears the stun")
	assert_false(w.swarm.has_statuses())


func test_stun_lets_a_jumping_mob_land_and_a_flyer_hover() -> void:
	var w := RF.quiet_world()
	var m := RF.put_mob(w, 1110100, 700)
	var ctx := _ctx(w)
	w.swarm.alpha[m] = 1.0
	w.swarm.fh[m] = -1
	w.swarm.y[m] -= 80.0
	w.swarm.vx[m] = 50.0
	w.swarm.vy[m] = 0.0
	var start := w.swarm.pos(m)
	assert_true(w.swarm.apply_status(m, "stun", {"time": 5.0}, w.events))
	for tick in 20:
		w.swarm.step(DT, ctx)
	assert_true(w.swarm.y[m] > start.y, "a mob stunned mid-air falls")
	assert_eq(w.swarm.x[m], start.x, "straight down")
	for tick in 120:
		w.swarm.step(DT, ctx)
	assert_true(w.swarm.fh[m] >= 0, "and lands")
	assert_eq(w.swarm.x[m], start.x)
	var f := w.spawn_mob(int(w.kind_of_id[9300063]), Vector2(700, 100), -1, 1.0, false)
	assert_true(w.swarm.mob_kind(f).flies, "fixture: a flying kind")
	w.swarm.alpha[f] = 1.0
	assert_true(w.swarm.apply_status(f, "stun", {"time": 2.0}, w.events))
	var pos := w.swarm.pos(f)
	for tick in 60:
		w.swarm.step(DT, ctx)
	assert_eq(w.swarm.pos(f), pos, "a stunned flyer hovers")
	for tick in 90:
		w.swarm.step(DT, ctx)
	assert_ne(w.swarm.pos(f), pos, "and pursues again afterwards")


func test_stunned_mob_starts_no_attack_for_the_duration_then_attacks() -> void:
	var control := MF.world()
	RF.put_mob(control, MF.TAURO, 600)
	var natural := _first_start(control, 600)
	assert_true(natural >= 0, "fixture: the unstunned Tauro attacks")
	var w := MF.world()
	w.god = true
	var slot := RF.put_mob(w, MF.TAURO, 600)
	var stun_ticks := natural + 60
	assert_true(w.swarm.apply_status(slot, "stun", {"time": float(stun_ticks) * DT}, w.events))
	var started := -1
	var hp := int(w.player_state.hp)
	for tick in stun_ticks + 600:
		w.step(DT, MoveInput.new())
		for e: Dictionary in w.drain_events():
			if e.type == "mob_attack" and e.phase == "start" and started < 0:
				started = tick
		if started >= 0:
			break
		assert_eq(w.mob_action_view().actions[slot], "", "no attack stance while stunned")
	assert_true(started >= stun_ticks - 1, "no attack starts until the stun ends (started %d, stun %d ticks)" % [
		started, stun_ticks])
	assert_eq(int(w.player_state.hp), hp)


func _first_start(w: RunWorld, ticks: int) -> int:
	for tick in ticks:
		w.step(DT, MoveInput.new())
		for e: Dictionary in w.drain_events():
			if e.type == "mob_attack" and e.phase == "start":
				return tick
	return -1


func test_stunned_monsters_deal_no_touch_damage() -> void:
	var w := RF.quiet_world()
	w.loadout.order.clear()
	var m := RF.put_mob(w, 1110100, w.player.pos.x)
	w.swarm.alpha[m] = 1.0
	assert_true(w.swarm.apply_status(m, "stun", {"time": 1.0}, w.events))
	var hp := float(w.player_state.hp)
	for tick in 59:
		w.step(DT, MoveInput.new())
	assert_eq(float(w.player_state.hp), hp, "a stunned monster deals no touch damage, like a frozen one")
	for tick in 90:
		w.step(DT, MoveInput.new())
	assert_true(float(w.player_state.hp) < hp, "its bodyAttack returns when the stun ends")


func test_bosses_and_steady_bosses_resist_stun_but_elements_do_not() -> void:
	for scheduled: bool in [false, true]:
		var w := RF.quiet_world()
		var m := RF.put_mob(w, 1110100 if scheduled else 2220000, 700)
		w.swarm.steady[m] = 1 if scheduled else 0
		w.drain_events()
		assert_false(w.swarm.accepts_status(m, "stun"))
		assert_false(w.swarm.apply_status(m, "stun", {"time": 2}, w.events),
			"a %s boss resists stun" % ("scheduled" if scheduled else "canonical"))
		assert_true(w.events.is_empty())
		assert_false(w.swarm.has_statuses())
		assert_true(w.swarm.can_act(m) or w.swarm.alpha[m] < 1.0, "a refused stun leaves the gate alone")
	var w := RF.quiet_world()
	var img := RF.mob_img(1110100)
	img.info["elemAttr"] = "S1I2F1L4P1"
	w.mob_kinds[0] = MobKind.from_wz(img, 1110100)
	var m := w.spawn_mob(0, w.player.pos + Vector2(200, 0), w.player.fh, 1.0, false)
	assert_true(w.swarm.apply_status(m, "stun", {"time": 2}, w.events), "stun has no element to resist")
	assert_true(w.swarm.apply_status(m, "stun", {"time": 2, "element": "f"}, w.events),
		"not even an element the applying skill passes in")


func test_a_new_stun_keeps_the_longer_remaining_time() -> void:
	var w := RF.quiet_world()
	var m := RF.put_mob(w, 1110100, 700)
	var ctx := _ctx(w)
	assert_true(w.swarm.apply_status(m, "stun", {"time": 3.0}, w.events))
	for tick in 60:
		w.swarm.step(DT, ctx)
	assert_near(w.swarm.status_time(m, MobSwarm.STUN), 2.0, 1e-6)
	assert_true(w.swarm.apply_status(m, "stun", {"time": 1.0}, w.events), "a shorter stun is still accepted")
	assert_near(w.swarm.status_time(m, MobSwarm.STUN), 2.0, 1e-6, "but the remaining time is kept")
	var elapsed := w.swarm.status_elapsed[m * MobSwarm.STATUS_COUNT + MobSwarm.STUN]
	assert_near(elapsed, 1.0, 1e-4, "and the art clock keeps running")
	assert_true(w.swarm.apply_status(m, "stun", {"time": 2.5}, w.events))
	assert_near(w.swarm.status_time(m, MobSwarm.STUN), 2.5, 1e-6, "a longer one refreshes to its own time")
	assert_eq(w.swarm.status_elapsed[m * MobSwarm.STATUS_COUNT + MobSwarm.STUN], 0.0)
	for tick in 150:
		w.swarm.step(DT, ctx)
	assert_near(w.swarm.status_time(m, MobSwarm.STUN), 0.0)
	assert_false(w.swarm.has_statuses())


func test_stun_needs_a_positive_time_and_leaves_other_statuses_alone() -> void:
	var w := RF.quiet_world()
	var m := RF.put_mob(w, 1110100, 700)
	assert_false(w.swarm.apply_status(m, "stun", {"time": 0.0}, w.events))
	assert_false(w.swarm.apply_status(m, "stun", {}, w.events))
	assert_true(w.swarm.apply_status(m, "slow", {"x": -40, "time": 5}, w.events))
	assert_true(w.swarm.apply_status(m, "stun", {"time": 1}, w.events))
	var ctx := _ctx(w)
	for tick in 61:
		w.swarm.step(DT, ctx)
	assert_near(w.swarm.status_time(m, MobSwarm.STUN), 0.0)
	assert_near(w.swarm.status_time(m, MobSwarm.SLOW), 4.0, 0.02, "the slow outlives the stun")
	assert_true(w.swarm.has_statuses(), "the slot stays listed while any status remains")
	assert_near(w.swarm.slow_factor[m], 0.6, 1e-6)


func test_on_hit_requests_stun_with_the_skills_prop_and_time_deterministically() -> void:
	var observations: Array = []
	for repeat in 2:
		var w := _skill_world({"status": "stun", "chance_field": "prop", "duration_field": "time"})
		var m := RF.put_mob(w, 1110100, 350, 195, 100.0)
		var st := w.loadout.stats("synthetic")
		w.drain_events()
		for line in 1000:
			w.hit_mob(m, st, -1)
		var applied := w.events.filter(func(e: Dictionary) -> bool: return e.type == "mob_status_applied")
		assert_between(applied.size(), 250, 350, "30% prop over 1000 seeded hits")
		observations.append(applied.size())
		assert_eq(applied[0].status, "stun")
		assert_near(float(applied[0].duration), 1.0, 1e-6, "time from the skill's level 1 fields")
		assert_near(w.swarm.status_time(m, MobSwarm.STUN), 1.0)
		# Level 2: prop 100 always lands and takes the level's own time.
		w.loadout.set_rank("synthetic", 2)
		var before := applied.size()
		w.drain_events()
		var st2 := w.loadout.stats("synthetic")
		w.hit_mob(m, st2, -1)
		assert_eq(w.events.filter(func(e: Dictionary) -> bool: return e.type == "mob_status_applied").size(), 1)
		assert_near(w.swarm.status_time(m, MobSwarm.STUN), 4.0)
		assert_true(before > 0)
	assert_eq(observations[0], observations[1], "the same seed reproduces the stun rolls")


func test_on_hit_stun_without_a_chance_field_always_lands_and_bosses_resist_it() -> void:
	var w := _skill_world({"status": "stun", "duration_field": "time"})
	var m := RF.put_mob(w, 1110100, 350)
	var boss := RF.put_mob(w, 1110100, 330)
	w.swarm.steady[boss] = 1
	w.drain_events()
	w.hit_mob(m, w.loadout.stats("synthetic"), -1)
	assert_near(w.swarm.status_time(m, MobSwarm.STUN), 1.0)
	w.hit_mob(boss, w.loadout.stats("synthetic"), -1)
	assert_near(w.swarm.status_time(boss, MobSwarm.STUN), 0.0, 1e-6, "a steady boss resists the skill's stun")
	assert_eq(w.events.filter(func(e: Dictionary) -> bool: return e.type == "mob_status_applied").size(), 1)


func test_real_v83_stun_cue_is_cached() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	assert_true(lib.open(AssetCachePaths.resolve_cache_root()))
	var anim := lib.find_anim(MobRenderer.STATUS_PATHS[MobRenderer.STUN_CUE])
	assert_true(anim != null, "the v83 stun stars (Skill.wz mob node) are in the cache")
	if anim != null:
		assert_eq(anim.frames.size(), 3)
		assert_near(anim.total, 0.3, 1e-6)
	lib.free()
