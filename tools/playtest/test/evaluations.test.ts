// Jev-assisted evaluations (#99: maple/eval_facts.ts, maple/evaluations.ts) against a mocked fetch: no network. Covers
// each request's shape (named buckets and short quoted text, never a raw number), the explicit classification
// thresholds, skipping without Jev, and card offers from the Scores the brain recorded.
import { test } from "node:test";
import assert from "node:assert/strict";
import { evaluationRequests, runEvaluations, classify, noulConfidence, RULES, FLAG_CONFIDENCE, opinionsOf }
	from "../src/maple/evaluations.ts";
import type { RunData } from "../src/maple/eval_facts.ts";
import { JevClient } from "../src/core/jev_client.ts";
import { deadRun, clearedRun, cardDecision } from "../fixtures/run_fixtures.ts";

const data = (run: ReturnType<typeof deadRun>, extra: Partial<RunData> = {}): RunData =>
	({ record: run.record, timeline: run.timeline, hits: run.hits, decisions: [], problems: [], ...extra });

/** Every leaf of `v` (object values, array items), with its path. */
function leaves(v: unknown, at = "state"): Array<[string, unknown]> {
	if (Array.isArray(v)) return v.flatMap((x, i) => leaves(x, `${at}[${i}]`));
	if (v !== null && typeof v === "object") return Object.entries(v).flatMap(([k, x]) => leaves(x, `${at}.${k}`));
	return [[at, v]];
}
const assertWordsOnly = (state: unknown) => {
	for (const [at, v] of leaves(state)) assert.equal(typeof v, "string", `${at} is ${JSON.stringify(v)}, not words`);
};

test("a DEAD run asks death fairness: one request, a fair-to-unfair Score plus an avoidable Noul over named buckets", () => {
	const reqs = evaluationRequests(data(deadRun()));
	const death = reqs.find((r) => r.id === "death");
	assert.ok(death, "death request");
	assertWordsOnly(death.state);
	assert.deepEqual(Object.keys(death.questions).sort(), ["avoidable", "fairness"]);
	const fairness = death.questions.fairness as { type: string; criteria: string[] };
	assert.equal(fairness.type, "score");
	assert.match(fairness.criteria[0], /^Clearly fair/);
	assert.match(fairness.criteria[fairness.criteria.length - 1], /^Clearly unfair/);
	const avoidable = death.questions.avoidable as { type: string; instructions: string };
	assert.equal(avoidable.type, "noul");
	assert.match(avoidable.instructions, /careful player/);
	const s = death.state as Record<string, any>;
	assert.equal(s["last 30 seconds, oldest first"].length, 6, "30 s in six 5 s chunks");
	assert.equal(s["last 30 seconds, oldest first"][5]["lowest HP"], "critical, then zero at the death", "20 of 100 HP: the game's critical (< 25%)");
	assert.equal(s["last 30 seconds, oldest first"][0]["lowest HP"], "full");
	assert.match(JSON.stringify(s["hits taken in the last 30 seconds"]), /the boss, contact/);
	assert.match(s["killing blow"], /the boss, contact.*large/);
	assert.match(s.boss, /arrived under 10 seconds before/);
	assert.equal(s["HP potions left"], "plenty");
	assert.match(s["tactic at death"], /^aggressive/);
	assert.ok(!JSON.stringify(s).includes("20.5"), "the hit before the window is left out");
});

test("no death request unless the round died", () => {
	assert.equal(evaluationRequests(data(clearedRun())).find((r) => r.id === "death"), undefined);
});

test("minute pacing batches one Score per run minute into one request, labelling the partial last minute", () => {
	const pacing = evaluationRequests(data(deadRun())).find((r) => r.id === "pacing");
	assert.ok(pacing);
	assertWordsOnly(pacing.state);
	const minutes = (pacing.state as Record<string, any>)["minutes of the round"];
	assert.deepEqual(Object.keys(minutes), ["minute 1 (0:00 to 1:00)"],
		"the 4.5 s last minute is under the minimum and skipped");
	assert.deepEqual(Object.keys(pacing.questions), ["m1"]);
	const q = pacing.questions.m1 as { type: string; instructions: string; criteria: string[] };
	assert.equal(q.type, "score");
	assert.match(q.instructions, /"minute 1 \(0:00 to 1:00\)"/, "the question names its state key");
	assert.match(q.criteria[0], /^Busy and engaging/);
	assert.match(q.criteria[q.criteria.length - 1], /^Nothing happening/);
	const m1 = minutes["minute 1 (0:00 to 1:00)"];
	assert.equal(m1["level-ups"], "a few");
	assert.equal(m1["monsters killed"], "lots");
	assert.equal(m1["hits taken"], "one");
	assert.equal(m1.boss, "a boss arrived");
	const cleared = evaluationRequests(data(clearedRun())).find((r) => r.id === "pacing");
	const labels = Object.keys((cleared!.state as Record<string, any>)["minutes of the round"]);
	assert.deepEqual(labels, ["minute 1 (0:00 to 1:00)", "minute 2 (1:00 to 2:00)", "minute 3 (2:00 to 2:30, the round ended)"]);
	assert.equal((cleared!.state as Record<string, any>)["minutes of the round"][labels[1]].boss, "a boss fight went on all minute");
});

test("movement asks one Noul over a movement summary", () => {
	const mv = evaluationRequests(data(deadRun(), { problems: [{ kind: "stuck", message: "x", time: 30 }] }))
		.find((r) => r.id === "movement");
	assert.ok(mv);
	assertWordsOnly(mv.state);
	assert.deepEqual(Object.keys(mv.questions), ["awkward"]);
	assert.equal((mv.questions.awkward as { type: string }).type, "noul");
	const s = mv.state as Record<string, string>;
	assert.equal(s["longest stay on one platform"], "over 30 seconds, up to 90");
	assert.equal(s["stuck findings (stayed inside a small box while pressing movement)"], "one");
	assert.equal(s["portals used"], "none");
	assert.equal(s["tactics used"], "aggressive almost all the time");
});

