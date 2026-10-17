// The aggregate summary of a multi-run scenario (adapter, tickets #98 / #99): summary.md / summary.json over the cells'
// run directories. A verdict and the next command come first. Then the outcomes table, then Problems in a run report's
// order: deterministic failures de-duplicated across cells by kind and location (core/aggregate.ts), patterns
// (deterministic aggregate insights: death clusters, death_clusters.ts), Jev-flagged and needs-review opinions grouped
// by kind across cells; then metric spreads (time, level, kills, cards taken) and decisions by source. Its exit code is
// the worst over the cells: patterns and opinions never change it (a cell's --strict-eval already counted in its own).
import { readCells, dedupeProblems, worstExit, cellExit, cellProblems } from "../core/aggregate.ts";
import type { CellReport, ProblemGroup } from "../core/aggregate.ts";
import { runClock } from "../core/report.ts";
import type { Opinion } from "../core/report.ts";
import { deathCells, deathClusters } from "./death_clusters.ts";
import type { DeathCluster } from "./death_clusters.ts";
import { DEFAULT_CLUSTER_SHARE, DEFAULT_CLUSTER_WINDOW_S } from "./eval_flags.ts";

type Outcome = { state?: string; time?: number | null; level?: number | null; job?: number | null; kills?: number | null;
	cards_taken?: number };
export type Spread = { n: number; min: number; median: number; max: number } | { n: 0 };

/** n, min, median and max of the numbers in `xs`. */
export function spread(xs: Array<number | null | undefined>): Spread {
	const v = xs.filter((x): x is number => typeof x === "number").sort((a, b) => a - b);
	if (!v.length) return { n: 0 };
	const mid = v.length >> 1;
	const median = v.length % 2 ? v[mid] : (v[mid - 1] + v[mid]) / 2;
	return { n: v.length, min: v[0], median, max: v[v.length - 1] };
}

const outcomeOf = (c: CellReport): Outcome | null => (c.report?.outcome as Outcome | null | undefined) ?? null;
const header = (c: CellReport): Record<string, string> => (c.report?.header as Record<string, string> | undefined) ?? {};
const windowed = (replay: string | null | undefined, t: number) => (replay ? `${replay} --windowed --shots-at=${Math.round(t * 10) / 10}` : null);

/** Opinions of one class grouped by kind across cells: the cells, and the earliest entry with its cell's replay. */
export type OpinionGroup = { kind: string; title: string; class: "flagged" | "review"; cells: string[];
	first: { cell: string; time?: number; message: string; evidence: string; replay: string | null } };

function opinionGroups(cells: readonly CellReport[], cls: "flagged" | "review"): OpinionGroup[] {
	const groups = new Map<string, OpinionGroup>();
	for (const c of cells) {
		const p = (c.report?.problems ?? {}) as { jev_flagged?: Opinion[]; needs_review?: Opinion[]; replay?: string };
		for (const o of (cls === "flagged" ? p.jev_flagged : p.needs_review) ?? []) {
			const first = { cell: c.name, time: o.time, message: o.message, evidence: o.evidence, replay: p.replay ?? null };
			const g = groups.get(o.kind);
			if (!g) groups.set(o.kind, { kind: o.kind, title: o.title, class: cls, cells: [c.name], first });
			else {
				if (!g.cells.includes(c.name)) g.cells.push(c.name);
				if ((o.time ?? Infinity) < (g.first.time ?? Infinity)) g.first = first;
			}
		}
	}
	return [...groups.values()].sort((a, b) => b.cells.length - a.cells.length || (a.first.time ?? Infinity) - (b.first.time ?? Infinity));
}

/** Cells whose report.json has no evaluations result (recorded before #99, or skipped). */
const notEvaluated = (cells: readonly CellReport[]) => cells.filter((c) => {
	const e = c.report?.evaluations as { status?: string } | null | undefined;
	return !e || e.status === "skipped";
});

