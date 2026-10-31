#!/usr/bin/env node
// Builds game/data/survivor/level_curve.json: the v83 reference curves of ordinary monsters by level (hp, pad, mad,
// pdd, mdd, exp for levels 1-200) that the stage `level_scale` rescales monsters with (docs/GAME_DESIGN.md 4.1,
// "Level scale"). Facts only: the output holds medians of numbers, no proprietary asset.
//
// Input is the text of `wzimport dump --wz <the owner's v83 folder> Mob.wz --imgs 2`, read from --dump=<file>
// (default stdin). tools/level_curve/run.sh runs the dump and this script together.
//
//   node tools/level_curve/generate.mjs --dump=mob_dump.txt --out=game/data/survivor/level_curve.json [--date=YYYY-MM-DD]
//
// The method is described in the `_doc` of the output and in tools/level_curve/README.md. Deterministic: the same dump
// and --date give the same bytes.

import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

export const MAX_LEVEL = 200;
export const STATS = ["hp", "pad", "mad", "pdd", "mdd", "exp"];
const INFO_KEY = { hp: "maxHP", pad: "PADamage", mad: "MADamage", pdd: "PDDamage", mdd: "MDDamage", exp: "exp" };
/** A mob whose HP is above this multiple of its level's median HP is an outlier (tier C: ours; the ticket says "about 5x"). */
export const HP_OUTLIER_FACTOR = 5;
/** Smoothing kernel over neighbouring levels, applied to log values (tier C: ours, "lightly smoothed"). */
export const SMOOTHING = [1, 2, 1];

/**
 * Ordinary monsters are the mainline field monsters: Mob.wz ids below this. Ids from 9,000,000 hold party quests,
 * Monster Carnival, Maze and other event mobs, trial dummies, GM and instance mobs, seasonal mobs and link copies of the
 * real bosses (docs/research/v83-bosses.md "Excluded"), and the 94xxxxx/95xxxxx content of later clients (Zipangu,
 * Masteria, Singapore). That content is too uneven to sample: its levels hold singletons with placeholder HP and
 * zero-damage props, which skew a median taken over few mobs per level (tier C: ours).
 */
export const MAINLINE_ID_LIMIT = 9000000;
/** Inclusive id ranges below the limit that are not ordinary either. */
export const EXCLUDED_ID_RANGES = [
  [6400005, 6400009], // Jr./Crimson/Baby Balrog link or low-HP variants
  [8800000, 8899999], // Zakum, Horntail and Pink Bean bodies and parts (expedition bosses, revive-chain stubs)
];

/** Parses the dump text into [{id, info: {key: number|string}, stances: number}], one per img. */
export function parseDump(text) {
  const mobs = [];
  let mob = null;
  let inInfo = false;
  for (const line of text.split(/\r?\n/)) {
    const head = /^## (\d+)\.img\s*$/.exec(line);
    if (head) {
      mob = { id: Number(head[1]), info: {}, stances: 0 };
      mobs.push(mob);
      inInfo = false;
      continue;
    }
    if (!mob) continue;
    const top = /^ {2}(\S+) = (.*)$/.exec(line);
    if (top) {
      inInfo = top[1] === "info";
      if (!inInfo) mob.stances += 1;
      continue;
    }
    const field = /^ {4}(\S+) = (.*)$/.exec(line);
    if (field && inInfo) mob.info[field[1]] = parseValue(field[2]);
  }
  return mobs;
}

function parseValue(raw) {
  if (raw.startsWith('"')) {
    try { return JSON.parse(raw); } catch { return raw; }
  }
  const n = Number(raw);
  return Number.isFinite(n) && raw.trim() !== "" ? n : raw;
}

function excludedId(id) {
  return id >= MAINLINE_ID_LIMIT || EXCLUDED_ID_RANGES.some(([lo, hi]) => id >= lo && id <= hi);
}

/** Median of a non-empty array of numbers (the mean of the two middle values when even). */
export function median(values) {
  const sorted = [...values].sort((a, b) => a - b);
  const mid = sorted.length >> 1;
  return sorted.length % 2 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
}

