// The Jev tactic question (#97) against a mocked fetch (no network): a Choice over the personality's allowed tactics
// in a seeded, recorded order plus a Noul "immediate danger", the personality text first in the state, and the code
// policy: low confidence keeps the current tactic, high danger forces defensive for personalities with `emergency`.
// Card and job requests carry the personality text too, and fall back to the personality's own fallback.
import { test } from "node:test";
import assert from "node:assert/strict";
import { createJevBrain } from "../src/maple/jev_brain.ts";
import { JevClient } from "../src/core/jev_client.ts";
import { loadPersonality } from "../src/maple/personality.ts";
import type { DecideMessage } from "../src/core/protocol.ts";
import { seededShuffle } from "../src/core/shuffle.ts";

type Sent = { body: Record<string, any> };
const json = (status: number, value: unknown) =>
	new Response(JSON.stringify(value), { status, headers: { "content-type": "application/json" } });

/** A fetch answering the tactic Choice with `pick` at `confidence`, the danger Noul with `danger`. */
function jev(pick: string, confidence: number, danger: number) {
	const sent: Sent[] = [];
	const fetch = async (_url: string, init?: RequestInit) => {
		const body = JSON.parse(String(init?.body));
		sent.push({ body });
		const answers: Record<string, unknown> = {};
		for (const [name, q] of Object.entries<any>(body.questions)) {
			if (q.type === "noul") answers[name] = { type: "noul", noul: danger };
			else if (q.type === "choice") {
				const labels = Object.keys(q.criteria);
				const choice = labels.includes(pick) ? pick : labels[0];
				answers[name] = { type: "choice", choice, confidence,
					probabilities: Object.fromEntries(labels.map((l) => [l, l === choice ? 0.6 : 0.4 / (labels.length - 1)])) };
			} else if (q.type === "score") {
				answers[name] = { type: "score", score: 2, confidence: 0.5, probabilities: { 0: 0, 1: 0, 2: 1, 3: 0 } };
			}
		}
		return json(200, { model: "jev-1.13.0", answers, usage: { input_tokens: 400, output_tokens: 30 } });
	};
	return { sent, client: new JevClient({ apiKey: "test-key", fetch, retry: { maxRetries: 0 } }) };
}

const P = (name: string) => loadPersonality(name).personality!;
const DESC: Record<string, string> = { kite: "Kite like the standard bot.", aggressive: "Close in and fight.",
	defensive: "Keep a wide berth.", explore: "Walk toward unvisited platforms.", collect: "Sweep up drops.", hold: "Stand still." };

function tacticDecide(allowed: string[], current: string, buckets: Record<string, unknown> = {}, id = 6): DecideMessage {
	return { v: 1, type: "decide", id, kind: "tactic", tick: 1440, time: 24,
		options: allowed.map((t) => ({ id: t, name: t, desc: DESC[t] })), baseline: { sensible: allowed.includes("kite") ? "kite" : allowed[0] },
		situation: { level: 6, hp: 30, max_hp: 100,
			buckets: { hp: "low", mp: "ok", mobs_near: "crowd", mobs_near_step: 2, boss: "none", potions_hp: "few",
				potions_mp: "plenty", drops_near: "some", drops_above: "none", phase: "early", platform: 3, recent_hits: "some", ...buckets },
			tactic: { current, trigger: "hp_low", held_s: 12.5, switches: 2,
				recent: [{ time: 4, from: "kite", to: "aggressive", trigger: "start" }, { time: 11.5, from: "aggressive", to: "kite", trigger: "crowd" }] } } };
}

test("a tactic decision asks one request: a Choice over the allowed tactics in a seeded order plus a danger Noul", async () => {
	const j = jev("kite", 0.8, 0.2);
	const brain = createJevBrain({ client: j.client, seed: 2026, profile: P("aggressive") });
	const d = tacticDecide(["aggressive", "kite"], "kite");
	const a = await brain.decide(d);
	assert.equal(j.sent.length, 1);
	const { body } = j.sent[0];
	const qs = Object.values<any>(body.questions);
	const choice = qs.find((q) => q.type === "choice");
	const noul = qs.find((q) => q.type === "noul");
	assert.match(choice.instructions, /tactic/i);
	assert.deepEqual(Object.keys(choice.criteria), seededShuffle(["aggressive", "kite"], 2026, 6), "allowed tactics only, seeded order");
	assert.equal(choice.criteria.aggressive, "Close in and fight.", "each tactic is described by its in-game text");
	assert.match(JSON.stringify(noul), /immediate danger of dying/i);
	// state: the personality first, then the bucketed situation and the tactic history, no raw pools
	assert.equal(Object.keys(body.state)[0], "player");
	assert.match(body.state.player, /reckless/i);
	assert.match(body.state.player, /Goals:/);
	assert.equal(body.state.situation.HP, "low");
	assert.equal(body.state.situation["monsters near"], "crowd");
	assert.equal(body.state["current tactic"], "kite");
	assert.match(body.state["current tactic held for"], /5 to 20 seconds/);
	assert.match(body.state["why this decision now"], /HP just fell to low/);
	assert.deepEqual(body.state["recent tactic switches"], ["kite -> aggressive (round start)", "aggressive -> kite (monsters crowded in)"]);
	assert.ok(!JSON.stringify(body.state).includes("max_hp"));
	assert.equal(a.answer, "kite");
	assert.equal(a.source, "jev");
	assert.equal(a.confidence, 0.8);
	assert.equal(a.extra?.danger, 0.2);
	assert.equal(a.extra?.gate, "none");
	assert.deepEqual(a.extra?.presented_order, seededShuffle(["aggressive", "kite"], 2026, 6));
});

