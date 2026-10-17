// The matrix summary's Problems area (#99): the same ordering as a run report (deterministic, then patterns, then
// Jev-flagged, then needs review), with death clusters computed in code from the cells' records: a run-time window
// holding the deaths of at least a share of the cells, broken down by boss alive at death, last hit source and
// personality, with a representative replay. Synthetic cell directories, no Godot, no network.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { deathClusters, deathCells } from "../src/maple/death_clusters.ts";
import { matrixSummary } from "../src/maple/matrix_summary.ts";
import { readCells } from "../src/core/aggregate.ts";
import { runCli } from "../src/maple/scenario_run.ts";
import { cliFlags, runOptionsFrom } from "../src/cli.ts";

type CellSpec = { personality: string; seed: number; state: string; time: number; boss?: boolean; hit?: "boss" | "mob" | "none";
	hitsFile?: boolean; flagged?: Array<{ kind: string; title: string; time: number }>; review?: number; evaluated?: boolean };

/** Writes one cell directory: report.json (header, outcome, problems, evaluations), record.json and maybe hits.jsonl. */
function writeCell(root: string, s: CellSpec): string {
	const name = `matrix_henesys_hg1_${s.personality}_s${s.seed}`;
	const dir = path.join(root, name);
	fs.mkdirSync(dir, { recursive: true });
	const replay = `bash scripts/agent_playtest.sh --replay=evidence/agent-playtest/m/${name}`;
	const op = (o: { kind: string; title: string; time: number }, cls: string) => ({ ...o, class: cls, message: "m", evidence: "e" });
	const report = {
		exit_code: 0, header: { personality: s.personality, seed: String(s.seed), stage: "henesys_hg1" },
		outcome: { state: s.state, time: s.time, level: 9, job: 0, kills: 100, cards_taken: 5 },
		problems: { infrastructure: [], deterministic: [], replay, rerun: "bash scripts/agent_playtest.sh --seed=1",
			jev_flagged: (s.flagged ?? []).map((o) => op(o, "flagged")),
			needs_review: Array.from({ length: s.review ?? 0 }, () => op({ kind: "minute_pacing", title: "dull minute", time: 120 }, "review")) },
		...(s.evaluated === false ? {} : { evaluations: { status: "done", results: [] } }),
	};
	fs.writeFileSync(path.join(dir, "report.json"), JSON.stringify(report));
	const fights = s.boss ? [{ mob_id: 2220000, spawn_time: 300, death_time: -1, status: "alive", elapsed: s.time - 300 }]
		: [{ mob_id: 2220000, spawn_time: -1, death_time: -1, status: "not_spawned" }];
	const bossHits = s.hit === "boss" ? [{ mob_id: 2220000, time: s.time, damage: 80, max_hp: 180, fraction: 0.44, source_kind: "touch" }] : [];
	fs.writeFileSync(path.join(dir, "record.json"), JSON.stringify({ state: s.state, time: s.time, boss_fights: fights, boss_hits: bossHits }));
	if (s.hitsFile) {
		const hit = s.hit === "mob" ? { time: s.time, tick: Math.round(s.time * 60), damage: 20, max_hp: 100, fraction: 0.2,
			source: "projectile", boss: false } : { time: s.time, tick: Math.round(s.time * 60), damage: 44, max_hp: 100, fraction: 0.44,
			source: "touch", boss: true };
		fs.writeFileSync(path.join(dir, "hits.jsonl"), JSON.stringify(hit) + "\n");
	}
	return dir;
}

