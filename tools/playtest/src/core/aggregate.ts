// Aggregating several run directories (game-agnostic core, ticket #98): read each cell's report.json, pick the worst
// exit code, and de-duplicate deterministic problems across cells by kind and location, so a systemic problem shows
// once with the cells it hit instead of once per run.
import fs from "node:fs";
import path from "node:path";
import { EXIT } from "./exit_codes.ts";
import type { Problem } from "./report.ts";

/** One cell's run directory and its report.json (null with `error` when it could not be read). */
export type CellReport = { name: string; dir: string; report: Record<string, unknown> | null; error?: string };

/** The worst exit code over cells: 2 (infrastructure) over 1 (problems) over 0. No cells at all is 2. */
export function worstExit(codes: readonly number[]): number {
	if (codes.length === 0) return EXIT.INFRA;
	return Math.max(...codes.map((c) => (c === EXIT.OK || c === EXIT.PROBLEMS ? c : EXIT.INFRA)));
}

/** Reads report.json of every cell directory. */
export function readCells(dirs: readonly string[]): CellReport[] {
	return dirs.map((dir) => {
		const name = path.basename(dir);
		try {
			return { name, dir, report: JSON.parse(fs.readFileSync(path.join(dir, "report.json"), "utf8")) };
		} catch (e) {
			return { name, dir, report: null, error: `no readable report.json (${(e as Error).message})` };
		}
	});
}

/** The cell's exit code (2 when its report is missing). */
export function cellExit(c: CellReport): number {
	return typeof c.report?.exit_code === "number" ? (c.report.exit_code as number) : EXIT.INFRA;
}

/** The cell's deterministic problems from report.json. */
export function cellProblems(c: CellReport): Problem[] {
	const p = (c.report?.problems as { deterministic?: Problem[] } | undefined)?.deterministic;
	return Array.isArray(p) ? p : [];
}

/** Where a problem happened, for de-duplication: its `location` (e.g. a script line), else the stage and the
 * snapshot's platform, else the stage. */
export type Locator = (p: Problem, cell: CellReport) => string;

export const defaultLocator: Locator = (p, cell) => {
	if (p.location) return p.location;
	const stage = String((cell.report?.header as Record<string, unknown> | undefined)?.stage ?? "");
	const platform = p.snapshot?.platform;
	if (platform !== undefined && platform !== null) return `${stage ? `${stage} ` : ""}platform ${String(platform)}`;
	return stage;
};

export type ProblemGroup = {
	kind: string; location: string; severity: string;
	/** Names of the cells it occurred in, in cell order. */
	cells: string[];
	/** Occurrences summed over cells (each problem's de-duplicated count). */
	count: number;
	/** The earliest occurrence: its cell, message, time and tick, and that cell's replay / re-run commands. */
	first: { cell: string; message: string; time?: number; tick?: number; replay?: string; rerun?: string };
};

const SEVERITY: Record<string, number> = { error: 0, warning: 1 };

/** Problems grouped by kind and location over `cells`: errors first, then the groups hitting most cells, then by
 * the earliest time. */
export function dedupeProblems(cells: readonly CellReport[], locate: Locator = defaultLocator): ProblemGroup[] {
	const groups = new Map<string, ProblemGroup>();
	for (const cell of cells) {
		const commands = (cell.report?.problems ?? {}) as { replay?: string; rerun?: string };
		for (const p of cellProblems(cell)) {
			const location = locate(p, cell);
			const key = `${p.kind}\u0000${location}`;
			const example = { cell: cell.name, message: p.message, time: p.time, tick: p.tick,
				replay: commands.replay ?? undefined, rerun: commands.rerun ?? undefined };
			const g = groups.get(key);
			if (!g) {
				groups.set(key, { kind: p.kind, location, severity: p.severity ?? "error", cells: [cell.name],
					count: p.count ?? 1, first: example });
				continue;
			}
			if (!g.cells.includes(cell.name)) g.cells.push(cell.name);
			g.count += p.count ?? 1;
			if ((p.severity ?? "error") === "error") g.severity = "error";
			if ((p.time ?? Infinity) < (g.first.time ?? Infinity)) g.first = example;
		}
	}
	return [...groups.values()].sort((a, b) => (SEVERITY[a.severity] ?? 2) - (SEVERITY[b.severity] ?? 2)
		|| b.cells.length - a.cells.length || (a.first.time ?? Infinity) - (b.first.time ?? Infinity));
}
