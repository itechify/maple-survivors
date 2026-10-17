// The deterministic fallback tactic rule table (adapter, #95): answers a `tactic` decide from the situation buckets.
// Rules are data, checked in order; the first rule whose conditions all hold and whose tactic is offered wins, else
// the decide's baseline ("kite"). Personalities (#97) pass their own table (or overrides) to `tacticFor`.
// All rules here are tier C (our own judgment of what a sensible player does), not MapleStory facts.
import type { DecideMessage } from "../core/protocol.ts";
import { bucketsOf } from "./situation.ts";
import type { Buckets } from "./situation.ts";

/** One rule: every listed bucket must have one of the listed values. */
export type TacticRule = { id: string; when: Partial<Record<keyof Buckets & string, readonly (string | number)[]>>; then: string };

/** The sensible player's table. */
export const SENSIBLE_TACTIC_RULES: readonly TacticRule[] = [
	{ id: "hp_critical", when: { hp: ["critical"] }, then: "defensive" },
	{ id: "low_hp_in_a_crowd", when: { hp: ["low"], mobs_near: ["crowd", "swarm"] }, then: "defensive" },
	{ id: "low_hp", when: { hp: ["low"] }, then: "kite" },
	{ id: "boss", when: { boss: ["present", "attacking"] }, then: "kite" },
	{ id: "swarm_or_crowd", when: { mobs_near: ["crowd", "swarm"] }, then: "kite" },
	{ id: "few_mobs_unhurt", when: { mobs_near: ["few"], hp: ["ok", "full"], recent_hits: ["none"] }, then: "aggressive" },
	{ id: "drops_on_a_quiet_map", when: { mobs_near: ["none"], drops_near: ["some", "many"] }, then: "collect" },
	{ id: "drops_above_on_a_quiet_map", when: { mobs_near: ["none"], drops_above: ["some", "many"] }, then: "collect" },
	{ id: "nothing_around", when: { mobs_near: ["none"] }, then: "explore" },
];

/** The rule-table answer to tactic decide `decide`: the tactic and the rule that chose it (null: the baseline). */
export function tacticFor(decide: DecideMessage, rules: readonly TacticRule[] = SENSIBLE_TACTIC_RULES): { answer: string; rule: string | null } {
	const offered = new Set(decide.options.map((o) => String(o.id)));
	const fallback = decide.baseline.sensible ?? decide.options[0]?.id ?? "";
	const b = bucketsOf(decide.situation);
	if (!b) return { answer: fallback, rule: null };
	for (const rule of rules) {
		if (!offered.has(rule.then)) continue;
		const holds = Object.entries(rule.when).every(([key, values]) => (values ?? []).includes(b[key] as string | number));
		if (holds) return { answer: rule.then, rule: rule.id };
	}
	return { answer: fallback, rule: null };
}
