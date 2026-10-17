// Exact replay (game-agnostic core, ticket #98): a replay brain answers each `decide` from a recorded run's
// decisions.jsonl in order, without any network or key, and checks that the driver asks the same decisions (kind,
// options in on-screen order, tick). After the round, `finish` compares the driver's applied decisions with the
// recording, and `compareFingerprints` compares the end fingerprint with the recorded fingerprint.json. Every mismatch
// is a divergence; the adapter reports them as `replay_divergence` problems (exit code 1). After the first divergence
// the brain answers the baseline, so the driver still reaches `end` and the report can name every differing field.
import fs from "node:fs";
import path from "node:path";
import type { DecideMessage } from "./protocol.ts";
import type { Brain, BrainAnswer, DecisionRecord } from "./session.ts";

/** A recorded run directory as a replay needs it: decisions.jsonl (in order), fingerprint.json (null if the run
 * had no end) and scenario.json (what the run was: the scenario, the cell, every flag value and the driver's hello). */
export type Recording = {
	dir: string; decisions: DecisionRecord[]; fingerprint: Record<string, unknown> | null;
	scenario: Record<string, unknown>; hello: Record<string, unknown> | null;
};

/** Reads run directory `dir` for a replay, or says why it cannot be replayed. */
export function readRecording(dir: string): Recording | { error: string } {
	const file = (n: string) => path.join(dir, n);
	if (!fs.existsSync(file("scenario.json"))) {
		return { error: `${dir} is not a replayable run directory: no scenario.json (runs recorded before #98 have none)` };
	}
	if (!fs.existsSync(file("decisions.jsonl"))) return { error: `${dir} is not a replayable run directory: no decisions.jsonl` };
	try {
		const scenario = JSON.parse(fs.readFileSync(file("scenario.json"), "utf8")) as Record<string, unknown>;
		const decisions = fs.readFileSync(file("decisions.jsonl"), "utf8").split("\n").filter((l) => l.trim())
			.map((l) => JSON.parse(l) as DecisionRecord);
		const fingerprint = fs.existsSync(file("fingerprint.json"))
			? (JSON.parse(fs.readFileSync(file("fingerprint.json"), "utf8")) as Record<string, unknown>) : null;
		const hello = (scenario.hello as Record<string, unknown> | undefined) ?? null;
		return { dir, decisions, fingerprint, scenario, hello };
	} catch (e) {
		return { error: `${dir}: cannot read the recording (${(e as Error).message})` };
	}
}

/** Hello fields that differ between the recorded and the replayed driver (its echo of what it was asked to play:
 * stage, seed, personality, and anything a later driver echoes, e.g. a motor seed). The brain mode is ignored. */
export function compareHello(recorded: Record<string, unknown> | null, replayed: Record<string, unknown> | undefined): Divergence[] {
	if (!recorded || !replayed) return [];
	const skip = new Set(["v", "type", "brain"]);
	const keys = [...new Set([...Object.keys(recorded), ...Object.keys(replayed)])].filter((k) => !skip.has(k));
	return keys.filter((k) => JSON.stringify(recorded[k]) !== JSON.stringify(replayed[k]))
		.map((k) => ({ field: `hello.${k}`, message: `hello.${k}: replay ${JSON.stringify(replayed[k]) ?? "missing"}, recorded ${JSON.stringify(recorded[k]) ?? "missing"}` }));
}

/** One replay mismatch: `decision` is the decision id it concerns (absent for run-level ones), `field` the
 * fingerprint field for fingerprint mismatches. */
export type Divergence = { message: string; decision?: number; field?: string };

/** Recorded fields copied into the replay's decision records (the presented order Jev saw, the on-screen order). */
const CARRIED = ["presented_order", "screen_order"];

export type ReplayBrain = Brain & {
	/** Divergences seen so far while answering. */
	divergences(): Divergence[];
	/** Every divergence of the replay, given the decisions the driver applied (its `end` message, or the CLI's own
	 * records when there is no end): mismatches seen while answering, decisions missing at the end, and applied
	 * answers that differ from the recording. */
	finish(applied: ReadonlyArray<Pick<DecisionRecord, "id" | "answer"> & { fallback_reason?: string }>): Divergence[];
};

