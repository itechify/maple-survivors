// The seeded option shuffle (core/shuffle.ts): reproducible from (run seed, decision id), a permutation of the input.
import { test } from "node:test";
import assert from "node:assert/strict";
import { seededShuffle } from "../src/core/shuffle.ts";

const items = ["a", "b", "c", "d", "e"];

test("the same run seed and decision id give the same order", () => {
	assert.deepEqual(seededShuffle(items, 2026, 7), seededShuffle(items, 2026, 7));
});

test("the result is a permutation and the input is untouched", () => {
	const out = seededShuffle(items, 2026, 7);
	assert.deepEqual([...out].sort(), items);
	assert.deepEqual(items, ["a", "b", "c", "d", "e"]);
});

test("different decisions get different orders, and the first option is not always first", () => {
	const orders = new Set<string>();
	const firsts = new Set<string>();
	for (let id = 1; id <= 40; id++) {
		const o = seededShuffle(items, 2026, id);
		orders.add(o.join(""));
		firsts.add(o[0]);
	}
	assert.ok(orders.size > 10, `only ${orders.size} distinct orders`);
	assert.equal(firsts.size, items.length, "every option leads some decision");
	assert.notDeepEqual(seededShuffle(items, 1, 3), seededShuffle(items, 2, 3), "the run seed matters");
});
