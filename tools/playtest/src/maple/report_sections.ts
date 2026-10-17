// Maple Survivors report sections (adapter), registered into the core report registry on import. Later tickets add
// their sections (metrics, invariants, evaluations) in their own modules and import them here.
import { registerSection } from "../core/report.ts";
import type { EndMessage } from "../core/protocol.ts";

const mmss = (t: number) => `${Math.floor(t / 60)}:${String(Math.floor(t % 60)).padStart(2, "0")}`;

/** The round's outcome from the end message's record (Maple round record, balance_run.gd run_one). */
export function outcomeOf(end: EndMessage | undefined) {
	if (!end) return null;
	const r = end.record as Record<string, unknown>;
	const num = (k: string) => (typeof r[k] === "number" ? (r[k] as number) : null);
	return { state: String(r.state ?? "?"), time: num("time"), level: num("level"), job: num("job"), kills: num("kills"),
		cards_taken: Array.isArray(r.cards_taken) ? r.cards_taken.length : 0, brain_lost: end.brain_lost === true,
		fingerprint: end.fingerprint ?? null };
}

registerSection({
	id: "outcome",
	order: 10,
	markdown: (ctx) => {
		const o = outcomeOf(ctx.data.end as EndMessage | undefined);
		if (!o) return ["## Outcome", "", "No round record (the driver sent no end message)."];
		const lines = ["## Outcome", "",
			`**${o.state}** at ${o.time === null ? "?" : mmss(o.time)}, Lv ${o.level ?? "?"}, job ${o.job ?? "?"}, ` +
			`kills ${o.kills ?? "?"}, cards taken ${o.cards_taken}`];
		if (o.state === "TIMEOUT") lines.push("", "TIMEOUT means the time cap ended a living round; it is not a clear.");
		if (o.brain_lost) lines.push("", "The brain was lost during the round (stdin closed); the driver finished on its builtin baseline.");
		return lines;
	},
	json: (ctx) => outcomeOf(ctx.data.end as EndMessage | undefined),
});
