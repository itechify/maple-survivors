extends Node
## Windowed replay of a recorded agent playtest (spec #91, ticket #100): plays the recorded round again in the real
## presentation layer (RunScene) with the playtest policy (tactic controller and the recording's personality.json motor
## params) and an in-process replay brain that answers from the recording's decisions.jsonl (replay_brain_link.gd: the
## checks of #98's Node replay), saves screenshots, then fingerprints the round and compares it with the recording.
## Started by `bash scripts/agent_playtest.sh --replay=<dir> --windowed` (tools/playtest/src/maple/windowed_replay.ts)
## or by hand:
##
##   ISOLATE=<name> bash scripts/run.sh res://scenes/debug/agent_replay.tscn -- --replay=<abs run dir> --out=<abs dir>
##       [--speed=4] [--shots-at=412.5,600] [--warp=<s>]
##
## Determinism: RunScene gets the policy through options.policy (move / choose / observe in run_one's batches), the
## headless driver's 800x600 logical view (options.view_size, and the window letterboxed to it), and stop_tick, which
## holds the sim at the round's tick cap (run_one's tick count) and at every screenshot tick, so a screenshot shows
## exactly that tick and --speed never changes which ticks run. --warp fast-forwards (nothing drawn) through the
## policy too; shots before it are skipped.
## Screenshots (out/shots/, 800x600): at_<t>s.png per --shots-at time, finding_<kind>_<t>s.png at each timed entry of
## the recording's findings.jsonl, final.png at a TIMEOUT, plus RunScene's own event shots (levelup_N, job_N,
## death_fall / death_land, clear, boss_*, window_*...). A shot needs a drawn frame: an occluded or minimized window
## draws none, and after SHOT_TIMEOUT real seconds the shot is recorded as skipped.
## Writes out/: fingerprint.json, decisions.jsonl (as applied), timeline.jsonl, replay.json (verdict: match,
## divergences with the first one first, the first timeline row that differs from the recording, view checks, shots).
## Exit code 0 match, 1 replay divergence, 2 infrastructure error (bad recording, asset cache missing). Tool code only.

const POLICY := preload("res://tools/playtest/playtest_policy.gd")
const LINK := preload("res://tools/playtest/replay_brain_link.gd")
const FINGERPRINT := preload("res://tools/playtest/playtest_fingerprint.gd")
const TIMELINE := preload("res://tools/playtest/playtest_timeline.gd")
const WINDOWED := preload("res://tools/playtest/windowed_replay.gd")
const DT := 1.0 / 60.0
## The headless driver's logical view (playtest_driver.gd builds its setup with it).
const VIEW := Vector2(800, 600)
## Real seconds to wait for a drawn frame before a screenshot counts as skipped.
const SHOT_TIMEOUT := 5.0
## Real seconds to wait for the run's end sequence (death / clear) after its last tick.
const END_TIMEOUT := 20.0
## Real seconds left for RunScene's pending event shots once the round is over.
const SETTLE := 1.5
## Run seconds between progress lines (the CLI's liveness timer counts any output line).
const PROGRESS_EVERY := 30.0

var run: RunScene
var policy: POLICY
var link: LINK
var fp: FINGERPRINT
## Writes timeline.jsonl (kept here: the policy holds only its observe Callable, not the object).
var timeline: TIMELINE
var out_dir := ""
var replay_dir := ""
var cap_tick := 0
var speed := 4
var warp := 0.0
## Pending screenshots by tick, ascending: [{tick, names: [..], reasons: [..]}].
var shots: Array = []
## Every planned screenshot with its outcome: [{name, reason, tick, time, saved, why?}].
var shot_log: Array = []
var view_mismatch_frames := 0
var _timeline_file: FileAccess
var _phase := "play" # play, capture, ending, settle, done
var _phase_t := 0
var _finished := false
## True once the round's last tick ran.
var _over := false
var _next_progress := PROGRESS_EVERY


func _ready() -> void:
	call_deferred("_start")


