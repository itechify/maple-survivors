extends TestCase
## Boss target priority (#83): scheduled bosses in range take target slots before the nearest-first fill in every
## targeting rule. Seeded synthetic worlds stepped with a fixed dt.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
## Mob HP multiplier: every target survives the hits so hit order is fully observable.
const TOUGH := 1000.0


## A world with one synthetic skill (nearest rule unless `cast` names another), player at x=200 facing left.
func _world(cast: Dictionary = {}, kind: String = "instant") -> RunWorld:
	var data := RF.quiet_data()
	data.skills.skills["synthetic"] = {"skill_id": 9991000, "book": "999", "kind": kind,
		"damage": "fixed", "ranks": [1], "cooldown": 1.0, "range": 400.0, "speed": 400.0, "cast": cast}
	var setup := RF.setup("quiet", 83, data)
	setup.skill_imgs["999"] = {"skill": {"9991000": {"level": {
		"1": {"lt": {"$v": [-100.0, -60.0]}, "rb": {"$v": [20.0, 0.0]}, "mobCount": 2.0,
			"attackCount": 1.0, "fixdamage": 10.0, "mpCon": 1.0, "x": -40.0, "time": 2.0},
	}}}}
	var w := RunWorld.new(setup)
	RF.place_player(w, 200)
	w.player.facing = -1
	w.loadout.order.clear()
	w.learn_skill("synthetic")
	w.drain_events()
	return w


## Marks slot m as scheduled boss encounter 0, the way BossDirector does for a spawned boss.
func _make_boss(w: RunWorld, m: int) -> void:
	w.mob_boss[m] = 0
	w.swarm.steady[m] = 1


## Slots hit by the next runner step, in hit order, without repeats.
func _cast_hits(w: RunWorld) -> Array:
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	w.drain_events()
	w.runner.step(DT, w)
	var hits := []
	for e: Dictionary in w.drain_events():
		if e.type == "mob_hit" and not int(e.mob) in hits:
			hits.append(int(e.mob))
	return hits


func test_box_rule_gives_an_in_box_boss_the_first_slot_then_fills_nearest_first() -> void:
	# Facing left, the canonical box covers x 100..220 around the player at 200.
	for count_add: float in [-1.0, 0.0]:
		var w := _world({"rule": "box"})
		w.loadout.add_skill_mod("synthetic", "count", "add", count_add)
		var near := RF.put_mob(w, 1110100, 180, 190, TOUGH)
		var mid := RF.put_mob(w, 1110100, 160, 190, TOUGH)
		var boss := RF.put_mob(w, 1110100, 120, 190, TOUGH)
		_make_boss(w, boss)
		var hits := _cast_hits(w)
		if count_add < 0.0:
			assert_eq(hits, [boss], "mobCount 1: the boss takes the only slot over two nearer mobs")
		else:
			assert_eq(hits, [boss, near], "mobCount 2: boss first, then the nearest normal mob")
			assert_eq(w.swarm.hp[mid], w.swarm.max_hp[mid], "the capped-out mob is untouched")


func test_nearest_rule_gives_an_in_range_boss_the_first_slot_then_fills_nearest_first() -> void:
	# Range 400 from the body: every mob below is in range; the boss is the farthest.
	for count_add: float in [0.0, 2.0]:
		var w := _world()
		w.loadout.add_skill_mod("synthetic", "count", "add", count_add)
		var near := RF.put_mob(w, 1110100, 230, 190, TOUGH)
		var mid := RF.put_mob(w, 1110100, 300, 190, TOUGH)
		var far := RF.put_mob(w, 1110100, 350, 190, TOUGH)
		var boss := RF.put_mob(w, 1110100, 450, 190, TOUGH)
		_make_boss(w, boss)
		var hits := _cast_hits(w)
		if count_add == 0.0:
			assert_eq(hits, [boss], "count 1: the boss takes the only slot over three nearer mobs")
		else:
			assert_eq(hits, [boss, near, mid], "count 3: boss first, then the two nearest normal mobs")
			assert_eq(w.swarm.hp[far], w.swarm.max_hp[far], "the capped-out mob is untouched")


