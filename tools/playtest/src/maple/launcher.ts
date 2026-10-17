// Launching the Maple Survivors playtest driver (adapter): resolves the pinned Godot console exe the way
// scripts/godot.sh does (never downloads; run `bash scripts/godot.sh --version` once for that), prepares the project
// (an ISOLATE mirror under _scratch/godot_runs/<name>/game, like scripts/test.sh), runs the import pass that registers
// class_name scripts, and builds the driver command line.
import fs from "node:fs";
import path from "node:path";
import { spawn } from "node:child_process";
import type { InvariantChecks } from "./invariant_flags.ts";
import { withoutKey } from "../core/key.ts";

export const GODOT_VERSION = "4.7.2";
export const DRIVER = "res://tools/playtest/playtest_driver.gd";

/** The Godot console exe: $GODOT, else the MapleSurvivors / MisoStory install of GODOT_VERSION. */
export function resolveGodot(env: NodeJS.ProcessEnv, platform: string = process.platform): { exe: string } | { error: string } {
	const version = env.GODOT_VERSION || GODOT_VERSION;
	if (env.GODOT) {
		return fs.existsSync(env.GODOT) ? { exe: env.GODOT } : { error: `Godot not found: GODOT=${env.GODOT} does not exist` };
	}
	const win = platform === "win32";
	const root = win ? env.LOCALAPPDATA || path.join(env.USERPROFILE || env.HOME || "", "AppData", "Local")
		: env.XDG_DATA_HOME || path.join(env.HOME || "", ".local", "share");
	const name = win ? `Godot_v${version}-stable_win64_console.exe` : `Godot_v${version}-stable_linux.x86_64`;
	const candidates = ["MapleSurvivors", "MisoStory"].map((p) => path.join(root, p, "godot", version, name));
	const exe = candidates.find((c) => fs.existsSync(c));
	return exe ? { exe } : { error: `Godot ${version} not found (looked for ${candidates.join(", ")}); run \`bash scripts/godot.sh --version\` once to install it, or set GODOT` };
}

/** The Godot project to run: game/, or with ISOLATE=<name> a private mirror of it (synced now). */
export function prepareProject(repo: string, env: NodeJS.ProcessEnv): string {
	const game = path.join(repo, "game");
	if (!env.ISOLATE) return game;
	const dest = path.join(repo, "_scratch", "godot_runs", env.ISOLATE, "game");
	mirrorProject(game, dest);
	return dest;
}

/** Copies `src` over `dest` (without .godot/ and export/ at the top) and deletes files that no longer exist in `src`. */
export function mirrorProject(src: string, dest: string): void {
	const skip = new Set([path.join(src, ".godot"), path.join(src, "export")]);
	fs.mkdirSync(dest, { recursive: true });
	fs.rmSync(path.join(dest, "export"), { recursive: true, force: true });
	fs.cpSync(src, dest, { recursive: true, force: true, filter: (p) => !skip.has(p) });
	const prune = (dir: string) => {
		for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
			const p = path.join(dir, entry.name);
			if (dir === dest && entry.name === ".godot") continue;
			const twin = path.join(src, path.relative(dest, p));
			if (entry.isDirectory()) {
				if (fs.existsSync(twin)) prune(p);
				else fs.rmSync(p, { recursive: true, force: true });
			} else if (!fs.existsSync(twin)) fs.rmSync(p, { force: true });
		}
	};
	prune(dest);
}

/** The headless import pass (registers new class_name scripts before the driver loads them), without blocking the
 * event loop (parallel matrix cells keep answering their drivers meanwhile). Failures are ignored, as in
 * scripts/test.sh: a real problem shows up when the driver runs. Godot gets `env` without the TypeSafe key. */
export function importProjectAsync(exe: string, project: string, env: NodeJS.ProcessEnv = process.env): Promise<void> {
	return new Promise((resolve) => {
		const child = spawn(exe, ["--headless", "--path", project, "--import"], { env: withoutKey(env), stdio: "ignore",
			windowsHide: true });
		const timer = setTimeout(() => child.kill(), 600_000);
		const done = () => {
			clearTimeout(timer);
			resolve();
		};
		child.on("error", done);
		child.on("close", done);
	});
}

export type DriverOptions = {
	stage: string; seed: number; minutes: number; personality: string; brain: "stdio" | "builtin";
	/** Run directory: the driver writes timeline.jsonl there. */
	out?: string;
	/** Absolute CharacterSnapshot path (#98): the round starts from it. */
	character?: string;
	/** Tier chain target (#98): >= 2 chains from tier 1 through this tier. */
	tier?: number;
	/** The personality's driver params (personality.json in the run directory, #97). */
	personalityFile?: string;
} & InvariantChecks;

/** Godot arguments that run the playtest driver on `project`. */
export function driverArgs(project: string, o: DriverOptions): string[] {
	const args = ["--headless", "--path", project, "--script", DRIVER, "--", `--stage=${o.stage}`, `--seed=${o.seed}`,
		`--minutes=${o.minutes}`, `--brain=${o.brain}`, `--personality=${o.personality}`];
	if (o.out) args.push(`--out=${o.out.replaceAll("\\", "/")}`);
	if (o.stuckPx !== undefined) args.push(`--stuck-px=${o.stuckPx}`);
	if (o.stuckS !== undefined) args.push(`--stuck-s=${o.stuckS}`);
	if (o.injectFinding) args.push(`--inject-finding=${o.injectFinding}`);
	if (o.character) args.push(`--character=${o.character.replaceAll("\\", "/")}`);
	if (o.tier !== undefined && o.tier >= 2) args.push(`--tier=${o.tier}`);
	if (o.personalityFile) args.push(`--personality-file=${o.personalityFile.replaceAll("\\", "/")}`);
	return args;
}
