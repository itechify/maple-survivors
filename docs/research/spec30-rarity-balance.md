# Spec #30 / #45: rarity balance training and frozen assessment

The new Potential tiers make sensible card choices much stronger. This pass first evaluates the rarity system
with the prior stage data, then tests odds and survivor potion supply. Canonical stats, skill costs, restoration,
starter stock, potion tier behavior and the fixed full-run regression windows are held constant.

All measurements use the player's real v83 cache, Godot 4.7.2 (`ed1daf0bf`), a 1/60 s fixed step, an 800 × 600 view,
Henesys Hunting Ground I and a 1,800 s safety cap. The sensible and random card policies share the kiting movement
and potion decisions. Only seeds **1–60 and 2026** are training data. Pilot cohorts use **1–12 and 2026**, thirteen
runs per policy. A pilot percentage is exploratory; acceptance uses all 61 seeds per policy.

## Frozen owner decision: C46 (2026-10-15)

The owner accepts the exact fully measured C46 profile as sufficient for current features and will revisit
balance after more features. Sensible **32/61 clears (52.46%)** and **902.3 s death median** miss the original
40–50% / 300–900 s targets slightly; these deviations are explicitly accepted, not relabeled strict passes.
Sensible MP is **13,104/10,817 = 1.21143**, stock median 30. Random is **4/61 (6.56%)**, death median 551.1 s,
MP **6,220/4,976 = 1.25000**, stock median four, with late waiting in **7/41** observed runs. The complete
122-record cohort, fixed pacing/boss guards, original evidence and canonical values stay intact.

The final data ports `c46-late-mp-hp-shift/patch.json` exactly, with documentation-only provenance added.
Historical C46 rejection below records the original strict decision before this owner acceptance. Later C47–C50
experiments are not selected. C50's full sensible cohort was stopped at owner steering after three completed
seed logs; `c50-hp-trough-mp-tail/full/aborted.json` marks it incomplete/owner-stop and it supplies no acceptance
result. No further tuning follows this decision. After final selected-data suite, rendered matrix and both review
axes passed, the originally planned frozen verification ran once on 601–630, as recorded below. The training
decision predates that assessment; held-out outcomes characterize the frozen candidate and do not drive tuning.
**601–630 is now spent. Fresh 701–730 is reserved for a later frozen feature candidate, not this pass.**

| Policy | Clear / dead / timeout | Clear rate | Death-only median (deaths) | Mage / Lv8 / Lv30 medians (reaches) |
|---|---|---|---|---|
| Sensible | 32 / 29 / 0 | 52.46% | 902.3 s (29) | 277.7 s (60) / 235.9 s (60) / 618.8 s (57) |
| Random | 4 / 57 / 0 | 6.56% | 551.1 s (57) | 280.8 s (45) / 244.4 s (45) / 597.3 s (15) |

| Policy | MP collected / used; ratio | MP stock median / empty runs | HP collected / used; stock median / empty runs | Late MP-wait runs / observed; seconds waited / observed |
|---|---|---|---|---|
| Sensible | 13,104 / 10,817; 1.21143 | 30 / 15 of 61 | 2,052 / 1,887; 0 / 31 of 61 | 13/60; 1,331.950 / 27,359.964 |
| Random | 6,220 / 4,976; 1.25000 | 4 / 19 of 61 | 1,044 / 1,339; 0 / 59 of 61 | 7/41; 167.749 / 7,494.134 |

| Policy / boss ID | Completed median seconds (completed / spawned) | Censored median seconds (spawned) | Unfinished / not spawned / skipped |
|---|---|---|---|
| Sensible / 2220000 | 31.91 (60/60) | 31.91 (60) | 0 / 1 / 0 |
| Sensible / 6130101 | 69.37 (53/59) | >=70.12 (59) | 6 / 2 / 0 |
| Sensible / 9400205 | 86.87 (32/47) | >=83.95 (47) | 15 / 14 / 0 |
| Random / 2220000 | 34.03 (41/45) | >=34.03 (45) | 4 / 16 / 0 |
| Random / 6130101 | 63 (13/25) | >=45.95 (25) | 12 / 36 / 0 |
| Random / 9400205 | 79.96 (4/5) | >=75.78 (5) | 1 / 56 / 0 |

| Policy | Tiers offered: Normal / Rare / Epic / Unique / Legendary | Tiers picked: Normal / Rare / Epic / Unique / Legendary |
|---|---|---|
| Sensible | 5692 / 999 / 215 / 120 / 30 | 1935 / 321 / 59 / 24 / 13 |
| Random | 3341 / 464 / 123 / 67 / 19 | 1104 / 163 / 41 / 25 / 5 |

| Policy | Minute 1 hits/kills | Minute 2 | Minute 3 | Minute 4 | Minute 5 |
|---|---|---|---|---|---|
| Sensible | 1.66 (734/442) | 1.34 (1286/959) | 1.39 (1789/1286) | 1.18 (3464/2948) | 1.43 (8580/5985) |
| Random | 1.7 (700/411) | 1.46 (1201/821) | 1.5 (1410/939) | 1.28 (2591/2029) | 1.43 (6501/4560) |

## Final frozen validation and held-out characterization

Final executable/data runtime is **`1b154207242672de00130cf1d63b710433892d00`**. The source bridge is historical
training `599590a9d86bb64dc8c6b5299df6f606fe828721` → inactive EXP cleanup
`79f9d3fd1a56aba670303e20c9c440a89a5a0508` → upstream status/elemental merge
`12b7ae81446361e380b60a48671c05565b0530b5` → final `1b154207`. Cleanup retains constant stage/global EXP,
the shared HP/MP probability curves and RNG ordering; 62 focused tests pass before and after. No shipped skill
applies the new statuses. On final source, three complete Henesys sensible records match historical C46 bytes:

| Fixed training seed | State / seconds | Historical and final full-record SHA-256 |
|---|---|---|
| 1 | DEAD / 756.1 | `4ba18ad2865bfcdff44272a9ca93d06787d302d71176126d56384dc0c698d68c` |
| 2 | DEAD / 936.9 | `261cb0a09e382cfac423d618d99994bdb4907c590034b7f03b80bb63add4d133` |
| 2026 | CLEARED / 995.7 | `cc79cc740c21541367915f13d832033e73d0535f879c3ec0b68638e8426792fa` |

This exact-record bridge covers these three neutral Henesys runs, not all six rendered cases or arbitrary status
configurations. Final selected-data validation passes **570 tests, zero failures, zero skips, 62 files, 270,135 ms**.
The unchanged full-run guards cover fixed 1/2/2026 on both stages. Independent Spec and Standards reviews of
source plus selected data each report **zero findings** against base `9c42d93a99692e209dc19597adafd9879b3ea1e2`.

All six rendered cases exit successfully with **`missing=[]`**: Henesys seeds 1/2/2026 give DEAD/DEAD/CLEARED,
and Tree gives DEAD/DEAD/DEAD. By-eye checks include Henesys seed 1 `t600.png` and `levelup_30.png`, Henesys
seed 2 `boss_windup_2.png`, and Tree seed 1 `hit_first.png`; sprites, effects, HUD and final-boss art are intact.
The Henesys 2026 clear is established by its summary. Its final capture was skipped after five seconds without
a drawn frame, so this report claims no clear PNG. Earlier frames and seed 2's final-boss frame provide the
visual coverage. Concurrent x32/vsync-off runs are asset/flow verification, not normal-speed performance data.
Dedicated rarity UI/input-flow evidence remains under `evidence/spec30/ui/`.

The released assessment uses fresh seeds **601–630 once per policy**, after those gates passed. The archived runner uses
an exclusive `execution-started.json` marker and rejects replay. Both processes exit zero, on final source with
**no PATCH**, Godot 4.7.2 (`ed1daf0bf`), fixed 1/60 s, 800 × 600 view, 1,800 s cap and JOBS=12. Start UTC is
2026-10-16T03:18:44.165151+00:00 (owner local date 2026-10-15). Every one of 60 unique records matches its
sole `BALANCE` console record, contains no world warning, has no logged runtime error/warning, and satisfies
starting stock + collected − used = final stock. All 30 runs per policy report tier counts. No deaths are
filtered and no timeout is counted as a clear.

**This characterization does not meet every original target.** Sensible clears **19/30 (63.33%)**, above 50%,
with death median **943 s**, above 900 s. Random clears **4/30 (13.33%)** with median **433.6 s**, both within
their bands, but **0/16** observed late runs show MP waiting; the training observation **7/41** does not
generalize to this sample. Both MP ratios remain 1.2–1.5, and sensible final MP median 60.5 remains below the
former 117 reference. These findings are reported without pooling with training, replay, retuning or changing
guards/targets. The owner's earlier acceptance applies to the documented training deviations; it is not
reinterpreted as acceptance of unmeasured held-out outcomes. Balance will be revisited after more features.

| Policy | Clear / dead / timeout | Clear rate | Death-only median (deaths) | Mage / Lv8 / Lv30 medians (reaches) |
|---|---|---|---|---|
| Sensible | 19 / 11 / 0 | 63.33% | 943 s (11) | 275.8 s (30) / 233.7 s (30) / 595.75 s (30) |
| Random | 4 / 26 / 0 | 13.33% | 433.6 s (26) | 282.2 s (24) / 253.65 s (24) / 573.9 s (11) |

| Policy | MP collected / used; ratio | MP stock median / empty runs | HP collected / used; stock median / empty runs | Late MP-wait runs / observed; seconds waited / observed |
|---|---|---|---|---|
| Sensible | 7,403 / 5,688; 1.30151 | 60.5 / 4 of 30 | 1,110 / 1,003; 3.5 / 12 of 30 | 4/30; 245.766 / 14,952.401 |
| Random | 3,628 / 2,677; 1.35525 | 5.0 / 3 of 30 | 534 / 670; 0.0 / 28 of 30 | 0/16; 0.000 / 4,552.784 |

| Policy / boss ID | Completed median seconds (completed / spawned) | Censored median seconds (spawned) | Unfinished / not spawned / skipped |
|---|---|---|---|
| Sensible / 2220000 | 23.76 (30/30) | 23.76 (30) | 0 / 0 / 0 |
| Sensible / 6130101 | 66.98 (29/30) | 67.09 (30) | 1 / 0 / 0 |
| Sensible / 9400205 | 91.42 (19/27) | >=89.83 (27) | 8 / 3 / 0 |
| Random / 2220000 | 45.77 (18/24) | >=30.77 (24) | 6 / 6 / 0 |
| Random / 6130101 | 73.97 (8/12) | >=50.56 (12) | 4 / 18 / 0 |
| Random / 9400205 | 71.17 (4/7) | >=56.55 (7) | 3 / 23 / 0 |

| Policy | Tiers offered: Normal / Rare / Epic / Unique / Legendary | Tiers picked: Normal / Rare / Epic / Unique / Legendary | Observed runs |
|---|---|---|---|
| Sensible | 3035 / 484 / 125 / 63 / 19 | 1040 / 144 / 39 / 15 / 4 | 30/30 |
| Random | 1727 / 221 / 62 / 31 / 14 | 581 / 69 / 24 / 9 / 2 | 30/30 |

| Policy | Minute 1 hits/kills | Minute 2 | Minute 3 | Minute 4 | Minute 5 |
|---|---|---|---|---|---|
| Sensible | 1.65 (372/225) | 1.32 (621/471) | 1.33 (882/662) | 1.16 (1626/1397) | 1.42 (4275/3013) |
| Random | 1.73 (352/204) | 1.41 (563/398) | 1.52 (693/455) | 1.33 (1092/820) | 1.44 (3561/2468) |

| Policy / boss ID / source | Whole-hit HP fraction %, median [min–max] (hits) |
|---|---|
| Sensible / 2220000 / touch | 47.87 [41.5–52.13] (53) |
| Sensible / 6130101 / attack | 36.54 [31.68–38.94] (27) |
| Sensible / 6130101 / touch | 36.14 [30.39–40.84] (123) |
| Sensible / 9400205 / attack | 36.94 [33.04–43.91] (22) |
| Sensible / 9400205 / touch | 37.88 [30.12–45.91] (104) |
| Random / 2220000 / touch | 47.73 [36.86–55.11] (47) |
| Random / 6130101 / attack | 33.51 [30.39–36.45] (8) |
| Random / 6130101 / touch | 34.96 [30.25–39.6] (40) |
| Random / 9400205 / attack | 31.79 [31.79–31.79] (1) |
| Random / 9400205 / touch | 35.13 [31.64–37.86] (24) |

