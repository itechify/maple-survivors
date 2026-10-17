// TypeSafe API key resolution (core/key.ts): process env first, then (win32 only) the Windows user-scope variable
// through an injected reader. The key value itself is never part of a reason text.
import { test } from "node:test";
import assert from "node:assert/strict";
import { resolveApiKey, NO_USER_KEY_ENV } from "../src/core/key.ts";

const reader = (value: string | null) => {
	const calls: number[] = [];
	return { calls, read: () => { calls.push(1); return value; } };
};

test("the process env wins and the user-scope reader is not consulted", () => {
	const r = reader("user-key");
	const got = resolveApiKey({ env: { TYPESAFE_API_KEY: "proc-key" }, platform: "win32", readUserKey: r.read });
	assert.deepEqual(got, { key: "proc-key", from: "process" });
	assert.equal(r.calls.length, 0);
});

test("on win32 an unset or blank process key falls back to the user-scope variable, trimmed of CR/LF", () => {
	for (const env of [{}, { TYPESAFE_API_KEY: "" }, { TYPESAFE_API_KEY: "  " }]) {
		const r = reader("user-key\r\n");
		assert.deepEqual(resolveApiKey({ env, platform: "win32", readUserKey: r.read }), { key: "user-key", from: "user" });
		assert.equal(r.calls.length, 1);
	}
});

test("no key anywhere gives a reason naming both places, never a key", () => {
	const got = resolveApiKey({ env: {}, platform: "win32", readUserKey: reader("\r\n").read });
	assert.equal(got.key, null);
	assert.equal(got.key === null && got.reason, "key absent in process and user env");
});

test("off Windows there is no user scope: the reader is not consulted", () => {
	const r = reader("user-key");
	const got = resolveApiKey({ env: {}, platform: "linux", readUserKey: r.read });
	assert.equal(r.calls.length, 0);
	assert.equal(got.key === null && got.reason, "key absent in process env");
});

test("the test hook disables the user-scope lookup and the reason says so", () => {
	const r = reader("user-key");
	const got = resolveApiKey({ env: { TYPESAFE_API_KEY: "", [NO_USER_KEY_ENV]: "1" }, platform: "win32", readUserKey: r.read });
	assert.equal(r.calls.length, 0);
	assert.equal(got.key === null && got.reason, `key absent in process env (user-scope lookup disabled by ${NO_USER_KEY_ENV})`);
});

test("a failing user-scope reader counts as no key", () => {
	const got = resolveApiKey({ env: {}, platform: "win32", readUserKey: () => { throw new Error("no powershell"); } });
	assert.equal(got.key === null && got.reason, "key absent in process env; user env unreadable (no powershell)");
});
