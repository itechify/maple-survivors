extends RefCounted
## The run fingerprint a replay compares (spec #91, ticket #98). A run loop observer hashes one sample per
## playtest_timeline.gd row (same cadence: every EVERY_S of run time) of the tier, tick, HP, level and the position
## rounded to whole pixels; `of_round` / `of_chain` build fingerprint.json's fields: total ticks, final state, time,
## level, job, kills, card ids taken in order, a hash of the decision answers and the timeline hash (a chain adds
## per-round entries). Read-only. Tool code only.

const TIMELINE := preload("res://tools/playtest/playtest_timeline.gd")
const DT := 1.0 / 60.0

## Samples hashed so far (equals the timeline's row count over the same rounds).
var samples := 0
## Ticks per round (the last observed tick of each round's world).
var round_ticks: Array = [0]
var _ctx := HashingContext.new()
var _next := TIMELINE.EVERY_S
var _digest := ""


func _init() -> void:
	_ctx.start(HashingContext.HASH_SHA256)


## The run loop observer: hashes a sample whenever another EVERY_S of run time has passed (as playtest_timeline.gd).
func observe(w: RunWorld, _events: Array) -> void:
	round_ticks[round_ticks.size() - 1] = roundi(w.time / DT)
	if w.time < _next - 1e-6:
		return
	while _next <= w.time + 1e-6:
		_next += TIMELINE.EVERY_S
	samples += 1
	var p := w.player.pos
	var line := "%d,%d,%d,%d,%d,%d\n" % [round_ticks.size(), roundi(w.time / DT), int(w.player_state.get("hp", 0)),
		int(w.player_state.get("level", 0)), roundi(p.x), roundi(p.y)]
	_ctx.update(line.to_utf8_buffer())


## Starts the next round of a chain (its world's time starts again at 0).
func next_round() -> void:
	round_ticks.append(0)
	_next = TIMELINE.EVERY_S


## The hex sha256 of every sample so far (final: call once all rounds are over).
func timeline_sha256() -> String:
	if _digest == "":
		_digest = _ctx.finish().hex_encode()
	return _digest


## sha256 of the applied decision answers ("kind:answer" in order), as playtest_policy.gd `fingerprint`.
static func answers_sha256(decisions: Array) -> String:
	var answers: Array = decisions.map(func(d: Dictionary) -> String: return "%s:%s" % [d.kind, d.answer])
	return JSON.stringify(answers).sha256_text()


## The fingerprint of one round: playtest_policy.gd `fingerprint` plus the job and the timeline hash of `fp`.
static func of_round(policy: Object, w: RunWorld, record: Dictionary, fp: Object) -> Dictionary:
	var out: Dictionary = policy.fingerprint(w, record)
	out["job"] = int(record.get("job", 0))
	out["timeline_sha256"] = fp.timeline_sha256()
	return out


## The fingerprint of a chain: the last round's outcome, ticks summed over the rounds, every card taken, the hash of
## every decision answer, the timeline hash, and per round {tier, stage, state, ticks, level, job, kills}.
static func of_chain(record: Dictionary, decisions: Array, fp: Object) -> Dictionary:
	var rounds: Array = record.get("rounds", [])
	var last: Dictionary = rounds[rounds.size() - 1] if not rounds.is_empty() else {}
	var per_round: Array = []
	var ticks := 0
	for i in rounds.size():
		var r: Dictionary = rounds[i]
		var t := int(fp.round_ticks[i]) if i < fp.round_ticks.size() else 0
		ticks += t
		per_round.append({"tier": int(r.get("tier", i + 1)), "stage": String(r.get("stage", "")), "state": String(r.get("state", "")),
			"ticks": t, "level": int(r.get("level", 0)), "job": int(r.get("job", 0)), "kills": int(r.get("kills", 0))})
	return {"ticks": ticks, "state": String(last.get("state", "")), "time": last.get("time", 0.0),
		"level": int(last.get("level", 0)), "job": int(last.get("job", 0)), "kills": int(last.get("kills", 0)),
		"cards_taken": record.get("cards_taken", []).duplicate(), "answers_sha256": answers_sha256(decisions),
		"timeline_sha256": fp.timeline_sha256(), "rounds": per_round}