export type MatrixSummary = {
	json: {
		scenario: string; exit_code: number; outcomes: Record<string, number>;
		cells: Array<Record<string, unknown>>; problems: ProblemGroup[]; patterns: DeathCluster[];
		jev_flagged: OpinionGroup[]; needs_review: OpinionGroup[]; not_evaluated: string[]; verdict: string[];
		metrics: Record<string, Spread>; decisions_by_source: Record<string, number>;
	};
	markdown: string;
};

const pct = (k: number, n: number) => `${Math.round((k / Math.max(1, n)) * 100)}%`;
const cellsWord = (n: number) => `${n} cell${n === 1 ? "" : "s"}`;

/** The summary of scenario `scenario` over the cell directories `dirs`; `cluster` sets the death-cluster window and
 * share. */
export function matrixSummary(scenario: string, dirs: readonly string[],
	cluster = { windowS: DEFAULT_CLUSTER_WINDOW_S, share: DEFAULT_CLUSTER_SHARE }): MatrixSummary {
	const cells = readCells(dirs);
	const outcomes: Record<string, number> = {};
	const bySource: Record<string, number> = {};
	const rows = cells.map((c) => {
		const o = outcomeOf(c);
		const state = o?.state ?? "no end";
		outcomes[state] = (outcomes[state] ?? 0) + 1;
		const dec = c.report?.decisions as { total?: number; by_source?: Record<string, number> } | undefined;
		const src = dec?.by_source ?? {};
		for (const [k, n] of Object.entries(src)) bySource[k] = (bySource[k] ?? 0) + n;
		const decisions = { jev: src.jev ?? 0, total: dec?.total ?? Object.values(src).reduce((a, n) => a + n, 0) };
		const problems = (c.report?.problems ?? {}) as { infrastructure?: string[]; replay?: string; rerun?: string };
		return { cell: c.name, dir: c.dir, personality: header(c).personality ?? "?", seed: header(c).seed ?? "?",
			stage: header(c).stage ?? "?", exit_code: cellExit(c), outcome: o, decisions, problems: cellProblems(c).length,
			infrastructure: c.error ? [c.error] : problems.infrastructure ?? [], replay: problems.replay ?? null,
			rerun: problems.rerun ?? null };
	});
	const outs = cells.map(outcomeOf).filter((o): o is Outcome => o !== null);
	const metrics = { time: spread(outs.map((o) => o.time)), level: spread(outs.map((o) => o.level)),
		kills: spread(outs.map((o) => o.kills)), cards_taken: spread(outs.map((o) => o.cards_taken)) };
	const groups = dedupeProblems(cells);
	const patterns = deathClusters(deathCells(cells), cells, cluster);
	const flagged = opinionGroups(cells, "flagged");
	const review = opinionGroups(cells, "review");
	const unevaluated = notEvaluated(cells).map((c) => c.name);
	const exit = worstExit(cells.map(cellExit));
	const infra = rows.filter((r) => r.infrastructure.length);
	const verdict = matrixVerdict({ exit, infra: infra.length, groups, patterns, flagged, review, cells: cells.length,
		evaluated: cells.length - unevaluated.length });
	const md: string[] = [`# Agent playtest matrix: ${scenario}`, "", ...verdict.flatMap((l) => [l, ""]),
		`- **cells:** ${cells.length}`, `- **outcomes:** ${Object.entries(outcomes).map(([k, n]) => `${k} ${n}`).join(", ")}`,
		`- **exit code:** ${exit} (the worst over the cells; patterns and Jev opinions never change it)`, "",
		"TIMEOUT means the time cap ended a living round; it is not a clear.", "",
		"## Outcomes", "", "| cell | personality | seed | exit | outcome | level | job | kills | Jev decisions | problems |",
		"|---|---|---|---|---|---|---|---|---|---|",
		...rows.map((r) => {
			const o = r.outcome;
			const out = o ? `${o.state ?? "?"} ${typeof o.time === "number" ? runClock(o.time) : "?"}` : "no end";
			return `| ${r.cell} | ${r.personality} | ${r.seed} | ${r.exit_code} | ${out} | ${o ? `Lv ${o.level ?? "?"}` : "-"} | ` +
				`${o?.job ?? "-"} | ${o?.kills ?? "-"} | ${r.decisions.jev}/${r.decisions.total} | ${r.problems} |`;
		}), ""];
	if (infra.length) {
		md.push("## Infrastructure errors", "");
		for (const r of infra) md.push(...r.infrastructure.map((e) => `- ${r.cell}: ${e}`));
		md.push("");
	}
	md.push("## Problems", "", "### Deterministic failures (de-duplicated across cells by kind and location)", "");
	if (!groups.length) md.push("No deterministic problems in any cell.");
	groups.forEach((g, i) => {
		const when = g.first.time !== undefined ? ` at ${runClock(g.first.time)}` : "";
		md.push(`${i + 1}. **${g.kind}** at ${g.location || "?"}: ${g.cells.length} cells, ${g.count} times (${g.severity}); ` +
			`first in ${g.first.cell}${when}: ${g.first.message}`, `   - cells: ${g.cells.join(", ")}`);
		if (g.first.replay) md.push(`   - replay: \`${g.first.replay}\``);
		if (g.first.replay && g.first.time !== undefined) md.push(`   - windowed replay: \`${windowed(g.first.replay, g.first.time)}\``);
		if (g.first.rerun) md.push(`   - re-run: \`${g.first.rerun}\``);
	});
	md.push("", "### Patterns (deterministic aggregate insights; not invariant failures)", "");
	if (!patterns.length) {
		md.push(`No death cluster: no ${cluster.windowS} s run-time window holds the deaths of ${pct(cluster.share, 1)} of the cells or more.`);
	}
	patterns.forEach((c, i) => md.push(...clusterLines(c, i)));
	md.push("", `### Jev-flagged (grouped by kind across cells)`, "");
	md.push(...opinionLines(flagged, "No cell's evaluations flagged anything."));
	md.push("", "### Needs human review (grouped by kind across cells)", "");
	md.push(...opinionLines(review, "Nothing needs review."));
	if (unevaluated.length) {
		md.push("", unevaluated.length === cells.length ? `Jev evaluations: not evaluated in any of the ${cells.length} cells (skipped, or recorded before #99).`
			: `Jev evaluations: not evaluated in ${cellsWord(unevaluated.length)} (skipped, or recorded before #99): ${unevaluated.join(", ")}.`);
	}
	md.push("", "## Metric spreads", "", "| metric | n | min | median | max |", "|---|---|---|---|---|",
		...Object.entries(metrics).map(([k, s]) => ("min" in s ? `| ${k} | ${s.n} | ${s.min} | ${s.median} | ${s.max} |` : `| ${k} | 0 | - | - | - |`)),
		"", "## Decisions by source", "", "| source | decisions |", "|---|---|",
		...Object.entries(bySource).map(([k, n]) => `| ${k} | ${n} |`), "", `exit code: ${exit}`, "");
	return { json: { scenario, exit_code: exit, outcomes, cells: rows, problems: groups, patterns, jev_flagged: flagged,
		needs_review: review, not_evaluated: unevaluated, verdict, metrics, decisions_by_source: bySource }, markdown: md.join("\n") };
}

