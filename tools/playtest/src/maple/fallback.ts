// Deterministic fallback brains for Maple Survivors (adapter). Each answers from the decide's baseline answers, which
// the driver computes with real game code (BotInput.pick_card_for / BotInput.pick_job). No network, identical runs
// for identical seeds. Personality-specific fallbacks (inexperienced, aggressive, ...) arrive with #94 / #95.
import type { Brain } from "../core/session.ts";

/** The sensible player: always the driver's "sensible" baseline (BotInput's choice). */
export const sensibleBrain: Brain = {
	name: "fallback:sensible",
	decide(decide) {
		const answer = decide.baseline.sensible ?? decide.options[0]?.id ?? "";
		return { answer, source: "fallback:sensible", confidence: null };
	},
};
