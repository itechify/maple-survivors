// Playtest personalities (adapter, #97): data-defined kinds of player, one file per personality in
// tools/playtest/personalities/<name>.json, validated here. A personality changes both what the brain decides (the
// Jev player text, the allowed tactics, the fallback card / job / tactic policies) and how the game-side controller
// moves (motor noise and potion thresholds, applied in game/tools/playtest/motor_noise.gd).
//
// Schema (every level rejects unknown fields; "_doc" is allowed at the top for notes):
//   name         string, the file name
//   description  natural language: who this player is (Jev reads it as the player)
//   goals        natural language list: what they want (Jev reads it after the description)
//   tactics      allowed: tactic ids (tactic_controller.gd TACTICS), non-empty, no repeats; one allowed tactic means
//                  the driver asks no tactic decisions at all
//                default: the tactic at the round start and the fallback rule table's answer when no rule applies
//                checkpoint_s (> 0): a tactic decision every this many run seconds; hold_s (>= 0): minimum hold
//                min_confidence (optional, 0..1): a Jev tactic answer below it keeps the current tactic (default 0.35)
//   emergency    true: a Jev "immediate danger" probability above 0.7 forces defensive (needs defensive allowed)
//   motor        reaction_delay_ticks (int >= 0): after the wanted input changes, the previous input repeats this long
//                mistake_rate (>= 0, per second): chance of a seeded wrong-direction or no-input burst
//                potion_hp_fraction / potion_mp_fraction (0..1 or null): drink only below this share of the pool,
//                  replacing the controller's own timing; null keeps the controller's (the bot's) timing
//   fallback     cards: "sensible" (BotInput.pick_card_for), "random" (seeded by run seed and decision id) or
//                  "weighted" (needs weights: {base, kind, stat, role}; see personality_fallback.ts)
//                job: "sensible" (BotInput.pick_job), "random", or a list of job ids in preference order
//                tactic_rules: rules (tactic_rules.ts TacticRule) checked before the sensible table
import fs from "node:fs";
import path from "node:path";
import type { TacticRule } from "./tactic_rules.ts";

export const PERSONALITY_DIR = path.resolve(import.meta.dirname, "..", "..", "personalities");
export const SHIPPED_PERSONALITIES = ["sensible", "inexperienced", "aggressive", "defensive", "exploratory", "completionist"] as const;
/** tactic_controller.gd TACTICS. */
export const TACTICS = ["kite", "aggressive", "defensive", "explore", "collect", "hold"] as const;
/** playtest_situation.gd BUCKET_KEYS (what a tactic rule may test). */
export const BUCKET_KEYS = ["hp", "mp", "mobs_near", "mobs_near_step", "boss", "potions_hp", "potions_mp", "drops_near",
	"drops_above", "phase", "platform", "recent_hits"] as const;
/** Card kinds a weight may name (UpgradePool card kinds). */
export const CARD_KINDS = ["skill_new", "skill_rank", "skill_mod", "stat", "potion_tier", "filler"] as const;
/** Card roles (card_decision.gd `role`). */
export const CARD_ROLES = ["attack", "support", "none"] as const;
/** tier C: a Jev tactic answer below this confidence keeps the current tactic (ticket #97 default). */
export const DEFAULT_MIN_CONFIDENCE = 0.35;

export type CardWeights = { base?: number; kind?: Record<string, number>; stat?: Record<string, number>;
	role?: Record<string, number> };
export type Personality = {
	_doc?: string;
	name: string;
	description: string;
	goals: string[];
	tactics: { allowed: string[]; default: string; checkpoint_s: number; hold_s: number; min_confidence?: number };
	emergency: boolean;
	motor: { reaction_delay_ticks: number; mistake_rate: number; potion_hp_fraction: number | null;
		potion_mp_fraction: number | null };
	fallback: { cards: "sensible" | "random" | "weighted"; weights?: CardWeights; job: "sensible" | "random" | string[];
		tactic_rules: TacticRule[] };
};

type Obj = Record<string, unknown>;
const isObj = (v: unknown): v is Obj => typeof v === "object" && v !== null && !Array.isArray(v);
const isNum = (v: unknown): v is number => typeof v === "number" && Number.isFinite(v);