func _start() -> void:
	var args := SceneFlow.parse_flags(OS.get_cmdline_user_args())
	replay_dir = String(args.get("replay", "")).replace("\\", "/")
	if replay_dir == "" or replay_dir == "1":
		_infra("--replay=<recorded run directory> is required")
		return
	out_dir = String(args.get("out", replay_dir + "_windowed")).replace("\\", "/")
	speed = maxi(1, int(args.get("speed", "4")))
	warp = maxf(0.0, float(args.get("warp", "0")))
	DirAccess.make_dir_recursive_absolute(out_dir.path_join("shots"))
	var scenario: Variant = _json(replay_dir.path_join("scenario.json"))
	if not scenario is Dictionary or not (scenario as Dictionary).get("run") is Dictionary:
		_infra("%s has no scenario.json with the run's options (not a replayable run directory)" % replay_dir)
		return
	var r: Dictionary = scenario.run
	if int(r.get("tier", 1)) >= 2:
		_infra("the windowed replay plays one round; %s is a tier chain (replay it headless with --replay)" % replay_dir)
		return
	if not FileAccess.file_exists(replay_dir.path_join("decisions.jsonl")):
		_infra("%s has no decisions.jsonl" % replay_dir)
		return
	var stage := String(r.get("stage", "henesys_hg1"))
	var seed_value := int(r.get("seed", 1))
	var params: Variant = _json(replay_dir.path_join("personality.json"))
	link = LINK.new(_jsonl(replay_dir.path_join("decisions.jsonl")))
	policy = POLICY.new(link, seed_value)
	policy.configure(params if params is Dictionary else {})
	fp = FINGERPRINT.new()
	_timeline_file = FileAccess.open(out_dir.path_join("timeline.jsonl"), FileAccess.WRITE)
	timeline = TIMELINE.new(policy, func(line: String) -> void:
		if _timeline_file != null:
			_timeline_file.store_line(line))
	policy.observers.append(timeline.observe)
	policy.observers.append(fp.observe)
	cap_tick = WINDOWED.tick_cap(WINDOWED.cap_seconds(float(r.get("minutes", 0.0)), DataRepo.load_all().get("balance", {})))
	_plan_shots(String(args.get("shots-at", "")))
	_force_view()
	var options := {"use_flow": false, "autoplay": true, "autopick": true, "speed": speed, "policy": policy,
		"view_size": VIEW, "shots_dir": out_dir.path_join("shots"), "stop_tick": _next_stop(), "warp": warp}
	if r.get("character") is String and String(r.character) != "":
		options["character"] = String(r.character)
	print("agent_replay: replaying %s (%s seed %d, cap %d ticks, %d recorded decisions) at x%d -> %s" % [replay_dir,
		stage, seed_value, cap_tick, link.recording.size(), speed, out_dir])
	run = (load(RunScene.SCENE_PATH) as PackedScene).instantiate()
	run.configure(stage, seed_value, options)
	run.run_finished.connect(func(_s: Dictionary) -> void: _finished = true)
	add_child(run)
	if run.error != "":
		_infra("RunScene could not start: %s" % run.error)
		return
	for s: Dictionary in shots.duplicate():
		if int(s.tick) < roundi(run.world.time / DT):
			_log_shots(s, false, "before the warp time")
			shots.erase(s)
	run.stop_tick = _next_stop()


func _process(_delta: float) -> void:
	if run == null or run.world == null or _phase == "done":
		return
	var w := run.world
	if w.view_size != VIEW:
		view_mismatch_frames += 1
	var tick := roundi(w.time / DT)
	if w.time >= _next_progress:
		_next_progress += PROGRESS_EVERY
		print("agent_replay: %s Lv %d kills %d alive %d decisions %d" % [_clock(w.time), int(w.player_state.level), w.kills,
			w.swarm.alive_count(), policy.decisions.size()])
	match _phase:
		"play":
			var over := w.state == RunWorld.DEAD or w.state == RunWorld.CLEARED
			if not over and not shots.is_empty() and tick >= int(shots[0].tick):
				_capture(shots[0])
			elif over or tick >= cap_tick:
				_round_over()
		"capture":
			if (Time.get_ticks_msec() - _phase_t) / 1000.0 > SHOT_TIMEOUT:
				if RenderingServer.frame_post_draw.is_connected(_on_drawn):
					RenderingServer.frame_post_draw.disconnect(_on_drawn)
				print("agent_replay: no frame drawn within %.0f s (window occluded or minimized?): %s skipped" % [
					SHOT_TIMEOUT, ", ".join(shots[0].names)])
				_log_shots(shots.pop_front(), false, "no frame drawn (window occluded or minimized?)")
				_resume()
		"ending":
			if _finished or (Time.get_ticks_msec() - _phase_t) / 1000.0 > END_TIMEOUT:
				_phase = "settle"
				_phase_t = Time.get_ticks_msec()
		"settle":
			if (Time.get_ticks_msec() - _phase_t) / 1000.0 > SETTLE:
				_finish()


## Holds at the shot's tick (the sim is already held there by stop_tick) and saves the next drawn frame.
func _capture(_shot: Dictionary) -> void:
	_phase = "capture"
	_phase_t = Time.get_ticks_msec()
	RenderingServer.frame_post_draw.connect(_on_drawn, CONNECT_ONE_SHOT)


