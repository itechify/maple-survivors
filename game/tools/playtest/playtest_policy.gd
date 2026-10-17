extends "res://tools/run_policy.gd"
## The agent playtest run policy (spec #91) for the headless run loop (balance_run.gd run_one / run_chain): every open
## decision goes to a brain link as a protocol `decide` and the answer is applied. Movement is the tactic controller
## (tactic_controller.gd) carrying out the current `tactic`, which a `tactic` decision (tactic_decision.gd) sets at
## the round start, at checkpoints and on triggers (see TACTIC_DEFAULTS and `_tactic_trigger`). With every tactic
## answered `kite` the round plays exactly as BotInput (the controller then calls BotInput.decide with `memo`).
## Tool code only.
##
## Hook points for later tickets:
##   decision_points  the decision kinds polled in `choose` (decision_point.gd; card and job windows by default)
##   decide(point, w) asks the brain about one decision and applies the answer (usable outside `choose`, e.g. at
##                    tactic checkpoints)
##   observers        Callables (w: RunWorld, events: Array) fanned out by `observe`, the run loop's per-tick observer
##   decision_observers  Callables (w: RunWorld, kind: String, phase: String) called by `decide` with phase "open"
##                    before the options are read and "applied" after the answer took effect (read-only watchers such
##                    as playtest_invariants.gd: chained windows resolve between two per-tick observations)
##   link             the brain: brain_link.gd (builtin baseline) or stdio_brain_link.gd (the Node CLI)
##   tactic           the current tactic (read it, e.g. the stuck detector ignores "hold"); set through set_tactic
##   tactic_params    checkpoint_s, hold_s, allowed (personalities override them before the round)
##   situation        playtest_situation.gd memory (recent hits, boss attacks) fed every tick
## An answer that is not one of the offered option ids, or a missing answer (lost brain), applies the baseline and
## records why, so the round always goes on.

const BRAIN_LINK := preload("res://tools/playtest/brain_link.gd")
const PROTOCOL := preload("res://tools/playtest/playtest_protocol.gd")
const SITUATION := preload("res://tools/playtest/playtest_situation.gd")
const CARD := preload("res://tools/playtest/card_decision.gd")
const JOB := preload("res://tools/playtest/job_decision.gd")
const POINT := preload("res://tools/playtest/decision_point.gd")
const TACTIC := preload("res://tools/playtest/tactic_decision.gd")
const CONTROLLER := preload("res://tools/playtest/tactic_controller.gd")
const DT := 1.0 / 60.0

## The brain answering decisions.
var link: BRAIN_LINK
## Decision kinds polled in `choose`, in order (decision_point.gd instances).
var decision_points: Array = []
## Per-tick observers: Callables (w, events).
var observers: Array = []
## Decision observers: Callables (w, kind, phase) with phase "open" / "applied" (see the header).
var decision_observers: Array = []
## One entry per decision: {id, kind, tick, time, options (ids), baseline, answer, source, confidence
## [, fallback_reason]}.
var decisions: Array = []
var _next_id := 1

## tier C: tactic decision timing: a checkpoint every checkpoint_s of run time, and a switched tactic held at least
## hold_s before a non-emergency trigger may change it (critical HP is the emergency). allowed: the offered tactics.
const TACTIC_DEFAULTS := {"checkpoint_s": 8.0, "hold_s": 4.0, "allowed": CONTROLLER.TACTICS}
## Trigger priority when several fire before a decision can be asked (higher first).
const TRIGGER_PRIORITY := {"hp_critical": 6, "start": 5, "boss": 4, "hp_low": 3, "crowd": 2, "card": 1, "checkpoint": 0}
## The current tactic (tactic_controller.gd TACTICS).
var tactic := "kite"
## Tactic timing parameters (TACTIC_DEFAULTS keys).
var tactic_params: Dictionary = TACTIC_DEFAULTS.duplicate(true)
## Situation memory (playtest_situation.gd instance) fed every tick by `observe`.
var situation: SITUATION
## Carries out the current tactic.
var controller: CONTROLLER
## The tactic decision point.
var tactic_point: TACTIC
## Tactic switches: [{tick, time, from, to, trigger, source}].
var tactic_log: Array = []
var _tactic_ticks := {}
var _tactic_triggers := {}
var _tactic_started := false
var _last_decision_tick := 0
## Tick of the last switch (none yet: far in the past, so nothing is held).
var _last_switch_tick := -(1 << 30)
var _pending := ""
var _prev_hp := "full"
var _mobs_step_at_decision := 0
var _cards_seen := 0


## `p_link` is the brain (null: the builtin baseline); `seed_value` / `p_branch` as in run_policy.gd.
func _init(p_link: BRAIN_LINK = null, seed_value := 0, p_branch := 0) -> void:
	super("bot", seed_value, p_branch)
	link = p_link if p_link != null else BRAIN_LINK.new()
	decision_points = [CARD.new(), JOB.new()]
	situation = SITUATION.new()
	controller = CONTROLLER.new()
	tactic_point = TACTIC.new()
	observers.append(_observe_tactics)
	for p: POINT in decision_points + [tactic_point]:
		p.memory = situation


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
	for o: Callable in decision_observers:
		o.call(w, point.kind, "open")
	var options: Array = point.options(w)
	var baseline: Dictionary = point.baseline(w, self)
	var tick := roundi(w.time / DT)
	var msg := PROTOCOL.decide(_next_id, point.kind, tick, w.time, point.situation(w), options, baseline)
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
	for o: Callable in decision_observers:
		o.call(w, point.kind, "applied")
	return String(entry.answer)


