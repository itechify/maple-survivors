// Not a test file: kept outside test/ so `node --test` does not run it.
// A tiny stand-in for game/tools/playtest/playtest_driver.gd that speaks the decision protocol (synthetic, no Godot).
//   node fake_driver.ts --mode=ok|no_end|hang|error|eof
//   ok      hello, a card decide, a job decide, end (record.received echoes the answer lines it read)
//   no_end  hello, then exits 0 without an end message
//   hang    hello, then goes silent (liveness timeout)
//   error   hello, error {reason: "cache_missing"}, exit 2
//   tactics hello, three tactic decides (calm map, drops near, critical HP), end with a fixed record.tactics
// Any other argument is echoed in hello.args so tests can check what the launcher passed.
import readline from "node:readline";

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
const send = (msg: Record<string, unknown>) => process.stdout.write("@@PT " + JSON.stringify({ v: 1, ...msg }) + "\n");
const lines = readline.createInterface({ input: process.stdin })[Symbol.asyncIterator]();
const read = async (): Promise<string> => {
	const next = await lines.next();
	return next.done ? "" : next.value;
};

send({ type: "hello", game: "fake", stage: "henesys_hg1", seed: 2026, minutes: 3, personality: "sensible",
	brain: "stdio", args: process.argv.slice(2) });
console.log("fake_driver: a log line");
if (mode === "no_end") process.exit(0);
if (mode === "hang") setInterval(() => {}, 1000);
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
		applied.push({ id: d.id, kind: d.kind, options: d.options.map((o) => o.id), baseline: d.baseline.sensible,
			answer: answer?.answer ?? d.baseline.sensible, source: answer?.source ?? "baseline",
			confidence: answer?.confidence ?? null, ...(answer ? {} : { fallback_reason: "brain lost" }) });
	}
	send({ type: "end", record: { state: "TIMEOUT", time: 180, level: 11, job: 200, kills: 42,
		cards_taken: ["0:b"], received, ...(mode === "tactics" ? { tactics: TACTICS_RECORD } : {}) }, fingerprint: { ticks: 10800, state: "TIMEOUT" }, decisions: applied,
		brain_lost: false });
	process.exit(0);
}
