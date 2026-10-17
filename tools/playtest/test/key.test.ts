// TypeSafe API key resolution (core/key.ts): process env first, then (win32 only) the Windows user-scope variable
// through an injected reader. The key value itself is never part of a reason text.
import { test } from "node:test";
import assert from "node:assert/strict";
import { noul } from "@typesafe-ai/sdk";
import { resolveApiKey, NO_USER_KEY_ENV, withoutKey, redactSecrets } from "../src/core/key.ts";
import { JevClient, JevUnavailable } from "../src/core/jev_client.ts";

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

test("a Jev failure whose SDK message contains the key or a bearer token carries neither into the reason", async () => {
	const key = "ts_live_SECRET123";
	const fetch = async (): Promise<Response> => {
		throw new Error(`socket hang up for Authorization: Bearer ${key} (key ${key}); retry with Bearer abc.def-ghi`);
	};
	const client = new JevClient({ apiKey: key, fetch, retry: { maxRetries: 0 } });
	await assert.rejects(client.ask({ a: "b" }, { q: noul("Is it?") }), (e: unknown) => {
		assert.ok(e instanceof JevUnavailable);
		assert.ok(!e.reason.includes(key), e.reason);
		assert.ok(!e.reason.includes("abc.def-ghi"), e.reason);
		assert.ok(!e.message.includes(key), e.message);
		assert.match(e.reason, /\[redacted\]/);
		return true;
	});
});

test("redactSecrets removes every listed secret and anything shaped like a bearer token", () => {
	assert.equal(redactSecrets("x sk-1 y sk-1 Bearer t.o-k_en z", ["sk-1"]), "x [redacted] y [redacted] Bearer [redacted] z");
	assert.equal(redactSecrets("nothing secret", ["", "k"]), "nothing secret", "an empty secret is ignored");
});

test("withoutKey drops the TypeSafe key from a child environment and keeps everything else", () => {
	const env = { TYPESAFE_API_KEY: "k", PATH: "/bin", ISOLATE: "x" };
	assert.deepEqual(withoutKey(env), { PATH: "/bin", ISOLATE: "x" });
	assert.equal(env.TYPESAFE_API_KEY, "k", "the caller's env is not changed");
});
