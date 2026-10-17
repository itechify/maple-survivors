// The final report with the Jev-assisted evaluations (#99), rendered from run directories the fake driver writes from
// synthetic fixtures (fixtures/run_fixtures.ts): a DEAD run with a finding, a clean CLEARED run and a fallback run
// with no key; --strict-eval; and a replay that never evaluates. The Jev transport is mocked: no network.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { runPlaytest } from "../src/maple/run.ts";
import { readRecording } from "../src/core/replay.ts";
import { EXIT } from "../src/core/exit_codes.ts";

const FAKE = path.join(import.meta.dirname, "..", "fixtures", "fake_driver.ts");
const tmp = () => fs.mkdtempSync(path.join(os.tmpdir(), "playtest-eval-"));
const launch = (mode: string) => ({ command: process.execPath, args: [FAKE, `--mode=${mode}`] });
const base = { stage: "henesys_hg1", seed: 2026, minutes: 3, personality: "sensible", brain: "fallback", livenessS: 10,
	evaluations: true, readUserKey: () => null };

/** A mocked TypeSafe transport: an unfair, unavoidable death; busy minutes; normal movement. */
function jev(answers: Record<string, unknown> = {}) {
	const sent: Array<Record<string, any>> = [];
	const fetch = async (_url: string, init?: RequestInit) => {
		const body = JSON.parse(String(init?.body));
		sent.push(body);
		const out = Object.fromEntries(Object.entries<any>(body.questions).map(([n, q]) => [n, answers[n]
			?? (n === "fairness" ? { type: "score", score: 2.6, confidence: 0.8, probabilities: {} }
				: n === "avoidable" ? { type: "noul", noul: 0.15 } : q.type === "noul" ? { type: "noul", noul: 0.3 }
				: { type: "score", score: 0.4, confidence: 0.9, probabilities: {} })]));
		return new Response(JSON.stringify({ model: "jev-1.13.0", answers: out, usage: { input_tokens: 400, output_tokens: 12 } }),
			{ status: 200, headers: { "content-type": "application/json" } });
	};
	return { sent, fetch };
}

const read = (dir: string, f: string) => fs.readFileSync(path.join(dir, f), "utf8");
const lineOf = (md: string, re: RegExp) => md.split("\n").findIndex((l) => re.test(l));

