// The report writer (game-agnostic core): report.md and report.json from a registry of sections. Core registers the
// header, problems, decisions and files sections; a game adapter or a later ticket adds its own section with
// `registerSection` in its own module (maple/report_sections.ts), ordered by `order`:
//   0 header, 10 outcome, 20 problems, 40 metrics, 60 decisions, 90 files.
import type { DecisionRecord } from "./session.ts";

/** A deterministic problem: a game-side invariant finding (protocol `finding`, source "invariant") or a process-level
 * check such as an error line in game.log (source "game.log"). `count` is how often it repeated (de-duplicated). */
export type Problem = {
	kind: string; message: string; severity?: string; time?: number; tick?: number; count?: number; source?: string;
	snapshot?: Record<string, unknown>; location?: string; [key: string]: unknown;
};

/** A model's opinion on something subjective (a Jev-assisted evaluation, #99), kept apart from deterministic problems:
 * "flagged" (past its threshold with enough confidence) or "review" (past it with low confidence: needs a human). */
export type Opinion = {
	kind: string; class: "flagged" | "review"; title: string; message: string;
	/** The model's numbers, as one line ("unfairness 2.6 of 3 (confidence 0.8); ..."). */
	evidence: string; time?: number; tick?: number;
};

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
	/** The command that re-runs this run live (shown with every problem). */
	rerun?: string;
	/** The command that replays this run exactly from its recorded answers (shown with every problem, #98). */
	replay?: string;
	/** The windowed replay with screenshots at run time `t` (s), shown with every timed problem (#99; the command
	 * itself is #100's). */
	windowed?: (t: number) => string;
	/** Model opinions (#99), kept apart from `problems`; absent: the run has no evaluations at all. */
	opinions?: Opinion[];
	/** The evaluations' status: one line, and whether they were skipped (with why in the line). */
	evaluations?: { line: string; skipped: boolean };
	/** --strict-eval: Jev-flagged opinions count toward exit code 1. */
	strictEval?: boolean;
};

/** Renders a finding's state snapshot as Markdown sub-bullets; a game adapter may replace it (setSnapshotFormatter). */
export type SnapshotFormatter = (snapshot: Record<string, unknown>) => string[];

const plain = (v: unknown): string => (v !== null && typeof v === "object"
	? Object.entries(v as Record<string, unknown>).map(([k, x]) => `${k} ${plain(x)}`).join(", ") : String(v));

/** The game-agnostic snapshot rendering: one `key value` list, arrays of objects on their own lines. */
export const genericSnapshot: SnapshotFormatter = (s) => {
	const flat = Object.entries(s).filter(([, v]) => !Array.isArray(v)).map(([k, v]) => `${k} ${plain(v)}`);
	const lists = Object.entries(s).filter(([, v]) => Array.isArray(v))
		.map(([k, v]) => `${k}: ${(v as unknown[]).length ? (v as unknown[]).map((x) => `(${plain(x)})`).join("; ") : "none"}`);
	return [...(flat.length ? [flat.join(", ")] : []), ...lists];
};

let snapshotFormatter: SnapshotFormatter = genericSnapshot;

/** Sets how finding snapshots are shown in the Problems section. */
export function setSnapshotFormatter(f: SnapshotFormatter): void {
	snapshotFormatter = f;
}

const SEVERITY_RANK: Record<string, number> = { error: 0, warning: 1 };

/** Problems in report order: errors before warnings, then by run time (untimed last); stable otherwise. */
export function orderProblems(problems: readonly Problem[]): Problem[] {
	const rank = (p: Problem) => SEVERITY_RANK[p.severity ?? "error"] ?? 2;
	return [...problems].sort((a, b) => rank(a) - rank(b) || (a.time ?? Infinity) - (b.time ?? Infinity));
}

/** "m:ss" (or "m:ss.s" when the time has a fraction) for run seconds. */
export function runClock(t: number): string {
	const s = t % 60;
	const whole = Math.abs(s - Math.round(s)) < 0.05;
	return `${Math.floor(t / 60)}:${whole ? String(Math.round(s)).padStart(2, "0") : s.toFixed(1).padStart(4, "0")}`;
}

