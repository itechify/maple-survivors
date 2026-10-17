// Maple Survivors report sections (adapter), registered into the core report registry on import. Later tickets add
// their sections (metrics, invariants, evaluations) in their own modules and import them here.
import { registerSection, setSnapshotFormatter, genericSnapshot, runClock } from "../core/report.ts";
import type { EndMessage } from "../core/protocol.ts";
import "./report_tactics.ts";
import "./report_rounds.ts";
import { num } from "../core/num.ts";

/** A Maple invariant snapshot (game/tools/playtest/playtest_invariants.gd `snapshot`) as Problems sub-bullets. */
export function mapleSnapshot(s: Record<string, unknown>): string[] {
	if (typeof s.x !== "number" || typeof s.y !== "number") return genericSnapshot(s);
	const mobs = Array.isArray(s.mobs) ? (s.mobs as Array<Record<string, unknown>>) : [];
	return [
		`${s.state ?? "?"}, Lv ${s.level ?? "?"}, job ${s.job ?? "?"}, HP ${s.hp ?? "?"}/${s.max_hp ?? "?"}, ` +
			`MP ${s.mp ?? "?"}/${s.max_mp ?? "?"}, tactic ${s.tactic ?? "?"}`,
		`position (${s.x}, ${s.y}), foothold ${s.fh ?? "?"}, platform ${s.platform ?? "?"}`,
		`nearest mobs: ${mobs.length ? mobs.map((m) => `${m.mob}${m.boss ? " (boss)" : ""} at ${m.d} px (${m.x}, ${m.y})`).join("; ") : "none"}`,
	];
}

setSnapshotFormatter(mapleSnapshot);


/** The round's outcome from the end message's record (Maple round record, balance_run.gd run_one). */
export function outcomeOf(end: EndMessage | undefined) {
	if (!end) return null;
	const r = end.record as Record<string, unknown>;
	const n = (k: string) => num(r[k], null);
	return { state: String(r.state ?? "?"), time: n("time"), level: n("level"), job: n("job"), kills: n("kills"),
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
			`**${o.state}** at ${o.time === null ? "?" : runClock(o.time)}, Lv ${o.level ?? "?"}, job ${o.job ?? "?"}, ` +
			`kills ${o.kills ?? "?"}, cards taken ${o.cards_taken}`];
		if (o.state === "TIMEOUT") lines.push("", "TIMEOUT means the time cap ended a living round; it is not a clear.");
		if (o.brain_lost) lines.push("", "The brain was lost during the round (stdin closed); the driver finished on its builtin baseline.");
		return lines;
	},
	json: (ctx) => outcomeOf(ctx.data.end as EndMessage | undefined),
});