/** Checks `value` against the schema; returns the personality (when valid) and one message per problem. */
export function validatePersonality(value: unknown): { personality?: Personality; errors: string[] } {
	const errors: string[] = [];
	const fields = (o: Obj, at: string, allowed: readonly string[]) => {
		for (const k of Object.keys(o)) if (!allowed.includes(k)) errors.push(`unknown field ${at}${k}`);
	};
	if (!isObj(value)) return { errors: ["a personality must be a JSON object"] };
	fields(value, "", ["_doc", "name", "description", "goals", "tactics", "emergency", "motor", "fallback"]);
	if (value._doc !== undefined && typeof value._doc !== "string") errors.push("_doc must be a string");
	if (typeof value.name !== "string" || !/^[a-z0-9_]+$/.test(value.name)) errors.push("name must be a lower_snake_case string");
	if (typeof value.description !== "string" || value.description.trim() === "") errors.push("description must be a non-empty string");
	if (!Array.isArray(value.goals) || value.goals.length === 0 || value.goals.some((g) => typeof g !== "string" || g.trim() === "")) {
		errors.push("goals must be a non-empty list of non-empty strings");
	}
	const t = value.tactics;
	let allowed: string[] = [];
	if (!isObj(t)) errors.push("tactics must be an object");
	else {
		fields(t, "tactics.", ["allowed", "default", "checkpoint_s", "hold_s", "min_confidence"]);
		if (!Array.isArray(t.allowed) || t.allowed.length === 0) errors.push("tactics.allowed must be a non-empty list");
		else {
			allowed = t.allowed.map(String);
			for (const a of allowed) if (!(TACTICS as readonly string[]).includes(a)) errors.push(`tactics.allowed: unknown tactic ${a}`);
			if (new Set(allowed).size !== allowed.length) errors.push("tactics.allowed names a tactic twice");
		}
		if (typeof t.default !== "string" || !allowed.includes(t.default)) errors.push("tactics.default must be one of tactics.allowed");
		if (!isNum(t.checkpoint_s) || t.checkpoint_s <= 0) errors.push("tactics.checkpoint_s must be a number > 0");
		if (!isNum(t.hold_s) || t.hold_s < 0) errors.push("tactics.hold_s must be a number >= 0");
		if (t.min_confidence !== undefined && (!isNum(t.min_confidence) || t.min_confidence < 0 || t.min_confidence > 1)) {
			errors.push("tactics.min_confidence must be a number in 0..1");
		}
	}
	if (typeof value.emergency !== "boolean") errors.push("emergency must be true or false");
	else if (value.emergency && isObj(t) && !allowed.includes("defensive")) errors.push("emergency needs defensive in tactics.allowed");
	const m = value.motor;
	if (!isObj(m)) errors.push("motor must be an object");
	else {
		fields(m, "motor.", ["reaction_delay_ticks", "mistake_rate", "potion_hp_fraction", "potion_mp_fraction"]);
		if (!Number.isInteger(m.reaction_delay_ticks) || (m.reaction_delay_ticks as number) < 0 || (m.reaction_delay_ticks as number) > 120) {
			errors.push("motor.reaction_delay_ticks must be an integer in 0..120");
		}
		if (!isNum(m.mistake_rate) || m.mistake_rate < 0 || m.mistake_rate > 5) errors.push("motor.mistake_rate must be a number in 0..5 (per second)");
		for (const k of ["potion_hp_fraction", "potion_mp_fraction"]) {
			const v = m[k];
			if (v !== null && (!isNum(v) || v < 0 || v > 1)) errors.push(`motor.${k} must be null or a number in 0..1`);
		}
	}
	const f = value.fallback;
	if (!isObj(f)) errors.push("fallback must be an object");
	else {
		fields(f, "fallback.", ["cards", "weights", "job", "tactic_rules"]);
		if (!["sensible", "random", "weighted"].includes(String(f.cards))) errors.push("fallback.cards must be sensible, random or weighted");
		if (f.cards === "weighted" && f.weights === undefined) errors.push("fallback.weights is needed when fallback.cards is weighted");
		if (f.weights !== undefined) validateWeights(f.weights, errors, fields);
		const job = f.job;
		if (!(job === "sensible" || job === "random" || (Array.isArray(job) && job.length > 0 && job.every((j) => typeof j === "string")))) {
			errors.push("fallback.job must be sensible, random or a non-empty list of job id strings");
		}
		if (!Array.isArray(f.tactic_rules)) errors.push("fallback.tactic_rules must be a list");
		else f.tactic_rules.forEach((r, i) => validateRule(r, `fallback.tactic_rules[${i}]`, errors, fields));
	}
	return errors.length ? { errors } : { personality: value as unknown as Personality, errors };
}

