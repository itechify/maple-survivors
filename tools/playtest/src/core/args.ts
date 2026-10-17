// The CLI flag registry (game-agnostic core). Modules define their flags with `defineFlag`; later tickets add flags
// by defining them in their own module instead of editing a central parser. Flags are `--name=value` (or `--name`
// for booleans); anything else is an error.

export type FlagKind = "string" | "int" | "number" | "bool";
export type FlagValue = string | number | boolean | undefined;
export type FlagSpec = {
	name: string;
	kind: FlagKind;
	help: string;
	default?: FlagValue;
	choices?: readonly string[];
};

/** The game-agnostic flags every playtest CLI has. */
export function defineCoreFlags(flags: FlagRegistry): FlagRegistry {
	return flags
		.define({ name: "help", kind: "bool", default: false, help: "print this help" })
		.define({ name: "out", kind: "string", help: "run directory (default evidence/agent-playtest/<stage>_s<seed>_<time>)" })
		.define({ name: "liveness-s", kind: "number", default: 60, help: "kill the game after this many seconds without output (infrastructure error)" });
}

export class FlagRegistry {
	#specs = new Map<string, FlagSpec>();

	/** Adds a flag; defining the same name twice is a programming error. */
	define(spec: FlagSpec): this {
		if (this.#specs.has(spec.name)) throw new Error(`flag --${spec.name} defined twice`);
		this.#specs.set(spec.name, spec);
		return this;
	}

	/** Parses argv into {name: value} (defaults filled in) plus one error message per bad argument. */
	parse(argv: readonly string[]): { values: Record<string, FlagValue>; errors: string[] } {
		const values: Record<string, FlagValue> = {};
		const errors: string[] = [];
		for (const spec of this.#specs.values()) values[spec.name] = spec.default;
		for (const arg of argv) {
			const m = /^--([a-z0-9-]+)(?:=(.*))?$/s.exec(arg);
			const spec = m ? this.#specs.get(m[1]) : undefined;
			if (!m || !spec) {
				errors.push(`unknown argument ${arg}`);
				continue;
			}
			const raw = m[2];
			if (spec.kind === "bool") {
				if (raw === undefined || raw === "true" || raw === "1") values[spec.name] = true;
				else if (raw === "false" || raw === "0") values[spec.name] = false;
				else errors.push(`--${spec.name} takes no value or true/false`);
				continue;
			}
			if (raw === undefined || raw === "") {
				errors.push(`--${spec.name} needs a value (--${spec.name}=...)`);
				continue;
			}
			if (spec.kind === "int" || spec.kind === "number") {
				const n = Number(raw);
				if (!Number.isFinite(n) || (spec.kind === "int" && !Number.isInteger(n))) {
					errors.push(`--${spec.name} must be ${spec.kind === "int" ? "an integer" : "a number"}, got ${raw}`);
					continue;
				}
				values[spec.name] = n;
				continue;
			}
			if (spec.choices && !spec.choices.includes(raw)) {
				errors.push(`--${spec.name} must be one of ${spec.choices.join(", ")}, got ${raw}`);
				continue;
			}
			values[spec.name] = raw;
		}
		return { values, errors };
	}

	/** One line per flag for --help. */
	help(): string {
		const lines: string[] = [];
		for (const s of this.#specs.values()) {
			const value = s.kind === "bool" ? "" : `=<${s.choices ? s.choices.join("|") : s.kind}>`;
			const def = s.default === undefined ? "" : ` (default ${String(s.default)})`;
			lines.push(`  --${s.name}${value}`.padEnd(36) + ` ${s.help}${def}`);
		}
		return lines.join("\n");
	}
}
