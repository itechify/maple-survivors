// The windowed replay end to end through the CLI entry (maple/scenario_run.ts -> maple/windowed_replay.ts) against a
// fake driver recording and a fake windowed scene (fixtures/fake_windowed.ts): the scene gets the recording, the output
// directory, the speed and the screenshot times; the report lists the screenshots and the replay verdict; the CLI
// re-checks the scene's decisions and fingerprint with #98's replay code; a crash or silence is an infrastructure error.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { runCli } from "../src/maple/scenario_run.ts";
import { runOptionsFrom, cliFlags } from "../src/cli.ts";
import { EXIT } from "../src/core/exit_codes.ts";
import { personalityNames } from "../src/maple/personalities.ts";
import { windowedSceneArgs } from "../src/maple/windowed_replay.ts";
import { parseShotsAt } from "../src/maple/windowed_flags.ts";
import { windowedReplayCommand } from "../src/maple/run.ts";

const FAKE = path.join(import.meta.dirname, "..", "fixtures", "fake_driver.ts");
const FAKE_WINDOWED = path.join(import.meta.dirname, "..", "fixtures", "fake_windowed.ts");
const REPO = path.resolve(import.meta.dirname, "..", "..", "..");
const tmp = () => fs.mkdtempSync(path.join(os.tmpdir(), "playtest-win-"));
const KNOWN = { personalities: personalityNames(), stages: ["henesys_hg1", "tree_that_grew_1", "dark_cave"], tiers: 2, cores: 16 };
const readJson = (f: string) => JSON.parse(fs.readFileSync(f, "utf8"));

async function cli(argv: string[], windowedMode = "match", livenessS?: number, driverMode = "ok") {
	const parsed = cliFlags().parse([...argv, ...(livenessS ? [`--liveness-s=${livenessS}`] : [])]);
	assert.deepEqual(parsed.errors, []);
	return runCli({ values: parsed.values, explicit: parsed.explicit, optionsFrom: runOptionsFrom, repo: REPO, known: KNOWN,
		now: new Date(2026, 9, 16, 9, 0, 0), env: { TYPESAFE_API_KEY: "" },
		overrides: { launch: { command: process.execPath, args: [FAKE, `--mode=${driverMode}`] }, readUserKey: () => null },
		windowedLaunch: { command: process.execPath, args: [FAKE_WINDOWED, `--mode=${windowedMode}`] } });
}

/** A recorded run directory (fake driver, fallback brain). */
async function recording(driverMode = "ok"): Promise<string> {
	const dir = path.join(tmp(), "run");
	const r = await cli(["--brain=fallback", `--out=${dir}`], "match", undefined, driverMode);
	assert.equal(r.exitCode, EXIT.OK);
	return dir;
}

test("the scene gets the recording, the output directory, the speed and the screenshot times", () => {
	assert.deepEqual(windowedSceneArgs({ replay: "C:\\r\\run", out: "C:\\r\\win", speed: 2, shotsAt: [60, 412.5], skipTo: 30 }),
		["--replay=C:/r/run", "--out=C:/r/win", "--speed=2", "--shots-at=60,412.5", "--skip-to=30"]);
	assert.deepEqual(windowedSceneArgs({ replay: "/r", out: "/w", speed: 4, shotsAt: [] }), ["--replay=/r", "--out=/w", "--speed=4"]);
});

