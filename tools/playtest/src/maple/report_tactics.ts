// The report's tactic section (adapter, #95): time per tactic, switches and what triggered the tactic decisions, from
// the round record's `tactics` (playtest_policy.gd tactic_summary) and the tactic decisions by source.
import { registerSection, runClock } from "../core/report.ts";
import type { ReportContext } from "../core/report.ts";
import type { EndMessage } from "../core/protocol.ts";

/** tier C: switch log lines shown in report.md (report.json keeps all). */
const LOG_LINES = 20;

type Switch = { tick?: number; time?: number; from?: string; to?: string; trigger?: string; source?: string };
type TacticsRecord = {
	seconds?: Record<string, number>; shares?: Record<string, number>; switches?: number; decisions?: number;
	triggers?: Record<string, number>; platforms_visited?: number; log?: Switch[];
};


function tacticsOf(ctx: ReportContext): TacticsRecord | null {
	const t = (ctx.data.end as EndMessage | undefined)?.record?.tactics;
	return t && typeof t === "object" ? (t as TacticsRecord) : null;
}

function bySource(ctx: ReportContext): Record<string, number> {
	const out: Record<string, number> = {};
	for (const d of ctx.decisions) if (d.kind === "tactic") out[d.source] = (out[d.source] ?? 0) + 1;
	return out;
}

registerSection({
	id: "tactics",
	order: 50,
	markdown: (ctx) => {
		const t = tacticsOf(ctx);
		if (!t) return [];
		const seconds = t.seconds ?? {};
		const shares = t.shares ?? {};
		const lines = ["## Tactics", "",
			`Tactic decisions: ${t.decisions ?? 0}, switches: ${t.switches ?? 0}, platforms stood on: ${t.platforms_visited ?? "?"}. Decided by: ${
				Object.entries(bySource(ctx)).map(([s, n]) => `${s} ${n}`).join(", ") || "-"}.`, "",
			"| tactic | seconds | share |", "|---|---|---|",
			...Object.keys(seconds).map((k) => `| ${k} | ${seconds[k].toFixed(1)} | ${((shares[k] ?? 0) * 100).toFixed(1)}% |`)];
		const triggers = Object.entries(t.triggers ?? {});
		if (triggers.length) lines.push("", `Triggers: ${triggers.map(([k, n]) => `${k} ${n}`).join(", ")}.`);
		const log = t.log ?? [];
		if (log.length) {
			lines.push("", "Switches:", "");
			for (const s of log.slice(0, LOG_LINES)) {
				lines.push(`- ${runClock(s.time ?? 0)} (tick ${s.tick ?? "?"}) ${s.from} -> ${s.to} (${s.trigger}, ${s.source})`);
			}
			if (log.length > LOG_LINES) lines.push(`- ... ${log.length - LOG_LINES} more in report.json`);
		}
		return lines;
	},
	json: (ctx) => {
		const t = tacticsOf(ctx);
		return t ? { ...t, by_source: bySource(ctx) } : null;
	},
});
