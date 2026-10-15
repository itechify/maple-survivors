# Spec #29 / ticket #42 balance evidence

Henesys uses the real imported map and seeded simulation, an 800 × 600 viewport and a 1,800-second safety cap.
Each reported full training cohort contains one full record for seeds 1–60 and 2026 per card policy. Capped living runs are
timeouts, never clears. All earlier probes and exact console output are retained with their patches and runtime
context; exploratory subsets do not stand in for population acceptance.

## Configuration and policy

The levers were applied in order: denser opening waves; stage HP above one after 2:00; finite potion economy;
then survivor projectile coverage. Canonical skill ranks, per-hit damage and per-cast MP costs were untouched.
Three Snails throws three base shells and Energy Bolt two base bolts. Tree stage data were not tuned.

The five-MP opening was a structural capacity trap: a canonical Blue restores at most five MP, and a three-MP
cast leaves two MP, above the old bot's 30% sipping threshold. Its first twenty diagnostic Blue sips wasted
88–92% of their canonical restoration. Forty starters diagnosed starvation but were rejected as a final supply.
The survivor pool is now 30 MP with five Blue starters, 50 HP unchanged and no ordinary level-up refill.
That larger base capacity remains part of later Max MP; it is not a temporary buff or a renewable opening grant.
It improves clipping while preserving a finite initial resource. The continuous-target test observes the first
sip before eight seconds, two sips restoring 24 MP each and 19 canonical-cost casts over twenty seconds.
Real-run per-use timestamps, restoration and capacity waste make the remaining tradeoff measurable.

Across C14's 61 sensible openings, the first five Blue uses restored 12,269 MP and clipped 18,231 MP
(59.77% of their nominal restoration). Random openings restored 12,066 and clipped 18,434 MP (60.44%).
The first sip's median was 14.8 / 14.78 seconds, and the fifth's 69.73 / 64.85 seconds (sensible / random).
Thus five starters bridge roughly the opening minute; continued spell use depends on collected supply.
The capacity increase reduces the original 88–92% clipping but does not eliminate it. These opening measurements
remain applicable only while the runtime and opening data match the C14 profile; later HP-supply probes preserve them.

Both card policies use the same movement and drinking decisions. An observed ready-skill affordability failure
prompts an MP sip even above the fraction threshold, provided the pool is not full. HP sipping uses 60%, MP 30%.
The sensible card priorities remain potion tiers 112, Guard learning 110 and ranks 109, then the existing offense
scores. The twenty canonical Guard levels make protection accumulate in smaller steps; neither score overrides
nor offer weights were changed to fit the clear target. Random choices remain uniform among the offered cards.

## Measurements

Ordinary hits/kill counts landed lifetime damage lines, grouped by the mob's death minute. Fresh slot reuse resets
the count, relocation transfers it, Magic Claw's two landed lines count twice, basic hits count, and elites,
scheduled bosses and canonical boss kinds are excluded. Aggregates divide summed hits by summed kills; no kills
means null, not zero. First-five-minute values must be read with their hit and kill denominators.

Late MP wait counts fixed ticks after 8:00 when an eligible ready skill fails affordability during the cast scan;
a later affordable skill or basic attack may still act. Reached-run counts and observed seconds distinguish a missing late
window from an observed zero. Initial stock, collection, use and actual leftovers are separate. MP collection/use
is the ratio of population totals, and death medians exclude clears and timeouts. Boss reports retain completed
and spawned counts, unfinished/not-spawned/skipped encounters and censored medians alongside completed medians.

Boss diagnostic snapshots encode an unobserved route distance as null while the live simulation retains infinity.
The report reader logs normalization of that field in preserved legacy `1e99999` records, without changing raw
files or actual measurements. Serialization milestone `f4f6576` passed twenty focused tests with zero skips.

## Rejected full training cohorts

Every row below includes all 61 training seeds for that policy. No held-out seed informed these changes.

