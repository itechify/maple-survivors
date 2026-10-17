// The CLI's top level (adapter, ticket #98): resolves the scenario (default smoke) with explicit flags laid over it,
// then plays its one cell as a single run, or several cells as a matrix, or replays a recorded run directory.
//   single  one run directory: evidence/agent-playtest/<scenario>_<stage>_<personality>_s<seed>_<time>/ (or --out)
//   matrix  evidence/agent-playtest/<scenario>_<time>/ (or --out) with one directory per cell
//           (<scenario>_<stage>_<personality>_s<seed>) and summary.md / summary.json; cells run in parallel, at most
//           `jobs` at once, each slot in its own ISOLATE mirror (<ISOLATE or scenario>_j<slot>); exit code: the worst
//   replay  --replay=<dir>: the recorded run again with its scenario.json flags and its decisions.jsonl answers,
//           written to <dir>_replay_<time>/ (or --out); a mismatch is a replay_divergence problem (exit 1)
import path from "node:path";
import fs from "node:fs";
import type { FlagValue } from "../core/args.ts";
import { EXIT } from "../core/exit_codes.ts";
import { readRecording } from "../core/replay.ts";
import { runPlaytest, REPO, cellName, stamp, uniqueDir } from "./run.ts";
import type { RunOptions } from "./run.ts";
import { loadScenario, resolveScenario, knownFacts, DEFAULT_SCENARIO } from "./scenario.ts";
import type { Cell, Known } from "./scenario.ts";
import { matrixSummary } from "./matrix_summary.ts";
import { clusterOptions } from "./eval_flags.ts";
import { runWindowedReplay } from "./windowed_replay.ts";
import { parseShotsAt } from "./windowed_flags.ts";

/** The windowed replay's flags (maple/windowed_flags.ts): they steer the CLI, never a run. */
const WINDOWED_FLAGS = ["windowed", "shots-at", "speed", "skip-to"];

/** Report lines echoed to the console (the head: title, header, outcome, problems). */
const HEAD_LINES = 30;
/** Flags that steer the CLI itself rather than a run; never recorded as a run's flags. */
const CLI_ONLY = ["help", "out", "replay", "jobs", "summarize", "cluster-window-s", "cluster-share", ...WINDOWED_FLAGS];

export type CliInput = {
	values: Record<string, FlagValue>;
	explicit: Set<string>;
	/** Flag values -> run options (cli.ts runOptionsFrom). */
	optionsFrom: (values: Record<string, FlagValue>) => RunOptions;
	repo?: string;
	cwd?: string;
	env?: NodeJS.ProcessEnv;
	now?: Date;
	/** Stages, tiers, personalities and cores (default: read from the repo). */
	known?: Known;
	scenarioDir?: string;
	/** Test seam: merged into every run's options (e.g. a fake driver launch). */
	overrides?: Partial<RunOptions>;
	/** Test seam: the windowed replay runs this command (plus the scene arguments) instead of Godot (#100). */
	windowedLaunch?: { command: string; args: string[] };
};

export type CliResult = { exitCode: number; dir: string; text: string };

const fail = (message: string): CliResult => ({ exitCode: EXIT.INFRA, dir: "", text: `agent_playtest: ${message}` });

/** A cell's flag values: the parsed values with the cell's fields laid over them (what scenario.json records). */
export function cellValues(cell: Cell, values: Record<string, FlagValue>): Record<string, FlagValue> {
	const v: Record<string, FlagValue> = { ...values };
	for (const k of CLI_ONLY) delete v[k];
	return { ...v, scenario: cell.scenario, stage: cell.stage, seed: cell.seed, personality: cell.personality,
		minutes: cell.minutes, brain: cell.brain, warp: cell.warp, character: cell.character, tier: cell.tier,
		evaluations: cell.evaluations, "stuck-px": cell.stuckPx, "stuck-s": cell.stuckS };
}