test("options the personality does not allow are never offered to Jev", async () => {
	const j = jev("kite", 0.8, 0.1);
	await createJevBrain({ client: j.client, seed: 1, profile: P("exploratory") })
		.decide(tacticDecide(["kite", "aggressive", "defensive", "explore", "collect", "hold"], "explore"));
	const choice = Object.values<any>(j.sent[0].body.questions).find((q) => q.type === "choice");
	assert.deepEqual(Object.keys(choice.criteria).sort(), ["collect", "explore", "kite"]);
});

test("a tactic answer below the confidence threshold keeps the current tactic", async () => {
	const j = jev("aggressive", 0.3, 0.1);
	const a = await createJevBrain({ client: j.client, seed: 1, profile: P("aggressive") }).decide(tacticDecide(["aggressive", "kite"], "kite"));
	assert.equal(a.answer, "kite");
	assert.equal(a.source, "jev");
	assert.equal(a.extra?.jev_choice, "aggressive");
	assert.match(String(a.extra?.gate), /low confidence 0\.3 < 0\.35.*kept kite/);
	const sure = await createJevBrain({ client: jev("aggressive", 0.36, 0.1).client, seed: 1, profile: P("aggressive") })
		.decide(tacticDecide(["aggressive", "kite"], "kite"));
	assert.equal(sure.answer, "aggressive", "at or above the threshold the top choice is applied");
});

test("high danger forces defensive only for personalities with emergency", async () => {
	const a = await createJevBrain({ client: jev("kite", 0.9, 0.75).client, seed: 1, profile: P("defensive") })
		.decide(tacticDecide(["defensive", "kite"], "kite"));
	assert.equal(a.answer, "defensive");
	assert.equal(a.extra?.jev_choice, "kite");
	assert.match(String(a.extra?.gate), /danger 0\.75 > 0\.7.*defensive/);
	const calm = await createJevBrain({ client: jev("kite", 0.9, 0.65).client, seed: 1, profile: P("defensive") })
		.decide(tacticDecide(["defensive", "kite"], "kite"));
	assert.equal(calm.answer, "kite", "danger at or below 0.7 does not force");
	const reckless = await createJevBrain({ client: jev("aggressive", 0.9, 0.95).client, seed: 1, profile: P("aggressive") })
		.decide(tacticDecide(["aggressive", "kite"], "kite"));
	assert.equal(reckless.answer, "aggressive", "no emergency flag: danger is recorded, not acted on");
	assert.equal(reckless.extra?.danger, 0.95);
});

test("a failed tactic request uses the personality's fallback rule table", async () => {
	const fetch = async () => json(500, { error: "boom" });
	const a = await createJevBrain({ client: new JevClient({ apiKey: "k", fetch, retry: { maxRetries: 0 } }), seed: 1,
		profile: P("defensive") }).decide(tacticDecide(["defensive", "kite"], "kite"));
	assert.equal(a.answer, "defensive", "defensive's hurt_backs_off rule");
	assert.equal(a.source, "fallback:tactic-rules");
	assert.match(String(a.reason), /500/);
});

test("card requests carry the personality text, and failures use the personality's card policy", async () => {
	const card: DecideMessage = { v: 1, type: "decide", id: 2, kind: "card", situation: { level: 3 }, baseline: { sensible: "a" },
		options: [{ id: "a", name: "Recovery", kind: "skill_rank", stat: "hp", role: "support", sensible_score: 42 },
			{ id: "b", name: "Bolt Power", kind: "skill_mod", stat: "damage", role: "attack", sensible_score: 76 }] };
	const j = jev("a", 0.7, 0);
	await createJevBrain({ client: j.client, seed: 1, profile: P("completionist") }).decide(card);
	assert.match(j.sent[0].body.state.player, /thorough/i);
	const fetch = async () => json(500, {});
	const a = await createJevBrain({ client: new JevClient({ apiKey: "k", fetch, retry: { maxRetries: 0 } }), seed: 1,
		profile: P("aggressive") }).decide(card);
	assert.equal(a.answer, "b");
	assert.equal(a.source, "fallback:aggressive");
});
