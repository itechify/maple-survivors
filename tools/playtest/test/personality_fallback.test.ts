// The personality fallback brain (#97): card picks by the personality's card policy (sensible, seeded random,
// weighted over kind / stat / role), job preferences, and the tactic rule table with the personality's overrides.
// Constructed offers; no Godot, no network.
import { test } from "node:test";
import assert from "node:assert/strict";
import { createFallbackBrain } from "../src/maple/personality_fallback.ts";
import { loadPersonality } from "../src/maple/personality.ts";
import type { DecideMessage, Option } from "../src/core/protocol.ts";

const P = (name: string) => loadPersonality(name).personality!;

/** Card options as card_decision.gd sends them: kind, the BotInput.card_score (`sensible_score`), `stat` and `role`. */
const DAMAGE: Option = { id: "energy_bolt_damage", name: "Bolt Power", kind: "skill_mod", stat: "damage", role: "attack",
	sensible_score: 76 };
const RECOVERY: Option = { id: "recovery_rank", name: "Recovery", kind: "skill_rank", stat: "hp", role: "support",
	sensible_score: 42 };
const NEW_SKILL: Option = { id: "magic_guard_new", name: "Magic Guard", kind: "skill_new", stat: "mp_guard", role: "support",
	sensible_score: 50 };
const COUNT: Option = { id: "energy_bolt_count", name: "Extra Bolt", kind: "skill_mod", stat: "count", role: "attack",
	sensible_score: 87 };
const RANK: Option = { id: "energy_bolt_rank", name: "Energy Bolt", kind: "skill_rank", stat: "", role: "attack",
	sensible_score: 74 };

function cardDecide(options: Option[], id = 4, sensible = options[0].id): DecideMessage {
	return { v: 1, type: "decide", id, kind: "card", options, baseline: { sensible }, situation: { level: 12 } };
}

test("aggressive takes the damage card, defensive the HP card, completionist the new skill", async () => {
	const offer = [RECOVERY, NEW_SKILL, DAMAGE];
	const pick = async (name: string) => (await createFallbackBrain(P(name), 2026).decide(cardDecide(offer, 4, RANK.id))).answer;
	assert.equal(await pick("aggressive"), "energy_bolt_damage");
	assert.equal(await pick("defensive"), "recovery_rank");
	assert.equal(await pick("completionist"), "magic_guard_new");
});

test("weighted picks name the policy and their scores", async () => {
	const a = await createFallbackBrain(P("aggressive"), 2026).decide(cardDecide([RECOVERY, DAMAGE]));
	assert.equal(a.source, "fallback:aggressive");
	assert.equal(a.confidence, null);
	assert.match(a.reason ?? "", /weighted/);
	const scores = a.extra?.card_scores as Record<string, number>;
	assert.ok(scores.energy_bolt_damage > scores.recovery_rank);
});

test("sensible takes the driver's BotInput baseline", async () => {
	const a = await createFallbackBrain(P("sensible"), 2026).decide(cardDecide([DAMAGE, COUNT, RECOVERY], 4, "recovery_rank"));
	assert.equal(a.answer, "recovery_rank");
	assert.equal(a.source, "fallback:sensible");
});

test("the careless player's random card is seeded by run seed and decision id", async () => {
	const offer = [DAMAGE, COUNT, RECOVERY, NEW_SKILL, RANK];
	const picks = async (seed: number) => {
		const brain = createFallbackBrain(P("inexperienced"), seed);
		const out: string[] = [];
		for (let id = 1; id <= 12; id++) out.push((await brain.decide(cardDecide(offer, id))).answer);
		return out;
	};
	const a = await picks(2026);
	assert.deepEqual(await picks(2026), a, "same seed, same picks");
	assert.ok(new Set(a).size >= 3, `picks vary across decisions: ${a}`);
	assert.notDeepEqual(await picks(7), a, "another seed picks differently");
});

test("job preferences take the first offered preferred branch, else the baseline", async () => {
	const job = (ids: string[], sensible: string): DecideMessage => ({ v: 1, type: "decide", id: 9, kind: "job",
		options: [...ids, "not_now"].map((id) => ({ id })), baseline: { sensible } });
	const defensive = createFallbackBrain(P("defensive"), 1);
	assert.equal((await defensive.decide(job(["210", "220", "230"], "220"))).answer, "230");
	assert.equal((await defensive.decide(job(["200"], "200"))).answer, "200", "no preferred branch offered: baseline");
	assert.equal((await createFallbackBrain(P("sensible"), 1).decide(job(["210", "220", "230"], "220"))).answer, "220");
});

const CALM = { hp: "full", mp: "full", mobs_near: "none", mobs_near_step: 0, boss: "none", potions_hp: "few",
	potions_mp: "few", drops_near: "none", drops_above: "none", phase: "early", platform: 0, recent_hits: "none" };
function tacticDecide(allowed: string[], buckets: Record<string, unknown> = {}): DecideMessage {
	return { v: 1, type: "decide", id: 5, kind: "tactic", options: allowed.map((id) => ({ id })),
		baseline: { sensible: allowed.includes("kite") ? "kite" : allowed[0] },
		situation: { buckets: { ...CALM, ...buckets }, tactic: { current: allowed[0], trigger: "checkpoint", held_s: 8, switches: 0 } } };
}

test("tactic rule overrides come first; nothing applicable gives the personality's default", async () => {
	const t = async (name: string, b: Record<string, unknown>) => {
		const p = P(name);
		return (await createFallbackBrain(p, 1).decide(tacticDecide(p.tactics.allowed, b))).answer;
	};
	assert.equal(await t("aggressive", { mobs_near: "crowd", mobs_near_step: 2, boss: "attacking" }), "aggressive", "pushes while healthy");
	assert.equal(await t("aggressive", { hp: "low" }), "kite");
	assert.equal(await t("defensive", { mobs_near: "crowd", mobs_near_step: 2 }), "defensive");
	assert.equal(await t("defensive", {}), "kite");
	assert.equal(await t("exploratory", { drops_near: "many" }), "explore");
	assert.equal(await t("exploratory", { mobs_near: "swarm", mobs_near_step: 3 }), "kite");
	assert.equal(await t("completionist", {}), "collect");
	const a = await createFallbackBrain(P("aggressive"), 1).decide(tacticDecide(["aggressive", "kite"]));
	assert.equal(a.source, "fallback:tactic-rules");
	assert.match(a.reason ?? "", /rule healthy_push/);
});
