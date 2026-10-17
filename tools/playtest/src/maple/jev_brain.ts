// The Jev brain for Maple Survivors card and job decisions (adapter, spec #91 / #94). One System One request per
// decision, following the TypeSafe docs (State, Choice/Score, Confidence, Speculative fan-out, Jev 1.13 jaggedness):
//   - the state is small and named: the player personality first, then the character (level, job, owned skills with
//     "r of max" ranks), a bucketed situation (the game-side HP/MP buckets, run phase, boss present; arithmetic stays
//     in code), then the offer;
//   - card: a Choice "which offered card would this player take now" over the card ids plus a Score of how meaningful
//     the offer is (kept in decisions.jsonl for the evaluations); job: a Choice over the branches and "not now";
//   - options are presented in a seeded shuffle of (run seed, decision id) against Jev 1.13's first-option bias
//     (UpgradePool lists guaranteed cards first); the presented and on-screen orders are both recorded.
// Policy (explicit, here): card and job answers are harmless preference choices, so the top choice is applied
// whatever its confidence, and the confidence and probabilities are recorded. Any failure (no Jev question for the
// kind, auth, network, 4xx/5xx after the SDK's retries, the request cap) answers that decision with the deterministic
// fallback and records why.
// Tactic decisions (#97): a Choice over the offered tactics the personality allows (in-game descriptions, seeded
// order) plus a Noul "immediate danger of dying"; the state is the personality text, named buckets, the current tactic,
// how long it has been held, why the decision is asked and the last switches. Policy in code (`tacticGate`): a
// personality with `emergency` goes defensive when danger > 0.7; else confidence < 0.35 (or the personality's
// min_confidence) keeps the current tactic; Jev's choice, the danger and the gate are recorded. With a `personality`, every
// request leads with the personality's text and failures use the personality's fallback brain.
import { choice, noul, score } from "@typesafe-ai/sdk";
import type { Brain, BrainAnswer } from "../core/session.ts";
import type { DecideMessage, Option } from "../core/protocol.ts";
import { JevUnavailable } from "../core/jev_client.ts";
import { redactSecrets } from "../core/key.ts";
import type { JevClient } from "../core/jev_client.ts";
import { seededShuffle } from "../core/shuffle.ts";
import { sensibleBrain } from "./fallback.ts";
import { DEFAULT_MIN_CONFIDENCE, personalityText } from "./personality.ts";
import type { Personality } from "./personality.ts";
import { createFallbackBrain } from "./personality_fallback.ts";
import { bucketsOf, fallbackSituation } from "./situation.ts";
import type { TacticState } from "./situation.ts";
import { num } from "../core/num.ts";

/** The player description Jev decides for, until personalities (#97) replace it. */
export const SENSIBLE_PLAYER = "A sensible, experienced MapleStory player in a survivor-style round: skills attack " +
	"automatically while the player moves, dodges and collects EXP. They want to survive every boss and clear the " +
	"stage, so they build up their main attack skills, take new skills that fit their job, and value survivability " +
	"when HP is a problem.";

export type JevBrainOptions = {
	client: JevClient;
	/** The run seed: with the decision id it seeds the presented option order. */
	seed: number;
	/** The player text that leads the state. Default the personality's text, else SENSIBLE_PLAYER. */
	playerText?: string;
	/** The playtest personality (#97): its text leads every request, its allowed tactics, `emergency` and
	 * `min_confidence` drive the tactic question, and its fallback brain answers failures. */
	personality?: Personality;
	/** Answers when Jev cannot. Default the personality's fallback brain, else the sensible fallback (the driver's
	 * BotInput baseline). */
	fallback?: Brain;
};

type Situation = Record<string, unknown>;

/** The run phase from run time and boss progress (tier C: ours). */
export function runPhase(s: Situation): string {
	const alive = num(s.bosses_alive);
	const defeated = num(s.bosses_defeated);
	const scheduled = num(s.bosses_scheduled);
	if (alive > 0) return "boss fight";
	if (num(s.time) < 120) return "opening minutes"; // tier C: the first 2:00
	if (scheduled === 0) return "mid-round";
	if (defeated === 0) return "early, before the first boss";
	if (defeated >= scheduled) return "after the final boss";
	if (defeated === scheduled - 1) return "late, the final boss is next";
	return "middle, between bosses";
}

