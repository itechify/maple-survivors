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

## Freeze and final checks

Candidate data and regression guards are committed before the full suite. Pacing applies conditionally to reached
milestones, with explicit minimum reach counts; legitimate early deaths remain in every report. Tree outcomes are
informational, with event/EXP/kill/finale invariants and empty real-presentation asset misses required.

The next fresh held-out range is 401–430, bot and random once each, only after the final 61-per-policy training
report and frozen QA are accepted. Spent 101–130, 201–212 and 301–330 are never reused. The final report will retain
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

The stable local evidence root is `evidence/spec29/balance/issue42/` (gitignored, archived by the coordinator before
the implementer worktree is removed). Candidate directories are `c00/` onward; full cohort aggregates are
`<candidate>/<policy>/training61_summary.json` and `.log`, with supplemental startup/exposure arithmetic in
`training61_analysis.json`. The final validation and held-out directories remain separate from training.
The inspected opening visual archive is `evidence/spec29/x1/c14_s1/`; later tuning can reuse it
only with an explicit unchanged-prefix check. It contains all five timed minute screenshots, the final image,
the actual launch SHA/hashes and `QA.md` inspection notes. Screenshots and imported assets are never committed.