function clusterLines(c: DeathCluster, i: number): string[] {
	const n = c.cells.length;
	const hits = Object.entries(c.last_hit).map(([k, v]) => `${k} ${v}`).join(", ");
	const pers = Object.entries(c.personalities).map(([k, p]) => `${k} ${p.in}/${p.of} (${p.from === p.to ? runClock(p.from) : `${runClock(p.from)} to ${runClock(p.to)}`})`).join(", ");
	const rep = c.representative;
	return [`${i + 1}. **death cluster** ${runClock(c.from)} to ${runClock(c.to)}: ${n}/${c.cells_total} cells (${pct(n, c.cells_total)}) died inside a ` +
		`${c.window_s} s window (${n} of ${c.deaths_total} deaths; threshold ${pct(c.share, 1)} of the cells)`,
		`   - boss alive at death: ${c.boss_alive.yes} yes, ${c.boss_alive.no} no; last hit: ${hits}`,
		`   - by personality (deaths in the cluster / cells): ${pers}`,
		`   - cells: ${c.cells.map((d) => `${d.cell} (${runClock(d.time)})`).join(", ")}`,
		...(rep.replay ? [`   - replay (representative: median death time): \`${rep.replay}\` (${rep.cell}, died ${runClock(rep.time)})`,
			`   - windowed replay: \`${windowed(rep.replay, rep.time)}\``] : [])];
}

