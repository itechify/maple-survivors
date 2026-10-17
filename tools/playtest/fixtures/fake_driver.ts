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
// Any other argument is echoed in hello.args so tests can check what the launcher passed.
import readline from "node:readline";

const mode = (process.argv.find((a) => a.startsWith("--mode=")) ?? "--mode=ok").slice(7);
const send = (msg: Record<string, unknown>) => process.stdout.write("@@PT " + JSON.stringify({ v: 1, ...msg }) + "\n");
const lines = readline.createInterface({ input: process.stdin })[Symbol.asyncIterator]();
const read = async (): Promise<string> => {
	const next = await lines.next();
	return next.done ? "" : next.value;
};

send({ type: "hello", game: "fake", stage: "henesys_hg1", seed: 2026, minutes: 3, personality: "sensible",
	brain: "stdio", args: process.argv.slice(2) });
console.log("fake_driver: a log line");
const stuck = { kind: "stuck", severity: "warning", tick: 1500, time: 25, count: 1,
	message: "the player stayed inside 24 px for 20 s while pressing movement (90% of ticks), tactic kite",
	snapshot: { x: 512, y: -40, fh: 7, platform: 2, hp: 50, max_hp: 50, mp: 5, max_mp: 5, level: 3, job: 0,
		tactic: "kite", state: "PLAYING", mobs: [{ mob: 100100, d: 30, x: 540, y: -40, boss: false }] } };
const hp = { kind: "hp_out_of_range", severity: "error", tick: 3600, time: 60, count: 1, message: "HP 60 outside 0..50",
	snapshot: { x: 0, y: 0, fh: 1, platform: 0, hp: 60, max_hp: 50, mp: 5, max_mp: 5, level: 4, job: 0, tactic: "kite",
		state: "PLAYING", mobs: [] } };
if (mode === "findings" || mode === "findings_no_end") send({ type: "finding", ...stuck });
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
	const decides = [
		{ id: 1, kind: "card", options: [{ id: "a", name: "A" }, { id: "b", name: "B" }], baseline: { sensible: "b" } },
		{ id: 2, kind: "job", options: [{ id: "200", name: "Magician" }, { id: "not_now", name: "Not now" }],
			baseline: { sensible: "200" } },
	];
	for (const d of decides) {
		send({ type: "decide", tick: 60 * d.id, time: d.id, situation: { level: 9 + d.id }, ...d });
		const line = await read();
		const answer = line === "" ? null : JSON.parse(line);
		received.push(answer);
		applied.push({ id: d.id, kind: d.kind, options: d.options.map((o) => o.id), baseline: d.baseline.sensible,
			answer: answer?.answer ?? d.baseline.sensible, source: answer?.source ?? "baseline",
			confidence: answer?.confidence ?? null, ...(answer ? {} : { fallback_reason: "brain lost" }) });
	}
	if (mode === "findings") send({ type: "finding", ...hp });
	send({ type: "end", record: { state: "TIMEOUT", time: 180, level: 11, job: 200, kills: 42,
		cards_taken: ["0:b"], received }, fingerprint: { ticks: 10800, state: "TIMEOUT" }, decisions: applied,
		brain_lost: false, findings: mode === "findings" ? [{ ...stuck, count: 4 }, hp] : [] });
	process.exit(0);
}
