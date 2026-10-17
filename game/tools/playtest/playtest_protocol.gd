extends RefCounted
## The decision protocol between the playtest driver (playtest_driver.gd) and the Node CLI (tools/playtest/, spec #91).
## The Node side is tools/playtest/src/core/protocol.ts; keep both headers in sync. Tool code only.
##
## Version 1. Two processes in lockstep over this process's stdin/stdout:
##   - Driver -> CLI: one stdout line per message, "@@PT " + a JSON object. Every other stdout line is a log line.
##   - CLI -> driver: one JSON line on stdin per `decide`. The driver blocks (the sim is paused) until it arrives;
##     stdin EOF ("") means "brain lost": the driver finishes the round on its builtin baseline.
## Every message carries "v": 1 and "type". Shapes:
##   hello   {v, type:"hello", game, stage, seed, minutes, personality, brain}             once, before the round
##           (the driver adds tier and character, #98; a replay compares every hello field but brain)
##   decide  {v, type:"decide", id, kind, tick, time, situation:{...}, options:[{id, ...}], baseline:{sensible: id}}
##           id 1, 2, 3... per run; kind "card", "job" or "tactic"; option ids are Strings (job ids as text,
##           plus "not_now"; tactic ids from tactic_controller.gd TACTICS); baseline answers come from real game code
##           (BotInput.pick_card_for / pick_job; "kite" for tactics). situation: playtest_situation.gd `of` (facts
##           plus `buckets`); a tactic decide adds situation.tactic {current, trigger, held_s, switches}.
##   finding {v, type:"finding", kind, severity, tick, time, message, snapshot:{...}, count}   an invariant failure
##           (playtest_invariants.gd), sent when it first happens; count 1 then (repeats only raise the end count)
##   end     {v, type:"end", record:{...}, fingerprint:{...}, decisions:[...], brain_lost, findings:[...]}  once,
##           after the round; findings are the de-duplicated findings with their final counts
##           decisions as applied: [{id, kind, tick, time, options, baseline, answer, source, confidence,
##           fallback_reason?}] (source "baseline" when an answer was invalid or the brain was lost)
##   error   {v, type:"error", reason, message}       infrastructure failure, then exit code 2 ("cache_missing", ...)
##   answer  {v, type:"answer", id, answer, source, confidence}      CLI -> driver; answer is one option id, source
##           names the brain ("fallback:sensible", later "jev", "replay"), confidence 0..1 or null.
## Answers are read with a READ_BUFFER-byte buffer: answer lines stay short.

const VERSION := 1
const PREFIX := "@@PT "
const GAME := "maple-survivors"
## Bytes per stdin read (OS.read_string_from_stdin); one answer line must fit.
const READ_BUFFER := 4096


## One protocol line (prefix + JSON) for message `msg` (`v` is added).
static func encode(msg: Dictionary) -> String:
	var out := {"v": VERSION}
	out.merge(msg)
	return PREFIX + JSON.stringify(out)


## The hello message sent before the round.
static func hello(stage: String, seed_value: int, minutes: float, personality: String, brain: String) -> Dictionary:
	return {"type": "hello", "game": GAME, "stage": stage, "seed": seed_value, "minutes": minutes,
		"personality": personality, "brain": brain}


## A decide message: decision `id` of `kind` at `tick` / run time `time`.
static func decide(id: int, kind: String, tick: int, time: float, situation: Dictionary, options: Array,
		baseline: Dictionary) -> Dictionary:
	return {"type": "decide", "id": id, "kind": kind, "tick": tick, "time": snappedf(time, 0.001),
		"situation": situation, "options": options, "baseline": baseline}


## The end message: the round record, its fingerprint, the decisions as applied (playtest_policy.gd `decisions`),
## whether the brain was lost and the de-duplicated findings (playtest_invariants.gd `results`).
static func end(record: Dictionary, fingerprint: Dictionary, decisions: Array, brain_lost: bool,
		findings: Array = []) -> Dictionary:
	return {"type": "end", "record": record, "fingerprint": fingerprint, "decisions": decisions,
		"brain_lost": brain_lost, "findings": findings}


## A finding message for invariant failure `f` ({kind, severity, tick, time, message, snapshot, count}).
static func finding(f: Dictionary) -> Dictionary:
	var out := {"type": "finding"}
	out.merge(f)
	return out


## An infrastructure error message (the driver then exits with code 2).
static func error(reason: String, message: String) -> Dictionary:
	return {"type": "error", "reason": reason, "message": message}


## Parses one answer line from stdin: {id, answer, source, confidence}, or {"error": why} when malformed.
static func parse_answer(line: String) -> Dictionary:
	var json := JSON.new() # not JSON.parse_string: that logs an engine ERROR line for a malformed answer
	var parsed: Variant = json.data if json.parse(line.strip_edges()) == OK else null
	if not (parsed is Dictionary):
		return {"error": "answer is not a JSON object: %s" % line.strip_edges().left(120)}
	var d: Dictionary = parsed
	if int(d.get("v", -1)) != VERSION or String(d.get("type", "")) != "answer":
		return {"error": "not a v%d answer: %s" % [VERSION, line.strip_edges().left(120)]}
	if not d.has("id") or not d.has("answer"):
		return {"error": "answer needs id and answer"}
	return {"id": int(d.id), "answer": str(d.answer), "source": String(d.get("source", "unknown")),
		"confidence": d.get("confidence")}
