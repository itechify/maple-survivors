// The windowed replay (adapter, ticket #100): `--replay=<dir> --windowed` plays a recorded run again in the real game
// window. It launches game/scenes/debug/agent_replay.tscn with the windowed Godot exe (no --headless; an ISOLATE
// mirror like every playtest run). The scene answers decisions in-process from the recording's decisions.jsonl (no
// pipe), saves screenshots and writes fingerprint.json, decisions.jsonl, timeline.jsonl and replay.json into the
// output directory. The CLI then re-checks the scene's applied decisions and fingerprint with #98's replay code
// (core/replay.ts), scans the log for script errors, writes report.md / report.json with a Screenshots section
// (maple/report_screenshots.ts), and appends a pointer to the recording's report.md.
// Exit code: 0 match, 1 replay divergence or script errors, 2 infrastructure error (no replay.json, liveness).
import fs from "node:fs";
import path from "node:path";
import { spawn } from "node:child_process";
import { RunRecorder } from "../core/recorder.ts";
import { renderReport } from "../core/report.ts";
import type { Problem, ReportContext } from "../core/report.ts";
import { exitCodeFor } from "../core/exit_codes.ts";
import { scanLog } from "../core/log_scan.ts";
import { createReplayBrain, compareFingerprints, orderDivergences } from "../core/replay.ts";
import type { Recording, Divergence } from "../core/replay.ts";
import type { DecisionRecord } from "../core/session.ts";
import { resolveGodot, prepareProject, importProjectAsync } from "./launcher.ts";
import { displayPath, REPO, replayCommand } from "./run.ts";
import type { RunOutcome } from "./run.ts";
import { runClock } from "../core/report.ts";
import "./report_sections.ts";
import "./report_screenshots.ts";

/** The windowed replay scene. */
export const WINDOWED_SCENE = "res://scenes/debug/agent_replay.tscn";

export type WindowedOptions = {
	recording: Recording;
	/** Output directory (default <recording>_windowed_<time>). */
	out: string;
	/** Sim ticks per 60 Hz frame. */
	speed: number;
	/** Run seconds to screenshot (besides every timed finding of the recording). */
	shotsAt: number[];
	/** Fast-forward to this run time before drawing. */
	skipTo?: number;
	livenessS: number;
	repo?: string;
	env?: NodeJS.ProcessEnv;
	/** Test seam: run this command (plus the scene arguments) instead of Godot. */
	launch?: { command: string; args: string[] };
};

/** The scene's arguments after `--`. */
export function windowedSceneArgs(o: { replay: string; out: string; speed: number; shotsAt: number[]; skipTo?: number }): string[] {
	const slash = (p: string) => p.replaceAll("\\", "/");
	return [`--replay=${slash(o.replay)}`, `--out=${slash(o.out)}`, `--speed=${o.speed}`,
		...(o.shotsAt.length ? [`--shots-at=${o.shotsAt.join(",")}`] : []), ...((o.skipTo ?? 0) > 0 ? [`--skip-to=${o.skipTo}`] : [])];
}

/** What the scene wrote into replay.json (game/scenes/debug/agent_replay.gd `_finish`). */
export type WindowedVerdict = {
	match?: boolean; first?: string; divergences?: Divergence[]; error?: string; speed?: number;
	view_size?: number[]; view_mismatch_frames?: number; window_size?: number[]; fingerprint?: Record<string, unknown>;
	decisions?: number; recorded_decisions?: number; first_timeline_difference?: Record<string, unknown>;
	shots?: Array<{ name: string; reason: string; tick: number; time: number; saved: boolean; why?: string }>;
	event_shots?: string[];
};

type Exit = { code: number | null; timedOut: boolean; spawnError?: string };

/** Runs `command args` to its exit, logging every output line; killed after `livenessMs` without output. */
function runLogged(command: string, args: string[], cwd: string, env: NodeJS.ProcessEnv, livenessMs: number,
	onLine: (line: string) => void): Promise<Exit> {
	return new Promise((resolve) => {
		const child = spawn(command, args, { cwd, env, stdio: ["ignore", "pipe", "pipe"], windowsHide: false });
		let timedOut = false;
		let timer: ReturnType<typeof setTimeout> | undefined;
		const arm = () => {
			clearTimeout(timer);
			timer = setTimeout(() => {
				timedOut = true;
				child.kill();
			}, livenessMs);
		};
		arm();
		const feed = (prefix: string) => {
			let rest = "";
			return (chunk: Buffer) => {
				arm();
				const text = rest + chunk.toString("utf8");
				const lines = text.split(/\r?\n/);
				rest = lines.pop() ?? "";
				for (const l of lines) onLine(prefix + l);
			};
		};
		child.stdout.on("data", feed(""));
		child.stderr.on("data", feed("[stderr] "));
		child.on("error", (e) => {
			clearTimeout(timer);
			resolve({ code: null, timedOut, spawnError: e.message });
		});
		child.on("close", (code) => {
			clearTimeout(timer);
			resolve({ code, timedOut });
		});
	});
}

