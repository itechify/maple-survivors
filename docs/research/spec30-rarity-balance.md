# Spec #30 / #45: rarity balance summary

A short record of the #30 rarity calibration, kept for the dedicated balance pass. The full 46-candidate log, raw
records, hashes and consoles stay in ignored `evidence/spec30/` (`research-full-log.md` there is the original
1,100-line version of this file). Feature tickets no longer tune balance (AGENTS.md "Balance"), so this pass is
historical input, not a target the current data meets.

## Setup

Real v83 cache, Godot 4.7.2, fixed 1/60 s step, 800 × 600 view, Henesys Hunting Ground I, 1,800 s cap. Sensible
(`bot`) and careless (`random`) card policies share the kiting movement and potion decisions. Training seeds were
1–60 and 2026; pilots used 1–12 and 2026. Targets were sensible clears 40–50%, careless 5–15%, death-only median
300–900 s, sensible MP collected/used 1.2–1.5, and some careless MP waiting after 8:00.

## What the search learned

- **Rarity is a large power boost for a sensible player.** With the spec weights 75/18/5/1.7/0.3 and the
  pre-#30 stage data, 10/13 sensible pilot runs cleared while 0/13 careless runs did.
- **Lowering the odds alone hurts the wrong player.** 90/7/2/0.7/0.3 cut sensible clears only a little and
  removed what careless runs had left.
- **Global MP cuts break the v83 opening.** Fewer MP drops change the bot's early pickup routes, and fixed seeds
  died before Magician. This led to the optional per-stage `normal_mp_drop_chance` curve (same contract as the HP
  curve), which keeps the opening and tapers ordinary MP later.
- **HP banking carries sensible runs late.** Sensible runs banked potions mid-run, then turned them into 300 HP White
  Potions at Lv 25. Later HP support plus more late mob HP worked better than cutting HP drops early.
- **A stage EXP curve was tried and rejected.** Lowering late EXP by 10% (C36) hurt weak builds more than strong
  ones. The mechanism was removed.

## C46: the accepted state (before the owner's 2026-10-15 changes)

C46 used card weights 86/8/3.5/1.7/0.8, the older 1/1/2/3/max stacking and 1/1/2/3/5 new-skill ladders, and the
Henesys stage data now in `stages.json` (late HP multipliers ×1.2–1.5 from 8:00, extra late HP support, ordinary MP
10% to 11:00 then 4% from 12:00). The owner accepted it, then restored the spec weights and a strictly increasing
ladder without re-tuning (GAME_DESIGN 4.2 and 8.1). The shipped odds and ladder therefore differ from what was
measured here.

| C46 cohort | Sensible clear / dead | Sensible death median | Careless clear / dead | MP ratio (sensible / careless) | Late careless MP waits |
|---|---|---|---|---|---|
| Training 1–60 + 2026 | 32 / 29 (52.46%) | 902.3 s | 4 / 57 (6.56%) | 1.21 / 1.25 | 7 of 41 runs |
| Held-out 601–630 (spent) | 19 / 11 (63.33%) | 943 s | 4 / 26 (13.33%) | 1.30 / 1.36 | 0 of 16 runs |

Tier counts in the held-out cohort (sensible, 30 runs): offered 3035 / 484 / 125 / 63 / 19 Normal / Rare / Epic /
Unique / Legendary, picked 1040 / 144 / 39 / 15 / 4.

## For the balance pass

- The sensible bot scores cards by id and ignores tier and magnitude, so it doesn't prefer a jackpot. A human would,
  so measured sensible survival understates real players. Make `BotInput.card_score` tier-aware first.
- Re-measure with the shipped spec weights and the new ladder before changing any stage data.
- Seeds 601–630 are spent; 701–730 is the next fresh held-out range.

## Reproduction (training seeds only)

```bash
ISOLATE=balance BALANCE_OUT="$PWD/_scratch/balance/bot" bash scripts/balance.sh 1..60 2026 --policy=bot
ISOLATE=balance BALANCE_OUT="$PWD/_scratch/balance/random" bash scripts/balance.sh 1..60 2026 --policy=random
ISOLATE=balance bash scripts/test.sh full_run
```

To replay a C46 variant exactly, set `PATCH` to a `patch.json` from `evidence/spec30/balance/` and check out the
source commit named in that cohort's `context.json`.
