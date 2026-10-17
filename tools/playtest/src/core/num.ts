// One number reader for recorded JSON (game-agnostic core): records, timeline rows and situations come from JSON, so
// a field may be missing, null or not a number.

/** `v` when it is a finite number, else `fallback` (default 0). */
export function num(v: unknown): number;
export function num<D>(v: unknown, fallback: D): number | D;
export function num(v: unknown, fallback: unknown = 0): unknown {
	return typeof v === "number" && Number.isFinite(v) ? v : fallback;
}