| Candidate / policy | Clear / dead / timeout | Clear rate | Death median, s (deaths) | MP collected / used | MP ratio | MP stock median | Late MP-wait runs / observed |
|---|---|---|---|---|---|---|---|
| C10 sensible | 38 / 23 / 0 | 62.30% | 870.8 (23) | 9,098 / 7,266 | 1.252 | 40 | 15 / 60 |
| C10 random | 3 / 58 / 0 | 4.92% | 706.4 (58) | 6,518 / 5,888 | 1.107 | 0 | 29 / 56 |
| C11 sensible | 18 / 43 / 0 | 29.51% | 893.0 (43) | 8,823 / 6,960 | 1.268 | 41 | 16 / 60 |
| C11 random | 0 / 61 / 0 | 0% | 671.1 (61) | 6,166 / 5,598 | 1.101 | 0 | 24 / 53 |
| C13 sensible | 29 / 32 / 0 | 47.54% | 885.85 (32) | 8,893 / 7,102 | 1.252 | 39 | 16 / 60 |
| C13 random | 2 / 59 / 0 | 3.28% | 668.9 (59) | 6,250 / 5,645 | 1.107 | 0 | 25 / 53 |
| C14 sensible | 28 / 33 / 0 | 45.90% | 925.1 (33) | 9,714 / 7,348 | 1.322 | 51 | 9 / 60 |
| C14 random | 4 / 57 / 0 | 6.56% | 666.3 (57) | 6,421 / 5,761 | 1.115 | 5 | 21 / 54 |
| C15 sensible | 25 / 36 / 0 | 40.98% | 923.75 (36) | 9,679 / 7,312 | 1.324 | 51 | 9 / 60 |
| C15 random | 3 / 58 / 0 | 4.92% | 669.1 (58) | 6,365 / 5,743 | 1.108 | 5 | 21 / 54 |
| C16 sensible | 24 / 37 / 0 | 39.34% | 879.5 (37) | 9,581 / 7,196 | 1.331 | 51 | 10 / 60 |
| C16 random | 3 / 58 / 0 | 4.92% | 661.05 (58) | 6,398 / 5,742 | 1.114 | 4 | 21 / 54 |
| C17 sensible | 26 / 35 / 0 | 42.62% | 879.3 (35) | 9,595 / 7,222 | 1.329 | 50 | 10 / 60 |
| C17 random | 3 / 58 / 0 | 4.92% | 661.05 (58) | 6,397 / 5,742 | 1.114 | 4 | 21 / 54 |
| C20 sensible | 30 / 31 / 0 | 49.18% | 909.4 (31) | 9,644 / 7,282 | 1.324 | 50 | 10 / 60 |
| C20 random | 4 / 57 / 0 | 6.56% | 660.6 (57) | 6,489 / 5,802 | 1.118 | 2 | 21 / 54 |

C10 had 25% more HP supply than C11 throughout the curve. C13 kept C11's opening/midgame supply and raised only
the 13:00 / 15:00 endpoints to 0.8% / 1.2%. This brought sensible clears into range, but careless clears still missed
the exact minimum: at 61 observations, at least four clears are needed for 5%. Three clears are not rounded up.

C14 changes only normal MP chance from 3.75% to 4%; elite MP stays 30% and boss bundles three. These are one third,
more than half and one half reductions from the original 6% / 65% / six-potion supply respectively. A deliberately
selected six-seed late-White-build probe cleared three versus C13's one; it motivates the population test but is
not an unbiased clear-rate estimate. C14's full cohort met both clear-rate and MP targets, but its sensible
death median exceeded 900 seconds, so it was not frozen. C15 reduced only the 13:00 HP endpoint from 0.8%
to 0.7%, first affecting interpolation after 12:00. It lost three sensible clears and one random clear without
moving the sensible death median below 900 seconds. It was rejected. C16 restored C14's late supply and reduced
the 9:00 HP chance from 0.48% to 0.24%, affecting interpolation from 8:00 to 11:00. Its complete cohort moved
the death median into range, with 20 of 37 sensible deaths before 15:00, but both policies were one clear below
their exact minimum. C17 retained that earlier deficit and raised only the 15:00 endpoint from 1.2% to 1.4%,
first affecting interpolation after 13:00. All 61 seeds per policy were freshly run on committed, unpatched data.
Sensible targets passed, but random still cleared only three; it collected only four additional HP bottles across
the whole cohort. C17 was rejected. C18 then probed a 13:00 endpoint of 0.9%, keeping C17's other values, on all
seven random runs that had spawned the final boss. The three completed/four censored outcomes did not change.
That conditional mechanism subset is not population acceptance. C19's 1.0% endpoint also left those outcomes
unchanged, adding only one HP bottle across seven runs. C20's 1.2% endpoint increased that subset's HP collection
from 270 to 292 and converted one unfinished finale: four completed, three censored. The promising mechanism is
then assessed on all 61 seeds per policy, including those seven records once. Both clear rates passed, but the
sensible death median was 909.4 seconds, so C20 was rejected. Fourteen of its 31 sensible deaths were before 15:00;
the next two occurred at 906.7 and 909.4 seconds. C21 probes a smaller 11:00 HP chance, 0.30% rather than 0.36%,
while keeping the 13:00/15:00 recovery. Its mechanism check covers all nine C20 random runs that spawned the final
boss: four still clear, while one former late death moves from 945.7 to 771.0 seconds. The C21 encounter sample is
four completed/eight spawned, four unfinished and one unspawned. The nine records are included once in the
subsequent full population assessment. No seed identities are protected.

