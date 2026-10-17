// Facts for the Jev-assisted evaluations (adapter, #99). Code reads the run directory (record.json, timeline.jsonl,
// hits.jsonl, decisions, findings) and turns it into named buckets and short quoted words, so Jev only judges meaning
// (TypeSafe Jev 1.13 jaggedness: no arithmetic, no raw numbers, no large state). Every value in a `state` built here
// is a string. A tier chain is judged on its last round only (rows and hits of the highest tier).
// All thresholds below are ours (tier C): they decide which words Jev reads, not what counts as a problem (that is
// evaluations.ts).
import fs from "node:fs";
import path from "node:path";
import type { DecisionRecord } from "../core/session.ts";
import type { Problem } from "../core/report.ts";
import { poolLevel } from "./jev_brain.ts";

export type Row = Record<string, unknown>;
export type Hit = { time: number; tick: number; damage: number; max_hp: number; fraction: number; source: string; boss: boolean;
	mob_id?: number; tier?: number };
export type RunData = { record: Record<string, unknown>; timeline: Row[]; hits: Hit[]; decisions: DecisionRecord[];
	problems: Problem[] };

/** tier C: the death window and its chunk length (run seconds). */
export const DEATH_WINDOW_S = 30;
export const DEATH_CHUNK_S = 5;
/** tier C: a partial last minute shorter than this is not judged for pacing (too short to be dull). */
export const MIN_MINUTE_S = 15;

const num = (v: unknown, d = 0) => (typeof v === "number" && Number.isFinite(v) ? v : d);
const clock = (t: number) => `${Math.floor(t / 60)}:${String(Math.floor(t % 60)).padStart(2, "0")}`;

/** Reads a JSON Lines file (missing: []). */
export function readJsonl<T = Row>(file: string): T[] {
	if (!fs.existsSync(file)) return [];
	return fs.readFileSync(file, "utf8").split("\n").filter((l) => l.trim()).flatMap((l) => {
		try {
			return [JSON.parse(l) as T];
		} catch {
			return [];
		}
	});
}

/** The run data of run directory `dir` (decisions and problems as given, else read from the directory). */
export function readRunData(dir: string, decisions?: DecisionRecord[], problems?: Problem[]): RunData | null {
	const f = path.join(dir, "record.json");
	if (!fs.existsSync(f)) return null;
	let record: Record<string, unknown>;
	try {
		record = JSON.parse(fs.readFileSync(f, "utf8"));
	} catch {
		return null;
	}
	return { record, timeline: readJsonl(path.join(dir, "timeline.jsonl")), hits: readJsonl<Hit>(path.join(dir, "hits.jsonl")),
		decisions: decisions ?? readJsonl<DecisionRecord>(path.join(dir, "decisions.jsonl")),
		problems: problems ?? readJsonl<Problem>(path.join(dir, "findings.jsonl")) };
}

/** The data of the round to judge: the run itself, or a tier chain's last round (its record, rows and hits). */
export function finalRound(d: RunData): RunData & { tier: number | null } {
	const rounds = d.record.rounds;
	if (!Array.isArray(rounds) || rounds.length === 0) return { ...d, tier: null };
	const last = rounds[rounds.length - 1] as Record<string, unknown>;
	const tier = num(last.tier, rounds.length);
	return { ...d, record: last, tier, timeline: d.timeline.filter((r) => num(r.tier, 1) === tier),
		hits: d.hits.filter((h) => num(h.tier, 1) === tier) };
}

// ---- words ----

/** A small count as words. */
export function countWords(n: number): string {
	if (n <= 0) return "none";
	if (n === 1) return "one";
	if (n <= 4) return "a few"; // tier C
	if (n <= 9) return "several"; // tier C
	return "many";
}

/** Mobs near the player as words (playtest_situation.gd MOBS_FEW / CROWD / SWARM). */
export function mobsWords(n: number): string {
	if (n <= 0) return "none";
	if (n < 4) return "a few";
	if (n < 12) return "a crowd";
	return "a swarm";
}

/** One hit's whole damage as a share of max HP, in words (tier C). */
export function damageWords(fraction: number): string {
	if (fraction < 0.05) return "tiny (under a twentieth of max HP)";
	if (fraction < 0.15) return "small (up to about a sixth of max HP)";
	if (fraction < 0.33) return "medium (up to a third of max HP)";
	if (fraction < 0.5) return "large (a third to a half of max HP)";
	return "huge (over half of max HP)";
}

const SOURCE_TEXT: Record<string, string> = { touch: "contact (bumping into it)", attack: "attack", projectile: "projectile",
	other: "other source" };
