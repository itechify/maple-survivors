// docs/PLAYTESTING.md documents every CLI flag: each flag --help lists has a row in the guide's Flags table.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { cliFlags } from "../src/cli.ts";

const GUIDE = path.join(import.meta.dirname, "..", "..", "..", "docs", "PLAYTESTING.md");

test("every --help flag has a row in PLAYTESTING.md's Flags table", () => {
	const guide = fs.readFileSync(GUIDE, "utf8");
	const section = guide.split("\n## Flags\n")[1]?.split("\n## ")[0];
	assert.ok(section, "a Flags section");
	const rows = section.split("\n").filter((l) => l.startsWith("| `--"));
	const documented = new Set(rows.flatMap((r) => [...r.split(" | ")[0].matchAll(/`--([a-z0-9-]+)/g)].map((m) => m[1])));
	const flags = [...cliFlags().help().matchAll(/^ {2}--([a-z0-9-]+)/gm)].map((m) => m[1]);
	assert.ok(flags.length > 20);
	assert.deepEqual(flags.filter((f) => !documented.has(f)), [], "flags missing from the Flags table");
	assert.deepEqual([...documented].filter((f) => !flags.includes(f)), [], "documented flags the CLI does not have");
});
