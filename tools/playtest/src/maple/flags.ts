// Maple Survivors CLI flags (adapter). Later tickets define their flags (--personality choices, --scenario,
// --replay, --windowed, ...) in their own modules on the same registry.
import type { FlagRegistry } from "../core/args.ts";

export function defineMapleFlags(flags: FlagRegistry): FlagRegistry {
	return flags
		.define({ name: "stage", kind: "string", default: "henesys_hg1", help: "stage key (game/data/survivor/stages.json)" })
		.define({ name: "seed", kind: "int", default: 2026, help: "run seed (training seeds 1..60 and 2026 only)" })
		.define({ name: "minutes", kind: "number", default: 3, help: "simulated time cap in minutes (0 = the stage's own cap)" })
		.define({ name: "personality", kind: "string", default: "sensible", help: "playtest personality" })
		.define({ name: "brain", kind: "string", default: "fallback", choices: ["fallback", "builtin"],
			help: "fallback: the CLI answers each decision with the deterministic fallback; builtin: the driver answers itself (no pipe)" });
}