| Seed | Sensible offered / picked (N,R,E,U,L) | Random offered / picked (N,R,E,U,L) |
|---|---|---|
| 601 | 99,12,6,1,2 / 37,3,0,0,0 | 86,5,2,0,0 / 27,2,2,0,0 |
| 602 | 91,16,1,0,0 / 30,6,0,0,0 | 21,6,0,0,0 / 8,1,0,0,0 |
| 603 | 110,19,5,4,0 / 38,5,1,2,0 | 64,6,1,1,0 / 22,0,1,1,0 |
| 604 | 100,17,4,2,0 / 32,7,1,1,0 | 68,5,1,1,0 / 23,2,0,0,0 |
| 605 | 96,21,7,2,0 / 33,5,3,1,0 | 106,17,6,2,1 / 38,5,1,0,0 |
| 606 | 100,18,7,4,0 / 35,5,2,1,0 | 24,1,3,2,0 / 6,1,2,1,0 |
| 607 | 110,15,6,1,0 / 33,6,4,1,0 | 127,15,2,0,0 / 44,3,1,0,0 |
| 608 | 106,12,5,2,1 / 38,4,0,0,0 | 25,1,0,1,0 / 9,0,0,0,0 |
| 609 | 105,16,4,0,1 / 35,5,2,0,0 | 59,9,2,1,1 / 21,3,0,0,0 |
| 610 | 111,15,3,0,0 / 37,5,1,0,0 | 115,16,2,1,1 / 35,8,2,0,0 |
| 611 | 110,11,3,2,0 / 39,3,0,0,0 | 59,6,6,0,1 / 18,3,3,0,0 |
| 612 | 104,15,6,2,2 / 39,3,1,0,0 | 90,15,5,3,1 / 34,3,0,1,0 |
| 613 | 75,8,5,1,1 / 28,1,1,0,0 | 11,0,2,2,0 / 4,0,1,0,0 |
| 614 | 106,20,5,4,0 / 35,6,3,1,0 | 99,20,5,4,1 / 33,7,1,2,0 |
| 615 | 100,19,6,4,0 / 33,7,1,2,0 | 25,4,1,0,0 / 9,0,1,0,0 |
| 616 | 91,14,3,3,0 / 31,4,1,1,0 | 27,2,1,0,0 / 10,0,0,0,0 |
| 617 | 91,23,1,1,1 / 31,7,1,0,0 | 106,16,0,0,1 / 35,6,0,0,0 |
| 618 | 114,18,2,3,1 / 39,5,1,0,1 | 11,1,0,0,0 / 4,0,0,0,0 |
| 619 | 106,19,7,3,0 / 38,6,1,0,0 | 74,9,8,2,0 / 26,2,3,0,0 |
| 620 | 100,21,2,2,1 / 33,7,1,0,1 | 76,11,3,2,1 / 25,5,1,0,0 |
| 621 | 97,20,3,3,3 / 35,6,1,0,0 | 13,2,0,0,0 / 5,0,0,0,0 |
| 622 | 102,16,7,1,0 / 33,5,3,1,0 | 11,1,0,0,0 / 4,0,0,0,0 |
| 623 | 92,15,3,5,2 / 32,3,3,1,0 | 116,16,1,5,3 / 39,5,1,2,0 |
| 624 | 102,18,3,3,0 / 36,6,0,0,0 | 9,0,3,0,0 / 3,0,1,0,0 |
| 625 | 131,15,2,6,2 / 44,4,1,1,2 | 53,2,0,1,1 / 19,0,0,0,0 |
| 626 | 98,10,3,0,0 / 33,3,1,0,0 | 30,0,0,0,0 / 10,0,0,0,0 |
| 627 | 91,13,6,1,0 / 30,5,2,0,0 | 12,0,0,0,0 / 4,0,0,0,0 |
| 628 | 106,13,4,0,0 / 36,3,2,0,0 | 39,4,2,0,0 / 13,2,0,0,0 |
| 629 | 101,21,5,1,1 / 36,5,1,1,0 | 105,22,6,0,2 / 31,9,3,0,2 |
| 630 | 90,14,1,2,1 / 31,4,0,1,0 | 66,9,0,3,0 / 22,2,0,2,0 |

Tier order in the per-run table is Normal, Rare, Epic, Unique, Legendary. These are actual displayed/picked
tiers, including floor-constrained bonus offers; they are not independent Fortune-zero distribution samples.
HP collection excludes the five starter HP potions per run (150 per policy); final stock includes them. MP
ratios divide collection totals by use totals. Late-wait observations require time after 8:00 and retain their
observed-run and observed-seconds denominators. Completed fight medians include only completed observations;
the completed/spawned and censored counts prevent survivor-only interpretation. Boss-hit fractions use the
whole hit before Guard's MP split, with actual HP at that hit; their observed spread is distinct from the fixed
typical-HP damage regression. First-five-minute hits/kill divides lifetime hit sums by ordinary kill sums.

The final hash context is `game/data` tree `6fc008daa47371aac78636328632f44ce0d7d8bc` and sim tree
`6199b3083c3059baec6fd2db2447a8bcc68617bc`. Full-run guard blob
`4eb7f63a48b47e8f13f1bc347ebe26989fe83a99` and boss-hit guard blob
`b39ba91682a7368bfc57c5b8d74b393a9b16d058` are unchanged. Runtime pin `1b154207` precedes the documentation
closure and script-header-only seed reservation update; executable script/game/sim/data bytes remain frozen.

| Preserved evidence | Location | SHA-256 |
|---|---|---|
| Original 122-record training seal | `evidence/spec30/balance/c46-late-mp-hp-shift/freeze.json` | `b2d4416114b27194eb4509b41f66e470265b9bbefdf586121ee77b875f790cb7` |
| Final suite log | `evidence/spec30/tests/final_suite.log` | `e786f4ca317eed480e2e0192177dd368cccb26e098f34e0e975fa2c2cc386d85` |
| Six-case rendered matrix | `evidence/spec30/final_render/matrix.json` | `0ffcd27b5a7a5dd4e8bfa9e4832728415ac49fc51c8587c21a46e647145e7269` |
| By-eye review | `evidence/spec30/final_render/visual_review.txt` | `eb37911d6b993355f1b2d506ffb08766bc236d63ae7fbad835cd59b184120c4a` |
| Exact neutral record bridge | `evidence/spec30/final_bridge/comparison.json` | `d4aab16ee899c6d6f86c6592f5a4bb68a1c4676c0072323b5cadd3693435ed94` |
| Held-out 134-artifact seal | `evidence/spec30/balance/c46-heldout-frozen/heldout-seal.json` | `19371fd9d5f25188b18e593d836817e08b6ac4b4f77801dc5fba62578285cc25` |

`evidence/spec30/frozen_validation.json` seals the final gate artifacts and source/data reviews. The held-out
directory preserves raw JSON/per-seed logs, exact bot/random consoles, machine-readable aggregate JSON and
exact report logs, assessments, `per-run-tiers.csv`, the table above, source/configuration context, start/finish
markers and the archived exclusive runner. Its seal hashes 134 artifacts and links the original training and
final-validation seals. Evidence remains ignored and local; no proprietary cache or screenshots are committed.

## Evidence and targets

The raw records, per-seed logs, exact console reports, patches and configuration manifests are preserved under
`evidence/spec30/balance/` in the integration worktree. This directory is ignored because the associated runtime
evidence may reference the user's proprietary cache. Each cohort's `assessment.json` lists SHA-256 hashes of its
raw records. `context.json` or `git-context.json` identifies its source and patch. Git context hashes use Git blob
bytes, avoiding checkout newline differences; the manifest records that convention explicitly.

Targets are sensible clears **40–50%** (25–30 of 61), random clears **5–15%** (4–9 of 61), death-only median
**300–900 s**, sensible MP collection/use totals **1.2–1.5**, a final MP bank well below the former median 117,
and some observed random MP waiting after 8:00. Death medians exclude clears but include every death. Reached
milestone medians always retain their reach counts. No timeout is counted as a clear.

## Training experiments

Unless stated otherwise, Fortune is zero and the nominal Normal/Rare/Epic/Unique/Legendary weights remain
**75/18/5/1.7/0.3**, with the designed Fortune scale 0.02. Rows below report separate thirteen-seed cohorts.
The MP ratio divides total collected by total used, rather than averaging individual ratios.

| Cohort | Change | Sensible clear / death median (deaths) / MP ratio | Random clear / death median (deaths) / MP ratio | Decision |
|---|---|---|---|---|
| `baseline` | Rarity on; prior stage and balance data | 10/13 / 691.5 s (3) / 1.744 | 0/13 / 601.3 s (13) / 1.352 | Establishes the large sensible power increase. |
| `c01-odds` | Weights 90/7/2/0.7/0.3; everything else unchanged | 7/13 / 696.35 s (6) / 1.694 | 0/13 / 567.5 s (13) / 1.292 | Reject: suppresses exciting tiers and weakens random builds without resolving the disparity. |
| `c02-hp` | Ordinary HP chance 0.8/0.6/0.6/0.7% at 8/9/11/12 min | 11/13 / 927.7 s (2) / 1.729 | 1/13 / 608.05 s (12) / 1.439 | Additional mid-run HP can help weak builds, but sensible survival is too high. |
| `c03-hp-pressure` | C02 plus roughly 20% greater ordinary/elite HP from 8 min | 11/13 / 820.45 s (2) / 1.529 | 0/13 / 597.2 s (13) / 1.243 | Expanded to all training seeds; rejected below. |
| `c04-mp` | C02 with global normal/elite MP 7.5/45% | 7/13 / 356.5 s (6) / 1.446 | Not run | Reject: fixed seeds 1 and 2026 die before Mage; global supply also changes opening pickup routes. |
| `c05-mp-curve` | C02 with ordinary MP 10% through 6 min, tapering to 7.5% at 8 min | 11/13 / 862.1 s (2) / 1.459 | Not run | Opening preserved; still excessive sensible survival and HP banking. |
| `c06-mp-curve` | C05's later ordinary MP reduced to 6% | 10/13 / 960.9 s (3) / 1.246 | Not run | MP ratio meets target, but HP stock median 17 supports prolonged survival. |
| `c07-hp-tail` | C06 with ordinary HP 0.2% from 12 min onward | 9/13 / 837.05 s (4) / 1.264 | Not run | HP stock median falls to 5; mid-run bank remains. |
| `c08-mid-hp` | C07 with ordinary HP 0.4/0.6/0.4/0.4% at 6/8/9/11 min | 8/13 / 746.6 s (5) / 1.295 | Not run | HP stock median 2; all thirteen reach Mage and Lv30. Expanded and rejected below. |
| `c09-mp-restore` | C07 with ordinary MP restored to 10% throughout | 10/13 / 849.8 s (3) / 1.758 | Full cohort below | Reject: excessive sensible MP stock and insufficient random clears. |
| `c11-mob-pressure` | C03 with ordinary/elite HP 1.5× the original endpoints from 8 min | 7/13 / 701.6 s (6) / 1.322 | Full cohort below | Reject: stronger pressure removes weak progression. |
| `c12-moderate-odds` | C03 with weights 82/12/4/1.7/0.3 | 9/13 / 775.7 s (4) / 1.494 | Full cohort below | Routine Rare/Epic progression reduced; Unique and Legendary weights preserved. Expanded and rejected below. |

Changed HP endpoints at 480 s begin interpolating immediately after the unchanged 360 s endpoint; “from 8 min”
in the experiment table identifies endpoints rather than an instantaneous switch. C03's full cohort demonstrates
why zero random clears in a pilot cannot determine population acceptance:

| Policy | Clear / dead / timeout | Death-only median (deaths) | Mage / Lv30 medians (reaches) | MP collected / used | MP stock median | Late MP-wait runs / observed |
|---|---|---|---|---|---|---|
| Sensible | 49 / 12 / 0 (80.33%) | 727.85 s (12) | 277.7 s (60) / 618.8 s (58) | 16,834 / 11,664 = 1.443 | 84 | 4/60 |
| Random | 5 / 56 / 0 (8.20%) | 547.15 s (56) | 282.05 s (46) / 595.65 s (14) | 6,534 / 4,756 = 1.374 | 6 | 4/39 |

C03 meets random survival and resource targets but leaves sensible survival far above its band. Additional
ordinary mob HP mainly reduces kill and potion income, rather than creating sufficient sensible attrition.
Later probes return to the original mob HP curve and retain the nominal rarity odds.

C08's full cohort shows that its mid-run HP reduction harms weaker builds before the final boss while leaving
too many sensible clears. Both policies contain all 61 training seeds; there are no simulation warnings or
logged runtime errors. Source is `64ffb86` plus the preserved C08 patch.

| Policy | Clear / dead / timeout | Death-only median (deaths) | Mage / Lv30 medians (reaches) | MP collected / used | MP stock median | Late MP-wait runs / observed |
|---|---|---|---|---|---|---|
| Sensible | 37 / 24 / 0 (60.66%) | 794.25 s (24) | 277.7 s (60) / 592.8 s (59) | 12,846 / 10,307 = 1.246 | 33 | 7/60 |
| Random | 0 / 61 / 0 (0%) | 551.2 s (61) | 282.05 s (46) / 580 s (16) | 5,028 / 4,089 = 1.230 | 3 | 8/40 |