const whenText = (time?: number, tick?: number) =>
	[time !== undefined ? `at ${runClock(time)}` : "", tick !== undefined ? `tick ${tick}` : ""].filter(Boolean).join(", ");

/** The re-run, replay and windowed replay lines of an entry at run time `time`. */
function commandLines(ctx: Pick<ReportContext, "rerun" | "replay" | "windowed">, time?: number): string[] {
	return [...(ctx.rerun ? [`   - re-run: \`${ctx.rerun}\``] : []), ...(ctx.replay ? [`   - replay: \`${ctx.replay}\``] : []),
		...(ctx.windowed && time !== undefined ? [`   - windowed replay: \`${ctx.windowed(time)}\``] : [])];
}

/** Markdown for one problem (a numbered entry with sub-bullets). */
function problemLines(p: Problem, i: number, ctx: Pick<ReportContext, "rerun" | "replay" | "windowed">): string[] {
	const when = whenText(p.time, p.tick);
	const seen = (p.count ?? 1) > 1 ? `, seen ${p.count} times` : "";
	const lines = [`${i + 1}. **${p.kind}** (${p.severity ?? "error"})${when ? ` ${when}` : ""}${seen}: ${p.message}`];
	if (p.location) lines.push(`   - where: ${p.location}`);
	if (p.snapshot) lines.push(...snapshotFormatter(p.snapshot).map((l) => `   - ${l}`));
	if (p.source && p.source !== "invariant") lines.push(`   - from: ${p.source}`);
	lines.push(...commandLines(ctx, p.time));
	return lines;
}

const CLASS_TEXT = { flagged: "Jev-flagged", review: "needs review" } as const;

/** Markdown for one opinion (a numbered entry: what, when, the model's numbers, the commands). */
function opinionLines(o: Opinion, i: number, ctx: Pick<ReportContext, "rerun" | "replay" | "windowed">): string[] {
	const when = whenText(o.time, o.tick);
	return [`${i + 1}. **${o.title}** (${CLASS_TEXT[o.class]})${when ? ` ${when}` : ""}: ${o.message}`,
		`   - Jev: ${o.evidence}`, ...commandLines(ctx, o.time)];
}

const plural = (n: number, word: string) => `${n} ${word}${n === 1 ? "" : "s"}`;

/** The two lines under the title: what is wrong (or that nothing is) and the one command to run next. */
export function verdictLines(ctx: ReportContext): string[] {
	const ops = ctx.opinions ?? [];
	const flagged = ops.filter((o) => o.class === "flagged");
	const review = ops.filter((o) => o.class === "review");
	if (ctx.infraErrors.length) {
		const more = ctx.infraErrors.length > 1 ? ` (+${ctx.infraErrors.length - 1} more)` : "";
		return [`**Verdict:** INFRASTRUCTURE ERROR: ${ctx.infraErrors[0]}${more}; exit code ${ctx.exitCode}.`,
			`**Next:** fix the error above, then re-run${ctx.rerun ? `: \`${ctx.rerun}\`` : ""}.`];
	}
	const det = orderProblems(ctx.problems);
	const first = det[0];
	const detText = first ? `PROBLEMS: ${plural(det.length, "deterministic failure")} (${first.kind}${first.time !== undefined ? ` at ${runClock(first.time)}` : ""})`
		: `${flagged.length ? "JEV-FLAGGED: " : "clean: "}no deterministic problems`;
	const jev = !ctx.evaluations ? "" : ctx.evaluations.skipped ? "; Jev evaluations skipped"
		: `; Jev: ${flagged.length} flagged, ${review.length} need${review.length === 1 ? "s" : ""} review`;
	const strict = ctx.strictEval && flagged.length ? " (--strict-eval: Jev-flagged results count)" : "";
	const verdict = `**Verdict:** ${detText}${jev}; exit code ${ctx.exitCode}${strict}.`;
	const shots = (t: number, what: string) => ctx.windowed ? `\`${ctx.windowed(t)}\` (screenshots at ${what}; then read the entry below)`
		: ctx.replay ? `\`${ctx.replay}\`` : "";
	let next: string;
	if (first?.time !== undefined) next = shots(first.time, `the first deterministic failure, ${runClock(first.time)}`);
	else if (first) next = `read the entry below and game.log${ctx.rerun ? `, then re-run: \`${ctx.rerun}\`` : ""}`;
	else if (flagged[0]?.time !== undefined) next = shots(flagged[0].time, `the first Jev-flagged entry, ${runClock(flagged[0].time)}`);
	else if (flagged.length) next = "read the Jev-flagged entries below";
	else next = `nothing to fix${review.length ? `; ${review.length === 1 ? "1 entry below needs" : `${review.length} entries below need`} a human look` : ""}`;
	return [verdict, `**Next:** ${next}`];
}

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
	markdown: (ctx) => [`# ${ctx.title}`, "", ...verdictLines(ctx).flatMap((l) => [l, ""]), ...ctx.header.map(([k, v]) => `- **${k}:** ${v}`)],
	json: (ctx) => Object.fromEntries(ctx.header),
});

