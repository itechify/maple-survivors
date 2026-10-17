extends "res://tools/run_policy.gd"
## The agent playtest run policy (spec #91) for the headless run loop (balance_run.gd run_one / run_chain): every open
## decision goes to a brain link as a protocol `decide` and the answer is applied. Movement is the inherited
## BotInput.decide (tactics arrive in #95). Tool code only.
##
## Hook points for later tickets:
##   decision_points  the decision kinds polled in `choose` (decision_point.gd; card and job windows by default)
##   decide(point, w) asks the brain about one decision and applies the answer (usable outside `choose`, e.g. at
##                    tactic checkpoints)
##   observers        Callables (w: RunWorld, events: Array) fanned out by `observe`, the run loop's per-tick observer
##   link             the brain: brain_link.gd (builtin baseline) or stdio_brain_link.gd (the Node CLI)
## An answer that is not one of the offered option ids, or a missing answer (lost brain), applies the baseline and
## records why, so the round always goes on.

const BRAIN_LINK := preload("res://tools/playtest/brain_link.gd")
const PROTOCOL := preload("res://tools/playtest/playtest_protocol.gd")
const SITUATION := preload("res://tools/playtest/playtest_situation.gd")
const CARD := preload("res://tools/playtest/card_decision.gd")
const JOB := preload("res://tools/playtest/job_decision.gd")
const POINT := preload("res://tools/playtest/decision_point.gd")
const DT := 1.0 / 60.0

## The brain answering decisions.
var link: BRAIN_LINK
## Decision kinds polled in `choose`, in order (decision_point.gd instances).
var decision_points: Array = []
## Per-tick observers: Callables (w, events).
var observers: Array = []
## One entry per decision: {id, kind, tick, time, options (ids), baseline, answer, source, confidence
## [, fallback_reason]}.
var decisions: Array = []
var _next_id := 1


## `p_link` is the brain (null: the builtin baseline); `seed_value` / `p_branch` as in run_policy.gd.
func _init(p_link: BRAIN_LINK = null, seed_value := 0, p_branch := 0) -> void:
	super("bot", seed_value, p_branch)
	link = p_link if p_link != null else BRAIN_LINK.new()
	decision_points = [CARD.new(), JOB.new()]


## Answers every pending decision of `w` through the brain (at most 64 in one call).
func choose(w: RunWorld) -> void:
	var guard := 0
	while guard < 64:
		var point: POINT = null
		for p: POINT in decision_points:
			if p.pending(w):
				point = p
				break
		if point == null:
			return
		guard += 1
		decide(point, w)


## Asks the brain about decision `point` in `w`, applies the answer (or the baseline) and returns the applied option id.
func decide(point: POINT, w: RunWorld) -> String:
	var options: Array = point.options(w)
	var baseline: Dictionary = point.baseline(w, self)
	var tick := roundi(w.time / DT)
	var msg := PROTOCOL.decide(_next_id, point.kind, tick, w.time, SITUATION.of(w), options, baseline)
	_next_id += 1
	var reply: Dictionary = link.ask(msg)
	var ids: Array = options.map(func(o: Dictionary) -> String: return String(o.id))
	var answer := String(reply.get("answer", ""))
	var entry := {"id": int(msg.id), "kind": point.kind, "tick": tick, "time": msg.time, "options": ids,
		"baseline": String(baseline.get("sensible", "")), "answer": answer,
		"source": String(reply.get("source", "")), "confidence": reply.get("confidence")}
	if reply.has("error") or not (answer in ids):
		entry.fallback_reason = String(reply.get("error", "answer \"%s\" is not an offered option" % answer))
		entry.answer = entry.baseline
		entry.source = "baseline"
		entry.confidence = null
	decisions.append(entry)
	point.apply(w, self, String(entry.answer))
	return String(entry.answer)


## The run loop's per-tick observer (balance_run.gd run_one `observer`): fans out to `observers`.
func observe(w: RunWorld, events: Array) -> void:
	for o: Callable in observers:
		o.call(w, events)


## The run fingerprint compared by replays: ticks, final state, level, kills, time, card ids taken and a hash of the
## decision answers, from round record `record` of `w`.
func fingerprint(w: RunWorld, record: Dictionary) -> Dictionary:
	var answers: Array = decisions.map(func(d: Dictionary) -> String: return "%s:%s" % [d.kind, d.answer])
	return {"ticks": roundi(w.time / DT), "state": String(record.get("state", "")), "time": record.get("time", 0.0),
		"level": int(record.get("level", 0)), "kills": int(record.get("kills", 0)),
		"cards_taken": cards_taken.duplicate(), "answers_sha256": JSON.stringify(answers).sha256_text()}
