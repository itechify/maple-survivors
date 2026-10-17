extends SceneTree
## Headless agent playtest driver (spec #91, ticket #93): plays one round of a stage on the real map and asset cache
## through the headless run loop (balance_run.gd run_one, so the round record carries every balance metric) with the
## playtest run policy (playtest_policy.gd). Decisions go to a brain over the decision protocol
## (playtest_protocol.gd: "@@PT {json}" lines on stdout, one answer line per decide on stdin), or to the builtin
## baseline with --brain=builtin (no pipe). Started by the Node CLI (tools/playtest, scripts/agent_playtest.sh).
## Tool code only, never loaded by production scenes.
##
##   godot --headless --path game --script res://tools/playtest/playtest_driver.gd -- --stage=henesys_hg1 --seed=2026
##       [--minutes=3] [--brain=stdio|builtin] [--personality=sensible] [--out=<abs dir>]
##       [--stuck-px=24] [--stuck-s=20] [--inject-finding=<kind>] [--character=<abs json>] [--tier=N]
##
## --character starts the round from a CharacterSnapshot (DataRepo.load_character, as balance_run.gd). --tier=N (>= 2)
## plays a chain from tier 1 (--stage) through tier N (playtest_chain.gd over balance_run.gd run_chain; not with
## --character); the record then has rounds[] and timeline rows carry "tier". Both are echoed in hello. The `end`
## fingerprint (playtest_fingerprint.gd) adds the job and a hash of the per-second timeline, for exact replays (#98).
##
## --minutes caps the round's simulated time (TIMEOUT at the cap; 0 = the stage's own run_time_cap).
## Deterministic invariants (playtest_invariants.gd) watch every tick and decision; each new finding is streamed as a
## protocol `finding` line and the de-duplicated list rides in `end`. --out writes timeline.jsonl (one row per run
## second, playtest_timeline.gd) and hits.jsonl (one line per landed player hit, #99) into that directory. --stuck-px / --stuck-s set the stuck detector's box and window.
## --inject-finding (test only) reports one finding of that kind at INJECT_AT run seconds, to show the reporting path
## end to end. Missing assets at setup: when the round can still be built (the map is there), each missing entry is a
## deterministic `missing_asset` finding on the first tick and the record lists them under `missing`; a round that
## cannot start at all (no cache root, no map) stays an infrastructure error (`error` cache_missing, exit 2).
## Movement follows the policy's tactic (tactic decisions over the same protocol, #95); the round record gains
## `tactics` (playtest_policy.gd tactic_summary: seconds, shares, switches, decisions, triggers, log).
## --personality-file=<abs json> (#97) holds the personality's driver params ({name, tactics, motor}; the CLI writes
## personality.json into the run directory): PlaytestPolicy.configure applies them, hello echoes them as
## `personality_params`, and the record gains `motor` (motor_noise.gd summary). Without it: kite-capable defaults
## (all tactics, quiet motor).
## Exit code 0 after `end`; 2 after an `error` message (bad arguments, asset cache missing).

const PROTOCOL := preload("res://tools/playtest/playtest_protocol.gd")
const POLICY := preload("res://tools/playtest/playtest_policy.gd")
const BRAIN_LINK := preload("res://tools/playtest/brain_link.gd")
const STDIO_LINK := preload("res://tools/playtest/stdio_brain_link.gd")
const BR := preload("res://tools/balance_run.gd")
const INVARIANTS := preload("res://tools/playtest/playtest_invariants.gd")
const TIMELINE := preload("res://tools/playtest/playtest_timeline.gd")
const FINGERPRINT := preload("res://tools/playtest/playtest_fingerprint.gd")
const CHAIN := preload("res://tools/playtest/playtest_chain.gd")
## tier C: simulated seconds between progress log lines (the CLI's liveness timer counts any stdout line).
const PROGRESS_EVERY := 60.0
## tier C: run time (s) of the --inject-finding finding.
const INJECT_AT := 10.0


