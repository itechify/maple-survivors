// One Maple Survivors agent playtest (adapter): launches the headless driver on the real game, answers decisions
// with the brain, and writes the run directory (decisions.jsonl, record.json, fingerprint.json, game.log, report.md,
// report.json). Returns the exit code (core/exit_codes.ts).
import fs from "node:fs";
import path from "node:path";
import { RunRecorder } from "../core/recorder.ts";
import { runSession, infraErrors } from "../core/session.ts";
import type { DecisionRecord, SessionResult } from "../core/session.ts";
import { renderReport } from "../core/report.ts";
import type { Problem, ReportContext } from "../core/report.ts";
import { exitCodeFor } from "../core/exit_codes.ts";
import { resolveGodot, prepareProject, importProjectAsync, driverArgs } from "./launcher.ts";
import { createReplayBrain, compareFingerprints, compareHello, orderDivergences } from "../core/replay.ts";
import type { Recording, ReplayBrain } from "../core/replay.ts";
import { personalityFile } from "./personalities.ts";
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
import { loadPersonality, driverParams } from "./personality.ts";
import type { Personality } from "./personality.ts";
import { createFallbackBrain } from "./personality_fallback.ts";
import "./report_personality.ts";

/** The personality's driver params, written into the run directory and passed with --personality-file (#97). */
export const PERSONALITY_FILE = "personality.json";

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
	/** Run directory; default <repo>/evidence/agent-playtest/<scenario>_<stage>_<personality>_s<seed>_<time>. */
	out?: string;
	repo?: string;
	env?: NodeJS.ProcessEnv;
	now?: Date;
	/** Test seam: run this command instead of resolving Godot (no import pass). */
	launch?: { command: string; args: string[] };
	/** Invariant thresholds and the test-only injected finding (driver defaults when absent). */
	checks?: InvariantChecks;
	/** Scenario name (#98; the run directory and the header). */
	scenario?: string;
	/** Absolute CharacterSnapshot path: the round starts from it (#98). */
	character?: string;
	/** Tier chain target: >= 2 chains from tier 1 through this tier (#98). */
	tier?: number;
	/** Run seconds answered by the sensible baseline (source "warp") before the brain decides (#98). */
	warp?: number;
	/** Jev-assisted evaluations on (scenario field; #99 reads it). */
	evaluations?: boolean;
	/** Recorded in scenario.json besides the run options: the scenario (name, file), the cell and every flag value. */
	record?: { scenario?: unknown; cell?: unknown; flags?: Record<string, unknown> };
	/** Replay this recording (#98): its answers instead of a brain (no Jev, no key), compared at the end. */
	replay?: Recording;
};

export type RunOutcome = { exitCode: number; dir: string; markdown: string };

export const stamp = (d: Date) => {
	const p = (n: number) => String(n).padStart(2, "0");
	return `${d.getFullYear()}${p(d.getMonth() + 1)}${p(d.getDate())}-${p(d.getHours())}${p(d.getMinutes())}${p(d.getSeconds())}`;
};

/** `base`, or `base_2`, `base_3`... if a run already used it. */
export function uniqueDir(base: string): string {
	let dir = base;
	for (let i = 2; fs.existsSync(dir); i++) dir = `${base}_${i}`;
	return dir;
}

/** The default run directory <scenario>_<stage>_<personality>_s<seed>_<time>, made unique if a run already used it. */
export function defaultRunDir(repo: string, o: Pick<RunOptions, "scenario" | "stage" | "personality" | "seed">, now: Date): string {
	return uniqueDir(path.join(repo, "evidence", "agent-playtest", `${cellName(o)}_${stamp(now)}`));
}

/** <scenario>_<stage>_<personality>_s<seed> (a matrix cell's directory name). */
export function cellName(o: Pick<RunOptions, "scenario" | "stage" | "personality" | "seed">): string {
	return `${o.scenario ?? "adhoc"}_${o.stage}_${o.personality}_s${o.seed}`;
}

