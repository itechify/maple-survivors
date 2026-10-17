// The run directory writer (game-agnostic core): appends game.log and decisions.jsonl as the session runs and
// writes JSON files. Every file written is remembered for the report's file list.
import fs from "node:fs";
import path from "node:path";

export class RunRecorder {
	readonly dir: string;
	#files = new Set<string>();

	constructor(dir: string) {
		this.dir = dir;
		fs.mkdirSync(dir, { recursive: true });
	}

	/** Appends one line to game.log (the driver's stdout/stderr and the CLI's own notes). */
	log(line: string): void {
		this.#append("game.log", line);
	}

	/** Appends one JSON line to `name` (e.g. decisions.jsonl). */
	jsonl(name: string, value: unknown): void {
		this.#append(name, JSON.stringify(value));
	}

	/** Writes `name` as pretty JSON. */
	json(name: string, value: unknown): void {
		this.text(name, JSON.stringify(value, null, "\t") + "\n");
	}

	/** Writes `name` with text content. */
	text(name: string, content: string): void {
		fs.writeFileSync(path.join(this.dir, name), content);
		this.#files.add(name);
	}

	/** Makes sure `name` exists (an empty decisions.jsonl still belongs in the run directory). */
	touch(name: string): void {
		fs.appendFileSync(path.join(this.dir, name), "");
		this.#files.add(name);
	}

	/** Lists `name` among the run's files if something else (the game-side driver) wrote it. */
	adopt(name: string): void {
		if (fs.existsSync(path.join(this.dir, name))) this.#files.add(name);
	}

	/** The files written so far, sorted. */
	files(): string[] {
		return [...this.#files].sort();
	}

	#append(name: string, line: string): void {
		fs.appendFileSync(path.join(this.dir, name), line + "\n");
		this.#files.add(name);
	}
}
