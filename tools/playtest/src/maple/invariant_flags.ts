// CLI flags of the deterministic invariants (adapter, ticket #96): stuck detector thresholds and the test-only
// injected finding. Passed through to the driver (game/tools/playtest/playtest_driver.gd).
import type { FlagRegistry } from "../core/args.ts";

/** The finding kinds the driver's invariants report (game/tools/playtest/playtest_invariants.gd KINDS). */
export const FINDING_KINDS = ["hp_out_of_range", "mp_out_of_range", "position_not_finite", "out_of_bounds",
	"level_decreased", "exp_decreased", "bad_state_transition", "card_offer", "world_warning", "missing_asset", "stuck"] as const;

export type InvariantChecks = { stuckPx?: number; stuckS?: number; injectFinding?: string };

export function defineInvariantFlags(flags: FlagRegistry): FlagRegistry {
	return flags
		.define({ name: "stuck-px", kind: "number", help: "stuck detector: the box the player stays inside (driver default 24 px)" })
		.define({ name: "stuck-s", kind: "number", help: "stuck detector: the run-time window (driver default 20 s)" })
		.define({ name: "inject-finding", kind: "string", choices: FINDING_KINDS,
			help: "test only: the driver reports one finding of this kind at 0:10 to show the reporting path" });
}

/** The invariant settings among parsed flag values (undefined = the driver's default). */
export function invariantChecks(values: Record<string, unknown>): InvariantChecks {
	const num = (k: string) => (typeof values[k] === "number" ? (values[k] as number) : undefined);
	return { stuckPx: num("stuck-px"), stuckS: num("stuck-s"),
		injectFinding: typeof values["inject-finding"] === "string" ? (values["inject-finding"] as string) : undefined };
}
