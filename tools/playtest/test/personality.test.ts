// Playtest personalities as data (#97): the schema (unknown fields and bad values are rejected), the shipped files,
// and the parameters the driver receives. No Godot, no network.
import { test } from "node:test";
import assert from "node:assert/strict";
import { validatePersonality, loadPersonality, SHIPPED_PERSONALITIES, driverParams, personalityText } from "../src/maple/personality.ts";

/** A minimal valid personality. */
const valid = () => ({
	name: "tester",
	description: "A test player.",
	goals: ["Survive."],
	tactics: { allowed: ["kite", "defensive"], default: "kite", checkpoint_s: 8, hold_s: 4 },
	emergency: true,
	motor: { reaction_delay_ticks: 0, mistake_rate: 0, potion_hp_fraction: null, potion_mp_fraction: null },
	fallback: { cards: "sensible", job: "sensible", tactic_rules: [] },
});

const errorsOf = (v: unknown) => validatePersonality(v).errors;

test("a minimal personality validates", () => {
	const r = validatePersonality(valid());
	assert.deepEqual(r.errors, []);
	assert.equal(r.personality?.name, "tester");
});

test("unknown fields are rejected at every level", () => {
	assert.match(errorsOf({ ...valid(), mood: "happy" }).join("; "), /unknown field mood/);
	const v = valid();
	(v.tactics as Record<string, unknown>).prior = "kite";
	assert.match(errorsOf(v).join("; "), /unknown field tactics\.prior/);
	const m = valid();
	(m.motor as Record<string, unknown>).reaction = 3;
	assert.match(errorsOf(m).join("; "), /unknown field motor\.reaction/);
	const f = valid();
	f.fallback.tactic_rules = [{ id: "x", when: { hp: ["low"] }, then: "kite", why: "?" }] as never;
	assert.match(errorsOf(f).join("; "), /unknown field fallback\.tactic_rules\[0\]\.why/);
	assert.deepEqual(errorsOf({ ...valid(), _doc: "notes are allowed" }), []);
});

test("bad values are rejected", () => {
	const bad = (patch: (v: ReturnType<typeof valid>) => void, re: RegExp) => {
		const v = valid();
		patch(v);
		assert.match(errorsOf(v).join("; "), re);
	};
	bad((v) => { v.tactics.allowed = []; }, /tactics\.allowed/);
	bad((v) => { v.tactics.allowed = ["kite", "dance"]; }, /tactics\.allowed.*dance/);
	bad((v) => { v.tactics.allowed = ["kite", "kite"]; }, /tactics\.allowed.*twice/);
	bad((v) => { v.tactics.default = "explore"; }, /tactics\.default/);
	bad((v) => { v.tactics.checkpoint_s = 0; }, /tactics\.checkpoint_s/);
	bad((v) => { v.tactics.hold_s = -1; }, /tactics\.hold_s/);
	bad((v) => { (v.tactics as Record<string, unknown>).min_confidence = 1.5; }, /tactics\.min_confidence/);
	bad((v) => { v.tactics.allowed = ["kite"]; v.tactics.default = "kite"; }, /emergency.*defensive/);
	bad((v) => { v.motor.reaction_delay_ticks = 2.5; }, /motor\.reaction_delay_ticks/);
	bad((v) => { v.motor.mistake_rate = -0.1; }, /motor\.mistake_rate/);
	bad((v) => { (v.motor as Record<string, unknown>).potion_hp_fraction = 2; }, /motor\.potion_hp_fraction/);
	bad((v) => { (v.fallback as Record<string, unknown>).cards = "smart"; }, /fallback\.cards/);
	bad((v) => { (v.fallback as Record<string, unknown>).cards = "weighted"; }, /fallback\.weights/);
	bad((v) => { (v.fallback as Record<string, unknown>).job = 200; }, /fallback\.job/);
	bad((v) => { v.fallback.tactic_rules = [{ id: "r", when: { mood: ["x"] }, then: "kite" }] as never; }, /when\.mood/);
	bad((v) => { v.fallback.tactic_rules = [{ id: "r", when: { hp: ["low"] }, then: "dance" }] as never; }, /then/);
	bad((v) => { v.description = ""; }, /description/);
	bad((v) => { v.goals = []; }, /goals/);
	assert.match(errorsOf(null).join("; "), /object/);
});

test("every shipped personality loads, and the file name is its name", () => {
	assert.deepEqual([...SHIPPED_PERSONALITIES].sort(),
		["aggressive", "completionist", "defensive", "exploratory", "inexperienced", "sensible"]);
	for (const name of SHIPPED_PERSONALITIES) {
		const r = loadPersonality(name);
		assert.deepEqual(r.errors, [], name);
		assert.equal(r.personality?.name, name);
	}
	assert.match(loadPersonality("nobody").errors.join("; "), /no personality nobody.*sensible/);
});

test("sensible is today's bot: kite only, BotInput's cards and jobs, no motor noise", () => {
	const p = loadPersonality("sensible").personality!;
	assert.deepEqual(p.tactics.allowed, ["kite"]);
	assert.equal(p.tactics.default, "kite");
	assert.equal(p.fallback.cards, "sensible");
	assert.equal(p.fallback.job, "sensible");
	assert.deepEqual(driverParams(p), {
		name: "sensible",
		tactics: { allowed: ["kite"], default: "kite", checkpoint_s: 8, hold_s: 4 },
		motor: { reaction_delay_ticks: 0, mistake_rate: 0, potion_hp_fraction: null, potion_mp_fraction: null },
	}, "the noise-free defaults the GDScript identity test configures");
});

test("the shipped personalities differ where the ticket says they do", () => {
	const p = (n: string) => loadPersonality(n).personality!;
	assert.ok(p("inexperienced").motor.reaction_delay_ticks > 0 && p("inexperienced").motor.mistake_rate > 0);
	assert.equal(p("inexperienced").fallback.cards, "random");
	assert.ok(p("inexperienced").tactics.checkpoint_s > p("sensible").tactics.checkpoint_s, "rarely changes tactic");
	assert.ok(p("aggressive").tactics.allowed.includes("aggressive"));
	assert.ok(p("defensive").tactics.allowed.includes("defensive") && p("defensive").emergency);
	assert.ok((p("defensive").motor.potion_hp_fraction ?? 0) > (p("inexperienced").motor.potion_hp_fraction ?? 1), "drinks earlier");
	assert.equal(p("exploratory").tactics.default, "explore");
	assert.equal(p("completionist").tactics.default, "collect");
});

test("the personality text Jev reads is the description followed by the goals", () => {
	const text = personalityText(valid() as never);
	assert.match(text, /^A test player\./);
	assert.match(text, /Survive\./);
});