C08's sensible HP stock median is zero. Its final boss completes 37/42 spawned fights, median 77.65 s across
those 37 completions and censored median ≥67.38 s across all 42 spawns. Random completes the second boss 9/20
times; only one run reaches the final boss, unfinished after 4.65 s. C08 is rejected for both clear rates. The
next experiment restores C07's mid-run HP support before considering stronger final-boss attrition. MP supply
and the nominal rarity defaults are retained for this causal comparison.

C07's restored-support random cohort also contains all 61 training seeds: **0 clear / 61 dead / 0 timeout**,
death median **560.7 s** (61), MP **5,396/4,335 = 1.245**, MP stock median **4**, and late waiting **7/40** observed
runs (424.733/6,954.317 s). Mage is 282.05 s (46 reaches), Lv30 585.05 s (18). The second boss completes 11/25
spawned fights, completed median 48.33 s (11), censored median ≥38.98 s (25). Two final fights spawn and neither
completes; their censored median is ≥6.97 s (2). Mid HP restoration alone is insufficient. The subsequent C09
comparison changes only ordinary MP from 6% back to 10% in the later endpoints, retaining C07's HP curve.

C09's full random cohort gives **1 clear / 60 dead / 0 timeout (1.64%)**, death median **568.05 s** (60), MP
**7,424/4,888 = 1.519**, MP stock median **7**, and late waiting **2/40** observed runs (53.950/7,232.716 s).
Mage is 282.05 s (46 reaches), Lv30 590.4 s (23). Restoring MP alone does not recover the required four clears.
The sensible pilot's final MP stock median is 138, above the earlier 117 reference, so all-run MP restoration on
this softer mob profile is rejected as well.

C10 returns to C03's known support and roughly 20% higher ordinary/elite HP after 8 min. It changes only
ordinary HP at 12 min from 0.7% to 0.3%, and at 13 min from 1.2% to 0.6%, preserving 1.4% recovery at 15 min.
The first change affects interpolation after 11 min. This tests pre-final attrition while retaining earlier weak
build support; a final-boss-only lever risks moving too many deaths past the 900 s median limit. Both full
61-seed policy cohorts were measured without an intermediate pilot. Boss and rarity settings are unchanged.

| C10 policy | Clear / dead / timeout | Death-only median (deaths) | Mage / Lv30 medians (reaches) | MP collected / used | MP stock median | Late MP-wait runs / observed |
|---|---|---|---|---|---|---|
| Sensible | 44 / 17 / 0 (72.13%) | 782.2 s (17) | 277.7 s (60) / 618.8 s (58) | 16,601 / 11,415 = 1.454 | 79 | 4/60 |
| Random | 2 / 59 / 0 (3.28%) | 550 s (59) | 282.05 s (46) / 595.65 s (14) | 6,299 / 4,643 = 1.357 | 6 | 4/39 |

C10 increases sensible deaths before 900 s from eight to twelve, but trades only five sensible clears for three
random clears. Sensible HP stock median is 4 (20/61 empty); random HP is zero (59/61 empty). The final boss
completes 44/49 sensible fights (completed median 82.24 s, 44 observations; censored median ≥77.25 s, 49) and
2/2 random fights (median 101.30 s, 2). The stronger trough has little room without losing required random clears.
C10 is rejected. The MP-only C07/C09 pilot clear difference was only 9/13 versus 10/13, so no additional full
cohort is spent on MP timing alone.

C11 restores C03's HP support and raises ordinary/elite HP endpoints from roughly 1.2× to 1.5× the original
curve: 4.8/4.875/5.875/6.375/7.6875/10.3125 at 8/9/11/12/13/15 min. Interpolation first changes after 6 min,
preserving the established opening. Boss settings remain independent. This tests whether additional crowd
pressure and Guard MP consumption can create earlier sensible attrition without removing weak-build HP supply.
It uses a sensible thirteen-seed pilot and a full random cohort; existing fixed pacing limits remain unchanged.
The pilot's predetermined seeds 1/2/2026 all die (612/896.6/559.6 s), with Mage reached by all three and Lv30
reached by seed 2 at 659.4 s. These outcomes retain the required reached-milestone windows and the one-of-three
Lv30 floor; they are not replaced with successful seeds. Full structural tests remain required after selection.

C11's full random cohort has **0 clear / 61 dead / 0 timeout**, death median **527.2 s** (61), MP
**4,767/3,861 = 1.235**, stock median **4**, and late waiting **6/38** observed runs (454.117/4,468.853 s).
Only five runs reach Lv30 (median 618.2 s); the second boss completes 4/17 times (completed median 68.19 s, 4;
censored median ≥22.82 s, 17) and the final boss never spawns. C11 is rejected because pressure removes weak
progression. The crowd-cap audit does not support separating the builds via rate/cap alone: by 9 min C03's mean
alive count is 153.97 sensible (60 observed runs) and 154.69 random (36), both near the same interpolated cap.

Ticket #45 explicitly allows Fortune/weight tuning and the spec calls its base odds approximate. The initial
nominal-odds preference is therefore revisited with C12's **82/12/4/1.7/0.3** weights on the C03 stage profile.
This shifts seven percentage points into Normal while preserving the original Unique and Legendary chances.
Fortune remains zero, its non-Normal multiplier scale stays 0.02, and tier gains, headroom, boss floor and
card-only semantics are unchanged. The sensible pilot reaches Mage in all thirteen runs and Lv30 in twelve,
median 624.35 s; MP stock median is 60.

C12's random full cohort meets its required floor: **4 clear / 57 dead / 0 timeout (6.56%)**, death median
**548.1 s** (57), MP **6,413/4,721 = 1.358**, stock median **5**, late waiting **4/40** observed runs
(73.283/6,884.483 s). Mage is 281.45 s (46 reaches), Lv30 595.65 s (14). The final boss completes 4/4 times,
median 71.72 s (4), with no unfinished fights and 57 unspawned. Effective offered tiers total
Normal/Rare/Epic/Unique/Legendary **3,155/575/140/56/7**, picked **1,050/192/48/20/1**; Unique/Legendary offer
counts remain 56/7 as in C03. The sensible full cohort is measured next before deciding on any late taper.

C12's sensible full cohort still has **44 clear / 17 dead / 0 timeout (72.13%)**, death median **760.4 s** (17),
MP **16,121/11,333 = 1.422**, stock median **77**, and late waiting **4/60** observed runs (311.267/28,031.719 s).
Mage is 277.7 s (60 reaches), Lv30 624.35 s (58). Twelve deaths are before 900 s. The final boss completes
44/49 fights (completed median 95.23 s, 44; censored median ≥94.73 s, 49). Offered tiers total
**5,571/1,260/255/107/10**, picked **1,896/402/74/24/5**. C12 preserves the required random floor and meaningful
high tiers, but is rejected as a final candidate for excess sensible clears.

C13 keeps C12's weights and HP profile. Ordinary MP stays 10% through 11 min, interpolates to 2.5% at 12 min,
then holds. Elite chances and fixed boss bundles remain unchanged. The late seam targets a measured resource
difference: C12's four random finale survivors carry 174/148/188/195 MP potions, versus sensible median 77.
Earlier 8-min MP tapering harmed weak progression; a late taper can preserve the entire pre-boss-2 window.
C13 first measures the sensible thirteen-seed pilot and **all four C12 random finales, seeds 28/42/47/55**, as an
explicitly selected mechanism subgroup. This subgroup cannot estimate population acceptance; any selected
profile must still include all 61 seeds exactly once per policy in its final cohort.

C13's sensible pilot gives **6/13 clears**, death median **925.5 s** (7), MP **2,589/2,197 = 1.178**, MP stock
median **16**, and late waiting **4/13** observed runs (571.716/6,316.067 s). All thirteen reach Mage and twelve
reach Lv30 (median 624.35 s). The selected random subgroup gives three clears and one death at 762.6 s;
that death retains 86 MP potions and has no MP wait. Fewer ground pickups can still alter HP survival routes.
The subgroup's three clears are not a population rate. C13 remains a full-cohort alternative because the pilot's
resource and death medians are near the bounds, rather than being rejected from a thirteen-run estimate.

C14 narrows the MP trough and adds recovery: 10% through 9 min, 7.5% at 11 min, 2.5% at 12 min, 5% at 13 min,
and 7.5% at 15 min. Earlier modest tapering aims to create attrition before 900 s; recovery aims to preserve
finale support and the population MP ratio. The same sensible pilot and complete four-run C12 finale subgroup
are measured first. If plausible, both full 61-seed cohorts follow; a small pilot miss does not substitute for
population acceptance.

C14's sensible pilot rebounds to **9/13 clears**, death median **767.55 s** (4), MP **2,807/2,257 = 1.244**,
stock median **52**, and late waiting **1/13** (124.683/6,023.348 s). The mechanism subgroup still gives three
clears and one death at 776.3 s, despite greater MP stock (median 109.5) and no MP wait. Recovery fixes the pilot
resource ratio but does not improve the subgroup or retain C13's clear-rate effect. C13 is therefore expanded
to both full 61-seed cohorts before deciding from small, conditional samples. C14 remains unassessed at
population scale.

Both C13 full cohorts are complete. A single sensible launch (seed 47) originally wrote no engine header or
record; the batch returned failure and did not launch random. The empty output and original incomplete report
remain in `c13-late-mp/full/failed-launch/`. Only seed 47 was retried on the identical source/patch, successfully,
and the unchanged reporting section of `scripts/balance.sh` regenerated the complete console/aggregate from all
61 records. Random then ran normally. No result is excluded or duplicated; all four mechanism records are
byte-identical to their later full-cohort counterparts.

| C13 policy | Clear / dead / timeout | Death-only median (deaths) | Mage / Lv30 medians (reaches) | MP collected / used | MP stock median | Late MP-wait runs / observed |
|---|---|---|---|---|---|---|
| Sensible | 31 / 30 / 0 (50.82%) | 905.65 s (30) | 277.7 s (60) / 624.35 s (58) | 12,176 / 10,750 = 1.133 | 13 | 17/60 |
| Random | 3 / 58 / 0 (4.92%) | 550.35 s (58) | 281.45 s (46) / 595.65 s (14) | 5,841 / 4,659 = 1.254 | 5 | 5/40 |

C13 misses both exact clear-count bands by one; 3/61 is not rounded into 5%. Sensible death median exceeds
900 s and its MP ratio remains below 1.2. Fourteen sensible deaths are before 900 s. The final boss completes
31/47 sensible fights (completed median 86.75 s, 31; censored median ≥85.98 s, 47) and 3/3 random fights
(median 68.97 s, 3). Sensible HP stock median is zero (32/61 empty), random zero (60/61 empty). C13 is rejected
as a final candidate after the full population assessment.

The read-only diagnostic supports a bounded C15 redistribution: ordinary HP at 9/11 min rises from 0.6% to
0.7%, while 13/15-min HP falls from 1.2%/1.4% to 0.9%/1.05%. MP remains 10% through 11 min, then tapers to
a 4.5% hold at 12 min. Earlier health supply addresses weak runs' median 550 s death window; reduced tail supply
targets sensible late survival, while the smaller MP reduction aims to meet the ratio floor. Opening data,
rarity weights, mob HP, boss damage and tier magnitudes remain unchanged. Population assessment follows a
plausible pilot; no exact thirteen-run result is treated as acceptance.

C15's sensible pilot gives 7/13 clears, death median 907.35 s (6), MP 2,767/2,214 = 1.250,
stock median 53, and late waiting 3/13. Both full populations then run unchanged.

| C15 policy | Clear / dead / timeout | Death-only median (deaths) | Mage / Lv30 medians (reaches) | MP collected / used | MP stock median | Late MP-wait runs / observed |
|---|---|---|---|---|---|---|
| Sensible | 34 / 27 / 0 (55.74%) | 859.9 s (27) | 277.7 s (60) / 626.65 s (58) | 13,123 / 10,860 = 1.208 | 31 | 12/60 |
| Random | 3 / 58 / 0 (4.92%) | 561.05 s (58) | 281.45 s (46) / 595.65 s (14) | 6,154 / 4,834 = 1.273 | 5 | 6/40 |

C15 passes resource and death timing but misses both clear-count bands. The final boss completes 34/47 sensible
fights (completed median 88.75 s, 34; censored median >=88.68 s, 47) and 3/4 random fights (completed median
67.82 s, 3; censored median >=86.27 s, 4). Sensible HP stock median is one (29/61 empty); random zero
(60/61 empty). Random seed 28 is restored to a clear, seed 51 reaches an unfinished finale, and former winner
47 dies at 819.1 s with zero HP potions and 127 MP potions. The measured weak deaths exhaust HP; further tail
cuts risk the random floor. C15 is rejected as a final candidate.