const readJson = (f: string): unknown => {
	try {
		return JSON.parse(fs.readFileSync(f, "utf8"));
	} catch {
		return null;
	}
};

const readJsonl = (f: string): Array<Record<string, unknown>> => (fs.existsSync(f)
	? fs.readFileSync(f, "utf8").split("\n").filter((l) => l.trim()).map((l) => JSON.parse(l) as Record<string, unknown>) : []);

/** The replay checks of #98 (core/replay.ts) over the scene's applied decisions and fingerprint: each applied decision
 * is put to a replay brain of the recording as the decide it answered, then its `finish`, then the fingerprints. */
export function recheck(r: Recording, applied: ReadonlyArray<Record<string, unknown>>, fingerprint: Record<string, unknown> | null): Divergence[] {
	const brain = createReplayBrain(r.decisions);
	for (const a of applied) {
		const options = (Array.isArray(a.options) ? a.options : []).map((id) => ({ id: String(id) }));
		brain.decide({ v: 1, type: "decide", id: Number(a.id), kind: String(a.kind), tick: Number(a.tick), time: Number(a.time),
			options, baseline: { sensible: String(a.baseline ?? "") } });
	}
	const divs = brain.finish(applied.map((a) => ({ id: Number(a.id), answer: String(a.answer),
		...(a.fallback_reason ? { fallback_reason: String(a.fallback_reason) } : {}) })));
	if (!r.fingerprint) divs.push({ message: "the recording has no fingerprint.json (its run sent no end)" });
	else if (fingerprint) divs.push(...compareFingerprints(r.fingerprint, fingerprint));
	return orderDivergences(divs);
}

/** "row 3 at 0:03 (tick 180): x 10 -> 12, hp 50 -> 44" for replay.json's first_timeline_difference, or "". */
export function timelineDifference(d: Record<string, unknown> | undefined): string {
	if (!d || !Object.keys(d).length) return "";
	if (d.missing) return `row ${d.row}: the ${d.missing} timeline ends there`;
	const fields = Object.entries((d.fields ?? {}) as Record<string, unknown[]>)
		.map(([k, [a, b]]) => `${k} ${JSON.stringify(a)} -> ${JSON.stringify(b)}`).join(", ");
	const when = typeof d.time === "number" ? ` at ${runClock(d.time)}${typeof d.tick === "number" ? ` (tick ${d.tick})` : ""}` : "";
	return `row ${d.row}${when}: ${fields}`;
}

