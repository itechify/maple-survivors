// Not a test file: kept outside test/ so `node --test` does not run it.
// A tiny stand-in for game/tools/playtest/playtest_driver.gd that speaks the decision protocol (synthetic, no Godot).
//   node fake_driver.ts --mode=ok|no_end|hang|error|eof
//   ok      hello, a card decide, a job decide, end (record.received echoes the answer lines it read)
//   no_end  hello, then exits 0 without an end message
//   hang    hello, then goes silent (liveness timeout)
//   error   hello, error {reason: "cache_missing"}, exit 2
//   findings        like ok, plus two streamed findings and an end whose findings carry final counts
//   findings_no_end hello, one streamed finding, exit 0 without an end message
//   script_error    like ok, plus a SCRIPT ERROR on stderr
//   stall           hello, one decide, then silent after the answer (liveness timeout mid-round)
//   tactics hello, three tactic decides (calm map, drops near, critical HP), end with a fixed record.tactics
//   chain   like ok, but the end record is a tier chain (rounds[] with two round records)
//   dead / dead_findings / cleared  like ok, but the round is fixtures/run_fixtures.ts deadRun / clearedRun: its record,
//           and its timeline.jsonl and hits.jsonl written into the run directory (the --personality-file's directory);
//           dead_findings also streams the stuck finding (#99)
// Like the real driver, an answer that is not an offered option applies the baseline (fallback_reason). The job
// decide comes at tick 150 instead of 120 when the card answer was "a", and the fingerprint carries the applied
// answers, so a replay with a changed answer diverges. record.isolate echoes the ISOLATE env variable.
// Any other argument is echoed in hello.args so tests can check what the launcher passed.
import fs from "node:fs";
import readline from "node:readline";
import path from "node:path";
import { deadRun, clearedRun } from "./run_fixtures.ts";

const TACTICS = ["kite", "aggressive", "defensive", "explore", "collect", "hold"].map((id) => ({ id, name: id }));
const CALM = { hp: "full", mp: "full", mobs_near: "none", mobs_near_step: 0, boss: "none", potions_hp: "few",
	potions_mp: "few", drops_near: "none", drops_above: "none", phase: "early", platform: 0, recent_hits: "none" };
const tacticDecide = (id: number, time: number, trigger: string, current: string, buckets: Record<string, unknown>) => ({
	id, kind: "tactic", tick: time * 60, time, options: TACTICS, baseline: { sensible: "kite" },
	situation: { level: 3, buckets: { ...CALM, ...buckets }, tactic: { current, trigger, held_s: 0, switches: id - 1 } } });
const TACTIC_DECIDES = [
	tacticDecide(1, 0, "start", "kite", {}),
	tacticDecide(2, 8, "checkpoint", "explore", { drops_near: "some" }),
	tacticDecide(3, 20, "hp_critical", "collect", { hp: "critical" }),
];
const TACTICS_RECORD = {
	seconds: { explore: 96, collect: 84, defensive: 60 }, shares: { explore: 0.4, collect: 0.35, defensive: 0.25 },
	switches: 3, decisions: 3, triggers: { start: 1, checkpoint: 1, hp_critical: 1 },
	log: [
		{ tick: 0, time: 0, from: "kite", to: "explore", trigger: "start", source: "fallback:tactic-rules" },
		{ tick: 480, time: 8, from: "explore", to: "collect", trigger: "checkpoint", source: "fallback:tactic-rules" },
		{ tick: 1200, time: 20, from: "collect", to: "defensive", trigger: "hp_critical", source: "fallback:tactic-rules" },
	],
};

const mode = (process.argv.find((a) => a.startsWith("--mode=")) ?? "--mode=ok").slice(7);
/** Like the real driver: hello echoes the --personality-file content (not its path) as personality_params. */
function personalityParams(): unknown {
	const arg = process.argv.find((a) => a.startsWith("--personality-file="));
	if (!arg) return {};
	try {
		return JSON.parse(fs.readFileSync(arg.slice("--personality-file=".length), "utf8"));
	} catch {
		return null;
	}
}
const send = (msg: Record<string, unknown>) => process.stdout.write("@@PT " + JSON.stringify({ v: 1, ...msg }) + "\n");
const lines = readline.createInterface({ input: process.stdin })[Symbol.asyncIterator]();
const read = async (): Promise<string> => {
	const next = await lines.next();
	return next.done ? "" : next.value;
};

send({ type: "hello", game: "fake", stage: "henesys_hg1", seed: 2026, minutes: 3, personality: "sensible",
	brain: "stdio", args: process.argv.slice(2).filter((a) => !a.startsWith("--personality-file=")),
	key_in_env: Boolean(process.env.TYPESAFE_API_KEY), personality_params: personalityParams() });
