// Playtest personality names (adapter). Hook for #97: a personality is a data file tools/playtest/personalities/
// <name>.json; `sensible` (the existing bot's choices) is always valid, even before any file exists. Scenario files
// and --personality are validated against `personalityNames`; #97's loader reads the files themselves.
import fs from "node:fs";
import path from "node:path";

export const PERSONALITY_DIR = path.resolve(import.meta.dirname, "..", "..", "personalities");
export const SENSIBLE = "sensible";

/** Every known personality: `sensible` first, then each personalities/<name>.json in name order. */
export function personalityNames(dir: string = PERSONALITY_DIR): string[] {
	const files = fs.existsSync(dir) ? fs.readdirSync(dir).filter((f) => f.endsWith(".json")).map((f) => f.slice(0, -5)).sort() : [];
	return [SENSIBLE, ...files.filter((n) => n !== SENSIBLE)];
}

/** The personality file's parsed content (recorded in scenario.json, so a replay shows what the run used), or null. */
export function personalityFile(name: string, dir: string = PERSONALITY_DIR): unknown {
	const f = path.join(dir, `${name}.json`);
	if (!fs.existsSync(f)) return null;
	const text = fs.readFileSync(f, "utf8");
	try {
		return JSON.parse(text);
	} catch {
		return text;
	}
}
