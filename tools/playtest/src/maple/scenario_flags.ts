// CLI flags of scenarios, replay, matrices, tier chains and character fixtures (adapter, ticket #98), defined on the
// shared flag registry. A flag given on the command line overrides the scenario file's field (maple/scenario.ts).
import type { FlagRegistry } from "../core/args.ts";
import { defineEvalFlags } from "./eval_flags.ts";

export function defineScenarioFlags(flags: FlagRegistry): FlagRegistry {
	return defineEvalFlags(flags) // #99: --strict-eval, --summarize, --cluster-window-s, --cluster-share
		.define({ name: "scenario", kind: "string", help: "scenario name (tools/playtest/scenarios/<name>.json; default smoke); explicit flags override its fields" })
		.define({ name: "replay", kind: "string", help: "re-run a recorded run directory exactly with its recorded answers (no Jev, no key) and compare the fingerprint" })
		.define({ name: "character", kind: "string", help: "start from this CharacterSnapshot JSON (path; one round, no --tier)" })
		.define({ name: "tier", kind: "int", help: "play a tier chain from tier 1 through this tier (stages.json tiers; --stage is tier 1's stage)" })
		.define({ name: "warp", kind: "number", help: "run seconds played by the sensible baseline (BotInput's choices, kite) before the brain decides" })
		.define({ name: "jobs", kind: "int", help: "parallel Godot processes for a multi-run scenario (default min(4, cores/2))" })
		.define({ name: "evaluations", kind: "bool", help: "run the Jev-assisted evaluations after the round (default true; skipped without a key and on a replay; --evaluations=false turns them off)" });
}