test("classification: past the threshold with confidence >= 0.6 is Jev-flagged, with less it needs review", () => {
	assert.equal(FLAG_CONFIDENCE, 0.6);
	const fair = RULES.death_fairness;
	assert.equal(classify(fair, 2.4, 0.7), "flagged");
	assert.equal(classify(fair, 2.4, 0.5), "review");
	assert.equal(classify(fair, 1.2, 0.9), "none");
	assert.equal(classify(RULES.death_avoidable, 0.1, noulConfidence(0.1)), "flagged", "clearly not avoidable");
	assert.equal(classify(RULES.death_avoidable, 0.35, noulConfidence(0.35)), "review");
	assert.equal(classify(RULES.death_avoidable, 0.9, noulConfidence(0.9)), "none", "avoidable is not a finding");
	assert.equal(classify(RULES.movement, 0.85, noulConfidence(0.85)), "flagged");
	assert.equal(classify(RULES.movement, 0.7, noulConfidence(0.7)), "review");
	assert.equal(classify(RULES.card_offer, 0.8, 0.7), "flagged", "a weak or empty offer");
	assert.equal(classify(RULES.card_offer, 2.6, 0.9), "none");
	assert.equal(classify(RULES.minute_pacing, 2.5, 0.3), "review");
	assert.equal(noulConfidence(0.5), 0);
	assert.equal(noulConfidence(0.9), 0.8);
});

type Sent = { body: Record<string, any> };
function fakeJev(answer: (name: string, q: any) => unknown) {
	const sent: Sent[] = [];
	const fetch = async (_url: string, init?: RequestInit) => {
		const body = JSON.parse(String(init?.body));
		sent.push({ body });
		const answers = Object.fromEntries(Object.entries<any>(body.questions).map(([n, q]) => [n, answer(n, q)]));
		return new Response(JSON.stringify({ model: "jev-1.13.0", answers, usage: { input_tokens: 300, output_tokens: 10 } }),
			{ status: 200, headers: { "content-type": "application/json" } });
	};
	return { sent, client: new JevClient({ apiKey: "k", fetch, retry: { maxRetries: 0 } }) };
}
const score = (s: number, confidence: number) => ({ type: "score", score: s, confidence, probabilities: {}, legend: {} });

test("a DEAD run's evaluations: three batched requests, classified, unfair death flagged, card offers from recorded Scores", async () => {
	const jev = fakeJev((name) => name === "fairness" ? score(2.6, 0.8) : name === "avoidable" ? { type: "noul", noul: 0.15 }
		: name === "awkward" ? { type: "noul", noul: 0.3 } : score(0.4, 0.9));
	const decisions = [cardDecision(4, 29, 2.8, 0.8), cardDecision(9, 50, 0.7, 0.75)];
	const e = await runEvaluations({ client: jev.client, data: data(deadRun(), { decisions }) });
	assert.equal(jev.sent.length, 3, "death, pacing and movement: one request each");
	assert.equal(e.status, "done");
	const byId = Object.fromEntries(e.results.map((r) => [r.id, r]));
	assert.equal(byId.death_fairness.class, "flagged");
	assert.equal(byId.death_avoidable.class, "flagged");
	assert.equal(byId["minute_pacing:m1"].class, "none");
	assert.equal(byId.movement.class, "none");
	assert.equal(byId["card_offer:4"].class, "none");
	assert.equal(byId["card_offer:9"].class, "flagged");
	const ops = opinionsOf(e);
	assert.deepEqual(ops.map((o) => [o.kind, o.class]), [["card_offer", "flagged"], ["death_fairness", "flagged"]],
		"one entry per finding (the two death questions merge), by run time");
	const death = ops.find((o) => o.kind === "death_fairness")!;
	assert.equal(death.time, 64.5);
	assert.match(death.evidence, /unfairness 2\.6 of 3 \(confidence 0\.8\)/);
	assert.match(death.evidence, /avoidable.*0\.15/);
	assert.equal(e.requests, 3);
	assert.equal(e.input_tokens, 900);
});

test("without Jev the evaluations are skipped with the reason and no request is made", async () => {
	const e = await runEvaluations({ client: null, skip: "no key: key absent in process env", data: data(deadRun()) });
	assert.equal(e.status, "skipped");
	assert.equal(e.reason, "no key: key absent in process env");
	assert.deepEqual(e.results, []);
	assert.deepEqual(opinionsOf(e), []);
});

test("one failing request leaves the other evaluations standing and records why", async () => {
	let n = 0;
	const fetch = async (_url: string, init?: RequestInit) => {
		const body = JSON.parse(String(init?.body));
		if ("fairness" in body.questions) return new Response("{}", { status: 500 });
		n++;
		const answers = Object.fromEntries(Object.entries<any>(body.questions).map(([k, q]) => [k,
			q.type === "noul" ? { type: "noul", noul: 0.9 } : score(2.5, 0.9)]));
		return new Response(JSON.stringify({ model: "jev-1.13.0", answers, usage: {} }), { status: 200 });
	};
	const e = await runEvaluations({ client: new JevClient({ apiKey: "k", fetch, retry: { maxRetries: 0 } }), data: data(deadRun()) });
	assert.equal(n, 2);
	assert.equal(e.status, "partial");
	assert.match(e.errors.join(";"), /death: API error 500/);
	assert.equal(e.results.find((r) => r.id === "movement")?.class, "flagged");
	assert.equal(e.results.find((r) => r.id === "minute_pacing:m1")?.class, "flagged");
});