function opinionLines(groups: OpinionGroup[], none: string): string[] {
	if (!groups.length) return [none];
	return groups.flatMap((g, i) => [
		`${i + 1}. **${g.title}**: ${cellsWord(g.cells.length)}; first in ${g.first.cell}${g.first.time !== undefined ? ` at ${runClock(g.first.time)}` : ""}: ${g.first.message}`,
		`   - Jev: ${g.first.evidence}`, `   - cells: ${g.cells.join(", ")}`,
		...(g.first.replay ? [`   - replay: \`${g.first.replay}\``] : []),
		...(g.first.replay && g.first.time !== undefined ? [`   - windowed replay: \`${windowed(g.first.replay, g.first.time)}\``] : [])]);
}

/** The matrix verdict and next command. */
function matrixVerdict(v: { exit: number; infra: number; groups: ProblemGroup[]; patterns: DeathCluster[]; flagged: OpinionGroup[];
	review: OpinionGroup[]; cells: number; evaluated: number }): string[] {
	const parts: string[] = [];
	if (v.infra) parts.push(`INFRASTRUCTURE ERRORS in ${cellsWord(v.infra)}`);
	const detCells = new Set(v.groups.flatMap((g) => g.cells)).size;
	parts.push(v.groups.length ? `PROBLEMS: ${v.groups.length} deterministic problem group${v.groups.length === 1 ? "" : "s"} in ${detCells}/${v.cells} cells`
		: "no deterministic problems");
	if (v.patterns.length) {
		const p = v.patterns[0];
		parts.push(`${v.patterns.length} pattern${v.patterns.length === 1 ? "" : "s"} (death cluster ${runClock(p.from)} to ${runClock(p.to)}, ${p.cells.length}/${p.cells_total} cells)`);
	}
	const flaggedCells = new Set(v.flagged.flatMap((g) => g.cells)).size;
	parts.push(v.evaluated === 0 ? "Jev: no cell was evaluated"
		: `Jev: ${v.flagged.length} flagged kind${v.flagged.length === 1 ? "" : "s"}${v.flagged.length ? ` in ${cellsWord(flaggedCells)}` : ""}, ` +
		`${v.review.length} need${v.review.length === 1 ? "s" : ""} review${v.evaluated < v.cells ? ` (${v.evaluated}/${v.cells} cells evaluated)` : ""}`);
	const g = v.groups.find((x) => x.first.replay && x.first.time !== undefined);
	const p = v.patterns[0];
	const f = v.flagged.find((x) => x.first.replay && x.first.time !== undefined);
	const next = v.infra ? "fix the infrastructure errors listed below, then re-run the scenario"
		: g ? `\`${windowed(g.first.replay, g.first.time!)}\` (the first deterministic problem group)`
		: p?.representative.replay ? `\`${windowed(p.representative.replay, p.representative.time)}\` (the death cluster's representative cell at its death)`
		: f ? `\`${windowed(f.first.replay, f.first.time!)}\` (the most common Jev-flagged kind)`
		: "nothing to fix";
	return [`**Verdict:** ${parts.join("; ")}; exit code ${v.exit}.`, `**Next:** ${next}`];
}
