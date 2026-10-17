// The situation buckets are computed game-side (game/tools/playtest/playtest_situation.gd). The Node side reads
// them from each decide; where it must bucket recorded numbers itself (the evaluation facts over timeline rows) it uses
// maple/situation.ts's mirror of the same thresholds, which these tests keep equal to the GDScript constants.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { SITUATION_THRESHOLDS, poolBucket, mobsBucket } from "../src/maple/situation.ts";
import { mobsWords } from "../src/maple/eval_facts.ts";

const GD = path.join(import.meta.dirname, "..", "..", "..", "game", "tools", "playtest", "playtest_situation.gd");

test("the Node bucket thresholds equal playtest_situation.gd's POOL_* and MOBS_* constants", () => {
	const gd = fs.readFileSync(GD, "utf8");
	const constant = (name: string) => {
		const m = new RegExp(`^const ${name} := ([0-9.]+)`, "m").exec(gd);
		assert.ok(m, `${name} in playtest_situation.gd`);
		return Number(m[1]);
	};
	for (const [name, value] of Object.entries(SITUATION_THRESHOLDS)) assert.equal(value, constant(name), name);
	assert.deepEqual(Object.keys(SITUATION_THRESHOLDS).sort(),
		["MOBS_CROWD", "MOBS_FEW", "MOBS_SWARM", "POOL_CRITICAL", "POOL_FULL", "POOL_LOW"]);
});

test("pool and mob buckets cut where the game's do (critical < 25%, low < 50%, full >= 95%; few 1, crowd 4, swarm 12)", () => {
	assert.deepEqual([24, 25, 49, 50, 94, 95, 100].map((v) => poolBucket(v, 100)), ["critical", "low", "low", "ok", "ok", "full", "full"]);
	assert.equal(poolBucket(0, 0), "full", "an empty pool reads full, as in the game");
	assert.deepEqual([0, 1, 3, 4, 11, 12].map(mobsBucket), ["none", "few", "few", "crowd", "crowd", "swarm"]);
	assert.deepEqual([0, 3, 4, 12].map(mobsWords), ["none", "a few", "a crowd", "a swarm"]);
});
