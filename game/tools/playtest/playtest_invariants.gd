extends RefCounted
## Deterministic invariants for agent playtests (spec #91, ticket #96): read-only checks of a RunWorld, run every tick
## through the run loop's observer and at every decision through playtest_policy.gd `decision_observers`. A failure
## becomes one finding {kind, severity, tick, time, message, snapshot, count}; repeats of the same kind and key at the
## same place within DEDUP_S of the last one only raise its count. New findings go to `sink` as they happen (the
## driver streams them as protocol `finding` lines). Never changes the world. Tool code only.

const DT := 1.0 / 60.0
## Snapshot: the nearest mobs listed.
const SNAPSHOT_MOBS := 5
## tier C: two findings of one kind and key closer than this (px) and DEDUP_S (run seconds) apart are one finding.
const DEDUP_PX := 96.0
const DEDUP_S := 30.0
## tier C: how far (px) outside the map's MapBounds rect the player may be before it is out of bounds.
const BOUNDS_MARGIN := 64.0
## tier C (ticket #96 defaults): stuck = the player stays inside a STUCK_PX box for STUCK_S run seconds while it
## presses movement (walking or in the air) for at least STUCK_PRESS of those ticks.
const STUCK_PX := 24.0
const STUCK_S := 20.0
const STUCK_PRESS := 0.5
## Every finding kind these checks report (also the values --inject-finding accepts).
const KINDS := ["hp_out_of_range", "mp_out_of_range", "position_not_finite", "out_of_bounds", "level_decreased",
	"exp_decreased", "bad_state_transition", "card_offer", "world_warning", "missing_asset", "stuck"]

## Findings so far, in order of first occurrence.
var findings: Array = []
## Card windows checked so far.
var checked_offers := 0
## The run policy whose tactic / name the checks read (any Object or null).
var policy: Object
## Receives each new finding (Callable(finding: Dictionary)); repeats only raise the count of the stored one.
var sink: Callable
var stuck_px := STUCK_PX
var stuck_s := STUCK_S
## Test-only: a finding of this kind is reported once at run time `inject_at` (driver --inject-finding).
var inject := ""
var inject_at := 0.0
## Asset lookups that failed while the round was built (DataRepo.build_setup's list): reported on the first tick.
var missing_at_start := PackedStringArray()


## `p_policy` is read for its tactic and name (never called); `options` overrides thresholds ({stuck_px, stuck_s}),
## may inject one finding ({inject: kind, inject_at: run seconds}) and lists the setup's missing assets ({missing:
## [path]}, one missing_asset finding each on the first tick); `p_sink` gets each new finding.
func _init(p_policy: Object = null, options := {}, p_sink := Callable()) -> void:
	policy = p_policy
	sink = p_sink
	stuck_px = float(options.get("stuck_px", STUCK_PX))
	stuck_s = float(options.get("stuck_s", STUCK_S))
	inject = String(options.get("inject", ""))
	inject_at = float(options.get("inject_at", 0.0))
	missing_at_start = PackedStringArray(options.get("missing", PackedStringArray()))


## Registers the checks on playtest policy `p` (its per-tick observers and decision observers).
func attach(p: Object) -> void:
	policy = p
	p.observers.append(observe)
	p.decision_observers.append(on_decision)


