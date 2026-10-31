# level_curve

Generates `game/data/survivor/level_curve.json`: for levels 1-200, the `hp`, `pad`, `mad`, `pdd`, `mdd` and `exp` of an
ordinary v83 monster of that level. A stage's `level_scale` (docs/GAME_DESIGN.md 4.1, "Level scale") uses the ratio of two
levels' values to rescale a monster. The output holds numbers only (medians), no asset.

```bash
bash tools/level_curve/run.sh "<the owner's v83 folder>" 2026-10-30   # dump Mob.wz, generate, write the file
node --test tools/level_curve/test/*.test.mjs                          # synthetic-dump tests, no WZ data needed
```

`run.sh` builds `tools/wzimport`, runs `wzimport dump --wz <folder> Mob.wz --imgs 2` and pipes the text to
`generate.mjs`, which is plain Node with no dependencies. The date is an argument so the output is reproducible: the
same dump and date give the same bytes (the committed file used `2026-10-30`).

The method is written in the output's `_doc` (also with the exclusion counts and the sample count of every level):

1. Ordinary monsters only: not `boss=1`, not an `info/link` mob without stances, Mob.wz id below 9,000,000 (party quest,
   carnival, event, trial, GM and later-client content starts there), without the Balrog variants 6400005-6400009 and the
   Zakum, Horntail and Pink Bean bodies 88xxxxx; level 1-200.
2. A mob whose HP is above 5x its level's median HP is dropped.
3. Per level and stat the median; a mob whose value is 0 is skipped for that stat (most monsters below Lv30 have no
   magic attack, so their `MADamage` of 0 says nothing about magic damage).
4. Levels with no sample interpolate log-linearly; outside the sampled span (Lv1-131) the nearest value holds.
5. Made non-decreasing by weighted isotonic regression on the log values, then smoothed 1-2-1 over neighbouring levels.

Tier: the numbers are tier A-derived (v83 `Mob.wz` info), used for a tier C purpose (the survivor level scale).

CI: the node tests are not wired into `.github/workflows/pages.yml` yet; add `tools/level_curve/test/*.test.mjs` to its
`node --test` step.
