extends TestCase
## Disorder's crowd admission, canonical Threatened effect and ordinary-attack interrupt (#210).
## Seeded synthetic worlds use fixed ticks; cache checks independently verify the v83 level table and art.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const MF := preload("res://tests/fixtures/mob_attack_fixtures.gd")
const DT := 1.0 / 60.0


func _world() -> RunWorld:
	var setup := MF.setup(210)
	setup["job"] = 400 # a Thief with no start skills (#284)
	var w := RunWorld.new(setup)
	RF.place_player(w, 400)
	w.drain_events()
	return w


func _put(w: RunWorld, x: float) -> int:
	var slot := RF.put_mob(w, MF.TAURO, x)
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	return slot


func test_disorder_requires_a_fresh_ordinary_crowd_and_casts_once() -> void:
	var w := _world()
	assert_true(w.book.has("disorder"), "Disorder is available")
	if not w.book.has("disorder"):
		return
	w.learn_skill("disorder")
	var a := _put(w, 450)
	var b := _put(w, 500)
	var boss := _put(w, 430)
	w.swarm.steady[boss] = 1
	var already := _put(w, 440)
	w.swarm.apply_status(already, "threatened", {"time": 30.0, "x": -10.0, "y": -10.0}, w.events)
	_put(w, 750) # outside the survivor box
	w.runner.step(DT, w)
	assert_eq(w.runner.casts, 0, "two eligible mobs do not satisfy the crowd rule")
	var c := _put(w, 550)
	w.runner.step(DT, w)
	assert_eq(w.runner.casts, 1)
	for slot: int in [a, b, c]:
		assert_near(w.swarm.status_time(slot, MobSwarm.THREATENED), 7.0)
		assert_eq(w.swarm.threatened_pad(slot, 100.0), 99.0)
		assert_eq(w.swarm.threatened_pdd(slot, 25.0), 24.0)
	assert_near(w.swarm.status_time(boss, MobSwarm.THREATENED), 0.0)
	assert_near(w.swarm.status_time(already, MobSwarm.THREATENED), 30.0, 1e-6, "no refresh on an existing status")
	w.runner.step(1.0, w)
	assert_eq(w.runner.casts, 1, "threatened mobs cannot trigger a second cast")


func test_disorder_cancels_a_windup_without_stun_or_rescheduling_but_threaten_does_not() -> void:
	for key in ["disorder", "threaten"]:
		var w := _world()
		w.god = true
		if key == "threaten":
			RF.change_job_bare(w, 120)
		for x in [500.0, 550.0, 600.0]:
			_put(w, x)
		var first := {}
		for tick in 240:
			w.step(DT, MoveInput.new())
			for e: Dictionary in w.drain_events():
				if e.type == "mob_attack" and e.phase == "start":
					first = e
			if not first.is_empty():
				break
		assert_false(first.is_empty(), "fixture starts an attack")
		if first.is_empty():
			return
		var slot := int(first.mob)
		var wait := w.mob_attacks.wait_left(slot)
		assert_true(w.mob_actions.busy(slot, w.time))
		w.learn_skill(key)
		w.runner.step(DT, w)
		assert_eq(w.runner.casts, 1)
		assert_eq(w.mob_actions.busy(slot, w.time), key == "threaten", "only Disorder releases the attack stance")
		assert_near(w.mob_attacks.wait_left(slot), wait, 1e-6, "the attack wait is preserved")
		assert_near(w.swarm.status_time(slot, MobSwarm.STUN), 0.0)
		assert_true(w.swarm.can_act(slot), "Threatened never prevents movement or future attacks")
		w.drain_events()
		var impacts := 0
		var next_start := -1.0
		for tick in 190:
			w.step(DT, MoveInput.new())
			for e: Dictionary in w.drain_events():
				if e.type == "mob_attack" and int(e.mob) == slot:
					if e.phase == "start":
						next_start = float(e.time)
					elif e.phase == "impact":
						impacts += 1
			if next_start >= 0.0:
				break
		assert_eq(impacts, 1 if key == "threaten" else 0, "Disorder loses the pending impact; Threaten keeps it")
		assert_near(next_start - float(first.time), 3.0, DT, "next attack starts at its original interval")


func test_disorder_has_only_learn_and_rank_cards_on_the_thief_line() -> void:
	var w := _world()
	assert_eq(w.book.skill_id("disorder"), 4001002)
	assert_eq(w.book.max_rank("disorder"), 20)
	var cards := w.upgrades.cards.filter(func(c: Dictionary) -> bool: return c.get("skill", "") == "disorder")
	assert_eq(cards.size(), 2)
	for c: Dictionary in cards:
		assert_true(String(c.id) in ["disorder_new", "disorder_rank"])
		assert_eq(Array(c.requires.jobs).map(func(j: Variant) -> int: return int(j)), [400])
		assert_false(c.requires.has("carry_jobs"))
		assert_false(bool(c.get("power", false)))


