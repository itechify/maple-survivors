// --personality on a whole run (maple/run.ts) against the fake driver: the resolved personality is recorded in the
// run directory and reaches the driver, the fallback brain is the personality's, the header names it, and an unknown
// or invalid personality stops before the game starts. No Godot, no network.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { runPlaytest } from "../src/maple/run.ts";
import { EXIT } from "../src/core/exit_codes.ts";
import { driverParams, loadPersonality } from "../src/maple/personality.ts";

const FAKE = path.join(import.meta.dirname, "..", "fixtures", "fake_driver.ts");
const tmp = () => fs.mkdtempSync(path.join(os.tmpdir(), "playtest-personality-"));
const base = { stage: "henesys_hg1", seed: 2026, minutes: 3, brain: "fallback", livenessS: 10, env: {} };

test("the personality is written to the run directory and passed to the driver", async () => {
	const out = path.join(tmp(), "run");
	const r = await runPlaytest({ ...base, personality: "defensive", out,
		launch: { command: process.execPath, args: [FAKE, "--mode=tactics"] } });
	assert.equal(r.exitCode, EXIT.OK);
	const written = JSON.parse(fs.readFileSync(path.join(out, "personality.json"), "utf8"));
	assert.deepEqual(written, driverParams(loadPersonality("defensive").personality!));
	const log = fs.readFileSync(path.join(out, "game.log"), "utf8");
	assert.ok(log.includes(`--personality-file=${path.join(out, "personality.json")}`), "the driver gets the file");
	const report = JSON.parse(fs.readFileSync(path.join(out, "report.json"), "utf8"));
	assert.equal(report.personality.name, "defensive");
	assert.deepEqual(report.personality.tactics.allowed, ["defensive", "kite"]);
});

test("a fallback run answers with the personality's fallback brain and the header names it", async () => {
	const out = path.join(tmp(), "run");
	await runPlaytest({ ...base, personality: "defensive", out, launch: { command: process.execPath, args: [FAKE, "--mode=tactics"] } });
	const decisions = fs.readFileSync(path.join(out, "decisions.jsonl"), "utf8").trim().split("\n").map((l) => JSON.parse(l));
	// the fake driver offers all six tactics; defensive's table: calm -> kite, drops near -> kite, critical HP -> defensive
	assert.deepEqual(decisions.map((d) => d.answer), ["kite", "kite", "defensive"]);
	const md = fs.readFileSync(path.join(out, "report.md"), "utf8");
	assert.match(md, /\*\*personality:\*\* defensive/);
	assert.match(md, /\*\*brain used:\*\* fallback:defensive/);
});

test("an unknown personality is an infrastructure error before the game starts", async () => {
	const out = path.join(tmp(), "run");
	const r = await runPlaytest({ ...base, personality: "nobody", out, launch: { command: process.execPath, args: [FAKE, "--mode=ok"] } });
	assert.equal(r.exitCode, EXIT.INFRA);
	const md = fs.readFileSync(path.join(out, "report.md"), "utf8");
	assert.match(md, /no personality nobody/);
	assert.ok(!fs.existsSync(path.join(out, "record.json")), "the game was not started");
});