/** #98's real matrix shape: 18 cells, 16 deaths; 15 between 4:17 and 6:18, 13 of them inside the 90 s from 4:17. */
function eighteen(root: string): string[] {
	const times: Record<string, Array<[number, string]>> = {
		sensible: [[600, "TIMEOUT"], [543, "DEAD"], [600, "TIMEOUT"]],
		inexperienced: [[257, "DEAD"], [313, "DEAD"], [304, "DEAD"]],
		aggressive: [[304, "DEAD"], [304, "DEAD"], [305, "DEAD"]],
		defensive: [[305, "DEAD"], [378, "DEAD"], [272, "DEAD"]],
		exploratory: [[261, "DEAD"], [309, "DEAD"], [271, "DEAD"]],
		completionist: [[257, "DEAD"], [374, "DEAD"], [306, "DEAD"]],
	};
	return Object.entries(times).flatMap(([p, ts]) => ts.map(([t, state], i) => writeCell(root, { personality: p, seed: [1, 2, 2026][i],
		state, time: t, boss: state === "DEAD" && t > 300, hit: t > 300 ? "boss" : "mob", hitsFile: p === "aggressive" })));
}

test("death cells read boss alive at death and the last hit, from hits.jsonl or the record's boss hits, else unknown", () => {
	const root = fs.mkdtempSync(path.join(os.tmpdir(), "clusters-"));
	const dirs = [writeCell(root, { personality: "aggressive", seed: 1, state: "DEAD", time: 304, boss: true, hit: "boss", hitsFile: true }),
		writeCell(root, { personality: "defensive", seed: 1, state: "DEAD", time: 305, boss: true, hit: "boss" }),
		writeCell(root, { personality: "exploratory", seed: 1, state: "DEAD", time: 261, hit: "mob" }),
		writeCell(root, { personality: "sensible", seed: 1, state: "TIMEOUT", time: 600 })];
	const deaths = deathCells(readCells(dirs));
	assert.deepEqual(deaths.map((d) => [d.personality, d.time, d.bossAlive, d.lastHit]), [
		["aggressive", 304, true, "the boss, contact"],
		["defensive", 305, true, "the boss, contact"],
		["exploratory", 261, false, "unknown (no hits.jsonl)"],
	]);
});

test("a window holding >= 40% of the cells is a death-cluster pattern with its breakdown and a median representative", () => {
	const root = fs.mkdtempSync(path.join(os.tmpdir(), "clusters-"));
	const cells = readCells(eighteen(root));
	const clusters = deathClusters(deathCells(cells), cells, { windowS: 90, share: 0.4 });
	assert.equal(clusters.length, 1);
	const c = clusters[0];
	assert.equal(c.cells.length, 13, "4:17 .. 5:13; 6:14 / 6:18 / 9:03 fall outside the best 90 s window");
	assert.deepEqual([c.from, c.to], [257, 313]);
	assert.equal(c.cells_total, 18);
	assert.equal(c.deaths_total, 16);
	assert.deepEqual(c.boss_alive, { yes: 8, no: 5 });
	assert.deepEqual(c.personalities.aggressive, { in: 3, of: 3, from: 304, to: 305 });
	assert.equal(c.representative.time, 304, "the median death time of the cluster");
	assert.equal(deathClusters(deathCells(cells), cells, { windowS: 90, share: 0.9 }).length, 0, "the share is configurable");
});

