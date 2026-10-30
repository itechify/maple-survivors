// Tests of the level-curve generator on a synthetic Mob.wz dump (no proprietary data).
import { test } from "node:test";
import assert from "node:assert/strict";
import { MAX_LEVEL, STATS, buildCurve, fillGaps, formatCurve, median, monotone, parseDump, selectSamples, smooth } from "../generate.mjs";

function mobText(id, info, stances = ["move", "stand"]) {
  const lines = [`## ${id}.img`, `${id}.img = [img ${stances.length + 1}]`, `  info = [Property ${Object.keys(info).length}]`];
  for (const [k, v] of Object.entries(info)) lines.push(`    ${k} = ${typeof v === "string" ? JSON.stringify(v) : v}`);
  for (const s of stances) lines.push(`  ${s} = [Property 2]`, `    0 = Canvas 10x10 fmt=1+0`);
  return lines.join("\n");
}

const mob = (id, level, hp, extra = {}, stances) => mobText(id, {
  level, maxHP: hp, PADamage: level * 2, PDDamage: level, MADamage: level * 3, MDDamage: level, exp: level * 5, ...extra,
}, stances);

function synthetic() {
  const parts = [];
  let id = 100000;
  for (let level = 1; level <= 100; level += 3) {
    for (const hp of [10, 11, 12]) parts.push(mob(id++, level, hp * level * level));
  }
  return parts.join("\n");
}

test("parseDump reads info numbers, strings and counts stances", () => {
  const mobs = parseDump(mobText(130100, { level: 4, maxHP: 40, elemAttr: "I2", link: "130101" }, []) + "\n" + mob(130101, 4, 40));
  assert.equal(mobs.length, 2);
  assert.equal(mobs[0].id, 130100);
  assert.equal(mobs[0].info.maxHP, 40);
  assert.equal(mobs[0].info.elemAttr, "I2");
  assert.equal(mobs[0].stances, 0);
  assert.equal(mobs[1].stances, 2);
});

test("selectSamples drops bosses, stance-less links, event ids, expedition bodies and HP outliers", () => {
  const text = [
    mob(100100, 10, 100), mob(100101, 10, 110), mob(100102, 10, 120), mob(100103, 10, 105),
    mob(100104, 10, 100000), // HP outlier: above 5x the level median
    mob(2220000, 10, 100, { boss: 1 }),
    mobText(9000001, { level: 10, maxHP: 100, link: "100100" }, []),
    mob(9300001, 10, 100), // party quest id
    mob(9400001, 10, 100), // later-client content
    mob(8810018, 10, 100), // Horntail body
    mob(6400005, 10, 100),
    mobText(100110, { level: 10, maxHP: 100, link: "100100" }, []), // link copy without stances
    mob(100111, 0, 100), // level 0
  ].join("\n");
  const { byLevel, excluded } = selectSamples(parseDump(text));
  assert.deepEqual(byLevel[10].map((m) => m.id), [100100, 100101, 100102, 100103]);
  assert.equal(excluded.boss, 1);
  assert.equal(excluded.link_without_stances, 2);
  assert.equal(excluded.id_range, 4);
  assert.equal(excluded.level_out_of_range, 1);
  assert.equal(excluded.hp_outlier, 1);
});

test("a stat's zero values are skipped, so a magic-less level keeps the nearest sampled value", () => {
  const text = [mob(100100, 5, 100, { MADamage: 0 }), mob(100101, 8, 200, { MADamage: 50 })].join("\n");
  const curve = buildCurve(parseDump(text), "2000-01-01");
  assert.ok(curve.mad.every((v) => v === curve.mad[0]), "one sampled value fills every level");
  assert.equal(curve.mad[0], 50);
});

test("median, gap filling and monotone fitting", () => {
  assert.equal(median([3, 1, 2]), 2);
  assert.equal(median([4, 1, 2, 3]), 2.5);
  const filled = fillGaps([null, 4, null, null, 32, null]);
  assert.deepEqual(filled.map((v) => Math.round(v * 1000) / 1000), [4, 4, 8, 16, 32, 32]);
  const fit = monotone([1, 100, 2, 3], [1, 1, 1, 1]);
  for (let i = 1; i < fit.length; i++) assert.ok(fit[i] >= fit[i - 1] - 1e-9);
  const lone = monotone([10, 10, 1000, 10, 10, 10], [5, 5, 1, 5, 5, 5]);
  assert.ok(Math.max(...lone) < 100, "a lone spike does not lift the levels above it");
  const smooth1 = smooth([1, 2, 4, 8, 8, 16]);
  for (let i = 1; i < smooth1.length; i++) assert.ok(smooth1[i] >= smooth1[i - 1] - 1e-9, "smoothing keeps a monotone curve monotone");
});

test("buildCurve gives 200 monotone entries per stat, the sample counts and the date", () => {
  const curve = buildCurve(parseDump(synthetic()), "2026-10-30");
  assert.equal(curve._doc.date, "2026-10-30");
  assert.equal(curve._doc.samples.per_level.length, MAX_LEVEL);
  assert.equal(curve._doc.samples.ordinary_samples, 34 * 3);
  for (const stat of STATS) {
    assert.equal(curve[stat].length, MAX_LEVEL, stat);
    for (let i = 1; i < MAX_LEVEL; i++) assert.ok(curve[stat][i] >= curve[stat][i - 1], `${stat} monotone at ${i + 1}`);
    assert.ok(curve[stat][0] > 0, stat);
  }
  assert.ok(curve.hp[99] > curve.hp[9] * 20, "HP grows with level");
});

test("output is deterministic and parses back to the same object", () => {
  const a = formatCurve(buildCurve(parseDump(synthetic()), "2026-10-30"));
  const b = formatCurve(buildCurve(parseDump(synthetic()), "2026-10-30"));
  assert.equal(a, b);
  const parsed = JSON.parse(a);
  assert.equal(parsed.hp.length, MAX_LEVEL);
  assert.ok(a.split("\n").some((line) => line.startsWith('\t"pad": [')), "each stat is one line");
});
