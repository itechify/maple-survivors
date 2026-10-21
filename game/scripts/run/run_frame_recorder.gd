class_name RunFrameRecorder
extends RefCounted
## Scene-owned frame samples: complete automation history, bounded recent samples for an on-demand F3 overlay.

const WINDOW_SECONDS := 2.0
const WARMUP_FRAMES := 60
## tier C: diagnostic retention cap, including zero-delta frames; no gameplay effect.
const RECENT_CAPACITY := 2048

var full_history := false
var skip_frames := 0
var recent_ms := PackedFloat32Array()
var _recent_t := PackedFloat64Array()
var _wall := 0.0
var _frame_count := 0
var _frame_ms := PackedFloat32Array()
var _work_us := PackedFloat32Array()
var _frame_t := PackedFloat32Array()
var _frame_alive := PackedInt32Array()


## Records one drawn frame. Warmup and screenshot exclusions apply only to full-history statistics.
func record(frame_ms: float, work_us: int, sim_time: float, alive: int) -> void:
	_frame_count += 1
	_wall += frame_ms / 1000.0
	if skip_frames > 0:
		skip_frames -= 1
	elif full_history and _frame_count > WARMUP_FRAMES:
		_frame_ms.append(frame_ms)
		_work_us.append(float(work_us))
		_frame_t.append(sim_time)
		_frame_alive.append(alive)
	recent_ms.append(frame_ms)
	_recent_t.append(_wall)
	var cut := maxi(0, recent_ms.size() - RECENT_CAPACITY)
	while cut < _recent_t.size() and _recent_t[cut] < _wall - WINDOW_SECONDS:
		cut += 1
	if cut > 0:
		recent_ms = recent_ms.slice(cut)
		_recent_t = _recent_t.slice(cut)


## Automation's existing frame statistics and grouping, detached from retained samples.
func summary() -> Dictionary:
	var frames := _frame_ms.duplicate()
	frames.sort()
	var work := _work_us.duplicate()
	work.sort()
	return {"frames": frames.size(), "frame_ms": {"p50": percentile(frames, 0.5), "p95": percentile(frames, 0.95),
		"p99": percentile(frames, 0.99), "max": frames[frames.size() - 1] if not frames.is_empty() else 0.0,
		"avg": average(frames)}, "frame_work_us": {"p50": percentile(work, 0.5), "p95": percentile(work, 0.95),
		"avg": average(work)}, "frame_ms_by_minute": _by_minute(),
		"frame_ms_100plus": _where(100), "frame_ms_200plus": _where(200)}


func _by_minute() -> Array:
	var groups := {}
	for i in _frame_ms.size():
		var minute := int(_frame_t[i] / 60.0)
		if not groups.has(minute):
			groups[minute] = [PackedFloat32Array(), 0, 0]
		var group: Array = groups[minute]
		var values: PackedFloat32Array = group[0]
		values.append(_frame_ms[i])
		group[0] = values
		group[1] = int(group[1]) + _frame_alive[i]
		group[2] = maxi(int(group[2]), _frame_alive[i])
	var out: Array = []
	var keys := groups.keys()
	keys.sort()
	for minute: int in keys:
		var values: PackedFloat32Array = groups[minute][0]
		values.sort()
		out.append({"minute": minute, "frames": values.size(), "p50": percentile(values, 0.5),
			"p95": percentile(values, 0.95), "p99": percentile(values, 0.99), "max": values[values.size() - 1],
			"alive_mean": roundi(float(groups[minute][1]) / values.size()), "alive_max": groups[minute][2]})
	return out


func _where(min_alive: int) -> Dictionary:
	var values := PackedFloat32Array()
	for i in _frame_ms.size():
		if _frame_alive[i] >= min_alive:
			values.append(_frame_ms[i])
	values.sort()
	return {"frames": values.size(), "p50": percentile(values, 0.5), "p95": percentile(values, 0.95),
		"p99": percentile(values, 0.99), "max": values[values.size() - 1] if not values.is_empty() else 0.0}


## Existing percentile convention: floor(size * q), capped to the last sorted sample.
static func percentile(sorted: PackedFloat32Array, q: float) -> float:
	if sorted.is_empty():
		return 0.0
	return sorted[clampi(int(sorted.size() * q), 0, sorted.size() - 1)]


## Mean of samples, or zero for an empty capture.
static func average(values: PackedFloat32Array) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for value in values:
		total += value
	return total / values.size()