func _on_drawn() -> void:
	if _phase != "capture" or shots.is_empty():
		return
	var s: Dictionary = shots.pop_front()
	var img := get_viewport().get_texture().get_image()
	var saved := img != null and not img.is_empty()
	if saved:
		for n: String in s.names:
			img.save_png(out_dir.path_join("shots").path_join(n))
	_log_shots(s, saved, "" if saved else "empty viewport image")
	_resume()


func _resume() -> void:
	if _over:
		_phase = "settle"
		_phase_t = Time.get_ticks_msec()
		return
	_phase = "play"
	run.stop_tick = _next_stop()


## The last tick ran (cap, death or clear): a TIMEOUT saves final.png; a death or clear waits for RunScene's end
## sequence (its death / clear shots) and then for the pending event shots.
func _round_over() -> void:
	for s: Dictionary in shots:
		_log_shots(s, false, "after the round ended")
	shots.clear()
	_over = true
	if run.world.state == RunWorld.PLAYING:
		shots.append({"tick": roundi(run.world.time / DT), "names": ["final.png"], "reasons": ["end of the round (TIMEOUT)"]})
		_capture(shots[0]) # _resume then settles
		return
	_phase = "ending"
	_phase_t = Time.get_ticks_msec()


func _finish() -> void:
	_phase = "done"
	if _timeline_file != null:
		_timeline_file.close()
		_timeline_file = null
	var w := run.world
	policy.choose(w) # run_one's trailing choose
	var fingerprint := FINGERPRINT.of_round(policy, w, WINDOWED.round_record(w), fp)
	var recorded: Variant = _json(replay_dir.path_join("fingerprint.json"))
	var divs: Array = link.finish(policy.decisions)
	if recorded is Dictionary:
		divs.append_array(LINK.compare_fingerprints(recorded, fingerprint))
	else:
		divs.append({"message": "the recording has no fingerprint.json (its run sent no end)"})
	divs = order_divergences(divs)
	var timeline_diff := first_timeline_difference(_lines(replay_dir.path_join("timeline.jsonl")),
		_lines(out_dir.path_join("timeline.jsonl")))
	_write(out_dir.path_join("fingerprint.json"), JSON.stringify(fingerprint, "\t"))
	var f := FileAccess.open(out_dir.path_join("decisions.jsonl"), FileAccess.WRITE)
	for d: Dictionary in policy.decisions:
		f.store_line(JSON.stringify(d))
	f.close()
	var event_shots: Array = []
	var planned := {}
	for s: Dictionary in shot_log:
		planned[String(s.name)] = true
	for n in DirAccess.get_files_at(out_dir.path_join("shots")):
		if n.ends_with(".png") and not planned.has(n):
			event_shots.append(n)
	var verdict := {"match": divs.is_empty(), "first": String(divs[0].message) if not divs.is_empty() else "",
		"divergences": divs, "replay_of": replay_dir, "out": out_dir, "speed": speed, "warp": warp,
		"view_size": [VIEW.x, VIEW.y], "view_mismatch_frames": view_mismatch_frames,
		"window_size": [get_window().size.x, get_window().size.y], "cap_tick": cap_tick, "fingerprint": fingerprint,
		"decisions": policy.decisions.size(), "recorded_decisions": link.recording.size(),
		"first_timeline_difference": timeline_diff, "shots": shot_log, "event_shots": event_shots}
	_write(out_dir.path_join("replay.json"), JSON.stringify(verdict, "\t"))
	if divs.is_empty():
		print("agent_replay: match (%d decisions, every fingerprint field identical); %d screenshots in %s" % [
			policy.decisions.size(), shot_log.filter(func(s: Dictionary) -> bool: return s.saved).size() + event_shots.size(),
			out_dir.path_join("shots")])
	else:
		print("agent_replay: replay_divergence: %s (%d divergences; first timeline difference %s)" % [verdict.first,
			divs.size(), JSON.stringify(timeline_diff)])
	get_tree().quit(0 if divs.is_empty() else 1)


## Divergences in report order (tools/playtest/src/core/replay.ts orderDivergences): decision ones by decision id,
## then the others in their order.
static func order_divergences(divs: Array) -> Array:
	var by_decision := divs.filter(func(d: Dictionary) -> bool: return d.has("decision"))
	by_decision.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.decision) < int(b.decision))
	return by_decision + divs.filter(func(d: Dictionary) -> bool: return not d.has("decision"))


