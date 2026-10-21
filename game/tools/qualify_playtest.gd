extends SceneTree
## Opt-in playtest workload qualification. Reads summary.json only; never launches a round or writes player data.


func _init() -> void:
	var options := {}
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		if parts.size() == 2:
			options[parts[0]] = parts[1]
	var path := String(options.get("summary", ""))
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		printerr("[playtest] UNQUALIFIED: cannot read a summary object from " + path)
		quit(1)
		return
	var problems := errors(parsed, float(options.get("warp", 0.0)),
		int(options.get("min-frames-100", 1)), int(options.get("min-frames-200", 1)))
	if not problems.is_empty():
		printerr("[playtest] UNQUALIFIED: " + "; ".join(problems))
		quit(1)
		return
	print("[playtest] QUALIFIED: reached warp %.3f, %d ticks, %d frames at 100+ mobs, %d at 200+" % [
		float(parsed.warped_to), int(parsed.ticks), int(parsed.frame_ms_100plus.frames), int(parsed.frame_ms_200plus.frames)])
	quit()


## Reasons the capture did not reach the requested workload. Zero disables one density threshold, never both.
static func errors(summary: Dictionary, requested_warp: float, min_100: int, min_200: int) -> PackedStringArray:
	var out := PackedStringArray()
	if not is_finite(requested_warp) or requested_warp < 0.0:
		out.append("requested warp must be finite and non-negative")
	if min_100 < 0 or min_200 < 0 or (min_100 == 0 and min_200 == 0):
		out.append("density minima must be non-negative, with at least one positive")
	var warped: Variant = summary.get("warped_to")
	if not _number(warped) or float(warped) + 1e-6 < requested_warp:
		out.append("warp not reached (warped_to=%s, requested=%.3f)" % [warped, requested_warp])
	var ticks: Variant = summary.get("ticks")
	if not _number(ticks) or float(ticks) <= 0.0:
		out.append("no measured simulation ticks (ticks=%s)" % ticks)
	for threshold in [100, 200]:
		var group: Variant = summary.get("frame_ms_%dplus" % threshold)
		var frames: Variant = group.get("frames") if group is Dictionary else null
		var minimum := min_100 if threshold == 100 else min_200
		if not _number(frames) or float(frames) < minimum:
			out.append("%d+ mob frames=%s, require %d" % [threshold, frames, minimum])
	return out


static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= 0.0
