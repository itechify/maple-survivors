// TypeSafe API key resolution (game-agnostic core). Order: TYPESAFE_API_KEY in the process env, then on win32 the
// Windows user-scope variable (a Git Bash shell started before the key was set, or by a parent that did not pass it
// on, does not inherit it). The key is returned only to be handed to the TypeSafe client: never log it, never write
// it to a run directory, never put it in a reason text.
import { spawnSync } from "node:child_process";

export const KEY_ENV = "TYPESAFE_API_KEY";
/** Test hook: set to 1 to skip the Windows user-scope lookup (so a run can be forced onto the fallback brain). */
export const NO_USER_KEY_ENV = "AGENT_PLAYTEST_NO_USER_KEY";

export type KeyResolution = { key: string; from: "process" | "user" } | { key: null; reason: string };

export type KeyOptions = {
	env: NodeJS.ProcessEnv;
	platform?: string;
	/** Reads the user-scope variable (null or "" when unset); injected by tests. Default: readUserKeyWindows. */
	readUserKey?: () => string | null;
};

/** The API key and where it came from, or why there is none. */
export function resolveApiKey(o: KeyOptions): KeyResolution {
	const proc = (o.env[KEY_ENV] ?? "").trim();
	if (proc) return { key: proc, from: "process" };
	if ((o.platform ?? process.platform) !== "win32") return { key: null, reason: "key absent in process env" };
	if (o.env[NO_USER_KEY_ENV] === "1") {
		return { key: null, reason: `key absent in process env (user-scope lookup disabled by ${NO_USER_KEY_ENV})` };
	}
	let user: string;
	try {
		user = ((o.readUserKey ?? readUserKeyWindows)() ?? "").replace(/[\r\n]/g, "").trim();
	} catch (e) {
		return { key: null, reason: `key absent in process env; user env unreadable (${(e as Error).message})` };
	}
	return user ? { key: user, from: "user" } : { key: null, reason: "key absent in process and user env" };
}

/** The Windows user-scope TYPESAFE_API_KEY through powershell.exe ("" when unset). Throws if powershell fails. */
export function readUserKeyWindows(): string {
	const r = spawnSync("powershell.exe", ["-NoProfile", "-NonInteractive", "-Command",
		`[Environment]::GetEnvironmentVariable('${KEY_ENV}','User')`], { encoding: "utf8", windowsHide: true, timeout: 20_000 });
	if (r.error) throw new Error(`powershell.exe: ${r.error.message}`);
	if (r.status !== 0) throw new Error(`powershell.exe exited with ${r.status}`);
	return r.stdout ?? "";
}