type Fields = (o: Obj, at: string, allowed: readonly string[]) => void;

function validateWeights(w: unknown, errors: string[], fields: Fields): void {
	if (!isObj(w)) {
		errors.push("fallback.weights must be an object");
		return;
	}
	fields(w, "fallback.weights.", ["base", "kind", "stat", "role"]);
	if (w.base !== undefined && !isNum(w.base)) errors.push("fallback.weights.base must be a number");
	for (const group of ["kind", "stat", "role"] as const) {
		const g = w[group];
		if (g === undefined) continue;
		if (!isObj(g)) {
			errors.push(`fallback.weights.${group} must be an object of numbers`);
			continue;
		}
		const known = group === "kind" ? CARD_KINDS : group === "role" ? CARD_ROLES : null;
		for (const [k, v] of Object.entries(g)) {
			if (known && !(known as readonly string[]).includes(k)) errors.push(`unknown field fallback.weights.${group}.${k}`);
			if (!isNum(v)) errors.push(`fallback.weights.${group}.${k} must be a number`);
		}
	}
}

function validateRule(r: unknown, at: string, errors: string[], fields: Fields): void {
	if (!isObj(r)) {
		errors.push(`${at} must be an object`);
		return;
	}
	fields(r, `${at}.`, ["id", "when", "then"]);
	if (typeof r.id !== "string" || r.id === "") errors.push(`${at}.id must be a non-empty string`);
	if (typeof r.then !== "string" || !(TACTICS as readonly string[]).includes(r.then)) errors.push(`${at}.then must be a tactic`);
	if (!isObj(r.when)) {
		errors.push(`${at}.when must be an object`);
		return;
	}
	for (const [k, v] of Object.entries(r.when)) {
		if (!(BUCKET_KEYS as readonly string[]).includes(k)) errors.push(`${at}.when.${k}: unknown bucket`);
		if (!Array.isArray(v) || v.length === 0) errors.push(`${at}.when.${k} must be a non-empty list of bucket values`);
	}
}

/** Loads and validates tools/playtest/personalities/<name>.json (or `dir`/<name>.json). */
export function loadPersonality(name: string, dir: string = PERSONALITY_DIR): { personality?: Personality; errors: string[] } {
	const file = path.join(dir, `${name}.json`);
	if (!/^[a-z0-9_]+$/.test(name) || !fs.existsSync(file)) {
		const known = fs.existsSync(dir) ? fs.readdirSync(dir).filter((f) => f.endsWith(".json")).map((f) => f.slice(0, -5)) : [];
		return { errors: [`no personality ${name} (known: ${known.join(", ")})`] };
	}
	let value: unknown;
	try {
		value = JSON.parse(fs.readFileSync(file, "utf8"));
	} catch (e) {
		return { errors: [`${file}: not JSON: ${(e as Error).message}`] };
	}
	const r = validatePersonality(value);
	if (r.personality && r.personality.name !== name) return { errors: [`${file}: name is ${r.personality.name}, expected ${name}`] };
	return r.errors.length ? { errors: r.errors.map((e) => `${name}: ${e}`) } : r;
}

/** What the game-side driver needs (personality.json in the run directory, read with --personality-file). */
export function driverParams(p: Personality) {
	return { name: p.name,
		tactics: { allowed: [...p.tactics.allowed], default: p.tactics.default, checkpoint_s: p.tactics.checkpoint_s,
			hold_s: p.tactics.hold_s },
		motor: { ...p.motor } };
}

/** The player text Jev reads first in every request: the description, then the goals. */
export function personalityText(p: Personality): string {
	return `${p.description.trim()} Goals: ${p.goals.map((g) => g.trim()).join(" ")}`;
}
