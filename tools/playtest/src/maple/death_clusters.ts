// Death clusters across a matrix (adapter, #99): a deterministic aggregate insight, computed in code from the cells'
// records, kept apart from invariant failures. Deaths are grouped by run time: the run-time window of `windowS`
// seconds holding the most deaths is a pattern when it holds the deaths of at least `share` of the cells; its deaths
// are taken out and the next window is tried. Each cluster is broken down by context: boss alive at death, the last
// hit's source and personality. The representative cell is the one at the cluster's median death time (the lower
// middle for an even count). Patterns never change an exit code.
import fs from "node:fs";
import path from "node:path";
import type { CellReport } from "../core/aggregate.ts";
import { bossAliveAt, finalRound, hitSource, readJsonl } from "./eval_facts.ts";
import type { Hit } from "./eval_facts.ts";

/** tier C: the last hit counts as the killing blow when it landed within this many run seconds of the death. */
export const LAST_HIT_S = 2;

export type DeathCell = { cell: string; dir: string; personality: string; seed: string; time: number; bossAlive: boolean;
	lastHit: string; replay: string | null };

const header = (c: CellReport) => (c.report?.header ?? {}) as Record<string, string>;
const num = (v: unknown, d = 0) => (typeof v === "number" && Number.isFinite(v) ? v : d);

/** The DEAD cells of `cells` with their death time, boss alive at death and last hit source (from hits.jsonl; a cell
 * recorded before hits.jsonl existed falls back to the record's boss hits, else "unknown (no hits.jsonl)"). */
export function deathCells(cells: readonly CellReport[]): DeathCell[] {
	return cells.flatMap((c) => {
		let record: Record<string, unknown>;
		try {
			record = JSON.parse(fs.readFileSync(path.join(c.dir, "record.json"), "utf8"));
		} catch {
			return [];
		}
		const hitsFile = path.join(c.dir, "hits.jsonl");
		const round = finalRound({ record, timeline: [], hits: readJsonl<Hit>(hitsFile), decisions: [], problems: [] });
		if (round.record.state !== "DEAD") return [];
		const t = num(round.record.time);
		const near = (x: { time?: number }) => typeof x.time === "number" && x.time <= t + 1e-6 && t - x.time <= LAST_HIT_S;
		let lastHit: string;
		const last = round.hits.filter(near).at(-1);
		if (last) lastHit = hitSource(last).replace(/ \(.*\)$/, "");
		else if (fs.existsSync(hitsFile)) lastHit = "not recorded";
		else {
			const bossHits = Array.isArray(round.record.boss_hits) ? round.record.boss_hits as Array<{ time?: number; source_kind?: string }> : [];
			const b = bossHits.filter(near).at(-1);
			lastHit = b ? hitSource({ boss: true, source: String(b.source_kind ?? "other") }).replace(/ \(.*\)$/, "") : "unknown (no hits.jsonl)";
		}
		const replay = (c.report?.problems as { replay?: string } | undefined)?.replay ?? null;
		return [{ cell: c.name, dir: c.dir, personality: header(c).personality ?? "?", seed: String(header(c).seed ?? "?"), time: t,
			bossAlive: bossAliveAt(round.record, t) !== null, lastHit, replay }];
	});
}

export type DeathCluster = {
	from: number; to: number; window_s: number; share: number;
	cells: DeathCell[]; cells_total: number; deaths_total: number;
	boss_alive: { yes: number; no: number };
	last_hit: Record<string, number>;
	/** Per personality: deaths in the cluster, its cells in the matrix, and the time span of those deaths. */
	personalities: Record<string, { in: number; of: number; from: number; to: number }>;
	representative: DeathCell;
};

/** The death clusters of `deaths` over the matrix's `cells` (greedy: the fullest window first). */
export function deathClusters(deaths: readonly DeathCell[], cells: readonly CellReport[], o: { windowS: number; share: number }): DeathCluster[] {
	const total = cells.length;
	const of: Record<string, number> = {};
	for (const c of cells) of[header(c).personality ?? "?"] = (of[header(c).personality ?? "?"] ?? 0) + 1;
	let left = [...deaths].sort((a, b) => a.time - b.time || a.cell.localeCompare(b.cell));
	const out: DeathCluster[] = [];
	while (left.length >= 2) {
		let best = { i: 0, j: 0 };
		for (let i = 0, j = 0; i < left.length; i++) {
			while (j + 1 < left.length && left[j + 1].time - left[i].time <= o.windowS + 1e-6) j++;
			if (j - i > best.j - best.i) best = { i, j };
		}
		const inside = left.slice(best.i, best.j + 1);
		if (inside.length < 2 || inside.length / Math.max(1, total) < o.share - 1e-9) break;
		const lastHit: Record<string, number> = {};
		const pers: DeathCluster["personalities"] = {};
		for (const d of inside) {
			lastHit[d.lastHit] = (lastHit[d.lastHit] ?? 0) + 1;
			const p = pers[d.personality] ?? { in: 0, of: of[d.personality] ?? 0, from: d.time, to: d.time };
			pers[d.personality] = { ...p, in: p.in + 1, from: Math.min(p.from, d.time), to: Math.max(p.to, d.time) };
		}
		out.push({ from: inside[0].time, to: inside[inside.length - 1].time, window_s: o.windowS, share: o.share, cells: inside,
			cells_total: total, deaths_total: deaths.length,
			boss_alive: { yes: inside.filter((d) => d.bossAlive).length, no: inside.filter((d) => !d.bossAlive).length },
			last_hit: Object.fromEntries(Object.entries(lastHit).sort((a, b) => b[1] - a[1])),
			personalities: Object.fromEntries(Object.entries(pers).sort((a, b) => b[1].in / Math.max(1, b[1].of) - a[1].in / Math.max(1, a[1].of))),
			representative: inside[Math.floor((inside.length - 1) / 2)] });
		left = [...left.slice(0, best.i), ...left.slice(best.j + 1)];
	}
	return out;
}
