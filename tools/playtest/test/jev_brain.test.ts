// The Jev brain for card and job decisions (maple/jev_brain.ts over core/jev_client.ts), against a mocked fetch: no
// network. Covers the request shapes (small named state, bucketed situation, seeded and recorded option order), acting
// on the top choice, and the deterministic fallback on 401 / 500 / timeout / the request cap.
import { test } from "node:test";
import assert from "node:assert/strict";
import { createJevBrain, situationBuckets } from "../src/maple/jev_brain.ts";
import { JevClient } from "../src/core/jev_client.ts";
import type { DecideMessage } from "../src/core/protocol.ts";
import { seededShuffle } from "../src/core/shuffle.ts";

type Sent = { url: string; body: Record<string, any> };
type Reply = (body: Record<string, any>) => Response | Promise<Response>;

/** A fetch that records each request and answers with `reply` (the SDK's only transport). */
function fakeFetch(reply: Reply) {
	const sent: Sent[] = [];
	const fetch = async (url: string, init?: RequestInit) => {
		const body = JSON.parse(String(init?.body));
		sent.push({ url, body });
		return reply(body);
	};
	return { sent, fetch };
}

const json = (status: number, value: unknown) =>
	new Response(JSON.stringify(value), { status, headers: { "content-type": "application/json" } });

/** A 200 answering every choice with `pick(labels)` and every score with level 2. */
const answering = (pick: (labels: string[]) => string, model = "jev-1.13.0"): Reply => (body) => {
	const answers: Record<string, unknown> = {};
	for (const [name, q] of Object.entries<any>(body.questions)) {
		if (q.type === "choice") {
			const labels = Object.keys(q.criteria);
			const choice = pick(labels);
			answers[name] = { type: "choice", choice, confidence: 0.6,
				probabilities: Object.fromEntries(labels.map((l) => [l, l === choice ? 0.7 : 0.3 / (labels.length - 1)])) };
		} else if (q.type === "score") {
			answers[name] = { type: "score", score: 2.1, confidence: 0.8,
				legend: Object.fromEntries(q.criteria.map((c: string, i: number) => [String(i), c])),
				probabilities: Object.fromEntries(q.criteria.map((_: string, i: number) => [String(i), i === 2 ? 0.9 : 0.1 / (q.criteria.length - 1)])) };
		}
	}
	return json(200, { model, answers, usage: { input_tokens: 500, output_tokens: 20 } });
};

const client = (fetch: (url: string, init?: RequestInit) => Promise<Response>, extra: Partial<ConstructorParameters<typeof JevClient>[0]> = {}) =>
	new JevClient({ apiKey: "test-key", model: "jev-latest", maxRequests: 400, fetch, retry: { maxRetries: 0 }, ...extra });

const CARD: DecideMessage = {
	v: 1, type: "decide", id: 3, kind: "card", tick: 5819, time: 96.983,
	situation: { state: "CHOOSING_UPGRADE", time: 96.983, level: 4, job_id: 0, job: "Beginner", hp: 20, max_hp: 92,
		mp: 35, max_mp: 35, kills: 20, alive: 4, skills: ["three_snails:2"], advancement: false, bonus: false,
		owned_skills: [{ key: "three_snails", name: "Three Snails", rank: 2, max_rank: 20 }],
		bosses_alive: 0, bosses_defeated: 0, bosses_scheduled: 3 },
	options: [
		{ id: "three_snails_pierce", name: "Piercing Shells", desc: "Shells pass through +2 more monster.", kind: "skill_mod",
			rank: 2, rank_before: 0, max_rank: 3, skill: "three_snails", skill_name: "Three Snails", tier: "rare" },
		{ id: "magic_claw_new", name: "Magic Claw", desc: "Attacks with two magic claws.", kind: "skill_new", rank: 1,
			rank_before: 0, max_rank: 20, skill: "magic_claw", skill_name: "Magic Claw", skill_level: 0, skill_level_next: 1,
			skill_level_max: 20 },
		{ id: "three_snails_count", name: "Additional Shell", desc: "Three Snails throws +1 shell.", kind: "skill_mod",
			rank: 3, rank_before: 2, max_rank: 4, skill: "three_snails", skill_name: "Three Snails", tier: "normal" },
	],
	baseline: { sensible: "three_snails_count" },
};

const JOB: DecideMessage = {
	v: 1, type: "decide", id: 9, kind: "job", tick: 30000, time: 500,
	situation: { state: "CHOOSING_JOB", time: 500, level: 30, job_id: 200, job: "Magician", hp: 300, max_hp: 300, mp: 50,
		max_mp: 500, owned_skills: [], bosses_alive: 1, bosses_defeated: 1, bosses_scheduled: 3 },
	options: [
		{ id: "210", name: "Wizard (Fire, Poison)", desc: "2nd-job Magician branch; skills: Fire Arrow, Poison Breath" },
		{ id: "220", name: "Wizard (Ice, Lightning)", desc: "2nd-job Magician branch; skills: Cold Beam, Thunder Bolt" },
		{ id: "230", name: "Cleric", desc: "2nd-job Magician branch; skills: Heal, Holy Arrow" },
		{ id: "not_now", name: "Not now" },
	],
	baseline: { sensible: "220" },
};