## Chosen C21 training profile

C21 meets every training target. Sensible records are 61 fresh unpatched runs at `cec3fe8`; random combines nine
mechanism runs at `b3a50c8` plus the exact C21 patch with 52 unpatched runs at `cec3fe8`. The patch's 42 leaves
match shipped values bit for bit, and gameplay code is unchanged between those commits. Every expected seed
occurs exactly once per policy. All simulation warnings are empty and no runtime errors or warnings were logged.

| Policy | Clear / dead / timeout | Clear rate | Death median, s (deaths) | MP collected / used | MP ratio | MP stock median (empty) | Late wait / observed runs |
|---|---|---|---|---|---|---|---|
| Sensible | 30 / 31 / 0 | 49.18% | 886.7 (31) | 9,646 / 7,271 | 1.32664 | 50 (8/61) | 10 / 60 |
| Random | 4 / 57 / 0 | 6.56% | 660.6 (57) | 6,443 / 5,776 | 1.11548 | 2 (28/61) | 21 / 54 |

Late sensible wait totals 697.568 s over 27,638.619 observed seconds; random totals 1,484.218 / 12,682.881 s.
Maximum per-run late waits are 255.600 / 194.283 s respectively. Magician medians are 201.9 s (60/61 reaches)
and 200.8 s (59/61); Lv30 is 748.3 s (53/61) and 708.55 s (14/61). The latter random sample is conditional,
not a progression target. First-five-minute hit means and every numerator/denominator are in GAME_DESIGN 4.2
and the official aggregates. The unchanged opening retains the resource/clipping measurements above.

| Policy / boss | Completed / spawned | Completed median [min–max], s | Unfinished / unspawned / skipped | Censored median, s | Whole-hit HP median (hits) |
|---|---|---|---|---|---|
| Sensible Mano | 60 / 60 | 20.91 [8.70–45.08] | 0 / 1 / 0 | 20.91 | 41.52% (77) |
| Sensible Mushmom | 56 / 60 | 57.35 [15.60–151.38] | 4 / 1 / 0 | 59.65 | 41.85% (275) |
| Sensible Blue Mushmom | 30 / 45 | 97.57 [42.55–177.10] | 15 / 16 / 0 | ≥92.47 | 44.69% (201) |
| Random Mano | 53 / 59 | 20.45 [8.52–63.90] | 6 / 2 / 0 | ≥23.48 | 41.98% (124) |
| Random Mushmom | 21 / 49 | 50.65 [26.00–125.82] | 28 / 12 / 0 | ≥50.95 | 43.60% (205) |
| Random Blue Mushmom | 4 / 8 | 65.75 [32.93–106.65] | 4 / 53 / 0 | ≥44.00 | 42.26% (36) |

Each censored sample includes every spawned fight, including unfinished elapsed lower bounds. Completed-only
medians cannot represent the unfinished or unspawned encounters. Source-specific hit counts and ranges remain
in the public JSON/log report.

Exact data Git tree: `e585c58d2728212ecc2d10b5c55c4c55dd6ea371`. Canonical Git-data manifest SHA256:
`a931ebbeb587ac94ead67e50be8517b8bc93d7777e210a1bb48a55571f88b3e9`.
Pacing-guard Git blob: `837c5f2639820d8149f46809ae625f55f598fac4`. The coordinator receives the clean freeze
commit and sealed `c21/freeze.json`, including all 122 record hashes, before any held-out execution.

