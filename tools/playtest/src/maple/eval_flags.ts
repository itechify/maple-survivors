// CLI flags of the evaluations and the final report (adapter, #99), defined on the shared flag registry. The
// windowed replay flags (--windowed, --shots-at) belong to #100 and are not defined here; the report only prints them.
import type { FlagRegistry } from "../core/args.ts";
import type { FlagValue } from "../core/args.ts";

/** tier C: a death cluster is a run-time window of this many seconds... */
export const DEFAULT_CLUSTER_WINDOW_S = 90;
/** ...holding the deaths of at least this share of a matrix's cells. */
export const DEFAULT_CLUSTER_SHARE = 0.4;

export function defineEvalFlags(flags: FlagRegistry): FlagRegistry {
	return flags
		.define({ name: "strict-eval", kind: "bool", default: false,
			help: "Jev-flagged evaluation results count toward exit code 1 (needs-review results never do)" })
		.define({ name: "summarize", kind: "string",
			help: "rewrite summary.md / summary.json of an existing matrix directory from its cell directories (no runs)" })
		.define({ name: "cluster-window-s", kind: "number", default: DEFAULT_CLUSTER_WINDOW_S,
			help: "matrix summary: run-time window (s) of a death cluster" })
		.define({ name: "cluster-share", kind: "number", default: DEFAULT_CLUSTER_SHARE,
			help: "matrix summary: share of the cells whose deaths fall in one window to report a death-cluster pattern" });
}

/** The death-cluster options from flag values (old recordings lack these flags: defaults). */
export function clusterOptions(values: Record<string, FlagValue>): { windowS: number; share: number } {
	const w = Number(values["cluster-window-s"]);
	const s = Number(values["cluster-share"]);
	return { windowS: Number.isFinite(w) && w > 0 ? w : DEFAULT_CLUSTER_WINDOW_S,
		share: Number.isFinite(s) && s > 0 ? s : DEFAULT_CLUSTER_SHARE };
}