test("a DEAD run with a finding: verdict first, then deterministic failures, then Jev-flagged, with windowed replay commands", async () => {
	const out = path.join(tmp(), "run");
	const t = jev();
	const r = await runPlaytest({ ...base, out, env: { TYPESAFE_API_KEY: "test-key" }, launch: launch("dead_findings"), jevFetch: t.fetch });
	assert.equal(r.exitCode, EXIT.PROBLEMS, "the finding decides the exit code");
	assert.equal(t.sent.length, 3, "death, pacing and movement requests");
	const md = read(out, "report.md");
	const verdict = lineOf(md, /^\*\*Verdict:\*\*/);
	assert.ok(verdict >= 0 && verdict < 5, "the verdict sits right under the title");
	assert.match(md.split("\n")[verdict], /1 deterministic failure \(stuck at 0:25\)/);
	assert.match(md.split("\n")[verdict], /Jev: 1 flagged, 0 need review/);
	const next = md.split("\n")[lineOf(md, /^\*\*Next:\*\*/)];
	assert.match(next, /--replay=\S+ --windowed --shots-at=25/, "next: screenshots at the first deterministic problem");
	const det = lineOf(md, /^### Deterministic failures \(1\)/);
	const flagged = lineOf(md, /^### Jev-flagged \(1\)/);
	assert.ok(det > 0 && flagged > det, "deterministic before Jev-flagged");
	assert.equal(lineOf(md, /^### Needs human review/), -1, "no empty review heading");
	const entry = md.split("\n").slice(flagged).join("\n");
	assert.match(entry, /\*\*death felt unfair\*\* \(Jev-flagged\) at 1:04\.5, tick 3870/);
	assert.match(entry, /unfairness 2\.6 of 3 \(confidence 0\.8\); avoidable by a careful player: p 0\.15/);
	assert.match(entry, /windowed replay: `bash scripts\/agent_playtest\.sh --replay=\S+ --windowed --shots-at=64\.5`/);
	assert.match(md, /- \*\*evaluations:\*\* done: /);
	const ev = JSON.parse(read(out, "evaluations.json"));
	assert.equal(ev.status, "done");
	assert.equal(ev.results.find((x: any) => x.id === "death_fairness").class, "flagged");
	assert.ok(ev.states.death, "the exact facts sent are kept");
	const json = JSON.parse(read(out, "report.json"));
	assert.equal(json.problems.jev_flagged.length, 1);
	assert.equal(json.evaluations.status, "done");
	assert.match(md, /`evaluations\.json`/);
	assert.match(md, /`hits\.jsonl`/);
	assert.ok(!md.includes("test-key") && !read(out, "evaluations.json").includes("test-key"), "the key is never written");
});

test("Jev results never change the exit code unless --strict-eval", async () => {
	const plain = await runPlaytest({ ...base, out: path.join(tmp(), "run"), env: { TYPESAFE_API_KEY: "k" }, launch: launch("dead"),
		jevFetch: jev().fetch });
	assert.equal(plain.exitCode, EXIT.OK);
	assert.match(plain.markdown, /\*\*Verdict:\*\* .*no deterministic problems.*Jev: 1 flagged/);
	const strict = await runPlaytest({ ...base, out: path.join(tmp(), "run"), env: { TYPESAFE_API_KEY: "k" }, launch: launch("dead"),
		jevFetch: jev().fetch, strictEval: true });
	assert.equal(strict.exitCode, EXIT.PROBLEMS);
	assert.match(strict.markdown, /--strict-eval/);
	const review = await runPlaytest({ ...base, out: path.join(tmp(), "run"), env: { TYPESAFE_API_KEY: "k" }, launch: launch("dead"),
		jevFetch: jev({ fairness: { type: "score", score: 2.4, confidence: 0.3 }, avoidable: { type: "noul", noul: 0.35 } }).fetch,
		strictEval: true });
	assert.equal(review.exitCode, EXIT.OK, "needs review never fails, even with --strict-eval");
	assert.match(review.markdown, /### Needs human review \(1\)/);
});

test("a clean CLEARED run: a clean verdict, metrics with milestones and boss fights, nothing flagged", async () => {
	const out = path.join(tmp(), "run");
	const r = await runPlaytest({ ...base, out, env: { TYPESAFE_API_KEY: "k" }, launch: launch("cleared"), jevFetch: jev().fetch });
	assert.equal(r.exitCode, EXIT.OK);
	const md = read(out, "report.md");
	assert.match(md, /\*\*Verdict:\*\* clean: no deterministic problems; Jev: 0 flagged, 0 need review; exit code 0/);
	assert.match(md, /\*\*Next:\*\* nothing to fix/);
	assert.match(md, /## Metrics/);
	assert.match(md, /Milestones: Lv 8 1:15, Lv 10 1:35, Lv 20 -, Lv 30 -; 1st job \(Magician, 200\) 1:35/);
	assert.match(md, /\| level \| 7 \| 13 \|/);
	assert.match(md, /Boss fights: 2220000 1:00 -> dead at 2:05 \(65 s\)/);
	assert.match(md, /Potions: HP collected 2, used 1, left 4; MP collected 1, used 1, left 0/);
	assert.match(md, /Cards taken \(2\): three_snails_count, magic_claw_new/);
	assert.match(md, /No deterministic problems found/);
	assert.match(md, /Jev flagged nothing/);
});

test("a fallback run with no key: the evaluations are skipped and the report says why", async () => {
	const out = path.join(tmp(), "run");
	const r = await runPlaytest({ ...base, out, env: {}, launch: launch("dead") });
	assert.equal(r.exitCode, EXIT.OK);
	const md = read(out, "report.md");
	assert.match(md, /- \*\*evaluations:\*\* skipped \(no TypeSafe key: key absent/);
	assert.match(md, /Jev-assisted evaluations were skipped/);
	assert.equal(JSON.parse(read(out, "evaluations.json")).status, "skipped");
});

test("evaluations off by scenario: skipped with that reason, and no request", async () => {
	const t = jev();
	const r = await runPlaytest({ ...base, evaluations: false, out: path.join(tmp(), "run"), env: { TYPESAFE_API_KEY: "k" },
		launch: launch("dead"), jevFetch: t.fetch });
	assert.equal(t.sent.length, 0);
	assert.match(r.markdown, /evaluations:\*\* skipped \(turned off/);
});

test("a replay never calls Jev for evaluations", async () => {
	const orig = path.join(tmp(), "orig");
	await runPlaytest({ ...base, out: orig, env: { TYPESAFE_API_KEY: "k" }, launch: launch("dead"), jevFetch: jev().fetch });
	const recording = readRecording(orig);
	assert.ok(!("error" in recording));
	const t = jev();
	const r = await runPlaytest({ ...base, out: path.join(tmp(), "replay"), env: { TYPESAFE_API_KEY: "k" }, launch: launch("dead"),
		jevFetch: t.fetch, replay: recording });
	assert.equal(t.sent.length, 0);
	assert.match(r.markdown, /evaluations:\*\* skipped \(replay: the recording's evaluations\.json has the verdicts\)/);
});