registerSection({
	id: "problems",
	order: 20,
	markdown: (ctx) => {
		const lines = ["## Problems", ""];
		if (ctx.infraErrors.length) lines.push("Infrastructure errors (exit code 2):", "", ...ctx.infraErrors.map((e) => `- ${e}`), "");
		if (ctx.problems.length) {
			lines.push(`### Deterministic failures (${ctx.problems.length})`, "");
			orderProblems(ctx.problems).forEach((p, i) => lines.push(...problemLines(p, i, ctx)));
		} else lines.push("No deterministic problems found (invariants, game.log errors).");
		if (!ctx.evaluations) return lines;
		const ops = ctx.opinions ?? [];
		const flagged = ops.filter((o) => o.class === "flagged");
		const review = ops.filter((o) => o.class === "review");
		if (flagged.length) {
			lines.push("", `### Jev-flagged (${flagged.length})`, "",
				`Jev's opinion past its threshold with confidence: a judgement, not an invariant${ctx.strictEval ? "; --strict-eval counts these toward exit code 1" : "; never changes the exit code without --strict-eval"}.`, "");
			flagged.forEach((o, i) => lines.push(...opinionLines(o, i, ctx)));
		}
		if (review.length) {
			lines.push("", `### Needs human review (${review.length})`, "",
				"Past the threshold but with low confidence: look before acting; never changes the exit code.", "");
			review.forEach((o, i) => lines.push(...opinionLines(o, i, ctx)));
		}
		if (!ops.length) {
			lines.push("", ctx.evaluations.skipped ? `Jev-assisted evaluations were ${ctx.evaluations.line}.`
				: `Jev flagged nothing and nothing needs review (every result: the Evaluations section; the facts sent: evaluations.json).`);
		}
		return lines;
	},
	json: (ctx) => ({ infrastructure: ctx.infraErrors, deterministic: orderProblems(ctx.problems),
		jev_flagged: (ctx.opinions ?? []).filter((o) => o.class === "flagged"),
		needs_review: (ctx.opinions ?? []).filter((o) => o.class === "review"),
		evaluations: ctx.evaluations?.line ?? null, verdict: verdictLines(ctx),
		rerun: ctx.rerun ?? null, replay: ctx.replay ?? null }),
});

registerSection({
	id: "reproduce",
	order: 85,
	markdown: (ctx) => (ctx.rerun || ctx.replay ? ["## Reproduce", "",
		...(ctx.rerun ? [`- live re-run: \`${ctx.rerun}\``] : []),
		...(ctx.replay ? [`- replay: \`${ctx.replay}\` (the recorded answers, no Jev; compares the fingerprint)`] : []),
		...(ctx.windowed ? [`- windowed replay: \`${ctx.windowed(0).replace(/=0$/, "=<seconds>")}\` (the same decisions in the game window, screenshots at that run time; #100)`] : [])] : []),
	json: (ctx) => ({ rerun: ctx.rerun ?? null, replay: ctx.replay ?? null }),
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
