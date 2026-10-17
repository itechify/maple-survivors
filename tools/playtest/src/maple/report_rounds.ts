// The report's tier chain section (adapter, #98): one row per round of a chain record (rounds[]; record_tier<N>.json
// in the run directory). The outcome section above shows the last round played.
import { registerSection, runClock } from "../core/report.ts";
import type { EndMessage } from "../core/protocol.ts";

type Round = { tier?: number; stage?: string; seed?: number; state?: string; time?: number; level?: number; job?: number;
	kills?: number; cards_taken?: unknown[]; start_character?: { level?: number; job_id?: number } };


registerSection({
	id: "rounds",
	order: 11,
	markdown: (ctx) => {
		const rec = (ctx.data.end as EndMessage | undefined)?.record;
		const rounds = Array.isArray(rec?.rounds) ? (rec.rounds as Round[]) : null;
		if (!rounds) return [];
		const target = Number(rec?.target_tier ?? rounds.length);
		return ["## Rounds", "", `Tier chain through tier ${target}: ${rounds.length} round(s) played; only a CLEARED round feeds the next.`, "",
			"| tier | stage | round seed | start | outcome | level | job | kills | cards | record |", "|---|---|---|---|---|---|---|---|---|---|",
			...rounds.map((r, i) => `| ${r.tier ?? i + 1} | ${r.stage ?? "?"} | ${r.seed ?? "?"} | ` +
				`Lv ${r.start_character?.level ?? "?"} job ${r.start_character?.job_id ?? "?"} | ` +
				`${r.state ?? "?"} ${typeof r.time === "number" ? runClock(r.time) : "?"} | Lv ${r.level ?? "?"} | ${r.job ?? "?"} | ` +
				`${r.kills ?? "?"} | ${Array.isArray(r.cards_taken) ? r.cards_taken.length : 0} | \`record_tier${r.tier ?? i + 1}.json\` |`)];
	},
	json: (ctx) => {
		const rec = (ctx.data.end as EndMessage | undefined)?.record;
		return Array.isArray(rec?.rounds) ? (rec.rounds as Round[]).map((r) => ({ tier: r.tier, stage: r.stage, seed: r.seed,
			state: r.state, time: r.time, level: r.level, job: r.job, kills: r.kills })) : null;
	},
});