func _init() -> void:
	var stage := "henesys_hg1"
	var seed_value := 1
	var minutes := 0.0
	var brain := "stdio"
	var personality := "sensible"
	var personality_file := ""
	var out_dir := ""
	var character_file := ""
	var tier := 1
	var checks := {"inject_at": INJECT_AT}
	var bad := PackedStringArray()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--stage="):
			stage = a.substr(8)
		elif a.begins_with("--seed=") and a.substr(7).is_valid_int():
			seed_value = int(a.substr(7))
		elif a.begins_with("--minutes=") and a.substr(10).is_valid_float():
			minutes = float(a.substr(10))
		elif a.begins_with("--brain="):
			brain = a.substr(8)
		elif a.begins_with("--personality="):
			personality = a.substr(14)
		elif a.begins_with("--personality-file="):
			personality_file = a.substr(19)
		elif a.begins_with("--out="):
			out_dir = a.substr(6)
		elif a.begins_with("--stuck-px=") and a.substr(11).is_valid_float():
			checks.stuck_px = float(a.substr(11))
		elif a.begins_with("--stuck-s=") and a.substr(10).is_valid_float():
			checks.stuck_s = float(a.substr(10))
		elif a.begins_with("--inject-finding=") and a.substr(17) in INVARIANTS.KINDS:
			checks.inject = a.substr(17)
		elif a.begins_with("--character="):
			character_file = a.substr(12)
		elif a.begins_with("--tier=") and a.substr(7).is_valid_int():
			tier = int(a.substr(7))
		else:
			bad.append(a)
	if brain not in ["stdio", "builtin"]:
		bad.append("--brain=" + brain)
	var link: BRAIN_LINK = STDIO_LINK.new() if brain == "stdio" else BRAIN_LINK.new()
	if not bad.is_empty():
		_fail(link, "bad_args", "unknown or malformed arguments: %s" % ", ".join(bad))
		return
	var params := {}
	if personality_file != "":
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(personality_file))
		if not parsed is Dictionary:
			_fail(link, "bad_args", "--personality-file=%s is not a JSON object" % personality_file)
			return
		params = parsed
	var hello := PROTOCOL.hello(stage, seed_value, minutes, personality, link.mode)
	hello["personality_params"] = params
	hello.merge({"tier": tier, "character": character_file})
	link.send(hello)
	var data := DataRepo.load_all()
	if not data.stages.stages.has(stage):
		_fail(link, "bad_args", "unknown stage %s" % stage)
		return
	if minutes > 0.0:
		data.balance["run_time_cap"] = minutes * 60.0 # harness cap, as balance_run.gd --cap; no data file changes
	var stages := _chain_stages(data, stage, tier, character_file)
	if stages.is_empty():
		_fail(link, "bad_args", "--tier=%d needs a tier-1 --stage and 2..%d tiers, and cannot be combined with --character" % [
			tier, data.stages.get("tiers", []).size()])
		return
	var character := {}
	if character_file != "":
		var errors := PackedStringArray()
		character = DataRepo.load_character(character_file, errors)
		if not errors.is_empty():
			_fail(link, "bad_args", "--character: " + "; ".join(errors))
			return
	var root := AssetCachePaths.resolve_cache_root()
	var setups: Array = []
	var missing_by_round: Array = []
	for stage_key: String in stages:
		var missing := PackedStringArray()
		var stage_setup := DataRepo.build_setup(data, stage_key, 0, Vector2(800, 600),
			func(p: String) -> Dictionary: return BR._json(root, p),
			func(id: int) -> Dictionary: return BR._json(root, "Mob.wz/%07d.img" % id), missing)
		var problem := setup_error(stage_setup, missing)
		if problem != "": # no cache at the root, or no map in it: the round cannot start
			_fail(link, "cache_missing", "the asset cache lacks %s for %s (root %s): %s; run scripts/import.sh" % [
				missing, stage_key, root, problem])
			return
		setups.append(stage_setup)
		missing_by_round.append(missing)
	if stages.size() > 1:
		_play_chain(link, setups, seed_value, stage, personality, checks, out_dir, params, missing_by_round)
		return
	var setup: Dictionary = setups[0]
	if character_file != "":
		setup.character = character
	setup.seed = seed_value
	var world := RunWorld.new(setup)
	var start_character := world.character_snapshot()
	var policy := POLICY.new(link, seed_value)
	policy.configure(params)
	checks["missing"] = missing_by_round[0]
	var invariants := INVARIANTS.new(policy, checks, func(f: Dictionary) -> void: link.send(PROTOCOL.finding(f)))
	invariants.attach(policy)
	var timeline_file: FileAccess = null
	if out_dir != "":
		timeline_file = FileAccess.open(out_dir.path_join("timeline.jsonl"), FileAccess.WRITE)
		if timeline_file == null:
			_fail(link, "bad_args", "cannot write %s (%s)" % [out_dir.path_join("timeline.jsonl"),
				error_string(FileAccess.get_open_error())])
			return
	var hits_file := _open_hits(out_dir)
	var timeline := TIMELINE.new(policy, func(line: String) -> void:
		if timeline_file != null:
			timeline_file.store_line(line),
		func(line: String) -> void:
			if hits_file != null:
				hits_file.store_line(line))
	policy.observers.append(timeline.observe)
	var fp := FINGERPRINT.new()
	policy.observers.append(fp.observe)
	policy.observers.append(_progress_observer())
	var record := BR.run_one(world, policy, seed_value, -1.0, 60.0, 0, policy.observe)
	record.merge({"seed": seed_value, "stage": stage, "policy": "playtest", "personality": personality,
		"start_character": start_character, "missing": Array(missing_by_round[0]), "tactics": policy.tactic_summary()})
	record["motor"] = policy.motor_summary()
	for tier_index in data.stages.get("tiers", []).size():
		if stage in data.stages.tiers[tier_index]:
			record["tier"] = tier_index + 1
	if timeline_file != null:
		timeline_file.close()
	if hits_file != null:
		hits_file.close()
	var fingerprint := FINGERPRINT.of_round(policy, world, record, fp)
	link.send(PROTOCOL.end(record, fingerprint, policy.decisions, link.lost, invariants.results()))
	print(BR.describe(record))
	quit(0)