/** The run options of `cell` with flag values `flags` (a live cell, or a replay's recorded cell and flags). */
export function cellRunOptions(cell: Cell, flags: Record<string, FlagValue>, optionsFrom: CliInput["optionsFrom"],
	scenario: unknown): RunOptions {
	return { ...optionsFrom(flags), strictEval: flags["strict-eval"] === true, scenario: cell.scenario, warp: cell.warp,
		character: cell.character, tier: cell.tier,
		evaluations: cell.evaluations, record: { scenario, cell, flags } };
}

export async function runCli(i: CliInput): Promise<CliResult> {
	const repo = i.repo ?? REPO;
	const env = i.env ?? process.env;
	const now = i.now ?? new Date();
	if (i.values.windowed === true && i.values.replay === undefined) return fail("--windowed needs --replay=<run dir>");
	if (i.values.replay !== undefined && i.values.windowed === true) return runWindowed(i, repo, env, now);
	if (i.values.replay !== undefined) return runReplay(i, repo, env, now);
	if (i.values.summarize !== undefined) return summarizeMatrix(path.resolve(i.cwd ?? process.cwd(), String(i.values.summarize)), i.values);
	const name = i.explicit.has("scenario") ? String(i.values.scenario) : DEFAULT_SCENARIO;
	const loaded = loadScenario(name, i.scenarioDir);
	if ("error" in loaded) return fail(loaded.error);
	let known: Known;
	try {
		known = i.known ?? knownFacts(repo);
	} catch (e) {
		return fail(`cannot read the stages (${(e as Error).message})`);
	}
	const r = resolveScenario(name, loaded.scenario, { values: i.values, explicit: i.explicit }, known, repo, i.cwd);
	if (r.errors.length) return fail(`scenario ${name}: ${r.errors.join("; ")}`);
	if (r.cells.length === 0) return fail(`scenario ${name} has no cells`);
	const scenarioRecord = { name, file: loaded.scenario };
	const optionsOf = (cell: Cell) => cellRunOptions(cell, cellValues(cell, i.values), i.optionsFrom, scenarioRecord);
	const out = i.explicit.has("out") && i.values.out !== undefined ? path.resolve(i.cwd ?? process.cwd(), String(i.values.out)) : undefined;
	if (r.cells.length === 1) {
		const run = await runPlaytest({ ...optionsOf(r.cells[0]), repo, env, now, out, ...i.overrides });
		return { exitCode: run.exitCode, dir: run.dir,
			text: `${run.markdown.split("\n").slice(0, HEAD_LINES).join("\n")}\n\nrun directory: ${run.dir}\nexit code: ${run.exitCode}` };
	}
	const root = out ?? uniqueDir(path.join(repo, "evidence", "agent-playtest", `${name}_${stamp(now)}`));
	fs.mkdirSync(root, { recursive: true });
	const dirs = r.cells.map((c) => path.join(root, cellName(c)));
	const slotBase = env.ISOLATE || name;
	let next = 0;
	const worker = async (slot: number) => {
		while (next < r.cells.length) {
			const k = next++;
			await runPlaytest({ ...optionsOf(r.cells[k]), repo, env: { ...env, ISOLATE: `${slotBase}_j${slot}` }, now, out: dirs[k],
				...i.overrides });
		}
	};
	await Promise.all(Array.from({ length: Math.min(r.jobs, r.cells.length) }, (_, slot) => worker(slot)));
	return writeSummary(name, root, dirs, i.values);
}

/** Writes summary.md / summary.json of matrix `root` over cell directories `dirs` (death clusters per the flags). */
function writeSummary(name: string, root: string, dirs: string[], values: Record<string, FlagValue>): CliResult {
	const summary = matrixSummary(name, dirs, clusterOptions(values));
	fs.writeFileSync(path.join(root, "summary.md"), summary.markdown);
	fs.writeFileSync(path.join(root, "summary.json"), JSON.stringify(summary.json, null, "\t") + "\n");
	return { exitCode: summary.json.exit_code, dir: root,
		text: `${summary.markdown.split("\n").slice(0, HEAD_LINES).join("\n")}\n\nsummary: ${path.join(root, "summary.md")}\n` +
			`exit code: ${summary.json.exit_code}` };
}

