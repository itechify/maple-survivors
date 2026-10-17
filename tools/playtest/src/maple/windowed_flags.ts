// CLI flags of the windowed replay (adapter, ticket #100), defined on the shared flag registry. They steer only
// `--replay=<dir> --windowed` (maple/windowed_replay.ts) and are never recorded as a run's flags.
import type { FlagRegistry } from "../core/args.ts";

export function defineWindowedFlags(flags: FlagRegistry): FlagRegistry {
	return flags
		.define({ name: "windowed", kind: "bool", default: false, help: "with --replay: replay in the real game window (RunScene) and save screenshots into the replay's shots/" })
		.define({ name: "shots-at", kind: "string", help: "with --windowed: run seconds to screenshot, comma separated (e.g. 412.5,600); every timed finding of the recording is shot too" })
		.define({ name: "speed", kind: "int", default: 4, help: "with --windowed: sim ticks per 60 Hz frame (Engine.time_scale; the ticks played never change)" })
		.define({ name: "skip-to", kind: "number", help: "with --windowed: fast-forward to this run time before drawing (the replay still plays every tick)" });
}

/** The --shots-at run seconds, or an error message. */
export function parseShotsAt(raw: string | undefined): number[] | { error: string } {
	if (raw === undefined || raw.trim() === "") return [];
	const parts = raw.split(",").map((s) => s.trim()).filter(Boolean);
	const times = parts.map(Number);
	if (times.some((t) => !Number.isFinite(t) || t < 0)) {
		return { error: `--shots-at takes run seconds separated by commas (e.g. 412.5,600), got ${raw}` };
	}
	return times;
}