## Why a built round setup cannot be played at all ("" when it can): no map image. Other entries of `missing`
## (DataRepo.build_setup's failed lookups: a mob, a skill image, a potion icon) leave a playable round; the driver
## reports them as missing_asset findings instead.
static func setup_error(stage_setup: Dictionary, missing: PackedStringArray) -> String:
	if stage_setup.get("map_img", {}).is_empty():
		var maps := Array(missing).filter(func(m: String) -> bool: return m.begins_with("Map.wz/"))
		return "no map image%s" % (" (%s)" % ", ".join(maps) if not maps.is_empty() else "")
	return ""


## The stages to play: [stage] for one round, or tier 1's `stage` then the first stage of each later tier through
## `tier` (balance_run.gd's chain rule); [] when the chain is invalid (stage not in tier 1, tier out of range, or a
## character fixture with a chain).
static func _chain_stages(data: Dictionary, stage: String, tier: int, character_file: String) -> Array:
	if tier <= 1:
		return [stage]
	var tiers: Array = data.stages.get("tiers", [])
	if tier > tiers.size() or character_file != "" or stage not in tiers[0]:
		return []
	var stages: Array = [stage]
	for tier_index in range(1, tier):
		stages.append(String(tiers[tier_index][0]))
	return stages


## A per-tick observer printing a progress line every PROGRESS_EVERY simulated seconds (each round counts from 0).
func _progress_observer() -> Callable:
	var progress := {"next": PROGRESS_EVERY}
	return func(w: RunWorld, _events: Array) -> void:
		if w.time < float(progress.next) - PROGRESS_EVERY - 1e-6:
			progress.next = PROGRESS_EVERY # a new round of a chain started
		if w.time >= float(progress.next) - 1e-6:
			progress.next = float(progress.next) + PROGRESS_EVERY
			print("playtest_driver: %s Lv %d kills %d alive %d" % [BR._mmss(w.time + 1e-3), int(w.player_state.level), w.kills,
				w.swarm.alive_count()])


## Plays a tier chain (playtest_chain.gd) and sends its `end`: the chain record (rounds[] plus the last round's outcome
## at the top level), the chain fingerprint, every round's decisions and findings. Timeline rows carry "tier".
func _play_chain(link: BRAIN_LINK, setups: Array, seed_value: int, stage: String, personality: String, checks: Dictionary,
		out_dir: String, params: Dictionary = {}, missing_by_round: Array = []) -> void:
	var timeline_file: FileAccess = null
	if out_dir != "":
		timeline_file = FileAccess.open(out_dir.path_join("timeline.jsonl"), FileAccess.WRITE)
		if timeline_file == null:
			_fail(link, "bad_args", "cannot write %s (%s)" % [out_dir.path_join("timeline.jsonl"),
				error_string(FileAccess.get_open_error())])
			return
	var chain := CHAIN.new(link, checks, func(f: Dictionary) -> void: link.send(PROTOCOL.finding(f)),
		func(line: String) -> void:
			if timeline_file != null:
				timeline_file.store_line(line))
	var hits_file := _open_hits(out_dir)
	chain.write_hits = func(line: String) -> void:
		if hits_file != null:
			hits_file.store_line(line)
	chain.extra_observers.append(_progress_observer())
	chain.policy_setup = func(p: Object) -> void: p.configure(params) # the personality applies in every round (#97)
	chain.missing_by_round = missing_by_round
	var result := chain.play(setups, seed_value)
	if timeline_file != null:
		timeline_file.close()
	if hits_file != null:
		hits_file.close()
	var record: Dictionary = result.record
	var missing: Array = []
	for m: PackedStringArray in missing_by_round:
		for entry: String in m:
			if entry not in missing:
				missing.append(entry)
	record.merge({"seed": seed_value, "stage": stage, "personality": personality, "missing": missing,
		"tier": setups.size()}, true)
	for i in record.rounds.size():
		record.rounds[i]["personality"] = personality
		record.rounds[i]["motor"] = chain.policies[i].motor_summary()
	link.send(PROTOCOL.end(record, result.fingerprint, result.decisions, link.lost, result.findings))
	print(BR.describe(record))
	quit(0)


## hits.jsonl in `out_dir` opened for writing (#99: one line per landed player hit), or null without --out.
static func _open_hits(out_dir: String) -> FileAccess:
	return FileAccess.open(out_dir.path_join("hits.jsonl"), FileAccess.WRITE) if out_dir != "" else null


## Reports an infrastructure error (protocol `error` message plus a log line) and exits with code 2.
func _fail(link: BRAIN_LINK, reason: String, message: String) -> void:
	link.send(PROTOCOL.error(reason, message))
	print("playtest_driver: %s: %s" % [reason, message])
	quit(2)