export async function runWindowedReplay(o: WindowedOptions): Promise<RunOutcome> {
	const repo = o.repo ?? REPO;
	const env = o.env ?? process.env;
	const r = o.recording;
	const rec = new RunRecorder(o.out);
	rec.touch("findings.jsonl");
	const errors: string[] = [];
	const sceneArgs = windowedSceneArgs({ replay: r.dir, out: o.out, speed: o.speed, shotsAt: o.shotsAt, skipTo: o.skipTo });
	let launch = o.launch ? { command: o.launch.command, args: [...o.launch.args, ...sceneArgs] } : undefined;
	if (!launch) {
		const godot = resolveGodot(env);
		if ("error" in godot) errors.push(godot.error);
		else {
			const project = prepareProject(repo, env);
			rec.log(`agent_playtest: windowed replay, Godot ${godot.exe}, project ${project}`);
			await importProjectAsync(godot.exe, project);
			launch = { command: godot.exe, args: ["--path", project, WINDOWED_SCENE, "--", ...sceneArgs] };
		}
	}
	const logLines: string[] = [];
	let exit: Exit | undefined;
	if (launch) {
		rec.log(`agent_playtest: ${launch.command} ${launch.args.join(" ")}`);
		const childEnv = { ...env };
		delete childEnv.TYPESAFE_API_KEY; // the game never needs the key
		exit = await runLogged(launch.command, launch.args, repo, childEnv, o.livenessS * 1000, (line) => {
			logLines.push(line);
			rec.log(line);
		});
		if (exit.spawnError) errors.push(`cannot start the windowed replay: ${exit.spawnError}`);
		if (exit.timedOut) errors.push(`no output from the windowed replay for ${o.livenessS} s (liveness timeout); killed`);
	}
	const verdict = (readJson(path.join(o.out, "replay.json")) ?? null) as WindowedVerdict | null;
	if (launch && !exit?.timedOut && !exit?.spawnError) {
		if (!verdict) errors.push(`the windowed replay wrote no replay.json (exit code ${exit?.code})`);
		else if (verdict.error) errors.push(`the windowed replay failed: ${verdict.error}`);
	}
	const applied = readJsonl(path.join(o.out, "decisions.jsonl"));
	const fingerprint = (readJson(path.join(o.out, "fingerprint.json")) ?? null) as Record<string, unknown> | null;
	const problems: Problem[] = [];
	let divergence: Problem | null = null;
	if (verdict && !verdict.error) {
		const mine = recheck(r, applied, fingerprint);
		const divs = mine.length ? mine : verdict.match === false ? orderDivergences(verdict.divergences ?? []) : [];
		if (divs.length) {
			const first = divs[0];
			const at = first.decision !== undefined ? r.decisions.find((d) => d.id === first.decision) : undefined;
			const more = divs.length > 1 ? ` (+${divs.length - 1} more: ${divs.slice(1, 4).map((d) => d.field ?? `decision ${d.decision ?? "?"}`).join(", ")}${divs.length > 4 ? ", ..." : ""})` : "";
			const diff = timelineDifference(verdict.first_timeline_difference);
			divergence = { kind: "replay_divergence", severity: "error", source: "windowed replay", message: `${first.message}${more}`,
				...(typeof at?.time === "number" ? { time: at.time } : {}), ...(typeof at?.tick === "number" ? { tick: at.tick } : {}),
				...(diff ? { location: `first timeline difference: ${diff}` } : {}), divergences: divs, replay_of: r.dir,
				scene_verdict: verdict.match === true ? "match" : "diverged" };
			problems.push(divergence);
		}
	}
	problems.push(...scanLog(logLines));
	for (const p of problems) rec.jsonl("findings.jsonl", p);
	for (const f of ["replay.json", "fingerprint.json", "decisions.jsonl", "timeline.jsonl"]) rec.adopt(f);
	const exitCode = exitCodeFor(errors, problems.length);
	const run = (r.scenario.run ?? {}) as Record<string, unknown>;
	const recordedRecord = (verdict && !verdict.error ? readJson(path.join(r.dir, "record.json")) : null) as Record<string, unknown> | null;
	const saved = (verdict?.shots ?? []).filter((s) => s.saved).length;
	const replayLine = !verdict || verdict.error ? "incomplete (the windowed replay wrote no verdict)"
		: divergence ? `DIVERGED: ${divergence.message}` : `match (${applied.length} decisions, every fingerprint field identical)`;
	const views = verdict?.view_size ? `${verdict.view_size.join("x")} logical (the headless driver's), window ${verdict.window_size?.join("x") ?? "?"}, ` +
		`frames with another view: ${verdict.view_mismatch_frames ?? "?"}` : "?";
	const ctx: ReportContext = {
		title: `Windowed replay: ${String(run.stage ?? "?")} seed ${String(run.seed ?? "?")}`,
		header: [["scenario", String((r.scenario.scenario as { name?: string } | undefined)?.name ?? "adhoc")], ["stage", String(run.stage ?? "?")],
			["seed", String(run.seed ?? "?")], ["personality", String(run.personality ?? "?")],
			["brain used", `windowed replay of ${displayPath(repo, r.dir)} (RunScene in the game window with the playtest policy; ` +
				`the ${r.decisions.length} recorded answers in decisions.jsonl, answered in-process; no Jev, no key)`],
			["replay", replayLine], ["view", views], ["speed", `x${o.speed}${(o.skipTo ?? 0) > 0 ? `, skipped to ${o.skipTo} s` : ""}`],
			["exit code", String(exitCode)]],
		infraErrors: errors, problems, decisions: applied as DecisionRecord[], files: rec.files(), exitCode,
		// A matching replay played the recorded round: its record.json holds the metrics; otherwise only the fingerprint.
		data: { end: fingerprint ? { record: (!divergence && recordedRecord) || fingerprint, fingerprint, brain_lost: false } : undefined,
			windowed: verdict },
		replay: replayCommand(r.dir, repo),
	};
	const report = renderReport(ctx);
	rec.text("report.md", report.markdown);
	rec.json("report.json", report.json);
	const pointer = `- ${new Date().toISOString()}: \`${displayPath(repo, o.out)}/report.md\`: ` +
		`${!verdict || verdict.error ? "incomplete" : divergence ? "DIVERGED" : "match"}, ${saved} screenshots in \`${displayPath(repo, o.out)}/shots/\``;
	appendPointer(path.join(r.dir, "report.md"), pointer);
	return { exitCode, dir: o.out, markdown: report.markdown };
}

/** Appends `line` under a "## Windowed replays" section at the end of the recording's report.md. */
function appendPointer(file: string, line: string): void {
	if (!fs.existsSync(file)) return;
	const text = fs.readFileSync(file, "utf8");
	const head = text.includes("\n## Windowed replays\n") ? "" : `${text.endsWith("\n") ? "" : "\n"}\n## Windowed replays\n\n`;
	fs.appendFileSync(file, `${head}${line}\n`);
}
