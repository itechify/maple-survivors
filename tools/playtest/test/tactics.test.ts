// The tactic layer on the Node side (#95): the deterministic fallback rule table answering `tactic` decides from the
// situation buckets, and the report's tactic section. No Godot, no network.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { tacticFor, SENSIBLE_TACTIC_RULES } from "../src/maple/tactic_rules.ts";
import type { Buckets } from "../src/maple/situation.ts";
import { sensibleBrain } from "../src/maple/fallback.ts";
import { runPlaytest } from "../src/maple/run.ts";
import type { DecideMessage } from "../src/core/protocol.ts";

const ALL = ["kite", "aggressive", "defensive", "explore", "collect", "hold"];
const CALM: Buckets = { hp: "full", mp: "full", mobs_near: "none", mobs_near_step: 0, boss: "none", potions_hp: "few",
	potions_mp: "few", drops_near: "none", drops_above: "none", phase: "early", platform: 0, recent_hits: "none" };

function tacticDecide(buckets: Partial<Buckets>, options: string[] = ALL, current = "kite"): DecideMessage {
	return { v: 1, type: "decide", id: 7, kind: "tactic", tick: 480, time: 8,
		situation: { level: 5, buckets: { ...CALM, ...buckets }, tactic: { current, trigger: "checkpoint", held_s: 8, switches: 0 } },
		options: options.map((id) => ({ id, name: id })), baseline: { sensible: "kite" } };
}

const answer = (b: Partial<Buckets>, options?: string[]) => tacticFor(tacticDecide(b, options)).answer;

test("critical HP plays defensive, whatever else is going on", () => {
	assert.equal(answer({ hp: "critical", mobs_near: "crowd", mobs_near_step: 2 }), "defensive");
	assert.equal(answer({ hp: "critical", boss: "attacking", phase: "boss" }), "defensive");
});

test("bosses and low HP are left to the kiting bot, except low HP in a crowd", () => {
	assert.equal(answer({ boss: "attacking", phase: "boss" }), "kite");
	assert.equal(answer({ boss: "present", phase: "boss", drops_near: "many" }), "kite");
	assert.equal(answer({ hp: "low" }), "kite");
	assert.equal(answer({ hp: "low", mobs_near: "crowd", mobs_near_step: 2 }), "defensive");
	assert.equal(answer({ mobs_near: "swarm", mobs_near_step: 3 }), "kite");
});

test("a quiet map is swept or explored, a few mobs at good health are fought", () => {
	assert.equal(answer({ drops_near: "some" }), "collect");
	assert.equal(answer({ drops_above: "many" }), "collect");
	assert.equal(answer({}), "explore");
	assert.equal(answer({ mobs_near: "few", mobs_near_step: 1 }), "aggressive");
	assert.equal(answer({ mobs_near: "few", mobs_near_step: 1, recent_hits: "some" }), "kite", "getting hit: back to kiting");
	assert.equal(answer({ mobs_near: "crowd", mobs_near_step: 2 }), "kite");
});

test("only offered tactics are answered; nothing applicable falls back to the baseline", () => {
	assert.equal(answer({ drops_near: "some" }, ["kite", "defensive"]), "kite");
	assert.equal(answer({ hp: "critical" }, ["kite", "hold"]), "kite");
	const noBuckets = tacticFor({ ...tacticDecide({}), situation: { level: 5 } });
	assert.equal(noBuckets.answer, "kite");
	assert.equal(noBuckets.rule, null);
	for (const rule of SENSIBLE_TACTIC_RULES) assert.ok(ALL.includes(rule.then), `rule ${rule.id} names a real tactic`);
});

test("the fallback brain answers tactic decides from the rule table and names the rule", async () => {
	const a = await sensibleBrain.decide(tacticDecide({ drops_near: "some" }));
	assert.equal(a.answer, "collect");
	assert.equal(a.source, "fallback:tactic-rules");
	assert.equal(a.confidence, null);
	assert.match(a.reason ?? "", /rule .*drops/);
	const card = await sensibleBrain.decide({ v: 1, type: "decide", id: 1, kind: "card",
		options: [{ id: "a" }, { id: "b" }], baseline: { sensible: "b" } });
	assert.equal(card.answer, "b", "card decides still take the sensible baseline");
	assert.equal(card.source, "fallback:sensible");
});

test("a run records tactic decisions and the report shows tactic shares and switches", async () => {
	const out = path.join(fs.mkdtempSync(path.join(os.tmpdir(), "playtest-tactics-")), "run");
	const FAKE = path.join(import.meta.dirname, "..", "fixtures", "fake_driver.ts");
	const r = await runPlaytest({ stage: "henesys_hg1", seed: 2026, minutes: 4, personality: "sensible", brain: "fallback",
		livenessS: 10, out, env: {}, launch: { command: process.execPath, args: [FAKE, "--mode=tactics"] } });
	assert.equal(r.exitCode, 0);
	const decisions = fs.readFileSync(path.join(out, "decisions.jsonl"), "utf8").trim().split("\n").map((l) => JSON.parse(l));
	assert.deepEqual(decisions.map((d) => [d.kind, d.answer, d.source]), [
		["tactic", "explore", "fallback:tactic-rules"],
		["tactic", "collect", "fallback:tactic-rules"],
		["tactic", "defensive", "fallback:tactic-rules"],
	]);
	const md = fs.readFileSync(path.join(out, "report.md"), "utf8");
	assert.match(md, /## Tactics/);
	assert.match(md, /\| explore \| 96(\.0)? \| 40(\.0)?% \|/, "seconds and share per tactic");
	assert.match(md, /switches: 3/i);
	assert.match(md, /0:08 .*explore -> collect.*checkpoint/, "the switch log names time, tactics and trigger");
	const json = JSON.parse(fs.readFileSync(path.join(out, "report.json"), "utf8"));
	assert.equal(json.tactics.switches, 3);
	assert.equal(json.tactics.shares.explore, 0.4);
	assert.equal(json.tactics.by_source["fallback:tactic-rules"], 3);
});
