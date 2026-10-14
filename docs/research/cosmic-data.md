# cosmic-data: what the Cosmic server gives us as reference data and formulas

Scope: `C:\Users\itech\Coding\maple-survivors-refs\cosmic-server\`, a shallow clone of https://github.com/P0nk/Cosmic at commit `fec53bc7714dc0f1ae3f50b2986cdf2727e0912a` (2026-02-03), licensed AGPL-3.0. We only read it for facts. Nothing was built or run.

Paths below are relative to that repo root unless they say otherwise. Scratch scripts and raw dumps are in `C:\Users\itech\Coding\maple-survivors-refs\research\cosmic-data\`:
- `wzxml.mjs` is a minimal XML-tree parser written for this task.
- `skills.mjs`, `mobs.mjs` and `maps.mjs` are the extractors.
- Outputs: `exp_table.tsv` (all 200 levels), `skills_beginner.txt`, `skills_mage.txt`, `mobs.tsv`, `map_104040000.txt`, `maps_early.txt`.

## Summary

- **The server XML has gameplay numbers but no art or audio.** The `wz/*.xml` "Private Server" export keeps every `<canvas>` node with its `width`/`height`, `origin`, `lt`/`rb`, `head` and `delay` children. It does not keep pixel data: 555,619 canvases and 3,980 `<sound>` nodes, and zero `basedata`/base64 payloads across all of `wz/`. README.md:142-143 says the export is "stripped of sprites". So it is good for stats, frame timings, hitboxes and map layout, but all art and audio must come from `v83-original\*.wz`.
- **The XML comes from HeavenMS-edited WZ files, not vanilla ones.** README.md:145 says the server "requires custom .wz files". `docs/feature_list.md:19-24` says it is not a pure v83 server running on clean WZ. `docs/wzchanges_gist.txt` lists edits to Character, Map (portals), Item, Quest and String, but not Mob or Skill. So the mob and skill numbers are **probably vanilla, but UNVERIFIED** until cross-checked against `v83-original`. The "Strange ..." mobs (9400614-9400617) and Cynical Orange Mushroom (9300274) in the Henesys maps may be HeavenMS insertions (`docs/mychanges_ptbr.txt:1586`).
- **EXP table:** `src/main/java/constants/game/ExpTable.java:25`. Index = current level, value = EXP needed to reach the next level. Level 1 needs 15, level 10 needs 1,242, level 30 needs 63,800, level 70 needs 1,650,340 and level 120 needs 23,772,654. The client exe is packed, so these values cannot be checked against it statically.
- **Job advancement:**
  - Job ids are in `src/main/java/client/Job.java:25-63`.
  - 1st job is level 8 for Magician and level 10 for everyone else. The stat gates are INT 20, STR 35, DEX 25 (Bowman/Thief) and DEX 20 (Pirate) (`scripting/AbstractPlayerInteraction.java:1149-1192`).
  - 2nd job is level 30, 3rd job is level 70 (from level 50 in the 3rd-job NPC scripts) and 4th job is level 120 (`scripts/npc/*.js`).
- **Skills:** all per-level skill parameters are in `wz/Skill.wz/<job>.img.xml` and match the String.wz tooltips. The `mastery` field N in the XML means a mastery of (10+5N)%. The v83 skills we looked at have **no `dot`/`dotTime`/`range`/`lt`/`rb`** for single-target attacks.
  - Three Snails has `fixdamage` 10/25/40 and `mpCon` 3/5/7 with **no itemCon**, so it uses no shells. Shell use exists only in Cosmic's optional `USE_ULTRA_THREE_SNAILS` mode, which is off by default.
- **Damage is client-authoritative in v83.** Cosmic reads the damage number from the client packet (`AbstractDealDamageHandler.java:834`, `TakeDamageHandler.java:73`) and only checks it against loose upper limits (warn above 1.5x, autoban point above 5x; `:863`, `:868`). **Cosmic does not contain the real GMS hit formulas** for defence reduction, level difference, accuracy/avoid or min/max damage. What it does have:
  - a magic damage upper bound (`:622`)
  - the physical max-base formula (`Character.java:792-830`)
  - the Magic Guard split (`TakeDamageHandler.java:253-262`)
  - poison damage over time (`Monster.java:1222-1229`)
  - the EXP-share rules (`Monster.java:535-757`)
- **Mob stats** for the eight requested mobs are in the table below. `info` contains level, maxHP, maxMP, exp, PADamage, PDDamage, MADamage, MDDamage, acc, eva, speed, bodyAttack, pushed, undead and elemAttr. Cosmic **ignores** acc, eva, speed, pushed, bodyAttack and fs: grepping `server/life` finds none of them. Their meaning is client-side, so it is UNVERIFIED here.
- **Map 104040000 (Henesys Hunting Ground I):**
  - 39 mob spawn points: Pig ×9, Shroom ×10, Blue Snail ×8, Red Snail ×12.
  - 181 footholds, 8 ladders/ropes and 18 portals.
  - bgm `Bgm01/CavaBien`, mobRate 1.5.
  - The `info` node has no VR bounds, so bounds fall back to `miniMap` (2317×1832).
  - Cosmic parses `mobRate` but never uses it.
- **Licensing:**
  - The Java and JS code is AGPL-3.0, and the OdinMS headers say "only version 3". **Do not port code.**
  - BCrypt.java has its own permissive notice.
  - The `wz/` XML and the drop SQL are Nexon-derived or community-compiled data that Cosmic does not and cannot license.
  - Re-deriving numbers and formulas as facts, in our own code, is the low-risk path. This is not legal advice.

## Detailed findings

### 1. Architecture: what needs MySQL, sockets or a login server

| Component | Evidence | Relevant to us? |
|---|---|---|
| MySQL 8 database "cosmic" | README.md:61-75; `config.yaml:162-165` (`DB_URL_FORMAT: "jdbc:mysql://%s:3306/cosmic"`, DB_HOST/USER/PASS); `Server.java:869` `DatabaseConnection.initializeConnectionPool()`; schema and seed data through Liquibase (`src/main/java/database/DatabaseMigrations.java:3-5`, `src/main/resources/db/changelog-*.xml`) | No. Only the seed **data** in `src/main/resources/db/data/*.sql` (drops, shops, maker recipes) is useful as reference |
| Login server on TCP 8484 | `net/server/Server.java:936-938` (`initLoginServer(8484)`), `net/netty/LoginServer.java:9` | No |
| Channel servers on TCP 7575+ | `net/server/channel/Channel.java:78,131` (`BASE_PORT = 7575`, port = 7575 + (channel−1) + world×100) | No |
| WZ XML loader | `provider/wz/WZFiles.java:38-39` (`-Dwz-path`), `provider/wz/XMLDomMapleData.java:117-153`. `getData()` returns values only for int, short, float, double, string, uol and vector. A canvas or sound node returns `null` (falls to `default`) | This XML is the reference data |
| Scripting | GraalVM JS (`pom.xml` artifact `js`, `js-scriptengine`); `scripts/npc|quest|portal|event|map|reactor|item/*.js` (708 NPC scripts) | Read for rules only |

**The server XML has no pixels.** Evidence:

- `grep -rl "basedata\|base64" wz/` returns nothing.
- Element census across all `wz/**/*.xml`:

  | Element | Count |
  |---|---|
  | canvas | 555,619 |
  | sound | 3,980 |
  | imgdir | 2,638,625 |
  | int | 6,097,715 |
  | string | 1,768,867 |
  | uol | 724,834 |
  | vector | 1,086,788 |
  | float | 7,216 |
  | extended | 8,990 |
  | short | 2,192 |
  | double | 49 |
  | null | 357 |

- Size comparison:
  - Server `wz/Mob.wz` is 19 MB against 480 MB for the original `Mob.wz`.
  - `wz/Sound.wz` is 462 KB against 363 MB.
  - Example sound node: `<sound name="SleepyWood"/>` in `wz/Sound.wz/Bgm00.img.xml`, with no data.

What each requested file contains:

- **`wz/Mob.wz/0100100.img.xml`** (4,463 bytes):
  - `info` holds bodyAttack, level, maxHP, maxMP, speed, PADamage, PDDamage, MADamage, MDDamage, acc, eva, exp, undead, pushed, fs, summonType and mobType.
  - Animations: `move` (5 frames), `stand` (1), `hit1` (1), `die1` (9).
  - Each frame is a `<canvas name="0" width="37" height="26">` with `origin` (18,26), `lt` (−18,−26), `rb` (19,0), `head` and `delay` (180 ms on move). There is no bitmap.
  - **Conclusion:** frame counts, delays, origins and hitboxes (`lt`/`rb`) are usable directly. The bitmaps are not there.
- **`wz/Map.wz/Map/Map1/104040000.img.xml`** (198,646 bytes) has these sections:
  - `info`, line 3
  - `back`, line 16 (5 entries: `bS`, `no`, `x`, `y`, `rx`, `ry`, `type`, `cx`, `cy`, `a`, `front`, `ani`, `f`)
  - layers `0`-`7` (`info/tS`, `tile`, `obj` with `oS`/`l0`/`l1`/`l2`/x/y/z/f/zM)
  - `life`, line 93
  - `reactor`, line 4190
  - `ToolTip`, line 4192
  - `foothold`, line 4242
  - `ladderRope`, line 5714
  - `miniMap`, line 5780
  - `portal`, line 5789
- **`wz/Skill.wz/000.img.xml`** (102,786 bytes):
  - Structure is `skill/<7-digit id>/` with `icon`, `iconMouseOver` and `iconDisabled` canvases (32×32, no pixels).
  - `level/<n>/` holds the scalar params plus `ball`/`hit`/`effect` canvas sub-trees with delays.
  - Uses the old v83 "level table" format, not the later `common` formula strings.

### 2. EXP table

- Source: `src/main/java/constants/game/ExpTable.java:25`, an `int[] exp` with 201 entries (index 0..200).
- Lookup is `getExpNeededForLevel(level) { return level > 200 ? 2000000000 : exp[level]; }` (`:30-32`).
- Semantics: `exp[L]` is the EXP to go from level L to L+1. Evidence: `client/Character.java:3160` `while (exp.get() >= ExpTable.getExpNeededForLevel(level)) levelUp(true);`. In `levelUp`, the EXP is subtracted and then the level goes up (`Character.java:6376`, `:6382`).
- Full table: `research\cosmic-data\exp_table.tsv`.

| Lv | EXP to next | Lv | EXP to next | Lv | EXP to next |
|---|---|---|---|---|---|
| 1 | 15 | 11 | 1,573 | 21 | 16,268 |
| 2 | 34 | 12 | 2,144 | 22 | 19,320 |
| 3 | 57 | 13 | 2,800 | 23 | 22,880 |
| 4 | 92 | 14 | 3,640 | 24 | 27,008 |
| 5 | 135 | 15 | 4,700 | 25 | 31,477 |
| 6 | 372 | 16 | 5,893 | 26 | 36,600 |
| 7 | 560 | 17 | 7,360 | 27 | 42,444 |
| 8 | 840 | 18 | 9,144 | 28 | 48,720 |
| 9 | 1,144 | 19 | 11,120 | 29 | 55,813 |
| 10 | 1,242 | 20 | 13,477 | 30 | 63,800 |
| **70** | **1,650,340** | **120** | **23,772,654** | 200 | 1,697,021,059 (index 200; there is no level 201) |

Anomalies and unknowns:
- Index 162 and index 163 are **both 223,471,711**. This is the only place the sequence fails to increase, and it is probably a copy error. UNVERIFIED.
- `index 0 = 15` is not used for players.
- The client's own table could not be checked:
  - A byte search of `v83-original\MapleStory.exe` for int32 runs (15,34,57,92,135), (372,560,840) and (1144,1242), and for float64 runs, found nothing.
  - The PE sections have random names (`ytkjcptk`, `albasygk`, `jbhyjsdw`) and the first section's raw size (3.0 MB) is much smaller than its virtual size (8.4 MB), so the **exe is packed or protected**. Static verification is not possible.
- The same file also has tables for equipment level (`:26`), pet closeness (`:27`) and mount EXP (`:28`).

### 3. Jobs and advancement

**Job id enum** (`src/main/java/client/Job.java`):

| Line | Jobs |
|---|---|
| 25 | BEGINNER(0) |
| 27-30 | WARRIOR 100; FIGHTER 110 / CRUSADER 111 / HERO 112; PAGE 120 / WHITEKNIGHT 121 / PALADIN 122; SPEARMAN 130 / DRAGONKNIGHT 131 / DARKKNIGHT 132 |
| 32-35 | MAGICIAN 200; FP_WIZARD 210 / FP_MAGE 211 / FP_ARCHMAGE 212; IL_WIZARD 220 / IL_MAGE 221 / IL_ARCHMAGE 222; CLERIC 230 / PRIEST 231 / BISHOP 232 |
| 37-39 | BOWMAN 300; HUNTER 310 / RANGER 311 / BOWMASTER 312; CROSSBOWMAN 320 / SNIPER 321 / MARKSMAN 322 |
| 41-43 | THIEF 400; ASSASSIN 410 / HERMIT 411 / NIGHTLORD 412; BANDIT 420 / CHIEFBANDIT 421 / SHADOWER 422 |
| 45-47 | PIRATE 500; BRAWLER 510 / MARAUDER 511 / BUCCANEER 512; GUNSLINGER 520 / OUTLAW 521 / CORSAIR 522 |
| 49-63 | GM 900/910; Cygnus 1000-1512; Aran 2000, 2100-2112; Evan 2001, 2200-2218 |

`isA()` is at `:118-121`.

**Advancement requirements:**

| Advancement | NPC (id: name from `wz/String.wz/Npc.img.xml`) | Code |
|---|---|---|
| 1st Magician | 1032001 Grendel the Really Old | `scripts/npc/1032001.js:49-50` checks `getJobId()==0` and shows the "level should be at least 8" message. `:126` `if (cm.getLevel() >= 8 && cm.canGetFirstJob(jobType))`. `:135-137` `changeJobById(200); gainItem(1372043, 1); resetStats()` |
| 1st Warrior / Bowman / Thief / Pirate | 1022000 Dances with Balrog / 1012100 Athena Pierce / 1052001 Dark Lord / 1090000 Kyrin | Level ≥ 10 at `1022000.js:126`, `1012100.js:125`, `1052001.js:127`, `1090000.js:175` |
| 1st-job stat gate | (shared) | `src/main/java/scripting/AbstractPlayerInteraction.java:1149-1172`: case 1 `getStr() >= 35`, case 2 `getInt() >= 20`, case 3/4 `getDex() >= 25`, case 5 `getDex() >= 20`. **Skipped when `USE_AUTOASSIGN_STARTERS_AP` is true (`:1150-1152`), and the default `config.yaml:231` sets it to true.** `getFirstJobStatRequirement` is at `:1175-1192` |
| 2nd job (lv 30) | same five NPCs. The test is with 1072000-1072003 / 1072008, the "Job Instructor" NPCs. Letter item 4031009, proof item 4031012 | `1032001.js:52` `cm.getLevel() >= 30 && cm.getJobId() == 200`. Choice of 210/220/230 at `:196` (`job += selection * 10`) |
| 3rd job (lv 70) | Tylus 2020008, Robeira 2020009 (magician, `jobStyle = 2`), Rene 2020010, Arec 2020011, Pedro 2020013 | `2020009.js:31` `getLevel() >= 70 && ... getJobId() % 10 == 0`. Quest flow starts at lv 50 (`:32`, `:124`). The job-instructor side is `1032001.js:62` (`gotPartyQuestItem("JB3") && getLevel() >= 70`) |
| 4th job (lv 120) | Harmonia 2081100, Gritto 2081200 (Mage), Legor 2081300, Hellin 2081400, Samuel 2081500 | `2081200.js:50` `if (cm.getLevel() < 120 \|\| Math.floor(cm.getJobId() / 100) != 2)`. `:65` `changeJobById(getJobId() + 1)` |

**Job-change and level-up rewards** (`client/Character.java`). These are emulator choices, UNVERIFIED against GMS:

| Event | Reward | Line |
|---|---|---|
| Job change | +1 SP, or +3 SP for 4th job | `:1154-1165` |
| Job change | +5 AP for jobs with `id % 10 >= 1`, unless USE_STARTING_AP_4 | `:1172-1184` |
| Job change | +4 slots per inventory | `:1187-1190` |
| Job change, 1st Mage | MaxMP +rand(100,150) | `:1196` |
| Job change, 2nd-4th Mage | MaxMP +rand(450,500) | `:1203` |
| Job change, 1st Warrior | MaxHP +rand(200,250) | `:1194` |
| Level-up | +5 AP | `:6308` |
| Level-up (job branch ≥ 1) | +3 SP | `:6271` |
| Level-up, Beginner | HP +rand(12,16), MP +rand(10,12) | `:6325-6326` |
| Level-up, Magician | HP +rand(10,14), MP +rand(22,24), plus Improved MaxMP Increase `x` | `:6340-6341` |
| Level-up, Magician (USE_RANDOMIZE_HPMP_GAIN, default true at `config.yaml:226`) | +INT/20 MP | `:6367` |
| Level-up, Beginner ≤ lv 10 (autoassign) | STR +5 below lv 6; STR +4 / DEX +1 from lv 6 | `:6288-6303` |

### 4. Skills: per-level parameters from server Skill.wz

**Files:**
- Beginner skills: `wz/Skill.wz/000.img.xml`. Three Snails is `0001000` at line 520, Recovery `0001001` at :342, Nimble Feet `0001002` at :433.
- Magician skills: `wz/Skill.wz/200.img.xml`. Lines: 2000000 :9, 2000001 :73, 2001002 :142, 2001003 :345, 2001004 :487, 2001005 :678.
- F/P Wizard skills: `wz/Skill.wz/210.img.xml`. Lines: 2100000 :9, 2101001 :151, 2101002 :405, 2101003 :521, 2101005 :780, 2101004 :1123.
- Tooltips: `wz/String.wz/Skill.img.xml`.

**How Cosmic loads the fields:** `server/StatEffect.java:241-490`.

| Field | Default when absent | Line |
|---|---|---|
| `time` | −1 (stored in seconds, ×1000 for skills) | :241, :301 |
| `prop` | 100 (stored as /100) | :248 |
| `mobCount` | 1 | :272 |
| `cooltime` | – | :273 |
| `pad`/`pdd`/`mad`/`mdd`/`acc`/`eva`/`speed`/`jump` | – | :306-314 |
| `damage` | 100 | :483 |
| `fixdamage` | −1 | :484 |
| `attackCount` | 1 | :485 |
| `bulletCount` | – | :486 |
| `itemCon` / `itemConNo` | – | :489-490 |

- `grep -c 'name="dot"\|name="dotTime"' wz/Skill.wz/*.xml` returns 0 in every file. **v83 has no `dot`/`dotTime` fields.** Poison damage over time is computed by the server (section 5).
- `itemCon` appears only in `1411`, `231`, `311`, `321`, `411` and `521.img.xml`, all 3rd-job files. None of the skills below has it.
- The `mastery` field maps to mastery% as **(10 + 5×mastery)**. For example, Energy Bolt L1 has `mastery=1` and the tooltip says "mastery 15%"; L20 has `mastery=10` and says "60%" (`String.wz/Skill.img.xml:259+`).

| Skill (id) | Max Lv | Fields present | Level 1 | Max level |
|---|---|---|---|---|
| Three Snails (1000) | 3 | mpCon, fixdamage; ball+hit anims | mpCon 3, fixdamage 10 | L3: mpCon 7, fixdamage 40 (L2: 5 / 25) |
| Recovery (1001) | 3 | mpCon, time, x, cooltime | mpCon 5, time 30 s, x 4, cooltime 120 s | L3: mpCon 15, x 12 |
| Nimble Feet (1002) | 3 | mpCon, time, speed, cooltime | mpCon 4, time 4 s, speed +10, cooltime 60 s | L3: mpCon 10, time 12 s, speed +20 |
| Improved MP Recovery (2000000) | 16 | **none**: the level nodes are empty | – | – (effect is hardcoded in the client; the tooltip only says "Constant additional recovery of MP") |
| Improved MaxMP Increase (2000001) | 10 | x, y; req {2000000: 5} | x 2 (per level-up), y 1 (per AP) | L10: x 20, y 10 |
| Magic Guard (2001002) | 20 | time, mpCon, x | time 111 s, mpCon 6, x 11 (% of damage taken from MP) | L20: time 600 s, mpCon 12, x 80 |
| Magic Armor (2001003) | 20 | time, mpCon, pdd; req {2001002: 3} | time 54 s, mpCon 8, pdd +2 | L20: time 400 s, mpCon 16, pdd +40 |
| Energy Bolt (2001004) | 20 | mpCon, mad, mastery | mpCon 6, mad 20, mastery 1 (15%) | L20: mpCon 14, mad 55, mastery 10 (60%) |
| Magic Claw (2001005) | 20 | mpCon, mad, mastery, attackCount; req {2001004: 1}; `CharLevel/10` alternate hit anim | mpCon 10, mad 11, mastery 1, attackCount 2 | L20: mpCon 20, mad 40, mastery 10, attackCount 2 |
| MP Eater (2100000) | 20 | prop, x | prop 11%, x 21 (% of mob MaxMP absorbed) | L20: prop 30, x 40 |
| Meditation (2101001) | 20 | mpCon, time, mad, lt, rb; req {2100000: 3} | mpCon 10, time 10 s, mad +1, area lt(−250,−150) rb(250,150) | L20: mpCon 20, time 200 s, mad +20, lt(−300,−200) rb(300,200) from L11 |
| Teleport (2101002) | 20 | mpCon, range | mpCon 60, range 130 | L20: mpCon 13, range 150 |
| Slow (2101003) | 20 | mpCon, x, time, lt, rb, mobCount; req {2101002: 5} | mpCon 8, x −2 (speed), time 2 s, lt(−200,−150) rb(200,150), mobCount 6 | L20: mpCon 16, x −40, time 40 s, lt(−250,−150) rb(250,150) |
| Fire Arrow (2101004) | 30 | elemAttr "f"; mpCon, mad, mastery | mpCon 14, mad 33, mastery 1 | L30: mpCon 28 (from L16), mad 120, mastery 10 |
| Poison Breath (2101005) | 30 | elemAttr "s"; mpCon, mad, mastery, prop, time; `mob` anim dir | mpCon 10, mad 12, mastery 1, prop 31%, time 4 s | L30: mpCon 20 (from L16), mad 70, mastery 10, prop 60%, time 40 s |

Per-level dumps for all levels are in `research\cosmic-data\skills_beginner.txt` and `skills_mage.txt`.

- **Three Snails:**
  - The data has no `itemCon`/`itemConNo`, so it consumes **nothing but MP**. The tooltip agrees: "MP -3; Damage 10" (`String.wz/Skill.img.xml:10-16`).
  - Cosmic enforces `fixdamage` exactly: any other non-zero total triggers autoban (`AbstractDealDamageHandler.java:462-465`).
  - Shell consumption exists only under `USE_ULTRA_THREE_SNAILS`, a custom mode where damage is multiplied by player level (`:469-488`). It is **false** by default (`config.yaml:348`).
  - Code bug, harmless: `constants/skills/Beginner.java:31` declares `THREE_SNAILS = 1001`, the same value as `RECOVERY` at `:32`. The live code instead computes `jobType*10000000 + 1000` (`AbstractDealDamageHandler.java:467`).
- **No range fields on single-target bolts:** Energy Bolt, Magic Claw, Fire Arrow and Poison Breath have **no `range`, `lt`/`rb` or `mobCount`**, so `mobCount` defaults to 1. Their reach is hardcoded in the client: UNVERIFIED value, to be taken from the client or from observation.
- **Data anomalies:**
  - (a) Recovery data says `mpCon` 5/10/15, but String.wz h1-h3 says "MP -10/20/30; Recover HP 24/48/72 in 30 sec". `x×6` matches the HP (one tick every 5 s, inferred). `mpCon` does not match.
  - (b) Poison Breath L29 has `time=58`, while L28 and L30 have 40. This is probably a Nexon data typo.
  - (c) Energy Bolt L9: data `mad=32` but tooltip "basic attack 33".

### 5. Damage and EXP formulas

**Headline: the v83 client computes damage, both player-to-mob and mob-to-player.**
- Player attacks: Cosmic reads each damage line from the packet (`net/server/channel/handlers/AbstractDealDamageHandler.java:834`). It compares the line to a computed `calcDmgMax`, only warns above `maxWithCrit*1.5` (`:863`), and adds an autoban point above `*5` (`:868`).
- Damage taken: `TakeDamageHandler.java:73` reads `int damage = p.readInt();` from the client and applies it.
- So **Cosmic does not have GMS's real accuracy/avoid, defence-reduction, level-difference or min-damage formulas.** These live in the packed `MapleStory.exe` and are UNVERIFIED.

**What Cosmic does have:**

| Formula | Location | Code (paraphrased) | Notes |
|---|---|---|---|
| Magic attack **cap** (anti-cheat bound) | `AbstractDealDamageHandler.java:621-622, 662` | `cap = ceil((M*ceil(M/1000) + M)/30) + ceil(INT/200)`, where M = total magic attack; then `cap *= skill.mad` (`effect.getMatk()`) | A loose upper bound in the shape of the well-known community formula `((M²/1000 + M)/30 + INT/200) × spell attack`, but with `ceil(M/1000)` instead of `M/1000`. Treat it as Cosmic's cap, not the true formula. Element Amplification at `:640-660`; Heal at `:663-668` |
| Physical max base damage | `client/Character.java:792-809` | `ceil((weaponMultiplier × mainStat + secondaryStat)/100 × WATK)`. Bow, crossbow and gun use DEX/STR. Claw and thief dagger use LUK/(DEX+STR). Everything else uses STR/DEX | Multipliers per weapon are in `WeaponType` (not dumped). Bare-handed pirate at `:816-826`. Skill `damage%` is applied at `AbstractDealDamageHandler.java:676` |
| `calculateMaxBaseMagicDamage` (stat-window style) | `Character.java:832-850` | `(matk − INT + 0.1996049769·INT^1.290631341) × 107/100` for INT ≤ 1700, with other branches above that | Used only for summons (`SummonDamageHandler.java:128`). Emulator curve fit. UNVERIFIED |
| `fixdamage` override | `AbstractDealDamageHandler.java:750-755` | If `fixdamage > 0`, then `calcDmgMax = fixdamage` | Three Snails |
| Elemental weakness | `:795-808` | ×1.5 if the mob is WEAK to the skill element. STRONG (×0.5) is commented out | elemAttr letters: F fire, I ice, L lightning, S poison, H holy, D dark, P physical (`server/life/Element.java:43-61`). Digits: 1 IMMUNE, 2 STRONG, 3 WEAK (`ElementalEffectiveness.java:27-34`, `LifeFactory.java:288-290`) |
| Crit cap | `:738-746, 856-859` | Only some classes can crit (×2 cap). Sharp Eyes ×1.4 | Mage cannot crit in v83 Cosmic |
| Poison damage over time (Poison Breath) | `server/life/Monster.java:1222-1229`, `:1629-1647` | Every **1000 ms**: `ceil(maxHP / (70 − skillLevel))`, capped at 32767. **Cannot kill**: damage is clamped to `curHp − 1` | Duration = skill `time`. Proc chance = `prop`. Bosses are immune to most statuses (`:1172-1177`). Poison status needs the mob not to be IMMUNE/STRONG (`:1138-1150`) |
| Magic Guard | `TakeDamageHandler.java:253-262` | `mpLoss = floor(damage × x/100)`, `hpLoss = damage − mpLoss`. If `mpLoss > curMP`, the overflow goes to HP | x from 2001002 (11 to 80) |
| Mob vs player damage | **not in Cosmic** (client) | – | Only an attack-info lookup (`MobAttackInfoFactory`) for MP burn, disease and deadly attacks (`TakeDamageHandler.java:155-189`) |
| Mob vs mob (hypnotize) cap | `MobDamageMobHandler.java:80-101` | Physical: `(PAD × (1.15 + 0.025×mobLevel) − 0.75×PDD) × ln\|PDD − PAD\| / ln 17` (`:98`). Magic uses MAD/MDD and ln 12 (`:90`) | The only server formula that uses mob PDD. Emulator approximation, **not** the GMS player formula |
| Power Guard / Achilles / Combo Barrier | `TakeDamageHandler.java:208-247` | (for completeness) | – |
| Natural HP/MP regen (incl. Improved MP Recovery) | client-side; `HealOvertimeHandler.java:46-71` only accepts the client's value (HP cap `77 × map.recovery × 1.5`) | – | UNVERIFIED formula |

**Mob EXP share** (`server/life/Monster.java`):
- `expPerDmg = mobExp / maxHpPlusHeal` (`:639-640`).
- Solo players: `exp = damageDealt × expPerDmg × (EXP_SPLIT_COMMON_MOD × lvl/lvl + EXP_SPLIT_MVP_MOD)` (`:535-543`, called at `:671` with highestDamager=true). With `config.yaml:295-296` (0.2 / 0.8), that is **100% of the mob's exp** if you dealt all the damage.
- Party: `0.8 × memberLevel/totalPartyLevel`, +0.2 for the top damager, and a party bonus of `0.05 × members` (`:548-600`).
- Multipliers: Holy Symbol (`getStatusExpMultiplier`, `:692-715`), then `getExpRate()` (`:731-732`), then rounding (`expValueToInteger`, `:718-725`).
- **Level-range rule:** `USE_ENFORCE_MOB_LEVEL_RANGE` (`config.yaml:243`) applies **only to party members** (the leech interval ±5 at `:549-578`). The solo path has **no level-difference penalty**. GMS v83 did not have the later Big Bang level-gap EXP modifiers either (UNVERIFIED).

**Drops:**
- `MapleMap.java:654-690` (chance test at `:669`): an item drops if `rand(999999) < chance × rate`, so chance is out of 1,000,000.
- Mesos are `rand(min..max)`, then the Meso Up buff, then the rate.
- Drop tables are in `src/main/resources/db/data/152-drop-data.sql`. For example, Snail 100100 drops:

  | Item | Chance | Quantity |
  |---|---|---|
  | 4000019 (Snail Shell) | 600000 | 1 |
  | 2000000 | 20000 | 1 |
  | 2060000 | 30000 | 1-2 |
  | 2040002 | 300 | 1 |
  | 2041001 | 300 | 1 |

  These are community-compiled. GMS drops were server-side, so no client file holds them.

### 6. Mob stats (server `wz/Mob.wz/<id>.img.xml` → `info`)

Names come from `wz/String.wz/Mob.img.xml`. In every row: boss = absent (0), undead 0, `bodyAttack` 1, `pushed` 1 and `fs` 10.0.

| id | Name | Lv | maxHP | maxMP | exp | PAD | PDD | MAD | MDD | acc | eva | speed | elemAttr | mobType | Anim frames (move/stand/hit1/die1, plus jump) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 0100100 | Snail | 1 | 8 | 0 | 3 | 12 | 0 | 0 | 0 | 20 | 0 | −65 | – | 0 | 5/1/1/9 |
| 0100101 | Blue Snail | 2 | 15 | 15 | 4 | 17 | 0 | 0 | 0 | 20 | 0 | −50 | – | 0 | 4/1/1/3 |
| 0120100 | Shroom | 2 | 20 | 15 | 5 | 17 | 0 | 0 | 0 | 30 | 0 | −30 | – | 4 | 4/3/1/4 |
| 0130101 | Red Snail | 4 | 40 | 30 | 8 | 27 | 3 | 0 | 10 | 35 | 0 | −50 | – | 0 | 4/1/1/3 |
| 0210100 | Slime | 6 | 50 | 35 | 10 | 32 | 5 | 0 | 10 | 35 | 1 | −20 | L3 (weak to lightning) | 5 | 7/3/1/4 + jump 1 |
| 1210100 | Pig | 7 | 75 | 40 | 15 | 37 | 5 | 0 | 20 | 40 | 0 | 0 | – | 0 | 3/3/1/3 + jump 1 |
| 1210102 | Orange Mushroom | 8 | 80 | 45 | 15 | 42 | 0 | 0 | 10 | 42 | 1 | 0 | – | 4 | 3/2/1/3 + jump 1 |
| 1110100 | Green Mushroom | 15 | 250 | 25 | 26 | 82 | 12 | 0 | 40 | 45 | 5 | −20 | S1 (immune to poison) | 4 | 4/3/1/4 |

Machine-readable copy: `research\cosmic-data\mobs.tsv`.

None of these mobs has `attack1` or `skill` nodes. They only deal touch damage (`bodyAttack=1`, packet `damagefrom == -1`; `TakeDamageHandler.java:208`).

Cosmic parses level, maxHP, maxMP, exp, PAD/PDD/MAD/MDD, boss, undead, elemAttr, link, firstAttack, revive, skills and attacks (`server/life/LifeFactory.java:108-248`). **It never reads `acc`, `eva`, `speed`, `pushed`, `bodyAttack`, `fs`, `mobType` or `summonType`** (grep of `src/main/java/server/life` finds no match). Our working guesses for those fields, all UNVERIFIED:
- `speed`: percent offset from base move speed
- `pushed`: knockback damage threshold
- `fs`: friction/slide
- `bodyAttack`: whether touching the mob deals damage

### 7. Map 104040000 and nearby early maps

**104040000 "Victoria Road : Henesys Hunting Ground I"** (`String.wz/Map.img.xml:877`). Full dump: `research\cosmic-data\map_104040000.txt`.

- **`info`:**
  - version 10, cloud 0, town 0, returnMap 100000000, forcedReturn 999999999, mapMark "Henesys"
  - **mobRate 1.499998**, **bgm "Bgm01/CavaBien"**
  - **No VRTop/VRLeft/VRBottom/VRRight.** Cosmic then falls back to `miniMap`: centerX 530, centerY 1278, width 2317, height 1832, mag 4 (`MapFactory.java:174-185`).
- **`life`:**
  - 39 mobs, each with keys type, id, x, y, mobTime 0, f, hide, fh, cy, rx0, rx1.
  - Counts: Shroom 0120100 ×10, Blue Snail 0100101 ×8, Red Snail 0130101 ×12, Pig 1210100 ×9.
  - Plus NPC 9000068.
  - They sit on 4 platform tiers: y≈185-196 (rx −469..1729), y≈−92..−129, y≈−341..−422, y≈−583..−616.
  - Example row: `{"type":"m","id":"0120100","x":"157","y":"185","mobTime":"0","f":"0","hide":"0","fh":"135","cy":"215","rx0":"-469","rx1":"1729"}`
- **`foothold`:**
  - 181 segments in 1 layer, spanning x[−489, 1749] and y[−1105, 480].
  - Each has x1, y1, x2, y2, prev, next. Example: `{x1:1311, y1:-85, x2:1389, y2:-85, prev:14, next:2}`.
- **`ladderRope`:** 8 entries with keys l, uf, x, y1, y2, page.
- **`portal`:** 18 portals.
  - 13 `sp` spawn points (pt 0).
  - `west00` (pt 2) at (−322, 215) leads to 104030000/east00.
  - `east00` (pt 2) at (1625, 216) leads to 100000000/west00 (Henesys).
  - `in00` (pt 3) at (958, −851) leads to 104040001/st00.
  - `st01` (pt 1).
- **`back`:** 5 backgrounds using `bS` "grassySoil". **Layer 0** has 59 `obj` (e.g. `oS` acc1, `l0` grassySoil, `l1` nature, `l2` 13).

**Spawn behaviour.** This is Cosmic's own behaviour, not verified against GMS:
- Respawn task runs every 10 s (`config.yaml:175`, `Server.java:996`).
- Target count = `ceil((0.70 + 0.05·min(6, players)) × spawnPoints)` (`MapleMap.java:3519-3537`). For 104040000 solo that is ceil(0.75×39) = **30 concurrent mobs**.
- Per-point cooldown: `createMobInterval` default 5000 ms when mobTime = 0 (`MapFactory.java:160`, `SpawnPoint.java:105-106`).
- `mobRate` is parsed into `MapleMap.monsterRate` (`MapleMap.java:134, 198-200`) and **never read again**. In GMS it probably scaled spawn density (UNVERIFIED).

**Candidate early stages** (from `research\cosmic-data\maps_early.txt`; names are `streetName : mapName`):

| Map id | Name | bgm | mobRate | Mob pool (spawn-point counts) |
|---|---|---|---|---|
| 104000100 | Victoria Road : Right Around Lith Harbor | Bgm02/AboveTheTreetops | 1.0 | Snail ×10, Blue Snail ×17 |
| 104000200 | Victoria Road : Thicket Around the Beach I | Bgm02/AboveTheTreetops | 1.0 | Snail ×8, Blue Snail ×13, Red Snail ×13 |
| 104040000 | Victoria Road : Henesys Hunting Ground I | Bgm01/CavaBien | 1.5 | Shroom ×10, Blue Snail ×8, Red Snail ×12, Pig ×9 |
| 100010000 | Victoria Road : The Hill East of Henesys | Bgm00/RestNPeace | 1.5 | Pig ×13, Blue Snail ×17, Red Snail ×11, Shroom ×9, *Cynical Orange Mushroom 9300274 ×2 (likely HeavenMS edit)* |
| 104030000 | Victoria Road : A Hill West of Henesys | Bgm01/CavaBien | 1.0 | Pig ×18, Red Snail ×9, Slime ×19 |
| 104010000 | Victoria Road : 3-Way Road-Split | Bgm02/AboveTheTreetops | 1.3 | Pig ×23, Orange Mushroom ×22, Red Snail ×12 |
| 104040001 | Victoria Road : Henesys Hunting Ground II | Bgm01/CavaBien | 1.5 | Green Mushroom ×7, Pig ×8, Ribbon Pig 1210101 ×12, Orange Mushroom ×9, *Strange ... 9400614-9400617 ×7 (vanilla status UNVERIFIED)* |
| 104040002 | Victoria Road : Henesys Hunting Ground III | Bgm01/CavaBien | 1.5 | Green Mushroom ×11, Ribbon Pig ×13, Orange Mushroom ×11, *Strange ... ×7* |
| 100020000 | Victoria Road : The Rain-Forest East of Henesys | Bgm00/RestNPeace | 1.0 | Pig ×6, Orange Mushroom ×4 |
| 100030000 | Victoria Road : The Forest East of Henesys | Bgm00/RestNPeace | 1.0 | Pig ×22, Ribbon Pig ×10, Orange Mushroom ×19 (+ Strange ×11). Has VR bounds (−4528..−786, −1786..465) |
| 101010000 | Victoria Road : The Field Up North of Ellinia | Bgm01/MoonlightShadow | 1.2 | Slime ×27, Red Snail ×8 |
| 101010100 | Victoria Road : The Tree That Grew I | Bgm01/MoonlightShadow | 1.0 | Slime ×25, Red Snail ×5 |
| 100040100 | Victoria Road : The Forest of Wisdom | Bgm01/MoonlightShadow | 1.0 | Slime ×40 |
| 101020000 | Victoria Road : The Forest North of Ellinia | Bgm01/MoonlightShadow | 1.3 | Dark Stump 1110101 ×25, Slime ×36. Very tall map (y −4123..2184); Magician Job Instructor 1072001 is here |
| 102010000 | Victoria Road : West Street Corner of Perion | Bgm00/Nightmare | 1.1 | Dark Stump ×7, Red Snail ×9, Stump 0130100 ×22 |
| 104010001 | Hidden Street : The Pig Beach | Bgm02/AboveTheTreetops | 1.5 | Pig ×10, Ribbon Pig ×11, Iron Hook 4090000 ×1 |

Maple Island maps are under `Map.wz/Map/Map0/0000xxxxx.img.xml` (zero-padded to 9 digits). They were not dumped.

## Licensing notes

**Cosmic code** (Java + JS scripts):
- AGPL-3.0 (`LICENSE`).
- File headers come from OdinMS (Patrick Huy, Matthias Butz, Jan Christian Meyer, 2008), e.g. `ExpTable.java:1-21` and `scripts/npc/1032001.js:1-5`. They add: "You may not use, modify or distribute this program under any other version of the GNU Affero General Public License" (`ExpTable.java:10-12`).
- (a) **Porting code** (translating Java or JS logic line by line into GDScript, Rust etc.) risks creating a derivative work. AGPL would then require the whole game to be released under AGPL-3.0 with source. **Recommendation: do not port code or copy structure or comments.**
- (b) **Using numbers and formulas as facts** (an EXP value, "poison = maxHP/(70−lvl) per second", a mob's HP) is generally treated as unprotectable facts or ideas, not expression. Re-implement them from a written spec such as this report, in our own code, with a provenance note per table.

**Third-party code inside Cosmic:**
- `src/main/java/tools/BCrypt.java` is © 2006 Damien Miller under an ISC-style permissive notice. Irrelevant to us.
- Maven dependencies (`pom.xml`: Netty, HikariCP, mysql-connector-j, Liquibase, Jdbi, log4j, slf4j, GraalVM JS, yamlbeans, JUnit, Mockito) all have their own licenses. None of them is needed by us.

**Data:**
- `wz/*.xml`, `handbook/*.txt` and `String.wz` text are **Nexon/Wizet game data** exported from the client. Cosmic grants no license for them (they are Nexon's copyright). `docs/feature_list.md:22` credits "clean WZ files, provided by Nexon/Wizet". `handbook/Cash.txt:299` has an item string "From NEXON".
- Our project already plans to use the original WZ. The legal exposure for game data is the same whether the numbers come from Cosmic's XML or from `v83-original`. **Source the shipped numbers from `v83-original` and use Cosmic only to cross-check.**
- `src/main/resources/db/data/152-drop-data.sql` and the other `db/data/*.sql` files (drops, shops, maker recipes) are community-compiled data under the repo's AGPL umbrella. Their copyrightability as a compilation is unclear. If we use them, treat them as reference, re-derive or curate our own tables, and do not bulk-copy SQL.

This is not legal advice. Get a proper review before any public release.

## Unknowns and risks

1. **Vanilla fidelity:** none of the server XML numbers (mob stats, skill tables, map spawns) has been byte-compared with `v83-original\*.wz`. Action: once a WZ reader exists (other research track), diff Mob/Skill/Map for the ids above. Treat these as suspect until then:
   - the 9400614-9400617 "Strange ..." spawns and 9300274 in the Henesys maps (`docs/mychanges_ptbr.txt:1586` documents HeavenMS adding Cynical Orange Mushrooms)
   - portal edits (`docs/wzchanges_gist.txt:6-7`)
2. **True damage and hit formulas are not in Cosmic.** We still need, from some other primary source, all of: player magic and physical min/max, mastery, accuracy vs avoid, mob PDD/MDD reduction, level-difference modifiers, mob touch damage from PADamage vs player defence, natural HP/MP regen, Improved MP Recovery. The client exe is packed, so it needs either dynamic analysis (out of scope: we must not run MapleStory.exe) or a documented community source, marked UNVERIFIED.
3. **EXP table** comes only from Cosmic. It has a duplicate at index 162/163, and the client copy is unverifiable statically.
4. **Client-only mob fields** (`speed`, `pushed`, `fs`, `eva`, `acc`) have no server semantics in Cosmic. We would have to define their behaviour ourselves.
5. **Skill reach is missing:** Energy Bolt, Magic Claw, Fire Arrow and Poison Breath carry no range or hitbox data in Skill.wz. The reach must come from the client or be designed.
6. **Data typos inside Nexon data:** Poison Breath L29 `time=58`; Recovery mpCon vs tooltip; Energy Bolt L9 mad 32 vs tooltip 33. We need to decide whether to stay faithful to the data or to the tooltip.
7. **Emulator inventions:**
   - HP/MP per level-up ranges, job-change HP/MP bonuses, the spawn-rate formula `0.70+0.05n`, and the hypnotize damage formula are Cosmic/HeavenMS approximations. Do not present them as GMS.
   - `USE_AUTOASSIGN_STARTERS_AP: true` by default skips the 1st-job stat checks.
