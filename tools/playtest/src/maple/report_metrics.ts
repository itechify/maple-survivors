// The report's metrics, cards and evaluations sections (adapter, #99): balance_run.gd's describe() fields from the
// round record (a tier chain: its last round), short enough to scan: milestones, a per-minute table (level, hits,
// kills, alive), potions, boss fights and MP shortfall; the cards taken; and the evaluations' results in report.json.
import { registerSection, runClock } from "../core/report.ts";
import type { ReportContext } from "../core/report.ts";
import type { EndMessage } from "../core/protocol.ts";
import type { Evaluations } from "./evaluations.ts";
import { num } from "../core/num.ts";

/** Every evaluation result in a few lines, flagged or not (Problems lists only what passed a threshold). */
export function evaluationSummary(e: Evaluations): string[] {
	const by = (k: string) => e.results.filter((r) => r.kind === k);
	const cls = (c: string) => (c === "none" ? "" : ` [${c}]`);
	const lines: string[] = [];
	const f = by("death_fairness")[0];
	const v = by("death_avoidable")[0];
	if (f || v) {
		lines.push(`- death: ${f ? `unfairness ${f.value} of 3 (confidence ${f.confidence})${cls(f.class)}` : ""}${f && v ? "; " : ""}` +
			`${v ? `avoidable by a careful player p ${v.value}${cls(v.class)}` : ""}; ${f?.detail ?? v?.detail ?? ""}`);
	}
	const m = by("minute_pacing");
	if (m.length) lines.push(`- minute pacing (dullness 0 busy .. 3 nothing happening): ${m.map((r) => `${r.label?.split(" (")[0].replace("minute ", "")}: ${r.value}${cls(r.class)}`).join(", ")}`);
	for (const r of by("movement")) lines.push(`- movement (stuck or awkward): p ${r.value}${cls(r.class)}`);
	const c = by("card_offer");
	if (c.length) {
		const low = c.reduce((a, b) => (b.value < a.value ? b : a));
		lines.push(`- card offers (meaningfulness 0 empty .. 3 strong, ${c.length} offers): lowest ${low.value} (confidence ${low.confidence})` +
			`${low.time !== undefined ? ` at ${runClock(low.time)}` : ""}; ${c.filter((r) => r.class !== "none").length} weak or empty`);
	}
	if (e.skipped_minutes.length) lines.push(`- not judged: ${e.skipped_minutes.join("; ")}`);
	if (e.errors.length) lines.push(`- failed: ${e.errors.join("; ")}`);
	lines.push("", `Thresholds (tools/playtest/src/maple/evaluations.ts RULES): flagged needs confidence >= ${e.thresholds.flag_confidence}. ` +
		"The exact facts sent are in evaluations.json `states`.");
	return lines;
}

/** balance_run.gd MILESTONES: 8, 10, 20 and 30 always shown, 40 and 50 when reached. */
const ALWAYS = [8, 10, 20, 30];
const IF_REACHED = [40, 50];

/** The round record to show: the run's, or a tier chain's last round. */
export function roundRecord(ctx: ReportContext): Record<string, unknown> | null {
	const rec = (ctx.data.end as EndMessage | undefined)?.record as Record<string, unknown> | undefined;
	if (!rec) return null;
	const rounds = rec.rounds;
	return Array.isArray(rounds) && rounds.length ? rounds[rounds.length - 1] as Record<string, unknown> : rec;
}

type Fight = { mob_id?: number; spawn_time?: number; death_time?: number; status?: string; elapsed?: number };
type Pots = Record<string, number> | undefined;

function fightText(f: Fight): string {
	const spawn = num(f.spawn_time, -1);
	if (spawn < 0) return `${f.mob_id} ${f.status === "skipped" ? "skipped (no mob image)" : "not spawned"}`;
	const death = num(f.death_time, -1);
	return death >= 0 ? `${f.mob_id} ${runClock(spawn)} -> dead at ${runClock(death)} (${Math.round(death - spawn)} s)`
		: `${f.mob_id} ${runClock(spawn)} -> alive at the end (${Math.round(num(f.elapsed))} s)`;
}

/** The metrics lines of record `r`. */
export function metricsLines(r: Record<string, unknown>): string[] {
	const reach = (r.reach ?? {}) as Record<string, number>;
	const ms = [...ALWAYS, ...IF_REACHED.filter((lv) => reach[String(lv)] !== undefined)]
		.map((lv) => `Lv ${lv} ${reach[String(lv)] !== undefined ? runClock(reach[String(lv)]) : "-"}`);
	const jobT = num(r.job_t, -1);
	const lines = [`Milestones: ${ms.join(", ")}; 1st job (Magician, 200) ${jobT >= 0 ? runClock(jobT) : "-"}.`, ""];
	const rows: Array<[string, unknown]> = [["level", r.level_by_min], ["hits", r.hits_by_min], ["kills (total)", r.kills_by_min],
		["alive (mean)", r.alive_by_min]];
	const width = Math.max(0, ...rows.map(([, v]) => (Array.isArray(v) ? v.length : 0)));
	if (width) {
		lines.push(`| minute | ${Array.from({ length: width }, (_, i) => i + 1).join(" | ")} |`, `|---|${"---|".repeat(width)}`);
		for (const [name, v] of rows) if (Array.isArray(v) && v.length) lines.push(`| ${name} | ${v.join(" | ")} |`);
		lines.push("");
	}
	const c = r.potions_collected as Pots;
	const u = r.potions_used as Pots;
	const l = r.potions_left as Pots;
	const pot = (k: string) => `${k.toUpperCase()} collected ${c?.[k] ?? 0}, used ${u?.[k] ?? 0}, left ${l?.[k] ?? 0}`;
	lines.push(`Potions: ${pot("hp")}; ${pot("mp")}.`);
	const fights = Array.isArray(r.boss_fights) ? (r.boss_fights as Fight[]) : [];
	lines.push(`Boss fights: ${fights.length ? fights.map(fightText).join("; ") : "none scheduled"}.`);
	lines.push(`MP short: ${num(r.mp_short_seconds)} s with a ready skill unaffordable. Full record: record.json.`);
	return lines;
}

registerSection({
	id: "metrics",
	order: 40,
	markdown: (ctx) => {
		const r = roundRecord(ctx);
		return r ? ["## Metrics", "", ...metricsLines(r)] : [];
	},
});

registerSection({
	id: "cards",
	order: 61,
	markdown: (ctx) => {
		const r = roundRecord(ctx);
		const taken = Array.isArray(r?.cards_taken) ? (r.cards_taken as unknown[]).map((x) => String(x).replace(/^-?\d+:/, "")) : [];
		return r ? [`Cards taken (${taken.length}): ${taken.join(", ") || "none"}.`] : [];
	},
});

registerSection({
	id: "evaluations",
	order: 65,
	markdown: (ctx) => {
		const e = ctx.data.evaluations as Evaluations | undefined;
		return e && e.status !== "skipped" ? ["## Evaluations", "", ...evaluationSummary(e)] : [];
	},
	json: (ctx) => {
		const e = ctx.data.evaluations as Evaluations | undefined;
		if (!e) return null;
		const { states: _states, ...rest } = e;
		return rest;
	},
});
