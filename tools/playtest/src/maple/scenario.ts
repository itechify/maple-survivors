// Scenario files (adapter, ticket #98): a repeatable playtest is one name, tools/playtest/scenarios/<name>.json.
// Schema (every field but description, stage, seeds, personalities and minutes is optional):
//   description    text shown in --help-like listings and the report
//   stage          stage key (game/data/survivor/stages.json); with tier >= 2 it is tier 1's stage
//   seeds          [int] training seeds only: 1..60 and 2026 (AGENTS.md; held-out ranges are never used)
//   personalities  [name] or "all" (every known personality, maple/personalities.ts)
//   minutes        simulated time cap per round (0 = the stage's own cap)
//   warp           run seconds played by the sensible baseline before the brain decides (default 0)
//   character      CharacterSnapshot JSON path, relative to the repo (one round; not with tier >= 2)
//   tier           chain from tier 1 through this tier (default 1: one round)
//   brain          auto | jev | fallback | builtin (default auto)
//   evaluations    run the Jev-assisted evaluations (#99; default true with brain auto or jev, false with fallback or
//                  builtin, so those stay deterministic and offline)
//   invariants     {stuck_px, stuck_s}: stuck detector thresholds (driver defaults when absent)
//   jobs           parallel Godot processes (default min(4, cores/2))
// The cells are personalities x seeds. A flag given on the command line overrides the matching field:
// --stage, --seed (one seed), --personality (one personality), --minutes, --warp, --character, --tier, --brain,
// --evaluations, --stuck-px, --stuck-s, --jobs.
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import type { FlagValue } from "../core/args.ts";
import { personalityNames } from "./personalities.ts";

export const SCENARIO_DIR = path.resolve(import.meta.dirname, "..", "..", "scenarios");
export const DEFAULT_SCENARIO = "smoke";
export const BRAINS = ["auto", "jev", "fallback", "builtin"] as const;

export type Scenario = {
	description?: string; stage: string; seeds: number[]; personalities: string[] | "all"; minutes: number; warp?: number;
	character?: string | null; tier?: number; brain?: string; evaluations?: boolean;
	invariants?: { stuck_px?: number; stuck_s?: number }; jobs?: number;
};

/** One run of a scenario: everything the run needs besides the brain's own flags. */
export type Cell = {
	scenario: string; stage: string; seed: number; personality: string; minutes: number; warp: number;
	/** Absolute CharacterSnapshot path, if any. */
	character?: string; tier: number; brain: string; evaluations: boolean; stuckPx?: number; stuckS?: number;
};

/** What scenarios are checked against: personality names, stage keys, the number of tiers, the CPU count. */
export type Known = { personalities: string[]; stages: string[]; tiers: number; cores?: number };

const FIELDS = new Set(["description", "stage", "seeds", "personalities", "minutes", "warp", "character", "tier", "brain",
	"evaluations", "invariants", "jobs"]);

/** Whether the evaluations run when neither the flag nor the scenario says: on for the brains that may use Jev (auto,
 * jev), off for fallback and builtin, so those runs stay deterministic and offline ("without Jev, evaluations are
 * skipped"; --evaluations=true turns them on). */
export function evaluationsByDefault(brain: string): boolean {
	return brain === "auto" || brain === "jev";
}

/** True for a training seed (1..60 and 2026); every other seed is held out or unassigned and never used here. */
export function isTrainingSeed(n: number): boolean {
	return Number.isInteger(n) && ((n >= 1 && n <= 60) || n === 2026);
}

/** The stages, tiers, personalities and CPU count of this repo. */
export function knownFacts(repo: string): Known {
	const stages = JSON.parse(fs.readFileSync(path.join(repo, "game", "data", "survivor", "stages.json"), "utf8"));
	return { personalities: personalityNames(), stages: Object.keys(stages.stages ?? {}), tiers: (stages.tiers ?? []).length,
		cores: os.availableParallelism() };
}

const isNum = (v: unknown): v is number => typeof v === "number" && Number.isFinite(v);

/** Schema errors of a scenario object (empty when valid). */
export function validateScenario(s: unknown, known: Known): string[] {
	if (typeof s !== "object" || s === null || Array.isArray(s)) return ["a scenario must be a JSON object"];
	const o = s as Record<string, unknown>;
	const errors: string[] = [];
	for (const k of Object.keys(o)) if (!FIELDS.has(k)) errors.push(`unknown field ${k}`);
	if (o.description !== undefined && typeof o.description !== "string") errors.push("description must be text");
	if (o.stage === undefined) errors.push("stage is required");
	else if (typeof o.stage !== "string" || !known.stages.includes(o.stage)) {
		errors.push(`stage ${String(o.stage)} is not a stage (${known.stages.join(", ")})`);
	}
	if (o.seeds === undefined) errors.push("seeds is required");
	else if (!Array.isArray(o.seeds) || o.seeds.length === 0) errors.push("seeds must be a non-empty array of training seeds");
	else errors.push(...seedErrors(o.seeds));
	if (o.personalities === undefined) errors.push("personalities is required");
	else if (o.personalities !== "all") {
		if (!Array.isArray(o.personalities) || o.personalities.length === 0) errors.push("personalities must be \"all\" or a non-empty array of names");
		else errors.push(...personalityErrors(o.personalities, known));
	}
	if (o.minutes === undefined) errors.push("minutes is required");
	else if (!isNum(o.minutes) || o.minutes < 0) errors.push("minutes must be a number >= 0");
	if (o.warp !== undefined && (!isNum(o.warp) || o.warp < 0)) errors.push("warp must be a number >= 0");
	if (o.character !== undefined && o.character !== null && typeof o.character !== "string") errors.push("character must be a path or null");
	if (o.tier !== undefined && (!Number.isInteger(o.tier) || (o.tier as number) < 1 || (o.tier as number) > known.tiers)) {
		errors.push(`tier must be an integer 1..${known.tiers}`);
	}
	if (typeof o.character === "string" && Number(o.tier ?? 1) >= 2) errors.push("character and tier >= 2 cannot be combined");
	if (o.brain !== undefined && !(BRAINS as readonly unknown[]).includes(o.brain)) errors.push(`brain must be one of ${BRAINS.join(", ")}`);
	if (o.evaluations !== undefined && typeof o.evaluations !== "boolean") errors.push("evaluations must be true or false");
	if (o.jobs !== undefined && (!Number.isInteger(o.jobs) || (o.jobs as number) < 1)) errors.push("jobs must be an integer >= 1");
	if (o.invariants !== undefined) {
		if (typeof o.invariants !== "object" || o.invariants === null) errors.push("invariants must be an object");
		else {
			for (const [k, v] of Object.entries(o.invariants)) {
				if (k !== "stuck_px" && k !== "stuck_s") errors.push(`unknown field invariants.${k}`);
				else if (!isNum(v) || v <= 0) errors.push(`invariants.${k} must be a number > 0`);
			}
		}
	}
	return errors;
}