test("a matching windowed replay reports match and lists its screenshots; the recording's report points at it", async () => {
	const orig = await recording("dead");
	const out = path.join(tmp(), "win");
	const r = await cli([`--replay=${orig}`, "--windowed", "--shots-at=60,150", `--out=${out}`]);
	assert.equal(r.exitCode, EXIT.OK, r.text);
	const args = readJson(path.join(out, "replay.json")).args as string[];
	assert.ok(args.includes(`--replay=${orig.replaceAll("\\", "/")}`) && args.includes("--speed=4") && args.includes("--shots-at=60,150"));
	const md = fs.readFileSync(path.join(out, "report.md"), "utf8");
	assert.match(md, /\*\*brain used:\*\* windowed replay of /);
	assert.match(md, /\*\*replay:\*\* match \(\d+ decisions/);
	assert.match(md, /## Screenshots/);
	assert.match(md, /\| 1:00 \(tick 3600\) \| `shots\/at_60s\.png` \| --shots-at 60 \|/);
	assert.match(md, /\| 0:10 \(tick 600\) \| `shots\/finding_stuck_10s\.png` \| finding stuck: injected \|/);
	assert.match(md, /`at_999s\.png` not saved \(16:39\): after the time cap/);
	assert.match(md, /`shots\/levelup_2\.png`/);
	assert.match(md, /No deterministic problems found/);
	assert.ok(readJson(path.join(out, "report.json")).screenshots.shots.length >= 4);
	const recorded = fs.readFileSync(path.join(orig, "report.md"), "utf8");
	const section = (text: string, name: string) => text.split(`## ${name}\n`)[1]?.split("\n## ")[0];
	assert.equal(section(md, "Metrics"), section(recorded, "Metrics"), "a match reports the recorded round's metrics");
	assert.match(recorded, /## Windowed replays/);
	assert.match(recorded, /match, 4 screenshots/);
});

test("a diverging windowed replay is a replay_divergence naming the first field and the first timeline difference", async () => {
	const orig = await recording();
	const out = path.join(tmp(), "win");
	const r = await cli([`--replay=${orig}`, "--windowed", `--out=${out}`], "diverge");
	assert.equal(r.exitCode, EXIT.PROBLEMS, r.text);
	const md = fs.readFileSync(path.join(out, "report.md"), "utf8");
	assert.match(md, /\*\*replay:\*\* DIVERGED: fingerprint\.ticks: replay \d+, recorded \d+/);
	assert.match(md, /\*\*replay_divergence\*\* \(error\)[^\n]*fingerprint\.ticks/);
	assert.match(md, /first timeline difference: row 3 at 0:03 \(tick 180\): x 10 -> 12/);
	assert.match(md, /## Screenshots/, "the screenshots are kept on a divergence");
});

test("the CLI re-checks the scene's applied decisions with #98's replay code", async () => {
	const orig = await recording();
	const out = path.join(tmp(), "win");
	const r = await cli([`--replay=${orig}`, "--windowed", `--out=${out}`], "drift");
	assert.equal(r.exitCode, EXIT.PROBLEMS, r.text);
	assert.match(fs.readFileSync(path.join(out, "report.md"), "utf8"), /decision 1: the driver applied \w+, recorded \w+/);
});

test("a crash without replay.json is an infrastructure error, with the script error in the problems", async () => {
	const orig = await recording();
	const out = path.join(tmp(), "win");
	const r = await cli([`--replay=${orig}`, "--windowed", `--out=${out}`], "crash");
	assert.equal(r.exitCode, EXIT.INFRA, r.text);
	const md = fs.readFileSync(path.join(out, "report.md"), "utf8");
	assert.match(md, /the windowed replay wrote no replay\.json/);
	assert.match(md, /SCRIPT ERROR: Invalid call/);
});

test("a silent scene is killed by the liveness timeout", async () => {
	const orig = await recording();
	const r = await cli([`--replay=${orig}`, "--windowed", `--out=${path.join(tmp(), "win")}`], "hang", 1);
	assert.equal(r.exitCode, EXIT.INFRA);
	assert.match(r.text, /no output from the windowed replay for 1 s/);
});

test("the windowed replay command the reports print (#99) parses with these flags", () => {
	const cmd = windowedReplayCommand(path.join(REPO, "evidence", "agent-playtest", "x"), 412.46, REPO);
	const argv = cmd.replace(/^bash scripts\/agent_playtest\.sh /, "").split(" ");
	const parsed = cliFlags().parse(argv);
	assert.deepEqual(parsed.errors, []);
	assert.equal(parsed.values.windowed, true);
	assert.deepEqual(parseShotsAt(String(parsed.values["shots-at"])), [412.5]);
});

test("--windowed needs --replay, and --shots-at takes run seconds", async () => {
	const a = await cli(["--windowed"]);
	assert.equal(a.exitCode, EXIT.INFRA);
	assert.match(a.text, /--windowed needs --replay=<run dir>/);
	const orig = await recording();
	const b = await cli([`--replay=${orig}`, "--windowed", "--shots-at=1:00"]);
	assert.equal(b.exitCode, EXIT.INFRA);
	assert.match(b.text, /--shots-at takes run seconds separated by commas/);
});
