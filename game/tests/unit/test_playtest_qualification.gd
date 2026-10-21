extends TestCase
## Qualification checks artifact coverage, independently of a game window, timing values or actual survival balance.

const Q := preload("res://tools/qualify_playtest.gd")


func test_early_death_artifacts_cannot_qualify_as_dense_performance_windows() -> void:
	for death_time in [259.383, 47.517, 47.517]:
		var problems := Q.errors({"warped_to": death_time, "ticks": 0,
			"frame_ms_100plus": {"frames": 0}, "frame_ms_200plus": {"frames": 0}}, 600, 30, 20)
		assert_eq(problems.size(), 4, "warp, ticks and both density counts fail independently")


func test_live_fixture_coverage_qualifies_and_density_minima_are_configurable() -> void:
	var report := {"warped_to": 600.0, "ticks": 1800,
		"frame_ms_100plus": {"frames": 300}, "frame_ms_200plus": {"frames": 100}}
	assert_eq(Q.errors(report, 600.0, 300, 100), PackedStringArray())
	assert_eq(Q.errors(report, 600.0, 301, 0).size(), 1)
	assert_eq(Q.errors(report, 600.0, 0, 101).size(), 1)
	assert_eq(Q.errors(report, 600.0, 0, 0).size(), 1, "one density requirement must stay enabled")
	report.ticks = 0
	assert_eq(Q.errors(report, 600.0, 1, 1).size(), 1, "dense frozen end presentation cannot qualify")


func test_missing_or_nonfinite_fields_fail_closed() -> void:
	assert_eq(Q.errors({}, 600, 1, 1).size(), 4)
	var report := {"warped_to": NAN, "ticks": INF,
		"frame_ms_100plus": {"frames": "100"}, "frame_ms_200plus": {"frames": -1}}
	assert_eq(Q.errors(report, 600, 1, 1).size(), 4)
