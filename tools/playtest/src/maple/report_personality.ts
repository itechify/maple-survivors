// The report's personality section (adapter, #97): who played (allowed tactics, timing, emergency, motor parameters,
// fallback policies) and what the motor layer did in the round (the record's `motor`: stale ticks, mistake bursts,
// threshold drinks) next to the potions used.
import { registerSection } from "../core/report.ts";
import type { ReportContext } from "../core/report.ts";
import type { EndMessage } from "../core/protocol.ts";
import type { Personality } from "./personality.ts";

type Motor = { delayed_ticks?: number; bursts?: number; wrong_direction?: number; no_input?: number; burst_ticks?: number;
	potion_hp_drinks?: number; potion_mp_drinks?: number };

const recordOf = (ctx: ReportContext) => ((ctx.data.end as EndMessage | undefined)?.record ?? {}) as Record<string, unknown>;
const pct = (v: number | null) => (v === null ? "the controller's timing" : `below ${Math.round(v * 100)}%`);

registerSection({
	id: "personality",
	order: 45,
	markdown: (ctx) => {
		const p = ctx.data.personality as Personality | undefined;
		if (!p) return [];
		const m = p.motor;
		const lines = ["## Personality", "",
			`**${p.name}**: tactics ${p.tactics.allowed.join(", ")} (start ${p.tactics.default}, checkpoint ${p.tactics.checkpoint_s} s, ` +
			`hold ${p.tactics.hold_s} s${p.tactics.allowed.length === 1 ? ", no tactic decisions" : ""}), emergency ${p.emergency ? "on" : "off"}; ` +
			`cards ${p.fallback.cards}, jobs ${Array.isArray(p.fallback.job) ? p.fallback.job.join(" > ") : p.fallback.job} (fallback).`,
			`Motor: reaction delay ${m.reaction_delay_ticks} ticks, mistakes ${m.mistake_rate}/s, HP potions ${pct(m.potion_hp_fraction)}, ` +
			`MP potions ${pct(m.potion_mp_fraction)}.`];
		const r = recordOf(ctx);
		const seen = r.motor as Motor | undefined;
		if (seen) {
			lines.push(`In the round: ${seen.delayed_ticks ?? 0} stale ticks, ${seen.bursts ?? 0} mistake bursts ` +
				`(${seen.wrong_direction ?? 0} wrong way, ${seen.no_input ?? 0} frozen; ${seen.burst_ticks ?? 0} ticks); ` +
				`potions used ${JSON.stringify(r.potions_used ?? {})}.`);
		}
		return lines;
	},
	json: (ctx) => {
		const p = ctx.data.personality as Personality | undefined;
		if (!p) return null;
		return { name: p.name, tactics: p.tactics, emergency: p.emergency, motor: p.motor,
			fallback: { cards: p.fallback.cards, job: p.fallback.job, tactic_rules: p.fallback.tactic_rules.map((t) => t.id) },
			motor_observed: recordOf(ctx).motor ?? null };
	},
});