## The per-tick check (run loop observer): call after every step of `w` with the step's drained `events`.
func observe(w: RunWorld, _events: Array) -> void:
	if not missing_at_start.is_empty():
		check_missing(w, missing_at_start)
		missing_at_start = PackedStringArray()
	var ps := w.player_state
	var hp := int(ps.get("hp", 0))
	var max_hp := int(ps.get("max_hp", 0))
	if hp < 0 or hp > max_hp:
		report(w, "hp_out_of_range", "hp", "HP %d outside 0..%d" % [hp, max_hp])
	var mp := int(ps.get("mp", 0))
	var max_mp := int(ps.get("max_mp", 0))
	if mp < 0 or mp > max_mp:
		report(w, "mp_out_of_range", "mp", "MP %d outside 0..%d" % [mp, max_mp])
	var pos := w.player.pos
	if not (is_finite(pos.x) and is_finite(pos.y)):
		report(w, "position_not_finite", "pos", "player position %s is not finite" % pos)
	elif w.bounds.has_area() and not w.bounds.grow(BOUNDS_MARGIN).has_point(pos):
		report(w, "out_of_bounds", "bounds", "player at (%.1f, %.1f) is outside the map bounds %s (margin %d px)" % [
			pos.x, pos.y, w.bounds, BOUNDS_MARGIN])
	var level := int(ps.get("level", 0))
	var exp := int(ps.get("exp", 0))
	if _level >= 0:
		if level < _level:
			report(w, "level_decreased", "level", "level went down from %d to %d" % [_level, level])
		elif level == _level and exp < _exp:
			report(w, "exp_decreased", "exp", "EXP went down from %d to %d at Lv %d" % [_exp, exp, level])
	_level = level
	_exp = exp
	while _warned < w.warnings.size():
		report(w, "world_warning", w.warnings[_warned], "world warning: %s" % w.warnings[_warned])
		_warned += 1
	_check_state(w)
	_check_offer(w)
	_check_stuck(w)
	if inject != "" and w.time >= inject_at - 1e-6:
		report(w, inject, "injected", "injected by --inject-finding=%s (test only; not a real failure)" % inject)
		inject = ""


## Reports every entry of `missing` (asset lookups that failed, DataRepo.build_setup's list) as a finding.
func check_missing(w: RunWorld, missing: PackedStringArray) -> void:
	for m: String in missing:
		report(w, "missing_asset", m, "missing asset: %s" % m)


var _level := -1
var _exp := 0
var _warned := 0
# Stuck detector: one bucket per run second [second, min x, max x, min y, max y, pressing ticks, ticks, ignored].
var _buckets: Array = []
var _cur: Array = []


func _check_stuck(w: RunWorld) -> void:
	var sec := int(floor(w.time))
	if _cur.is_empty() or int(_cur[0]) != sec:
		if not _cur.is_empty():
			_buckets.append(_cur)
			_judge_stuck(w)
		var p0 := w.player.pos
		_cur = [sec, p0.x, p0.x, p0.y, p0.y, 0, 0, false]
	var p := w.player.pos
	_cur[1] = minf(_cur[1], p.x)
	_cur[2] = maxf(_cur[2], p.x)
	_cur[3] = minf(_cur[3], p.y)
	_cur[4] = maxf(_cur[4], p.y)
	_cur[6] += 1
	if w.player.state == PlayerMotion.ST_WALK or w.player.state == PlayerMotion.ST_AIR:
		_cur[5] += 1
	if w.state != RunWorld.PLAYING or _parked(w):
		_cur[7] = true


# Hold presses nothing on purpose; a camper parks after camp_after.
func _parked(w: RunWorld) -> bool:
	if tactic() == "hold":
		return true
	var policy_name: Variant = policy.get("name") if policy != null else null
	return policy_name != null and String(policy_name).begins_with("camper") \
		and w.time >= float(policy.get("camp_after"))


func _judge_stuck(w: RunWorld) -> void:
	var n := ceili(stuck_s - 1e-6)
	if _buckets.size() > n:
		_buckets = _buckets.slice(_buckets.size() - n)
	if _buckets.size() < n:
		return
	var box := Rect2(Vector2(_buckets[0][1], _buckets[0][3]), Vector2.ZERO)
	var press := 0
	var ticks := 0
	for b: Array in _buckets:
		if bool(b[7]):
			return
		box = box.expand(Vector2(b[1], b[3])).expand(Vector2(b[2], b[4]))
		press += int(b[5])
		ticks += int(b[6])
	if maxf(box.size.x, box.size.y) < stuck_px and press >= STUCK_PRESS * ticks:
		report(w, "stuck", "stuck", "the player stayed inside %d px for %d s while pressing movement (%d%% of ticks), tactic %s" % [
			roundi(stuck_px), roundi(stuck_s), roundi(100.0 * press / maxi(1, ticks)), tactic()], "warning")
		_buckets.clear()


## The decision check (playtest_policy.gd decision observer): `phase` "open" before a decision of `kind` is answered,
## "applied" after its answer took effect.
func on_decision(w: RunWorld, _kind: String, _phase: String) -> void:
	_hooked = true
	_check_state(w)
	_check_offer(w)


