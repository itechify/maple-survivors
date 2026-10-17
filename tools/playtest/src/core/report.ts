// The report writer (game-agnostic core): report.md and report.json from a registry of sections. Core registers the
// header, problems, decisions and files sections; a game adapter or a later ticket adds its own section with
// `registerSection` in its own module (maple/report_sections.ts), ordered by `order`:
//   0 header, 10 outcome, 20 problems, 40 metrics, 60 decisions, 90 files.
import type { DecisionRecord } from "./session.ts";

/** A deterministic problem (invariant failure, process check). Filled in by #96; empty until then. */
export type Problem = { kind: string; message: string; time?: number; tick?: number; [key: string]: unknown };

export type ReportContext = {
	title: string;
	/** Ordered header facts (label, value): scenario, stage, seed, brain and why, ... */
	header: Array<[string, string]>;
	infraErrors: string[];
	problems: Problem[];
	decisions: DecisionRecord[];
	/** Files in the run directory (report.md / report.json are added by the files section). */
	files: string[];
	exitCode: number;
	/** Adapter data for adapter sections (Maple: hello, end record, fingerprint). */
	data: Record<string, unknown>;
};

export type ReportSection = {
	id: string;
	order: number;
	/** Markdown lines for report.md ([] to leave the section out). */
	markdown(ctx: ReportContext): string[];
	/** This section's part of report.json (merged under its id), if any. */
	json?(ctx: ReportContext): unknown;
};

const sections = new Map<string, ReportSection>();

/** Adds (or replaces, by id) a report section. */
export function registerSection(section: ReportSection): void {
	sections.set(section.id, section);
}

/** report.md text and the report.json object for `ctx`. */
export function renderReport(ctx: ReportContext): { markdown: string; json: Record<string, unknown> } {
	const ordered = [...sections.values()].sort((a, b) => a.order - b.order || a.id.localeCompare(b.id));
	const md: string[] = [];
	const json: Record<string, unknown> = { title: ctx.title, exit_code: ctx.exitCode };
	for (const s of ordered) {
		const lines = s.markdown(ctx);
		if (lines.length > 0) md.push(...lines, "");
		if (s.json) json[s.id] = s.json(ctx);
	}
	return { markdown: md.join("\n"), json };
}

/** Decision counts by kind and source plus the mean brain latency and confidence. */
export function decisionSummary(decisions: readonly DecisionRecord[]) {
	const rows = new Map<string, { kind: string; source: string; count: number; latency: number[]; confidence: number[] }>();
	for (const d of decisions) {
		const key = `${d.kind}\u0000${d.source}`;
		const row = rows.get(key) ?? { kind: d.kind, source: d.source, count: 0, latency: [], confidence: [] };
		row.count++;
		if (typeof d.latency_ms === "number") row.latency.push(d.latency_ms);
		if (typeof d.confidence === "number") row.confidence.push(d.confidence);
		rows.set(key, row);
	}
	const mean = (xs: number[]) => (xs.length ? Math.round((xs.reduce((a, b) => a + b, 0) / xs.length) * 1000) / 1000 : null);
	return [...rows.values()].map((r) => ({ kind: r.kind, source: r.source, count: r.count,
		mean_latency_ms: mean(r.latency), mean_confidence: mean(r.confidence) }));
}

/** Decision counts by source. */
export function bySource(decisions: readonly DecisionRecord[]): Record<string, number> {
	const out: Record<string, number> = {};
	for (const d of decisions) out[d.source] = (out[d.source] ?? 0) + 1;
	return out;
}

registerSection({
	id: "header",
	order: 0,
	markdown: (ctx) => [`# ${ctx.title}`, "", ...ctx.header.map(([k, v]) => `- **${k}:** ${v}`)],
	json: (ctx) => Object.fromEntries(ctx.header),
});

registerSection({
	id: "problems",
	order: 20,
	markdown: (ctx) => {
		const lines = ["## Problems", ""];
		if (ctx.infraErrors.length) lines.push("Infrastructure errors (exit code 2):", "", ...ctx.infraErrors.map((e) => `- ${e}`), "");
		if (ctx.problems.length) lines.push(...ctx.problems.map((p) => `- **${p.kind}**${p.time !== undefined ? ` at ${p.time} s` : ""}: ${p.message}`));
		else if (!ctx.infraErrors.length) lines.push("No deterministic problems detected (no invariant checks run yet).");
		return lines;
	},
	json: (ctx) => ({ infrastructure: ctx.infraErrors, deterministic: ctx.problems }),
});

registerSection({
	id: "decisions",
	order: 60,
	markdown: (ctx) => {
		const rows = decisionSummary(ctx.decisions);
		if (!rows.length) return ["## Decisions", "", "No decisions were made."];
		return ["## Decisions", "", "| source | decisions |", "|---|---|",
			...Object.entries(bySource(ctx.decisions)).map(([source, n]) => `| ${source} | ${n} |`), "",
			"| kind | source | count | mean latency (ms) | mean confidence |", "|---|---|---|---|---|",
			...rows.map((r) => `| ${r.kind} | ${r.source} | ${r.count} | ${r.mean_latency_ms ?? "-"} | ${r.mean_confidence ?? "-"} |`)];
	},
	json: (ctx) => ({ total: ctx.decisions.length, by_source: bySource(ctx.decisions),
		by_kind_source: decisionSummary(ctx.decisions) }),
});

registerSection({
	id: "files",
	order: 90,
	markdown: (ctx) => ["## Files", "", ...[...new Set([...ctx.files, "report.md", "report.json"])].sort().map((f) => `- \`${f}\``)],
	json: (ctx) => [...new Set([...ctx.files, "report.md", "report.json"])].sort(),
});