C16 therefore changes two bounded fields: Normal/Rare weights from 82/12 to 85/9, retaining Epic/Unique/Legendary
at 4/1.7/0.3, and ordinary HP at 540/660 s from 0.7% to 0.8%. Every other C15 value is unchanged. The odds change
targets routine sensible rank progression; the HP adjustment compensates weak mid-run survival. Both complete
61-seed populations are assessed directly rather than selecting from another thirteen-run estimate.

| C16 policy | Clear / dead / timeout | Death-only median (deaths) | Mage / Lv30 medians (reaches) | MP collected / used | MP stock median | Late MP-wait runs / observed |
|---|---|---|---|---|---|---|
| Sensible | 37 / 24 / 0 (60.66%) | 843.1 s (24) | 277.7 s (60) / 628.7 s (58) | 13,121 / 10,869 = 1.207 | 34 | 12/60 |
| Random | 3 / 58 / 0 (4.92%) | 561.05 s (58) | 281.45 s (46) / 597.3 s (15) | 6,213 / 4,886 = 1.272 | 4 | 6/40 |

C16 changes routine Rare counts but adds sensible clears and does not restore random's minimum clear count.
Its sensible offered/picked Rare totals fall from C15's 1,222/388 to 1,071/350; MP demand barely changes.
Only 15 sensible deaths precede 900 s, so a finale-only pressure change would not safely satisfy both the clear
count and death-median bands. Completed final fights are 37/46 sensible (median 97.33 s, 37; censored median
>=96.98 s, 46) and 3/5 random (median 67.82 s, 3; censored median >=67.82 s, 5). C16 is rejected.

C17 returns to C15's 82/12/4/1.7/0.3 weights and 0.7% HP support at 540/660 s. It tests temporal MP separation:
10% ordinary MP through 480 s, 13.5% at 540/660 s, then a 1% hold from 720 s. Ordinary HP at 780/900 s returns
to C13's 1.2%/1.4%. C13 established the near-target sensible clear effect of a late MP cut, but its total supply
fell below 1.2 times use. Earlier MP compensates the aggregate ratio while the deeper late cut tests high-Guard
attrition. Restored tail HP addresses the observed exhaustion of former random winner 47; C15's modest mid-run
HP support retains the restoration of seed 28. Both full cohorts are measured without changing the profile.

| C17 policy | Clear / dead / timeout | Death-only median (deaths) | Mage / Lv30 medians (reaches) | MP collected / used | MP stock median | Late MP-wait runs / observed |
|---|---|---|---|---|---|---|
| Sensible | 36 / 25 / 0 (59.02%) | 901.6 s (25) | 277.7 s (60) / 626 s (58) | 12,956 / 11,163 = 1.161 | 23 | 14/60 |
| Random | 4 / 57 / 0 (6.56%) | 558.8 s (57) | 281.45 s (46) / 598.9 s (14) | 6,424 / 4,951 = 1.298 | 7 | 3/40 |

C17 restores random's exact minimum clear count, including seeds 28/42/47/55, but sensible still misses clear,
death timing and resource bands. Earlier MP banking plus restored tail HP does not preserve C13's survival effect.
Only 12 sensible deaths precede 900 s. Completed final fights are 36/49 sensible (median 102.61 s, 36;
censored median >=100.78 s, 49) and 4/5 random (median 58.08 s, 4; censored median >=51.18 s, 5). C17 is rejected.

A subsequent card-tier audit finds an unused availability lever. C15 has 31 random deaths at Lv25+, of which 14
never take White Potion; only 17/58 dead runs take White versus all three clears. C17 still has 12 Lv25+ deaths
without White. Actual `potion_uses.item_id` confirms that late failed former winners already use 2000002, so
the weight change targets other weak builds rather than directly rescuing seed 47. The exact audits remain beside
the full console reports. Potion restoration, minimum levels, preceding-tier requirements and stock conversion stay fixed.

C18 combines C11's previously measured stronger stage pressure (HP endpoints 1.5 times the old owner profile,
supported HP curve and unchanged 10% normal MP fallback) with C12's 82/12/4/1.7/0.3 odds, and raises existing
Orange/White potion card weights from 30 to 90. This changes availability after an ignored guarantee; the sensible
policy takes the guarantee immediately and the card becomes ineligible. C11's sensible pilot already gave fewer
clears and an MP ratio of 1.322. Greater potion-tier availability is the causal hypothesis for restoring random
survival under that pressure, without changing the card pool or magnitudes. Both complete cohorts are assessed.

| C18 policy | Clear / dead / timeout | Death-only median (deaths) | Mage / Lv30 medians (reaches) | MP collected / used | MP stock median | Late MP-wait runs / observed |
|---|---|---|---|---|---|---|
| Sensible | 28 / 33 / 0 (45.90%) | 785.1 s (33) | 277.7 s (60) / 659.45 s (48) | 12,490 / 10,041 = 1.244 | 35 | 9/60 |
| Random | 0 / 61 / 0 (0%) | 542.1 s (61) | 281.45 s (46) / 600.35 s (8) | 5,027 / 4,103 = 1.225 | 3 | 13/39 |

C18 meets every sensible population target but fails random clears. Orange reaches 43/46 Mage runs, yet only
21 random runs reach Lv25+ (7 without White), and all exhaust HP stock. Twenty-seven sensible deaths precede
900 s. Completed final fights are 28/34 sensible (median 90.78 s, 28; censored median >=90.78 s, 34) and
0/3 random (none, 0; censored median >=33.35 s, 3). C18 is rejected as a final candidate.

C19 changes only C18's ordinary/elite HP endpoints at 480/540/660 s back to C12's 3.84/3.9/4.7. The stronger
endpoints remain at 720/780/900 s (6.375/7.6875/10.3125). This relieves the weak build window identified by
C18's 542 s random median death and loss of Lv25 progression, while preserving the measured late pressure.
Odds, potion-card availability, HP/MP supply, starter state and boss scaling stay fixed. Both full cohorts run.

| C19 policy | Clear / dead / timeout | Death-only median (deaths) | Mage / Lv30 medians (reaches) | MP collected / used | MP stock median | Late MP-wait runs / observed |
|---|---|---|---|---|---|---|
| Sensible | 37 / 24 / 0 (60.66%) | 892.55 s (24) | 277.7 s (60) / 622.3 s (57) | 15,265 / 11,200 = 1.363 | 63 | 4/60 |
| Random | 2 / 59 / 0 (3.28%) | 559.9 s (59) | 281.45 s (46) / 576.6 s (12) | 6,199 / 4,748 = 1.306 | 5 | 6/37 |

C19 restores sensible progression and too many clears; random improves but remains below the exact floor.
Thirteen sensible deaths precede 900 s. Random reaches Lv25+ in 29 dead runs, ten still without White.
Completed final fights are 37/48 sensible (median 105.4 s, 37; censored median >=98.27 s, 48) and 2/4 random
(median 126.81 s, 2; censored median >=97.77 s, 4). C19 is rejected as a final candidate.

C20 returns to C18's passing sensible stage and changes only Orange/White card weights from 90 to 300.
This clean comparison tests whether near-certain reoffers after an ignored guarantee improve careless HP survival.
Random runs first; a failing random cohort rejects the profile without duplicating a full sensible cohort.
A plausible complete random population is followed by all 61 sensible runs before any final selection.

C20 random gives 0/61 clears, death median 527.2 s (61), MP 4,564/4,001 = 1.141, stock median 3, and late
waiting 12/38 (692.983/4,579.081 s). Orange picks are 42 and White 12; concentrating potion reoffers does not
restore HP survival and can displace attack progression. It is rejected without a sensible rerun.

The next audit uses actual buff-cast snapshots rather than assuming the queued card prefix is character level.
C18 sensible casts Guard in 60/60 Mage runs before 480 s, first-cast median 297.96 s, final rank median 20.
Random casts it in 41/46 Mage runs, 40 before 480 s, first-cast median 330.57 s, but final rank median 3.
Learning availability is a smaller gap than rank progression. C21 changes only C18's Guard rank-card weight
from 8 to 16 and runs the thirteen-seed pilot. The matching C18 subset is copied byte-for-byte from existing
full records: sensible 5/13 clears, death median 760.55 s (8), MP 1.297; random 0/13, death median 574.7 s,
MP 1.292. No baseline simulations are repeated.

C21 sensible rises to 9/13 clears, death median 666.6 s (4), MP 2,619/2,096 = 1.250, stock median 36, and
late waiting 2/13. Random remains 0/13, death median 558.7 s (13), MP 1,120/940 = 1.191, stock median zero,
late waiting 3/10, and Lv30 reaches fall from two to one. Random's final Guard rank median rises to four,
but lost attack progression cancels its HP benefit. The strong sensible survival effect rejects this direction.

C22 instead changes only C12's Guard rank-card weight from 8 to 4. Learning weight, every magnitude, policies,
stage pressure and HP/MP supply remain fixed. C12's exact thirteen-seed subset is copied from the full cohort:
sensible 9/13 clears, MP 1.494; random 0/13, death median 597.2 s (13), MP 1.203 and three Lv30 reaches.
The complete C12 random population already passes at 4/61, so zero pilot clears alone will not reject the probe.

C22 sensible moves in the opposite direction: 11/13 clears, death median 765.2 s (2), Lv30 median 588.2 s
(12 reaches), MP 4,527/2,429 = 1.864, stock median 135 and no late waiting. Earlier attack progression outweighs
lower Guard protection. Random remains 0/13, death median 583.3 s (13), MP 1,505/1,165 = 1.292, stock median 21,
late waiting 1/11 and four Lv30 reaches. It is rejected on sensible survival and resources without a full expansion.

A cap audit suggests a temporary weak-build window. In C15, minute ending 8:00 sensible clears average 104.06
alive (34 observations), sensible deaths 114.19 (26), random clears 100 (3), and random deaths 122.27 (37).
Near-mob medians are 30.6 for sensible clears and 48.9 for random deaths. C18 is denser: corresponding alive
means are 114.82 (28), 121.41 (32), and 123.15 random deaths (39). These fields are means over the preceding
minute, not instantaneous snapshots; the stage cap interpolates over that window. Both policies converge near
the cap by minute ending 9:00. Six-minute alive means of 14–17 are far below the cap, so early cap changes would
do little. Exact audit reports retain every denominator.

C23 starts from C15, reducing cap endpoints at 480/540 s from 143.33/165 to 110/140 and ordinary HP endpoints
at 720/780 s from 0.7%/0.9% to 0.6%/0.8%. The 900 s HP chance remains 1.05%. Opening, MP curve, rates,
11/12-minute density, odds and every card weight remain fixed. The sensible pilot rises from 7/13 to 9/13
clears, death median 779.5 s (4), MP 2,784/2,239 = 1.243 and stock median 54. Random remains 0/13, death
median 611.1 s (13), MP 1,475/1,186 = 1.244, stock median 1, late waiting 1/11 and only one Lv30 reach.

The separate four-run C12 finale mechanism cohort shows no reliable new health bank: seed 28 retains its clear
and ends with four HP potions versus one in C15; 42 clears with zero; 47 dies earlier at 762.2 s versus 819.1 s,
HP0/MP134; and 55 loses its clear, dying at 927.9 s with HP0/MP132. Zero random pilot clears alone is not the
rejection: the higher sensible survival and vulnerable-build losses reject this cap/HP-trough direction.
The raw mechanism records and exact HP-use comparison remain under `c23-cap-trough/mechanism/`.

C24 returns to C15 and changes only the rarity table to Normal/Rare/Epic/Unique/Legendary **86/8/3.5/1.7/0.8**.
It reduces routine Rare rank gains, retains meaningful Epic offers and unchanged Unique weight, while modestly
increasing the full-headroom Legendary jackpot. Measured random builds retain low Guard ranks while sensible
builds reach the cap; a jackpot can close more missing ranks for the weak build. This is a causal hypothesis,
not a clear-rate forecast. Stage data, card weights, Fortune base/scale and all magnitudes remain fixed.
Jackpot variance motivates measuring both complete populations directly.

| C24 policy | Clear / dead / timeout | Death-only median (deaths) | Mage / Lv30 medians (reaches) | MP collected / used | MP stock median | Late MP-wait runs / observed |
|---|---|---|---|---|---|---|
| Sensible | 38 / 23 / 0 (62.30%) | 830 s (23) | 277.7 s (60) / 618.8 s (57) | 13,620 / 10,868 = 1.253 | 39 | 10/60 |
| Random | 4 / 57 / 0 (6.56%) | 551.1 s (57) | 280.8 s (45) / 597.3 s (15) | 6,303 / 5,002 = 1.260 | 4 | 7/41 |