/** Who hit and how: "the boss, contact (bumping into it)". */
export function hitSource(h: Pick<Hit, "boss" | "source">): string {
	return `${h.boss ? "the boss" : "a monster"}, ${SOURCE_TEXT[h.source] ?? h.source}`;
}

/** Tactic names as the player-facing description (tactic_controller.gd modes). */
export const TACTIC_TEXT: Record<string, string> = {
	kite: "kite: keep moving away from monsters while skills attack", aggressive: "aggressive: close in on the nearest monster or boss",
	defensive: "defensive: keep a wide berth and flee early", explore: "explore: walk, climb and use portals to other platforms",
	collect: "collect: sweep up EXP and potion drops", hold: "hold: stay put",
};

/** Seconds as rough words (tier C). */
function durationWords(s: number): string {
	if (s < 5) return "under 5 seconds";
	if (s < 15) return "5 to 15 seconds";
	if (s < 30) return "15 to 30 seconds";
	return "over 30 seconds";
}

/** How long before the death the boss arrived, as words (tier C). */
function arrivalWords(s: number): string {
	if (s < 10) return "under 10 seconds";
	if (s < 30) return "10 to 30 seconds";
	if (s < 60) return "30 to 60 seconds";
	return "over a minute";
}

// ---- boss state ----

type Fight = { spawn_time?: number; death_time?: number; status?: string };
const fights = (record: Record<string, unknown>): Fight[] => (Array.isArray(record.boss_fights) ? record.boss_fights as Fight[] : []);
const spawned = (f: Fight) => num(f.spawn_time, -1) >= 0;
const diedAt = (f: Fight) => (num(f.death_time, -1) >= 0 ? num(f.death_time) : Infinity);

/** The boss fight alive at run time `t` (spawned at or before it, not yet dead), or null. */
export function bossAliveAt(record: Record<string, unknown>, t: number): Fight | null {
	return fights(record).find((f) => spawned(f) && num(f.spawn_time) <= t && diedAt(f) > t) ?? null;
}

// ---- death ----

export type DeathFacts = { state: Record<string, unknown>; time: number; tick: number; bossAlive: boolean;
	lastHit: string; title: string };

/** The death-fairness state (DEAD only): the last 30 s as six named chunks, the hit sources with damage words, the
 * killing blow, the boss, HP potions and the tactic; null when the round did not die. */
export function deathFacts(input: RunData): DeathFacts | null {
	const d = finalRound(input);
	if (d.record.state !== "DEAD") return null;
	const t = num(d.record.time);
	const from = t - DEATH_WINDOW_S;
	const rows = d.timeline.filter((r) => num(r.time) > from && num(r.time) <= t + 1e-6);
	const hits = d.hits.filter((h) => h.time > from && h.time <= t + 1e-6);
	const chunks = [];
	for (let k = DEATH_WINDOW_S / DEATH_CHUNK_S; k >= 1; k--) {
		const a = t - k * DEATH_CHUNK_S;
		const b = a + DEATH_CHUNK_S;
		const rs = rows.filter((r) => num(r.time) > a && num(r.time) <= b + 1e-6);
		const hs = hits.filter((h) => h.time > a && h.time <= b + 1e-6);
		const minHp = rs.length ? Math.min(...rs.map((r) => num(r.hp) / Math.max(1, num(r.max_hp)))) : null;
		chunks.push({ when: `${k * DEATH_CHUNK_S} to ${(k - 1) * DEATH_CHUNK_S} seconds before death`,
			"lowest HP": minHp === null ? "not sampled" : poolLevel(minHp, 1),
			"monsters near": rs.length ? mobsWords(Math.max(...rs.map((r) => num(r.near)))) : "not sampled",
			"boss on the map": rs.some((r) => num(r.bosses) > 0) || bossAliveAt(d.record, b) ? "yes" : "no",
			tactic: String(rs.at(-1)?.tactic ?? "unknown"),
			"hits taken": hs.length ? `${countWords(hs.length)}, the biggest ${damageWords(Math.max(...hs.map((h) => h.fraction))).split(" (")[0]}` : "none" });
	}
	const groups = new Map<string, Hit[]>();
	for (const h of hits) groups.set(hitSource(h), [...(groups.get(hitSource(h)) ?? []), h]);
	const hitLines = [...groups.entries()].map(([src, hs]) =>
		`${src}: ${countWords(hs.length)} hit${hs.length === 1 ? "" : "s"}, the biggest ${damageWords(Math.max(...hs.map((h) => h.fraction)))}`);
	const last = d.hits.filter((h) => h.time <= t + 1e-6).at(-1);
	const killing = last && t - last.time <= 2 ? `${hitSource(last)}, ${damageWords(last.fraction)}` : "not recorded";
	const boss = bossAliveAt(d.record, t);
	const bossText = boss ? `a boss was on the map; it arrived ${arrivalWords(t - num(boss.spawn_time))} before the death`
		: "no boss on the map";
	const high = [...d.timeline].reverse().find((r) => num(r.time) <= t && num(r.hp) / Math.max(1, num(r.max_hp)) >= 0.6);
	const potionsLeft = num((d.record.potions_left as Record<string, unknown> | undefined)?.hp);
	const drunk = (Array.isArray(d.record.potion_uses) ? d.record.potion_uses as Array<Record<string, unknown>> : [])
		.filter((u) => u.kind === "hp" && num(u.time) > from).length;
	const tactic = String(rows.at(-1)?.tactic ?? "unknown");
	const state = {
		"what happened": `The character died ${boss ? "during a boss fight" : "with no boss on the map"}.`,
		boss: bossText,
		"time from high HP to death": high ? durationWords(t - num(high.time)) : "HP was never high in the round",
		"last 30 seconds, oldest first": chunks,
		"hits taken in the last 30 seconds": hitLines.length ? hitLines : ["none recorded"],
		"killing blow": killing,
		"HP potions left": potionsLeft <= 0 ? "none" : potionsLeft >= 5 ? "plenty" : "a few",
		"HP potions drunk in the last 30 seconds": countWords(drunk),
		"tactic at death": TACTIC_TEXT[tactic] ?? tactic,
	};
	return { state, time: t, tick: last && t - last.time <= 2 ? last.tick : Math.round(t * 60), bossAlive: boss !== null,
		lastHit: last && t - last.time <= 2 ? hitSource(last) : "not recorded",
		title: `died ${boss ? "during a boss fight" : "with no boss on the map"}; killing blow: ${killing}` };
}

