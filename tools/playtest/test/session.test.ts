// A session against a fake driver process that speaks the decision protocol.
import { test } from "node:test";
import assert from "node:assert/strict";
import path from "node:path";
import { runSession, infraErrors } from "../src/core/session.ts";
import type { Brain } from "../src/core/session.ts";
import { sensibleBrain } from "../src/maple/fallback.ts";

const FAKE = path.join(import.meta.dirname, "..", "fixtures", "fake_driver.ts");
const fake = (mode: string) => ({ command: process.execPath, args: [FAKE, `--mode=${mode}`] });

test("each decide is answered on stdin and the driver's end arrives", async () => {
	const logs: string[] = [];
	const result = await runSession({ ...fake("ok"), brain: sensibleBrain, livenessMs: 10_000,
		onLine: (line) => logs.push(line) });
	assert.deepEqual(infraErrors(result), []);
	assert.equal(result.hello?.stage, "henesys_hg1");
	assert.equal(result.end?.record.state, "TIMEOUT");
	assert.deepEqual(result.decisions.map((d) => [d.id, d.kind, d.answer, d.source]),
		[[1, "card", "b", "fallback:sensible"], [2, "job", "200", "fallback:sensible"]]);
	assert.ok(result.decisions.every((d) => typeof d.latency_ms === "number" && d.latency_ms >= 0));
	const received = result.end?.record.received as Array<Record<string, unknown>>;
	assert.deepEqual(received.map((r) => [r.v, r.type, r.id, r.answer]), [[1, "answer", 1, "b"], [1, "answer", 2, "200"]],
		"the driver read one versioned answer line per decide");
	assert.ok(logs.includes("fake_driver: a log line"), "non-protocol lines reach the log");
	assert.equal(result.exitCode, 0);
});

test("a brain that answers something else is passed through as its own source", async () => {
	const firstOption: Brain = { name: "first", decide: (d) => ({ answer: d.options[0].id, source: "test:first", confidence: 0.9 }) };
	const result = await runSession({ ...fake("ok"), brain: firstOption, livenessMs: 10_000 });
	assert.deepEqual(result.decisions.map((d) => d.answer), ["a", "200"]);
	assert.deepEqual(result.decisions.map((d) => d.confidence), [0.9, 0.9]);
});

test("a driver that exits without an end message is an infrastructure error", async () => {
	const result = await runSession({ ...fake("no_end"), brain: sensibleBrain, livenessMs: 10_000 });
	assert.equal(result.end, undefined);
	assert.ok(infraErrors(result).some((e) => e.includes("no end message")), infraErrors(result).join("; "));
});

test("a silent driver is killed by the liveness timeout", async () => {
	const result = await runSession({ ...fake("hang"), brain: sensibleBrain, livenessMs: 400 });
	assert.equal(result.timedOut, true);
	assert.ok(infraErrors(result).some((e) => e.includes("no output")), infraErrors(result).join("; "));
});

test("a driver error message is an infrastructure error naming its reason", async () => {
	const result = await runSession({ ...fake("error"), brain: sensibleBrain, livenessMs: 10_000 });
	assert.ok(infraErrors(result).some((e) => e.includes("cache_missing")), infraErrors(result).join("; "));
	assert.equal(result.exitCode, 2);
});

test("a command that cannot start is an infrastructure error", async () => {
	const result = await runSession({ command: path.join(import.meta.dirname, "no_such_godot.exe"), args: [],
		brain: sensibleBrain, livenessMs: 10_000 });
	assert.ok(result.spawnError);
	assert.ok(infraErrors(result).length > 0);
});
