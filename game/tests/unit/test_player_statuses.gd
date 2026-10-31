extends TestCase
## The shared status seam (PlayerStatuses, #456): timed statuses as plain data with the lockout floor.


func test_a_status_is_active_for_exactly_its_time() -> void:
	var s := PlayerStatuses.new()
	assert_true(s.apply(123, 10.0, 2.0, {"visual": "v"}))
	assert_true(s.is_active(123, 10.0))
	assert_true(s.is_active(123, 11.99))
	assert_false(s.is_active(123, 12.0))
	assert_eq(s.state(123, 11.0), {"skill_id": 123, "remaining": 1.0, "visual": "v"})
	assert_eq(s.state(123, 12.0), {})
	assert_false(s.is_active(126, 11.0), "statuses are keyed by id")


func test_lockout_is_the_longer_of_the_floor_and_the_time() -> void:
	var s := PlayerStatuses.new()
	assert_eq(s.lockout_seconds(123, 2.0), 4.0, "default floor 4 s")
	assert_eq(s.lockout_seconds(123, 9.0), 9.0, "its own time when longer")
	var rules := PlayerStatuses.new({"default": 6, "123": 10})
	assert_eq(rules.lockout_seconds(123, 2.0), 10.0, "per-status override")
	assert_eq(rules.lockout_seconds(124, 2.0), 6.0, "configured default")


func test_a_locked_status_neither_refreshes_nor_stacks() -> void:
	var s := PlayerStatuses.new()
	assert_true(s.apply(123, 0.0, 3.0, {"visual": "a"}))
	assert_false(s.apply(123, 1.0, 3.0, {"visual": "b"}), "refused while active")
	assert_eq(s.state(123, 1.0).visual, "a")
	assert_near(float(s.state(123, 1.0).remaining), 2.0, 1e-9, "the end time did not move")
	assert_true(s.is_locked(123, 5.0), "locked after it ends")
	assert_false(s.apply(123, 6.9, 3.0), "still inside max(4, 3) s after the end at 3 s")
	assert_true(s.apply(123, 7.0, 3.0), "free again at end + lockout")


func test_lockout_holds_per_status() -> void:
	var s := PlayerStatuses.new()
	s.apply(123, 0.0, 2.0)
	assert_true(s.apply(124, 1.0, 2.0), "another status is unaffected")
	assert_true(s.is_locked(123, 5.0))


func test_without_lockout_a_recast_overwrites_like_slow() -> void:
	var s := PlayerStatuses.new()
	assert_true(s.apply(126, 0.0, 15.0, {"multiplier": 0.8}, false))
	assert_true(s.apply(126, 5.0, 15.0, {"multiplier": 0.5}, false), "recast while active is taken")
	assert_eq(s.field(126, 6.0, "multiplier", 1.0), 0.5)
	assert_true(s.is_active(126, 19.0), "the new end time, 20 s")
	assert_false(s.is_locked(126, 20.0), "no immunity afterwards")
	assert_eq(s.field(126, 25.0, "multiplier", 1.0), 1.0, "fallback once expired")


func test_clear_ends_a_status_but_not_its_immunity() -> void:
	var s := PlayerStatuses.new()
	s.apply(123, 0.0, 3.0)
	s.clear(123)
	assert_false(s.is_active(123, 1.0))
	assert_true(s.is_locked(123, 1.0))