// ---- minute pacing ----

export type Minute = { key: string; label: string; start: number; end: number; partial: boolean };
export type MinuteFacts = { state: Record<string, unknown>; minutes: Minute[]; skipped: string[] };

/** tier C: kills in one minute as words. */
function killWords(n: number): string {
	if (n <= 0) return "none";
	if (n <= 15) return "a few";
	if (n <= 60) return "a steady stream";
	if (n <= 200) return "lots";
	return "a flood";
}

/** tier C: EXP drops lying on the map as words. */
function dropWords(n: number): string {
	if (n <= 0) return "none";
	if (n <= 5) return "a few";
	if (n <= 20) return "many";
	return "piles";
}

/** The minute-pacing state: per run minute its level-ups, kills, hits taken, EXP drops left on the map, boss activity
 * and card/job choices, as words, keyed by a label naming the minute ("minute 3 (2:00 to 3:00)"). */
export function minuteFacts(input: RunData): MinuteFacts {
	const d = finalRound(input);
	const end = num(d.record.time, num(d.timeline.at(-1)?.time));
	const startLevel = num((d.record.start_character as Record<string, unknown> | undefined)?.level, num(d.timeline[0]?.level, 1));
	const minutes: Minute[] = [];
	const skipped: string[] = [];
	const out: Record<string, unknown> = {};
	for (let m = 0; m * 60 < end - 1e-6; m++) {
		const a = m * 60;
		const b = Math.min(end, a + 60);
		const partial = b < a + 60 - 1e-6;
		const label = `minute ${m + 1} (${clock(a)} to ${clock(b)}${partial ? ", the round ended" : ""})`;
		if (partial && b - a < MIN_MINUTE_S) {
			skipped.push(`${label}: shorter than ${MIN_MINUTE_S} s`);
			continue;
		}
		const before = [...d.timeline].reverse().find((r) => num(r.time) <= a + 1e-6);
		const inside = d.timeline.filter((r) => num(r.time) > a + 1e-6 && num(r.time) <= b + 1e-6);
		const last = inside.at(-1) ?? before;
		const levelUps = num(last?.level, startLevel) - (before ? num(before.level) : startLevel);
		const kills = num(last?.kills) - num(before?.kills);
		const hits = d.hits.filter((h) => h.time > a && h.time <= b + 1e-6).length;
		const choices = d.decisions.filter((x) => (x.kind === "card" || x.kind === "job") && num(x.time) > a && num(x.time) <= b + 1e-6).length;
		const fs = fights(d.record).filter(spawned);
		const arrived = fs.some((f) => num(f.spawn_time) > a && num(f.spawn_time) <= b);
		const defeated = fs.some((f) => diedAt(f) > a && diedAt(f) <= b);
		const allMinute = fs.some((f) => num(f.spawn_time) <= a && diedAt(f) > b);
		const boss = arrived && defeated ? "a boss arrived and was defeated" : arrived ? "a boss arrived" : defeated
			? "a boss was defeated" : allMinute ? "a boss fight went on all minute" : "no boss";
		out[label] = { "level-ups": countWords(levelUps), "monsters killed": killWords(kills), "hits taken": countWords(hits),
			"EXP drops left lying on the map": dropWords(num(last?.drops)), boss, "card or job choices": countWords(choices) };
		minutes.push({ key: `m${m + 1}`, label, start: a, end: b, partial });
	}
	return { state: { "minutes of the round": out }, minutes, skipped };
}

