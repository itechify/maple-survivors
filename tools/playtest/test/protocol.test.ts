// The decision protocol's line format: parsing driver lines and serialising answers.
import { test } from "node:test";
import assert from "node:assert/strict";
import { parseLine, serializeAnswer, PREFIX, PROTOCOL_VERSION } from "../src/core/protocol.ts";

test("a prefixed line carrying a known message parses to that message", () => {
	const line = '@@PT {"v":1,"type":"decide","id":3,"kind":"card","options":[{"id":"a"}],"baseline":{"sensible":"a"}}';
	const parsed = parseLine(line);
	assert.equal(parsed.kind, "message");
	assert.equal(parsed.kind === "message" && parsed.message.type, "decide");
	assert.equal(parsed.kind === "message" && parsed.message.type === "decide" && parsed.message.id, 3);
});

test("a line without the prefix is a log line", () => {
	assert.deepEqual(parseLine("balance_run: something happened"), { kind: "log", line: "balance_run: something happened" });
	assert.deepEqual(parseLine(""), { kind: "log", line: "" });
});

test("a trailing carriage return (Windows pipes) is ignored", () => {
	const parsed = parseLine('@@PT {"v":1,"type":"hello","stage":"henesys_hg1","seed":7}\r');
	assert.equal(parsed.kind, "message");
});

test("malformed prefixed lines are protocol violations, not logs", () => {
	for (const bad of ["@@PT {not json", "@@PT [1,2]", '@@PT {"v":1}', '@@PT {"v":1,"type":"nope"}',
		'@@PT {"v":99,"type":"hello"}', '@@PT {"type":"hello"}']) {
		const parsed = parseLine(bad);
		assert.equal(parsed.kind, "invalid", bad);
		assert.ok(parsed.kind === "invalid" && parsed.error.length > 0, bad);
	}
});

test("a decide without an id or options is a protocol violation", () => {
	assert.equal(parseLine('@@PT {"v":1,"type":"decide","kind":"card","options":[]}').kind, "invalid");
	assert.equal(parseLine('@@PT {"v":1,"type":"decide","id":1,"kind":"card"}').kind, "invalid");
});

test("an answer serialises to one versioned JSON line", () => {
	const out = serializeAnswer({ id: 4, answer: "magic_claw_new", source: "fallback:sensible", confidence: null });
	assert.ok(out.endsWith("\n"));
	assert.equal(out.indexOf("\n"), out.length - 1, "exactly one line");
	assert.deepEqual(JSON.parse(out), { v: PROTOCOL_VERSION, type: "answer", id: 4, answer: "magic_claw_new",
		source: "fallback:sensible", confidence: null });
});

test("the prefix is the reserved @@PT marker", () => {
	assert.equal(PREFIX, "@@PT ");
	assert.equal(PROTOCOL_VERSION, 1);
});