# Allowed RunWorld.state changes (docs/ARCHITECTURE.md 4.4.2): step() leaves PLAYING for a window, death or the clear;
# a job window always continues to a card window (apply_job's advancement draw, decline_job's level choice); a card
# window continues to play, the next queued level's job or card window, or the next bonus pick.
const TRANSITIONS := {
	RunWorld.PLAYING: [RunWorld.PLAYING, RunWorld.CHOOSING_JOB, RunWorld.CHOOSING_UPGRADE, RunWorld.DEAD,
		RunWorld.CLEARED],
	RunWorld.CHOOSING_JOB: [RunWorld.CHOOSING_JOB, RunWorld.CHOOSING_UPGRADE],
	RunWorld.CHOOSING_UPGRADE: [RunWorld.CHOOSING_UPGRADE, RunWorld.PLAYING, RunWorld.CHOOSING_JOB],
	RunWorld.DEAD: [RunWorld.DEAD],
	RunWorld.CLEARED: [RunWorld.CLEARED],
}
var _state := -1
# True once on_decision ran: decision hooks are wired, so every window's state change is seen. With `observe` alone
# (any run_one policy), windows resolve inside choose() between two observations and only their outcome is checked.
var _hooked := false


func _check_state(w: RunWorld) -> void:
	if not _hooked and (_state == RunWorld.CHOOSING_JOB or _state == RunWorld.CHOOSING_UPGRADE):
		_state = RunWorld.PLAYING # observer only: the policy resolved the windows unseen, back to play before the step
	if _state >= 0 and _state != w.state and not (w.state in TRANSITIONS.get(_state, [])):
		report(w, "bad_state_transition", "%d>%d" % [_state, w.state], "state %s -> %s is not in the pause protocol" % [
			RunWorld.STATE_NAMES[_state], w.state_name()])
	_state = w.state


var _offer_seen: Array = []


# Card offer rules (docs/GAME_DESIGN.md 8, ticket #96), checked once per open card window.
func _check_offer(w: RunWorld) -> void:
	if w.state != RunWorld.CHOOSING_UPGRADE or (_offer_seen.size() > 0 and is_same(_offer_seen[0], w.pending_cards)):
		return
	_offer_seen = [w.pending_cards]
	checked_offers += 1
	var cards := w.pending_cards
	if cards.is_empty():
		report(w, "card_offer", "empty", "the card window is empty (every reward opens a window with at least the Power Elixir)")
		return
	var job := w.progression.job_id
	var ids := {}
	var fillers := 0
	for c: Dictionary in cards:
		var id := String(c.get("id", ""))
		if ids.has(id):
			report(w, "card_offer", "duplicate:" + id, "duplicate card id %s in one offer" % id)
		ids[id] = true
		var def := w.upgrades.card(id)
		if def.is_empty():
			report(w, "card_offer", "unknown:" + id, "unknown card id %s" % id)
			continue
		var kind := String(def.get("kind", ""))
		if kind == "filler":
			fillers += 1
			continue
		var req: Dictionary = def.get("requires", {}) if def.get("requires") is Dictionary else {}
		var jobs: Array = req.get("jobs", []).map(func(j: Variant) -> int: return int(j))
		if not jobs.is_empty() and not (job in jobs):
			report(w, "card_offer", "job:" + id, "card %s requires jobs %s but the current job is job %d" % [
				id, str(jobs), job])
		var skill := String(def.get("skill", ""))
		if skill == "" or not w.loadout.book.has(skill):
			continue
		var skill_def := w.loadout.book.def(skill)
		if skill_def.has("job") and not w.jobs.is_descendant(job, int(skill_def.job)):
			report(w, "card_offer", "line:" + id, "card %s is for %s (job %d), not in the line of job %d" % [
				id, skill, int(skill_def.job), job])
		var max_rank := int(def.get("max_rank", 1))
		if max_rank > 0 and w.upgrades.rank(id, w) >= max_rank:
			report(w, "card_offer", "max:" + id, "card %s is offered at its max rank %d" % [id, max_rank])
		match kind:
			"skill_rank":
				if w.loadout.rank(skill) >= w.loadout.book.max_rank(skill):
					report(w, "card_offer", "max:" + id, "card %s ranks %s, already at its max rank %d" % [
						id, skill, w.loadout.book.max_rank(skill)])
			"skill_new":
				if w.loadout.has(skill):
					report(w, "card_offer", "owned:" + id, "card %s learns %s, which is already learned" % [id, skill])
			"skill_mod":
				if not w.loadout.has(skill):
					report(w, "card_offer", "unowned:" + id, "card %s modifies %s, which is not learned" % [id, skill])
	if fillers > 1 or (fillers == 1 and cards.size() - fillers >= 3):
		report(w, "card_offer", "filler", "the Power Elixir is offered %d time(s) beside %d cards (only one, and only with fewer than three)" % [
			fillers, cards.size() - fillers])
	if not w.choice_advancement and cards.size() > 3:
		report(w, "card_offer", "size", "%d cards in a normal draw (at most three)" % cards.size())


