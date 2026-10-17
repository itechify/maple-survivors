// The report's brain facts (#94): which brain was requested and used, why any fallback happened, and the Jev model,
// request count, tokens and Jev-sourced share. `brainHeader` gives the header lines; the `jev` section adds the raw
// client stats to report.json.
import { registerSection } from "../core/report.ts";
import type { DecisionRecord } from "../core/session.ts";
import type { JevStats } from "../core/jev_client.ts";

export type BrainFacts = {
	/** --brain as given: auto, jev, fallback or builtin. */
	requested: string;
	/** What answered: the Jev brain (with per-decision fallbacks), the fallback brain, or the driver's builtin. */
	mode: "jev" | "fallback" | "builtin";
	/** Why the fallback brain was used for the whole run (no key), if it was not requested. */
	noJevReason?: string;
	keyFrom?: "process" | "user";
	stats?: JevStats;
	decisions: readonly DecisionRecord[];
	brainLost?: boolean;
};

const BASELINE = "the driver's baseline, BotInput.pick_card_for / pick_job";

/** Header lines (label, value) for the brain. */
export function brainHeader(f: BrainFacts): Array<[string, string]> {
	const n = f.decisions.length;
	const jev = f.decisions.filter((d) => d.source === "jev").length;
	const lost = f.brainLost ? "; the brain was lost mid-round, later decisions took the driver's baseline" : "";
	let used: string;
	let fallback: string;
	if (f.mode === "builtin") {
		used = `builtin (the driver answered every decision with ${BASELINE}; no pipe)`;
		fallback = "none (builtin brain)";
	} else if (f.mode === "fallback") {
		used = `fallback:sensible (deterministic: ${BASELINE})`;
		fallback = f.noJevReason ?? "requested (--brain=fallback)";
	} else {
		used = jev === n ? "jev" : `jev, fallback on ${n - jev}/${n} decisions`;
		fallback = jev === n ? "none" : fallbackReasons(f.decisions, n);
	}
	return [["brain requested", f.requested], ["brain used", used + lost], ["fallback", fallback], ["Jev", jevLine(f, jev, n)]];
}

/** "reason on k/n decisions; ..." over the decisions Jev did not answer, most frequent first. */
function fallbackReasons(decisions: readonly DecisionRecord[], n: number): string {
	const counts = new Map<string, number>();
	for (const d of decisions) {
		if (d.source === "jev") continue;
		const why = String(d.fallback_reason ?? d.reason ?? "unknown reason");
		counts.set(why, (counts.get(why) ?? 0) + 1);
	}
	return [...counts.entries()].sort((a, b) => b[1] - a[1]).map(([why, k]) => `${why} on ${k}/${n} decisions`).join("; ");
}

function jevLine(f: BrainFacts, jev: number, n: number): string {
	const s = f.stats;
	if (f.mode !== "jev" || !s) return "not used";
	const pct = n ? Math.round((jev / n) * 100) : 0;
	const models = s.models.length ? s.models.join(", ") : "no model reported";
	const key = f.keyFrom === "user" ? "key from the Windows user env" : "key from the process env";
	return `model ${models} (requested ${s.model_requested}), ${s.requests} requests (cap ${s.max_requests}), ` +
		`${s.input_tokens} input + ${s.output_tokens} output tokens, Jev-sourced ${jev}/${n} decisions (${pct}%), ${key}`;
}

registerSection({
	id: "jev",
	order: 1,
	markdown: () => [],
	json: (ctx) => (ctx.data.jev as JevStats | undefined) ?? null,
});