export async function runPlaytest(o: RunOptions): Promise<RunOutcome> {
	const repo = o.repo ?? REPO;
	const env = o.env ?? process.env;
	const dir = o.out ? path.resolve(o.out) : defaultRunDir(repo, o, o.now ?? new Date());
	const rec = new RunRecorder(dir);
	rec.touch("decisions.jsonl");
	rec.touch("findings.jsonl");
	const checks = o.checks ?? {};
	const driverBrain = o.brain === "builtin" && !o.replay ? "builtin" : "stdio";
	let launch = o.launch;
	const setupErrors: string[] = [];
	const loaded = loadPersonality(o.personality);
	const personality = loaded.personality;
	const personalityFile = path.join(dir, PERSONALITY_FILE);
	// A replay passes the recording's own personality.json back to the driver (motor and tactic params as recorded),
	// not today's personality file (#98).
	const recordedParams = o.replay ? recordedPersonality(o.replay.dir) : null;
	if (recordedParams) rec.json(PERSONALITY_FILE, recordedParams);
	else if (personality) rec.json(PERSONALITY_FILE, driverParams(personality));
	const hasParams = recordedParams !== null || personality !== undefined;
	const pick = o.replay ? replayPick(o.replay) : warped(chooseBrain(o, env, personality), o.warp ?? 0);
	const driverOptions = { stage: o.stage, seed: o.seed, minutes: o.minutes, personality: o.personality,
		brain: driverBrain, out: dir, character: o.character, tier: o.tier, personalityFile, ...checks } as const;
	if (!hasParams) {
		setupErrors.push(...loaded.errors);
		launch = undefined;
	} else if (pick.error) {
		setupErrors.push(pick.error);
		launch = undefined;
	} else if (launch) {
		launch = { command: launch.command, args: [...launch.args, `--personality-file=${personalityFile}`] };
	} else {
		const godot = resolveGodot(env);
		if ("error" in godot) setupErrors.push(godot.error);
		else {
			const project = prepareProject(repo, env);
			rec.log(`agent_playtest: Godot ${godot.exe}, project ${project}`);
			await importProjectAsync(godot.exe, project);
			launch = { command: godot.exe, args: driverArgs(project, driverOptions) };
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
		const rounds = session.end.record.rounds;
		if (Array.isArray(rounds)) rounds.forEach((r, i) => rec.json(`record_tier${Number((r as { tier?: number }).tier ?? i + 1)}.json`, r));
	}
	rec.json("scenario.json", scenarioRecord(o, dir, launch?.args ?? null, session));
	const problems = sessionProblems(session, logLines);
	const divergence = o.replay && pick.replay && session ? replayProblem(o.replay, pick.replay, session, decisions) : null;
	if (divergence) problems.unshift(divergence);
	for (const p of problems) rec.jsonl("findings.jsonl", p);
	rec.adopt("timeline.jsonl");
	const exitCode = exitCodeFor(errors, problems.length);
	const brainLines = o.replay ? pick.header?.(divergence, session) ?? []
		: brainHeader({ ...pick.facts, decisions, stats: pick.client?.stats(), brainLost: session?.end?.brain_lost === true });
	const ctx: ReportContext = {
		title: `Agent playtest: ${o.stage} seed ${o.seed}`,
		header: [["scenario", o.scenario ?? "adhoc"], ["stage", o.stage], ["seed", String(o.seed)],
			["time cap", o.minutes > 0 ? `${o.minutes} min${(o.tier ?? 1) >= 2 ? " per round" : ""}` : "stage cap"],
			["personality", o.personality],
			...(o.character ? [["character", displayPath(repo, o.character)] as [string, string]] : []),
			...((o.tier ?? 1) >= 2 ? [["tier chain", `tier 1 through ${o.tier} (a round feeds the next only when CLEARED)`] as [string, string]] : []),
			...((o.warp ?? 0) > 0 && !o.replay ? [["warp", `the first ${o.warp} s took the sensible baseline (source warp: BotInput's choices, tactic kite); the brain decided after`] as [string, string]] : []),
			...brainLines,
			["exit code", String(exitCode)]],
		infraErrors: errors, problems, decisions, files: rec.files(), exitCode,
		data: { hello: session?.hello, end: session?.end, jev: pick.client?.stats(), personality }, rerun: rerunCommand(o, repo),
		replay: replayCommand(o.replay?.dir ?? dir, repo),
	};
	const report = renderReport(ctx);
	rec.text("report.md", report.markdown);
	rec.json("report.json", report.json);
	return { exitCode, dir, markdown: report.markdown };
}

/** The recorded run's personality.json (the driver params it played with), or null. */
function recordedPersonality(dir: string): Record<string, unknown> | null {
	const f = path.join(dir, PERSONALITY_FILE);
	if (!fs.existsSync(f)) return null;
	try {
		return JSON.parse(fs.readFileSync(f, "utf8")) as Record<string, unknown>;
	} catch {
		return null;
	}
}

/** `p` relative to the repo with forward slashes when it is inside it, else absolute. */
export function displayPath(repo: string, p: string): string {
	const rel = path.relative(repo, p);
	return (rel && !rel.startsWith("..") && !path.isAbsolute(rel) ? rel : path.resolve(p)).replaceAll("\\", "/");
}

/** The command that replays run directory `dir` exactly (#98). */
export function replayCommand(dir: string, repo: string = REPO): string {
	return `bash scripts/agent_playtest.sh --replay=${displayPath(repo, dir)}`;
}

/** The command that plays this run again live (same stage, seed, cap, personality, brain, character, tier, warp and
 * invariant flags). */
export function rerunCommand(o: RunOptions, repo: string = REPO): string {
	const c = o.checks ?? {};
	return ["bash scripts/agent_playtest.sh", `--stage=${o.stage}`, `--seed=${o.seed}`, `--minutes=${o.minutes}`,
		`--personality=${o.personality}`, `--brain=${o.brain}`,
		...(o.character ? [`--character=${displayPath(repo, o.character)}`] : []),
		...((o.tier ?? 1) >= 2 ? [`--tier=${o.tier}`] : []), ...((o.warp ?? 0) > 0 ? [`--warp=${o.warp}`] : []),
		...(c.stuckPx !== undefined ? [`--stuck-px=${c.stuckPx}`] : []), ...(c.stuckS !== undefined ? [`--stuck-s=${c.stuckS}`] : []),
		...(c.injectFinding ? [`--inject-finding=${c.injectFinding}`] : [])].join(" ");
}

/** scenario.json: everything a replay needs to play this run again (#98): the scenario and its file, the cell, every
 * flag value (so flags added later are restored too), the run options, the personality file's content, the exact
 * driver arguments and the driver's hello echo (compared by the replay, e.g. a motor seed the driver reports). */
function scenarioRecord(o: RunOptions, dir: string, driverArgv: string[] | null, session: SessionResult | undefined) {
	return {
		scenario: o.record?.scenario ?? { name: o.scenario ?? "adhoc" }, cell: o.record?.cell ?? null, flags: o.record?.flags ?? null,
		run: { stage: o.stage, seed: o.seed, minutes: o.minutes, personality: o.personality, brain: o.brain,
			model: o.model ?? null, jev_max_requests: o.jevMaxRequests ?? null, warp: o.warp ?? 0, character: o.character ?? null,
			tier: o.tier ?? 1, evaluations: o.evaluations ?? null, checks: o.checks ?? {} },
		personality_file: personalityFile(o.personality),
		driver_args: driverArgv, hello: session?.hello ?? null,
		...(o.replay ? { replay_of: o.replay.dir } : {}),
		dir,
	};
}

/** The replay's verdict as one `replay_divergence` problem naming the first diverging decision or field (all of them
 * in `divergences`), or null when the decisions, the hello echo and the fingerprint all match. */
function replayProblem(r: Recording, brain: ReplayBrain, session: SessionResult, decisions: DecisionRecord[]): Problem | null {
	const found = [...brain.finish(session.end?.decisions ?? decisions), ...compareHello(r.hello, session.hello)];
	if (session.end) {
		if (!r.fingerprint) found.push({ message: "the recording has no fingerprint.json (its run sent no end)" });
		else found.push(...compareFingerprints(r.fingerprint, session.end.fingerprint ?? {}));
	}
	const divs = orderDivergences(found);
	if (!divs.length) return null;
	const first = divs[0];
	const at = first.decision !== undefined ? r.decisions.find((d) => d.id === first.decision) : undefined;
	const more = divs.length > 1 ? ` (+${divs.length - 1} more: ${divs.slice(1, 4).map((d) => d.field ?? `decision ${d.decision ?? "?"}`).join(", ")}${divs.length > 4 ? ", ..." : ""})` : "";
	return { kind: "replay_divergence", severity: "error", source: "replay", message: `${first.message}${more}`,
		...(typeof at?.time === "number" ? { time: at.time } : {}), ...(typeof at?.tick === "number" ? { tick: at.tick } : {}),
		divergences: divs, replay_of: r.dir };
}

type BrainPick = { brain: Brain; client?: JevClient; facts: Omit<BrainFacts, "decisions">; error?: string;
	replay?: ReplayBrain; header?: (divergence: Problem | null, session: SessionResult | undefined) => Array<[string, string]> };

/** The replay brain for recording `r`: no key is resolved and Jev is never called. */
function replayPick(r: Recording): BrainPick {
	const brain = createReplayBrain(r.decisions);
	const recordedBrain = String((r.scenario.run as { brain?: string } | undefined)?.brain ?? "?");
	return { brain, replay: brain, facts: { requested: "replay", mode: "fallback" },
		header: (divergence, session) => [["brain requested", "replay"],
			["brain used", `replay of ${displayPath(REPO, r.dir)} (the ${r.decisions.length} recorded answers in decisions.jsonl; recorded brain ${recordedBrain}; no Jev, no key)`],
			["fallback", "none"], ["Jev", "not used (replay)"],
			["replay", !session?.end ? "incomplete (the driver sent no end)" : divergence ? `DIVERGED: ${divergence.message}`
				: `match (${r.decisions.length} decisions, the driver's hello and every fingerprint field identical)`]] };
}

/** `pick` with the first `warp` run seconds answered by the decide's sensible baseline (source "warp"). */
function warped(pick: BrainPick, warp: number): BrainPick {
	if (!(warp > 0) || pick.error) return pick;
	const inner = pick.brain;
	return { ...pick, brain: { name: inner.name, decide(d) {
		if ((d.time ?? 0) < warp) {
			return { answer: d.baseline.sensible ?? d.options[0]?.id ?? "", source: "warp", confidence: null,
				reason: `before the warp time ${warp} s: sensible baseline` };
		}
		return inner.decide(d);
	} } };
}

/** The CLI's brain for --brain: Jev when a key resolves (auto / jev), else the deterministic fallback; --brain=jev
 * without a key is a setup error (exit 2, the game is not started). The key goes only into the TypeSafe client. */
function chooseBrain(o: RunOptions, env: NodeJS.ProcessEnv, profile: Personality | undefined): BrainPick {
	const fallback = profile ? createFallbackBrain(profile, o.seed) : sensibleBrain;
	const fallbackFacts = { personality: profile?.name, cardPolicy: profile?.fallback.cards };
	if (o.brain === "builtin") return { brain: fallback, facts: { requested: o.brain, mode: "builtin" } };
	if (o.brain !== "auto" && o.brain !== "jev") return { brain: fallback, facts: { requested: o.brain, mode: "fallback", ...fallbackFacts } };
	const key = resolveApiKey({ env, readUserKey: o.readUserKey });
	if (key.key === null) {
		return o.brain === "jev"
			? { brain: fallback, facts: { requested: o.brain, mode: "none", noJevReason: key.reason },
				error: `--brain=jev needs a TypeSafe API key: ${key.reason}` }
			: { brain: fallback, facts: { requested: o.brain, mode: "fallback", noJevReason: key.reason, ...fallbackFacts } };
	}
	const client = new JevClient({ apiKey: key.key, model: o.model, maxRequests: o.jevMaxRequests, fetch: o.jevFetch,
		retry: o.jevRetry });
	return { brain: createJevBrain({ client, seed: o.seed, profile, fallback }), client,
		facts: { requested: o.brain, mode: "jev", keyFrom: key.from } };
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
