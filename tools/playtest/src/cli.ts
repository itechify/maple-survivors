// Agent playtest CLI (spec #91): plays a real round of Maple Survivors headless through the decision protocol and
// writes a run directory with a report. Entry point: scripts/agent_playtest.sh (installs dependencies first).
//
//   node tools/playtest/src/cli.ts --stage=henesys_hg1 --seed=2026 --minutes=3
//   node tools/playtest/src/cli.ts --scenario=matrix          # scenario file; several cells in parallel + summary
//   node tools/playtest/src/cli.ts --replay=<run dir>         # exact re-run from the recorded answers (no Jev)
//   node tools/playtest/src/cli.ts --replay=<run dir> --windowed --shots-at=412.5   # in the game window + screenshots
//   ISOLATE=<name> node tools/playtest/src/cli.ts ...   # run the game from a private project mirror
//
// Exit code: 0 clean, 1 deterministic problems found, 2 infrastructure error (Godot missing, cache missing, no end).
// Flags come from registries: core/args.ts (defineCoreFlags) and maple/flags.ts (defineMapleFlags) and the modules
// below. Scenario, matrix and replay handling: maple/scenario_run.ts.
import type { FlagValue } from "./core/args.ts";
import { FlagRegistry, defineCoreFlags } from "./core/args.ts";
import { EXIT } from "./core/exit_codes.ts";
import { defineMapleFlags } from "./maple/flags.ts";
import { defineInvariantFlags, invariantChecks } from "./maple/invariant_flags.ts";
import { defineJevFlags } from "./maple/jev_flags.ts";
import type { RunOptions } from "./maple/run.ts";
import { defineScenarioFlags } from "./maple/scenario_flags.ts";
import { defineWindowedFlags } from "./maple/windowed_flags.ts";
import { runCli } from "./maple/scenario_run.ts";

const USAGE = "usage: bash scripts/agent_playtest.sh [flags]";

/** Every CLI flag. */
export function cliFlags(): FlagRegistry {
	return defineWindowedFlags(defineScenarioFlags(defineInvariantFlags(defineJevFlags(defineMapleFlags(defineCoreFlags(new FlagRegistry()))))));
}

/** The run options of one run from flag values. A scenario cell's values, and a replay's recorded values
 * (scenario.json `flags`), go through here too, so a flag added later is restored by a replay. */
export function runOptionsFrom(values: Record<string, FlagValue>): RunOptions {
	return {
		stage: String(values.stage), seed: Number(values.seed), minutes: Number(values.minutes),
		personality: String(values.personality), brain: String(values.brain), livenessS: Number(values["liveness-s"]),
		out: values.out === undefined ? undefined : String(values.out),
		model: String(values.model), jevMaxRequests: Number(values["jev-max-requests"]),
		checks: invariantChecks(values),
	};
}

async function main(argv: string[]): Promise<number> {
	const flags = cliFlags();
	const { values, errors, explicit } = flags.parse(argv);
	if (values.help) {
		console.log(`${USAGE}\n\n${flags.help()}`);
		return EXIT.OK;
	}
	if (errors.length) {
		console.error(`agent_playtest: ${errors.join("; ")}\n${USAGE}\n\n${flags.help()}`);
		return EXIT.INFRA;
	}
	const run = await runCli({ values, explicit, optionsFrom: runOptionsFrom });
	console.log(run.text);
	return run.exitCode;
}

if (import.meta.main) process.exitCode = await main(process.argv.slice(2));
