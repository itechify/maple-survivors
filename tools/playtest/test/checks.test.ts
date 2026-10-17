// Process-level checks (core/log_scan.ts), the exit-code matrix (core/exit_codes.ts) and the Problems section of the
// report (core/report.ts) from fixture findings. No Godot, no network.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { scanLog } from "../src/core/log_scan.ts";
import { EXIT, exitCodeFor } from "../src/core/exit_codes.ts";
import { renderReport } from "../src/core/report.ts";
import type { Problem, ReportContext } from "../src/core/report.ts";
import { FINDING_KINDS } from "../src/maple/invariant_flags.ts";

const LOG = path.join(import.meta.dirname, "..", "fixtures", "game_log_errors.txt");

test("SCRIPT ERROR and ERROR: lines in game.log are problems; engine leak noise at exit is not", () => {
	const problems = scanLog(fs.readFileSync(LOG, "utf8").split(/\r?\n/));
	assert.deepEqual(problems.map((p) => [p.kind, p.count]), [["script_error", 2], ["script_error", 1], ["script_error", 1]]);
	assert.match(problems[0].message, /^SCRIPT ERROR: Invalid access to property or key 'fh'/);
	assert.equal(problems[0].location, "_step (res://scripts/sim/run_world.gd:612)", "the at: line names the script line");
	assert.equal(problems[0].severity, "error");
	assert.equal(problems[0].source, "game.log");
	assert.match(problems[1].message, /^ERROR: Condition "p_index >= size"/);
	assert.match(problems[2].message, /^USER ERROR: a push_error/);
	assert.ok(!problems.some((p) => /leaked|still in use/.test(p.message)), "leak noise is ignored, as scripts/test.sh does");
});

test("the CLI's finding kinds match the driver's invariant KINDS", () => {
	const gd = fs.readFileSync(path.join(import.meta.dirname, "..", "..", "..", "game", "tools", "playtest", "playtest_invariants.gd"), "utf8");
	const literal = /const KINDS := \[([^\]]*)\]/.exec(gd);
	assert.ok(literal, "KINDS literal in playtest_invariants.gd");
	assert.deepEqual([...literal[1].matchAll(/"([a-z_]+)"/g)].map((m) => m[1]), [...FINDING_KINDS]);
});

test("a clean log has no problems", () => {
	assert.deepEqual(scanLog(["playtest_driver: 1:00 Lv 3 kills 20 alive 14", '@@PT {"v":1,"type":"end"}', ""]), []);
});

test("exit codes: 0 clean, 1 deterministic problems, 2 infrastructure errors (which win)", () => {
	const matrix: Array<[string[], number, number]> = [
		[[], 0, EXIT.OK],
		[[], 1, EXIT.PROBLEMS],
		[[], 7, EXIT.PROBLEMS],
		[["no end message"], 0, EXIT.INFRA],
		[["liveness timeout"], 3, EXIT.INFRA],
	];
	for (const [infra, problems, code] of matrix) assert.equal(exitCodeFor(infra, problems), code, `${infra} ${problems}`);
});

const finding: Problem = {
	kind: "stuck", severity: "warning", tick: 15120, time: 252.0, count: 3, source: "invariant",
	message: "the player stayed inside 24 px for 20 s while pressing movement (97% of ticks), tactic kite",
	snapshot: { x: 1234.5, y: -80, fh: 41, platform: 6, hp: 120, max_hp: 300, mp: 40, max_mp: 120, level: 12, job: 200,
		tactic: "kite", state: "PLAYING", mobs: [{ mob: 100100, d: 42.1, x: 1270, y: -80, boss: false }] },
};

function ctx(problems: Problem[], infra: string[] = []): ReportContext {
	return { title: "t", header: [], infraErrors: infra, problems, decisions: [], files: [],
		exitCode: exitCodeFor(infra, problems.length), data: {},
		rerun: "bash scripts/agent_playtest.sh --stage=henesys_hg1 --seed=2026 --minutes=5" };
}

test("the Problems section lists each deterministic failure with time, tick, snapshot and the re-run command", () => {
	const script: Problem = { kind: "script_error", severity: "error", count: 1, source: "game.log",
		message: "SCRIPT ERROR: boom", location: "_step (res://x.gd:1)" };
	const { markdown, json } = renderReport(ctx([finding, script]));
	const section = markdown.slice(markdown.indexOf("## Problems"));
	assert.match(section, /Deterministic failures \(2\)/);
	assert.match(section, /\*\*stuck\*\* \(warning\) at 4:12, tick 15120, seen 3 times/);
	assert.match(section, /stayed inside 24 px/);
	assert.match(section, /platform 6/, "the snapshot is shown");
	assert.match(section, /100100/, "nearest mobs are shown");
	assert.match(section, /bash scripts\/agent_playtest\.sh --stage=henesys_hg1 --seed=2026 --minutes=5/, "re-run command");
	assert.match(section, /\*\*script_error\*\* \(error\)/);
	assert.match(section, /_step \(res:\/\/x\.gd:1\)/);
	const problems = json.problems as { deterministic: Problem[]; rerun: string };
	assert.equal(problems.deterministic.length, 2);
	assert.equal(problems.rerun, ctx([]).rerun);
});

test("errors sort before warnings in the Problems section", () => {
	const hp: Problem = { kind: "hp_out_of_range", severity: "error", tick: 60, time: 1, count: 1, message: "HP 9 outside 0..5" };
	const md = renderReport(ctx([finding, hp])).markdown;
	assert.ok(md.indexOf("hp_out_of_range") < md.indexOf("**stuck**"), md);
});

test("a clean run says no deterministic problems were found", () => {
	const md = renderReport(ctx([])).markdown;
	assert.match(md, /No deterministic problems found/);
	assert.doesNotMatch(md, /no invariant checks run yet/);
});

test("infrastructure errors come first", () => {
	const md = renderReport(ctx([finding], ["no output from the driver for 60 s (liveness timeout); killed"])).markdown;
	assert.ok(md.indexOf("liveness timeout") < md.indexOf("**stuck**"));
	assert.match(md, /exit code 2/);
});
