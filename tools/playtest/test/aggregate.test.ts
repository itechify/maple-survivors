// The matrix aggregate (core/aggregate.ts, maple/matrix_summary.ts) from fixture cell directories: problems
// de-duplicated across cells by kind and location, the outcomes table, metric spreads and the worst exit code.
import { test } from "node:test";
import assert from "node:assert/strict";
import path from "node:path";
import { worstExit, dedupeProblems, readCells } from "../src/core/aggregate.ts";
import { matrixSummary } from "../src/maple/matrix_summary.ts";
import { EXIT } from "../src/core/exit_codes.ts";

const ROOT = path.join(import.meta.dirname, "..", "fixtures", "matrix");
const DIRS = ["matrix_henesys_hg1_sensible_s1", "matrix_henesys_hg1_sensible_s2", "matrix_henesys_hg1_sensible_s2026"]
	.map((d) => path.join(ROOT, d));

test("the worst exit code wins: infrastructure (2) over problems (1) over clean (0)", () => {
	assert.equal(worstExit([0, 0, 0]), EXIT.OK);
	assert.equal(worstExit([0, 1, 0]), EXIT.PROBLEMS);
	assert.equal(worstExit([1, 2, 0]), EXIT.INFRA);
	assert.equal(worstExit([2, 1]), EXIT.INFRA);
	assert.equal(worstExit([]), EXIT.INFRA, "no cell ran: nothing was checked");
});

test("problems are de-duplicated across cells by kind and location", () => {
	const groups = dedupeProblems(readCells(DIRS));
	assert.deepEqual(groups.map((g) => [g.kind, g.location, g.cells.length, g.count]), [
		["script_error", "_step (res://scripts/sim/run_world.gd:612)", 1, 1],
		["stuck", "henesys_hg1 platform 7", 2, 3],
		["stuck", "henesys_hg1 platform 3", 1, 1],
	]);
	const stuck7 = groups[1];
	assert.deepEqual(stuck7.cells, ["matrix_henesys_hg1_sensible_s1", "matrix_henesys_hg1_sensible_s2"]);
	assert.equal(stuck7.first.time, 85, "the earliest occurrence is the example");
	assert.match(stuck7.first.replay ?? "", /--replay=.*sensible_s1/);
});

test("the summary has an outcomes table, the de-duplicated problems, metric spreads and the worst exit", () => {
	const s = matrixSummary("matrix", DIRS);
	assert.equal(s.json.exit_code, EXIT.INFRA);
	assert.equal(s.json.cells.length, 3);
	assert.deepEqual(s.json.outcomes, { DEAD: 1, TIMEOUT: 1, "no end": 1 });
	assert.deepEqual(s.json.metrics.level, { n: 2, min: 14, median: 17, max: 20 });
	assert.deepEqual(s.json.metrics.time, { n: 2, min: 421.5, median: 510.75, max: 600 });
	assert.equal(s.json.problems.length, 3);
	const md = s.markdown;
	assert.match(md, /^# Agent playtest matrix: matrix/m);
	assert.match(md, /\| matrix_henesys_hg1_sensible_s1 \| sensible \| 1 \| 1 \| DEAD 7:01\.5 \| Lv 14 \| 200 \| 310 \| 0\/60 \| 2 \|/);
	assert.match(md, /\| matrix_henesys_hg1_sensible_s2026 \| sensible \| 2026 \| 2 \| no end \|/);
	assert.match(md, /\*\*stuck\*\* at henesys_hg1 platform 7: 2 cells, 3 times/);
	assert.match(md, /liveness timeout/, "infrastructure errors are listed per cell");
	assert.match(md, /exit code: 2/);
});

test("the outcomes table shows each cell's Jev-sourced decisions, so a fallback cell inside a Jev matrix stands out", () => {
	const s = matrixSummary("matrix", DIRS);
	assert.match(s.markdown, /\| cell \| personality \| seed \| exit \| outcome \| level \| job \| kills \| Jev decisions \| problems \|/);
	assert.match(s.markdown, /\| matrix_henesys_hg1_sensible_s2 \| .* \| 75\/80 \| \d+ \|/);
	assert.deepEqual(s.json.cells.map((c) => c.decisions), [{ jev: 0, total: 60 }, { jev: 75, total: 80 }, { jev: 0, total: 3 }]);
	assert.deepEqual(s.json.decisions_by_source, { "fallback:sensible": 19, "fallback:tactic-rules": 49, jev: 75 });
});
