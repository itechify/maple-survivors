// Process-level log checks (game-agnostic core): engine and script error lines in the driver's log (game.log) are
// deterministic problems. Godot prints "SCRIPT ERROR: ...", "ERROR: ..." or "USER ERROR: ..." followed by an
// "   at: <where>" line. The engine's leak report at exit is noise and ignored (the same patterns scripts/test.sh filters).
import type { Problem } from "./report.ts";

const ERROR_LINE = /^(?:USER |SCRIPT )?ERROR: /;
const AT_LINE = /^\s+at: (.*)$/;
/** Leak noise at exit (scripts/test.sh's grep -v list). */
const NOISE = [/^WARNING: .*leaked/, /^ERROR: .*ObjectDB instances leaked/, /^ERROR: .* resources still in use/, /^Leaked instance/];
/** The prefix the run directory's game.log puts before the driver's stderr lines. */
const STDERR = "[stderr] ";

/** One `script_error` problem per distinct error line and `at:` location in `lines`, with a repeat count, in order of
 * first occurrence (`line` is its 1-based line number). */
export function scanLog(lines: Iterable<string>): Problem[] {
	const entries: Array<{ message: string; location?: string; line: number }> = [];
	let prev: (typeof entries)[number] | null = null;
	let n = 0;
	for (const raw of lines) {
		n++;
		const line = (raw.startsWith(STDERR) ? raw.slice(STDERR.length) : raw).replace(/\r$/, "");
		const at = AT_LINE.exec(line);
		if (at && prev) prev.location = at[1].trim();
		prev = null;
		if (at || !ERROR_LINE.test(line) || NOISE.some((re) => re.test(line))) continue;
		prev = { message: line.trim(), line: n };
		entries.push(prev);
	}
	const out = new Map<string, Problem>();
	for (const e of entries) {
		const key = `${e.message}\u0000${e.location ?? ""}`;
		const seen = out.get(key);
		if (seen) seen.count = Number(seen.count) + 1;
		else out.set(key, { kind: "script_error", severity: "error", message: e.message, count: 1, source: "game.log",
			line: e.line, ...(e.location ? { location: e.location } : {}) });
	}
	return [...out.values()];
}
