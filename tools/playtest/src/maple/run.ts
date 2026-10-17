// One Maple Survivors agent playtest (adapter): launches the headless driver on the real game, answers decisions
// with the brain, and writes the run directory (decisions.jsonl, record.json, fingerprint.json, game.log, report.md,
// report.json). Returns the exit code (core/exit_codes.ts).
import fs from "node:fs";
import path from "node:path";
import { RunRecorder } from "../core/recorder.ts";
import { runSession, infraErrors } from "../core/session.ts";
import type { DecisionRecord, SessionResult } from "../core/session.ts";
import { renderReport } from "../core/report.ts";
import type { ReportContext } from "../core/report.ts";
import { exitCodeFor } from "../core/exit_codes.ts";
import { resolveGodot, prepareProject, importProject, driverArgs } from "./launcher.ts";
import { sensibleBrain } from "./fallback.ts";
import "./report_sections.ts";

export const REPO = path.resolve(import.meta.dirname, "..", "..", "..", "..");

export type RunOptions = {
	stage: string;
	seed: number;
	minutes: number;
	personality: string;
	/** "fallback": the CLI answers over the pipe; "builtin": the driver answers itself. */
	brain: string;
	livenessS: number;
	/** Run directory; default <repo>/evidence/agent-playtest/<stage>_s<seed>_<time>. */
	out?: string;
	repo?: string;
	env?: NodeJS.ProcessEnv;
	now?: Date;
	/** Test seam: run this command instead of resolving Godot (no import pass). */
	launch?: { command: string; args: string[] };
};

export type RunOutcome = { exitCode: number; dir: string; markdown: string };

const stamp = (d: Date) => {
	const p = (n: number) => String(n).padStart(2, "0");
	return `${d.getFullYear()}${p(d.getMonth() + 1)}${p(d.getDate())}-${p(d.getHours())}${p(d.getMinutes())}${p(d.getSeconds())}`;
};

/** The default run directory, made unique if a run already used this second. */
export function defaultRunDir(repo: string, stage: string, seed: number, now: Date): string {
	const base = path.join(repo, "evidence", "agent-playtest", `${stage}_s${seed}_${stamp(now)}`);
	let dir = base;
	for (let i = 2; fs.existsSync(dir); i++) dir = `${base}_${i}`;
	return dir;
}

export async function runPlaytest(o: RunOptions): Promise<RunOutcome> {
	const repo = o.repo ?? REPO;
	const env = o.env ?? process.env;
	const dir = o.out ? path.resolve(o.out) : defaultRunDir(repo, o.stage, o.seed, o.now ?? new Date());
	const rec = new RunRecorder(dir);
	rec.touch("decisions.jsonl");
	const driverBrain = o.brain === "builtin" ? "builtin" : "stdio";
	let launch = o.launch;
	const setupErrors: string[] = [];
	if (!launch) {
		const godot = resolveGodot(env);
		if ("error" in godot) setupErrors.push(godot.error);
		else {
			const project = prepareProject(repo, env);
			rec.log(`agent_playtest: Godot ${godot.exe}, project ${project}`);
			importProject(godot.exe, project);
			launch = { command: godot.exe, args: driverArgs(project, { stage: o.stage, seed: o.seed, minutes: o.minutes,
				personality: o.personality, brain: driverBrain }) };
		}
	}
	let session: SessionResult | undefined;
	if (launch) {
		rec.log(`agent_playtest: ${launch.command} ${launch.args.join(" ")}`);
		session = await runSession({ command: launch.command, args: launch.args, cwd: repo, env, brain: sensibleBrain,
			livenessMs: o.livenessS * 1000, onLine: (line, stream) => rec.log(stream === "stderr" ? `[stderr] ${line}` : line) });
	}
	const errors = [...setupErrors, ...(session ? infraErrors(session) : [])];
	const decisions = mergeDecisions(session);
	for (const d of decisions) rec.jsonl("decisions.jsonl", d);
	if (session?.end) {
		rec.json("record.json", session.end.record);
		if (session.end.fingerprint) rec.json("fingerprint.json", session.end.fingerprint);
	}
	const exitCode = exitCodeFor(errors, 0);
	const ctx: ReportContext = {
		title: `Agent playtest: ${o.stage} seed ${o.seed}`,
		header: [["stage", o.stage], ["seed", String(o.seed)], ["time cap", o.minutes > 0 ? `${o.minutes} min` : "stage cap"],
			["personality", o.personality], ["brain", brainLine(o.brain, session)],
			["Jev", "not used (the Jev brain arrives with #94)"], ["exit code", String(exitCode)]],
		infraErrors: errors, problems: [], decisions, files: rec.files(), exitCode,
		data: { hello: session?.hello, end: session?.end },
	};
	const report = renderReport(ctx);
	rec.text("report.md", report.markdown);
	rec.json("report.json", report.json);
	return { exitCode, dir, markdown: report.markdown };
}

/** Which brain decided and why, for the report header. */
function brainLine(brain: string, session: SessionResult | undefined): string {
	const lost = session?.end?.brain_lost ? "; the brain was lost mid-round, later decisions took the driver's baseline" : "";
	if (brain === "builtin") return `builtin (the driver answered every decision with its baseline, BotInput.pick_card_for / pick_job; no pipe)${lost}`;
	return `fallback:sensible (deterministic fallback over the decision protocol: the driver's baseline, BotInput.pick_card_for / pick_job; no Jev brain in this build)${lost}`;
}

/** The CLI's decision records completed with the driver's view (`end.decisions`): an answer the driver replaced with
 * its baseline keeps that baseline and its reason; decisions made after the brain was lost (or by the builtin brain)
 * appear only on the driver side. */
function mergeDecisions(session: SessionResult | undefined): DecisionRecord[] {
	if (!session) return [];
	const asked = new Map(session.decisions.map((d) => [d.id, d]));
	const applied = session.end?.decisions;
	if (!applied) return session.decisions;
	return applied.map((a) => {
		const mine = asked.get(a.id);
		const base: DecisionRecord = mine ?? { id: a.id, kind: a.kind, tick: a.tick ?? null, time: a.time ?? null,
			options: a.options ?? [], baseline: a.baseline ?? null, answer: a.answer, source: a.source,
			confidence: a.confidence ?? null, latency_ms: null };
		return a.fallback_reason ? { ...base, answer: a.answer, source: a.source, confidence: null, fallback_reason: a.fallback_reason } : base;
	});
}
