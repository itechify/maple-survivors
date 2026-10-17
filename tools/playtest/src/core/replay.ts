// Exact replay (game-agnostic core, ticket #98): a replay brain answers each `decide` from a recorded run's
// decisions.jsonl in order, without any network or key, and checks that the driver asks the same decisions (kind,
// options in on-screen order, tick). After the round, `finish` compares the driver's applied decisions with the
// recording, and `compareFingerprints` compares the end fingerprint with the recorded fingerprint.json. Every mismatch
// is a divergence; the adapter reports them as `replay_divergence` problems (exit code 1). After the first divergence
// the brain answers the baseline, so the driver still reaches `end` and the report can name every differing field.
import type { DecideMessage } from "./protocol.ts";
import type { Brain, BrainAnswer, DecisionRecord } from "./session.ts";

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
