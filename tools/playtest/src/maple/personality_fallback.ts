// The deterministic fallback brain of a personality (adapter, #97). No network; identical answers for identical
// (personality, run seed, decide). It answers when Jev is not used, and when Jev fails on a decision.
//   card    sensible: the driver's BotInput.pick_card_for baseline
//           random:   one offered card, seeded by (run seed, decision id) (a careless player)
//           weighted: the highest `base * sensible_score + kind[kind] + stat[stat] + role[role]`, where sensible_score
//                     is BotInput.card_score and stat / role come from card_decision.gd; ties go to the baseline,
//                     then on-screen order
//   job     sensible: the baseline (BotInput.pick_job); random: seeded; a list: the first offered id in it, else the
//           baseline
//   tactic  the personality's tactic_rules, then the sensible table (tactic_rules.ts), over offered tactics only;
//           no rule: the personality's default tactic when offered, else the baseline
import type { Brain, BrainAnswer } from "../core/session.ts";
import type { DecideMessage, Option } from "../core/protocol.ts";
import { seededShuffle } from "../core/shuffle.ts";
import { SENSIBLE_TACTIC_RULES, tacticFor } from "./tactic_rules.ts";
import type { Personality } from "./personality.ts";

/** Salt that keeps the careless player's picks independent of the Jev brain's presented order (same seed, id). */
const RANDOM_SALT = 0x6361726c; // "carl"

const baselineOf = (d: DecideMessage) => d.baseline.sensible ?? d.options[0]?.id ?? "";

/** A weighted card's score (see the header). */
export function cardScore(c: Option, w: NonNullable<Personality["fallback"]["weights"]>): number {
	const n = (v: unknown) => (typeof v === "number" ? v : 0);
	return (w.base ?? 1) * n(c.sensible_score) + n(w.kind?.[String(c.kind ?? "")]) + n(w.stat?.[String(c.stat ?? "")]) +
		n(w.role?.[String(c.role ?? "none")]);
}

/** The deterministic brain for personality `p` in a run with seed `seed`. */
export function createFallbackBrain(p: Personality, seed: number): Brain {
	const name = `fallback:${p.name}`;
	const randomPick = (d: DecideMessage) => seededShuffle(d.options, (seed ^ RANDOM_SALT) >>> 0, d.id)[0]?.id ?? baselineOf(d);
	const card = (d: DecideMessage): BrainAnswer => {
		const f = p.fallback;
		if (f.cards === "random") return { answer: randomPick(d), source: name, confidence: null, reason: "random card (seeded)" };
		if (f.cards === "weighted" && f.weights) {
			const base = baselineOf(d);
			const scores = Object.fromEntries(d.options.map((o) => [o.id, Math.round(cardScore(o, f.weights!) * 100) / 100]));
			let best = d.options[0]?.id ?? base;
			for (const o of d.options) {
				const better = scores[o.id] > scores[best] || (scores[o.id] === scores[best] && o.id === base);
				if (better) best = o.id;
			}
			return { answer: best, source: name, confidence: null, reason: "weighted card scores", extra: { card_scores: scores } };
		}
		return { answer: baselineOf(d), source: name, confidence: null };
	};
	const job = (d: DecideMessage): BrainAnswer => {
		const j = p.fallback.job;
		if (j === "random") return { answer: randomPick(d), source: name, confidence: null, reason: "random job (seeded)" };
		if (Array.isArray(j)) {
			const offered = new Set(d.options.map((o) => o.id));
			const pick = j.find((id) => offered.has(id));
			if (pick) return { answer: pick, source: name, confidence: null, reason: `job preference ${j.join(" > ")}` };
		}
		return { answer: baselineOf(d), source: name, confidence: null };
	};
	const rules = [...p.fallback.tactic_rules, ...SENSIBLE_TACTIC_RULES];
	const tactic = (d: DecideMessage): BrainAnswer => {
		const t = tacticFor(d, rules);
		if (t.rule) return { answer: t.answer, source: "fallback:tactic-rules", confidence: null, reason: `rule ${t.rule}` };
		const def = d.options.some((o) => o.id === p.tactics.default) ? p.tactics.default : t.answer;
		return { answer: def, source: "fallback:tactic-rules", confidence: null, reason: "no rule applies: the personality's default" };
	};
	return {
		name,
		decide(d) {
			if (d.kind === "card") return card(d);
			if (d.kind === "job") return job(d);
			if (d.kind === "tactic") return tactic(d);
			return { answer: baselineOf(d), source: name, confidence: null };
		},
	};
}
