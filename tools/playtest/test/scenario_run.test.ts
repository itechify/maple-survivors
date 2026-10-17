// Scenarios, replay, matrices, tier chains and warp end to end through the CLI entry (maple/scenario_run.ts) against
// the fake driver: scenario.json records what a replay needs, a replay matches without any key, a tampered recording
// diverges, a matrix writes one directory per cell plus summary.md / summary.json with the worst exit code.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { runCli } from "../src/maple/scenario_run.ts";
import { runOptionsFrom, cliFlags } from "../src/cli.ts";
import { EXIT } from "../src/core/exit_codes.ts";
import { driverArgs } from "../src/maple/launcher.ts";
import { personalityNames } from "../src/maple/personalities.ts";

const FAKE = path.join(import.meta.dirname, "..", "fixtures", "fake_driver.ts");
const REPO = path.resolve(import.meta.dirname, "..", "..", "..");
const tmp = () => fs.mkdtempSync(path.join(os.tmpdir(), "playtest-scn-"));
const KNOWN = { personalities: personalityNames(), stages: ["henesys_hg1", "tree_that_grew_1", "dark_cave"], tiers: 2, cores: 16 };
const launch = (mode = "ok") => ({ command: process.execPath, args: [FAKE, `--mode=${mode}`] });
const noKey = () => { throw new Error("the user key must not be consulted"); };
const readJsonl = (f: string) => fs.readFileSync(f, "utf8").split("\n").filter(Boolean).map((l) => JSON.parse(l));
const readJson = (f: string) => JSON.parse(fs.readFileSync(f, "utf8"));

async function cli(argv: string[], extra: Record<string, unknown> = {}) {
	const { values, explicit, errors } = cliFlags().parse(argv);
	assert.deepEqual(errors, []);
	return runCli({ values, explicit, optionsFrom: runOptionsFrom, repo: REPO, known: KNOWN, now: new Date(2026, 9, 16, 9, 0, 0),
		overrides: { launch: launch(), readUserKey: noKey, ...extra }, env: { TYPESAFE_API_KEY: "" } });
}