test("a card decision asks one request: a Choice over the card ids in a seeded order plus a meaningfulness Score", async () => {
	const f = fakeFetch(answering((labels) => labels[labels.length - 1]));
	const brain = createJevBrain({ client: client(f.fetch), seed: 2026 });
	const a = await brain.decide(CARD);
	assert.equal(f.sent.length, 1, "independent questions share one request");
	const { body } = f.sent[0];
	assert.match(f.sent[0].url, /\/v1\/systemone$/);
	assert.equal(body.model, "jev-latest");
	const qs = Object.values<any>(body.questions);
	const choice = qs.find((q) => q.type === "choice");
	const score = qs.find((q) => q.type === "score");
	assert.match(choice.instructions, /Which offered card would this player take now/);
	assert.ok(score && score.criteria.length >= 3, "a meaningfulness Score with ordered levels");
	const presented = Object.keys(choice.criteria);
	const screen = CARD.options.map((o) => o.id);
	assert.deepEqual([...presented].sort(), [...screen].sort(), "labels are the offered card ids");
	assert.deepEqual(presented, seededShuffle(screen, 2026, 3), "presented in the seeded (run seed, decision id) shuffle");
	assert.match(choice.criteria.magic_claw_new, /Magic Claw/);
	assert.match(choice.criteria.magic_claw_new, /Lv\. 1 of 20|level 1 of 20/i);
	assert.match(choice.criteria.three_snails_count, /3 of 4/);
	// state: personality first, then character, bucketed situation and the offer; no raw HP arithmetic
	const keys = Object.keys(body.state);
	assert.equal(keys[0], "player");
	assert.match(String(body.state.player), /sensible/i);
	assert.equal(body.state.character.level, 4);
	assert.equal(body.state.character.job, "Beginner");
	assert.deepEqual(body.state.character.skills, [{ name: "Three Snails", rank: "2 of 20" }]);
	assert.equal(body.state.situation.hp, "low");
	assert.equal(body.state.situation.mp, "full");
	assert.equal(body.state.situation["boss present"], "no");
	assert.equal(body.state.situation["run phase"], "opening minutes");
	assert.ok(!JSON.stringify(body.state).includes("\"max_hp\""), "no raw pools for Jev to divide");
	assert.deepEqual(body.state["offered cards"].map((c: any) => c.id), presented, "the state lists the cards in the presented order");
	// answer: the top choice, with confidence, probabilities and both orders recorded
	assert.equal(a.answer, presented[presented.length - 1]);
	assert.equal(a.source, "jev");
	assert.equal(a.confidence, 0.6);
	assert.deepEqual(a.extra?.presented_order, presented);
	assert.deepEqual(a.extra?.screen_order, screen);
	assert.equal((a.extra?.probabilities as Record<string, number>)[a.answer], 0.7);
	assert.equal((a.extra?.meaningfulness as { score: number }).score, 2.1);
	assert.equal(a.extra?.model, "jev-1.13.0");
});

test("the same seed and decision give the same request; another decision id reorders", async () => {
	const f1 = fakeFetch(answering((l) => l[0]));
	const f2 = fakeFetch(answering((l) => l[0]));
	await createJevBrain({ client: client(f1.fetch), seed: 7 }).decide(CARD);
	await createJevBrain({ client: client(f2.fetch), seed: 7 }).decide(CARD);
	assert.deepEqual(f1.sent[0].body, f2.sent[0].body);
	const orders = new Set<string>();
	for (let id = 1; id <= 12; id++) {
		const f = fakeFetch(answering((l) => l[0]));
		await createJevBrain({ client: client(f.fetch), seed: 7 }).decide({ ...CARD, id });
		orders.add(Object.keys(Object.values<any>(f.sent[0].body.questions).find((q) => q.type === "choice").criteria).join());
	}
	assert.ok(orders.size > 1, "the order varies across decisions");
});

test("a job decision is a Choice over the branches (name and description) and not now", async () => {
	const f = fakeFetch(answering((labels) => labels.find((l) => l.endsWith("230")) ?? labels[0]));
	const a = await createJevBrain({ client: client(f.fetch), seed: 2026 }).decide(JOB);
	const { body } = f.sent[0];
	const choice = Object.values<any>(body.questions).find((q) => q.type === "choice");
	assert.match(choice.instructions, /job/i);
	const labels = Object.keys(choice.criteria);
	assert.equal(labels.length, 4);
	assert.ok(labels.some((l) => /not.?now/i.test(l)));
	const cleric = labels.find((l) => l.endsWith("230"))!;
	assert.match(choice.criteria[cleric], /Cleric/);
	assert.match(choice.criteria[cleric], /Heal/);
	assert.equal(body.state.situation["boss present"], "yes");
	assert.equal(a.answer, "230", "the label maps back to the protocol's job id");
	assert.equal(a.source, "jev");
	assert.deepEqual([...(a.extra?.presented_order as string[])].sort(), ["210", "220", "230", "not_now"]);
});

