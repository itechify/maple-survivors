// Scenario files (maple/scenario.ts): schema validation, the shipped scenarios, and CLI flags overriding scenario
// fields. No Godot, no network.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { validateScenario, loadScenario, resolveScenario, SCENARIO_DIR, isTrainingSeed } from "../src/maple/scenario.ts";
import { FlagRegistry, defineCoreFlags } from "../src/core/args.ts";
import { defineMapleFlags } from "../src/maple/flags.ts";
import { defineInvariantFlags } from "../src/maple/invariant_flags.ts";
import { defineJevFlags } from "../src/maple/jev_flags.ts";
import { defineScenarioFlags } from "../src/maple/scenario_flags.ts";
import { personalityNames } from "../src/maple/personalities.ts";
import { SHIPPED_PERSONALITIES } from "../src/maple/personality.ts";

test("scenario personality names come from #97's loader: the six shipped files, in their order", () => {
	assert.deepEqual(personalityNames(), [...SHIPPED_PERSONALITIES]);
	const dir = fs.mkdtempSync(path.join(os.tmpdir(), "personalities-"));
	fs.writeFileSync(path.join(dir, "broken.json"), JSON.stringify({ name: "broken" }));
	assert.deepEqual(personalityNames(dir), [], "a file that does not validate is not a known personality");
});

const REPO = path.resolve(import.meta.dirname, "..", "..", "..");
const KNOWN = { personalities: ["sensible", "aggressive"], stages: ["henesys_hg1", "tree_that_grew_1", "dark_cave"], tiers: 2 };
const flags = () => defineScenarioFlags(defineInvariantFlags(defineJevFlags(defineMapleFlags(defineCoreFlags(new FlagRegistry())))));
const parse = (argv: string[]) => flags().parse(argv);
const GOOD = { description: "d", stage: "henesys_hg1", seeds: [1, 2, 2026], personalities: ["sensible"], minutes: 10 };

test("a minimal scenario is valid; unknown keys, missing fields and bad values are named", () => {
	assert.deepEqual(validateScenario(GOOD, KNOWN), []);
	const errors = validateScenario({ stage: "nowhere", seeds: [], personalities: ["nobody"], minutes: -1, brain: "magic",
		jobs: 0, tier: 3, warp: "x", invariants: { stuck_px: 0, other: 1 }, colour: "red" }, KNOWN);
	for (const re of [/unknown field colour/, /stage nowhere is not a stage/, /seeds must be a non-empty array/,
		/personality nobody is unknown \(known: sensible, aggressive\)/, /minutes must be a number >= 0/, /brain must be one of/,
		/jobs must be an integer >= 1/, /tier must be an integer 1\.\.2/, /warp must be a number >= 0/,
		/invariants\.stuck_px must be a number > 0/, /unknown field invariants\.other/]) {
		assert.ok(errors.some((e) => re.test(e)), `${re} in ${errors.join("; ")}`);
	}
	assert.match(validateScenario({ stage: "henesys_hg1", personalities: ["sensible"], minutes: 1 }, KNOWN).join(), /seeds is required/);
});

test("held-out seeds are rejected; only training seeds 1..60 and 2026 are allowed", () => {
	assert.ok([1, 2, 60, 2026].every(isTrainingSeed));
	assert.ok(![0, 61, 101, 130, 201, 601, 701, 730].some(isTrainingSeed));
	const errors = validateScenario({ ...GOOD, seeds: [2, 101] }, KNOWN);
	assert.match(errors.join(), /seed 101 is not a training seed \(1\.\.60, 2026\)/);
});

test("a character fixture cannot be combined with a tier chain", () => {
	assert.match(validateScenario({ ...GOOD, tier: 2, character: "x.json" }, KNOWN).join(), /character and tier >= 2 cannot be combined/);
});

test("\"all\" personalities expands to every known personality", () => {
	assert.deepEqual(validateScenario({ ...GOOD, personalities: "all" }, KNOWN), []);
	const r = resolveScenario("m", { ...GOOD, personalities: "all" }, parse([]), KNOWN, REPO);
	assert.deepEqual(r.cells.map((c) => c.personality), ["sensible", "sensible", "sensible", "aggressive", "aggressive", "aggressive"]);
});

test("every shipped scenario is valid and uses training seeds only", () => {
	const names = fs.readdirSync(SCENARIO_DIR).filter((f) => f.endsWith(".json")).map((f) => f.slice(0, -5)).sort();
	assert.deepEqual(names, ["fixture_dark_cave", "henesys_full", "matrix", "smoke", "tier_chain"]);
	for (const n of names) {
		const s = loadScenario(n);
		assert.ok(!("error" in s), `${n}: ${"error" in s ? s.error : ""}`);
		if ("scenario" in s) assert.deepEqual(validateScenario(s.scenario, { ...KNOWN, personalities: personalityNames() }), [], n);
	}
	const matrix = loadScenario("matrix");
	assert.ok("scenario" in matrix);
	assert.deepEqual(matrix.scenario.personalities, [...SHIPPED_PERSONALITIES], "the matrix covers every shipped personality");
	assert.match(String((loadScenario("nope") as { error: string }).error), /unknown scenario nope \(known: fixture_dark_cave, henesys_full, matrix, smoke, tier_chain\)/);
});

