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
	assert_true(s._frames.recent_ms.size() <= RunFrameRecorder.RECENT_CAPACITY)
	for frame in 10060:
		s._frames.record(0.0, 0, s.world.time, 0)
	assert_eq(s._frames.recent_ms.size(), RunFrameRecorder.RECENT_CAPACITY, "zero-delta samples also stay bounded")
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
		s._frames.skip_frames = 2
		for frame in 2:
			s._record_frame(999.0, 9999)
		assert_eq(s.perf_summary(), report, "screenshot exclusions preserve all retained statistics")
		_free(s)


func test_summary_reports_the_meters_held_units_only_when_the_job_has_a_meter() -> void:
	var plain := _run()
	assert_false(plain.perf_summary().has("meter"), "no meter, no entry (F/P's summary is as before)")
	_free(plain)
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["212"]["meter"] = {"id": "meso_charge", "max": 10,
		"gain": {"event": "meso_picked", "amount": 1, "per_mesos": 1000}, "per_unit": {"stat": "damage", "value": 0.03}}
	var s := RunScene.new()
	s.configure("quiet", 27, {})
	s.world = RunWorld.new(RF.setup("quiet", 27, data))
	RF.place_player(s.world, 400)
	s._perf_canvas = Node2D.new()
	s.world.meter.gain_amount("meso_picked", 4000, s.world.events)
	for tick in 120:
		s.world.step(1.0 / 60.0, MoveInput.new())
	var stats: Dictionary = s.perf_summary().meter
	assert_eq(stats.peak, 4)
	assert_near(float(stats.mean), 4.0, 1e-6)
	_free(s)
