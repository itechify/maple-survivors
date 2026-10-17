extends TestCase
## The windowed replay's in-process replay brain (spec #91, ticket #100; game/tools/playtest/replay_brain_link.gd): it
## answers each decide from a recording's decisions.jsonl in order and applies the checks of #98's Node replay brain
## (tools/playtest/src/core/replay.ts, same messages): decision id at its position, kind, options in on-screen order,
## tick; after the first divergence it answers the baseline; `finish` adds missing decisions and the first applied
## answer that differs; `compare_fingerprints` compares field by field with numbers by value.

const LINK := preload("res://tools/playtest/replay_brain_link.gd")
const REPLAY := preload("res://scenes/debug/agent_replay.gd")


static func _rec(id: int, kind: String, tick: int, options: Array, answer: String, confidence: Variant = null) -> Dictionary:
	return {"id": float(id), "kind": kind, "tick": float(tick), "time": tick / 60.0, "options": options,
		"baseline": options[0], "answer": answer, "source": "jev", "confidence": confidence}


static func _decide(id: int, kind: String, tick: int, ids: Array, baseline: String = "") -> Dictionary:
	return {"type": "decide", "id": id, "kind": kind, "tick": tick, "time": tick / 60.0,
		"options": ids.map(func(i: String) -> Dictionary: return {"id": i}),
		"baseline": {"sensible": baseline if baseline != "" else String(ids[0])}}


func _recording() -> Array:
	return [_rec(1, "tactic", 0, ["kite", "explore"], "explore", 0.8), _rec(2, "card", 600, ["a", "b", "c"], "c"),
		_rec(3, "job", 900, ["200", "not_now"], "200")]


func test_it_answers_the_recorded_answers_in_order() -> void:
	var link := LINK.new(_recording())
	assert_eq(link.mode, "replay")
	var a := link.ask(_decide(1, "tactic", 0, ["kite", "explore"]))
	assert_eq(a, {"id": 1, "answer": "explore", "source": "replay", "confidence": 0.8})
	assert_eq(String(link.ask(_decide(2, "card", 600, ["a", "b", "c"])).answer), "c")
	assert_eq(String(link.ask(_decide(3, "job", 900, ["200", "not_now"])).answer), "200")
	assert_eq(link.divergences(), [])
	var applied := [{"id": 1, "answer": "explore"}, {"id": 2, "answer": "c"}, {"id": 3, "answer": "200"}]
	assert_eq(link.finish(applied), [])


func test_reordered_options_diverge_and_later_decides_take_the_baseline() -> void:
	var link := LINK.new(_recording())
	link.ask(_decide(1, "tactic", 0, ["kite", "explore"]))
	var a := link.ask(_decide(2, "card", 600, ["b", "a", "c"], "b"))
	assert_eq(String(a.answer), "b", "the baseline after a divergence")
	assert_eq(link.divergences(), [{"message": "decision 2: options [b, a, c], recorded [a, b, c] (same options in another order)",
		"decision": 2}])
	assert_eq(String(link.ask(_decide(3, "job", 900, ["200", "not_now"], "not_now")).answer), "not_now",
		"still the baseline")
	assert_eq(link.divergences().size(), 1, "only the first divergence is a decide-time one")


func test_kind_tick_and_extra_decisions_diverge_with_node_messages() -> void:
	var kind := LINK.new(_recording())
	kind.ask(_decide(1, "card", 0, ["kite", "explore"]))
	assert_eq(String(kind.divergences()[0].message), "decision 1: kind card, recorded tactic")
	var tick := LINK.new(_recording())
	tick.ask(_decide(1, "tactic", 5, ["kite", "explore"]))
	assert_eq(String(tick.divergences()[0].message), "decision 1: tick 5, recorded 0")
	var extra := LINK.new([_rec(1, "tactic", 0, ["kite", "explore"], "explore")])
	extra.ask(_decide(1, "tactic", 0, ["kite", "explore"]))
	extra.ask(_decide(2, "card", 60, ["a"]))
	assert_eq(String(extra.divergences()[0].message), "decision 2 (card) is not in the recording (1 decisions)")
	var options := LINK.new(_recording())
	options.ask(_decide(1, "tactic", 0, ["kite", "hold"]))
	assert_eq(String(options.divergences()[0].message), "decision 1: options [kite, hold], recorded [kite, explore]")


func test_finish_reports_missing_decisions_and_the_first_different_applied_answer() -> void:
	var link := LINK.new(_recording())
	link.ask(_decide(1, "tactic", 0, ["kite", "explore"]))
	link.ask(_decide(2, "card", 600, ["a", "b", "c"]))
	var out := link.finish([{"id": 1, "answer": "explore"}, {"id": 2, "answer": "a", "fallback_reason": "why"}])
	assert_eq(out, [{"message": "the replay made 2 decisions, the recording has 3"},
		{"decision": 2, "message": "decision 2: the driver applied a, recorded c (why)"}])


func test_the_first_differing_timeline_row_names_its_fields() -> void:
	var rec := PackedStringArray(['{"time":1.0,"tick":60,"hp":50,"x":10.0}', '{"time":2.0,"tick":120,"hp":50,"x":12.0}'])
	var same := PackedStringArray(['{"time":1,"tick":60,"hp":50,"x":10}', '{"time":2.0,"tick":120,"hp":50,"x":12.0}'])
	assert_eq(REPLAY.first_timeline_difference(rec, same), {}, "numbers by value")
	var moved := PackedStringArray([rec[0], '{"time":2.0,"tick":120,"hp":44,"x":15.5}'])
	assert_eq(REPLAY.first_timeline_difference(rec, moved), {"row": 2, "time": 2.0, "tick": 120.0,
		"fields": {"hp": [50.0, 44.0], "x": [12.0, 15.5]}})
	assert_eq(REPLAY.first_timeline_difference(rec, PackedStringArray([rec[0]])), {"row": 2, "missing": "replayed"})


func test_divergences_are_ordered_like_the_node_replay() -> void:
	var divs := [{"field": "ticks", "message": "f"}, {"decision": 9, "message": "d9"}, {"message": "short"},
		{"decision": 4, "message": "d4"}]
	assert_eq(REPLAY.order_divergences(divs).map(func(d: Dictionary) -> String: return String(d.message)),
		["d4", "d9", "f", "short"])


func test_fingerprints_compare_by_value_in_recorded_field_order() -> void:
	var recorded: Dictionary = JSON.parse_string('{"ticks":5400,"state":"TIMEOUT","time":90.0,"level":3,"cards_taken":["2:a"]}')
	var same := {"ticks": 5400, "state": "TIMEOUT", "time": 90.0, "level": 3, "cards_taken": ["2:a"]}
	assert_eq(LINK.compare_fingerprints(recorded, same), [], "ints equal the recording's JSON floats")
	var other := {"ticks": 5400, "state": "DEAD", "time": 90.0, "level": 4, "cards_taken": ["2:a"], "job": 0}
	assert_eq(LINK.compare_fingerprints(recorded, other).map(func(d: Dictionary) -> String: return String(d.field)),
		["state", "level", "job"])
	assert_eq(String(LINK.compare_fingerprints(recorded, other)[0].message),
		"fingerprint.state: replay \"DEAD\", recorded \"TIMEOUT\"")
