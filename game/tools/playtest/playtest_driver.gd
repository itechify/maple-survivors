extends SceneTree
## Headless agent playtest driver (spec #91, ticket #93): plays one round of a stage on the real map and asset cache
## through the headless run loop (balance_run.gd run_one, so the round record carries every balance metric) with the
## playtest run policy (playtest_policy.gd). Decisions go to a brain over the decision protocol
## (playtest_protocol.gd: "@@PT {json}" lines on stdout, one answer line per decide on stdin), or to the builtin
## baseline with --brain=builtin (no pipe). Started by the Node CLI (tools/playtest, scripts/agent_playtest.sh).
## Tool code only, never loaded by production scenes.
##
##   godot --headless --path game --script res://tools/playtest/playtest_driver.gd -- --stage=henesys_hg1 --seed=2026
##       [--minutes=3] [--brain=stdio|builtin] [--personality=sensible]
##
## --minutes caps the round's simulated time (TIMEOUT at the cap; 0 = the stage's own run_time_cap).
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
## Simulated seconds between progress log lines (the CLI's liveness timer counts any stdout line).
const PROGRESS_EVERY := 60.0


func _init() -> void:
	var stage := "henesys_hg1"
	var seed_value := 1
	var minutes := 0.0
	var brain := "stdio"
	var personality := "sensible"
	var personality_file := ""
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
	link.send(hello)
	var data := DataRepo.load_all()
	if not data.stages.stages.has(stage):
		_fail(link, "bad_args", "unknown stage %s" % stage)
		return
	if minutes > 0.0:
		data.balance["run_time_cap"] = minutes * 60.0 # harness cap, as balance_run.gd --cap; no data file changes
	var root := AssetCachePaths.resolve_cache_root()
	var missing := PackedStringArray()
	var setup := DataRepo.build_setup(data, stage, 0, Vector2(800, 600),
		func(p: String) -> Dictionary: return BR._json(root, p),
		func(id: int) -> Dictionary: return BR._json(root, "Mob.wz/%07d.img" % id), missing)
	if not missing.is_empty() or setup.get("map_img", {}).is_empty():
		_fail(link, "cache_missing", "the asset cache lacks %s for %s (root %s); run scripts/import.sh" % [
			missing, stage, root])
		return
	setup.seed = seed_value
	var world := RunWorld.new(setup)
	var start_character := world.character_snapshot()
	var policy := POLICY.new(link, seed_value)
	policy.configure(params)
	var progress := {"next": PROGRESS_EVERY}
	policy.observers.append(func(w: RunWorld, _events: Array) -> void:
		if w.time >= float(progress.next) - 1e-6:
			progress.next = float(progress.next) + PROGRESS_EVERY
			print("playtest_driver: %s Lv %d kills %d alive %d" % [BR._mmss(w.time + 1e-3), int(w.player_state.level), w.kills,
				w.swarm.alive_count()]))
	var record := BR.run_one(world, policy, seed_value, -1.0, 60.0, 0, policy.observe)
	record.merge({"seed": seed_value, "stage": stage, "policy": "playtest", "personality": personality,
		"start_character": start_character, "missing": [], "tactics": policy.tactic_summary()})
	record["motor"] = policy.motor_summary()
	for tier_index in data.stages.get("tiers", []).size():
		if stage in data.stages.tiers[tier_index]:
			record["tier"] = tier_index + 1
	var fingerprint := policy.fingerprint(world, record)
	link.send(PROTOCOL.end(record, fingerprint, policy.decisions, link.lost))
	print(BR.describe(record))
	quit(0)


## Reports an infrastructure error (protocol `error` message plus a log line) and exits with code 2.
func _fail(link: BRAIN_LINK, reason: String, message: String) -> void:
	link.send(PROTOCOL.error(reason, message))
	print("playtest_driver: %s: %s" % [reason, message])
	quit(2)