## The player's input for the next tick of `w`: asks a tactic decision when one is due, then lets the controller carry
## out the current tactic (kite: BotInput.decide with `memo`, exactly the inherited movement).
func move(w: RunWorld) -> MoveInput:
	var why := _tactic_trigger(w)
	if why != "":
		_ask_tactic(w, why)
	_tactic_ticks[tactic] = int(_tactic_ticks.get(tactic, 0)) + 1
	return controller.input(w, tactic, memo)


## Switches to tactic `to` (an allowed tactic) because of `trigger`; logs the switch with the deciding source.
func set_tactic(w: RunWorld, to: String, trigger: String) -> void:
	if to == tactic:
		return
	var source := String(decisions[decisions.size() - 1].source) if not decisions.is_empty() else ""
	tactic_log.append({"tick": roundi(w.time / DT), "time": snappedf(w.time, 0.001), "from": tactic, "to": to,
		"trigger": trigger, "source": source})
	tactic = to
	_last_switch_tick = roundi(w.time / DT)


## Tactic telemetry for the round record: seconds and time shares per tactic, the number of switches and decisions,
## decisions per trigger, the number of platforms stood on, and the switch log.
func tactic_summary() -> Dictionary:
	var total := 0
	for t: String in _tactic_ticks:
		total += int(_tactic_ticks[t])
	var seconds := {}
	var shares := {}
	for t: String in CONTROLLER.TACTICS:
		if _tactic_ticks.has(t):
			seconds[t] = snappedf(int(_tactic_ticks[t]) * DT, 0.001)
			shares[t] = snappedf(float(_tactic_ticks[t]) / maxf(1.0, total), 0.0001)
	var asked := decisions.filter(func(d: Dictionary) -> bool: return d.kind == "tactic").size()
	return {"seconds": seconds, "shares": shares, "switches": tactic_log.size(), "decisions": asked,
		"triggers": _tactic_triggers.duplicate(), "platforms_visited": controller.visits.size(),
		"log": tactic_log.duplicate(true)}


## Asks the tactic decision for trigger `why` and resets the checkpoint and the mob-bucket reference.
func _ask_tactic(w: RunWorld, why: String) -> void:
	var tick := roundi(w.time / DT)
	tactic_point.allowed = Array(tactic_params.get("allowed", CONTROLLER.TACTICS))
	tactic_point.trigger = why
	tactic_point.current = tactic
	tactic_point.held_s = (tick - maxi(0, _last_switch_tick)) * DT
	tactic_point.switches = tactic_log.size()
	_tactic_triggers[why] = int(_tactic_triggers.get(why, 0)) + 1
	_last_decision_tick = tick
	_pending = ""
	_mobs_step_at_decision = SITUATION.mobs_step(SITUATION.mobs_near(w))
	decide(tactic_point, w)


## The trigger that asks a tactic decision on this tick of `w`, or "" (see the class doc): the round start, critical
## HP (at once), then after the hold time a boss spawn, HP entering low, a mob-bucket jump of two steps since the last
## decision, a resolved card window, or the checkpoint. A trigger inside the hold waits for it to end.
func _tactic_trigger(w: RunWorld) -> String:
	var tick := roundi(w.time / DT)
	if not _tactic_started:
		_tactic_started = true
		_prev_hp = SITUATION.pool_bucket(int(w.player_state.hp), int(w.player_state.max_hp))
		_cards_seen = cards_taken.size()
		return "start"
	var hp := SITUATION.pool_bucket(int(w.player_state.hp), int(w.player_state.max_hp))
	var entered := hp != _prev_hp
	_prev_hp = hp
	if entered and hp == "critical":
		return "hp_critical"
	if entered and hp == "low":
		_raise("hp_low")
	if SITUATION.mobs_step(SITUATION.mobs_near(w)) - _mobs_step_at_decision >= 2:
		_raise("crowd")
	if cards_taken.size() > _cards_seen:
		_cards_seen = cards_taken.size()
		_raise("card")
	if tick - _last_decision_tick >= roundi(float(tactic_params.get("checkpoint_s", 8.0)) / DT):
		_raise("checkpoint")
	if _pending == "" or tick - _last_switch_tick < roundi(float(tactic_params.get("hold_s", 4.0)) / DT):
		return ""
	return _pending


## Keeps trigger `why` pending unless a higher-priority one already is.
func _raise(why: String) -> void:
	if _pending == "" or int(TRIGGER_PRIORITY[why]) > int(TRIGGER_PRIORITY[_pending]):
		_pending = why


## Per-tick tactic bookkeeping: the situation memory and boss spawns.
func _observe_tactics(w: RunWorld, events: Array) -> void:
	situation.observe(w, events)
	for e: Dictionary in events:
		if String(e.get("type", "")) == "boss_spawned":
			_raise("boss")


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