/** The bucketed situation Jev sees (named levels, no raw numbers to compare): HP and MP are the decide's game-side
 * buckets (playtest_situation.gd, the same ones the tactic question and the fallback rules read). */
export function situationBuckets(s: Situation): Record<string, string> {
	const b = bucketsOf(s);
	return { hp: String(b?.hp ?? "unknown"), mp: String(b?.mp ?? "unknown"),
		"run phase": runPhase(s), "boss present": num(s.bosses_alive) > 0 ? "yes" : "no" };
}

/** The character facts: level, job and owned skills with "r of max" ranks. */
function character(s: Situation) {
	const owned = Array.isArray(s.owned_skills) ? (s.owned_skills as Array<Record<string, unknown>>) : [];
	return { level: num(s.level), job: String(s.job ?? "?"),
		skills: owned.map((k) => ({ name: String(k.name ?? k.key ?? "?"), rank: `${k.rank} of ${k.max_rank}` })) };
}

const KIND_TEXT: Record<string, string> = {
	skill_new: "learn a new skill", skill_rank: "raise a skill's level", skill_mod: "improve an owned skill",
	stat: "character stat", potion_tier: "better potions", filler: "filler (nothing better was left)",
};

/** The card's rank as the level-up window shows it, as words: "skill Lv. 3 -> 4 of 20", "rank 2 of 4". */
export function cardRankText(c: Option): string {
	const n = (k: string) => (typeof c[k] === "number" ? (c[k] as number) : 0);
	const kind = String(c.kind ?? "");
	if (kind === "filler") return "";
	if (kind === "skill_new" && n("skill_level_next") > 0) return `new skill at Lv. ${n("skill_level_next")} of ${n("skill_level_max")}`;
	if (kind === "skill_rank" && n("skill_level") > 0 && n("skill_level_next") > n("skill_level")) {
		return `skill Lv. ${n("skill_level")} -> ${n("skill_level_next")} of ${n("skill_level_max")}`;
	}
	return `rank ${n("rank")} of ${n("max_rank")}`;
}

/** One offered card as Jev reads it: in-game name, description, rank and kind. */
function cardFacts(c: Option) {
	const skill = String(c.skill_name ?? "");
	return { id: c.id, name: String(c.name ?? c.id) + (skill && skill !== c.name ? ` (${skill})` : ""),
		description: String(c.desc ?? ""), rank: cardRankText(c), kind: KIND_TEXT[String(c.kind)] ?? String(c.kind ?? "") };
}

const cardLine = (f: ReturnType<typeof cardFacts>) =>
	`${f.name}: ${f.description}${f.rank ? ` ${f.rank[0].toUpperCase()}${f.rank.slice(1)}.` : ""} Kind: ${f.kind}.`;

const WINDOW = (s: Situation) => (s.advancement ? "job advancement skill draw" : s.bonus ? "boss reward" : "level-up");

const MEANINGFUL_LEVELS = [
	"Empty: none of the offered cards does anything useful for this character now",
	"Weak: at most one card is mildly useful, the rest barely matter",
	"Fair: at least one card is a sensible upgrade for this character",
	"Strong: a clearly valuable card, or a real trade-off between several good cards",
] as const;

/** The card request: state, questions, and the presented order (protocol ids). */
export function cardRequest(d: DecideMessage, seed: number, personality: string) {
	const s = d.situation ?? {};
	const presented = seededShuffle(d.options, seed, d.id);
	const facts = presented.map(cardFacts);
	const state = { player: personality, character: character(s), situation: situationBuckets(s),
		window: WINDOW(s), "offered cards": facts };
	const questions = {
		card: choice("Which offered card would this player take now?",
			Object.fromEntries(facts.map((f) => [f.id, cardLine(f)]))),
		meaningful: score("How meaningful is this card offer for this character right now?", MEANINGFUL_LEVELS),
	};
	return { state, questions, presented: presented.map((o) => o.id), labelToId: (l: string) => l };
}

const NOT_NOW = "not_now";
/** Job ids are numbers, and JS objects list integer-like keys first in ascending order whatever the insertion
 * order, which would undo the shuffle: job labels get a word prefix. */
const jobLabel = (id: string) => (id === NOT_NOW ? NOT_NOW : `job_${id}`);