func test_the_nearest_six_get_the_canonical_cut_and_it_expires_without_stun() -> void:
	for rank in [1, 20]:
		var w := _world()
		w.god = true
		w.learn_skill("disorder")
		w.loadout.set_rank("disorder", rank)
		var mobs := []
		for x in [610.0, 580.0, 550.0, 520.0, 490.0, 460.0, 430.0]:
			mobs.append(_put(w, x))
		w.runner.step(DT, w)
		w.runner.cooldowns.disorder = 10000.0 # observe expiry without an immediate new cast
		assert_near(w.swarm.status_time(mobs[0], MobSwarm.THREATENED), 0.0, 1e-6, "farthest is beyond the six-target cap")
		var slot := int(mobs[-1])
		assert_eq(w.swarm.threatened_pad(slot, 100.0), 99.0 if rank == 1 else 80.0)
		assert_eq(w.swarm.threatened_pdd(slot, 25.0), 24.0 if rank == 1 else 5.0)
		assert_eq(w.swarm.threatened_pdd(slot, 0.0), 0.0)
		var seconds := 7 if rank == 1 else 60
		for tick in seconds * 60 - 1:
			w.step(DT, MoveInput.new())
		assert_true(w.swarm.status_time(slot, MobSwarm.THREATENED) > 0.0)
		for tick in 2:
			w.step(DT, MoveInput.new())
		assert_near(w.swarm.status_time(slot, MobSwarm.THREATENED), 0.0)
		assert_eq(w.swarm.threatened_pad(slot, 100.0), 100.0)
		assert_eq(w.swarm.threatened_pdd(slot, 25.0), 25.0)
		assert_near(w.swarm.status_time(slot, MobSwarm.STUN), 0.0)


func test_disorder_plays_its_own_mob_art_once_per_affected_target_without_damage() -> void:
	var w := _world()
	w.learn_skill("disorder")
	for x in [450.0, 500.0, 550.0]:
		_put(w, x)
	w.drain_events()
	w.runner.step(DT, w)
	var events := w.drain_events()
	var effects := events.filter(func(e: Dictionary) -> bool: return e.type == "skill_mob_effect")
	assert_eq(effects.size(), 3)
	for e: Dictionary in effects:
		assert_eq(String(e.effect), "Skill.wz/400.img/skill/4001002/mob")
		assert_eq(String(e.skill), "disorder")
	assert_false(events.any(func(e: Dictionary) -> bool: return e.type == "mob_hit"), "no fake damaging hits")


func test_real_v83_levels_and_art_cast_through_the_survivor_fallback_box() -> void:
	if not require_cache():
		return
	var library := AssetLibrary.new()
	library.open()
	var img := library.img("Skill.wz/400.img")
	assert_true(img != null)
	if img == null:
		library.free()
		return
	var setup := MF.setup(210)
	setup.skill_imgs["400"] = img.root
	setup["job"] = 400 # a Thief with no start skills (#284)
	var w := RunWorld.new(setup)
	RF.place_player(w, 400)
	var times := [7,9,11,13,15,20,22,24,29,31,33,38,40,42,47,49,51,56,58,60]
	var costs := [5,5,5,5,5,6,6,6,7,7,7,8,8,8,9,9,9,10,10,10]
	for lv in range(1, 21):
		assert_eq(w.book.canonical("disorder", lv, "x"), -float(lv))
		assert_eq(w.book.canonical("disorder", lv, "y"), -float(lv))
		assert_eq(w.book.canonical("disorder", lv, "time"), float(times[lv - 1]))
		assert_eq(w.book.canonical("disorder", lv, "mpCon"), float(costs[lv - 1]))
		assert_false(w.book.level_node("disorder", lv).has("lt"), "range belongs in survivor data")
	assert_true(library.find_anim("Skill.wz/400.img/skill/4001002/mob") != null)
	assert_true(library.sound("Sound.wz/Skill.img/4001002/Use") != null)
	w.learn_skill("disorder")
	w.loadout.set_rank("disorder", 6)
	var mobs := [_put(w, 450), _put(w, 500), _put(w, 550)]
	w.runner.step(DT, w)
	assert_eq(w.runner.casts, 1)
	assert_near(w.swarm.status_time(mobs[0], MobSwarm.THREATENED), 20.0)
	assert_eq(w.swarm.threatened_pad(mobs[0], 100.0), 94.0)
	library.free()
