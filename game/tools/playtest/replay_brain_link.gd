extends "res://tools/playtest/brain_link.gd"
## The in-process replay brain of the windowed replay (spec #91, ticket #100; scenes/debug/agent_replay.gd): answers
## each decide from a recorded run's decisions.jsonl, in order, with no pipe, no Jev and no key. It applies the checks
## of #98's Node replay brain (tools/playtest/src/core/replay.ts createReplayBrain, compareFingerprints; keep the two in
## step, messages included): the recorded decision at this position has the decide's id, kind, options in on-screen
## order ("same options in another order" is called out) and tick. After the first divergence it answers the decide's
## baseline, so the round still ends. `finish(applied)` adds a shortfall of decisions and the first applied answer that
## differs from the recording. A divergence is {message, decision?, field?}. Tool code only.

## The recorded decisions (decisions.jsonl lines, parsed), in order.
var recording: Array = []
var _asked := 0
var _found: Array = []


func _init(p_recording: Array = []) -> void:
	recording = p_recording
	mode = "replay"


## The recorded answer to `decide` (or its baseline once the replay has diverged), source "replay".
func ask(decide: Dictionary) -> Dictionary:
	var r: Variant = recording[_asked] if _asked < recording.size() else null
	_asked += 1
	if _found.is_empty():
		var problem := _check(decide, r)
		if problem != "":
			_found.append({"message": problem, "decision": int(decide.id)})
	if not _found.is_empty() or r == null:
		return {"id": int(decide.id), "answer": _baseline(decide), "source": "replay", "confidence": null}
	var c: Variant = r.get("confidence")
	return {"id": int(decide.id), "answer": String(r.answer), "source": "replay",
		"confidence": float(c) if c is float or c is int else null}


## Divergences seen while answering.
func divergences() -> Array:
	return _found.duplicate(true)


## Every divergence given the decisions the policy applied ([{id, answer, fallback_reason?}]): the ones seen while
## answering, a shortfall of decisions, and the first applied answer that differs from the recording.
func finish(applied: Array) -> Array:
	var out := _found.duplicate(true)
	if _found.is_empty() and applied.size() < recording.size():
		out.append({"message": "the replay made %d decisions, the recording has %d" % [applied.size(), recording.size()]})
	var by_id := {}
	for r: Dictionary in recording:
		by_id[int(r.get("id", -1))] = r
	for a: Dictionary in applied:
		var r: Variant = by_id.get(int(a.id))
		if r == null or String(r.answer) == String(a.answer):
			continue
		if _found.any(func(f: Dictionary) -> bool: return f.has("decision") and int(f.decision) <= int(a.id)):
			break
		var why := " (%s)" % String(a.fallback_reason) if a.has("fallback_reason") else ""
		out.append({"decision": int(a.id), "message": "decision %d: the driver applied %s, recorded %s%s" % [
			int(a.id), String(a.answer), String(r.answer), why]})
		break
	return out


## Fingerprint fields that differ between `recorded` (parsed fingerprint.json) and `replayed`, in the recorded field
## order, then fields only the replay has; numbers compare by value (5400.0 equals 5400).
static func compare_fingerprints(recorded: Dictionary, replayed: Dictionary) -> Array:
	var keys: Array = recorded.keys()
	for k: Variant in replayed:
		if not recorded.has(k):
			keys.append(k)
	var out: Array = []
	for k: Variant in keys:
		var a := canon(recorded.get(k)) if recorded.has(k) else "missing"
		var b := canon(replayed.get(k)) if replayed.has(k) else "missing"
		if a != b:
			out.append({"field": String(k), "message": "fingerprint.%s: replay %s, recorded %s" % [String(k), b, a]})
	return out


## JSON text of `v` with sorted keys and whole floats written as integers (how Node prints the parsed JSON).
static func canon(v: Variant) -> String:
	return JSON.stringify(_whole(v), "", true)


static func _whole(v: Variant) -> Variant:
	if v is float and is_finite(v) and v == floorf(v) and absf(v) < 1e15:
		return int(v)
	if v is Array:
		return (v as Array).map(func(x: Variant) -> Variant: return _whole(x))
	if v is Dictionary:
		var d := {}
		for k: Variant in v:
			d[k] = _whole(v[k])
		return d
	return v


static func _baseline(decide: Dictionary) -> String:
	var b: Variant = decide.get("baseline", {}).get("sensible")
	if b != null:
		return String(b)
	var options: Array = decide.get("options", [])
	return String(options[0].id) if not options.is_empty() else ""


## The first mismatch between `decide` and recorded decision `r`, or "".
func _check(decide: Dictionary, r: Variant) -> String:
	var id := int(decide.id)
	if r == null:
		return "decision %d (%s) is not in the recording (%d decisions)" % [id, String(decide.kind), recording.size()]
	if int(r.get("id", -1)) != id:
		return "decision %d: recorded decision at this position has id %d" % [id, int(r.get("id", -1))]
	if String(r.get("kind", "")) != String(decide.kind):
		return "decision %d: kind %s, recorded %s" % [id, String(decide.kind), String(r.get("kind", ""))]
	var ids: Array = decide.options.map(func(o: Dictionary) -> String: return String(o.id))
	var rec: Array = Array(r.get("options", [])).map(func(o: Variant) -> String: return _text(o))
	if ids != rec:
		var a := ids.duplicate()
		var b := rec.duplicate()
		a.sort()
		b.sort()
		return "decision %d: options [%s], recorded [%s]%s" % [id, ", ".join(ids), ", ".join(rec),
			" (same options in another order)" if a == b else ""]
	var rt: Variant = r.get("tick")
	if (rt is float or rt is int) and int(rt) != int(decide.tick):
		return "decision %d: tick %d, recorded %d" % [id, int(decide.tick), int(rt)]
	return ""


## An option id as text (job ids may be parsed as numbers).
static func _text(o: Variant) -> String:
	return str(int(o)) if o is float and o == floorf(o) else String(o) if o is String else str(o)
