// Not a test file: kept outside test/ so `node --test` does not run it.
// A stand-in for game/scenes/debug/agent_replay.gd (the windowed replay scene; synthetic, no Godot). It reads the
// arguments the CLI passes after the launch command (--replay=<recorded dir> --out=<dir> --speed --shots-at
// [--skip-to]) and writes what the scene writes into --out: fingerprint.json, decisions.jsonl, timeline.jsonl,
// replay.json and shots/*.png (a few fake bytes each).
//   node fake_windowed.ts --mode=match|diverge|drift|crash|hang [scene args]
//   match    copies the recording's fingerprint and decisions: a match
//   diverge  the fingerprint's ticks and kills differ, replay.json says so (first timeline difference at row 3)
//   drift    replay.json claims a match, but decisions.jsonl applied another answer to decision 1 (the CLI's own
//            check with #98's replay code must catch it)
//   crash    prints a SCRIPT ERROR and exits 1 without replay.json
//   hang     prints one line, then goes silent (liveness timeout)
// replay.json echoes the scene args it got under "args".
import fs from "node:fs";
import path from "node:path";

const argv = process.argv.slice(2);
const arg = (name: string) => argv.find((a) => a.startsWith(`--${name}=`))?.slice(name.length + 3);
const mode = arg("mode") ?? "match";
const replay = arg("replay") ?? "";
const out = arg("out") ?? "";
console.log(`agent_replay: replaying ${replay} at x${arg("speed")} -> ${out}`);
if (mode === "hang") {
	setInterval(() => {}, 1000);
} else if (mode === "crash") {
	console.error("SCRIPT ERROR: Invalid call. Nonexistent function 'boom'.");
	console.error("   at: agent_replay.gd:42");
	process.exit(1);
} else {
	fs.mkdirSync(path.join(out, "shots"), { recursive: true });
	const fingerprint = JSON.parse(fs.readFileSync(path.join(replay, "fingerprint.json"), "utf8")) as Record<string, unknown>;
	const decisions = fs.readFileSync(path.join(replay, "decisions.jsonl"), "utf8").split("\n").filter(Boolean)
		.map((l) => JSON.parse(l) as Record<string, unknown>);
	if (mode === "diverge") {
		fingerprint.ticks = Number(fingerprint.ticks) + 60;
		fingerprint.kills = Number(fingerprint.kills) + 1;
	}
	if (mode === "drift" && decisions.length) {
		const d = decisions[0];
		const other = (d.options as string[]).find((o) => o !== d.answer) ?? d.answer;
		decisions[0] = { ...d, answer: other };
	}
	fs.writeFileSync(path.join(out, "fingerprint.json"), JSON.stringify(fingerprint, null, "\t"));
	fs.writeFileSync(path.join(out, "decisions.jsonl"), decisions.map((d) => JSON.stringify(d)).join("\n") + "\n");
	fs.writeFileSync(path.join(out, "timeline.jsonl"), "");
	const shotsAt = (arg("shots-at") ?? "").split(",").filter(Boolean).map(Number);
	const shots = [
		...shotsAt.map((t) => ({ name: `at_${t}s.png`, reason: `--shots-at ${t}`, tick: Math.round(t * 60), time: t, saved: true })),
		{ name: "finding_stuck_10s.png", reason: "finding stuck: injected", tick: 600, time: 10, saved: true },
		{ name: "at_999s.png", reason: "--shots-at 999", tick: 59940, time: 999, saved: false, why: "after the time cap" },
		{ name: "final.png", reason: "end of the round (TIMEOUT)", tick: 10800, time: 180, saved: true },
	];
	for (const s of shots) if (s.saved) fs.writeFileSync(path.join(out, "shots", s.name), "png");
	fs.writeFileSync(path.join(out, "shots", "levelup_2.png"), "png");
	const diverged = mode === "diverge";
	const divergences = diverged ? [
		{ field: "ticks", message: `fingerprint.ticks: replay ${fingerprint.ticks}, recorded ${Number(fingerprint.ticks) - 60}` },
		{ field: "kills", message: "fingerprint.kills: replay 2, recorded 1" }] : [];
	fs.writeFileSync(path.join(out, "replay.json"), JSON.stringify({
		match: !diverged, first: diverged ? divergences[0].message : "", divergences, replay_of: replay, out,
		speed: Number(arg("speed")), view_size: [800, 600], view_mismatch_frames: 0, window_size: [1600, 1200],
		fingerprint, decisions: decisions.length, recorded_decisions: decisions.length,
		first_timeline_difference: diverged ? { row: 3, time: 3, tick: 180, fields: { x: [10, 12] } } : {},
		shots, event_shots: ["levelup_2.png"], args: argv,
	}, null, "\t"));
	console.log(diverged ? `agent_replay: replay_divergence: ${divergences[0].message}` : "agent_replay: match");
	process.exit(diverged ? 1 : 0);
}
