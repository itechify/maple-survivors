// The decision protocol (game-agnostic core): line format and message shapes between a game-side playtest driver
// and this CLI. The GDScript side is game/tools/playtest/playtest_protocol.gd; keep both headers in sync.
//
// Version 1. Two processes in lockstep over the driver's stdin/stdout:
//   - Driver -> CLI: one line per message on stdout, "@@PT " + a JSON object. Every other stdout line is a log line.
//   - CLI -> driver: one JSON line on stdin per `decide`, nothing else. The driver blocks (sim paused) until it
//     arrives; stdin EOF means "brain lost" and the driver finishes on its builtin baseline.
// Every message carries "v": 1 and "type". Shapes:
//   hello   {v, type:"hello", game, stage, seed, minutes, personality, brain}             once, before the round
//           (the Maple driver adds tier and character, #98; a replay compares every hello field but brain)
//   decide  {v, type:"decide", id, kind, tick, time, situation:{...}, options:[{id, ...}], baseline:{<policy>: id}}
//           id: 1, 2, 3... per run; kind: a decision kind of the game adapter (Maple: "card", "job", "tactic");
//           option ids are strings; baseline answers come from real game code (Maple: "sensible").
//           Maple's situation shape (facts plus named `buckets`, and `tactic` on tactic decides) is documented in
//           game/tools/playtest/playtest_situation.gd and typed in maple/situation.ts.
//   finding {v, type:"finding", kind, severity, tick, time, message, snapshot:{...}, count}   an invariant failure,
//           sent when it first happens; count 1 then (repeats only raise the end count)
//   end     {v, type:"end", record:{...}, fingerprint:{...}, decisions:[...], brain_lost, findings:[...]}  once,
//           after the round; findings are the de-duplicated findings with their final counts
//           decisions as applied: [{id, kind, tick, time, options, baseline, answer, source, confidence,
//           fallback_reason?}] (source "baseline" when an answer was invalid or the brain was lost)
//   error   {v, type:"error", reason, message}             infrastructure failure (e.g. reason "cache_missing")
//   answer  {v, type:"answer", id, answer, source, confidence}        CLI -> driver; answer is one option id,
//           source names the brain ("fallback:sensible", later "jev", "replay"), confidence is 0..1 or null.
// The driver reads answers with a 4096-byte buffer: keep answer lines short.

export const PROTOCOL_VERSION = 1;
export const PREFIX = "@@PT ";

export type Option = { id: string; [key: string]: unknown };

export type HelloMessage = {
	v: number; type: "hello"; game?: string; stage?: string; seed?: number; minutes?: number;
	personality?: string; brain?: string; [key: string]: unknown;
};
export type DecideMessage = {
	v: number; type: "decide"; id: number; kind: string; tick?: number; time?: number;
	situation?: Record<string, unknown>; options: Option[]; baseline: Record<string, string>; [key: string]: unknown;
};
export type FindingMessage = {
	v: number; type: "finding"; kind?: string; severity?: string; tick?: number; time?: number; message?: string;
	snapshot?: Record<string, unknown>; count?: number; [key: string]: unknown;
};
/** One decision as the driver applied it (the `end` message's decisions). */
export type AppliedDecision = {
	id: number; kind: string; tick?: number; time?: number; options?: string[]; baseline?: string; answer: string;
	source: string; confidence?: number | null; fallback_reason?: string;
};
export type EndMessage = {
	v: number; type: "end"; record: Record<string, unknown>; fingerprint?: Record<string, unknown>;
	decisions?: AppliedDecision[]; brain_lost?: boolean; findings?: Array<Record<string, unknown>>; [key: string]: unknown;
};
export type ErrorMessage = { v: number; type: "error"; reason: string; message?: string; [key: string]: unknown };
export type DriverMessage = HelloMessage | DecideMessage | FindingMessage | EndMessage | ErrorMessage;

/** One answer to a `decide` (the CLI's side of the protocol). */
export type Answer = { id: number; answer: string; source: string; confidence: number | null };

export type ParsedLine =
	| { kind: "log"; line: string }
	| { kind: "message"; message: DriverMessage }
	| { kind: "invalid"; line: string; error: string };

const TYPES = new Set(["hello", "decide", "finding", "end", "error"]);

/** Classifies one driver stdout line: a protocol message, a log line, or a protocol violation. */
export function parseLine(raw: string): ParsedLine {
	const line = raw.endsWith("\r") ? raw.slice(0, -1) : raw;
	if (!line.startsWith(PREFIX)) return { kind: "log", line };
	let value: unknown;
	try {
		value = JSON.parse(line.slice(PREFIX.length));
	} catch (e) {
		return { kind: "invalid", line, error: `not JSON: ${(e as Error).message}` };
	}
	if (typeof value !== "object" || value === null || Array.isArray(value)) {
		return { kind: "invalid", line, error: "not a JSON object" };
	}
	const msg = value as Record<string, unknown>;
	if (msg.v !== PROTOCOL_VERSION) return { kind: "invalid", line, error: `protocol version ${String(msg.v)}, expected ${PROTOCOL_VERSION}` };
	if (typeof msg.type !== "string" || !TYPES.has(msg.type)) return { kind: "invalid", line, error: `unknown type ${String(msg.type)}` };
	if (msg.type === "decide") {
		if (typeof msg.id !== "number" || typeof msg.kind !== "string") return { kind: "invalid", line, error: "decide needs id and kind" };
		if (!Array.isArray(msg.options) || typeof msg.baseline !== "object" || msg.baseline === null) {
			return { kind: "invalid", line, error: "decide needs options and baseline" };
		}
	}
	if (msg.type === "end" && (typeof msg.record !== "object" || msg.record === null)) {
		return { kind: "invalid", line, error: "end needs a record" };
	}
	return { kind: "message", message: msg as DriverMessage };
}

/** The stdin line answering one `decide`. */
export function serializeAnswer(a: Answer): string {
	return JSON.stringify({ v: PROTOCOL_VERSION, type: "answer", id: a.id, answer: a.answer, source: a.source,
		confidence: a.confidence }) + "\n";
}