C24 raises Legendary offered/picked totals from C15's 10/5 to 30/13 for sensible and 7/1 to 19/5 for random.
Random meets the exact floor. Its additional clear is seed 22 with one Legendary pick, final Guard rank 20,
HP stock 9 and MP46. Existing clears 28/42/55 retain their prior clear times with HP stock 2/0/0 and MP98/62/128.
These are observed final builds; they do not establish the timing or identity of the individual jackpot pick.
Sensible remains too easy and has only 14 deaths before 900 s, so finale-only attrition risks the death median.
Final fights complete 38/47 sensible (median 88.89 s, 38; censored median >=86.07 s, 47) and 4/5 random
(median 69.68 s, 4; censored median 71.53 s, 5). C24 is rejected as a final profile but retained as the rarity base.

C25 changes only C24's ordinary/elite HP at 720/780 s to 5.95/7.175, 1.4 times the old owner endpoints,
holding the 900 s value at 8.25. This adds pre-finale pressure while retaining the final-arrival HP endpoint.
The existing quarter-rate post-duration HP extrapolation changes with the final slope: from 0.004375 to
0.00223958 HP-multiplier units per second. This coupled effect is measured rather than hidden as an independent
mechanic. All earlier endpoints, odds, card weights, MP/HP supply, boss scaling, crowd caps and rates remain fixed.

The exact C24 thirteen-run subset is derived from its full records: sensible 8/13 clears, death median 703.5 s
(5), MP 1.292; random 0/13, death median 605.8 s, MP 1.250 and three Lv30 reaches. C25 sensible drops to 5/13
clears, death median 935.35 s (8), MP 2,764/2,145 = 1.289 and stock median 59. Mage reaches all 13; Lv30 reaches
11, median 621.1 s. Random remains 0/13 with unchanged 605.8 s death median and three Lv30 reaches, MP
1,548/1,239 = 1.249, stock median 19 and late waiting 2/11. The separate four-build cohort preserves all C24
random clears: 22/28/42/55 finish at 1,013.4/979.5/954.8/990.2 s with HP stock 8/2/0/0. The full populations
therefore follow unchanged; their death median and exact clear counts remain unresolved by the pilot.

| C25 policy | Clear / dead / timeout | Death-only median (deaths) | Mage / Lv30 medians (reaches) | MP collected / used | MP stock median | Late MP-wait runs / observed |
|---|---|---|---|---|---|---|
| Sensible | 33 / 28 / 0 (54.10%) | 885.65 s (28) | 277.7 s (60) / 618.8 s (57) | 13,476 / 10,856 = 1.241 | 40 | 10/60 |
| Random | 4 / 57 / 0 (6.56%) | 551.1 s (57) | 280.8 s (45) / 597.3 s (15) | 6,268 / 4,984 = 1.258 | 4 | 7/41 |

The complete C25 populations retain all four random clears, but sensible still exceeds the 30-clear ceiling
by three. Every other acceptance metric is in band. Sensible HP stock median is two with 29/61 empty runs;
random stock median is zero with 59/61 empty. Completed final fights are 33/46 sensible (median 84.33 s,
33; censored median >=85.32 s, 46) and 4/5 random (median 84.86 s, four; censored median >=79.53 s, five).
C25 is retained as the closest complete comparison, not accepted.

C26 changes only the 720 s HP multiplier from 5.95 to 6.375, leaving the 780/900 s endpoints and the
post-duration slope unchanged. This tests whether greater pre-finale pressure can reduce clears without
moving deaths entirely past 900 s. Both complete 61-seed populations run directly; no extra pilot is used.

| C26 policy | Clear / dead / timeout | Death-only median (deaths) | Mage / Lv30 medians (reaches) | MP collected / used | MP stock median | Late MP-wait runs / observed |
|---|---|---|---|---|---|---|
| Sensible | 34 / 27 / 0 (55.74%) | 850.9 s (27) | 277.7 s (60) / 618.8 s (57) | 13,370 / 10,796 = 1.238 | 38 | 10/60 |
| Random | 4 / 57 / 0 (6.56%) | 551.1 s (57) | 280.8 s (45) / 597.3 s (15) | 6,249 / 4,972 = 1.257 | 4 | 7/41 |

C26 preserves all four random clears and moves sensible deaths earlier, but its 34 clears still miss the
ceiling. It is rejected as final. Completed final fights are 34/46 sensible (median 79 s, 34; censored median
>=75.79 s, 46) and 4/5 random (median 75.92 s, four; censored median >=58.47 s, five).

C27 changes only C26's Normal/Rare weights from 86/8 to 90/4. Epic/Unique/Legendary remain 3.5/1.7/0.8,
and stage/supply/card weights/Fortune base and scale stay fixed. This isolates routine rank gains from the
successful jackpot increase, which C24 had changed together. Both complete populations run directly.

| C27 policy | Clear / dead / timeout | Death-only median (deaths) | Mage / Lv30 medians (reaches) | MP collected / used | MP stock median | Late MP-wait runs / observed |
|---|---|---|---|---|---|---|
| Sensible | 34 / 27 / 0 (55.74%) | 844.6 s (27) | 277.7 s (60) / 618.8 s (57) | 13,319 / 10,801 = 1.233 | 35 | 8/60 |
| Random | 4 / 57 / 0 (6.56%) | 551.1 s (57) | 280.8 s (45) / 595.9 s (14) | 6,248 / 4,971 = 1.257 | 4 | 7/41 |

C27 reduces sensible Rare picks from 323 to 241 but leaves the clear count at 34. Random retains the same
four clears, with one fewer Lv30 reach. Legendary picked totals are 14 sensible and five random. Sixteen
sensible deaths precede 900 s. Completed final fights are 34/45 sensible (median 88.18 s, 34; censored median
>=78.1 s, 45) and 4/5 random (median 75.97 s, four; censored median >=58.47 s, five). The pure routine-rarity
reduction is rejected because it provides no survival calibration benefit.

C28 returns to C26's 86/8/3.5/1.7/0.8 table and changes only the 780 s HP multiplier from 7.175 to 7.6875.
The 900 s endpoint stays 8.25. This tests a small further pre-finale pressure step while preserving the
mid-run window, all supply and the final-arrival HP endpoint. The coupled quarter-rate post-duration HP
slope falls from 0.00223958 to 0.001171875 multiplier units per second. Both complete populations run directly.

| C28 policy | Clear / dead / timeout | Death-only median (deaths) | Mage / Lv30 medians (reaches) | MP collected / used | MP stock median | Late MP-wait runs / observed |
|---|---|---|---|---|---|---|
| Sensible | 33 / 28 / 0 (54.10%) | 866.5 s (28) | 277.7 s (60) / 618.8 s (57) | 13,294 / 10,732 = 1.239 | 37 | 10/60 |
| Random | 4 / 57 / 0 (6.56%) | 551.1 s (57) | 280.8 s (45) / 597.3 s (15) | 6,250 / 4,973 = 1.257 | 4 | 7/41 |

C28 removes one sensible clear relative to C26 but still misses the ceiling by three. Fifteen sensible deaths
precede 900 s. The four random clears retain MP stock 44/56/97/123 (seeds 22/42/28/55), without late waiting;
three end with HP0. The eight lowest-stock sensible clears end MP0/0/4/12/12/14/14/18, also without observed
late waiting. Seeds 46 and 30 finish with one HP potion and MP12/14. This supports testing a small MP cut
rather than removing more vulnerable random HP. The exact audit is `c28-780-hp-step/full/mp-clear-margin.txt`.
Completed final fights are 33/46 sensible (median 82.35 s, 33; censored median >=69.81 s, 46) and 4/5 random
(median 73.52 s, four; censored median >=54.6 s, five).

C29 changes only C28's normal MP endpoints at 720/780/900 s from 4.5% to 4.25%, held thereafter.
The 10% endpoint through 660 s, rarity, HP multipliers and supply, all card weights, elites and boss bundles
stay fixed. This modest late cut targets lower-stock sensible builds while retaining the random clears' measured
MP bank. The aggregate 1.239 ratio leaves limited margin above 1.2, and the 300–900 s death-median guard
remains strict. Both full populations run directly.

| C29 policy | Clear / dead / timeout | Death-only median (deaths) | Mage / Lv30 medians (reaches) | MP collected / used | MP stock median | Late MP-wait runs / observed |
|---|---|---|---|---|---|---|
| Sensible | 34 / 27 / 0 (55.74%) | 847.9 s (27) | 277.7 s (60) / 618.8 s (57) | 13,211 / 10,775 = 1.226 | 33 | 11/60 |
| Random | 4 / 57 / 0 (6.56%) | 551.1 s (57) | 280.8 s (45) / 597.3 s (15) | 6,238 / 4,981 = 1.252 | 4 | 7/41 |

C29 increases observed sensible waiting but not deaths; sixteen deaths precede 900 s. It is rejected as final.
Completed final fights are 34/45 sensible (median 82.07 s, 34; censored median >=79.58 s, 45) and 4/5 random
(median 84.57 s, four; censored median >=84.4 s, five). Tiny late HP/MP changes and routine rarity reduction
have clustered at 33–34 sensible clears while preserving exactly four random clears.

A read-only C28 boss audit finds greater policy separation in the first encounter. Random clear builds average
255.5 HP damage after Guard, three boss hits and 4.75 HP drinks; sensible clears average 94.36 HP, 1.15 hits
and 1.27 drinks. Their completed duration medians are 39.3 s (4/4) and 29.85 s (33/33). These outcome-conditioned
groups explain a support hypothesis, not a guaranteed causal effect. Across all runs, first fights complete 41/45
random (median 34.03 s, 41; censored >=34.03 s, 45) and 60/60 sensible (median 31.91 s, 60; same censored median).
Four random deaths leave Mano alive at 312.8/332.1/340.9/345.4 s. Random clears 22/28/42 drink Red50 four/seven/four
times during Mano; 55 drinks Orange150 four times. Saving an early potion preserves a count for later White-tier
healing. The first reward supplies six HP and three MP plus a card. Boss2's clear-build HP damage and drinks are
nearly policy-equal, so it is a weaker selective support lever. The ordinary spawn rate is halved while a boss
lives: a faster kill also ends that relief sooner, and the net effect must be measured.

C30 starts from C28 (restoring the 4.5% late MP endpoints) and pairs Mano HP multiplier 1.8→1.5 with a single
stronger ordinary/elite HP endpoint at 900 s, 8.25→9.625. Earlier endpoints, every damage multiplier and boss
reward, rarity/card weights and all HP/MP supply stay fixed. The late endpoint is 1.4 times the old owner value;
its 16.67% increase over C28 also changes the quarter-rate post-duration HP slope to 0.0040364583/s. The measured
early support is intended to provide careless survival margin for that stronger late pressure. Both full
populations run directly; neither clear-rate success nor a new potion bank is assumed.

| C30 policy | Clear / dead / timeout | Death-only median (deaths) | Mage / Lv30 medians (reaches) | MP collected / used | MP stock median | Late MP-wait runs / observed |
|---|---|---|---|---|---|---|
| Sensible | 33 / 28 / 0 (54.10%) | 902.25 s (28) | 277.7 s (60) / 618.5 s (56) | 13,263 / 10,752 = 1.234 | 35 | 11/60 |
| Random | 1 / 60 / 0 (1.64%) | 575.75 s (60) | 280.8 s (45) / 597.1 s (14) | 6,310 / 5,093 = 1.239 | 5 | 4/42 |

C30 is rejected on both sensible targets and random clears. First fights improve to 43/45 random completions
(median 29.57 s, 43; censored >=29.57 s, 45) and remain 60/60 sensible (median 26.91 s, 60). The first reward is
reached more often, but later health does not improve reliably: random 22 retains its clear and HP stock rises
8→11; 28 dies at 802 s with HP0/MP116, 42 at 947 s with HP0/MP65, and 55 at 961.7 s with HP0/MP130. Only the
first remains a clear. Completed final fights are 33/47 sensible (median 87.78 s, 33; censored >=86.25 s, 47)
and 1/3 random (149.9 s, one; censored >=61.7 s, three). The pair cannot isolate the faster-kill timing from the
stronger late pressure, and the complete four-build comparison remains in the evidence folder.

**Release-invalid boss multiplier in C31–C37.** A later full-source preflight identified that Mano damage 1.0
violates the unchanged `test_boss_hit_bands.gd` full-roll guard: 72–85 damage at the documented typical
196 HP / 7 PDD is 36.73–43.37%, below the required 40–50% band. These experimental records remain intact
but none can be a release candidate, independently of their population results. Neither typical HP/PDD nor
the guard was changed. Damage 1.10 produces 79–94 (40.31–47.96%) and passes all three boss-band tests,
with no failures or skips; exact output is `mano110-guard-preflight.log`. C38 uses that valid multiplier.

