extends TestCase
## Seeded monster hits through the shared combat boundary: mitigation, source scaling and misses.

const RF := preload("res://tests/fixtures/run_fixtures.gd")


func test_monster_damage_pinned_ranges() -> void:
	var examples := [
		{"attack": 42.0, "magic": false, "element": "", "defense": {"pdd": 7.0}, "lo": 31, "hi": 37},
		{"attack": 82.0, "magic": false, "element": "", "defense": {"pdd": 7.0}, "lo": 65, "hi": 77},
		{"attack": 82.0, "magic": false, "element": "", "defense": {"pdd": 47.0}, "lo": 35, "hi": 47},
		{"attack": 100.0, "magic": true, "element": "", "defense": {"pdd": 99.0, "mdd": 20.0}, "lo": 70, "hi": 85},
		{"attack": 100.0, "magic": true, "element": "f", "defense": {"mdd": 20.0, "resistance": {"f": 50.0}}, "lo": 35, "hi": 42},
		{"attack": 1.0, "magic": false, "element": "", "defense": {"pdd": 100.0}, "lo": 1, "hi": 1},
	]
	for example: Dictionary in examples:
		var rng := RandomNumberGenerator.new()
		rng.seed = 611
		var lo := 100000
		var hi := 0
		for hit in 2000:
			var damage := CombatMath.monster_hit(example.attack, example.magic, example.element, example.defense, rng)
			lo = mini(lo, damage)
			hi = maxi(hi, damage)
		assert_eq(lo, example.lo, "lower rounded endpoint is reached")
		assert_eq(hi, example.hi, "highest seeded result")
	assert_eq(CombatMath.monster_damage(100.0, 1.0, 20.0, 50.0), 43, "an exact maximum roll rounds 42.5 up")


func test_seeded_miss_rate_matches_avoid_against_accuracy() -> void:
	assert_near(CombatMath.miss_chance(5.0, 42.0), 0.0257142857, 1e-9)
	var rng := RandomNumberGenerator.new()
	rng.seed = 612
	var misses := 0
	for hit in 10000:
		if CombatMath.roll_miss(5.0, 42.0, rng):
			misses += 1
	assert_between(misses, 207, 307, "about 2.6% misses, with seeded sampling tolerance")
	var before := rng.state
	assert_false(CombatMath.roll_miss(0.0, 42.0, rng))
	assert_false(CombatMath.roll_miss(5.0, 0.0, rng), "missing synthetic accuracy cannot divide by zero")
	assert_eq(rng.state, before, "no RNG consumption when a miss is impossible")


func test_miss_has_no_damage_knockback_or_invincibility() -> void:
	var data := RF.quiet_data()
	data.balance.player.stats.dex = 4000 # Guaranteed avoid vs accuracy 42.
	var w := RunWorld.new(RF.setup("quiet", 613, data))
	RF.as_job(w, 200)
	w.learn_skill("magic_guard")
	w.drain_events()
	var before := w.player_state.duplicate()
	var velocity := w.player.vel
	assert_eq(w.take_hit(82.0, false, "", w.player.pos - Vector2(10, 0), {"accuracy": 42}), 0)
	var events := w.drain_events()
	assert_eq(events.size(), 1)
	assert_eq(events[0].type, "player_hit")
	assert_eq(events[0].miss, true)
	assert_eq(events[0].damage, 0)
	assert_false(events[0].has("mp_absorbed"), "no MP (#285)")
	assert_eq(w.player_state.hp, before.hp)
	assert_eq(w.player_state.invincible_t, 0.0)
	assert_eq(w.player.vel, velocity)


func test_only_explicit_hit_source_multipliers_scale_damage() -> void:
	var data := RF.quiet_data()
	data.stages.stages.quiet.elites = {"damage_mult": 2.0}
	# Legacy stage-wide damage values must have no effect, even in an old synthetic setup.
	data.stages.stages.quiet.keyframes[0].damage = 0.01
	var normal := RunWorld.new(RF.setup("quiet", 614, data))
	var elite := RunWorld.new(RF.setup("quiet", 614, data))
	assert_eq(normal.hit_source_multiplier({}), 1.0)
	assert_eq(elite.hit_source_multiplier({"elite": true}), 2.0)
	assert_eq(elite.hit_source_multiplier({"dmg_mult": 3.0}), 3.0, "boss attack source can supply its multiplier")
	assert_between(normal.take_hit(20.0, false, "", normal.player.pos), 17, 20)
	assert_between(elite.take_hit(20.0, false, "", elite.player.pos, {"elite": true}), 34, 40)


func test_normal_mob_flinches_only_at_canonical_pushed_threshold() -> void:
	var setup := RF.setup("quiet", 615, RF.quiet_data())
	setup.mob_imgs[100100].info.pushed = 30.0
	var w := RunWorld.new(setup)
	var mob := RF.put_mob(w, 100100, 460.0, 190.0, 100.0)
	var hp := w.swarm.hp[mob]
	var position := Vector2(w.swarm.x[mob], w.swarm.y[mob])
	w.hit_mob(mob, {"damage_min": 29.0, "damage_max": 29.0, "magic": false,
		"crit": 0.0, "crit_mult": 1.5, "skill": "three_snails"}, -1)
	assert_eq(w.swarm.hp[mob], hp - 29)
	assert_eq(w.swarm.state[mob], MobSwarm.STAND, "below pushed: damage without hit stun")
	assert_eq(Vector2(w.swarm.x[mob], w.swarm.y[mob]), position)
	w.hit_mob(mob, {"damage_min": 30.0, "damage_max": 30.0, "magic": false,
		"crit": 0.0, "crit_mult": 1.5, "skill": "three_snails"}, -1)
	assert_eq(w.swarm.state[mob], MobSwarm.HIT, "pushed reached: hit stun starts")
	assert_true(w.swarm.vx[mob] > 0.0, "a grounded mob is also pushed away")


func test_landed_hit_still_grants_invincibility() -> void:
	var w := RF.quiet_world(400.0, 618)
	w.drain_events()
	assert_between(w.take_hit(20.0, false, "", w.player.pos - Vector2(10, 0)), 17, 20)
	assert_eq(w.player_state.invincible_t, 1.5)
	assert_true(w.player.vel.x > 0.0, "the landed hit pushes away from the source")
	var hp := int(w.player_state.hp)
	w.drain_events()
	assert_eq(w.take_hit(82.0, false, "", w.player.pos), 0, "a second hit is rejected during invincibility")
	assert_eq(w.player_state.hp, hp)
	assert_true(w.drain_events().is_empty(), "rejected hits produce no damage or MISS event")
