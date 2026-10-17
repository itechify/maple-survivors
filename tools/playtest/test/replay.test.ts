// The replay brain and fingerprint comparison (core/replay.ts): answers decisions from a recording, detects a wrong
// kind, different options, extra or missing decisions, applied answers that differ, and fingerprint fields that differ.
import { test } from "node:test";
import assert from "node:assert/strict";
import { createReplayBrain, compareFingerprints } from "../src/core/replay.ts";
import type { DecideMessage } from "../src/core/protocol.ts";
import type { DecisionRecord } from "../src/core/session.ts";

const rec = (id: number, kind: string, options: string[], answer: string, extra: Record<string, unknown> = {}): DecisionRecord =>
	({ id, kind, tick: id * 60, time: id, options, baseline: options[0], answer, source: "jev", confidence: 0.5,
		latency_ms: 1, ...extra });
const decide = (id: number, kind: string, options: string[], tick = id * 60): DecideMessage =>
	({ v: 1, type: "decide", id, kind, tick, time: tick / 60, options: options.map((o) => ({ id: o })),
		baseline: { sensible: options[0] } });

const RECORDING = [
	rec(1, "tactic", ["kite", "explore"], "explore", { presented_order: ["explore", "kite"] }),
	rec(2, "card", ["a", "b", "c"], "c"),
	rec(3, "job", ["200", "not_now"], "200"),
];

test("a matching replay answers every decision from the recording and reports no divergence", async () => {
	const brain = createReplayBrain(RECORDING);
	const answers = [];
	for (const r of RECORDING) answers.push(await brain.decide(decide(r.id, r.kind, r.options)));
	assert.deepEqual(answers.map((a) => [a.answer, a.source]), [["explore", "replay"], ["c", "replay"], ["200", "replay"]]);
	assert.deepEqual(answers[0].extra?.presented_order, ["explore", "kite"], "the recorded presented order is reused");
	assert.deepEqual(brain.finish(RECORDING), []);
});

test("a decision of another kind is a divergence naming that decision", async () => {
	const brain = createReplayBrain(RECORDING);
	await brain.decide(decide(1, "tactic", ["kite", "explore"]));
	const a = await brain.decide(decide(2, "job", ["a", "b", "c"]));
	assert.equal(a.answer, "a", "after a divergence the replay answers the baseline so the round can end");
	const d = brain.finish(RECORDING);
	assert.equal(d[0].decision, 2);
	assert.match(d[0].message, /decision 2: kind job, recorded card/);
});

test("different options and the same options in another order are divergences", async () => {
	const other = createReplayBrain(RECORDING);
	await other.decide(decide(1, "tactic", ["kite", "hold"]));
	assert.match(other.finish(RECORDING)[0].message, /decision 1: options \[kite, hold\], recorded \[kite, explore\]/);
	const order = createReplayBrain(RECORDING);
	await order.decide(decide(1, "tactic", ["explore", "kite"]));
	assert.match(order.finish(RECORDING)[0].message, /same options in another order/);
});

test("a decision at another tick is a divergence", async () => {
	const brain = createReplayBrain(RECORDING);
	await brain.decide(decide(1, "tactic", ["kite", "explore"], 61));
	assert.match(brain.finish(RECORDING)[0].message, /decision 1: tick 61, recorded 60/);
});

test("an extra decision beyond the recording and a missing one at the end are divergences", async () => {
	const extra = createReplayBrain(RECORDING.slice(0, 1));
	await extra.decide(decide(1, "tactic", ["kite", "explore"]));
	const a = await extra.decide(decide(2, "card", ["a", "b"]));
	assert.equal(a.answer, "a");
	assert.match(extra.finish(RECORDING.slice(0, 1))[0].message, /decision 2 \(card\) is not in the recording \(1 decisions\)/);
	const missing = createReplayBrain(RECORDING);
	await missing.decide(decide(1, "tactic", ["kite", "explore"]));
	assert.match(missing.finish(RECORDING.slice(0, 1))[0].message, /the replay made 1 decisions, the recording has 3/);
});

test("an applied answer that differs from the recording (the driver rejected it) is a divergence", async () => {
	const tampered = [RECORDING[0], { ...RECORDING[1], answer: "zzz" }, RECORDING[2]];
	const brain = createReplayBrain(tampered);
	for (const r of tampered) await brain.decide(decide(r.id, r.kind, r.options));
	const applied = [RECORDING[0], { ...RECORDING[1], answer: "a", source: "baseline",
		fallback_reason: "answer \"zzz\" is not an offered option" }, RECORDING[2]];
	const d = brain.finish(applied);
	assert.equal(d.length, 1);
	assert.match(d[0].message, /decision 2: the driver applied a, recorded zzz \(answer "zzz" is not an offered option\)/);
});

test("fingerprints compare field by field; the first differing field is named first", () => {
	const fp = { ticks: 10800, state: "TIMEOUT", time: 180, level: 11, job: 200, kills: 42, cards_taken: ["0:a", "0:b"],
		answers_sha256: "aa", timeline_sha256: "tt" };
	assert.deepEqual(compareFingerprints(fp, { ...fp }), []);
	assert.deepEqual(compareFingerprints({ ...fp, time: 180.0 }, { ...fp, time: 180 }), [], "180.0 and 180 are equal");
	const diff = compareFingerprints(fp, { ...fp, kills: 40, answers_sha256: "bb", cards_taken: ["0:a", "0:c"] });
	assert.deepEqual(diff.map((d) => d.field), ["kills", "cards_taken", "answers_sha256"]);
	assert.match(diff[0].message, /fingerprint\.kills: replay 40, recorded 42/);
	assert.deepEqual(compareFingerprints(fp, { ...fp, extra_field: 1 }).map((d) => d.field), ["extra_field"]);
});
