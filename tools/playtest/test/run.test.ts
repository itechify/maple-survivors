// A whole playtest run (maple/run.ts) against the fake driver: run directory, report and exit codes; and the CLI's
// exit code for bad flags. No Godot, no network.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { runPlaytest } from "../src/maple/run.ts";
import { EXIT } from "../src/core/exit_codes.ts";

const FAKE = path.join(import.meta.dirname, "..", "fixtures", "fake_driver.ts");
const CLI = path.join(import.meta.dirname, "..", "src", "cli.ts");
const tmp = () => fs.mkdtempSync(path.join(os.tmpdir(), "playtest-run-"));
const base = { stage: "henesys_hg1", seed: 2026, minutes: 3, personality: "sensible", brain: "fallback", livenessS: 10 };

test("a clean run exits 0 and writes the run directory", async () => {
	const out = path.join(tmp(), "run");
	const r = await runPlaytest({ ...base, out, env: {}, launch: { command: process.execPath, args: [FAKE, "--mode=ok"] } });
	assert.equal(r.exitCode, EXIT.OK);
	assert.equal(r.dir, out);
	for (const f of ["decisions.jsonl", "record.json", "fingerprint.json", "game.log", "report.md", "report.json"]) {
		assert.ok(fs.existsSync(path.join(out, f)), f);
	}
	const decisions = fs.readFileSync(path.join(out, "decisions.jsonl"), "utf8").trim().split("\n").map((l) => JSON.parse(l));
	assert.deepEqual(decisions.map((d) => [d.id, d.kind, d.answer, d.source]),
		[[1, "card", "b", "fallback:sensible"], [2, "job", "200", "fallback:sensible"]]);
	assert.ok(decisions.every((d) => Array.isArray(d.options) && typeof d.latency_ms === "number"));
	assert.equal(JSON.parse(fs.readFileSync(path.join(out, "record.json"), "utf8")).state, "TIMEOUT");
	const md = fs.readFileSync(path.join(out, "report.md"), "utf8");
	assert.match(md, /henesys_hg1/);
	assert.match(md, /fallback/i, "the header says which brain decided");
	assert.match(md, /TIMEOUT/);
	assert.match(md, /Lv 11/);
	assert.match(md, /fallback:sensible\s*\|\s*2/, "decisions by source");
	assert.match(md, /decisions\.jsonl/, "file list");
	const json = JSON.parse(fs.readFileSync(path.join(out, "report.json"), "utf8"));
	assert.equal(json.exit_code, 0);
	assert.equal(json.outcome.state, "TIMEOUT");
	assert.equal(fs.readFileSync(path.join(out, "game.log"), "utf8").includes("fake_driver: a log line"), true);
});

test("the default run directory is evidence/agent-playtest/<stage>_s<seed>_<time>", async () => {
	const repo = tmp();
	const r = await runPlaytest({ ...base, repo, env: {}, now: new Date(2026, 9, 16, 17, 5, 9),
		launch: { command: process.execPath, args: [FAKE, "--mode=ok"] } });
	assert.equal(r.dir, path.join(repo, "evidence", "agent-playtest", "henesys_hg1_s2026_20261016-170509"));
});

test("no end message is an infrastructure error (exit 2) and the report says why", async () => {
	const out = path.join(tmp(), "run");
	const r = await runPlaytest({ ...base, out, env: {}, launch: { command: process.execPath, args: [FAKE, "--mode=no_end"] } });
	assert.equal(r.exitCode, EXIT.INFRA);
	assert.match(fs.readFileSync(path.join(out, "report.md"), "utf8"), /no end message/);
});

test("a cache_missing driver error is an infrastructure error (exit 2)", async () => {
	const out = path.join(tmp(), "run");
	const r = await runPlaytest({ ...base, out, env: {}, launch: { command: process.execPath, args: [FAKE, "--mode=error"] } });
	assert.equal(r.exitCode, EXIT.INFRA);
	assert.match(fs.readFileSync(path.join(out, "report.md"), "utf8"), /cache_missing/);
});

test("a missing Godot is an infrastructure error (exit 2)", async () => {
	const out = path.join(tmp(), "run");
	const r = await runPlaytest({ ...base, out, env: { GODOT: path.join(tmp(), "no_godot.exe") } });
	assert.equal(r.exitCode, EXIT.INFRA);
	assert.match(fs.readFileSync(path.join(out, "report.md"), "utf8"), /Godot/);
});

test("the CLI exits 2 on an unknown flag and 0 on --help", () => {
	const bad = spawnSync(process.execPath, [CLI, "--no-such-flag=1"], { encoding: "utf8" });
	assert.equal(bad.status, EXIT.INFRA);
	assert.match(bad.stderr, /no-such-flag/);
	const help = spawnSync(process.execPath, [CLI, "--help"], { encoding: "utf8" });
	assert.equal(help.status, EXIT.OK);
	assert.match(help.stdout, /--stage/);
	assert.match(help.stdout, /--seed/);
});