/** The ordinary samples by level (1..200) and the counts of what was left out. */
export function selectSamples(mobs) {
  const excluded = { boss: 0, link_without_stances: 0, id_range: 0, level_out_of_range: 0, no_hp: 0, hp_outlier: 0 };
  const byLevel = Array.from({ length: MAX_LEVEL + 1 }, () => []);
  for (const mob of mobs) {
    const level = Math.trunc(Number(mob.info.level ?? 0));
    if (Number(mob.info.boss ?? 0) !== 0) { excluded.boss++; continue; }
    if (mob.info.link !== undefined && mob.stances === 0) { excluded.link_without_stances++; continue; }
    if (excludedId(mob.id)) { excluded.id_range++; continue; }
    if (!(level >= 1 && level <= MAX_LEVEL)) { excluded.level_out_of_range++; continue; }
    if (!(Number(mob.info.maxHP ?? 0) > 0)) { excluded.no_hp++; continue; }
    byLevel[level].push(mob);
  }
  for (let level = 1; level <= MAX_LEVEL; level++) {
    const group = byLevel[level];
    if (group.length === 0) continue;
    const limit = HP_OUTLIER_FACTOR * median(group.map((m) => Number(m.info.maxHP)));
    byLevel[level] = group.filter((m) => {
      const keep = Number(m.info.maxHP) <= limit;
      if (!keep) excluded.hp_outlier++;
      return keep;
    });
  }
  return { byLevel, excluded };
}

/** Per-level medians of one stat (null where the level has no sample with a positive value) and the sample counts. */
function levelMedians(byLevel, stat) {
  const key = INFO_KEY[stat];
  const medians = new Array(MAX_LEVEL).fill(null);
  const counts = new Array(MAX_LEVEL).fill(0);
  for (let level = 1; level <= MAX_LEVEL; level++) {
    const values = byLevel[level].map((m) => Number(m.info[key] ?? 0)).filter((v) => v > 0);
    counts[level - 1] = values.length;
    if (values.length > 0) medians[level - 1] = median(values);
  }
  return { medians, counts };
}

/** Fills the null levels by geometric (log-linear) interpolation; levels outside the sampled span hold the nearest value. */
export function fillGaps(values) {
  const known = [];
  values.forEach((v, i) => { if (v !== null) known.push(i); });
  if (known.length === 0) throw new Error("a stat has no sample at any level");
  const out = [...values];
  for (let i = 0; i < out.length; i++) {
    if (out[i] !== null) continue;
    const lo = known.filter((k) => k < i).pop();
    const hi = known.find((k) => k > i);
    if (lo === undefined) out[i] = values[hi];
    else if (hi === undefined) out[i] = values[lo];
    else out[i] = Math.exp(Math.log(values[lo]) + (Math.log(values[hi]) - Math.log(values[lo])) * (i - lo) / (hi - lo));
  }
  return out;
}

function runningMax(values) {
  let top = -Infinity;
  return values.map((v) => (top = Math.max(top, v)));
}

/** Weight of a level that has no sample of its own (its value is interpolated) in the monotone fit. */
export const INTERPOLATED_WEIGHT = 0.25;

/**
 * Weighted isotonic regression (pool adjacent violators) of the log values: the non-decreasing sequence closest to the
 * medians, where a level counts as many times as it has samples. Unlike a running maximum, one lone high median (a
 * level with a single tough mob) does not lift every level above it.
 */
export function monotone(values, weights) {
  const blocks = [];
  values.forEach((v, i) => {
    blocks.push({ sum: Math.log(v) * weights[i], weight: weights[i], size: 1 });
    while (blocks.length > 1) {
      const top = blocks[blocks.length - 1];
      const below = blocks[blocks.length - 2];
      if (below.sum / below.weight <= top.sum / top.weight) break;
      blocks.splice(blocks.length - 2, 2, { sum: below.sum + top.sum, weight: below.weight + top.weight, size: below.size + top.size });
    }
  });
  return blocks.flatMap((b) => new Array(b.size).fill(Math.exp(b.sum / b.weight)));
}

/** Weighted moving average of the log values; the edges repeat their end value. A monotone input stays monotone. */
export function smooth(values) {
  const logs = values.map(Math.log);
  const radius = (SMOOTHING.length - 1) >> 1;
  const total = SMOOTHING.reduce((a, b) => a + b, 0);
  return logs.map((_, i) => {
    let sum = 0;
    SMOOTHING.forEach((w, j) => { sum += w * logs[Math.min(logs.length - 1, Math.max(0, i + j - radius))]; });
    return Math.exp(sum / total);
  });
}

const round2 = (v) => Math.round(v * 100) / 100;

/** The finished curve of one stat: medians, gap fill, monotone fit, smoothed, two decimals. */
export function buildStat(byLevel, stat) {
  const { medians, counts } = levelMedians(byLevel, stat);
  const weights = counts.map((n) => (n > 0 ? n : INTERPOLATED_WEIGHT));
  return runningMax(smooth(monotone(fillGaps(medians), weights))).map(round2);
}

