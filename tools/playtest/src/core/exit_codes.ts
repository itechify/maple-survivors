// CLI exit codes (game-agnostic core): 0 clean, 1 deterministic problems found, 2 infrastructure error.

export const EXIT = { OK: 0, PROBLEMS: 1, INFRA: 2 } as const;
export type ExitCode = (typeof EXIT)[keyof typeof EXIT];

/** The exit code for a run with these infrastructure errors and this many deterministic problems. */
export function exitCodeFor(infraErrors: readonly string[], problems: number): ExitCode {
	if (infraErrors.length > 0) return EXIT.INFRA;
	return problems > 0 ? EXIT.PROBLEMS : EXIT.OK;
}