test("the smoke scenario is the CLI's defaults, so no-argument runs keep their meaning", () => {
	const s = loadScenario("smoke");
	assert.ok("scenario" in s);
	const { values } = parse([]);
	const [cell] = resolveScenario("smoke", s.scenario, parse([]), KNOWN, REPO).cells;
	assert.deepEqual([cell.stage, cell.seed, cell.minutes, cell.personality, cell.brain],
		[values.stage, values.seed, values.minutes, values.personality, values.brain]);
});

test("explicit CLI flags override scenario fields; defaults do not", () => {
	const scenario = { ...GOOD, stage: "tree_that_grew_1", brain: "fallback", warp: 30, invariants: { stuck_px: 30, stuck_s: 25 } };
	const plain = resolveScenario("m", scenario, parse([]), KNOWN, REPO);
	assert.equal(plain.cells.length, 3);
	assert.deepEqual(plain.cells.map((c) => [c.stage, c.seed, c.minutes, c.brain, c.warp, c.stuckPx, c.stuckS]), [
		["tree_that_grew_1", 1, 10, "fallback", 30, 30, 25], ["tree_that_grew_1", 2, 10, "fallback", 30, 30, 25],
		["tree_that_grew_1", 2026, 10, "fallback", 30, 30, 25]]);
	const over = resolveScenario("m", scenario, parse(["--seed=7", "--minutes=2", "--brain=builtin", "--stage=henesys_hg1",
		"--personality=aggressive", "--stuck-s=9", "--warp=0"]), KNOWN, REPO);
	assert.deepEqual(over.cells.map((c) => [c.stage, c.seed, c.minutes, c.brain, c.personality, c.warp, c.stuckPx, c.stuckS]),
		[["henesys_hg1", 7, 2, "builtin", "aggressive", 0, 30, 9]]);
	assert.deepEqual(over.errors, []);
});

test("evaluations default on for the auto and jev brains and off for fallback and builtin; explicit values win", () => {
	const cell = (argv: string[], s: Record<string, unknown> = {}) =>
		resolveScenario("m", { ...GOOD, ...s }, parse(argv), KNOWN, REPO).cells[0].evaluations;
	assert.deepEqual(["auto", "jev", "fallback", "builtin"].map((b) => cell([`--brain=${b}`])), [true, true, false, false]);
	assert.deepEqual(["auto", "jev", "fallback", "builtin"].map((b) => cell([], { brain: b })), [true, true, false, false],
		"a scenario's brain field decides the default too");
	assert.equal(cell(["--brain=fallback", "--evaluations=true"]), true, "--evaluations=true turns them on");
	assert.equal(cell(["--brain=builtin"], { evaluations: true }), true, "a scenario's explicit evaluations field turns them on");
	assert.equal(cell(["--brain=jev", "--evaluations=false"]), false);
});

test("CLI values are validated like scenario values (held-out seed, unknown personality)", () => {
	const r = resolveScenario("m", GOOD, parse(["--seed=101", "--personality=nobody"]), KNOWN, REPO);
	assert.match(r.errors.join(), /seed 101 is not a training seed/);
	assert.match(r.errors.join(), /personality nobody is unknown/);
});

test("a scenario character path is resolved against the repo, a CLI one against the working directory", () => {
	const fixture = "game/tests/fixtures/characters/lv35_magician_2nd.json";
	const fromFile = resolveScenario("f", { ...GOOD, seeds: [1], stage: "dark_cave", character: fixture }, parse([]), KNOWN, REPO);
	assert.equal(fromFile.cells[0].character, path.join(REPO, fixture));
	const fromCli = resolveScenario("f", GOOD, parse([`--character=${fixture}`]), KNOWN, REPO, REPO);
	assert.equal(fromCli.cells[0].character, path.join(REPO, fixture));
	const missing = resolveScenario("f", { ...GOOD, character: "no/such.json" }, parse([]), KNOWN, REPO);
	assert.match(missing.errors.join(), /character fixture .*such\.json does not exist/);
});

test("jobs defaults to min(4, cores / 2) and the scenario or --jobs overrides it", () => {
	assert.equal(resolveScenario("m", GOOD, parse([]), { ...KNOWN, cores: 16 }, REPO).jobs, 4);
	assert.equal(resolveScenario("m", GOOD, parse([]), { ...KNOWN, cores: 2 }, REPO).jobs, 1);
	assert.equal(resolveScenario("m", { ...GOOD, jobs: 3 }, parse([]), { ...KNOWN, cores: 16 }, REPO).jobs, 3);
	assert.equal(resolveScenario("m", { ...GOOD, jobs: 3 }, parse(["--jobs=2"]), { ...KNOWN, cores: 16 }, REPO).jobs, 2);
});