const list = (xs: readonly string[]) => `[${xs.join(", ")}]`;

/** A brain that replays `recording` (decisions.jsonl lines, in order). */
export function createReplayBrain(recording: readonly DecisionRecord[]): ReplayBrain {
	const found: Divergence[] = [];
	let asked = 0;
	const baseline = (d: DecideMessage) => d.baseline.sensible ?? d.options[0]?.id ?? "";
	const check = (d: DecideMessage, r: DecisionRecord | undefined): string | null => {
		if (!r) return `decision ${d.id} (${d.kind}) is not in the recording (${recording.length} decisions)`;
		if (r.id !== d.id) return `decision ${d.id}: recorded decision at this position has id ${r.id}`;
		if (r.kind !== d.kind) return `decision ${d.id}: kind ${d.kind}, recorded ${r.kind}`;
		const ids = d.options.map((o) => String(o.id));
		const rec = (r.options ?? []).map(String);
		if (ids.join("\u0000") !== rec.join("\u0000")) {
			const same = ids.length === rec.length && [...ids].sort().join("\u0000") === [...rec].sort().join("\u0000");
			return `decision ${d.id}: options ${list(ids)}, recorded ${list(rec)}${same ? " (same options in another order)" : ""}`;
		}
		if (typeof r.tick === "number" && typeof d.tick === "number" && r.tick !== d.tick) {
			return `decision ${d.id}: tick ${d.tick}, recorded ${r.tick}`;
		}
		return null;
	};
	return {
		name: "replay",
		decide(d: DecideMessage): BrainAnswer {
			const r = recording[asked];
			asked++;
			const problem = found.length ? null : check(d, r);
			if (problem) found.push({ message: problem, decision: d.id });
			if (found.length || !r) {
				return { answer: baseline(d), source: "replay", confidence: null, reason: "replay diverged: baseline" };
			}
			const extra: Record<string, unknown> = { recorded_source: r.source };
			for (const k of CARRIED) if (r[k] !== undefined) extra[k] = r[k];
			return { answer: r.answer, source: "replay", confidence: typeof r.confidence === "number" ? r.confidence : null, extra };
		},
		divergences: () => [...found],
		finish(applied) {
			const out = [...found];
			if (!found.length && applied.length < recording.length) {
				out.push({ message: `the replay made ${applied.length} decisions, the recording has ${recording.length}` });
			}
			const byId = new Map(recording.map((r) => [r.id, r]));
			for (const a of applied) {
				const r = byId.get(a.id);
				if (!r || r.answer === a.answer) continue;
				if (found.some((f) => f.decision !== undefined && f.decision <= a.id)) break;
				out.push({ decision: a.id, message: `decision ${a.id}: the driver applied ${a.answer}, recorded ${r.answer}` +
					(a.fallback_reason ? ` (${a.fallback_reason})` : "") });
				break;
			}
			return out;
		},
	};
}

/** Divergences in report order: decision-level ones by decision id (the earliest first), then run-level ones (missing
 * decisions, hello fields, fingerprint fields) in their given order. */
export function orderDivergences(divs: readonly Divergence[]): Divergence[] {
	const byDecision = divs.filter((d) => d.decision !== undefined).sort((a, b) => (a.decision ?? 0) - (b.decision ?? 0));
	return [...byDecision, ...divs.filter((d) => d.decision === undefined)];
}

const canon = (v: unknown): string => JSON.stringify(v);

/** Fingerprint fields that differ between the recorded and the replayed fingerprint, in the recorded field order
 * (then fields only the replay has). Numbers compare by value (180.0 equals 180). */
export function compareFingerprints(recorded: Record<string, unknown>, replayed: Record<string, unknown>): Divergence[] {
	const keys = [...Object.keys(recorded), ...Object.keys(replayed).filter((k) => !(k in recorded))];
	const out: Divergence[] = [];
	for (const k of keys) {
		if (canon(recorded[k]) === canon(replayed[k])) continue;
		out.push({ field: k, message: `fingerprint.${k}: replay ${canon(replayed[k]) ?? "missing"}, recorded ${canon(recorded[k]) ?? "missing"}` });
	}
	return out;
}