console.log("fake_driver: a log line");
const stuck = { kind: "stuck", severity: "warning", tick: 1500, time: 25, count: 1,
	message: "the player stayed inside 24 px for 20 s while pressing movement (90% of ticks), tactic kite",
	snapshot: { x: 512, y: -40, fh: 7, platform: 2, hp: 50, max_hp: 50, mp: 5, max_mp: 5, level: 3, job: 0,
		tactic: "kite", state: "PLAYING", mobs: [{ mob: 100100, d: 30, x: 540, y: -40, boss: false }] } };
const hp = { kind: "hp_out_of_range", severity: "error", tick: 3600, time: 60, count: 1, message: "HP 60 outside 0..50",
	snapshot: { x: 0, y: 0, fh: 1, platform: 0, hp: 60, max_hp: 50, mp: 5, max_mp: 5, level: 4, job: 0, tactic: "kite",
		state: "PLAYING", mobs: [] } };
if (mode === "findings" || mode === "findings_no_end" || mode === "dead_findings") send({ type: "finding", ...stuck });
if (mode === "no_end" || mode === "findings_no_end") process.exit(0);
if (mode === "script_error") {
	process.stderr.write("SCRIPT ERROR: Invalid access to property or key 'fh' on a base object of type 'Nil'.\n");
	process.stderr.write("          at: _step (res://scripts/sim/run_world.gd:612)\n");
}
if (mode === "stall") {
	send({ type: "decide", id: 1, kind: "card", tick: 60, time: 1, situation: {}, options: [{ id: "a" }], baseline: { sensible: "a" } });
	await read();
	setInterval(() => {}, 1000);
} else if (mode === "hang") setInterval(() => {}, 1000);
else if (mode === "error") {
	send({ type: "error", reason: "cache_missing", message: "the asset cache lacks the map" });
	process.exit(2);
} else {
	const received: unknown[] = [];
	const applied: unknown[] = [];
	const decides = mode === "tactics" ? TACTIC_DECIDES : [
		{ id: 1, kind: "card", options: [{ id: "a", name: "A" }, { id: "b", name: "B" }], baseline: { sensible: "b" } },
		{ id: 2, kind: "job", options: [{ id: "200", name: "Magician" }, { id: "not_now", name: "Not now" }],
			baseline: { sensible: "200" } },
	];
	for (const d of decides) {
		send({ type: "decide", tick: 60 * d.id, time: d.id, situation: { level: 9 + d.id }, ...d });
		// (a tactic decide carries its own tick, time and situation, which the spread above keeps)
		const line = await read();
		const answer = line === "" ? null : JSON.parse(line);
		received.push(answer);
		const offered = answer !== null && d.options.some((o) => o.id === answer.answer);
		const why = answer === null ? "brain lost" : offered ? null : `answer "${answer.answer}" is not an offered option`;
		applied.push({ id: d.id, kind: d.kind, options: d.options.map((o) => o.id), baseline: d.baseline.sensible,
			answer: why ? d.baseline.sensible : answer.answer, source: why ? "baseline" : answer.source,
			confidence: why ? null : answer?.confidence ?? null, ...(why ? { fallback_reason: why } : {}) });
		if (d.kind === "card" && !why && answer.answer === "a" && decides[1]) (decides[1] as Record<string, unknown>).tick = 150;
	}
	const answers = applied.map((a) => `${a.kind}:${a.answer}`);
	const fixture = mode.startsWith("dead") ? deadRun() : mode === "cleared" ? clearedRun() : null;
	const pfile = process.argv.find((a) => a.startsWith("--personality-file="));
	if (fixture && pfile) {
		const dir = path.dirname(pfile.slice("--personality-file=".length));
		fs.writeFileSync(path.join(dir, "timeline.jsonl"), fixture.timeline.map((r) => JSON.stringify(r) + "\n").join(""));
		fs.writeFileSync(path.join(dir, "hits.jsonl"), fixture.hits.map((h) => JSON.stringify(h) + "\n").join(""));
	}
	const round: Record<string, unknown> = fixture ? fixture.record
		: { state: "TIMEOUT", time: 180, level: 11, job: 200, kills: 42, cards_taken: ["0:b"] };
	if (mode === "findings") send({ type: "finding", ...hp });
	send({ type: "end", record: { ...round, received, isolate: process.env.ISOLATE ?? null,
		...(mode === "tactics" ? { tactics: TACTICS_RECORD } : {}),
		...(mode === "chain" ? { mode: "chain", rounds: [{ ...round, tier: 1, stage: "henesys_hg1", state: "CLEARED" }, { ...round, tier: 2, stage: "dark_cave" }] } : {}) },
		fingerprint: { ticks: 10800, state: round.state, answers: answers.join(",") }, decisions: applied,
		brain_lost: false, findings: mode === "findings" ? [{ ...stuck, count: 4 }, hp] : mode === "dead_findings" ? [stuck] : [] });
	process.exit(0);
}