// ---- movement ----

export type MovementFacts = { state: Record<string, string>; longestStart: number | null; longestS: number };

/** The movement summary: the longest stay on one platform and whether drops were above meanwhile, platforms stood on,
 * portals used, stuck findings, tactics used and how often drops lay above. */
export function movementFacts(input: RunData): MovementFacts {
	const d = finalRound(input);
	const rows = d.timeline;
	let best = { start: 0, len: 0, above: 0, rows: 0 };
	let cur = { start: 0, len: 0, above: 0, rows: 0, platform: -2 };
	for (const r of rows) {
		const p = num(r.platform, -1);
		if (p < 0) { // in the air or on a rope: the stay goes on
			if (cur.platform >= 0) cur.len++, cur.rows++, cur.above += num(r.drops_above) > 0 ? 1 : 0;
			continue;
		}
		if (p !== cur.platform) cur = { start: num(r.time), len: 0, above: 0, rows: 0, platform: p };
		cur.len++;
		cur.rows++;
		cur.above += num(r.drops_above) > 0 ? 1 : 0;
		if (cur.len > best.len) best = { start: cur.start, len: cur.len, above: cur.above, rows: cur.rows };
	}
	const share = (k: number, n: number) => (n === 0 || k === 0 ? "never" : k / n >= 0.5 ? "most of the time" : "some of the time");
	const platforms = new Set(rows.map((r) => num(r.platform, -1)).filter((p) => p >= 0)).size;
	const portals = Array.isArray((d.record.camper as Record<string, unknown> | undefined)?.portals)
		? ((d.record.camper as Record<string, unknown>).portals as unknown[]).length : 0;
	const stuck = d.problems.filter((p) => p.kind === "stuck").length;
	const shares = ((d.record.tactics as Record<string, unknown> | undefined)?.shares ?? {}) as Record<string, number>;
	const ranked = Object.entries(shares).sort((x, y) => y[1] - x[1]);
	const tactics = !ranked.length ? "unknown" : ranked[0][1] >= 0.9 ? `${ranked[0][0]} almost all the time`
		: ranked[0][1] >= 0.6 ? `mostly ${ranked[0][0]}, also ${ranked.slice(1).map(([k]) => k).join(", ")}`
		: `a mix of ${ranked.map(([k]) => k).join(", ")}`;
	const len = num(d.record.time, rows.length);
	const state = {
		"round length": len < 180 ? "under 3 minutes" : len <= 600 ? "3 to 10 minutes" : "over 10 minutes",
		"longest stay on one platform": best.len < 30 ? "under 30 seconds" : best.len <= 90 ? "over 30 seconds, up to 90" : "over 90 seconds",
		"EXP drops on platforms above during that stay": share(best.above, best.rows),
		"EXP drops on platforms above, over the whole round": share(rows.filter((r) => num(r.drops_above) > 0).length, rows.length),
		"platforms stood on": platforms <= 2 ? "one or two" : platforms <= 6 ? "a few" : "many",
		"portals used": countWords(portals),
		"stuck findings (stayed inside a small box while pressing movement)": countWords(stuck),
		"tactics used": tactics,
	};
	return { state, longestStart: best.len ? best.start : null, longestS: best.len };
}

// ---- card offers ----

export type CardOffer = { id: number; time: number | null; tick: number | null; options: string[]; answer: string;
	score: number; confidence: number; levels: number };

/** Card decisions that carry the meaningfulness Score the Jev brain asked with the card (#94). */
export function cardOffers(d: RunData): CardOffer[] {
	return d.decisions.flatMap((x) => {
		const m = (x as Record<string, unknown>).meaningfulness as { score?: number; confidence?: number; levels?: number } | undefined;
		if (x.kind !== "card" || typeof m?.score !== "number") return [];
		return [{ id: x.id, time: typeof x.time === "number" ? x.time : null, tick: typeof x.tick === "number" ? x.tick : null,
			options: (x.options as unknown[]).map(String), answer: String(x.answer), score: m.score, confidence: num(m.confidence),
			levels: num(m.levels, 4) }];
	});
}