## Freeze and final checks

Candidate data and regression guards are committed before the full suite. Pacing applies conditionally to reached
milestones, with explicit minimum reach counts; legitimate early deaths remain in every report. Tree outcomes are
informational, with event/EXP/kill/finale invariants and empty real-presentation asset misses required.

Freeze commit `81afb947ed69ad9895b2becc0f81b9af84b355e3` contains the unchanged `cec3fe8` gameplay/data and the
complete training report. Its sealed `c21/freeze.json` hashes all 122 records. Before held-out execution, the
reservation was corrected from 401–430 to untouched 501–530: historical "Review-fix pass 3" in GAME_DESIGN and
IMPLEMENTATION_PLAN already reported 401–406 for bot and random. Repository reports and the coordinator's
history audit found no prior use of 501–530. Data/runtime/guard and all training hashes are unchanged.
Amended manifest SHA256: `6d12b85a5c86b4b107571ff77df7ca2958495030addeaf8c7b4936d7d960767b`.
The original unexecuted manifest remains as `freeze-original-401-430-unexecuted.json`, SHA256
`58e9e2645aedf0ac5025496204a0895469b4a5eb4cce2a83a99af2d63fdfa87b`, with the reason recorded in the amendment.

The three actual headless Tree RunScene regressions completed successfully at that freeze, with no script,
error or warning lines and `missing: []` in every summary. They use autoplay/autopick, no warp, speed 120 and an
1,800 s safety cap. These are presentation/asset/crash checks, not visual or Tree pacing acceptance.

| Tree seed | Outcome | Time, s | Level | Kills |
|---|---|---|---|---|
| 1 | DEAD | 1,067.417 | 30 | 3,565 |
| 2 | DEAD | 1,213.533 | 33 | 4,369 |
| 2026 | DEAD | 239.417 | 7 | 210 |

The clear rate is therefore 0/3, recorded without judging it. Per-seed stdout, summaries and summary hashes are
in `final/tree-presentation/`, alongside `checks.json`. Full-suite simulation regressions are separate.

The next fresh held-out range is 501–530, bot and random once each, only after the final 61-per-policy training
report and frozen QA are accepted. Spent 101–130, 201–212, 301–330 and 401–430 are never reused. The final report will retain
the freeze SHA/data hash, held-out output, six fixed RunWorld regressions, three headless Tree presentation checks
and the inspected five-minute x1 Henesys evidence separately from training.

## Reproduction and local archive

On the final committed candidate, reproduce training without a patch:

```bash
ISOLATE=training_bot BALANCE_OUT=evidence/reproduce/bot bash scripts/balance.sh 1..60 2026
ISOLATE=training_random BALANCE_OUT=evidence/reproduce/random bash scripts/balance.sh 1..60 2026 --policy=random
```

The recorded pilot/extension splits contain exactly the same complete seed sets. Each archive directory retains
the exact patch, runtime SHA/context and any runtime diff, per-seed JSON/logs, console output and aggregate reports.
The selected mechanism subsets are explicitly labeled; they are included once when that same configuration is
extended to a full cohort. Legacy diagnostic normalization is logged during aggregation, with raw records retained.
C18's CRLF seed-list markers were removed from filenames only; the input, raw console and filename mapping remain
in its archive. JSON seed IDs and record contents were unchanged. Later commands use literal numeric arguments.

The stable local evidence root is `evidence/spec29/balance/issue42/` (gitignored, archived by the coordinator before
the implementer worktree is removed). Candidate directories are `c00/` onward; full cohort aggregates are
`<candidate>/<policy>/training61_summary.json` and `.log`, with supplemental startup/exposure arithmetic in
`training61_analysis.json`. The final validation and held-out directories remain separate from training.
The inspected opening visual archive is `evidence/spec29/x1/c14_s1/`; later tuning can reuse it
only with an explicit unchanged-prefix check. It contains all five timed minute screenshots, the final image,
the actual launch SHA/hashes and `QA.md` inspection notes. Screenshots and imported assets are never committed.
