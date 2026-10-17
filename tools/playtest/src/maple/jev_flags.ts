// The Jev brain's CLI flags (#94), defined on the shared flag registry. The key is never a flag: it comes from
// TYPESAFE_API_KEY in the process env or, on Windows, the user-scope variable (core/key.ts).
import type { FlagRegistry } from "../core/args.ts";
import { DEFAULT_MAX_REQUESTS, DEFAULT_MODEL } from "../core/jev_client.ts";

export function defineJevFlags(flags: FlagRegistry): FlagRegistry {
	return flags
		.define({ name: "model", kind: "string", default: DEFAULT_MODEL, help: "TypeSafe model for the Jev brain" })
		.define({ name: "jev-max-requests", kind: "int", default: DEFAULT_MAX_REQUESTS,
			help: "Jev requests per run, the brain and the evaluations together; later decisions use the fallback" });
}