C31 returns to C28 and changes only Mano's existing damage multiplier 1.15→1.0, retaining its HP and all late
endpoints. This tests differential HP preservation without deliberately changing the first fight's kill timing
or adding pressure at the same time. The random full population runs first. Any meaningful support effect must
be established before pairing it with stronger ordinary pressure; a passing final profile still requires both
complete populations and every unchanged guard.

C31 random gives 4/61 clears, 57 deaths, no timeouts, death median 559.9 s, Mage median 280.8 s (45),
Lv30 median 597.3 s (15), MP 6,374/5,069 = 1.257, stock median five and late waiting 7/42.
All four prior clears survive. Seed22 preserves its complete card/skill build and 992.4 s clear time while
HP stock rises 8→9. Seeds28/55 retain their complete builds, 932.7/954.6 s clear times and zero HP stock.
Seed42 clears at 984.5 s rather than 1,025.1 s, ending HP2 rather than zero, with one attack-card difference
(one fewer Energy Bolt rank and a Magic Claw target). Its stock gain cannot be attributed solely to damage
relief. Final current HP is not recorded, so zero stock does not prove unchanged ending health. First fights
complete 42/45 (median 34.29 s, 42; censored >=34.55 s, 45); final fights 4/5 (median 69.54 s, four; censored
>=54.6 s, five). Support is modest, with no new clear. A separate sensible support-only cohort is not run.

C32 retains C31's damage relief and raises only the 720 s ordinary/elite HP multiplier from 6.375 to 7.225,
1.7 times the old owner endpoint and 13.33% above C31. The change interpolates from the unchanged 660 s point
and rejoins the unchanged 780 s point. The 780/900 s endpoints remain 7.6875/8.25, preserving final-arrival
HP and its post-duration slope. This concentrates pressure before 900 s rather than repeating C30's failed
finale jump. All supply, rarity/card weights and other boss settings stay fixed; both full populations run.

| C32 policy | Clear / dead / timeout | Death-only median (deaths) | Mage / Lv30 medians (reaches) | MP collected / used | MP stock median | Late MP-wait runs / observed |
|---|---|---|---|---|---|---|
| Sensible | 31 / 30 / 0 (50.82%) | 900.15 s (30) | 277.7 s (60) / 618.8 s (57) | 13,344 / 10,840 = 1.231 | 36 | 13/60 |
| Random | 1 / 60 / 0 (1.64%) | 566.95 s (60) | 280.8 s (45) / 597.3 s (15) | 6,280 / 4,989 = 1.259 | 5 | 7/42 |

C32 is rejected: its sensible values fail both strict boundaries despite their proximity, and ordinary HP
pressure removes three random clears. Seeds28/42/55 die at 909.7/817.2/968.6 s with zero HP potions and
MP92/61/120. Only22 clears. Completed final fights are 31/46 sensible (median 96.23 s, 31; censored >=84.38 s,
46) and 1/4 random (76.58 s, one; censored >=44.13 s, four). The measured Mano damage support is insufficient
to offset this pre-finale HP increase; extra late HP pressure is not assumed to be selective.

C33 returns to C31's HP profile and damage relief, changing only normal MP supply: 10% through 660 s,
1.5% at both 720 and 780 s, recovering to 7.5% at 900 s and held thereafter. The deeper, longer pre-finale
trough targets high-Guard sensible demand while recovery aims to retain the 1.2–1.5 aggregate ratio. The four
random clears have much larger measured MP banks. This differs from C14's brief 2.5% trough with recovery
already at 780 s, and uses the stronger current ordinary HP profile. It is a measured timing hypothesis,
not an assumed policy advantage; altered pickups can still change movement and health. Both full populations run.
Interpolation is explicit: supply falls from 660 to 720 s, holds at 1.5% through 780 s, then recovery starts
at 780 s and reaches 7.5% at 900 s. Relative to C31's 4.5% hold, supply is lower from just after 660 to 840 s
and higher after 840 s; there is no instantaneous recovery at 900 s.

| C33 policy | Clear / dead / timeout | Death-only median (deaths) | Mage / Lv30 medians (reaches) | MP collected / used | MP stock median | Late MP-wait runs / observed |
|---|---|---|---|---|---|---|
| Sensible | 33 / 28 / 0 (54.10%) | 855.3 s (28) | 277.7 s (60) / 618.8 s (57) | 13,184 / 10,817 = 1.219 | 33 | 10/60 |
| Random | 3 / 58 / 0 (4.92%) | 562.95 s (58) | 280.8 s (45) / 597.3 s (15) | 6,262 / 5,043 = 1.242 | 5 | 7/42 |

C33 preserves a valid MP ratio and moves seventeen sensible deaths before 900 s but still leaves 33 clears.
Random loses seed28 at 938.5 s, with HP0/MP81 and a lower final Guard rank (10 versus12); 22/42/55 clear.
Pickup and progression changes therefore invalidate an assumption that a high final MP bank guarantees survival.
Completed final fights are 33/44 sensible (median 83.65 s, 33; censored >=78.88 s, 44) and 3/5 random
(median 91.98 s, three; censored >=84.73 s, five). C33 fails both clear-count bands and is rejected.

C34 changes only C33's Legendary/Epic weights from 0.8/3.5 to 0.5/3.8, keeping Normal/Rare/Unique at86/8/1.7.
The total non-Normal weight, Fortune base/scale and all stage/supply settings stay fixed. C24's earlier joint
rarity change added four sensible clears and one random clear, while the isolated routine Rare cut in C27
provided no clear-rate benefit. This motivates isolating max-out jackpots versus Epic gains rather than
assuming the earlier joint change established a single-tier causal effect. Meaningful Legendary offers remain;
both complete populations, including any new or lost random clears, determine acceptance.

| C34 policy | Clear / dead / timeout | Death-only median (deaths) | Mage / Lv30 medians (reaches) | MP collected / used | MP stock median | Late MP-wait runs / observed |
|---|---|---|---|---|---|---|
| Sensible | 32 / 29 / 0 (52.46%) | 865.8 s (29) | 277.7 s (60) / 620.5 s (58) | 12,857 / 10,784 = 1.192 | 26 | 11/60 |
| Random | 3 / 58 / 0 (4.92%) | 570.25 s (58) | 280.95 s (46) / 595.9 s (16) | 6,494 / 5,210 = 1.246 | 5 | 6/43 |

C34 removes one sensible clear but also lowers the aggregate MP ratio below 1.2; random still misses its
exact four-clear floor. Legendary offered/picked totals fall to 16/8 sensible and 12/3 random. Eighteen sensible
deaths precede 900 s. Completed final fights are 32/43 sensible (median 92.84 s, 32; censored >=79.07 s, 43)
and 3/6 random (91.98 s, three; censored >=63.14 s, six). The launched C33 supply profile was kept immutable
despite the later suggestion to use C31's flatter curve; C34 is rejected as final.

A read-only audit identifies room for the existing HG stage EXP multiplier without widening any guard.
C34 fixed training seeds1/2/2026 have Lv8 median243.2 s, Mage286.9 s and Lv30 629 s. A crude 2.5/2.4
time scaling would remain inside median windows, but it is not an actual simulation and can cross the first
boss arrival for late Mage builds. C31 random clears have Mage times268/284.6/289/294.1 s; even 2.45's
crude scaling moves one across300 s. Population testing must resolve that interaction rather than preserve
particular winners. Separately, C34 sensible clears average8.31 Bolt/Claw picks afterLv30 and29/32 finish
Guard20. Delaying a late offensive choice is a plausible pressure lever after Guard caps; this correlation
does not establish that lower EXP will reduce clears monotonically.

C35 retains C34's 86/8/3.8/1.7/0.5 rarity table and C31's Mano damage relief, restores C31's flat4.5% MP
endpoints at720/780/900 s, and changes only the HG stage EXP multiplier2.5→2.45. The failed MP trough is
removed to preserve more supply margin and the baseline random survival. HP endpoints, canonical EXP/stat
facts, survivor progression curve, starter state, potion behavior, card magnitudes, policies and fixed guards
stay unchanged. Both full populations measure the new progression lever and its first-boss interaction.

| C35 policy | Clear / dead / timeout | Death-only median (deaths) | Mage / Lv30 medians (reaches) | MP collected / used | MP stock median | Late MP-wait runs / observed |
|---|---|---|---|---|---|---|
| Sensible | 31 / 30 / 0 (50.82%) | 906.65 s (30) | 280.35 s (60) / 629 s (57) | 12,904 / 10,803 = 1.194 | 29 | 13/59 |
| Random | 3 / 58 / 0 (4.92%) | 514.25 s (58) | 284.8 s (41) / 601 s (11) | 5,184 / 4,120 = 1.258 | 4 | 1/34 |

C35 is rejected on sensible clear/death/MP boundaries and random clears. Only fourteen sensible deaths precede
900 s. Random Mage reaches fall 46→41 and Lv30 reaches16→11; the uniform EXP change affects the opening,
whereas the simultaneous MP change cannot act before 660 s. Twenty random deaths occur without Mage, all
exhausting HP stock (37 collected +100 starters =137 used), versus fifteen in C34 (22+75=97 used). These data
establish early fragility; they do not prove that more kill-dependent HP supply would selectively help weak builds.
Completed final fights are 31/47 sensible (median 90.4 s, 31; censored >=85.7 s, 47) and 3/3 random
(median 130.7 s, three; same censored median). The HP-income audit also rejects a proposed fixed-bundle/late-drop
transfer: C28's random winners kill more and collect more HP than sensible winners, while spending more health.

## Why EXP needs a stage curve now

After these 35 cohorts, uniform stage EXP is a poor proxy for the intended late offensive progression pressure.
The optional keyframe `exp_mult` therefore follows the existing held-curve contract, using stage-wide `exp_mult`
(default1) for missing endpoints, clamping each endpoint nonnegative before interpolation, and holding the nearest
endpoint outside the range without the spawn ramp. `SpawnDirector.exp_mult_at` supplies the value at kill time.
`RunWorld` multiplies canonical mob EXP by the global, stage and existing elite factors and rounds only once;
scheduled boss EXP remains governed by its independent reward configuration. No active curve is selected by
the source milestone, and the original 2.5 opening remains the next calibration baseline.

The first seeded public kill/drop test failed against the old runtime: fixed stage9 produced41 EXP where
the explicit endpoints required9/6/2. The minimal implementation passed it. Further public tests cover absent and
partial endpoint fallback, a mob killed after its spawn-time multiplier changes, negative endpoint clamping before
interpolation, zero EXP with no pickup, elite-factor rounding and an independent scheduled boss shower. The
focused EXP/potion/spawn/progression/boss-reward group passes49 tests, zero failures/skips. Existing out-of-range
HP/MP endpoint coverage still passes after the private interpolation helper is shared with an upper bound1 for
probabilities and no upper bound for EXP. Exact logs are `stage-exp-red.log`, `stage-exp-green.log`,
`stage-exp-focused.log` and `stage-exp-focused-final.log` under the root evidence directory.

The source mechanism is committed as `d14f1ee0414e10bb57aaed40a6f9fdfc42fefb8e` and merged/reviewed on
integration `3d66f0e6b1a5110ca475153bee6f18d688c0676a`. C36 uses that integration source; its pre-run context
records the new runtime and unchanged guard blobs rather than attributing late-curve runs to the earlier runtime.

C36 restores the original HG stage EXP fallback2.5 and sets optional keyframe EXP2.25 at720/780/900 s.
Missing earlier endpoints retain2.5, so interpolation starts at660 s, reaches2.25 at720 s and holds afterward.
Normal MP remains10% through660 s, tapers to5% at720 s and holds; this provides supply margin above C35's
ratio-deficient4.5% profile. Rarity86/8/3.8/1.7/0.5, C28 HP endpoints and Mano damage1.0 remain. All opening
stats, starters, canonical EXP, progression formulas, card magnitudes, policies and fixed guards stay unchanged.
Both complete populations test a 10% late progression reduction with the original opening; the completed results below reject it.

| C36 policy | Clear / dead / timeout | Death-only median (deaths) | Mage / Lv30 medians (reaches) | MP collected / used | MP stock median | Late MP-wait runs / observed |
|---|---|---|---|---|---|---|
| Sensible | 31 / 30 / 0 (50.82%) | 903.9 s (30) | 277.7 s (60) / 620.5 s (58) | 13,310 / 10,869 = 1.225 | 31 | 13/60 |
| Random | 2 / 59 / 0 (3.28%) | 574.3 s (59) | 280.95 s (46) / 595.9 s (16) | 6,681 / 5,265 = 1.269 | 5 | 6/43 |