func test_nearest_projectiles_aim_at_the_boss_first() -> void:
	var w := _world({}, "projectile")
	RF.put_mob(w, 1110100, 170, 190, TOUGH)
	var boss := RF.put_mob(w, 1110100, 450, 190, TOUGH)
	_make_boss(w, boss)
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	w.runner.step(DT, w)
	assert_eq(w.projectiles.active_count(), 1, "count 1 fires one shot")
	var shots := []
	for i in w.projectiles.active.size():
		if w.projectiles.active[i] != 0:
			shots.append(w.projectiles.vx[i])
	assert_eq(shots.size(), 1)
	if shots.size() == 1:
		assert_true(float(shots[0]) > 0.0, "the shot flies right, toward the boss, not the nearer mob on the left")
	assert_eq(w.player.facing, 1, "the caster turns toward the boss")


## Slots slowed by the next crowd cast, in the order of `slots`.
func _slowed(w: RunWorld, slots: Array) -> Array:
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	w.runner.step(DT, w)
	return slots.filter(func(m: int) -> bool: return w.swarm.status_time(m, MobSwarm.SLOW) > 0.0)


func test_crowd_rule_puts_an_eligible_boss_first_and_never_slows_a_steady_scheduled_boss() -> void:
	for steady: bool in [false, true]:
		for count_add: float in [-1.0, 0.0]:
			var w := _world({"rule": "crowd", "min_targets": 1})
			w.loadout.add_skill_mod("synthetic", "count", "add", count_add)
			var near := RF.put_mob(w, 1110100, 180, 190, TOUGH)
			var mid := RF.put_mob(w, 1110100, 160, 190, TOUGH)
			var boss := RF.put_mob(w, 1110100, 120, 190, TOUGH)
			_make_boss(w, boss)
			if not steady:
				# Hypothetical slowable boss: shows the shared crowd order, which real (steady) bosses never reach.
				w.swarm.steady[boss] = 0
			var slowed := _slowed(w, [near, mid, boss])
			if steady:
				# tier C: Slow rejects scheduled bosses, so the eligible targets are exactly those with no boss.
				assert_eq(slowed, [near] if count_add < 0.0 else [near, mid], "a steady boss takes no Slow slot")
			elif count_add < 0.0:
				assert_eq(slowed, [boss], "mobCount 1: an eligible boss takes the only Slow slot")
			else:
				assert_eq(slowed, [near, boss], "mobCount 2: the boss and the nearest eligible mob")
				assert_eq(w.swarm.status_time(mid, MobSwarm.SLOW), 0.0, "the capped-out mob is not slowed")


func test_without_a_boss_every_rule_keeps_nearest_first_and_elites_get_no_priority() -> void:
	# The same layouts as the boss tests, with the farthest mob an elite instead of a scheduled boss.
	var box := _world({"rule": "box"})
	var b_near := RF.put_mob(box, 1110100, 180, 190, TOUGH)
	var b_mid := RF.put_mob(box, 1110100, 160, 190, TOUGH)
	RF.put_mob(box, 1110100, 120, 190, TOUGH, true)
	assert_eq(_cast_hits(box), [b_near, b_mid], "box: nearest first")
	var nearest := _world()
	nearest.loadout.add_skill_mod("synthetic", "count", "add", 2.0)
	var n_near := RF.put_mob(nearest, 1110100, 230, 190, TOUGH)
	var n_mid := RF.put_mob(nearest, 1110100, 300, 190, TOUGH)
	var n_far := RF.put_mob(nearest, 1110100, 350, 190, TOUGH)
	RF.put_mob(nearest, 1110100, 450, 190, TOUGH, true)
	assert_eq(_cast_hits(nearest), [n_near, n_mid, n_far], "nearest: nearest first")
	var crowd := _world({"rule": "crowd", "min_targets": 1})
	var c_near := RF.put_mob(crowd, 1110100, 180, 190, TOUGH)
	var c_mid := RF.put_mob(crowd, 1110100, 160, 190, TOUGH)
	var c_elite := RF.put_mob(crowd, 1110100, 120, 190, TOUGH, true)
	assert_eq(_slowed(crowd, [c_near, c_mid, c_elite]), [c_near, c_mid], "crowd: nearest first")