## Records a failure of `kind` in `w` (`key` tells apart unrelated failures of one kind) with `message`.
func report(w: RunWorld, kind: String, key: String, message: String, severity := "error") -> void:
	var pos := w.player.pos
	for f: Dictionary in findings:
		if f.kind == kind and f._key == key and w.time - float(f._last) <= DEDUP_S \
				and Vector2(f.snapshot.x, f.snapshot.y).distance_to(pos) <= DEDUP_PX:
			f.count = int(f.count) + 1
			f._last = w.time
			return
	var f := {"kind": kind, "severity": severity, "tick": roundi(w.time / DT), "time": snappedf(w.time, 0.001),
		"message": message, "snapshot": snapshot(w), "count": 1, "_key": key, "_last": w.time}
	findings.append(f)
	if sink.is_valid():
		sink.call(public(f))


## Finding `f` without the bookkeeping fields (what goes over the protocol and into findings.jsonl).
static func public(f: Dictionary) -> Dictionary:
	var out := f.duplicate(true)
	out.erase("_key")
	out.erase("_last")
	return out


## Every finding without bookkeeping fields, with final counts.
func results() -> Array:
	return findings.map(func(f: Dictionary) -> Dictionary: return public(f))


## The tactic the policy plays now ("kite" when it has none).
func tactic() -> String:
	var t: Variant = policy.get("tactic") if policy != null else null
	return "kite" if t == null or String(t) == "" else String(t)


## A compact state snapshot of `w`: position, foothold / platform, HP / MP, level, job, tactic, state and up to
## SNAPSHOT_MOBS nearest mobs [{mob, d, x, y, boss}].
func snapshot(w: RunWorld) -> Dictionary:
	var ps := w.player_state
	var p := w.player.pos
	var near: Array = []
	var s := w.swarm
	for i in s.capacity():
		if s.active[i] != 0:
			near.append({"slot": i, "d": Vector2(s.x[i], s.y[i]).distance_to(p)})
	near.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.d) < float(b.d))
	var mobs: Array = []
	for n: Dictionary in near.slice(0, SNAPSHOT_MOBS):
		var i := int(n.slot)
		var k := int(s.kind[i])
		mobs.append({"mob": w.mob_kinds[k].id if k >= 0 and k < w.mob_kinds.size() else -1,
			"d": snappedf(float(n.d), 0.1), "x": snappedf(s.x[i], 0.1), "y": snappedf(s.y[i], 0.1),
			"boss": i < w.mob_boss.size() and w.mob_boss[i] >= 0})
	return {"x": snappedf(p.x, 0.1), "y": snappedf(p.y, 0.1), "fh": w.player.fh,
		"platform": w.fhm.platform_of(w.player.fh) if w.fhm != null else -1,
		"hp": int(ps.get("hp", 0)), "max_hp": int(ps.get("max_hp", 0)), "mp": int(ps.get("mp", 0)),
		"max_mp": int(ps.get("max_mp", 0)), "level": int(ps.get("level", 0)), "job": int(ps.get("job_id", 0)),
		"tactic": tactic(), "state": w.state_name(), "mobs": mobs}