C36 is rejected. The opening is preserved exactly: all122 policy/seed records match C34's Mage/Lv8/Lv10
observations and first-five-minute ordinary kill-hit buckets (`early-equivalence.json`). Late progression still
hurts weak builds: 22/28 clear, but 42/55 die at954.6/1,013 s with HP0 and MP69/122, with fewer late Guard
or attack ranks. Fourteen sensible deaths precede900 s. Completed final fights are31/47 sensible (median100.87 s,
31; censored>=90.9 s,47) and2/6 random (median92.56 s,two; censored>=51.04 s,six). The new curve successfully
separates the opening from late progression; reducing late EXP is not assumed to be policy-selective.

Integration `599590a9d86bb64dc8c6b5299df6f606fe828721` was merged after the complete C36 cohort.
Its reviewed `c96b5b5` refactor constructs fresh zero tier histograms from the shared tier list; it changes no
gameplay data, RNG or outcome. C36 remains attributed to its original3d66f0e source; later contexts use the new tip.

## Why the supply curve is a stage setting

Global MP reduction in C04 breaks the fixed opening, even though Blue Potions cannot fit the five-MP Beginner's
pool: altered ground pickups change the bot's route. The optional stage `normal_mp_drop_chance` therefore uses
the existing ordinary HP curve contract. Each endpoint clamps to [0, 1], missing endpoints use the global
normal chance, values interpolate linearly, and the nearest endpoint holds outside the range. Elite chances and
fixed boss bundles are independent. The field is survivor tuning, tier C.

The implementation was added through the agreed public seeded `RunWorld` drop/event seam. The failing test
first observed unchanged global late supply instead of the requested stage taper. Passing tests cover unchanged
opening supply and seeded sequence, later supply, missing-stage/endpoint fallback and clamping, plus unchanged
elite rolls and fixed boss bundles. The subsequent shared interpolation refactor preserves seeded totals.

## Health banking observation

C07's fixed training seeds 1, 2 and 2026 were separately stopped alive at 600 s to inspect stock. These records
are **timeouts**, not clears, and are stored in `c07-hp-tail/stock-at-600/`.

| Seed | Level | HP stock | HP collected / used | MP stock | MP collected / used |
|---|---|---|---|---|---|
| 1 | 28 | 6 | 18 / 17 | 28 | 110 / 82 |
| 2 | 30 | 24 | 30 / 11 | 0 | 130 / 130 |
| 2026 | 30 | 3 | 19 / 21 | 48 | 125 / 77 |

The sensible policy takes Orange at Lv10 and White at Lv25 in these records. Tier changes preserve every carried
potion, so earlier Red/Orange stock becomes 300-HP White stock. First White sips occur at 542.783/508.117/508.750 s,
restoring 151/151/164 HP and wasting 149/149/136 HP. The observed bank motivates reducing mid-run supply while
retaining the existing restoration, stock conversion and waste guard.

## Acceptance status

The selected-data focused group (`fortune potions boss_hit_bands data_files spawn_director`) passes **56 tests,
zero failures and zero skips**. `fortune86-red.log` preserves RED against nominal 75/18/5/1.7/0.3 data.
The initial prepared Fortune-zero Legendary band 0.6–1.0% rejected the selected 0.8% distribution's seeded
1.01% observation in 20,000 draws. The final independent literal band is 0.5–1.1%, about ±4.8 binomial sampling
standard deviations around the documented 0.8%; high-Fortune per-tier bounds remain independently pinned.
The old nominal sample 0.4% still fails the new lower bound. This adjusts the configured-odds statistical test's
sampling margin; neither full-run pacing nor boss damage guards change. Exact initial/final logs are
`c46-focused-initial-statistical-band.log` / `c46-focused-final.log`.

C37 (`c37-late-exp-support`) raised C36's late EXP endpoints from 2.25 to 3.0 with the same opening 2.5,
5% late MP and other data. It was stopped after the invalid Mano multiplier was identified. Thirty random
seed logs completed before the launcher and workers stopped; remaining files are incomplete. Its preserved
`full/aborted.json` labels it `aborted_incomplete_not_population_evidence`; no aggregate or acceptance claim
is drawn from this partial cohort.

C38 (`c38-late-exp-support-mano110`) is a fresh immutable support probe on source
`599590a9d86bb64dc8c6b5299df6f606fe828721`, identical to C37 except Mano damage 1.10. Opening stage EXP
remains 2.5 through 660 s, interpolates to 3.0 at 720 s and holds thereafter. Its first full 61-seed random
cohort tests whether late progression helps incomplete Guard builds without changing their opening; completed
outcomes and actual health margin will determine the next pressure pair. No held-out seeds are used.

C38 completes 3/61 random clears, 58 deaths and no timeouts: death median 561.05 s, Mage median 280.95 s
(46), Lv30 median 597.3 s (15), MP 6,386/5,048 = 1.2651, median MP stock five, and late waiting in six of
41 observed runs. Final levels are 5–44. Its first/second/final bosses complete 41/46, 13/25 and 3/5 spawned
fights, with completed medians 34.55 s (41), 63 s (13) and 101.58 s (3); all-spawn censored medians are
at least 34.29/46.25/93.93 s. Clears 22/28/42 retain 9/6/0 HP potions. Seed 55 dies at 915.2 s after
using all 43 HP potions (38 collected plus five starters), retaining 135 MP. Thus late EXP support does not
meet the strict four-clear minimum; no sensible support-only cohort is run.

C39 (`c39-epic-to-normal`) returns to the nearest valid full pair, C28 (33 sensible / four random clears),
and changes only the odds from 86/8/3.5/1.7/0.8 to **88/8/1.5/1.7/0.8**. Normal/Rare stacking cards both
give one rank, so C27's Rare→Normal shift did not remove a stacking step. This Epic→Normal shift targets
that step while preserving the Unique and Legendary boundaries and jackpot weight. This is a hypothesis,
not a predicted clear rate. All C28 stage/supply data, stage EXP 2.5, Fortune settings, card magnitudes,
policies and the valid Mano 1.15 multiplier remain unchanged. Both complete training cohorts run immutably
on source `599590a9d86bb64dc8c6b5299df6f606fe828721` before selection.

| C39 policy | Clear / dead / timeout | Death-only median (deaths) | Mage / Lv30 medians (reaches) | MP collected / used | MP stock median | Late MP-wait runs / observed |
|---|---|---|---|---|---|---|
| Sensible | 32 / 29 / 0 (52.46%) | 885.1 s (29) | 277.7 s (60) / 619.55 s (56) | 13,170 / 10,717 = 1.229 | 35 | 10/60 |
| Random | 1 / 60 / 0 (1.64%) | 562.65 s (60) | 280.8 s (45) / 597.3 s (13) | 6,197 / 4,913 = 1.261 | 5 | 8/42 |

C39 is rejected: removing one sensible clear costs three random clears. Former random winners 22/42 die at
669.1/661.9 s with no HP stock, and 55 dies at 897.6 s with no HP stock and 129 MP; only 28 clears. The fixed
sensible seeds 1/2/2026 end at levels 27/34/37. One other training seed, 15, ends at 50; this is reported without
changing the fixed `<50` guard or silently excluding a run. Final boss completions are 32/46 sensible (median
83.24 s, 32; all-spawn censored median at least 75.69 s) and 1/2 random (59.58 s, one; at least 42.2 s, two).

The next bounded matrix is frozen before running: C40 shifts one remaining Epic point to Normal
(89/8/0.5/1.7/0.8), with all other C39 data unchanged. C41 independently returns to valid C28 and shifts one
Unique point to Normal (**87/8/3.5/0.7/0.8**), preserving C28's Epic weight. The initially prepared C41 table
89/8/1.5/0.7/0.8 would have compounded the rejected Epic loss; it was superseded before any C41 worker launched,
and its exact patch/contexts remain in `c41-unrun-compounded-odds` labeled unrun. Each launched profile uses
the same thirteen-seed pilot for both policies; seeds 22/28/42/55 form a separately
labeled former-clear diagnostic and never enter the pilot aggregate. All five tiers remain nonzero. A profile
must be plausibly near the targets before expansion; neither the pilot nor this selected diagnostic can establish
full-population acceptance.

C40 finishes five sensible clears in thirteen (death median 950.45 s, MP 2,782/2,171 = 1.2814) and zero random
clears in thirteen (621.7 s, 1,564/1,245 = 1.2562). In the separately labeled diagnostic only 55 clears (977.5 s,
zero HP potions); 22/28/42 die at 669.1/706.9/619.9 s with no HP stock. The sensible pilot has exactly the same
five clear seeds as C39. This does not support expansion; C40 is rejected without a full cohort. Exact comparable
13-seed subsets of complete C28/C39 and the C40/C41 pilot/diagnostic results are in `odds-matrix-comparison.json`.

C41 also rejects expansion: six sensible clears in thirteen (death median 927.4 s, MP 2,784/2,190 = 1.2712),
zero random clears in thirteen (612.6 s, 1,527/1,223 = 1.2486), and no clears in the separate four-seed diagnostic.
Former winners 22/28/42/55 die at 673.3/689.6/661.9/897.6 s with zero HP stock. Preserving Epic's total weight
does not preserve its random-roll interval when Normal grows: C28's Epic interval is 94–97.5% but C41's is
95–98.5%. Thus early rolls can change from Epic to Rare. No claim of an isolated Unique effect follows.

C42 (`c42-mano110-valid`) returns to complete valid C28 and changes only Mano's damage 1.15→1.10, the
guard-compatible support comparator. It uses the same separate thirteen-seed pilots and four-seed diagnostic;
no EXP, odds, supply or other stage parameter changes. If this does not yield a plausible final pair, the next
bounded odds hypothesis is Unique→Epic **86/8/4.5/0.7/0.8**: this preserves both lower boundaries, the original
Epic interval and the Legendary boundary, replacing only the lower one-point slice of Unique with Epic.

C42 finishes six sensible clears in thirteen (death median 917.1 s, MP 2,722/2,117 = 1.2858) and zero random
clears in thirteen (605.8 s, 1,555/1,242 = 1.2520). All four former random winners clear with identical clear
times and final HP/MP stock to C28. The sensible clear count and death median also match C28's same-seed subset.
This supplies no measured pressure benefit, so C42 is not expanded solely because selected random survivors persist.

C43 (`c43-unique-to-epic`) runs the independent Unique→Epic hypothesis on otherwise unchanged C28, including
valid Mano 1.15. It screens the thirteen sensible training seeds first and then the four separately labeled random
diagnostic seeds. The standard random pilot is deliberately not run: the comparable C28 subset already has zero
clears and a further zero is a weak discriminator. A plausible candidate instead proceeds to both full cohorts.

C43 completes seven sensible clears in thirteen (death median 922.25 s, MP 2,815/2,201 = 1.2790), above C28's
six, and three of the four diagnostic random clears. Seed 28 dies at 701.6 s with exhausted HP stock and 94 MP,
ending Guard level five versus C28's twelve; the other three retain their clear times and stocks. This screen
does not support expansion, so no random pilot or full cohort is run for C43.

C44 (`c44-780-hp-plateau`) changes only C28's 780 s HP endpoint 7.6875→8.25, retaining 900 s at 8.25. The
existing formula makes the quarter-rate HP extrapolation zero, so HP is unchanged through 720 s, higher during
720–900 s and lower after 900 s than C28; other fields' post-duration slopes remain unchanged. This tested earlier
attrition with final-fight relief without changing the 900 endpoint. Only seed 22 clears in the four-seed diagnostic
(1,062.4 s, seven HP potions); 28/42/55 die at 937.7/949.7/900.3 s with exhausted HP and 88/62/126 MP. C44
is rejected at that gate and its prepared sensible pilot remains unrun.

C45 (`c45-hp-unlock-weight90`) returns to valid C28 and changes only Orange/White potion-card weights 30→90.
The independent audit found thirteen C28 random deaths at Lv25+ without White, whereas all four clears own it.
These are weighted eligible offers, not guaranteed potion slots: both policies' card paths can change. Earlier
C18/C20 potion-weight probes used different stage/odds data and do not isolate this lever. The new immutable
61-seed random cohort runs first; a full sensible cohort follows only if random reaches the 5–15% band. A selected
four-clear diagnostic cannot reveal new White recipients, so it does not gate this support probe.

C45 random completes two clears (24/35), 59 deaths, no timeouts: death median 559.9 s, Mage 280.8 s (45),
Lv30 581.8 s (13), MP 6,208/4,848 = 1.2805, median stock four and late waiting 8/39. White ownership rises
20→24 runs and Lv25+ deaths without White fall 13→8, but every run ends with zero HP stock and all four
former winners are lost. Final fights complete 2/5 (median 60.45 s, two; censored median at least 42.33 s,
five). Improving unlock access does not meet survival acceptance; C45 is rejected and sensible is not run.

