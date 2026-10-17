// Playtest personality names for scenarios (adapter, #98), through #97's loader (maple/personality.ts): a name is
// known when tools/playtest/personalities/<name>.json loads and validates. Shipped personalities come first in their
// SHIPPED_PERSONALITIES order, then any other valid file in name order (so "all" in a scenario covers them).
import fs from "node:fs";
import path from "node:path";
import { PERSONALITY_DIR, SHIPPED_PERSONALITIES, loadPersonality } from "./personality.ts";

/** Every valid personality in `dir`: shipped ones in their order, then the rest by name. */
export function personalityNames(dir: string = PERSONALITY_DIR): string[] {
	const files = fs.existsSync(dir) ? fs.readdirSync(dir).filter((f) => f.endsWith(".json")).map((f) => f.slice(0, -5)).sort() : [];
	const valid = files.filter((n) => loadPersonality(n, dir).personality !== undefined);
	const shipped = (SHIPPED_PERSONALITIES as readonly string[]).filter((n) => valid.includes(n));
	return [...shipped, ...valid.filter((n) => !shipped.includes(n))];
}

/** The personality file's parsed content (recorded in scenario.json next to the run's personality.json), or null. */
export function personalityFile(name: string, dir: string = PERSONALITY_DIR): unknown {
	const f = path.join(dir, `${name}.json`);
	if (!/^[a-z0-9_]+$/.test(name) || !fs.existsSync(f)) return null;
	try {
		return JSON.parse(fs.readFileSync(f, "utf8"));
	} catch {
		return null;
	}
}
