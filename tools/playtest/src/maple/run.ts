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
import { sessionProblems } from "../core/findings.ts";
import type { InvariantChecks } from "./invariant_flags.ts";
import "./report_sections.ts";
import type { Brain } from "../core/session.ts";
import type { Fetch, RetryPolicy } from "@typesafe-ai/sdk";
import { resolveApiKey, KEY_ENV } from "../core/key.ts";
import { JevClient } from "../core/jev_client.ts";
import { createJevBrain } from "./jev_brain.ts";
import { brainHeader } from "./jev_report.ts";
import type { BrainFacts } from "./jev_report.ts";

export const REPO = path.resolve(import.meta.dirname, "..", "..", "..", "..");

export type RunOptions = {
	stage: string;
	seed: number;
	minutes: number;
	personality: string;
	/** "auto" (Jev if a key resolves, else fallback), "jev" (exit 2 without a key), "fallback" (the CLI answers with
	 * the deterministic fallback over the pipe) or "builtin" (the driver answers itself). */
	brain: string;
	/** TypeSafe model for the Jev brain (default jev-latest). */
	model?: string;
	/** Jev requests per run (default 400). */
	jevMaxRequests?: number;
	/** Test seam: reads the Windows user-scope key (default powershell.exe). */
	readUserKey?: () => string | null;
	/** Test seam: the TypeSafe SDK's HTTP transport. */
	jevFetch?: Fetch;
	/** Test seam: SDK retry overrides. */
	jevRetry?: Partial<RetryPolicy>;
	livenessS: number;
	/** Run directory; default <repo>/evidence/agent-playtest/<stage>_s<seed>_<time>. */
	out?: string;
	repo?: string;
	env?: NodeJS.ProcessEnv;
	now?: Date;
	/** Test seam: run this command instead of resolving Godot (no import pass). */
	launch?: { command: string; args: string[] };
	/** Invariant thresholds and the test-only injected finding (driver defaults when absent). */
	checks?: InvariantChecks;
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
	rec.touch("findings.jsonl");
	const checks = o.checks ?? {};
	const driverBrain = o.brain === "builtin" ? "builtin" : "stdio";
	let launch = o.launch;
	const setupErrors: string[] = [];
	const pick = chooseBrain(o, env);
	if (pick.error) {
		setupErrors.push(pick.error);
		launch = undefined;
	} else if (!launch) {
		const godot = resolveGodot(env);
		if ("error" in godot) setupErrors.push(godot.error);
		else {
			const project = prepareProject(repo, env);
			rec.log(`agent_playtest: Godot ${godot.exe}, project ${project}`);
			importProject(godot.exe, project);
			launch = { command: godot.exe, args: driverArgs(project, { stage: o.stage, seed: o.seed, minutes: o.minutes,
				personality: o.personality, brain: driverBrain, out: dir, ...checks }) };
		}
	}
	let session: SessionResult | undefined;
	const logLines: string[] = [];
	if (launch) {
		rec.log(`agent_playtest: ${launch.command} ${launch.args.join(" ")}`);
		session = await runSession({ command: launch.command, args: launch.args, cwd: repo, env: withoutKey(env), brain: pick.brain,
			livenessMs: o.livenessS * 1000, onLine: (line, stream) => {
				const logged = stream === "stderr" ? `[stderr] ${line}` : line;
				logLines.push(logged);
				rec.log(logged);
			} });
	}
	const errors = [...setupErrors, ...(session ? infraErrors(session) : [])];
	const decisions = mergeDecisions(session);
	for (const d of decisions) rec.jsonl("decisions.jsonl", d);
	if (session?.end) {
		rec.json("record.json", session.end.record);
		if (session.end.fingerprint) rec.json("fingerprint.json", session.end.fingerprint);
	}
	const problems = sessionProblems(session, logLines);
	for (const p of problems) rec.jsonl("findings.jsonl", p);
	rec.adopt("timeline.jsonl");
	const exitCode = exitCodeFor(errors, problems.length);
	const ctx: ReportContext = {
		title: `Agent playtest: ${o.stage} seed ${o.seed}`,
		header: [["stage", o.stage], ["seed", String(o.seed)], ["time cap", o.minutes > 0 ? `${o.minutes} min` : "stage cap"],
			["personality", o.personality],
			...brainHeader({ ...pick.facts, decisions, stats: pick.client?.stats(), brainLost: session?.end?.brain_lost === true }),
			["exit code", String(exitCode)]],
		infraErrors: errors, problems, decisions, files: rec.files(), exitCode,
		data: { hello: session?.hello, end: session?.end, jev: pick.client?.stats() }, rerun: rerunCommand(o),
	};
	const report = renderReport(ctx);
	rec.text("report.md", report.markdown);
	rec.json("report.json", report.json);
	return { exitCode, dir, markdown: report.markdown };
}

/** The command that plays this run again live (same stage, seed, cap, personality, brain and invariant flags). */
export function rerunCommand(o: RunOptions): string {
	const c = o.checks ?? {};
	return ["bash scripts/agent_playtest.sh", `--stage=${o.stage}`, `--seed=${o.seed}`, `--minutes=${o.minutes}`,
		`--personality=${o.personality}`, `--brain=${o.brain}`,
		...(c.stuckPx !== undefined ? [`--stuck-px=${c.stuckPx}`] : []), ...(c.stuckS !== undefined ? [`--stuck-s=${c.stuckS}`] : []),
		...(c.injectFinding ? [`--inject-finding=${c.injectFinding}`] : [])].join(" ");
}

type BrainPick = { brain: Brain; client?: JevClient; facts: Omit<BrainFacts, "decisions">; error?: string };

/** The CLI's brain for --brain: Jev when a key resolves (auto / jev), else the deterministic fallback; --brain=jev
 * without a key is a setup error (exit 2, the game is not started). The key goes only into the TypeSafe client. */
function chooseBrain(o: RunOptions, env: NodeJS.ProcessEnv): BrainPick {
	if (o.brain === "builtin") return { brain: sensibleBrain, facts: { requested: o.brain, mode: "builtin" } };
	if (o.brain !== "auto" && o.brain !== "jev") return { brain: sensibleBrain, facts: { requested: o.brain, mode: "fallback" } };
	const key = resolveApiKey({ env, readUserKey: o.readUserKey });
	if (key.key === null) {
		return o.brain === "jev"
			? { brain: sensibleBrain, facts: { requested: o.brain, mode: "none", noJevReason: key.reason },
				error: `--brain=jev needs a TypeSafe API key: ${key.reason}` }
			: { brain: sensibleBrain, facts: { requested: o.brain, mode: "fallback", noJevReason: key.reason } };
	}
	const client = new JevClient({ apiKey: key.key, model: o.model, maxRequests: o.jevMaxRequests, fetch: o.jevFetch,
		retry: o.jevRetry });
	return { brain: createJevBrain({ client, seed: o.seed }), client, facts: { requested: o.brain, mode: "jev", keyFrom: key.from } };
}

/** `env` without the TypeSafe key: the game process never needs it. */
function withoutKey(env: NodeJS.ProcessEnv): NodeJS.ProcessEnv {
	const out = { ...env };
	delete out[KEY_ENV];
	return out;
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
