// Agent playtest CLI (spec #91): plays a real round of Maple Survivors headless through the decision protocol and
// writes a run directory with a report. Entry point: scripts/agent_playtest.sh (installs dependencies first).
//
//   node tools/playtest/src/cli.ts --stage=henesys_hg1 --seed=2026 --minutes=3
//   ISOLATE=<name> node tools/playtest/src/cli.ts ...   # run the game from a private project mirror
//
// Exit code: 0 clean, 1 deterministic problems found, 2 infrastructure error (Godot missing, cache missing, no end).
// Flags come from registries: core/args.ts (defineCoreFlags) and maple/flags.ts (defineMapleFlags).
import { FlagRegistry, defineCoreFlags } from "./core/args.ts";
import { EXIT } from "./core/exit_codes.ts";
import { defineMapleFlags } from "./maple/flags.ts";
import { defineInvariantFlags, invariantChecks } from "./maple/invariant_flags.ts";
import { defineJevFlags } from "./maple/jev_flags.ts";
import { runPlaytest } from "./maple/run.ts";

const USAGE = "usage: bash scripts/agent_playtest.sh [flags]";
/** Report lines echoed to the console (the head: title, header, outcome, problems). */
const HEAD_LINES = 30;

async function main(argv: string[]): Promise<number> {
	const flags = defineInvariantFlags(defineJevFlags(defineMapleFlags(defineCoreFlags(new FlagRegistry()))));
	const { values, errors } = flags.parse(argv);
	if (values.help) {
		console.log(`${USAGE}\n\n${flags.help()}`);
		return EXIT.OK;
	}
	if (errors.length) {
		console.error(`agent_playtest: ${errors.join("; ")}\n${USAGE}\n\n${flags.help()}`);
		return EXIT.INFRA;
	}
	const run = await runPlaytest({
		stage: String(values.stage), seed: Number(values.seed), minutes: Number(values.minutes),
		personality: String(values.personality), brain: String(values.brain), livenessS: Number(values["liveness-s"]),
		out: values.out === undefined ? undefined : String(values.out),
		model: String(values.model), jevMaxRequests: Number(values["jev-max-requests"]),
		checks: invariantChecks(values),
	});
	console.log(run.markdown.split("\n").slice(0, HEAD_LINES).join("\n"));
	console.log(`\nrun directory: ${run.dir}\nexit code: ${run.exitCode}`);
	return run.exitCode;
}

process.exitCode = await main(process.argv.slice(2));