/** The job request: a Choice over the branches (name and one-line description) and not now. */
export function jobRequest(d: DecideMessage, seed: number, personality: string) {
	const s = d.situation ?? {};
	const presented = seededShuffle(d.options, seed, d.id);
	const current = String(s.job ?? "the current job");
	const criteria = Object.fromEntries(presented.map((o) => [jobLabel(o.id), o.id === NOT_NOW
		? `Not now: stay ${current} with only the skills already learned, and be offered the advancement again later.`
		: `Advance to ${String(o.name ?? o.id)} now${o.desc ? ` (${String(o.desc)})` : ""}.`]));
	const state = { player: personality, character: character(s), situation: situationBuckets(s),
		window: "job advancement" };
	const questions = { job: choice("Which job advancement would this player take now?", criteria) };
	const byLabel = new Map(presented.map((o) => [jobLabel(o.id), o.id]));
	return { state, questions, presented: presented.map((o) => o.id), labelToId: (l: string) => byLabel.get(l) ?? l };
}

/** tier C: a danger Noul above this forces defensive for personalities with `emergency` (ticket #97). */
export const DANGER_FORCES_DEFENSIVE = 0.7;
/** tier C: recent tactic switches shown to Jev (newest last). */
const RECENT_SWITCHES = 3;

/** Why a tactic decision was asked, as words (playtest_policy.gd TRIGGER_PRIORITY keys). */
const TRIGGER_TEXT: Record<string, string> = {
	start: "round start", checkpoint: "regular check", hp_low: "HP just fell to low", hp_critical: "HP just fell to critical",
	boss: "a boss just appeared", crowd: "monsters crowded in", card: "just took a card",
};
const triggerText = (t: unknown) => TRIGGER_TEXT[String(t)] ?? String(t ?? "?");

/** tier C: how long the current tactic has been held, as words. */
export function heldText(seconds: number): string {
	if (seconds < 5) return "under 5 seconds";
	if (seconds <= 20) return "5 to 20 seconds";
	return "over 20 seconds";
}

/** The tactic decide's buckets as named words (playtest_situation.gd buckets; no numbers to compare). */
function tacticSituation(d: DecideMessage): Record<string, string> {
	const b = bucketsOf(d.situation) ?? ({} as Record<string, unknown>);
	const w = (k: string) => String(b[k] ?? "unknown");
	return { HP: w("hp"), MP: w("mp"), "monsters near": w("mobs_near"),
		boss: b.boss === "attacking" ? "attacking the player" : w("boss"), "HP potions": w("potions_hp"),
		"MP potions": w("potions_mp"), "drops nearby": w("drops_near"), "drops on platforms above": w("drops_above"),
		"hits taken in the last few seconds": w("recent_hits"), "run phase": b.phase === "boss" ? "boss fight" : w("phase") };
}

/** The tactic request: a Choice over the offered tactics the personality allows (in-game descriptions, seeded order)
 * and a Noul "immediate danger of dying"; the state is the personality text, the bucketed situation, the current
 * tactic, how long it has been held, why the decision is asked now and the last few switches. */
export function tacticRequest(d: DecideMessage, seed: number, personality: string, allowed?: readonly string[]) {
	const offered = d.options.filter((op) => !allowed || allowed.includes(op.id));
	const presented = seededShuffle(offered, seed, d.id);
	const t = (d.situation?.tactic ?? {}) as Partial<TacticState> & { recent?: Array<Record<string, unknown>> };
	const recent = (Array.isArray(t.recent) ? t.recent : []).slice(-RECENT_SWITCHES)
		.map((r) => `${r.from} -> ${r.to} (${triggerText(r.trigger)})`);
	const state = { player: personality, situation: tacticSituation(d), "current tactic": String(t.current ?? "kite"),
		"current tactic held for": heldText(typeof t.held_s === "number" ? t.held_s : 0), "why this decision now": triggerText(t.trigger),
		"recent tactic switches": recent.length ? recent : ["none yet"] };
	const questions = {
		tactic: choice("Which tactic would this player use for the next few seconds?",
			Object.fromEntries(presented.map((op) => [op.id, String(op.desc ?? op.name ?? op.id)]))),
		danger: noul("Is the player in immediate danger of dying in the next few seconds?"),
	};
	return { state, questions, presented: presented.map((op) => op.id), labelToId: (l: string) => l };
}

