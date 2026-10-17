extends RefCounted
## Tier chains for the agent playtest driver (spec #91, ticket #98): plays prepared tier setups through
## balance_run.gd `run_chain` (the real character carry; only a CLEARED round feeds the next) with a fresh playtest
## policy per round on the same brain link. Decision ids continue across rounds (the CLI keys decisions by id), every
## round gets its own invariants (playtest_invariants.gd) and timeline (rows tagged with "tier"), and one fingerprint
## observer hashes the whole chain. The record is run_chain's (rounds[] with per-round records and tactics) plus the
## last round's state, time, level, job and kills at the top level, every card taken, and the combined tactics.
## Tool code only.

const BR := preload("res://tools/balance_run.gd")
const POLICY := preload("res://tools/playtest/playtest_policy.gd")
const BRAIN_LINK := preload("res://tools/playtest/brain_link.gd")
const INVARIANTS := preload("res://tools/playtest/playtest_invariants.gd")
const TIMELINE := preload("res://tools/playtest/playtest_timeline.gd")
const FINGERPRINT := preload("res://tools/playtest/playtest_fingerprint.gd")
const CONTROLLER := preload("res://tools/playtest/tactic_controller.gd")
const DT := 1.0 / 60.0

## The brain answering every round's decisions.
var link: BRAIN_LINK
## Invariant options (playtest_invariants.gd); an injected test finding fires in the first round only.
var checks: Dictionary
## Receives each new finding (Dictionary).
var sink: Callable
## Receives each timeline row (a JSON line with "tier"); invalid: no timeline.
var write_timeline: Callable
## Extra per-tick observers added to every round's policy (e.g. the driver's progress lines).
var extra_observers: Array = []
## The policy of each round played, in order.
var policies: Array = []
## The invariants of each round played, in order.
var invariants: Array = []
## The timeline writer of each round played (kept alive for their observer Callables).
var timelines: Array = []
## The fingerprint observer over the whole chain.
var fingerprint := FINGERPRINT.new()


func _init(p_link: BRAIN_LINK = null, p_checks := {}, p_sink := Callable(), p_write_timeline := Callable()) -> void:
	link = p_link if p_link != null else BRAIN_LINK.new()
	checks = p_checks
	sink = p_sink
	write_timeline = p_write_timeline


## Plays `setups` (tier 1 first) from run seed `run_seed`: {record, fingerprint, decisions, findings}.
func play(setups: Array, run_seed: int) -> Dictionary:
	var current := {"policy": null}
	var factory := func(tier_index: int, round_seed: int) -> Object:
		var p := _round_policy(tier_index, round_seed)
		current.policy = p
		return p
	var observer := func(w: RunWorld, events: Array) -> void: current.policy.observe(w, events)
	var chain: Dictionary = BR.run_chain(setups, factory, run_seed, -1.0, 60.0, 0, observer)
	var record := chain.duplicate()
	var rounds: Array = record.rounds
	var cards: Array = []
	for i in rounds.size():
		rounds[i]["policy"] = "playtest"
		rounds[i]["tactics"] = policies[i].tactic_summary()
		cards.append_array(rounds[i].get("cards_taken", []))
	var last: Dictionary = rounds[rounds.size() - 1]
	for k: String in ["state", "time", "level", "job", "kills"]:
		record[k] = last.get(k)
	record.merge({"policy": "playtest", "cards_taken": cards, "tactics": combined_tactics(rounds),
		"start_character": rounds[0].get("start_character", {}), "warnings": last.get("warnings", [])}, true)
	var decisions := all_decisions()
	var findings: Array = []
	for inv: INVARIANTS in invariants:
		findings.append_array(inv.results())
	return {"record": record, "fingerprint": FINGERPRINT.of_chain(record, decisions, fingerprint), "decisions": decisions,
		"findings": findings}


## Every round's applied decisions, in order.
func all_decisions() -> Array:
	var out: Array = []
	for p: POLICY in policies:
		out.append_array(p.decisions)
	return out


## The policy for round `tier_index`: decision ids continue from the earlier rounds; its own invariants and timeline.
func _round_policy(tier_index: int, round_seed: int) -> POLICY:
	var p := POLICY.new(link, round_seed)
	p._next_id = all_decisions().size() + 1 # ids continue across rounds (the policy counts from 1 on its own)
	var round_checks := checks.duplicate()
	if tier_index > 0:
		round_checks.erase("inject")
		fingerprint.next_round()
	var inv := INVARIANTS.new(p, round_checks, sink)
	inv.attach(p)
	invariants.append(inv)
	var tier := tier_index + 1
	var tl := TIMELINE.new(p, func(line: String) -> void:
		if write_timeline.is_valid():
			write_timeline.call("{\"tier\":%d,%s" % [tier, line.substr(1)]))
	timelines.append(tl) # a Callable does not keep its RefCounted object alive
	p.observers.append(tl.observe)
	p.observers.append(fingerprint.observe)
	p.observers.append_array(extra_observers)
	policies.append(p)
	return p


## The rounds' tactic telemetry combined: seconds, decisions, switches, triggers and platforms summed, shares over the
## whole chain, and the switch logs concatenated with each entry's tier.
static func combined_tactics(rounds: Array) -> Dictionary:
	var seconds := {}
	var triggers := {}
	var switch_log: Array = []
	var switches := 0
	var asked := 0
	var platforms := 0
	for r: Dictionary in rounds:
		var t: Dictionary = r.get("tactics", {})
		for k: String in t.get("seconds", {}):
			seconds[k] = snappedf(float(seconds.get(k, 0.0)) + float(t.seconds[k]), 0.001)
		for k: String in t.get("triggers", {}):
			triggers[k] = int(triggers.get(k, 0)) + int(t.triggers[k])
		for entry: Dictionary in t.get("log", []):
			var e := entry.duplicate()
			e["tier"] = int(r.get("tier", 1))
			switch_log.append(e)
		switches += int(t.get("switches", 0))
		asked += int(t.get("decisions", 0))
		platforms += int(t.get("platforms_visited", 0))
	var total := 0.0
	for k: String in seconds:
		total += float(seconds[k])
	var shares := {}
	for k: String in CONTROLLER.TACTICS:
		if seconds.has(k):
			shares[k] = snappedf(float(seconds[k]) / maxf(DT, total), 0.0001)
	return {"seconds": seconds, "shares": shares, "switches": switches, "decisions": asked, "triggers": triggers,
		"platforms_visited": platforms, "log": switch_log}