function seedErrors(seeds: unknown[]): string[] {
	return seeds.filter((n) => !isTrainingSeed(Number(n)) || typeof n !== "number")
		.map((n) => `seed ${String(n)} is not a training seed (1..60, 2026); held-out ranges are never used`);
}

function personalityErrors(names: unknown[], known: Known): string[] {
	return names.filter((n) => typeof n !== "string" || !known.personalities.includes(n))
		.map((n) => `personality ${String(n)} is unknown (known: ${known.personalities.join(", ")})`);
}

/** The scenario file `name` from `dir`, or why it cannot be used (unknown name, not JSON). Not validated here. */
export function loadScenario(name: string, dir: string = SCENARIO_DIR): { scenario: Scenario } | { error: string } {
	const file = path.join(dir, `${name}.json`);
	if (!/^[a-z0-9_]+$/.test(name) || !fs.existsSync(file)) {
		const known = fs.existsSync(dir) ? fs.readdirSync(dir).filter((f) => f.endsWith(".json")).map((f) => f.slice(0, -5)).sort() : [];
		return { error: `unknown scenario ${name} (known: ${known.join(", ")})` };
	}
	try {
		return { scenario: JSON.parse(fs.readFileSync(file, "utf8")) as Scenario };
	} catch (e) {
		return { error: `scenario ${name} is not valid JSON: ${(e as Error).message}` };
	}
}

export type Resolved = { name: string; scenario: Scenario; cells: Cell[]; jobs: number; errors: string[] };

/** The cells of scenario `s` (already loaded) with the explicitly given flags of `parsed` laid over its fields.
 * `repo` resolves the scenario's character path; `cwd` resolves a --character path. */
export function resolveScenario(name: string, s: Scenario, parsed: { values: Record<string, FlagValue>; explicit: Set<string> },
	known: Known, repo: string, cwd: string = process.cwd()): Resolved {
	const errors = validateScenario(s, known);
	const { values, explicit } = parsed;
	const given = (k: string) => explicit.has(k) && values[k] !== undefined;
	const stage = given("stage") ? String(values.stage) : s.stage;
	const seeds = given("seed") ? [Number(values.seed)] : Array.isArray(s.seeds) ? s.seeds : [];
	const personalities = given("personality") ? [String(values.personality)]
		: s.personalities === "all" ? known.personalities : Array.isArray(s.personalities) ? s.personalities : [];
	if (given("seed")) errors.push(...seedErrors(seeds));
	if (given("personality")) errors.push(...personalityErrors(personalities, known));
	if (given("stage") && !known.stages.includes(stage)) errors.push(`stage ${stage} is not a stage (${known.stages.join(", ")})`);
	let character: string | undefined;
	if (given("character")) character = path.resolve(cwd, String(values.character));
	else if (typeof s.character === "string") character = path.resolve(repo, s.character);
	if (character !== undefined && !fs.existsSync(character)) errors.push(`character fixture ${character} does not exist`);
	const tier = given("tier") ? Number(values.tier) : s.tier ?? 1;
	if (given("tier") && (tier < 1 || tier > known.tiers)) errors.push(`tier must be an integer 1..${known.tiers}`);
	if (character !== undefined && tier >= 2 && (given("tier") || given("character"))) errors.push("character and tier >= 2 cannot be combined");
	const inv = s.invariants ?? {};
	const brain = given("brain") ? String(values.brain) : s.brain ?? "auto";
	const base = {
		scenario: name, stage,
		minutes: given("minutes") ? Number(values.minutes) : s.minutes,
		warp: given("warp") ? Number(values.warp) : s.warp ?? 0,
		tier, brain,
		evaluations: given("evaluations") ? values.evaluations === true : s.evaluations ?? evaluationsByDefault(brain),
		stuckPx: given("stuck-px") ? Number(values["stuck-px"]) : inv.stuck_px,
		stuckS: given("stuck-s") ? Number(values["stuck-s"]) : inv.stuck_s,
		...(character !== undefined ? { character } : {}),
	};
	const cells: Cell[] = [];
	for (const personality of personalities) for (const seed of seeds) cells.push({ ...base, personality, seed });
	const cores = known.cores ?? os.availableParallelism();
	const jobs = given("jobs") ? Math.max(1, Number(values.jobs)) : s.jobs ?? Math.max(1, Math.min(4, Math.floor(cores / 2)));
	return { name, scenario: s, cells, jobs, errors };
}
