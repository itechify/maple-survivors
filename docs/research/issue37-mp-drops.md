# Issue #37: initial MP drop scarcity

The measurements below predate the merge of `main` through `02038d1` (#48/#49/#50). That integration preserves the
MP scarcity settings alongside upstream's potion RNG fix, Henesys HP trickle, boss fixes, level-10 Magician advancement
and report enhancements.
These historical numbers are not a fresh balance assessment of the merged simulation.

Merge validation (2026-10-15): 102 focused tests passed with no failures/skips across `balance_metrics`,
`data_files`, `potions`, `boss_rewards`, `boss_hit_bands`, `progression`, `player_stats` and `run_scene`.
Godot script typechecking, Bash syntax and whitespace checks passed. Rust synthetic/offline checks passed
29 tests; 17 real-WZ tests skipped because `MAPLE_WZ_ROOT` was unset, so they provide no real-data evidence.
The full Godot suite started against the intermediate #48/#49 integration was stopped when #50 merged into
main; it was not rerun after the final conflict resolution. No new full-suite or population-balance pass is claimed.

Measured 2026-10-14 with Godot 4.7.2 and the local original-v83 asset cache. Both variants use
Henesys Hunting Ground I, training seeds 1..12, fixed 1/60 s ticks, default 1800 s cap, kiting movement,
and either `bot` (sensible cards) or `random` (seeded random cards). No held-out seeds were run.

Baseline: commit `85e60901b802359d7591c295c301b4d18143de64`. Candidate: the same code/data except
normal MP chance 0.06 -> 0.02, elite MP chance 0.65 -> 0.30, default and four explicit boss MP bundles
6 -> 3. HP data is identical. The reporting change adds an aggregate ratio and does not change simulation.
These are the issue's starting values; this sample was not used to tune another candidate.

| Policy | Variant | MP collected | MP used | Collected / used | Median leftover | MP-short seconds min / median / max | Clears |
|---|---|---:|---:|---:|---:|---|---:|
| bot | baseline | 2341 | 1221 | 1.917 | 85 | 0 / 0 / 0 | 4/12 |
| bot | candidate | 515 | 484 | 1.064 | 0 | 21.833 / 116.884 / 184.833 | 0/12 |
| random | baseline | 1317 | 579 | 2.275 | 59.5 | 0 / 0 / 0 | 0/12 |
| random | candidate | 391 | 378 | 1.034 | 0 | 0 / 54.367 / 151.883 | 0/12 |

Ratio means total collected divided by total used within one policy, not an average of per-run ratios.
Leftover is collected minus used because MP starting stock is zero and stock has no cap. Every run not
cleared died; none timed out. Early deaths shorten collection/use observations, so these totals do not
compare equal-duration supply rates. Candidate random seed 6 dies at 2:47 without using any MP potions;
its collected potions still contribute to the policy totals.

Supply moves down toward, then below, the requested 1.2-1.5 ratio. The sensible bot's median stock is
far below the issue's historical 117, but the comparable baseline here is 85. The candidate overshoots:
all sensible runs experience MP waiting, and their clears fall from four to zero. This is evidence for
the follow-up balance pass (#42), **not a claim that the final MP economy or overall pacing target is met**.

Late waiting is confirmed with a same-seed prefix replay: candidate random seed 1 has 32.133 MP-short
seconds at the `--cap=480` timeout, versus 142.383 by death at 636.1 s in its full run. Thus 110.250 s
of waiting occurs after 8:00. This diagnostic cap is a TIMEOUT, not an extra clear or part of the 12-run aggregate.

## Reproduction and evidence

Validation: Godot's `--check-only` passes for `balance_run.gd`. The focused `balance_metrics potions boss_rewards`
suite passes all 22 tests with no skips. The full `scripts/test.sh` run completes 490 tests across 59 files:
**1 test failed, 0 skipped**. `test_full_run_real_map` fails three existing pacing assertions: neither stage
has at least two of seeds 1/2/2026 reach Lv30, and Tree seed 1 reaches Lv8 at 303.9 s, beyond its 270 s limit.
These guards remain unchanged. The initial scarcity candidate is not ready as final calibrated balance;
the draft PR records this regression for integration with #42. Standards/spec code review found no code defects.

On the baseline checkout and then the candidate checkout, with the same asset cache:

```bash
BALANCE_OUT="$PWD/_scratch/issue37/before" bash scripts/balance.sh 1..12 --policy=bot
BALANCE_OUT="$PWD/_scratch/issue37/before" bash scripts/balance.sh 1..12 --policy=random
BALANCE_OUT="$PWD/_scratch/issue37/after" JOBS=6 bash scripts/balance.sh 1..12 --policy=bot
BALANCE_OUT="$PWD/_scratch/issue37/after" JOBS=6 bash scripts/balance.sh 1..12 --policy=random
BALANCE_OUT="$PWD/_scratch/issue37/late_probe" bash scripts/balance.sh 1 --policy=random --cap=480
```

The original baseline simulations loaded their data before the edit and were summarized with the new
ratio reporter. The candidate bot shell's report phase was interrupted by editing its header while
it was running; all 12 simulations completed, and the unchanged report phase was replayed against
those logs without rerunning or discarding any seed. Raw records and aggregate JSON remain locally
under `_scratch/issue37/{before,after}`. The exact tables and `SYSTEMS` output are preserved below.

### Baseline sensible

```text
stage henesys_hg1, policy bot
seed  Lv8   Lv10  Lv20  Lv30  lv@4/8/12 alive4/8/12 near4/8/12 hit<6  hit8+  drop8  kills  level end            eng6/9/12 stale6/9/12 recyc/reloc
1     2:58  3:56  8:10  15:12 10/19/27  12/132/227  0/63/110   0      204    172    3286   30    DEAD     15:49 27/58/62  0/0/0       0/79
2     3:00  3:50  7:53  13:35 10/20/28  15/131/227  0/50/100   0      241    175    3927   36    CLEARED  16:38 18/61/64  0/0/0       0/73
3     2:58  3:57  7:57  14:28 10/20/26  14/129/227  0/46/111   4      256    260    3824   32    CLEARED  16:56 24/54/70  0/0/0       0/80
4     2:59  3:58  8:10  --:-- 10/19/    12/132/     0/51/-     0      98     139    2347   24    DEAD     11:07 26/55/-   1/1/-       0/56
5     3:04  4:02  8:10  --:-- 9/19/     15/127/     0/43/-     9      61     286    2308   23    DEAD     10:13 21/68/-   0/0/-       0/44
6     2:55  3:56  8:10  --:-- 10/19/    12/93/      0/17/-     3      91     242    2920   28    DEAD     11:31 14/56/-   0/0/-       0/48
7     3:00  3:59  8:07  --:-- 10/19/    14/109/     0/27/-     1      90     245    3017   28    DEAD     11:59 14/53/-   0/0/-       0/62
8     3:02  4:00  8:08  --:-- 9/19/     12/128/     0/39/-     0      58     258    2465   24    DEAD     10:37 19/54/-   0/0/-       0/56
9     2:58  4:01  7:38  11:19 9/20/31   13/55/222   0/8/100    2      212    213    6387   42    CLEARED  16:15 18/35/56  1/1/0       0/43
10    2:57  3:53  8:05  13:09 10/19/28  14/122/227  0/44/98    0      242    361    4225   33    CLEARED  16:53 24/51/65  0/2/0       0/76
11    3:01  4:08  8:13  --:-- 9/19/26   13/131/227  0/62/128   5      115    300    2516   27    DEAD     12:06 24/55/76  0/1/0       0/63
12    2:55  3:52  8:48  --:-- 10/18/25  12/133/227  0/54/106   2      223    113    2796   28    DEAD     15:23 27/61/67  1/0/0       0/87
SUMMARY 12 runs: 4 cleared, 8 died (at 15:49 11:07 10:13 11:31 11:59 10:37 12:06 15:23), 0 timed out
  Lv 8 2:55-3:04 (median 2:58, 12 runs), 12 in 2:30-3:45
  Lv 10 3:50-4:08 (median 3:57, 12 runs)
  Lv 30 11:19-15:12 (median 13:35, 5 runs), 4 at 12:00 or later
  final level 23-42 (median 28)
  engagement % (400 x 200 px) at 6:00 14-27 (median 22.5), 9:00 35-68 (median 55), 12:00 56-76 (median 65)
  stale % (20 s+ outside) at 6:00 0-1 (median 0), 9:00 0-2 (median 0), 12:00 0-0 (median 0)
  recycled % of spawns 0-0 (median 0); relocated per spawn % 43-87 (median 62.5)
SYSTEMS 12 runs: potions collected HP 370 MP 2341; used HP 391 MP 1221; MP collected/used 1.917; MP-short seconds 0.00/0.00/0.00 (n=12); campers reached 0/0 started
  boss whole-hit HP percent 34.45/44.37/50.24 (n=117)
  boss 2220000 fight seconds 11.53/19.26/31.48 (n=12); unfinished 0; not spawned 0
  boss 6130101 fight seconds 27.07/68.38/105.28 (n=9); unfinished 3; not spawned 0
  boss 9400205 fight seconds 75.78/105.82/116.37 (n=4); unfinished 2; not spawned 6
  boss 6130101 whole-hit HP percent 39.63/43.10/50.00 (n=63)
    touch HP percent 40.06/43.10/50.00 (n=53)
    attack HP percent 39.63/43.09/48.78 (n=10)
  boss 9400205 whole-hit HP percent 34.45/45.92/50.24 (n=29)
    touch HP percent 37.70/46.07/50.24 (n=26)
    attack HP percent 34.45/44.81/48.01 (n=3)
  boss 2220000 whole-hit HP percent 41.20/45.41/50.00 (n=25)
    touch HP percent 41.20/45.41/50.00 (n=25)
```

### Baseline random

```text
stage henesys_hg1, policy random
seed  Lv8   Lv10  Lv20  Lv30  lv@4/8/12 alive4/8/12 near4/8/12 hit<6  hit8+  drop8  kills  level end            eng6/9/12 stale6/9/12 recyc/reloc
1     2:57  3:55  8:03  --:-- 10/19/    14/131/     1/45/-     0      59     197    2330   24    DEAD     10:56 23/56/-   1/0/-       0/59
2     2:59  3:57  9:08  --:-- 10/18/    12/134/     0/55/-     2      34     82     1674   20    DEAD     9:55  28/61/-   3/0/-       0/65
3     3:03  4:04  8:10  --:-- 9/19/     15/132/     0/47/-     8      61     219    2186   23    DEAD     10:46 25/58/-   0/0/-       0/56
4     3:37  4:21  --:-- --:-- 9/19/     37/133/     7/54/-     7      0      152    1512   19    DEAD     8:17  40/-/-    1/-/-       0/55
5     2:55  4:00  --:-- --:-- 9//       15//        1/-/-      0      0      -      714    12    DEAD     5:20  -/-/-     -/-/-       0/45
6     3:33  4:12  8:10  --:-- 9/19/     37/113/     7/30/-     21     30     275    2008   22    DEAD     9:38  16/48/-   0/1/-       0/41
7     2:55  3:52  7:57  --:-- 10/20/27  13/113/227  0/30/116   0      116    273    2658   27    DEAD     12:23 16/64/69  2/1/0       0/66
8     3:00  3:52  8:00  --:-- 10/19/    13/129/     0/42/-     3      59     257    2274   23    DEAD     10:22 22/61/-   0/0/-       0/52
9     3:00  4:05  8:23  --:-- 9/19/     12/133/     0/57/-     6      0      118    1636   20    DEAD     8:39  36/-/-    3/-/-       0/45
10    2:59  3:53  8:02  --:-- 10/19/27  12/130/226  0/43/97    0      148    208    2966   28    DEAD     13:27 17/49/61  0/0/1       0/73
11    3:43  4:16  --:-- --:-- 9//       58//        13/-/-     33     0      -      574    12    DEAD     5:57  -/-/-     -/-/-       0/88
12    2:57  3:54  --:-- --:-- 10/17/    19/125/     2/45/-     2      27     58     1508   19    DEAD     9:28  45/47/-   1/2/-       0/68
SUMMARY 12 runs: 0 cleared, 12 died (at 10:56 9:55 10:46 8:17 5:20 9:38 12:23 10:22 8:39 13:27 5:57 9:28), 0 timed out
  Lv 8 2:55-3:43 (median 2:59, 12 runs), 12 in 2:30-3:45
  Lv 10 3:52-4:21 (median 3:58, 12 runs)
  Lv 30 none, 0 at 12:00 or later
  final level 12-28 (median 21)
  engagement % (400 x 200 px) at 6:00 16-45 (median 24), 9:00 47-64 (median 57), 12:00 61-69 (median 65)
  stale % (20 s+ outside) at 6:00 0-3 (median 1), 9:00 0-2 (median 0), 12:00 0-1 (median 0.5)
  recycled % of spawns 0-0 (median 0); relocated per spawn % 41-88 (median 57.5)
SYSTEMS 12 runs: potions collected HP 260 MP 1317; used HP 320 MP 579; MP collected/used 2.275; MP-short seconds 0.00/0.00/0.00 (n=12); campers reached 0/0 started
  boss whole-hit HP percent 32.71/44.23/51.09 (n=61)
  boss 2220000 fight seconds 13.73/33.55/169.22 (n=10); unfinished 2; not spawned 0
  boss 6130101 fight seconds 51.22/55.83/113.00 (n=3); unfinished 2; not spawned 7
  boss 9400205 fight seconds none (n=0); unfinished 0; not spawned 12
  boss 6130101 whole-hit HP percent 38.78/43.21/46.04 (n=17)
    touch HP percent 39.06/43.21/46.04 (n=16)
    attack HP percent 38.78/38.78/38.78 (n=1)
  boss 2220000 whole-hit HP percent 32.71/44.90/51.09 (n=44)
    touch HP percent 32.71/44.90/51.09 (n=44)
```

### Candidate sensible

```text
stage henesys_hg1, policy bot
seed  Lv8   Lv10  Lv20  Lv30  lv@4/8/12 alive4/8/12 near4/8/12 hit<6  hit8+  drop8  kills  level end            eng6/9/12 stale6/9/12 recyc/reloc
1     3:00  3:59  8:56  --:-- 10/18/    14/134/     0/57/-     0      65     132    1777   21    DEAD     10:17 23/61/-   1/0/-       0/70
2     2:59  4:01  8:14  --:-- 9/19/     13/130/     0/50/-     0      64     285    2212   23    DEAD     10:49 24/61/-   1/0/-       0/56
3     2:57  4:10  8:12  --:-- 9/19/     17/124/     0/48/-     1      97     286    2724   27    DEAD     11:49 24/51/-   1/1/-       0/56
4     2:59  4:02  --:-- --:-- 9/18/     11/134/     0/61/-     0      32     115    1542   19    DEAD     9:04  34/56/-   1/1/-       0/53
5     3:01  4:00  8:08  --:-- 9/19/     12/128/     0/47/-     0      66     213    2209   23    DEAD     10:51 18/61/-   0/0/-       0/53
6     2:55  3:48  7:58  --:-- 10/20/    13/116/     0/35/-     6      61     210    2381   23    DEAD     10:10 17/52/-   0/2/-       0/45
7     2:59  4:02  8:00  --:-- 9/19/     15/109/     0/33/-     0      92     257    2887   28    DEAD     11:33 18/60/-   0/0/-       0/42
8     3:02  4:00  8:22  --:-- 9/19/     17/133/     0/67/-     0      55     186    1980   22    DEAD     10:11 22/56/-   0/0/-       0/56
9     2:58  4:02  7:43  --:-- 9/20/     13/64/      0/8/-      7      83     233    2560   24    DEAD     11:01 17/45/-   0/1/-       0/49
10    2:55  3:56  8:03  --:-- 10/19/    14/122/     0/49/-     1      57     322    2357   24    DEAD     10:55 21/48/-   0/1/-       0/53
11    3:00  4:01  8:29  --:-- 9/19/     11/133/     0/52/-     7      52     147    1861   21    DEAD     10:10 23/66/-   1/1/-       0/59
12    2:57  3:59  --:-- --:-- 10/17/    15/134/     0/51/-     2      26     118    1490   19    DEAD     9:46  32/61/-   0/1/-       0/76
SUMMARY 12 runs: 0 cleared, 12 died (at 10:17 10:49 11:49 9:04 10:51 10:10 11:33 10:11 11:01 10:55 10:10 9:46), 0 timed out
  Lv 8 2:55-3:02 (median 2:59, 12 runs), 12 in 2:30-3:45
  Lv 10 3:48-4:10 (median 4:00, 12 runs)
  Lv 30 none, 0 at 12:00 or later
  final level 19-28 (median 23)
  engagement % (400 x 200 px) at 6:00 17-34 (median 22.5), 9:00 45-66 (median 58), 12:00 -
  stale % (20 s+ outside) at 6:00 0-1 (median 0), 9:00 0-2 (median 1), 12:00 -
  recycled % of spawns 0-0 (median 0); relocated per spawn % 42-76 (median 54.5)
SYSTEMS 12 runs: potions collected HP 296 MP 515; used HP 356 MP 484; MP collected/used 1.064; MP-short seconds 21.83/116.88/184.83 (n=12); campers reached 0/0 started
  boss whole-hit HP percent 37.55/45.41/50.33 (n=50)
  boss 2220000 fight seconds 12.43/33.60/65.95 (n=12); unfinished 0; not spawned 0
  boss 6130101 fight seconds 29.30/39.99/50.68 (n=2); unfinished 8; not spawned 2
  boss 9400205 fight seconds none (n=0); unfinished 0; not spawned 12
  boss 6130101 whole-hit HP percent 42.94/46.85/50.33 (n=26)
    touch HP percent 42.94/46.65/50.30 (n=21)
    attack HP percent 43.24/47.65/50.33 (n=5)
  boss 2220000 whole-hit HP percent 37.55/45.41/50.00 (n=24)
    touch HP percent 37.55/45.41/50.00 (n=24)
```

### Candidate random

```text
stage henesys_hg1, policy random
seed  Lv8   Lv10  Lv20  Lv30  lv@4/8/12 alive4/8/12 near4/8/12 hit<6  hit8+  drop8  kills  level end            eng6/9/12 stale6/9/12 recyc/reloc
1     2:57  3:49  8:08  --:-- 10/19/    13/131/     1/41/-     1      61     230    2100   22    DEAD     10:36 21/62/-   0/1/-       0/55
2     2:53  3:54  8:38  --:-- 10/19/    13/133/     0/52/-     12     29     70     1638   20    DEAD     9:15  49/69/-   1/0/-       0/53
3     2:59  3:54  8:01  --:-- 10/19/    14/132/     0/60/-     10     25     176    1940   22    DEAD     9:45  30/60/-   0/0/-       0/48
4     2:56  3:50  --:-- --:-- 10/17/    14/133/     0/66/-     0      31     91     1402   18    DEAD     9:03  30/46/-   3/0/-       0/69
5     2:58  3:55  8:27  --:-- 10/19/    14/134/     0/73/-     5      32     100    1707   20    DEAD     9:02  30/59/-   0/1/-       0/50
6     --:-- --:-- --:-- --:-- //        //          -/-/-      1      0      -      143    5     DEAD     2:47  -/-/-     -/-/-       0/70
7     2:58  3:57  8:04  --:-- 10/19/26  14/111/227  0/31/96    0      124    255    2500   26    DEAD     12:00 14/61/59  0/1/0       0/56
8     2:56  3:56  8:08  --:-- 10/19/    14/132/     0/50/-     5      59     199    2089   22    DEAD     10:01 24/63/-   1/0/-       0/49
9     2:57  3:58  --:-- --:-- 10/18/    19/135/     0/57/-     0      24     94     1439   19    DEAD     9:05  27/59/-   1/0/-       0/62
10    2:54  4:02  8:13  --:-- 9/19/     15/129/     0/41/-     2      68     225    2238   23    DEAD     10:42 23/56/-   0/1/-       0/57
11    3:51  4:44  --:-- --:-- 8//       59//        18/-/-     57     0      -      618    12    DEAD     6:36  55/-/-    2/-/-       0/87
12    2:56  3:56  --:-- --:-- 10/18/    19/133/     2/62/-     15     0      62     1428   19    DEAD     8:41  29/-/-    2/-/-       0/60
SUMMARY 12 runs: 0 cleared, 12 died (at 10:36 9:15 9:45 9:03 9:02 2:47 12:00 10:01 9:05 10:42 6:36 8:41), 0 timed out
  Lv 8 2:53-3:51 (median 2:57, 11 runs), 10 in 2:30-3:45
  Lv 10 3:49-4:44 (median 3:56, 11 runs)
  Lv 30 none, 0 at 12:00 or later
  final level 5-26 (median 20)
  engagement % (400 x 200 px) at 6:00 14-55 (median 29), 9:00 46-69 (median 60), 12:00 59-59 (median 59)
  stale % (20 s+ outside) at 6:00 0-3 (median 1), 9:00 0-1 (median 0), 12:00 0-0 (median 0)
  recycled % of spawns 0-0 (median 0); relocated per spawn % 48-87 (median 56.5)
SYSTEMS 12 runs: potions collected HP 259 MP 391; used HP 319 MP 378; MP collected/used 1.034; MP-short seconds 0.00/54.37/151.88 (n=12); campers reached 0/0 started
  boss whole-hit HP percent 31.36/44.39/49.49 (n=63)
  boss 2220000 fight seconds 17.67/28.67/57.60 (n=10); unfinished 1; not spawned 1
  boss 6130101 fight seconds 76.92/76.92/76.92 (n=1); unfinished 3; not spawned 8
  boss 9400205 fight seconds none (n=0); unfinished 0; not spawned 12
  boss 2220000 whole-hit HP percent 31.36/44.39/49.49 (n=51)
    touch HP percent 31.36/44.39/49.49 (n=51)
  boss 6130101 whole-hit HP percent 37.43/42.91/48.48 (n=12)
    touch HP percent 37.43/42.51/48.48 (n=11)
    attack HP percent 46.52/46.52/46.52 (n=1)
```