## The first timeline.jsonl row that differs between the recording and the replay: {row, time, tick, fields: {name:
## [recorded, replayed]}}, {row, missing: "recorded" | "replayed"} when one is shorter, or {} when they agree.
static func first_timeline_difference(recorded: PackedStringArray, replayed: PackedStringArray) -> Dictionary:
	for i in maxi(recorded.size(), replayed.size()):
		if i >= recorded.size() or i >= replayed.size():
			return {"row": i + 1, "missing": "recorded" if i >= recorded.size() else "replayed"}
		if recorded[i] == replayed[i]:
			continue
		var a: Variant = JSON.parse_string(recorded[i])
		var b: Variant = JSON.parse_string(replayed[i])
		if not (a is Dictionary and b is Dictionary):
			return {"row": i + 1, "fields": {"line": [recorded[i], replayed[i]]}}
		var fields := {}
		for k: Variant in a:
			if LINK.canon(a.get(k)) != LINK.canon(b.get(k)):
				fields[k] = [a.get(k), b.get(k)]
		if fields.is_empty():
			continue
		return {"row": i + 1, "time": a.get("time"), "tick": a.get("tick"), "fields": fields}
	return {}


## Letterboxes the window to the 800x600 logical view (the headless driver's), whatever its size or the player's
## fill_window setting (changed in memory only; settings are saved only by their setters).
func _force_view() -> void:
	var settings := get_node_or_null("/root/Settings")
	if settings != null:
		settings.set("fill_window", false)
	var root := get_tree().root
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	root.content_scale_size = Vector2i(VIEW)
	if settings != null and settings.has_method("fit_viewport"):
		settings.call("fit_viewport")


## Plans the screenshots: each --shots-at time and each timed finding of the recording, grouped by tick.
func _plan_shots(shots_at: String) -> void:
	var by_tick := {}
	var add := func(tick: int, name: String, reason: String) -> void:
		if not by_tick.has(tick):
			by_tick[tick] = {"tick": tick, "names": [], "reasons": []}
		by_tick[tick].names.append(name)
		by_tick[tick].reasons.append(reason)
	for part in shots_at.split(",", false):
		if part.strip_edges().is_valid_float():
			var t := float(part)
			add.call(roundi(t / DT), "at_%ss.png" % _num(t), "--shots-at %s" % _num(t))
	for finding: Variant in _jsonl(replay_dir.path_join("findings.jsonl")):
		if finding is Dictionary and (finding.get("time") is float or finding.get("tick") is float):
			var tick := int(finding.tick) if finding.get("tick") is float else roundi(float(finding.time) / DT)
			var kind := String(finding.get("kind", "finding")).validate_filename()
			add.call(tick, "finding_%s_%ss.png" % [kind, _num(tick * DT)], "finding %s: %s" % [kind,
				String(finding.get("message", "")).left(160)])
	var ticks := by_tick.keys()
	ticks.sort()
	for t: int in ticks:
		if t > cap_tick:
			_log_shots(by_tick[t], false, "after the time cap")
		else:
			shots.append(by_tick[t])


func _next_stop() -> int:
	return mini(int(shots[0].tick), cap_tick) if not shots.is_empty() else cap_tick


func _log_shots(s: Dictionary, saved: bool, why: String) -> void:
	for i in s.names.size():
		var e := {"name": s.names[i], "reason": s.reasons[i], "tick": int(s.tick), "time": snappedf(int(s.tick) * DT, 0.001),
			"saved": saved}
		if why != "":
			e["why"] = why
		shot_log.append(e)


func _infra(message: String) -> void:
	print("agent_replay: error: %s" % message)
	if out_dir != "":
		DirAccess.make_dir_recursive_absolute(out_dir)
		_write(out_dir.path_join("replay.json"), JSON.stringify({"error": message, "replay_of": replay_dir}, "\t"))
	_phase = "done"
	get_tree().quit(2)


static func _num(t: float) -> String:
	return str(roundi(t)) if absf(t - roundf(t)) < 1e-6 else str(snappedf(t, 0.001))


static func _clock(t: float) -> String:
	return "%d:%02d" % [int(t / 60.0), int(t) % 60]


static func _json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var j := JSON.new()
	return j.data if j.parse(FileAccess.get_file_as_string(path)) == OK else null


static func _lines(path: String) -> PackedStringArray:
	if not FileAccess.file_exists(path):
		return PackedStringArray()
	return FileAccess.get_file_as_string(path).split("\n", false)


static func _jsonl(path: String) -> Array:
	var out: Array = []
	for line in _lines(path):
		var j := JSON.new()
		if line.strip_edges() != "" and j.parse(line) == OK:
			out.append(j.data)
	return out


static func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(text + "\n")
		f.close()
