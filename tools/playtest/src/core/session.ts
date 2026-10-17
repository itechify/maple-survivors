// One playtest session (game-agnostic core): spawns the game-side driver, answers each `decide` through a brain in
// lockstep over stdin, and collects hello / findings / end. Protocol shapes: protocol.ts.
import { spawn } from "node:child_process";
import readline from "node:readline";
import { parseLine, serializeAnswer } from "./protocol.ts";
import type { DecideMessage, EndMessage, ErrorMessage, FindingMessage, HelloMessage } from "./protocol.ts";
import { redactSecrets, withoutKey } from "./key.ts";

/** What a brain returns for one decision. `reason` explains a fallback (e.g. why Jev was not used); `extra` holds
 * brain-specific facts recorded in decisions.jsonl only (probabilities, presented order, model, ...), never sent to
 * the driver. */
export type BrainAnswer = { answer: string; source: string; confidence: number | null; reason?: string;
	extra?: Record<string, unknown> };

/** Answers decisions. Implementations: maple/fallback.ts (deterministic), later Jev (#94) and replay (#98). */
export type Brain = {
	name: string;
	decide(decide: DecideMessage): BrainAnswer | Promise<BrainAnswer>;
};

/** One answered decision as the CLI saw it (a line of decisions.jsonl). */
export type DecisionRecord = {
	id: number; kind: string; tick: number | null; time: number | null; options: string[]; baseline: string | null;
	answer: string; source: string; confidence: number | null; latency_ms: number | null; reason?: string;
	fallback_reason?: string;
	[extra: string]: unknown;
};

export type SessionOptions = {
	command: string;
	args: string[];
	cwd?: string;
	env?: NodeJS.ProcessEnv;
	brain: Brain;
	/** Kill the driver after this long without a stdout/stderr line (time spent in the brain does not count). */
	livenessMs: number;
	onLine?: (line: string, stream: "stdout" | "stderr") => void;
	onDecision?: (record: DecisionRecord) => void;
	onFinding?: (finding: FindingMessage) => void;
};

export type SessionResult = {
	hello?: HelloMessage;
	end?: EndMessage;
	errors: ErrorMessage[];
	findings: FindingMessage[];
	decisions: DecisionRecord[];
	violations: string[];
	exitCode: number | null;
	signal: string | null;
	spawnError?: string;
	timedOut: boolean;
	livenessMs: number;
};

/** Runs the driver to its exit and returns everything it said. Never rejects: failures land in the result. */
export function runSession(opts: SessionOptions): Promise<SessionResult> {
	const result: SessionResult = { errors: [], findings: [], decisions: [], violations: [], exitCode: null, signal: null,
		timedOut: false, livenessMs: opts.livenessMs };
	return new Promise((resolve) => {
		let settled = false;
		const finish = () => {
			if (settled) return;
			settled = true;
			clearTimeout(timer);
			resolve(result);
		};
		const child = spawn(opts.command, opts.args, { cwd: opts.cwd, env: withoutKey(opts.env ?? process.env),
			stdio: ["pipe", "pipe", "pipe"], windowsHide: true });
		let timer: ReturnType<typeof setTimeout> | undefined;
		let thinking = false;
		const arm = () => {
			clearTimeout(timer);
			if (thinking) return;
			timer = setTimeout(() => {
				result.timedOut = true;
				child.kill();
			}, opts.livenessMs);
		};
		arm();
		child.on("error", (e) => {
			result.spawnError = e.message;
			finish();
		});
		child.stdin.on("error", () => {}); // EPIPE after the driver died: the missing `end` reports it
		let queue = Promise.resolve();
		const answer = async (decide: DecideMessage) => {
			thinking = true;
			clearTimeout(timer);
			const t0 = performance.now();
			let reply: BrainAnswer;
			try {
				reply = await opts.brain.decide(decide);
			} catch (e) {
				const baseline = decide.baseline.sensible ?? decide.options[0]?.id ?? "";
				reply = { answer: baseline, source: "baseline", confidence: null, reason: redactSecrets(`brain ${opts.brain.name} failed: ${(e as Error).message}`, []) };
			}
			const latency = performance.now() - t0;
			if (child.stdin.writable) child.stdin.write(serializeAnswer({ id: decide.id, answer: reply.answer, source: reply.source,
				confidence: reply.confidence }));
			thinking = false;
			arm();
			const record: DecisionRecord = { id: decide.id, kind: decide.kind, tick: decide.tick ?? null, time: decide.time ?? null,
				options: decide.options.map((o) => String(o.id)), baseline: decide.baseline.sensible ?? null,
				answer: reply.answer, source: reply.source, confidence: reply.confidence,
				latency_ms: Math.round(latency * 1000) / 1000, ...(reply.reason ? { reason: reply.reason } : {}),
				...(reply.extra ?? {}) };
			result.decisions.push(record);
			opts.onDecision?.(record);
		};
		const onStdout = (raw: string) => {
			arm();
			const parsed = parseLine(raw);
			if (parsed.kind === "log") {
				opts.onLine?.(parsed.line, "stdout");
				return;
			}
			opts.onLine?.(raw.replace(/\r$/, ""), "stdout");
			if (parsed.kind === "invalid") {
				result.violations.push(parsed.error);
				return;
			}
			const msg = parsed.message;
			switch (msg.type) {
				case "hello": result.hello = msg; break;
				case "decide": queue = queue.then(() => answer(msg)); break;
				case "finding": result.findings.push(msg); opts.onFinding?.(msg); break;
				case "end": result.end = msg; break;
				case "error": result.errors.push(msg); break;
			}
		};
		readline.createInterface({ input: child.stdout }).on("line", onStdout);
		readline.createInterface({ input: child.stderr }).on("line", (line) => {
			arm();
			opts.onLine?.(line, "stderr");
		});
		child.on("close", (code, signal) => {
			result.exitCode = code;
			result.signal = signal;
			queue.then(finish, finish);
		});
	});
}

/** Infrastructure failures of a session (exit code 2): could not start, hung, protocol broken, no end, bad exit. */
export function infraErrors(r: SessionResult): string[] {
	const out: string[] = [];
	if (r.spawnError) out.push(`could not start the driver: ${r.spawnError}`);
	if (r.timedOut) out.push(`no output from the driver for ${r.livenessMs / 1000} s (liveness timeout); killed`);
	for (const v of r.violations) out.push(`protocol violation: ${v}`);
	for (const e of r.errors) out.push(`driver error ${e.reason}: ${e.message ?? ""}`.trim());
	if (!r.spawnError && !r.end) out.push(`no end message from the driver (exit code ${r.exitCode ?? r.signal ?? "none"})`);
	if (r.end && r.exitCode !== 0) out.push(`the driver exited with code ${r.exitCode ?? r.signal} after its end message`);
	return out;
}
