// Deterministic problems of one session (game-agnostic core): the driver's invariant findings (the `end` message's
// de-duplicated list with final counts, else the findings streamed before the driver died) plus the process-level
// error lines of its log (log_scan.ts). These are the lines of findings.jsonl and decide exit code 1.
import { scanLog } from "./log_scan.ts";
import type { Problem } from "./report.ts";
import type { SessionResult } from "./session.ts";

/** Every deterministic problem of `session`, given the log lines it wrote (as in game.log). */
export function sessionProblems(session: SessionResult | undefined, logLines: readonly string[]): Problem[] {
	const endFindings = session?.end?.findings;
	const findings = Array.isArray(endFindings) ? endFindings : session?.findings ?? [];
	const fromDriver = findings.map((f) => {
		const { v: _v, type: _type, ...rest } = f as Record<string, unknown>;
		return { source: "invariant", ...rest, kind: String(rest.kind ?? "unknown"), message: String(rest.message ?? "") } as Problem;
	});
	return [...fromDriver, ...scanLog(logLines)];
}