test("the summary orders Problems like a run report: deterministic, patterns, Jev-flagged, needs review; verdict first", () => {
	const root = fs.mkdtempSync(path.join(os.tmpdir(), "clusters-"));
	const dirs = eighteen(root);
	writeCell(root, { personality: "aggressive", seed: 1, state: "DEAD", time: 304, boss: true, hit: "boss", hitsFile: true,
		flagged: [{ kind: "death_fairness", title: "death felt unfair", time: 304 }], review: 1 });
	writeCell(root, { personality: "aggressive", seed: 2, state: "DEAD", time: 304, boss: true, hit: "boss",
		flagged: [{ kind: "death_fairness", title: "death felt unfair", time: 304 }] });
	writeCell(root, { personality: "sensible", seed: 2, state: "DEAD", time: 543, evaluated: false });
	const s = matrixSummary("matrix", dirs, { windowS: 90, share: 0.4 });
	const md = s.markdown.split("\n");
	const at = (re: RegExp) => md.findIndex((l) => re.test(l));
	assert.ok(at(/^\*\*Verdict:\*\*/) > 0 && at(/^\*\*Verdict:\*\*/) < 4);
	assert.match(md[at(/^\*\*Verdict:\*\*/)], /1 pattern \(death cluster 4:17 to 5:13, 13\/18 cells\)/);
	assert.match(md[at(/^\*\*Verdict:\*\*/)], /Jev: 1 flagged kind in 2 cells, 1 needs review/);
	assert.match(md[at(/^\*\*Next:\*\*/)], /--replay=\S+ --windowed --shots-at=304/);
	const det = at(/^### Deterministic failures/);
	const pat = at(/^### Patterns/);
	const flag = at(/^### Jev-flagged/);
	const rev = at(/^### Needs human review/);
	assert.ok(det > 0 && pat > det && flag > pat && rev > flag, "Problems order");
	const block = md.slice(pat, flag).join("\n");
	assert.match(block, /\*\*death cluster\*\* 4:17 to 5:13: 13\/18 cells \(72%\) died inside a 90 s window \(13 of 16 deaths; threshold 40% of the cells\)/);
	assert.match(block, /boss alive at death: 8 yes, 5 no/);
	assert.match(block, /last hit: the boss, contact 8/);
	assert.match(block, /aggressive 3\/3 \(5:04 to 5:05\)/);
	assert.match(block, /replay \(representative: median death time\): `bash scripts\/agent_playtest\.sh --replay=\S+`/);
	assert.match(md.slice(flag, rev).join("\n"), /\*\*death felt unfair\*\*: 2 cells/);
	assert.match(s.markdown, /not evaluated in 1 cell/);
	assert.equal(s.json.exit_code, 0, "patterns and Jev results never change the matrix exit code");
	assert.equal(s.json.patterns.length, 1);
});

test("--summarize rewrites an existing matrix's summary from its cell directories without running anything", async () => {
	const root = fs.mkdtempSync(path.join(os.tmpdir(), "clusters-"));
	eighteen(root);
	const { values, explicit } = cliFlags().parse([`--summarize=${root}`, "--cluster-share=0.5"]);
	const r = await runCli({ values, explicit, optionsFrom: runOptionsFrom, cwd: root });
	assert.equal(r.exitCode, 0);
	const md = fs.readFileSync(path.join(root, "summary.md"), "utf8");
	assert.match(md, /# Agent playtest matrix: /);
	assert.match(md, /death cluster/);
	assert.ok(JSON.parse(fs.readFileSync(path.join(root, "summary.json"), "utf8")).patterns.length === 1);
});

test("--summarize leaves out the replay and windowed replay directories a cell's replay writes beside it", async () => {
	const root = fs.mkdtempSync(path.join(os.tmpdir(), "clusters-"));
	eighteen(root);
	// The summary's own Next command replays a cell; its output lands in <cell>_replay_<time> / <cell>_windowed_<time>.
	for (const suffix of ["_replay_20261016-202625", "_windowed_20261016-203000", "_windowed_20261016-203000_2"]) {
		fs.cpSync(path.join(root, "matrix_henesys_hg1_aggressive_s1"), path.join(root, `matrix_henesys_hg1_aggressive_s1${suffix}`),
			{ recursive: true });
	}
	const { values, explicit } = cliFlags().parse([`--summarize=${root}`]);
	const r = await runCli({ values, explicit, optionsFrom: runOptionsFrom, cwd: root });
	assert.equal(r.exitCode, 0);
	const json = JSON.parse(fs.readFileSync(path.join(root, "summary.json"), "utf8"));
	assert.equal(json.cells.length, 18, "replays are not cells");
	assert.ok(!json.cells.some((c: { cell: string }) => /_(replay|windowed)_/.test(c.cell)));
});
