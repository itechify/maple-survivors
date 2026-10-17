// The aggregate summary of a multi-run scenario (adapter, ticket #98): summary.md / summary.json over the cells' run
// directories: an outcomes table, problems de-duplicated across cells by kind and location (core/aggregate.ts),
// metric spreads (time, level, kills, cards taken) and decisions by source. Its exit code is the worst over the cells.
import { readCells, dedupeProblems, worstExit, cellExit, cellProblems } from "../core/aggregate.ts";
import type { CellReport, ProblemGroup } from "../core/aggregate.ts";
import { runClock } from "../core/report.ts";

type Outcome = { state?: string; time?: number | null; level?: number | null; job?: number | null; kills?: number | null;
	cards_taken?: number };
export type Spread = { n: number; min: number; median: number; max: number } | { n: 0 };

const mmss = (t: number) => `${Math.floor(t / 60)}:${String(Math.floor(t % 60)).padStart(2, "0")}`;

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

export type MatrixSummary = {
	json: {
		scenario: string; exit_code: number; outcomes: Record<string, number>;
		cells: Array<Record<string, unknown>>; problems: ProblemGroup[];
		metrics: Record<string, Spread>; decisions_by_source: Record<string, number>;
	};
	markdown: string;
};

/** The summary of scenario `scenario` over the cell directories `dirs`. */
export function matrixSummary(scenario: string, dirs: readonly string[]): MatrixSummary {
	const cells = readCells(dirs);
	const outcomes: Record<string, number> = {};
	const bySource: Record<string, number> = {};
	const rows = cells.map((c) => {
		const o = outcomeOf(c);
		const state = o?.state ?? "no end";
		outcomes[state] = (outcomes[state] ?? 0) + 1;
		const src = (c.report?.decisions as { by_source?: Record<string, number> } | undefined)?.by_source ?? {};
		for (const [k, n] of Object.entries(src)) bySource[k] = (bySource[k] ?? 0) + n;
		const problems = (c.report?.problems ?? {}) as { infrastructure?: string[]; replay?: string; rerun?: string };
		return { cell: c.name, dir: c.dir, personality: header(c).personality ?? "?", seed: header(c).seed ?? "?",
			stage: header(c).stage ?? "?", exit_code: cellExit(c), outcome: o, problems: cellProblems(c).length,
			infrastructure: c.error ? [c.error] : problems.infrastructure ?? [], replay: problems.replay ?? null,
			rerun: problems.rerun ?? null };
	});
	const outs = cells.map(outcomeOf).filter((o): o is Outcome => o !== null);
	const metrics = { time: spread(outs.map((o) => o.time)), level: spread(outs.map((o) => o.level)),
		kills: spread(outs.map((o) => o.kills)), cards_taken: spread(outs.map((o) => o.cards_taken)) };
	const groups = dedupeProblems(cells);
	const exit = worstExit(cells.map(cellExit));
	const md: string[] = [`# Agent playtest matrix: ${scenario}`, "",
		`- **cells:** ${cells.length}`, `- **outcomes:** ${Object.entries(outcomes).map(([k, n]) => `${k} ${n}`).join(", ")}`,
		`- **exit code:** ${exit} (the worst over the cells)`, "",
		"TIMEOUT means the time cap ended a living round; it is not a clear.", "",
		"## Outcomes", "", "| cell | personality | seed | exit | outcome | level | job | kills | problems |",
		"|---|---|---|---|---|---|---|---|---|",
		...rows.map((r) => {
			const o = r.outcome;
			const out = o ? `${o.state ?? "?"} ${typeof o.time === "number" ? mmss(o.time) : "?"}` : "no end";
			return `| ${r.cell} | ${r.personality} | ${r.seed} | ${r.exit_code} | ${out} | ${o ? `Lv ${o.level ?? "?"}` : "-"} | ` +
				`${o?.job ?? "-"} | ${o?.kills ?? "-"} | ${r.problems} |`;
		}), ""];
	const infra = rows.filter((r) => r.infrastructure.length);
	if (infra.length) {
		md.push("## Infrastructure errors", "");
		for (const r of infra) md.push(...r.infrastructure.map((e) => `- ${r.cell}: ${e}`));
		md.push("");
	}
	md.push("## Problems (de-duplicated across cells by kind and location)", "");
	if (!groups.length) md.push("No deterministic problems in any cell.");
	groups.forEach((g, i) => {
		const when = g.first.time !== undefined ? ` at ${runClock(g.first.time)}` : "";
		md.push(`${i + 1}. **${g.kind}** at ${g.location || "?"}: ${g.cells.length} cells, ${g.count} times (${g.severity}); ` +
			`first in ${g.first.cell}${when}: ${g.first.message}`, `   - cells: ${g.cells.join(", ")}`);
		if (g.first.replay) md.push(`   - replay: \`${g.first.replay}\``);
		if (g.first.rerun) md.push(`   - re-run: \`${g.first.rerun}\``);
	});
	md.push("", "## Metric spreads", "", "| metric | n | min | median | max |", "|---|---|---|---|---|",
		...Object.entries(metrics).map(([k, s]) => ("min" in s ? `| ${k} | ${s.n} | ${s.min} | ${s.median} | ${s.max} |` : `| ${k} | 0 | - | - | - |`)),
		"", "## Decisions by source", "", "| source | decisions |", "|---|---|",
		...Object.entries(bySource).map(([k, n]) => `| ${k} | ${n} |`), "", `exit code: ${exit}`, "");
	return { json: { scenario, exit_code: exit, outcomes, cells: rows, problems: groups, metrics, decisions_by_source: bySource },
		markdown: md.join("\n") };
}