test("a run records scenario.json: the scenario, the cell, every flag value, the driver's hello", async () => {
	const out = path.join(tmp(), "run");
	const r = await cli(["--brain=fallback", `--out=${out}`, "--stuck-s=9"]);
	assert.equal(r.exitCode, EXIT.OK);
	const s = readJson(path.join(out, "scenario.json"));
	assert.equal(s.scenario.name, "smoke");
	assert.equal(s.scenario.file.minutes, 3);
	assert.deepEqual([s.cell.stage, s.cell.seed, s.cell.personality, s.cell.minutes, s.cell.brain, s.cell.stuckS],
		["henesys_hg1", 2026, "sensible", 3, "fallback", 9]);
	assert.equal(s.flags.brain, "fallback");
	assert.equal(s.flags["stuck-s"], 9);
	assert.equal(s.flags.model, "jev-latest", "the brain's own flags are recorded too");
	assert.equal(s.hello.type, "hello");
	assert.ok(Array.isArray(s.driver_args));
	const md = fs.readFileSync(path.join(out, "report.md"), "utf8");
	assert.match(md, /\*\*scenario:\*\* smoke/);
	assert.match(md, /## Reproduce/);
	assert.match(md, /live re-run: `bash scripts\/agent_playtest\.sh --stage=henesys_hg1 --seed=2026 --minutes=3 --personality=sensible --brain=fallback --stuck-s=9`/);
	assert.match(md, /replay: `bash scripts\/agent_playtest\.sh --replay=.*run`/);
});

test("the default run directory is <scenario>_<stage>_<personality>_s<seed>_<time>", async () => {
	const repo = tmp();
	fs.mkdirSync(path.join(repo, "game", "data", "survivor"), { recursive: true });
	const { values, explicit } = cliFlags().parse(["--brain=fallback"]);
	const r = await runCli({ values, explicit, optionsFrom: runOptionsFrom, repo, known: KNOWN, now: new Date(2026, 9, 16, 17, 5, 9),
		overrides: { launch: launch() }, env: {} });
	assert.equal(r.dir, path.join(repo, "evidence", "agent-playtest", "smoke_henesys_hg1_sensible_s2026_20261016-170509"));
});

test("problem entries carry the replay command next to the live re-run", async () => {
	const out = path.join(tmp(), "run");
	const r = await cli(["--brain=fallback", `--out=${out}`], { launch: launch("findings") });
	assert.equal(r.exitCode, EXIT.PROBLEMS);
	const md = fs.readFileSync(path.join(out, "report.md"), "utf8");
	assert.match(md, /\*\*stuck\*\*[^\n]*\n(?:   - [^\n]*\n)*   - replay: `bash scripts\/agent_playtest\.sh --replay=[^`]*run`/);
	assert.match(readJson(path.join(out, "report.json")).problems.replay, /--replay=/);
});

async function recorded(argv: string[] = []) {
	const out = path.join(tmp(), "orig");
	const r = await cli(["--brain=fallback", `--out=${out}`, ...argv]);
	assert.equal(r.exitCode, EXIT.OK);
	return out;
}

test("a replay answers from decisions.jsonl without any key, and the fingerprint matches", async () => {
	const orig = await recorded();
	const out = path.join(tmp(), "replay");
	const r = await cli([`--replay=${orig}`, `--out=${out}`], { readUserKey: noKey });
	assert.equal(r.exitCode, EXIT.OK, fs.readFileSync(path.join(out, "report.md"), "utf8"));
	assert.deepEqual(readJsonl(path.join(out, "decisions.jsonl")).map((d) => [d.id, d.answer, d.source]),
		[[1, "b", "replay"], [2, "200", "replay"]]);
	const md = fs.readFileSync(path.join(out, "report.md"), "utf8");
	assert.match(md, /\*\*brain used:\*\* replay of /);
	assert.match(md, /\*\*replay:\*\* match/);
	assert.match(md, /\*\*Jev:\*\* not used \(replay\)/);
	assert.equal(readJson(path.join(out, "scenario.json")).replay_of, orig);
});

test("a replay of a Jev run needs no key (the recorded answers replace Jev)", async () => {
	const orig = await recorded();
	const file = path.join(orig, "decisions.jsonl");
	const lines = readJsonl(file).map((d) => ({ ...d, source: "jev", confidence: 0.4, presented_order: d.options }));
	fs.writeFileSync(file, lines.map((l) => JSON.stringify(l)).join("\n") + "\n");
	const s = readJson(path.join(orig, "scenario.json"));
	s.cell.brain = "jev";
	s.flags.brain = "jev";
	fs.writeFileSync(path.join(orig, "scenario.json"), JSON.stringify(s));
	const out = path.join(tmp(), "replay");
	const r = await cli([`--replay=${orig}`, `--out=${out}`], { readUserKey: noKey });
	assert.equal(r.exitCode, EXIT.OK);
	const d = readJsonl(path.join(out, "decisions.jsonl"));
	assert.deepEqual(d.map((x) => [x.source, x.recorded_source]), [["replay", "jev"], ["replay", "jev"]]);
	assert.deepEqual(d[0].presented_order, ["a", "b"]);
});

test("a replay hands the driver the recording's personality.json, not today's personality file", async () => {
	const orig = await recorded(["--personality=aggressive"]);
	const params = { ...readJson(path.join(orig, "personality.json")), motor: { recorded_marker: 1 } };
	fs.writeFileSync(path.join(orig, "personality.json"), JSON.stringify(params));
	const s = readJson(path.join(orig, "scenario.json"));
	s.hello.personality_params = params;
	fs.writeFileSync(path.join(orig, "scenario.json"), JSON.stringify(s));
	const out = path.join(tmp(), "replay");
	const r = await cli([`--replay=${orig}`, `--out=${out}`]);
	assert.equal(r.exitCode, EXIT.OK, fs.readFileSync(path.join(out, "report.md"), "utf8"));
	assert.deepEqual(readJson(path.join(out, "personality.json")), params);
	assert.deepEqual(readJson(path.join(out, "scenario.json")).hello.personality_params, params);
	const changed = path.join(tmp(), "replay2");
	s.hello.personality_params = { ...params, motor: { recorded_marker: 2 } };
	fs.writeFileSync(path.join(orig, "scenario.json"), JSON.stringify(s));
	const d = await cli([`--replay=${orig}`, `--out=${changed}`]);
	assert.equal(d.exitCode, EXIT.PROBLEMS, "a driver that played other personality params diverges");
	assert.match(readJsonl(path.join(changed, "findings.jsonl"))[0].message, /hello\.personality_params/);
});

test("a tampered offered answer diverges: replay_divergence names the first diverging decision (exit 1)", async () => {
	const orig = await recorded();
	const file = path.join(orig, "decisions.jsonl");
	const lines = readJsonl(file);
	lines[0].answer = "a";
	fs.writeFileSync(file, lines.map((l) => JSON.stringify(l)).join("\n") + "\n");
	const out = path.join(tmp(), "replay");
	const r = await cli([`--replay=${orig}`, `--out=${out}`]);
	assert.equal(r.exitCode, EXIT.PROBLEMS);
	const findings = readJsonl(path.join(out, "findings.jsonl"));
	assert.equal(findings[0].kind, "replay_divergence");
	assert.match(findings[0].message, /decision 2: tick 150, recorded 120/);
	assert.ok(findings[0].divergences.some((d: { field?: string }) => d.field === "answers"), "the fingerprint differs too");
	assert.match(fs.readFileSync(path.join(out, "report.md"), "utf8"), /\*\*replay:\*\* DIVERGED/);
});

test("a tampered answer the driver rejects diverges on the applied answer", async () => {
	const orig = await recorded();
	const file = path.join(orig, "decisions.jsonl");
	const lines = readJsonl(file);
	lines[1].answer = "999";
	fs.writeFileSync(file, lines.map((l) => JSON.stringify(l)).join("\n") + "\n");
	const out = path.join(tmp(), "replay");
	const r = await cli([`--replay=${orig}`, `--out=${out}`]);
	assert.equal(r.exitCode, EXIT.PROBLEMS);
	const [f] = readJsonl(path.join(out, "findings.jsonl"));
	assert.equal(f.kind, "replay_divergence");
	assert.match(f.message, /decision 2: the driver applied 200, recorded 999 \(answer "999" is not an offered option\)/);
});

test("a directory without scenario.json cannot be replayed (exit 2)", async () => {
	const dir = tmp();
	fs.writeFileSync(path.join(dir, "decisions.jsonl"), "");
	const r = await cli([`--replay=${dir}`, `--out=${path.join(tmp(), "x")}`]);
	assert.equal(r.exitCode, EXIT.INFRA);
	assert.match(r.text, /scenario\.json/);
});

test("a matrix runs every cell in parallel with its own ISOLATE slot and writes the aggregate summary", async () => {
	const root = path.join(tmp(), "matrix");
	const r = await cli(["--scenario=matrix", "--brain=fallback", "--jobs=2", `--out=${root}`], {});
	assert.equal(r.exitCode, EXIT.OK);
	const cells = personalityNames().flatMap((p) => [1, 2, 2026].map((seed) => `matrix_henesys_hg1_${p}_s${seed}`));
	assert.equal(cells.length, 18, "six personalities x three seeds");
	for (const c of cells) assert.ok(fs.existsSync(path.join(root, c, "report.json")), c);
	const isolates = cells.map((c) => readJson(path.join(root, c, "record.json")).isolate);
	assert.ok(isolates.every((i) => i === "matrix_j0" || i === "matrix_j1"), isolates.join());
	const summary = readJson(path.join(root, "summary.json"));
	assert.equal(summary.exit_code, EXIT.OK);
	assert.equal(summary.cells.length, 18);
	assert.match(fs.readFileSync(path.join(root, "summary.md"), "utf8"), /\| matrix_henesys_hg1_sensible_s2 \| sensible \| 2 \| 0 \| TIMEOUT 3:00 \|/);
	assert.match(r.text, /summary\.md/);
});

test("the matrix exit code is the worst over its cells", async () => {
	const root = path.join(tmp(), "matrix");
	const r = await cli(["--scenario=matrix", "--brain=fallback", `--out=${root}`], { launch: launch("findings") });
	assert.equal(r.exitCode, EXIT.PROBLEMS);
	const summary = readJson(path.join(root, "summary.json"));
	assert.deepEqual(summary.problems.map((g: { kind: string; cells: string[] }) => [g.kind, g.cells.length]),
		[["hp_out_of_range", 18], ["stuck", 18]]);
});

test("a tier chain writes one record per round, and the driver gets --tier and --character", async () => {
	const out = path.join(tmp(), "chain");
	const r = await cli(["--scenario=tier_chain", "--brain=fallback", `--out=${out}`], { launch: launch("chain") });
	assert.equal(r.exitCode, EXIT.OK);
	assert.equal(readJson(path.join(out, "record_tier1.json")).state, "CLEARED");
	assert.equal(readJson(path.join(out, "record_tier2.json")).stage, "dark_cave");
	const md = fs.readFileSync(path.join(out, "report.md"), "utf8");
	assert.match(md, /--tier=2/);
	assert.match(md, /## Rounds/);
	assert.match(md, /\| 1 \| henesys_hg1 \|[^\n]*CLEARED 3:00[^\n]*`record_tier1\.json` \|/);
	assert.match(md, /\| 2 \| dark_cave \|[^\n]*`record_tier2\.json` \|/);
	const args = driverArgs("game", { stage: "henesys_hg1", seed: 1, minutes: 1, personality: "sensible", brain: "stdio",
		tier: 2 });
	assert.ok(args.includes("--tier=2"));
	const fx = driverArgs("game", { stage: "dark_cave", seed: 1, minutes: 1, personality: "sensible", brain: "stdio",
		character: "C:\\repo\\game\\tests\\fixtures\\characters\\lv35.json" });
	assert.ok(fx.includes("--character=C:/repo/game/tests/fixtures/characters/lv35.json"), fx.join(" "));
});

test("warp: decisions before the warp time take the sensible baseline (source warp); the header says so", async () => {
	const out = path.join(tmp(), "warp");
	const r = await cli(["--brain=fallback", "--warp=1.5", `--out=${out}`]);
	assert.equal(r.exitCode, EXIT.OK);
	assert.deepEqual(readJsonl(path.join(out, "decisions.jsonl")).map((d) => d.source), ["warp", "fallback:sensible"]);
	assert.match(fs.readFileSync(path.join(out, "report.md"), "utf8"), /\*\*warp:\*\* the first 1\.5 s/);
});

test("bad scenario input is an infrastructure error before any game starts", async () => {
	const r = await cli(["--scenario=nope"]);
	assert.equal(r.exitCode, EXIT.INFRA);
	assert.match(r.text, /unknown scenario nope/);
	const held = await cli(["--seed=101"]);
	assert.equal(held.exitCode, EXIT.INFRA);
	assert.match(held.text, /seed 101 is not a training seed/);
});
