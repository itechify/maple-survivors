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
import { driverArgs } from "../src/maple/launcher.ts";

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

const readJsonl = (f: string) => fs.readFileSync(f, "utf8").split("\n").filter(Boolean).map((l) => JSON.parse(l));

test("invariant findings make exit code 1; findings.jsonl holds the end's de-duplicated findings", async () => {
	const out = path.join(tmp(), "run");
	const r = await runPlaytest({ ...base, out, env: {}, launch: { command: process.execPath, args: [FAKE, "--mode=findings"] } });
	assert.equal(r.exitCode, EXIT.PROBLEMS);
	const findings = readJsonl(path.join(out, "findings.jsonl"));
	assert.deepEqual(findings.map((f) => [f.kind, f.count, f.source]), [["stuck", 4, "invariant"], ["hp_out_of_range", 1, "invariant"]]);
	const md = fs.readFileSync(path.join(out, "report.md"), "utf8");
	assert.match(md, /Deterministic failures \(2\)/);
	assert.match(md, /\*\*hp_out_of_range\*\* \(error\) at 1:00, tick 3600/);
	assert.match(md, /\*\*stuck\*\* \(warning\) at 0:25, tick 1500, seen 4 times/);
	assert.match(md, /re-run: `bash scripts\/agent_playtest\.sh --stage=henesys_hg1 --seed=2026 --minutes=3/);
	assert.match(md, /\*\*exit code:\*\* 1/);
	assert.equal(JSON.parse(fs.readFileSync(path.join(out, "report.json"), "utf8")).exit_code, 1);
});

test("streamed findings are kept when the driver never sent its end", async () => {
	const out = path.join(tmp(), "run");
	const r = await runPlaytest({ ...base, out, env: {}, launch: { command: process.execPath, args: [FAKE, "--mode=findings_no_end"] } });
	assert.equal(r.exitCode, EXIT.INFRA, "no end is still an infrastructure error");
	assert.deepEqual(readJsonl(path.join(out, "findings.jsonl")).map((f) => f.kind), ["stuck"]);
	assert.match(fs.readFileSync(path.join(out, "report.md"), "utf8"), /\*\*stuck\*\*/);
});

test("a SCRIPT ERROR in the game log is a deterministic problem (exit 1)", async () => {
	const out = path.join(tmp(), "run");
	const r = await runPlaytest({ ...base, out, env: {}, launch: { command: process.execPath, args: [FAKE, "--mode=script_error"] } });
	assert.equal(r.exitCode, EXIT.PROBLEMS);
	const md = fs.readFileSync(path.join(out, "report.md"), "utf8");
	assert.match(md, /\*\*script_error\*\* \(error\): SCRIPT ERROR: Invalid access/);
	assert.match(md, /run_world\.gd:612/);
	assert.deepEqual(readJsonl(path.join(out, "findings.jsonl")).map((f) => [f.kind, f.source]), [["script_error", "game.log"]]);
});

test("a clean run writes an empty findings.jsonl and exits 0", async () => {
	const out = path.join(tmp(), "run");
	const r = await runPlaytest({ ...base, out, env: {}, launch: { command: process.execPath, args: [FAKE, "--mode=ok"] } });
	assert.equal(r.exitCode, EXIT.OK);
	assert.equal(fs.readFileSync(path.join(out, "findings.jsonl"), "utf8"), "");
	assert.match(fs.readFileSync(path.join(out, "report.md"), "utf8"), /findings\.jsonl/);
});

test("a driver that stops talking mid-round is killed by the liveness timeout (exit 2)", async () => {
	const out = path.join(tmp(), "run");
	const r = await runPlaytest({ ...base, livenessS: 0.5, out, env: {}, launch: { command: process.execPath, args: [FAKE, "--mode=stall"] } });
	assert.equal(r.exitCode, EXIT.INFRA);
	assert.match(fs.readFileSync(path.join(out, "report.md"), "utf8"), /liveness timeout/);
});

test("the driver gets the run directory and the invariant flags", () => {
	const args = driverArgs("C:\\repo\\game", { stage: "henesys_hg1", seed: 2026, minutes: 5, personality: "sensible",
		brain: "stdio", out: "C:\\repo\\evidence\\agent-playtest\\run", stuckPx: 30, stuckS: 15, injectFinding: "stuck" });
	assert.ok(args.includes("--out=C:/repo/evidence/agent-playtest/run"), args.join(" "));
	assert.ok(args.includes("--stuck-px=30") && args.includes("--stuck-s=15") && args.includes("--inject-finding=stuck"));
	const plain = driverArgs("game", { stage: "henesys_hg1", seed: 1, minutes: 1, personality: "sensible", brain: "stdio" });
	assert.ok(!plain.some((a) => a.startsWith("--inject-finding") || a.startsWith("--stuck")), "defaults stay the driver's");
});

test("the CLI's liveness timeout defaults to 60 s and it knows --inject-finding", () => {
	const help = spawnSync(process.execPath, [CLI, "--help"], { encoding: "utf8" });
	assert.match(help.stdout, /--liveness-s=<number>.*\(default 60\)/);
	assert.match(help.stdout, /--inject-finding/);
	assert.match(help.stdout, /--stuck-px/);
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

// ---- #94: brain modes, the Jev brain over a mocked transport, and the report header -------------------------------

const SECRET = "test-key-do-not-leak";
/** A mocked TypeSafe transport answering every choice with its last label (no network). */
const jevFetch = (status = 200) => {
	const sent: unknown[] = [];
	const fetch = async (_url: string, init?: RequestInit) => {
		const body = JSON.parse(String(init?.body));
		sent.push(body);
		if (status !== 200) return new Response(JSON.stringify({ error: "x" }), { status });
		const answers: Record<string, unknown> = {};
		for (const [name, q] of Object.entries<any>(body.questions)) {
			if (q.type === "choice") {
				const labels = Object.keys(q.criteria);
				const choice = labels[labels.length - 1];
				answers[name] = { type: "choice", choice, confidence: 0.5,
					probabilities: Object.fromEntries(labels.map((l) => [l, l === choice ? 1 : 0])) };
			} else answers[name] = { type: "score", score: 1, confidence: 1, legend: {}, probabilities: { 0: 0, 1: 1 } };
		}
		return new Response(JSON.stringify({ model: "jev-1.13.0", answers, usage: { input_tokens: 300, output_tokens: 10 } }),
			{ status: 200, headers: { "content-type": "application/json" } });
	};
	return { sent, fetch };
};
const fakeLaunch = { command: process.execPath, args: [FAKE, "--mode=ok"] };
const allFiles = (dir: string) => fs.readdirSync(dir).map((f) => fs.readFileSync(path.join(dir, f), "utf8")).join("\n");
const readDecisions = (out: string) =>
	fs.readFileSync(path.join(out, "decisions.jsonl"), "utf8").trim().split("\n").map((l) => JSON.parse(l));

test("--brain=auto with a key decides through Jev; the header names the model, requests, tokens and Jev share", async () => {
	const out = path.join(tmp(), "run");
	const t = jevFetch();
	const r = await runPlaytest({ ...base, brain: "auto", out, env: { TYPESAFE_API_KEY: SECRET }, launch: fakeLaunch,
		jevFetch: t.fetch, readUserKey: () => { throw new Error("must not be consulted"); } });
	assert.equal(r.exitCode, EXIT.OK);
	assert.equal(t.sent.length, 2, "one request per decision");
	const decisions = readDecisions(out);
	assert.deepEqual(decisions.map((d) => d.source), ["jev", "jev"]);
	assert.ok(decisions.every((d) => d.confidence === 0.5 && Array.isArray(d.presented_order) && Array.isArray(d.screen_order)
		&& typeof d.probabilities === "object" && d.model === "jev-1.13.0"));
	const md = fs.readFileSync(path.join(out, "report.md"), "utf8");
	assert.match(md, /\*\*brain requested:\*\* auto/);
	assert.match(md, /\*\*brain used:\*\* jev/);
	assert.match(md, /\*\*fallback:\*\* none/);
	assert.match(md, /jev-1\.13\.0/);
	assert.match(md, /2 requests \(cap 400\)/);
	assert.match(md, /600 input \+ 20 output tokens/);
	assert.match(md, /Jev-sourced 2\/2 decisions \(100%\)/);
	assert.match(md, /key from the process env/);
	const json = JSON.parse(fs.readFileSync(path.join(out, "report.json"), "utf8"));
	assert.equal(json.jev.requests, 2);
	assert.match(fs.readFileSync(path.join(out, "game.log"), "utf8"), /"key_in_env":false/, "the game process never gets the key");
	assert.ok(!allFiles(out).includes(SECRET), "the key is nowhere in the run directory");
});

test("--brain=auto with the key hidden runs on the fallback and the header says why", async () => {
	const out = path.join(tmp(), "run");
	const r = await runPlaytest({ ...base, brain: "auto", out, env: { TYPESAFE_API_KEY: "" }, launch: fakeLaunch,
		readUserKey: () => "" });
	assert.equal(r.exitCode, EXIT.OK);
	const md = fs.readFileSync(path.join(out, "report.md"), "utf8");
	assert.match(md, /\*\*brain used:\*\* fallback:sensible/);
	assert.match(md, /\*\*fallback:\*\* key absent in process and user env/);
	assert.match(md, /\*\*Jev:\*\* not used/);
	assert.match(md, /fallback:sensible\s*\|\s*2/);
});

test("--brain=jev without a key is an infrastructure error before the game starts", async () => {
	const out = path.join(tmp(), "run");
	const r = await runPlaytest({ ...base, brain: "jev", out, env: {}, readUserKey: () => null,
		launch: { command: process.execPath, args: ["-e", "process.exit(9)"] } });
	assert.equal(r.exitCode, EXIT.INFRA);
	const md = fs.readFileSync(path.join(out, "report.md"), "utf8");
	assert.match(md, /--brain=jev.*key absent in process and user env/);
	assert.match(md, /\*\*brain used:\*\* none \(the game was not started\)/);
	const log = path.join(out, "game.log");
	assert.ok(!fs.existsSync(log) || !fs.readFileSync(log, "utf8").includes("process.exit(9)"), "the game was not started");
	assert.ok(!fs.existsSync(path.join(out, "record.json")));
});

test("API errors fall back per decision and the header counts them", async () => {
	const out = path.join(tmp(), "run");
	const r = await runPlaytest({ ...base, brain: "jev", out, env: { TYPESAFE_API_KEY: SECRET }, launch: fakeLaunch,
		jevFetch: jevFetch(500).fetch, jevRetry: { maxRetries: 0 } });
	assert.equal(r.exitCode, EXIT.OK, "a Jev outage is not a game problem");
	const md = fs.readFileSync(path.join(out, "report.md"), "utf8");
	assert.match(md, /\*\*brain used:\*\* jev, fallback on 2\/2 decisions/);
	assert.match(md, /\*\*fallback:\*\* API error 500 on 2\/2 decisions/);
	const decisions = readDecisions(out);
	assert.deepEqual(decisions.map((d) => d.source), ["fallback:sensible", "fallback:sensible"]);
	assert.ok(decisions.every((d) => /API error 500/.test(d.reason)));
});

test("--jev-max-requests caps the requests; the rest fall back; --model reaches the request", async () => {
	const out = path.join(tmp(), "run");
	const t = jevFetch();
	await runPlaytest({ ...base, brain: "jev", out, env: { TYPESAFE_API_KEY: SECRET }, launch: fakeLaunch, jevFetch: t.fetch,
		jevMaxRequests: 1, model: "jev-preview" });
	assert.equal(t.sent.length, 1);
	assert.equal((t.sent[0] as { model: string }).model, "jev-preview");
	const md = fs.readFileSync(path.join(out, "report.md"), "utf8");
	assert.match(md, /Jev request cap \(1\) reached on 1\/2 decisions/);
	assert.match(md, /Jev-sourced 1\/2 decisions \(50%\)/);
});

test("the CLI knows --brain=auto|jev|fallback|builtin, --model and --jev-max-requests", () => {
	const help = spawnSync(process.execPath, [CLI, "--help"], { encoding: "utf8" });
	assert.match(help.stdout, /--brain=<auto\|jev\|fallback\|builtin>/);
	assert.match(help.stdout, /default auto/);
	assert.match(help.stdout, /--model/);
	assert.match(help.stdout, /--jev-max-requests/);
});