/** The code policy over a Jev tactic answer: with `emergency`, danger above DANGER_FORCES_DEFENSIVE forces defensive
 * (when offered); otherwise a confidence below `minConfidence` keeps the current tactic (when offered); otherwise
 * Jev's top choice. `gate` records which rule acted ("none" when Jev's choice stands). */
export function tacticGate(d: DecideMessage, choice: string, confidence: number | null, danger: number | null,
	offered: readonly string[], emergency: boolean, minConfidence: number): { answer: string; gate: string } {
	if (emergency && danger !== null && danger > DANGER_FORCES_DEFENSIVE && offered.includes("defensive")) {
		return { answer: "defensive", gate: `danger ${danger} > ${DANGER_FORCES_DEFENSIVE}: forced defensive` };
	}
	const current = String((d.situation?.tactic as Partial<TacticState> | undefined)?.current ?? "");
	if (confidence !== null && confidence < minConfidence && offered.includes(current)) {
		return { answer: current, gate: `low confidence ${confidence} < ${minConfidence}: kept ${current}` };
	}
	return { answer: choice, gate: "none" };
}

/** The Jev brain: card, job and tactic decisions through Jev, anything else (and every failure) through `fallback`. */
export function createJevBrain(o: JevBrainOptions): Brain {
	const p = o.personality;
	const player = o.playerText ?? (p ? personalityText(p) : SENSIBLE_PLAYER);
	const fallback = o.fallback ?? (p ? createFallbackBrain(p, o.seed) : sensibleBrain);
	const fallBack = async (d: DecideMessage, reason: string): Promise<BrainAnswer> => {
		const a = await fallback.decide(d);
		return { ...a, reason, extra: { situation_shown: fallbackSituation(d.situation), ...a.extra } };
	};
	const minConfidence = p?.tactics.min_confidence ?? DEFAULT_MIN_CONFIDENCE;
	return {
		name: "jev",
		async decide(d) {
			const build = d.kind === "card" ? cardRequest : d.kind === "job" ? jobRequest
				: d.kind === "tactic" ? (dd: DecideMessage, seed: number, text: string) => tacticRequest(dd, seed, text, p?.tactics.allowed)
				: null;
			if (!build) return fallBack(d, `no Jev question for decision kind ${d.kind}`);
			const req = build(d, o.seed, player);
			if (req.presented.length === 0) return fallBack(d, "no offered option is allowed for this personality");
			let reply;
			try {
				reply = await o.client.ask(req.state, req.questions);
			} catch (e) {
				return fallBack(d, e instanceof JevUnavailable ? e.reason : redactSecrets(`Jev failed: ${(e as Error).message}`, []));
			}
			const answers = reply.result.answers as Record<string, { choice?: string; confidence?: number;
				probabilities?: Record<string, number>; score?: number; noul?: number }>;
			const main = answers[d.kind];
			const answer = main?.choice === undefined ? undefined : req.labelToId(main.choice);
			if (answer === undefined || !req.presented.includes(answer)) {
				return fallBack(d, `Jev answered ${JSON.stringify(main?.choice)}, not an offered option`);
			}
			const probabilities = Object.fromEntries(Object.entries(main.probabilities ?? {}).map(([l, p]) => [req.labelToId(l), p]));
			const confidence = typeof main.confidence === "number" ? main.confidence : null;
			const extra: Record<string, unknown> = { situation_shown: req.state, probabilities, presented_order: req.presented,
				screen_order: d.options.map((op) => op.id), model: reply.result.model, usage: reply.result.usage,
				jev_latency_ms: Math.round(reply.latencyMs) };
			const m = answers.meaningful;
			if (m) extra.meaningfulness = { score: m.score, confidence: m.confidence, probabilities: m.probabilities,
				levels: MEANINGFUL_LEVELS.length };
			if (d.kind === "tactic") {
				const danger = typeof answers.danger?.noul === "number" ? answers.danger.noul : null;
				const g = tacticGate(d, answer, confidence, danger, req.presented, p?.emergency === true, minConfidence);
				Object.assign(extra, { jev_choice: answer, danger, gate: g.gate });
				return { answer: g.answer, source: "jev", confidence, extra };
			}
			return { answer, source: "jev", confidence, extra };
		},
	};
}