C46 (`c46-late-mp-hp-shift`) tests one independent supply transfer on valid C28. At 720/780/900 s, normal MP
chance falls 0.045→0.040, while normal HP chance rises exactly 15%: 0.007/0.009/0.0105→
0.00805/0.01035/0.012075. Both curves begin interpolating after the unchanged 660 s endpoint, then hold
after 900 s. This targets C28's measured random HP exhaustion with 44–123 MP retained, while sensible max-Guard
builds pay more incoming damage in MP. C28 has 415.6 collected MP above the aggregate 1.2 floor; this is a
budget constraint, not a forecast that the changed cohort will pass. Opening, stage HP, odds, card weights and
bosses stay C28. The four random diagnostics run first, followed by sensible thirteen and complete cohorts only
if the screen is viable. All HP/MP collection/use/stock counts and the unchanged MP floor remain acceptance data.

The C46 four-seed diagnostic preserves all four clears. Seeds 22/28/42/55 finish with HP stock 8/2/0/0 and
MP 35/88/57/118, at 1,004.6/945.8/984.1/975.8 s. Seed 28 gains two carried HP potions; seed 55 uses three
additional late HP drinks and still clears. These are observed support margins, not a population acceptance claim.
The unchanged C46 pair proceeds to the thirteen-seed sensible screen.

C46's sensible screen gives five clears in thirteen (death median 927 s, MP 2,652/2,075 = 1.2781), versus
six in C28's same subset. Opening timings remain unchanged, so the intact pair expands to complete cohorts.

| C46 policy | Clear / dead / timeout | Death-only median (deaths) | Mage / Lv30 medians (reaches) | MP collected / used | MP stock median | Late MP-wait runs / observed |
|---|---|---|---|---|---|---|
| Sensible | 32 / 29 / 0 (52.46%) | 902.3 s (29) | 277.7 s (60) / 618.8 s (57) | 13,104 / 10,817 = 1.2114 | 30 | 13/60 |
| Random | 4 / 57 / 0 (6.56%) | 551.1 s (57) | 280.8 s (45) / 597.3 s (15) | 6,220 / 4,976 = 1.2500 | 4 | 7/41 |

C46 is rejected on both strict sensible clear/death targets. Only fourteen sensible deaths precede 900 s,
and the MP total has only 123.6 collected potions above the 1.2 floor. HP collection/use totals are 2,052/1,887
sensible and 1,044/1,339 random; starting HP stock totals 305 in each cohort. Final fights complete 32/47 sensible
(86.87 s median, 32; censored median at least 83.95 s, 47) and 4/5 random (79.96 s, four; at least 75.78 s, five).
The sole lost sensible clear, seed 7, changes from a clear with MP zero/15 HP potions to death at 1,080.2 s,
both stocks zero and 160.15 s late MP waiting; HP use rises 24→39. Thus MP pressure is observed, not assumed.

Random clear seeds remain 22/28/42/55; survivor counts at 660/720/780/900 s remain 15/13/8/5. Whole-cohort
HP drinks rise 57→58 in 660–720 s, 31→32 in 720–780 s, 37→39 in 780–900 s, and 14→21 after 900 s. All four
winners have the same number of pre-780 HP drinks as C28. Intermediate stock is not recorded, so this does not
prove unchanged health banking. Sensible survivors increase 50→51 at 780 s and 46→47 at 900 s. Exact observed
timing is preserved in `c46-late-mp-hp-shift/full/supply-timing-comparison.json`.

C47 (`c47-hp-support-delayed`) retains C46 MP 0.040 and HP780/900 0.01035/0.012075, but restores HP720
to C28's 0.007. This removes the early extra HP support (differences begin after 660 s and taper away at 780 s)
while preserving late/final-fight relief. Everything else remains C46/C28. Four random diagnostics run first;
if all four persist, the next step is full sensible 61, then full random if sensible is viable. A further
thirteen-seed screen cannot resolve the narrow two-clear gap and is not run.

While C47's immutable 599590a9 cohort runs, integration cleanup
`79f9d3fd1a56aba670303e20c9c440a89a5a0508` removes the unused EXP-keyframe mechanism and its EXP-only tests/docs.
This is the final-scope disposition of the rejected C36–C38 experiment, rather than an unused future API.
The explicit bridge at `evidence/spec30/review-fixes/exp-cleanup/` proves identical gameplay stage data excluding
documentation, zero keyframe EXP overrides on both stages, unchanged positive stage factors 2.5/0.9, identical
multiply/rounding order, and no RNG changes. Shared HP/MP probability interpolation stays intact. Existing focused
tests pass 62/62 before and after, with zero failures/skips and identical seeded potion totals. C47 measurements
remain attributed to 599590a9; cleanup must be merged before final data port and validation, without relabeling
the historical cohort's source.

C47 preserves all four diagnostic clears, then fails the full sensible cohort: 32 clears, 29 deaths, no timeouts,
death median 902.3 s, MP 13,095/10,780 = 1.21475, median MP stock 29 and late waiting 13/60. Clear count,
death median and fourteen pre-900 deaths are unchanged from C46. HP collection/use is 2,036/1,881. Final fights
complete 32/47 (median 82.525 s, 32; all-spawn censored median at least 81.1 s, 47). No full random cohort runs
because sensible already fails. Cleanup integration 79f9d3fd is merged after this cohort; fixed pacing guard
blob remains `4eb7f63a48b47e8f13f1bc347ebe26989fe83a99`.

C48 (`c48-late-mp375`) changes only C47's three late MP endpoints 0.040→0.0375, retaining all HP timing.
It runs on cleanup integration **79f9d3fd1a56aba670303e20c9c440a89a5a0508**. The tentative budget audit uses
the observed C28→C46 MP collection decline 13,294→13,104 for a 0.005 chance step. Half that decline for the
new half-size step suggests about 95 fewer collected potions, or 13,000/10,780 ≈1.20594 against C47's use.
This is only a plausibility estimate: HP support, pickup paths, duration and use also change, so actual full
MP ratio must still pass 1.2. C47 sensible clear MP margins include 0/0/3/7/8, versus the four diagnostic random
margins 35/88/51/118; seed 7's observed MP death supports the mechanism. Four diagnostics gate direct full
sensible, followed by full random only if sensible is viable. No other values or acceptance bounds change.

C48 fails the four-seed gate: only three clear. Seed 28 dies at 936.6 s with all 47 HP potions used, MP 78,
and Guard level ten versus C47's twelve. The other three clear, retaining MP 39/54/117. Lowering MP can change
pickup routes and subsequent card paths even without final MP exhaustion. No full cohort is run for C48.

C49 (`c49-tail-mp35`) delays MP pressure: C47's 720/780 endpoints stay 0.040, while 900 falls to 0.035 and
holds thereafter. All HP chances and other data remain C47. Every route through 780 s is preserved; the only
changed supply chance interpolates over 780–900 s. Source remains 79f9d3fd. Four diagnostics gate full sensible.

Its tentative budget uses actual C47 cumulative kill snapshots, differenced per minute with the final partial
interval included: 29,837 kills occur after 780 s. Applying the probability change at interval start/midpoint/end
estimates 78.50/102.18/125.86 fewer drop opportunities, fixed-use ratios 1.20747/1.20527/1.20307. This is
explicitly a **drop-exposure proxy**, not observed normal MP collection: all-kill counts include elites and bosses,
collection timestamps/source kinds are unrecorded, and changed paths/use/survival can invalidate the projection.
Actual full collection/use and all strict targets remain required. Exact audit is `c49-tail-mp35/tail-mp-budget-audit.json`.

C49 preserves four diagnostic clears but fails full sensible: 31 clears / 30 deaths / no timeouts, death median
902.85 s, MP 13,038/10,773 = 1.21025, stock median 28, late waiting 14/60 and only thirteen deaths before 900 s.
HP collection/use is 2,049/1,913. Final fights complete 31/48 (81.45 s median, 31; censored median at least
81.37 s, 48). Actual MP collection falls only 57 from C47; the tentative exposure projection was not treated
as an observed result. Full random is skipped because sensible fails.

The next audit finds sensible seeds 44/13/27 dying at 901.6/902.3/903.4 s with HP zero, MP 23/19/70 and
no MP waiting. Their last HP drinks occur at 844.35/818.95/862.33 s, supporting an earlier HP-budget lever.
**Guard evidence correction:** random 28's ending Guard levels differ in C47/C48, but the actual recorded casts
are identical in C47/C48/C49: level seven at 569.6 s (33%), level ten at 836.6 s (42%). The final-rank difference
therefore does not establish a different active Guard fraction or explain C48's loss. Choice timestamps are not
recorded; the comparisons retain the final-rank facts without claiming their timing or causality.

C50 (`c50-hp-trough-mp-tail`) changes C49's HP780 0.01035→0.009 and MP900 0.035→0.030, retaining
HP720 0.007 / HP900 0.012075 and MP720/780 0.040. HP differences begin after 720 s and end at 900 s;
MP differences begin after 780 s and hold after 900 s. Combined routes are preserved through **720 s**, not
780 s. This pairs pre-900 HP attrition with stronger final-fight MP pressure while keeping final HP relief.
If the next MP collection decline matched the prior 57, fixed-use ratio would be 1.20496, but actual totals
must still pass. Source stays 79f9d3fd; four diagnostics gate direct full sensible before any full random.

The exact C46 full training profile is frozen by owner acceptance, including the explicitly documented sensible
clear/death deviations. Final selected-data suite, six-case rendered matrix, exact three-record source bridge
and both independent review axes pass as recorded above. The released one-time 601–630 assessment is complete;
its larger sensible clear/death misses and absent random late waits are characterization, not a tuning input.
**601–630 is spent. Fresh 701–730 is reserved for a later feature candidate frozen before assessment.**
Spent or retired 101–130, 201–212, 301–330, 401–430, 501–530 and 601–630 are not reused for tuning or fresh
evidence. No further tuning follows this assessment, and no 701–730 run belongs to this pass.

## Reproduction

The following commands use **training seeds only**. Run the committed candidate from the integration worktree with its v83 cache installed. Unpatched commands use
the shipped survivor data; a historical probe additionally sets `PATCH` to its preserved `patch.json` and checks
out the immutable source commit in its context manifest. `ISOLATE` keeps this job's project mirror separate from
other Godot processes.

```bash
mkdir -p evidence/spec30/balance/reproduction/training/{bot,random}
ISOLATE=spec30_45 BALANCE_OUT="$PWD/evidence/spec30/balance/reproduction/training/bot" JOBS=12 \
  bash scripts/balance.sh 1..60 2026 --policy=bot \
  > "$PWD/evidence/spec30/balance/reproduction/training/bot-console.log" 2>&1
ISOLATE=spec30_45 BALANCE_OUT="$PWD/evidence/spec30/balance/reproduction/training/random" JOBS=12 \
  bash scripts/balance.sh 1..60 2026 --policy=random \
  > "$PWD/evidence/spec30/balance/reproduction/training/random-console.log" 2>&1
ISOLATE=spec30_45 bash scripts/test.sh full_run
```

The fixed full-run test executes seeds 1/2/2026 on both stages and retains the existing reached-milestone,
event, engagement, population, no-lost-mob
and all-boss finale guards. Presentation `missing` requires the separate rendered RunScene matrix; headless
balance records alone do not establish asset lookup completeness.

The completed held-out execution is an immutable historical record, not a replay recipe. Seeds 601–630 are spent;
701–730 remains reserved and unexecuted for this pass. To inspect existing evidence without launching Godot,
run this read-only hash check from the integration worktree that contains the ignored artifacts:

```bash
py - <<'PY'
import hashlib
import json
from pathlib import Path
root = Path.cwd()
seal_path = root / "evidence/spec30/balance/c46-heldout-frozen/heldout-seal.json"
assert hashlib.sha256(seal_path.read_bytes()).hexdigest() == "19371fd9d5f25188b18e593d836817e08b6ac4b4f77801dc5fba62578285cc25"
seal = json.loads(seal_path.read_text(encoding="utf-8"))
for path, expected in seal["files_sha256"].items():
    assert hashlib.sha256((root / path).read_bytes()).hexdigest() == expected, path
assert hashlib.sha256((root / "evidence/spec30/frozen_validation.json").read_bytes()).hexdigest() == seal["frozen_validation_sha256"]
assert hashlib.sha256((root / "evidence/spec30/balance/c46-late-mp-hp-shift/freeze.json").read_bytes()).hexdigest() == seal["training_seal_sha256"]
print(f"Verified {len(seal['files_sha256'])} preserved artifacts; no simulations launched.")
PY
```

Read `bot/henesys_hg1_bot_summary.json`, `random/henesys_hg1_random_summary.json` and the matching exact
`*_summary.log` reports under that directory for existing aggregates. Original raw records, hashes and markers
remain unchanged. Recomputing a display from those stored records is distinct from replaying their spent seeds.