/** --summarize=<matrix dir> (#99): the summary again from the cell directories already there (every subdirectory with
 * a report.json), with today's summary code; nothing is played. The scenario name comes from the old summary.json. */
function summarizeMatrix(root: string, values: Record<string, FlagValue>): CliResult {
	if (!fs.existsSync(root)) return fail(`--summarize: ${root} does not exist`);
	const dirs = fs.readdirSync(root, { withFileTypes: true }).filter((e) => e.isDirectory()
		&& fs.existsSync(path.join(root, e.name, "report.json"))).map((e) => path.join(root, e.name)).sort();
	if (!dirs.length) return fail(`--summarize: no cell directory with a report.json under ${root}`);
	let name = path.basename(root);
	try {
		name = String(JSON.parse(fs.readFileSync(path.join(root, "summary.json"), "utf8")).scenario ?? name);
	} catch { /* no old summary: the directory name */ }
	return writeSummary(name, root, dirs, values);
}

/** --replay=<dir>: the recorded run again from its scenario.json (cell and every flag value) and decisions.jsonl. */
async function runReplay(i: CliInput, repo: string, env: NodeJS.ProcessEnv, now: Date): Promise<CliResult> {
	const dir = path.resolve(i.cwd ?? process.cwd(), String(i.values.replay));
	const recording = readRecording(dir);
	if ("error" in recording) return fail(recording.error);
	const s = recording.scenario as { cell?: Cell; flags?: Record<string, FlagValue>; scenario?: unknown };
	if (!s.cell || !s.flags) return fail(`${dir}/scenario.json has no cell or flags to replay`);
	const out = i.explicit.has("out") && i.values.out !== undefined ? path.resolve(i.cwd ?? process.cwd(), String(i.values.out))
		: uniqueDir(`${dir}_replay_${stamp(now)}`);
	const run = await runPlaytest({ ...cellRunOptions(s.cell, s.flags, i.optionsFrom, s.scenario), replay: recording, repo, env,
		now, out, ...i.overrides });
	return { exitCode: run.exitCode, dir: run.dir,
		text: `${run.markdown.split("\n").slice(0, HEAD_LINES).join("\n")}\n\nrun directory: ${run.dir}\nexit code: ${run.exitCode}` };
}

/** --replay=<dir> --windowed (#100): the recorded run again in the game window with screenshots, written to
 * <dir>_windowed_<time>/ (or --out); a mismatch is a replay_divergence problem (exit 1). */
async function runWindowed(i: CliInput, repo: string, env: NodeJS.ProcessEnv, now: Date): Promise<CliResult> {
	const dir = path.resolve(i.cwd ?? process.cwd(), String(i.values.replay));
	const recording = readRecording(dir);
	if ("error" in recording) return fail(recording.error);
	const shotsAt = parseShotsAt(i.values["shots-at"] === undefined ? undefined : String(i.values["shots-at"]));
	if (!Array.isArray(shotsAt)) return fail(shotsAt.error);
	const out = i.explicit.has("out") && i.values.out !== undefined ? path.resolve(i.cwd ?? process.cwd(), String(i.values.out))
		: uniqueDir(`${dir}_windowed_${stamp(now)}`);
	const run = await runWindowedReplay({ recording, out, speed: Number(i.values.speed ?? 4), shotsAt,
		skipTo: i.values["skip-to"] === undefined ? undefined : Number(i.values["skip-to"]),
		livenessS: Number(i.values["liveness-s"] ?? 60), repo, env, launch: i.windowedLaunch });
	return { exitCode: run.exitCode, dir: run.dir,
		text: `${run.markdown.split("\n").slice(0, HEAD_LINES).join("\n")}\n\nrun directory: ${run.dir}\nexit code: ${run.exitCode}` };
}
