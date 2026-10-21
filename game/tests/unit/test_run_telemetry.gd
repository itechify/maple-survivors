extends TestCase
## Frame retention is opt-in; synthetic samples verify automation statistics and mid-round overlay data.

const RF := preload("res://tests/fixtures/run_fixtures.gd")


func _run(options: Dictionary = {}) -> RunScene:
	var s := RunScene.new()
	s.configure("quiet", 27, options)
	s.world = RF.quiet_world()
	s._perf_canvas = Node2D.new()
	return s


func _free(s: RunScene) -> void:
	s._perf_canvas.free()
	s.free()


func test_ordinary_paused_play_does_not_retain_full_frame_history() -> void:
	var s := _run()
	s.paused = true
	for frame in 10060:
		s._record_frame(1000.0 / 164.0, 12)
	assert_eq(s.perf_summary().frames, 0, "full history requires an explicit output/perf request")
	s._perf_on = true
	s._record_frame(1000.0 / 164.0, 12)
	assert_true(s.perf_lines()[0].contains("6.10"), "F3 has recent frame data immediately")
	assert_eq(s.perf_summary().frames, 0, "toggling F3 does not enable unbounded retention")
	_free(s)


func test_explicit_recording_preserves_warmup_skip_and_summary_grouping() -> void:
	for options: Dictionary in [{"perf": true}, {"quit_after": 60.0}, {"shots_dir": "evidence/test"}]:
		var s := _run(options)
		for frame in 60:
			s._record_frame(99.0, 999)
		s._record_frame(10.0, 100)
		s.world.time = 60.0
		for mob in 200:
			RF.put_mob(s.world, 1110100, 800)
		s._record_frame(20.0, 200)
		var report := s.perf_summary()
		assert_eq(report.frames, 2)
		assert_eq(report.frame_ms, {"p50": 20.0, "p95": 20.0, "p99": 20.0, "max": 20.0, "avg": 15.0})
		assert_eq(report.frame_work_us, {"p50": 200.0, "p95": 200.0, "avg": 150.0})
		assert_eq(report.frame_ms_by_minute.size(), 2)
		assert_eq(report.frame_ms_by_minute[0].minute, 0)
		assert_eq(report.frame_ms_by_minute[1].alive_mean, 200)
		assert_eq(report.frame_ms_100plus.frames, 1)
		assert_eq(report.frame_ms_200plus.frames, 1)
		_free(s)