const fallbackCases: Array<[string, Reply | "timeout", RegExp]> = [
	["401", () => json(401, { error: "bad key" }), /401/],
	["500", () => json(500, { error: "boom" }), /500/],
	["timeout", "timeout", /timed? ?out/i],
];
for (const [name, reply, reason] of fallbackCases) {
	test(`a ${name} answers with the deterministic fallback and records why`, async () => {
		const fetch = reply === "timeout"
			? (_url: string, init?: RequestInit) => new Promise<Response>((_, reject) =>
				init?.signal?.addEventListener("abort", () => reject(init.signal!.reason ?? new Error("aborted"))))
			: fakeFetch(reply).fetch;
		const jev = client(fetch, { timeoutMs: 50 });
		const a = await createJevBrain({ client: jev, seed: 2026 }).decide(CARD);
		assert.equal(a.answer, "three_snails_count", "the sensible baseline");
		assert.equal(a.source, "fallback:sensible");
		assert.match(String(a.reason), reason);
		assert.ok(!String(a.reason).includes("test-key"), "the key never appears in a reason");
		assert.equal(jev.stats().errors, 1);
	});
}

test("after an auth failure Jev is not asked again in this run", async () => {
	const f = fakeFetch(() => json(401, { error: "bad key" }));
	const brain = createJevBrain({ client: client(f.fetch), seed: 2026 });
	await brain.decide(CARD);
	const second = await brain.decide({ ...CARD, id: 4 });
	assert.equal(f.sent.length, 1);
	assert.equal(second.source, "fallback:sensible");
	assert.match(String(second.reason), /401/);
});

test("the request cap sends later decisions to the fallback", async () => {
	const f = fakeFetch(answering((l) => l[0]));
	const jev = client(f.fetch, { maxRequests: 2 });
	const brain = createJevBrain({ client: jev, seed: 2026 });
	const answers = [];
	for (let id = 1; id <= 4; id++) answers.push(await brain.decide({ ...CARD, id }));
	assert.equal(f.sent.length, 2);
	assert.deepEqual(answers.map((a) => a.source), ["jev", "jev", "fallback:sensible", "fallback:sensible"]);
	assert.match(String(answers[3].reason), /cap \(2\)/);
});

test("the client sums tokens and remembers the versioned model ids", async () => {
	const f = fakeFetch(answering((l) => l[0], "jev-1.13.0"));
	const jev = client(f.fetch);
	const brain = createJevBrain({ client: jev, seed: 2026 });
	await brain.decide(CARD);
	await brain.decide(JOB);
	assert.deepEqual(jev.stats(), { requests: 2, errors: 0, input_tokens: 1000, output_tokens: 40, models: ["jev-1.13.0"],
		max_requests: 400, model_requested: "jev-latest", disabled: null });
});

test("a decision kind without a Jev question uses the fallback without a request", async () => {
	const f = fakeFetch(answering((l) => l[0]));
	const a = await createJevBrain({ client: client(f.fetch), seed: 2026 }).decide({ ...CARD, kind: "tactic",
		options: [{ id: "kite" }, { id: "hold" }], baseline: { sensible: "kite" } });
	assert.equal(f.sent.length, 0);
	assert.equal(a.answer, "kite");
	assert.match(String(a.reason), /tactic/);
});

test("situation buckets: HP/MP named levels, run phase from time and boss progress, boss present", () => {
	const b = (s: Record<string, unknown>) => situationBuckets({ hp: 10, max_hp: 100, mp: 50, max_mp: 100, time: 400,
		bosses_alive: 0, bosses_defeated: 0, bosses_scheduled: 3, ...s });
	assert.deepEqual(b({}), { hp: "critical", mp: "medium", "run phase": "early, before the first boss", "boss present": "no" });
	assert.equal(b({ hp: 100 }).hp, "full");
	assert.equal(b({ hp: 70 }).hp, "high");
	assert.equal(b({ hp: 20 }).hp, "low");
	assert.equal(b({ time: 30 })["run phase"], "opening minutes");
	assert.deepEqual([b({ bosses_alive: 1 })["run phase"], b({ bosses_alive: 1 })["boss present"]], ["boss fight", "yes"]);
	assert.equal(b({ bosses_defeated: 1 })["run phase"], "middle, between bosses");
	assert.equal(b({ bosses_defeated: 2 })["run phase"], "late, the final boss is next");
	assert.equal(b({ bosses_defeated: 3 })["run phase"], "after the final boss");
});
