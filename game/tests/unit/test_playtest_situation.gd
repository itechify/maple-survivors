extends TestCase
## The playtest situation builder (game/tools/playtest/playtest_situation.gd, spec #91 ticket #95): named buckets at
## their boundaries, and the buckets a constructed world reports (mobs near, drops near/above, a boss, recent hits).
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const SITUATION := preload("res://tools/playtest/playtest_situation.gd")
const DT := 1.0 / 60.0


func test_pool_buckets_at_their_boundaries() -> void:
	assert_eq(SITUATION.pool_bucket(0, 100), "critical")
	assert_eq(SITUATION.pool_bucket(24, 100), "critical")
	assert_eq(SITUATION.pool_bucket(25, 100), "low", "a quarter of the pool is low, not critical")
	assert_eq(SITUATION.pool_bucket(49, 100), "low")
	assert_eq(SITUATION.pool_bucket(50, 100), "ok", "half the pool is ok")
	assert_eq(SITUATION.pool_bucket(94, 100), "ok")
	assert_eq(SITUATION.pool_bucket(95, 100), "full", "95% counts as full")
	assert_eq(SITUATION.pool_bucket(100, 100), "full")
	assert_eq(SITUATION.pool_bucket(0, 0), "full", "an empty pool (no MP at all) is not in danger")


func test_count_buckets_at_their_boundaries() -> void:
	assert_eq([0, 1, 3, 4, 11, 12, 40].map(SITUATION.mobs_bucket),
		["none", "few", "few", "crowd", "crowd", "swarm", "swarm"])
	assert_eq([0, 1, 2, 3, 4, 5, 6, 7].map(SITUATION.mobs_step), [0, 1, 1, 1, 2, 2, 2, 2])
	assert_eq([0, 1, 4, 5, 20].map(SITUATION.potion_bucket), ["none", "few", "few", "plenty", "plenty"])
	assert_eq([0, 1, 5, 6].map(SITUATION.drops_bucket), ["none", "some", "some", "many"])
	assert_eq([0, 1, 2, 3].map(SITUATION.hits_bucket), ["none", "some", "some", "many"])


func test_phase_follows_the_stage_duration_and_bosses() -> void:
	assert_eq(SITUATION.phase_bucket(0.0, 900.0, false), "early")
	assert_eq(SITUATION.phase_bucket(299.9, 900.0, false), "early")
	assert_eq(SITUATION.phase_bucket(300.0, 900.0, false), "mid", "the first third of the stage is early")
	assert_eq(SITUATION.phase_bucket(600.0, 900.0, false), "late")
	assert_eq(SITUATION.phase_bucket(1200.0, 900.0, false), "late", "past the stage duration is still late")
	assert_eq(SITUATION.phase_bucket(10.0, 900.0, true), "boss", "a living boss makes it the boss phase")


func test_quiet_world_buckets() -> void:
	var w := RF.quiet_world(400.0, 11)
	var s := SITUATION.of(w)
	assert_true(s.has("level") and s.has("hp"), "the plain facts stay")
	var b: Dictionary = s.buckets
	for key: String in SITUATION.BUCKET_KEYS:
		assert_true(b.has(key), "bucket %s is always present" % key)
	assert_eq(String(b.hp), "full")
	assert_eq(String(b.mobs_near), "none")
	assert_eq(int(b.mobs_near_step), 0)
	assert_eq(String(b.boss), "none")
	assert_eq(String(b.drops_near), "none")
	assert_eq(String(b.drops_above), "none")
	assert_eq(String(b.phase), "early")
	assert_eq(String(b.recent_hits), "none", "no memory means no recent hits")
	assert_eq(int(b.platform), w.player_platform())


func test_constructed_world_buckets() -> void:
	var w := RF.quiet_world(400.0, 12)
	for x: float in [450.0, 500.0, 330.0, 560.0]:
		RF.put_mob(w, 100100, x)
	RF.put_mob(w, 100100, 1400.0) # far away: not near
	w.pickups.spawn(Vector2(600.0, 195.0), 5, 0)
	w.pickups.spawn(Vector2(420.0, 60.0), 5, 0) # on the platform above, out of magnet reach
	var b: Dictionary = SITUATION.of(w).buckets
	assert_eq(String(b.mobs_near), "crowd", "four mobs within reach are a crowd")
	assert_eq(String(b.drops_near), "some")
	assert_eq(String(b.drops_above), "some")
	var boss := RF.put_mob(w, 100100, 700.0)
	w.mob_boss[boss] = 0
	b = SITUATION.of(w).buckets
	assert_eq(String(b.boss), "present", "a living scheduled boss away from the player")
	assert_eq(String(b.phase), "boss")


func test_memory_counts_recent_hits_and_boss_attacks() -> void:
	var w := RF.quiet_world(400.0, 13)
	var memory := SITUATION.new()
	var hit := {"type": "player_hit", "miss": false, "boss": false}
	memory.observe(w, [hit, hit, {"type": "player_hit", "miss": true, "boss": false}])
	assert_eq(String(SITUATION.of(w, memory).buckets.recent_hits), "some", "two hits; a miss does not count")
	var boss := RF.put_mob(w, 100100, 900.0)
	w.mob_boss[boss] = 0
	memory.observe(w, [{"type": "player_hit", "miss": false, "boss": true}])
	var b: Dictionary = SITUATION.of(w, memory).buckets
	assert_eq(String(b.recent_hits), "many")
	assert_eq(String(b.boss), "attacking", "a boss that just hit the player is attacking")
	w.time += SITUATION.RECENT_S + 0.1
	b = SITUATION.of(w, memory).buckets
	assert_eq(String(b.recent_hits), "none", "hits older than the window are forgotten")
	assert_eq(String(b.boss), "present")