/** The whole file object. */
export function buildCurve(mobs, date) {
  const { byLevel, excluded } = selectSamples(mobs);
  const perLevel = byLevel.slice(1).map((group) => group.length);
  const doc = {
    what: "Reference v83 monster strength by level: for levels 1-200 (index = level - 1) the HP, weapon attack (pad), "
      + "magic attack (mad), weapon defence (pdd), magic defence (mdd) and EXP of an ordinary monster of that level. "
      + "A stage's level_scale divides one level's value by another to rescale a monster (RunWorld, LevelScale).",
    tier: "A-derived numbers (v83 Mob.wz info: maxHP, PADamage, MADamage, PDDamage, MDDamage, exp), used for a tier C purpose.",
    source: "the owner's v83 Mob.wz, read with `wzimport dump Mob.wz --imgs 2`",
    generator: "tools/level_curve/generate.mjs (tools/level_curve/run.sh); same dump and date give the same bytes",
    date,
    method: [
      "1. Ordinary monsters: not boss=1; not an info/link mob without stances; a mainline field monster, Mob.wz id "
      + "below 9000000 (ids from 9000000 are party-quest, carnival, event, trial, GM and later-client content, "
      + "docs/research/v83-bosses.md 'Excluded'), without the Balrog variants 6400005-6400009 and the Zakum, Horntail "
      + "and Pink Bean bodies 8800000-8899999; level 1-200 with maxHP above 0.",
      "2. HP outliers: a mob whose maxHP is above 5x the median maxHP of its level is dropped.",
      "3. Per level and stat, the median of the remaining mobs' values; a mob whose value is 0 is skipped for that "
      + "stat (a mob without magic attack has MADamage 0, which says nothing about its level's magic damage).",
      "4. Levels with no sample are filled by log-linear interpolation between the nearest sampled levels; below the "
      + "first and above the last sampled level the nearest value holds.",
      "5. Made monotone non-decreasing by weighted isotonic regression on the log values (pool adjacent violators; a "
      + "level weighs its sample count, an interpolated level 0.25), smoothed with the weights 1-2-1 over neighbouring "
      + "levels on the log values (edges repeat; smoothing keeps a monotone curve monotone), rounded to two decimals.",
    ],
    samples: {
      mob_imgs_read: mobs.length,
      ordinary_samples: perLevel.reduce((a, b) => a + b, 0),
      levels_with_samples: perLevel.filter((n) => n > 0).length,
      excluded,
      per_level: perLevel,
    },
  };
  const out = { _doc: doc };
  for (const stat of STATS) out[stat] = buildStat(byLevel, stat);
  return out;
}

/** JSON with tab indent and every number array on one line, so a level range diffs and reads as a row. */
export function formatCurve(curve) {
  const lines = ["{"];
  const keys = Object.keys(curve);
  keys.forEach((key, i) => {
    const comma = i < keys.length - 1 ? "," : "";
    const value = curve[key];
    if (key === "_doc") {
      const text = JSON.stringify(value, null, "\t")
        .replace(/\[\s*(-?\d[^\]]*?)\s*\]/g, (_, body) => `[${body.replace(/\s+/g, "")}]`)
        .replace(/\n/g, "\n\t");
      lines.push(`\t"_doc": ${text}${comma}`);
    } else {
      lines.push(`\t${JSON.stringify(key)}: ${JSON.stringify(value)}${comma}`);
    }
  });
  lines.push("}");
  return lines.join("\n") + "\n";
}

function main() {
  const args = Object.fromEntries(process.argv.slice(2).map((a) => {
    const m = /^--([^=]+)(?:=(.*))?$/.exec(a);
    return m ? [m[1], m[2] ?? "true"] : [a, "true"];
  }));
  const out = args.out;
  if (!out) {
    console.error("usage: generate.mjs --out=<level_curve.json> [--dump=<file>] [--date=YYYY-MM-DD]");
    process.exit(2);
  }
  const text = readFileSync(args.dump ?? 0, "utf8");
  const date = args.date ?? new Date().toISOString().slice(0, 10);
  const curve = buildCurve(parseDump(text), date);
  writeFileSync(out, formatCurve(curve));
  const doc = curve._doc.samples;
  console.log(`level_curve: ${doc.mob_imgs_read} mob imgs, ${doc.ordinary_samples} ordinary samples on ${doc.levels_with_samples} levels -> ${out}`);
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) main();
