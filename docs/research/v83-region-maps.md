# v83 maps for the new regions

> Research for the region progression (#447, #448, #449), 2026-10-30. Read from the owner's v83 files with `tools/wzimport dump` and throwaway scripts (not committed; mentions of `_scratch/` are those). Facts only (ids, names, levels, HP, spans): tier A unless marked inferred.

Part A covers Ludibrium, Omega Sector, Magatia, Zipangu, Mushroom Castle and a check of the #270 picks. Part B covers Leafre, the Phantom Forest, the Clocktower and the Temple of Time.

## Part A


Source: the owner's v83 Map.wz / String.wz / Mob.wz, read with `tools/wzimport dump` plus the scratch dumps in `_scratch/boss-inventory/`. Scripts and raw JSON: `_scratch/map-candidates-a/` (`geom.py`, `gen.py`, `summ.json`, `portals.json`). Facts only (ids, names, levels, spans); nothing proprietary is copied.

How to read the tables
- **W x H** = span of the non-vertical footholds (x max - x min, y max - y min), in px. The map's own VR rectangle (camera bounds) is in the detail blocks where present. Foothold layers can overlap, so a 'floor' is counted once per layer.
- **flat lvls** = number of distinct horizontal platform heights (within 30 px) with at least 300 px of flat foothold in total; a rough 'tiers' count, steep slopes are not counted. Many levels with small H = staircase of short ledges, many levels with large H = climbing map.
- **lad/rope** = `ladderRope` entries with `l=1` / `l=0` (ladder / rope; the l-flag mapping is the usual v83 one, inferred).
- **flags**: swim, fly, decHP (HP loss per interval), lvLimit / lvForceMove (min level to enter / level above which the client force-moves the player out; both unused offline, inferred meaning), timeLimit, moveLimit, fieldType, fieldLimit (bit mask; decoded bits are the usual community meaning: 1 move, 2 skill, 4 summon, 8 mystic door, 16 migrate, 32 portal scroll, 64 teleport item, 128 minigame; inferred). `conveyor xN` = N footholds with a non-zero `force`. No swim map and no `timeLimit` map appears in any proposed list.
- **mobs** = life entries with `type=m` grouped by mob id: `x N` is the number of spawn points (the game will use its own counts). `mobTime` 1-2 s on ordinary mobs is a quick respawn tag, not an event mob; `mobTime` of hundreds or thousands of seconds is a timed spawn (listed in the detail blocks). `*` / **boss-flagged** = Mob.wz `boss=1` mini-bosses or the actual bosses (Rurumo, Snow Witch, Riche, Scholar Ghost, MT-09, Chief Gray, Male/Female Boss...): drop them from the hunting pool.
- **mapMark** = `info/mapMark` (every map listed has one). BGM = `info/bgm`.
- 'flier' = mob has a fly stance (and no move stance).

### 1. Ludibrium (String.wz group `ossyria`, street `Ludibrium`)

Ludibrium's field maps top out at mob L46 (Master Robo 44, Master Chronos 46). Everything above that (Warped / Forgotten Path of Time, L61-108) is a 2100-2500 px wide, 1800-3000 px tall climbing shaft with 16-30 ladders/ropes and `lvLimit=15`: rejected. Eos Tower / Hidden Tower (221020701 is 530 wide x 3662 tall) rejected. The Toy Factory fields are the only wide ones (3600-4200 px) and carry a few conveyor-belt footholds (`force`, handled by `FootholdMap`/`player_motion.gd`); Process 2 Zone 3, Process 2 Zone 4 and Main Process 2 have none, Process 1 Zones and Main Process 1 have 5-6, Process 2 Zone 1 has 4. Boss-natural maps: Rombot only lives in Hidden Tower 221020701 (530 x 3662, 12 ledge levels, 11 ladders: rejected); Alishar is a PQ instance (922010900 'A Crack on the Wall', arena x -410..1310, not a field); Timer's field maps are Lost Time <1>/<2> and Whirlpool of Time (220050000/100/200, 1777 x 1020-1146, 11-16 ladders: a climbing map, listed as alternates). The bosses do not need a natural map here (they arrive on a timer).

**Proposed (map 1 -> 3)**

| slot | id | street - map | W x H | flat lvls | lad/rope | flags | mobs (spawn points; * = boss-flagged/mini-boss) | BGM | mapMark |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 220011000 | Ludibrium - Sky Terrace<5> | 2227 x 420 | 5 | 5/0 | - | Roloduck L34 x22, Panda Teddy L36 x19 | Bgm06/FantasticThinking | Ludibrium |
| 2 | 220030400 | Ludibrium - Toy Factory <Process 2> Zone 4 | 3667 x 340 | 6 | 4/0 | - | Panda Teddy L36 x8, Robo L41 x28 | Bgm07/WaltzForWork | Ludibrium |
| 3 | 220030000 | Ludibrium - Toy Factory <Process 2> Zone 1 | 3667 x 401 | 5 | 4/0 | conveyor x4 | Master Robo L44 x29 | Bgm07/WaltzForWork | Ludibrium |

**Alternates**

| slot | id | street - map | W x H | flat lvls | lad/rope | flags | mobs (spawn points; * = boss-flagged/mini-boss) | BGM | mapMark |
|---|---|---|---|---|---|---|---|---|---|
| 1 alt | 220010300 | Ludibrium - Cloud Terrace<2> | 2137 x 420 | 5 | 6/0 | - | Pink Teddy L32 x28, Roloduck L34 x5 | Bgm06/FantasticThinking | Ludibrium |
| 1 alt | 220010000 | Ludibrium - Cloud Terrace<5> | 2137 x 420 | 5 | 5/0 | - | Brown Teddy L30 x6, Toy Trojan L39 x16 | Bgm06/FantasticThinking | Ludibrium |
| 2 alt | 220030300 | Ludibrium - Toy Factory <Process 2> Zone 3 | 3757 x 300 | 7 | 0/0 | - | Panda Teddy L36 x24, Robo L41 x7 | Bgm07/WaltzForWork | Ludibrium |
| 2 alt | 220030200 | Ludibrium - Toy Factory <Main Process 2> | 4207 x 392 | 5 | 6/0 | - | Panda Teddy L36 x35 | Bgm07/WaltzForWork | Ludibrium |
| 2 alt | 220020300 | Ludibrium - Toy Factory <Main Process 1> | 4207 x 363 | 4 | 4/0 | conveyor x6 | Panda Teddy L36 x28 | Bgm07/WaltzForWork | Ludibrium |
| 2 alt | 220020100 | Ludibrium - Toy Factory <Process 1> Zone 2 | 3667 x 360 | 5 | 4/0 | conveyor x5 | Panda Teddy L36 x9, Robo L41 x11, Master Robo L44 x10 | Bgm07/WaltzForWork | Ludibrium |
| 3 alt | 220040400 | Ludibrium - The Path of Time <4> | 2047 x 1020 | 9 | 10/0 | - | Master Chronos L46 x34 | Bgm07/WhereverYouAre | Ludibrium |
| 3 alt (Timer natural) | 220050200 | Ludibrium - Lost Time <2> | 1777 x 1146 | 7 | 16/0 | - | Master Chronos L46 x38 | Bgm07/WhereverYouAre | Ludibrium |
| 3 alt (Timer natural) | 220050000 | Ludibrium - Lost Time <1> | 1777 x 1020 | 8 | 11/0 | - | Platoon Chronos L41 x36 | Bgm07/WhereverYouAre | Ludibrium |

<details><summary>Full detail (foothold spans, VR, life flags)</summary>

- **220011000** Ludibrium | Sky Terrace<5> [String.wz `ossyria`]: foothold x -1153..1074 (W 2227), y -288..132 (H 420); 5 flat levels (lengths 539/1803/404/1253/2227); ladders 5, ropes 0; walls 18; conveyor fh 0; flags: none; VR x-1135..1057 y-350..250; mobRate 1.3000000715255737; BGM `Bgm06/FantasticThinking`; mapMark `Ludibrium`
  - life: Roloduck 3210204 L34 x22; Panda Teddy 3210203 L36 x19
- **220030400** Ludibrium | Toy Factory <Process 2> Zone 4 [String.wz `ossyria`]: foothold x -1558..2109 (W 3667), y -178..162 (H 340); 6 flat levels (lengths 407/470/1383/581/579/3667); ladders 4, ropes 0; walls 10; conveyor fh 0; flags: none; VR x-1558..2108 y-315..285; mobRate 1; BGM `Bgm07/WaltzForWork`; mapMark `Ludibrium`
  - life: Panda Teddy 3210203 L36 x8; Robo 4230111 L41 x28
- **220030000** Ludibrium | Toy Factory <Process 2> Zone 1 [String.wz `ossyria`]: foothold x -1558..2109 (W 3667), y -239..162 (H 401); 5 flat levels (lengths 825/1406/1472/764/3667); ladders 4, ropes 0; walls 22; conveyor fh 4; flags: none; VR x-1558..2109 y-315..285; mobRate 1; BGM `Bgm07/WaltzForWork`; mapMark `Ludibrium`
  - life: Master Robo 4230112 L44 x29
- **220010300** Ludibrium | Cloud Terrace<2> [String.wz `ossyria`]: foothold x -1063..1074 (W 2137), y -288..132 (H 420); 5 flat levels (lengths 920/330/733/1026/2137); ladders 6, ropes 0; walls 22; conveyor fh 0; flags: none; VR x-1045..1057 y-350..250; mobRate 1.100000023841858; BGM `Bgm06/FantasticThinking`; mapMark `Ludibrium`
  - life: Pink Teddy 3110101 L32 x28; Roloduck 3210204 L34 x5
- **220010000** Ludibrium | Cloud Terrace<5> [String.wz `ossyria`]: foothold x -1063..1074 (W 2137), y -288..132 (H 420); 5 flat levels (lengths 1032/405/514/651/2137); ladders 5, ropes 0; walls 20; conveyor fh 0; flags: none; VR x-1045..1057 y-350..250; mobRate 1.2000000476837158; BGM `Bgm06/FantasticThinking`; mapMark `Ludibrium`
  - life: Brown Teddy 3000005 L30 x6; Toy Trojan 3230305 L39 x16
- **220030300** Ludibrium | Toy Factory <Process 2> Zone 3 [String.wz `ossyria`]: foothold x -1648..2109 (W 3757), y -138..162 (H 300); 7 flat levels (lengths 1041/334/1347/396/396/396/3757); ladders 0, ropes 0; walls 24; conveyor fh 0; flags: none; VR x-1648..2109 y-315..285; mobRate 1; BGM `Bgm07/WaltzForWork`; mapMark `Ludibrium`
  - life: Panda Teddy 3210203 L36 x24; Robo 4230111 L41 x7
- **220030200** Ludibrium | Toy Factory <Main Process 2> [String.wz `ossyria`]: foothold x -2098..2109 (W 4207), y -230..162 (H 392); 5 flat levels (lengths 321/1708/1169/344/4207); ladders 6, ropes 0; walls 22; conveyor fh 0; flags: none; VR x-2098..2109 y-315..285; mobRate 1; BGM `Bgm07/WaltzForWork`; mapMark `Ludibrium`
  - life: Panda Teddy 3210203 L36 x35
- **220020300** Ludibrium | Toy Factory <Main Process 1> [String.wz `ossyria`]: foothold x -2098..2109 (W 4207), y -201..162 (H 363); 4 flat levels (lengths 1310/2025/535/4207); ladders 4, ropes 0; walls 18; conveyor fh 6; flags: none; VR x-2098..2109 y-315..285; mobRate 1; BGM `Bgm07/WaltzForWork`; mapMark `Ludibrium`
  - life: Panda Teddy 3210203 L36 x28
- **220020100** Ludibrium | Toy Factory <Process 1> Zone 2 [String.wz `ossyria`]: foothold x -1558..2109 (W 3667), y -198..162 (H 360); 5 flat levels (lengths 831/991/1265/389/3667); ladders 4, ropes 0; walls 18; conveyor fh 5; flags: none; VR x-1558..2105 y-315..285; mobRate 1; BGM `Bgm07/WaltzForWork`; mapMark `Ludibrium`
  - life: Panda Teddy 3210203 L36 x9; Robo 4230111 L41 x11; Master Robo 4230112 L44 x10
- **220040400** Ludibrium | The Path of Time <4> [String.wz `ossyria`]: foothold x -1153..894 (W 2047), y 12..1032 (H 1020); 9 flat levels (lengths 332/1100/550/1099/797/746/1157/634/2047); ladders 10, ropes 0; walls 44; conveyor fh 0; flags: none; VR x-1145..883 y-600..1240; mobRate 1.6000001430511475; BGM `Bgm07/WhereverYouAre`; mapMark `Ludibrium`
  - life: Master Chronos 4230115 L46 x34
- **220050200** Ludibrium | Lost Time <2> [String.wz `ossyria`]: foothold x -883..894 (W 1777), y -114..1032 (H 1146); 7 flat levels (lengths 396/1214/1325/1325/1325/396/1777); ladders 16, ropes 0; walls 72; conveyor fh 0; flags: none; VR x-883..895 y-600..1240; mobRate 1.5000001192092896; BGM `Bgm07/WhereverYouAre`; mapMark `Ludibrium`
  - life: Master Chronos 4230115 L46 x38
- **220050000** Ludibrium | Lost Time <1> [String.wz `ossyria`]: foothold x -1153..624 (W 1777), y 12..1032 (H 1020); 8 flat levels (lengths 314/977/381/1214/1214/337/441/1777); ladders 11, ropes 0; walls 58; conveyor fh 0; flags: none; VR x-1153..624 y-400..1240; mobRate 1.5000001192092896; BGM `Bgm07/WhereverYouAre`; mapMark `Ludibrium`
  - life: Platoon Chronos 4230114 L41 x36

</details>

### 2. Omega Sector (String.wz group `ossyria`, streets `Omega Sector` / `Hidden Street`)

Omega fields are wide, low strips (2250-5500 px, H 510-750): a long ground floor plus several short ledges (4-8 flat levels), a mix of ropes and ladders; no swim, decHP or fieldLimit on any of the maps listed. Natural boss maps are the three Hidden Street instances 221040201 (Chief Gray), 221030601 (MT-09), 221040301 (Zeno, script-summoned); they are 2250-2414 wide, so I propose the regular neighbours instead. The Kulan IV / Barnard / Prairie maps list Chief Gray 4240000 as timed life (480/780/1020 s), exclude it from the mob pool if it is a boss. Zeta Gray is a flier (fly stance only).

**Proposed (map 1 -> 3)**

| slot | id | street - map | W x H | flat lvls | lad/rope | flags | mobs (spawn points; * = boss-flagged/mini-boss) | BGM | mapMark |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 221040000 | Omega Sector - Kulan Field I | 2864 x 540 | 5 | 6/5 | - | Barnard Gray L40 x17 | Bgm08/FindingForest | OmegaSector |
| 2 | 221030200 | Omega Sector - Boswell Field II | 4214 x 510 | 8 | 6/4 | - | Mateon L41 x7, Plateon L44 x27 | Bgm08/LetsHuntAliens | OmegaSector |
| 3 | 221030500 | Omega Sector - Boswell Field V | 4574 x 510 | 6 | 5/2 | - | Plateon L44 x11, Mecateon L46 x21 | Bgm08/LetsHuntAliens | OmegaSector |

**Alternates**

| slot | id | street - map | W x H | flat lvls | lad/rope | flags | mobs (spawn points; * = boss-flagged/mini-boss) | BGM | mapMark |
|---|---|---|---|---|---|---|---|---|---|
| 1 alt | 221040100 | Omega Sector - Kulan Field II | 2504 x 540 | 6 | 4/2 | - | Barnard Gray L40 x10, Zeta Gray L42 x7 | Bgm08/FindingForest | OmegaSector |
| 2 alt | 221030100 | Omega Sector - Boswell Field I | 3854 x 630 | 6 | 6/5 | - | Mateon L41 x21, Plateon L44 x16 | Bgm08/LetsHuntAliens | OmegaSector |
| 2 alt (widest, 51 Mateon) | 221030000 | Omega Sector - Off-Limits | 5474 x 600 | 6 | 8/9 | - | Mateon L41 x51 | Bgm08/LetsHuntAliens | OmegaSector |
| 3 alt | 221040300 | Omega Sector - Kulan Field IV | 3854 x 510 | 5 | 11/1 | - | Zeta Gray L42 x8, Ultra Gray L45 x22, Chief Gray L49 x2 | Bgm08/FindingForest | OmegaSector |
| 3 alt | 221030400 | Omega Sector - Boswell Field IV | 2774 x 720 | 5 | 2/5 | - | Plateon L44 x12, Mecateon L46 x13 | Bgm08/LetsHuntAliens | OmegaSector |
| boss-natural | 221040201 | Hidden Street - Barnard Field | 2414 x 750 | 6 | 0/10 | - | Barnard Gray L40 x18, Chief Gray L49 x3 | Bgm08/FindingForest | OmegaSector |
| boss-natural | 221030601 | Hidden Street - Defeat Monsters | 2414 x 750 | 5 | 3/0 | - | Plateon L44 x4, Mecateon L46 x15, MT-09 L54 x3* | Bgm08/LetsHuntAliens | OmegaSector |
| boss-natural | 221040301 | Hidden Street - Gray's Prairie | 2250 x 510 | 4 | 0/2 | - | Ultra Gray L45 x7, Chief Gray L49 x2 | Bgm08/FindingForest | OmegaSector |

<details><summary>Full detail (foothold spans, VR, life flags)</summary>

- **221040000** Omega Sector | Kulan Field I [String.wz `ossyria`]: foothold x -3367..-503 (W 2864), y 266..806 (H 540); 5 flat levels (lengths 418/958/524/524/2864); ladders 6, ropes 5; walls 48; conveyor fh 0; flags: none; mobRate 1.4000000953674316; BGM `Bgm08/FindingForest`; mapMark `OmegaSector`
  - life: Barnard Gray 4230116 L40 x17
- **221030200** Omega Sector | Boswell Field II [String.wz `ossyria`]: foothold x -847..3367 (W 4214), y 296..806 (H 510); 8 flat levels (lengths 921/995/365/529/942/381/667/3367); ladders 6, ropes 4; walls 50; conveyor fh 0; flags: none; mobRate 0.7999999523162842; BGM `Bgm08/LetsHuntAliens`; mapMark `OmegaSector`
  - life: Mateon 4230119 L41 x7; Plateon 4230120 L44 x27
- **221030500** Omega Sector | Boswell Field V [String.wz `ossyria`]: foothold x -2737..1837 (W 4574), y 296..806 (H 510); 6 flat levels (lengths 868/725/598/1048/434/3462); ladders 5, ropes 2; walls 50; conveyor fh 0; flags: none; mobRate 0.7999999523162842; BGM `Bgm08/LetsHuntAliens`; mapMark `OmegaSector`
  - life: Plateon 4230120 L44 x11; Mecateon 4230121 L46 x21
- **221040100** Omega Sector | Kulan Field II [String.wz `ossyria`]: foothold x -3727..-1223 (W 2504), y 266..806 (H 540); 6 flat levels (lengths 434/704/1302/757/990/323); ladders 4, ropes 2; walls 46; conveyor fh 0; flags: none; mobRate 1.3000000715255737; BGM `Bgm08/FindingForest`; mapMark `OmegaSector`
  - life: Barnard Gray 4230116 L40 x10; Zeta Gray 4230117 L42 x7 (flier)
- **221030100** Omega Sector | Boswell Field I [String.wz `ossyria`]: foothold x -1747..2107 (W 3854), y 416..1046 (H 630); 6 flat levels (lengths 1318/905/344/3277/503/1350); ladders 6, ropes 5; walls 66; conveyor fh 0; flags: none; mobRate 0.7999999523162842; BGM `Bgm08/LetsHuntAliens`; mapMark `OmegaSector`
  - life: Mateon 4230119 L41 x21; Plateon 4230120 L44 x16
- **221030000** Omega Sector | Off-Limits [String.wz `ossyria`]: foothold x -2737..2737 (W 5474), y 446..1046 (H 600); 6 flat levels (lengths 1879/1307/1133/3907/1154/3076); ladders 8, ropes 9; walls 75; conveyor fh 0; flags: none; mobRate 1.2000000476837158; BGM `Bgm08/LetsHuntAliens`; mapMark `OmegaSector`
  - life: Mateon 4230119 L41 x51
- **221040300** Omega Sector | Kulan Field IV [String.wz `ossyria`]: foothold x -4987..-1133 (W 3854), y 296..806 (H 510); 5 flat levels (lengths 1392/344/1318/1318/4124); ladders 11, ropes 1; walls 51; conveyor fh 0; flags: none; mobRate 1.2000000476837158; BGM `Bgm08/FindingForest`; mapMark `OmegaSector`
  - life: Zeta Gray 4230117 L42 x8 (flier); Ultra Gray 4230118 L45 x22; Chief Gray 4240000 L49 x2 [timed x2: mobTime 480,780s]
- **221030400** Omega Sector | Boswell Field IV [String.wz `ossyria`]: foothold x -2917..-143 (W 2774), y 266..986 (H 720); 5 flat levels (lengths 1011/815/868/2128/360); ladders 2, ropes 5; walls 42; conveyor fh 0; flags: none; mobRate 0.8999999761581421; BGM `Bgm08/LetsHuntAliens`; mapMark `OmegaSector`
  - life: Plateon 4230120 L44 x12; Mecateon 4230121 L46 x13
- **221040201** Hidden Street | Barnard Field [String.wz `ossyria`]: foothold x -4807..-2393 (W 2414), y 56..806 (H 750); 6 flat levels (lengths 1048/598/434/524/704/2414); ladders 0, ropes 10; walls 248; conveyor fh 0; flags: none; mobRate 1; BGM `Bgm08/FindingForest`; mapMark `OmegaSector`
  - life: Barnard Gray 4230116 L40 x18; Chief Gray 4240000 L49 x3 [timed x3: mobTime 480,780,1020s]
- **221030601** Hidden Street | Defeat Monsters [String.wz `ossyria`]: foothold x -3637..-1223 (W 2414), y 56..806 (H 750); 5 flat levels (lengths 487/307/487/720/1334); ladders 3, ropes 0; walls 47; conveyor fh 0; flags: none; mobRate 0.5999999046325684; BGM `Bgm08/LetsHuntAliens`; mapMark `OmegaSector`
  - life: Plateon 4230120 L44 x4; Mecateon 4230121 L46 x15; MT-09 5120100 L54 x3 [timed x3: mobTime 1140,1320,1980s] **boss-flagged**
- **221040301** Hidden Street | Gray's Prairie [String.wz `ossyria`]: foothold x -4635..-2385 (W 2250), y 266..776 (H 510); 4 flat levels (lengths 365/598/524/2250); ladders 0, ropes 2; walls 83; conveyor fh 0; flags: none; VR x-4634..-2389 y-59..979; mobRate 1.2000000476837158; BGM `Bgm08/FindingForest`; mapMark `OmegaSector`
  - life: Ultra Gray 4230118 L45 x7; Chief Gray 4240000 L49 x2 [timed x2: mobTime 480,780s]

</details>

### 3. Nihal Desert (String.wz group `ossyria`, streets `The Burning Sands`, `Sunset Road`, `Alcadno/Zenumist Research Institute`)

Ariant fields are 1600-2500 wide, flat with 2-3 levels. Magatia is a town (261000000, no mobs); its fields are the lab corridors, 1950-2400 wide but only 200-330 tall (wide and flat, 2-4 shelf levels and 3-8 ladders; no ropes). Lab maps carry `mobRate=2`. Rurumo 6090004 (L63, boss flag, mobTime 2400, removeAfter 1800) and Deet and Roi 8090000 are boss-flagged extras in some lab maps: exclude from the pool. Secret Basement Path 261030000 (Chimera's map) is 1260 x 640 with 3 levels and no mobs: not usable as an arena. Level steps: Ariant fields L20-40, Alcadno labs L42-63 (A-3 L42-45, B-1 L47, C-1/C-2 L54-58), Zenumist labs L32-38 (Units 101-103) and L65-73 (Units 201-203); Zenumist 101-103 (L32-38, 1470-2200 wide) are a gentler map 2 if the owner prefers a smooth ramp (261010003: 2196 x 229 Rumo L35 / Triple Rumo L38). Natural boss maps: Deo 260010201 (1620 x 300, 2 levels, 3 ropes), Homunscullo 261010102 (1955 x 218), Chimera 261030000 (1260 x 640, 3 levels, 2 ladders, no mob life, hideMinimap): all three are narrower than the proposed hunting maps. Homunscullo's own map (261010102, Unit 202) also holds Deet and Roi, so Unit 201/203 are the proposed hunting maps.

**Proposed (map 1 -> 3)**

| slot | id | street - map | W x H | flat lvls | lad/rope | flags | mobs (spawn points; * = boss-flagged/mini-boss) | BGM | mapMark |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 260020300 | Sunset Road - The Desert of Red Sand | 2430 x 420 | 3 | 3/0 | - | Kiyo L30 x9, Sand Dwarf  L32 x6 | Bgm15/SunsetDesert | Ariant |
| 2 | 261020400 | Alcadno Research Institute - Lab - Area C-2 | 2410 x 232 | 4 | 3/0 | - | Roid  L54 x14, Neo Huroid L58 x13, Rurumo L63 x1* | Bgm12/Dispute | Magatia |
| 3 | 261010101 | Zenumist Research Institute - Lab - Unit 201 | 2196 x 279 | 5 | 4/0 | - | Homun L65 x11, Saitie L68 x5 | Bgm12/Dispute | Magatia |

**Alternates**

| slot | id | street - map | W x H | flat lvls | lad/rope | flags | mobs (spawn points; * = boss-flagged/mini-boss) | BGM | mapMark |
|---|---|---|---|---|---|---|---|---|---|
| 1 alt | 260020400 | Sunset Road - The Ruins of Desert Nomads | 2430 x 420 | 2 | 2/0 | - | Kiyo L30 x2, Sand Dwarf  L32 x7, Desert Giant  L40 x3 | Bgm15/SunsetDesert | Ariant |
| 1 alt | 260020100 | The Burning Sands - North Desert Road 1 | 2520 x 480 | 5 | 2/2 | - | Meerkat L29 x10 | Bgm14/HotDesert | Ariant |
| 1 alt (Deo natural, small) | 260010201 | Hidden Street - Royal Catthus Desert | 1620 x 300 | 2 | 0/3 | - | Royal Cactus L28 x10 | Bgm14/HotDesert | Ariant |
| 2 alt | 261020200 | Alcadno Research Institute - Lab - Area B-1 | 2008 x 314 | 4 | 6/0 | - | Mithril  mutae L47 x24, Rurumo L63 x1* | Bgm12/Dispute | Magatia |
| 2 alt | 261020700 | Alcadno Research Institute - Lab - Area A-3 | 2006 x 456 | 4 | 8/0 | - | Iron Mutae L42 x9, Reinforced Iron Mutae L45 x18 | Bgm12/Dispute | Magatia |
| 2 alt | 261020600 | Alcadno Research Institute - Lab - Area B-3 | 2008 x 203 | 3 | 4/0 | - | Iron Mutae L42 x13, Rurumo L63 x1* | Bgm12/Dispute | Magatia |
| 3 alt | 261010103 | Zenumist Research Institute - Lab - Unit 203 | 1954 x 327 | 4 | 5/0 | - | Saitie L68 x4, Homunculus L73 x19 | Bgm12/Dispute | Magatia |
| 3 alt (Homunscullo + Deet and Roi in life) | 261010102 | Zenumist Research Institute - Lab - Unit 202 | 1955 x 218 | 4 | 2/0 | - | Homunculus L73 x14, Homunscullo L80 x2*, Deet and Roi L80 x1* | Bgm12/Dispute | Magatia |

<details><summary>Full detail (foothold spans, VR, life flags)</summary>

- **260020300** Sunset Road | The Desert of Red Sand [String.wz `ossyria`]: foothold x -450..1980 (W 2430), y -145..275 (H 420); 3 flat levels (lengths 1134/978/1272); ladders 3, ropes 0; walls 12; conveyor fh 0; flags: none; VR x-450..1980 y-660..455; mobRate 1; BGM `Bgm15/SunsetDesert`; mapMark `Ariant`
  - life: Kiyo 3100102 L30 x9; Sand Dwarf  3100101 L32 x6
- **261020400** Alcadno Research Institute | Lab - Area C-2 [String.wz `ossyria`]: foothold x -714..1696 (W 2410), y -65..167 (H 232); 4 flat levels (lengths 761/747/522/2410); ladders 3, ropes 0; walls 0; conveyor fh 0; flags: none; VR x-714..1695 y-316..321; mobRate 2.000000238418579; BGM `Bgm12/Dispute`; mapMark `Magatia`
  - life: Roid  5110301 L54 x14 [timed x4: mobTime 1,2s]; Neo Huroid 5110302 L58 x13 [timed x1: mobTime 1200s]; Rurumo 6090004 L63 x1 [timed x1: mobTime 2400s] **boss-flagged**
- **261010101** Zenumist Research Institute | Lab - Unit 201 [String.wz `ossyria`]: foothold x -1244..952 (W 2196), y 29..308 (H 279); 5 flat levels (lengths 708/372/1309/642/2196); ladders 4, ropes 0; walls 0; conveyor fh 0; flags: none; VR x-1243..950 y-172..490; mobRate 2.000000238418579; BGM `Bgm12/Dispute`; mapMark `Magatia`
  - life: Homun 6110300 L65 x11; Saitie 6110301 L68 x5
- **260020400** Sunset Road | The Ruins of Desert Nomads [String.wz `ossyria`]: foothold x -450..1980 (W 2430), y -145..275 (H 420); 2 flat levels (lengths 966/2160); ladders 2, ropes 0; walls 14; conveyor fh 0; flags: none; VR x-450..1980 y-720..455; mobRate 1; BGM `Bgm15/SunsetDesert`; mapMark `Ariant`
  - life: Kiyo 3100102 L30 x2; Sand Dwarf  3100101 L32 x7; Desert Giant  4230600 L40 x3 [timed x3: mobTime 300s]
- **260020100** The Burning Sands | North Desert Road 1 [String.wz `ossyria`]: foothold x -1080..1440 (W 2520), y -205..275 (H 480); 5 flat levels (lengths 468/312/954/1080/1260); ladders 2, ropes 2; walls 30; conveyor fh 0; flags: none; VR x-1080..1440 y-780..455; mobRate 1; BGM `Bgm14/HotDesert`; mapMark `Ariant`
  - life: Meerkat 2100108 L29 x10
- **260010201** Hidden Street | Royal Catthus Desert [String.wz `ossyria`]: foothold x -540..1080 (W 1620), y -25..275 (H 300); 2 flat levels (lengths 348/1620); ladders 0, ropes 3; walls 6; conveyor fh 0; flags: none; VR x-539..1074 y-500..455; mobRate 1; BGM `Bgm14/HotDesert`; mapMark `Ariant`
  - life: Royal Cactus 2100104 L28 x10
- **261020200** Alcadno Research Institute | Lab - Area B-1 [String.wz `ossyria`]: foothold x -1064..944 (W 2008), y -88..226 (H 314); 4 flat levels (lengths 894/498/848/2287); ladders 6, ropes 0; walls 0; conveyor fh 0; flags: none; VR x-1050..943 y-246..380; mobRate 2.000000238418579; BGM `Bgm12/Dispute`; mapMark `Magatia`
  - life: Mithril  mutae 4110302 L47 x24; Rurumo 6090004 L63 x1 [timed x1: mobTime 2400s] **boss-flagged**
- **261020700** Alcadno Research Institute | Lab - Area A-3 [String.wz `ossyria`]: foothold x -672..1334 (W 2006), y -276..180 (H 456); 4 flat levels (lengths 2006/498/1445/2006); ladders 8, ropes 0; walls 0; conveyor fh 0; flags: none; VR x-672..1332 y-479..335; mobRate 2.000000238418579; BGM `Bgm12/Dispute`; mapMark `Magatia`
  - life: Iron Mutae 4110300 L42 x9; Reinforced Iron Mutae 4110301 L45 x18
- **261020600** Alcadno Research Institute | Lab - Area B-3 [String.wz `ossyria`]: foothold x -1064..944 (W 2008), y 23..226 (H 203); 3 flat levels (lengths 588/351/2148); ladders 4, ropes 0; walls 0; conveyor fh 0; flags: none; VR x-1063..943 y-258..380; mobRate 2.000000238418579; BGM `Bgm12/Dispute`; mapMark `Magatia`
  - life: Iron Mutae 4110300 L42 x13; Rurumo 6090004 L63 x1 [timed x1: mobTime 2400s] **boss-flagged**
- **261010103** Zenumist Research Institute | Lab - Unit 203 [String.wz `ossyria`]: foothold x -705..1249 (W 1954), y -113..214 (H 327); 4 flat levels (lengths 850/981/1081/2429); ladders 5, ropes 0; walls 0; conveyor fh 0; flags: none; VR x-700..1245 y-265..360; mobRate 2.000000238418579; BGM `Bgm12/Dispute`; mapMark `Magatia`
  - life: Saitie 6110301 L68 x4; Homunculus 7110301 L73 x19
- **261010102** Zenumist Research Institute | Lab - Unit 202 [String.wz `ossyria`]: foothold x -706..1249 (W 1955), y -4..214 (H 218); 4 flat levels (lengths 315/319/595/2045); ladders 2, ropes 0; walls 0; conveyor fh 0; flags: none; VR x-700..1246 y-265..360; mobRate 2.000000238418579; BGM `Bgm12/Dispute`; mapMark `Magatia`
  - life: Homunculus 7110301 L73 x14; Deet and Roi 8090000 L80 x1 [timed x1: mobTime 2400s] **boss-flagged**; Homunscullo 8110300 L80 x2 [timed x2: mobTime 5400s]

</details>

### 4. Zipangu (String.wz group `jp`, street `Zipangu`)

String.wz has no 80004xxxx maps, so there is no Ninja Castle in this data set; the content is the Mushroom Shrine area (800000000 town, 8000x) and Showa Town (801xxxxxx). Male Boss: `9400120` and `9400122` are the same mob apart from the id (all 30 fields I parsed, including level 95, 85000 HP, EXP, stances and the 19 skill entries, compare equal; the sprite data was not diffed). `9400120` is the one placed on the open field (Showa Street 3, 801030000, mobTime 10 s, 3850 px wide); `9400122` is placed in the Armory (801040004, mobTime 0) and in the story map The Nightmarish Last Days (801040100, mobTime 300, 1638 px, fieldLimit 252). Use 9400120. The Showa maps below 801040xxx carry fieldLimit 228/236 (summon + portal-scroll + teleport-item + minigame, no skill/move limit bits), harmless for this game. Black Crow (L115, 35,000,000 HP) only exists in 800020130 with mobTime 82800 s; Female Boss (L130, 75,000,000 HP) in Parlor, mobTime 14400 s. Dreamy Ghost L100 (68,000 HP, speed +45) in the Buddha map is the only L100 mob in the region; the next-highest hunting mob is Bain L90 (45,000 HP). 'Flat levels' of 1 means one flat ground strip.

**Proposed (map 1 -> 3)**

| slot | id | street - map | W x H | flat lvls | lad/rope | flags | mobs (spawn points; * = boss-flagged/mini-boss) | BGM | mapMark |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 800020110 | Zipangu - A Night in the Forest | 3228 x 0 | 1 | 0/0 | - | Paper Lantern Ghost L40 x12, Big Cloud Fox L45 x7 | BgmJp/BizarreForest | jipangu |
| 2 | 801030000 | Zipangu - Showa Street 3 | 3850 x 360 | 3 | 0/13 | - | Extra A L45 x4, Extra B L47 x3, Extra C L50 x3, Leader A L62 x4, Leader B L64 x4, Male Boss L95 x1* | BgmJp/Yume | shouwa |
| 3 | 800020130 | Zipangu - Encounter with the Buddha | 2868 x 0 | 1 | 0/0 | - | Dreamy Ghost L100 x16, Black Crow L115 x1* | BgmJp/BizarreForest | jipangu |

**Alternates**

| slot | id | street - map | W x H | flat lvls | lad/rope | flags | mobs (spawn points; * = boss-flagged/mini-boss) | BGM | mapMark |
|---|---|---|---|---|---|---|---|---|---|
| 1 alt (lowest start, L24-25 + 6 golems L58) | 800020100 | Zipangu - Road to Cemetery | 3408 x 840 | 9 | 1/8 | - | Zombie Mushroom L24 x16, Crow L25 x6, Dark Stone Golem L58 x6 | BgmJp/BizarreForest | jipangu |
| 1 alt | 800030000 | Zipangu - Forest of Animals | 2688 x 1350 | 9 | 2/13 | - | Cloud Fox L30 x15, Fire Raccoon L30 x26 | BgmJp/Feeling | jipangu |
| 1 alt | 801010000 | Zipangu - Showa Street 1 | 3220 x 300 | 4 | 0/4 | - | Jr. Cerebes L43 x12, Extra A L45 x11, Extra B L47 x14 | BgmJp/Yume | shouwa |
| 2 alt (no boss in life) | 801020000 | Zipangu - Showa Street 2 | 2860 x 300 | 5 | 0/2 | - | Extra A L45 x8, Extra B L47 x7, Extra C L50 x7, Leader A L62 x5, Leader B L64 x6 | BgmJp/Yume | shouwa |
| 2 alt | 800020300 | Zipangu - Cemetery Full of Ghosts | 2958 x 748 | 6 | 0/6 | - | Coolie Zombie L57 x18, Nightghost L60 x13 | BgmJp/BizarreForest | jipangu |
| 2 alt | 800020120 | Zipangu - Vanished Village | 2868 x 0 | 1 | 0/0 | - | Samiho L56 x8, Water Goblin L60 x16 | BgmJp/BizarreForest | jipangu |
| 3 alt | 801040001 | Zipangu - Parking Lot | 3375 x 245 | 6 | 0/5 | fieldLimit=228 | Leader B L64 x9, Extra D L72 x13 | BgmJp/BattleField | shouwa |
| 3 alt | 800020400 | Zipangu - WanWan Spa of Hell | 2958 x 868 | 9 | 0/7 | - | Bain L90 x21 | BgmJp/BizarreForest | jipangu |
| 3 alt (Male Boss 9400122 in life) | 801040004 | Zipangu - Armory | 3000 x 58 | 2 | 0/0 | fieldLimit=228 | Bain L90 x14, Male Boss L95 x1* | BgmJp/BattleField | shouwa |
| Female Boss natural | 801040003 | Zipangu - Parlor | 2450 x 121 | 2 | 0/0 | fieldLimit=236 | Leader A L62 x5, Leader B L64 x5, Extra D L72 x5, Female Boss L130 x1* | BgmJp/BattleField | shouwa |

<details><summary>Full detail (foothold spans, VR, life flags)</summary>

- **800020110** Zipangu | A Night in the Forest [String.wz `jp`]: foothold x -1389..1839 (W 3228), y 95..95 (H 0); 1 flat levels (lengths 3228); ladders 0, ropes 0; walls 13; conveyor fh 0; flags: none; mobRate 1.2000000476837158; BGM `BgmJp/BizarreForest`; mapMark `jipangu`
  - life: Paper Lantern Ghost 9400011 L40 x12 [timed x7: mobTime 1s]; Big Cloud Fox 9400004 L45 x7
- **801030000** Zipangu | Showa Street 3 [String.wz `jp`]: foothold x -1835..2015 (W 3850), y 35..395 (H 360); 3 flat levels (lengths 770/3850/3400); ladders 0, ropes 13; walls 34; conveyor fh 0; flags: none; mobRate 1; BGM `BgmJp/Yume`; mapMark `shouwa`
  - life: Extra A 9400100 L45 x4; Extra B 9400101 L47 x3; Extra C 9400102 L50 x3; Leader A 9400110 L62 x4; Leader B 9400111 L64 x4; Male Boss 9400120 L95 x1 [timed x1: mobTime 10s] **boss-flagged**
- **800020130** Zipangu | Encounter with the Buddha [String.wz `jp`]: foothold x -1299..1569 (W 2868), y 215..215 (H 0); 1 flat levels (lengths 2868); ladders 0, ropes 0; walls 8; conveyor fh 0; flags: none; mobRate 1; BGM `BgmJp/BizarreForest`; mapMark `jipangu`
  - life: Dreamy Ghost 9400013 L100 x16; Black Crow 9400014 L115 x1 [timed x1: mobTime 82800s] **boss-flagged**
- **800020100** Zipangu | Road to Cemetery [String.wz `jp`]: foothold x -1479..1929 (W 3408), y -625..215 (H 840); 9 flat levels (lengths 528/489/528/309/852/811/579/2008/489); ladders 1, ropes 8; walls 41; conveyor fh 0; flags: none; mobRate 0.8999999761581421; BGM `BgmJp/BizarreForest`; mapMark `jipangu`
  - life: Zombie Mushroom 2230101 L24 x16; Crow 9400000 L25 x6 (flier); Dark Stone Golem 5130102 L58 x6
- **800030000** Zipangu | Forest of Animals [String.wz `jp`]: foothold x -489..2199 (W 2688), y -1255..95 (H 1350); 9 flat levels (lengths 1146/1549/1944/336/1236/696/360/1903/822); ladders 2, ropes 13; walls 88; conveyor fh 0; flags: none; mobRate 0.8999999761581421; BGM `BgmJp/Feeling`; mapMark `jipangu`
  - life: Cloud Fox 9400002 L30 x15; Fire Raccoon 9400001 L30 x26
- **801010000** Zipangu | Showa Street 1 [String.wz `jp`]: foothold x -1025..2195 (W 3220), y -145..155 (H 300); 4 flat levels (lengths 485/575/935/3255); ladders 0, ropes 4; walls 27; conveyor fh 0; flags: none; mobRate 1; BGM `BgmJp/Yume`; mapMark `shouwa`
  - life: Jr. Cerebes 4230108 L43 x12; Extra A 9400100 L45 x11; Extra B 9400101 L47 x14
- **801020000** Zipangu | Showa Street 2 [String.wz `jp`]: foothold x -1295..1565 (W 2860), y -145..155 (H 300); 5 flat levels (lengths 700/1275/1040/325/3035); ladders 0, ropes 2; walls 40; conveyor fh 0; flags: none; mobRate 1; BGM `BgmJp/Yume`; mapMark `shouwa`
  - life: Extra A 9400100 L45 x8; Extra B 9400101 L47 x7; Extra C 9400102 L50 x7; Leader A 9400110 L62 x5; Leader B 9400111 L64 x6
- **800020300** Zipangu | Cemetery Full of Ghosts [String.wz `jp`]: foothold x -1749..1209 (W 2958), y -533..215 (H 748); 6 flat levels (lengths 730/640/528/516/1450/1248); ladders 0, ropes 6; walls 20; conveyor fh 0; flags: none; mobRate 0.7999999523162842; BGM `BgmJp/BizarreForest`; mapMark `jipangu`
  - life: Coolie Zombie 5130107 L57 x18; Nightghost 9400003 L60 x13 (flier)
- **800020120** Zipangu | Vanished Village [String.wz `jp`]: foothold x -1299..1569 (W 2868), y 155..155 (H 0); 1 flat levels (lengths 2868); ladders 0, ropes 0; walls 8; conveyor fh 0; flags: none; mobRate 1.2000000476837158; BGM `BgmJp/BizarreForest`; mapMark `jipangu`
  - life: Samiho 5100004 L56 x8; Water Goblin 9400012 L60 x16 [timed x1: mobTime 1s]
- **801040001** Zipangu | Parking Lot [String.wz `jp`]: foothold x -1900..1475 (W 3375), y -84..161 (H 245); 6 flat levels (lengths 2700/479/1027/1601/1537/3375); ladders 0, ropes 5; walls 1; conveyor fh 0; flags: fieldLimit=228 (summon,portal-scroll,teleport-item,minigame); VR x-1896..1472 y-336..295; mobRate 1; BGM `BgmJp/BattleField`; mapMark `shouwa`
  - life: Leader B 9400111 L64 x9; Extra D 9400103 L72 x13
- **800020400** Zipangu | WanWan Spa of Hell [String.wz `jp`]: foothold x -1749..1209 (W 2958), y -533..335 (H 868); 9 flat levels (lengths 829/336/606/606/516/477/1365/450/576); ladders 0, ropes 7; walls 77; conveyor fh 0; flags: none; VR x-1741..1201 y-946..427; mobRate 0.7999999523162842; BGM `BgmJp/BizarreForest`; mapMark `jipangu`
  - life: Bain 8140500 L90 x21
- **801040004** Zipangu | Armory [String.wz `jp`]: foothold x -1525..1475 (W 3000), y 103..161 (H 58); 2 flat levels (lengths 460/3000); ladders 0, ropes 0; walls 0; conveyor fh 0; flags: fieldLimit=228 (summon,portal-scroll,teleport-item,minigame); VR x-1523..1470 y-339..296; mobRate 1; BGM `BgmJp/BattleField`; mapMark `shouwa`
  - life: Bain 8140500 L90 x14; Male Boss 9400122 L95 x1 **boss-flagged**
- **801040003** Zipangu | Parlor [String.wz `jp`]: foothold x -1150..1300 (W 2450), y 41..162 (H 121); 2 flat levels (lengths 517/3079); ladders 0, ropes 0; walls 0; conveyor fh 0; flags: fieldLimit=236 (summon,mystic-door,portal-scroll,teleport-item,minigame); VR x-1151..1297 y-341..296; mobRate 1; BGM `BgmJp/BattleField`; mapMark `shouwa`
  - life: Leader A 9400110 L62 x5; Leader B 9400111 L64 x5; Extra D 9400103 L72 x5; Female Boss 9400121 L130 x1 [timed x1: mobTime 14400s] **boss-flagged**

</details>

### 5. Mushroom Castle (String.wz group `victoria`, street `Mushroom Castle`)

**How you get there.** From Henesys town (100000000) the regular portal `in03` (x 318, y -75) leads to 100000002 'Hidden Street - An Empty House'. That map has a script portal `TD00` (portal type 8, script `TD_MC_first`, at x -1094 y 214) that, judging by its name, warps to the castle (inferred: the script itself is server-side and not in the WZ files). The first castle map 106020000 'Mushroom Forest Field' (1530 wide, no mobs, onUserEnter script `TD_MC_title`) has its `left00` portal back to 100000002, so the castle is a Henesys-side dungeon: Henesys -> An Empty House -> Mushroom Forest Field -> Secluded / Isolated / Deep Inside Mushroom Forest (106020100-300) -> Split Road of Destiny (106020400, script portal `right00` 'gotocastle') -> Castle Wall Edge 106020500/501 -> Outer Castle Wall 106020600 -> Skyscraper 1..6 (106020700..106021300) -> towers -> Entrance to Wedding Hall 106021500 (Grey/Gold/White Yeti and King Pepe 3300005-7, lvLimit 30, arena 1031 wide) -> Wedding Hall 106021600/601/700 (Prime Minister 3300008, arena 1381 wide). All castle maps carry `lvLimit=30` and most `lvForceMove=39`, i.e. the intended range is Lv30-39 (inferred meaning). No castle map has swim, decHP or timeLimit except the 566-wide Security Room 106021001 (timeLimit 3600, fieldLimit 262224), which is unsuitable.

The Skyscraper maps are the roomy ones (2000-2750 px, 240-420 px tall, 3-7 short ledges plus a long floor, 2-4 ladders). The forest maps (1350-1710 wide, 540-780 tall, rope climbs) are weak arenas. Mob levels barely move: Renegade Spores / Poison Mushroom L30, Intoxicated Pig L31, Helmet Pepe L32, Royal Guard Pepe L33.

Suggested Ellinia map 1/2: **106020800 Skyscraper 2** (Helmet Pepe L32; 2728 px, 3 levels, floor 2763) then **106021300 Skyscraper 6** (Royal Guard Pepe L33; 2584 px) or **106021100 Skyscraper 4** (Helmet 32 + Royal Guard 33 mixed, 2250 px).

| slot | id | street - map | W x H | flat lvls | lad/rope | flags | mobs (spawn points; * = boss-flagged/mini-boss) | BGM | mapMark |
|---|---|---|---|---|---|---|---|---|---|
| pick | 106020800 | Mushroom Castle - Skyscraper 2 | 2728 x 240 | 3 | 3/0 | lvLimit=30 lvForceMove=39 | Helmet Pepe L32 x13 | Bgm19/MushCatle | MushCatle |
| pick | 106021300 | Mushroom Castle - Skyscraper 6 | 2584 x 330 | 5 | 3/0 | lvLimit=30 lvForceMove=39 | Royal Guard Pepe L33 x11 | Bgm19/MushCatle | MushCatle |
| alt | 106021100 | Mushroom Castle - Skyscraper 4 | 2250 x 420 | 6 | 2/0 | lvLimit=30 lvForceMove=39 | Helmet Pepe L32 x4, Royal Guard Pepe L33 x9 | Bgm19/MushCatle | MushCatle |
| alt | 106021000 | Mushroom Castle - Skyscraper 3 | 2652 x 420 | 7 | 2/0 | lvLimit=30 lvForceMove=39 | Helmet Pepe L32 x8 | Bgm19/MushCatle | MushCatle |
| alt | 106020700 | Mushroom Castle - Skyscraper 1 | 2250 x 360 | 6 | 3/0 | lvLimit=30 lvForceMove=39 | Helmet Pepe L32 x12 | Bgm19/MushCatle | MushCatle |
| alt | 106021200 | Mushroom Castle - Skyscraper 5 | 2026 x 420 | 4 | 4/0 | lvLimit=30 lvForceMove=39 | Royal Guard Pepe L33 x9 | Bgm19/MushCatle | MushCatle |
| weak (forest) | 106020100 | Mushroom Castle - Secluded Mushroom Forest | 1620 x 600 | 6 | 0/4 | lvLimit=30 lvForceMove=39 | Renegade Spores L30 x16, Poison Mushroom L30 x2 | Bgm19/MushCatle | MushCatle |
| weak (forest) | 106020200 | Mushroom Castle - Isolated Mushroom Forest | 1710 x 540 | 5 | 0/2 | lvLimit=30 lvForceMove=39 | Renegade Spores L30 x10, Poison Mushroom L30 x2 | Bgm19/MushCatle | MushCatle |
| weak (forest) | 106020400 | Mushroom Castle - Split Road of Destiny | 1710 x 660 | 7 | 0/3 | lvLimit=30 lvForceMove=39 | Poison Mushroom L30 x14 | Bgm19/MushCatle | MushCatle |
| weak (forest) | 106020402 | Mushroom Castle - Steep Downhill 2 | 1350 x 660 | 6 | 0/0 | lvLimit=30 lvForceMove=39 | Intoxicated Pig L31 x13 | Bgm19/MushCatle | MushCatle |
| boss arena | 106021500 | Mushroom Castle - Entrance to Wedding Hall | 1031 x 42 | 2 | 0/0 | lvLimit=30 lvForceMove=39 fieldLimit=271096 |  | Bgm19/MushCatle | MushCatle |
| boss arena | 106021700 | Mushroom Castle - Wedding Hall | 1381 x 55 | 2 | 0/0 | - |  | Bgm19/MushCatle | MushCatle |
| entry (no mobs) | 106020000 | Mushroom Castle - Mushroom Forest Field | 1530 x 360 | 3 | 0/0 | lvLimit=30 |  | Bgm19/MushCatle | MushCatle |

<details><summary>Full detail</summary>

- **106020800** Mushroom Castle | Skyscraper 2 [String.wz `victoria`]: foothold x -1170..1558 (W 2728), y -98..142 (H 240); 3 flat levels (lengths 2763/906/1251); ladders 3, ropes 0; walls 15; conveyor fh 0; flags: lvLimit=30, lvForceMove=39; VR x-1171..1800 y-960..360; mobRate 1.5000001192092896; BGM `Bgm19/MushCatle`; mapMark `MushCatle`
  - life: Helmet Pepe 3300003 L32 x13
- **106021300** Mushroom Castle | Skyscraper 6 [String.wz `victoria`]: foothold x -1387..1197 (W 2584), y -368..-38 (H 330); 5 flat levels (lengths 308/1414/610/1080/894); ladders 3, ropes 0; walls 24; conveyor fh 0; flags: lvLimit=30, lvForceMove=39; mobRate 1.5; BGM `Bgm19/MushCatle`; mapMark `MushCatle`
  - life: Royal Guard Pepe 3300004 L33 x11
- **106021100** Mushroom Castle | Skyscraper 4 [String.wz `victoria`]: foothold x 360..2610 (W 2250), y -98..322 (H 420); 6 flat levels (lengths 1083/540/392/1536/360/1707); ladders 2, ropes 0; walls 32; conveyor fh 0; flags: lvLimit=30, lvForceMove=39; VR x360..2610 y-770..545; mobRate 1.5; BGM `Bgm19/MushCatle`; mapMark `MushCatle`
  - life: Helmet Pepe 3300003 L32 x4; Royal Guard Pepe 3300004 L33 x9
- **106021000** Mushroom Castle | Skyscraper 3 [String.wz `victoria`]: foothold x -312..2340 (W 2652), y -98..322 (H 420); 7 flat levels (lengths 665/667/614/495/435/990/894); ladders 2, ropes 0; walls 31; conveyor fh 0; flags: lvLimit=30, lvForceMove=39; VR x-540..2340 y-900..540; mobRate 1.5000001192092896; BGM `Bgm19/MushCatle`; mapMark `MushCatle`
  - life: Helmet Pepe 3300003 L32 x8
- **106020700** Mushroom Castle | Skyscraper 1 [String.wz `victoria`]: foothold x -1080..1170 (W 2250), y -38..322 (H 360); 6 flat levels (lengths 636/964/720/450/967/1341); ladders 3, ropes 0; walls 38; conveyor fh 0; flags: lvLimit=30, lvForceMove=39; mobRate 1.5000001192092896; BGM `Bgm19/MushCatle`; mapMark `MushCatle`
  - life: Helmet Pepe 3300003 L32 x12
- **106021200** Mushroom Castle | Skyscraper 5 [String.wz `victoria`]: foothold x -810..1216 (W 2026), y -158..262 (H 420); 4 flat levels (lengths 1083/438/1652/1257); ladders 4, ropes 0; walls 22; conveyor fh 0; flags: lvLimit=30, lvForceMove=39; mobRate 1.5; BGM `Bgm19/MushCatle`; mapMark `MushCatle`
  - life: Royal Guard Pepe 3300004 L33 x9
- **106020100** Mushroom Castle | Secluded Mushroom Forest [String.wz `victoria`]: foothold x -270..1350 (W 1620), y -565..35 (H 600); 6 flat levels (lengths 489/540/477/387/348/1440); ladders 0, ropes 4; walls 14; conveyor fh 0; flags: lvLimit=30, lvForceMove=39; VR x-270..1350 y-1080..300; mobRate 1.5000001192092896; BGM `Bgm19/MushCatle`; mapMark `MushCatle`
  - life: Poison Mushroom 3300001 L30 x2; Renegade Spores 3300000 L30 x16
- **106020200** Mushroom Castle | Isolated Mushroom Forest [String.wz `victoria`]: foothold x -270..1440 (W 1710), y -505..35 (H 540); 5 flat levels (lengths 438/414/618/360/1170); ladders 0, ropes 2; walls 18; conveyor fh 0; flags: lvLimit=30, lvForceMove=39; VR x-270..1440 y-900..300; mobRate 1.5000001192092896; BGM `Bgm19/MushCatle`; mapMark `MushCatle`
  - life: Poison Mushroom 3300001 L30 x2; Renegade Spores 3300000 L30 x10
- **106020400** Mushroom Castle | Split Road of Destiny [String.wz `victoria`]: foothold x -270..1440 (W 1710), y -325..335 (H 660); 7 flat levels (lengths 438/516/348/360/1119/450/450); ladders 0, ropes 3; walls 10; conveyor fh 0; flags: lvLimit=30, lvForceMove=39; VR x-270..1440 y-900..540; mobRate 1.5000001192092896; BGM `Bgm19/MushCatle`; mapMark `MushCatle`
  - life: Poison Mushroom 3300001 L30 x14
- **106020402** Mushroom Castle | Steep Downhill 2 [String.wz `victoria`]: foothold x 180..1530 (W 1350), y -325..335 (H 660); 6 flat levels (lengths 450/360/399/720/669/681); ladders 0, ropes 0; walls 28; conveyor fh 0; flags: lvLimit=30, lvForceMove=39; VR x180..1530 y-660..510; mobRate 1.5000001192092896; BGM `Bgm19/MushCatle`; mapMark `MushCatle`
  - life: Intoxicated Pig 3300002 L31 x13
- **106021500** Mushroom Castle | Entrance to Wedding Hall [String.wz `victoria`]: foothold x -522..509 (W 1031), y -110..-68 (H 42); 2 flat levels (lengths 330/1031); ladders 0, ropes 0; walls 4; conveyor fh 0; flags: lvLimit=30, lvForceMove=39, fieldLimit=271096 (mystic-door,migrate,portal-scroll,teleport-item,minigame,+higher bits 0x42200); VR x-765..765 y-830..130; mobRate 1.5; BGM `Bgm19/MushCatle`; mapMark `MushCatle`
  - life: 
- **106021700** Mushroom Castle | Wedding Hall [String.wz `victoria`]: foothold x -689..692 (W 1381), y 87..142 (H 55); 2 flat levels (lengths 1612/1381); ladders 0, ropes 0; walls 2; conveyor fh 0; flags: none; VR x-848..848 y-780..325; mobRate 1; BGM `Bgm19/MushCatle`; mapMark `MushCatle`
  - life: 
- **106020000** Mushroom Castle | Mushroom Forest Field [String.wz `victoria`]: foothold x -180..1350 (W 1530), y -85..275 (H 360); 3 flat levels (lengths 362/1080/630); ladders 0, ropes 0; walls 2; conveyor fh 0; flags: lvLimit=30; VR x-180..1350 y-600..480; mobRate 1; BGM `Bgm19/MushCatle`; mapMark `MushCatle`
  - life: 

</details>

### 6. Verification of the earlier picks

| id | map | verdict |
|---|---|---|
| 211010000 | El Nath - Watch Out for Icy Path I | Geometry fine (3050 x 720) but **decHP=10** (cold damage), 9 ledge levels, and the life list holds **Snow Witch 6090001 (L64, boss flag, mobTime 3600 s)**. Mobs Jr. Yeti L50 x23, Hector L55 x2. |
| 211041100 | El Nath - Forest of Dead Trees I | Widest of the three (4310 x 810, 9 levels, 7 ropes) but **decHP=10** and **Riche 6090000 (L65, boss flag, mobTime 3600 s)** in life. Coolie Zombie L57 x26. |
| 211042100 | El Nath - The Cave of Trial II | Good arena: 4290 x 488, 6 levels, 12 ropes, no decHP; only fieldLimit 64 (teleport item). Cerebes L72 x13 + Jr. Cerebes L43 x7 (a wide level gap between the two). |
| 250010300 | Mu Lung - Snake Area | **Narrow and tall**: 1530 x 720, 6 levels, 8 ropes. No flags. Black Porky L43, Blue/Red Flower Serpent L45. |
| 250010301 | Mu Lung - Wild Bear Area 1 | 1980 x 637, 4 levels, 9 ropes, `mobRate=2`. Grizzly L56 x19 only. Below the 2000 px target but usable. |
| 250010700 | Mu Lung - Peach Farm 3 | **Tall**: 1980 x 1050, 6 levels, 4 ladders + 4 ropes. Peach Monkey L62 x20, Reindeer L58 x4. Weakest of the set. |
| 222010000 | Korean Folk Town - Entrance to Black Mountain | 2520 x 720, 3 levels, 6 ropes, no flags. Moon Bunny L45 x13 plus 3 stray Dark Axe Stump L22 spawn points (one with mobTime 20 s): drop the stump. |
| 222010200 | Korean Folk Town - Tiger Ridge | 2520 x 630, 6 ledge levels, 6 ropes. Hodori L50 x10, Hogul L53 x3 (one timed, mobTime 60 s). Fine. |
| 222010300 | Korean Folk Town - Fox Ridge | 3240 x 600, 5 levels, floor 2700, 1 rope. Samiho L56 x21 plus **Scholar Ghost 6090003 (L62, boss flag, mobTime 3600 s)**: drop it. Best of the three. |

Summary of problems: both El Nath snow maps (and every outdoor El Nath map except the Dead Mine, The Passage and Cave of Trial series) have `decHP=10`; Mu Lung fields are all 1260-2000 px wide with 3-6 rope tiers, none reaches 2100 (only the Practice Field maps do, 2070-2340; 250020200 is 2340 x 810, 6 levels, 6 ladders, populated by Straw/Wooden Target Dummy L50/51 training dummies, which I did not check for attacks, so treat it as unvetted). If El Nath needs a decHP-free third map the Cave of Trial series is the replacement: 211042000 (3930 x 487, Jr. Cerebes 43 / Firebomb 51 / Cerebes 72), 211042200 (5190 x 486, 20 ropes; adds Bain L90 x13, widest map found anywhere in these regions). Detail blocks:

- **211010000** El Nath | Watch Out for Icy Path I [String.wz `ossyria`]: foothold x -1030..2020 (W 3050), y -686..34 (H 720); 9 flat levels (lengths 310/310/689/490/360/360/360/360/670); ladders 1, ropes 3; walls 25; conveyor fh 0; flags: decHP=10; mobRate 1.2000000476837158; BGM `Bgm04/WarmRegard`; mapMark `ElNath`
  - life: Jr. Yeti 5100000 L50 x23; Hector 5130104 L55 x2; Snow Witch 6090001 L64 x1 [timed x1: mobTime 3600s] **boss-flagged**
- **211041100** El Nath | Forest of Dead Trees I [String.wz `ossyria`]: foothold x -1210..3100 (W 4310), y -536..274 (H 810); 9 flat levels (lengths 350/440/620/350/360/474/1083/490/810); ladders 0, ropes 7; walls 39; conveyor fh 0; flags: decHP=10; mobRate 0.7999999523162842; BGM `Bgm05/WolfWood`; mapMark `ElNathDungeon`
  - life: Coolie Zombie 5130107 L57 x26; Riche 6090000 L65 x1 [timed x1: mobTime 3600s] **boss-flagged**
- **211042100** El Nath | The Cave of Trial II [String.wz `ossyria`]: foothold x -930..3360 (W 4290), y -578..-90 (H 488); 6 flat levels (lengths 569/956/419/1452/748/842); ladders 0, ropes 12; walls 46; conveyor fh 0; flags: fieldLimit=64 (teleport-item); VR x-930..3360 y-715..-70; mobRate 0.7999999523162842; BGM `Bgm05/HellGate`; mapMark `ElNathDungeon`
  - life: Jr. Cerebes 4230108 L43 x7; Cerebes 7130001 L72 x13
- **211042000** El Nath | The Cave of Trial I [String.wz `ossyria`]: foothold x -1020..2910 (W 3930), y -577..-90 (H 487); 6 flat levels (lengths 750/620/1020/689/1632/601); ladders 0, ropes 9; walls 39; conveyor fh 0; flags: fieldLimit=64 (teleport-item); VR x-1022..2910 y-766..-70; mobRate 0.7999999523162842; BGM `Bgm05/HellGate`; mapMark `ElNathDungeon`
  - life: Jr. Cerebes 4230108 L43 x14; Firebomb 5100002 L51 x5; Cerebes 7130001 L72 x11
- **211042200** El Nath | The Cave of Trial III [String.wz `ossyria`]: foothold x -1290..3900 (W 5190), y -576..-90 (H 486); 7 flat levels (lengths 1160/750/532/2130/1170/463/1028); ladders 0, ropes 20; walls 55; conveyor fh 0; flags: fieldLimit=64 (teleport-item); VR x-1290..3900 y-720..-70; mobRate 0.7999999523162842; BGM `Bgm05/HellGate`; mapMark `ElNathDungeon`
  - life: Jr. Cerebes 4230108 L43 x8; Firebomb 5100002 L51 x9; Cerebes 7130001 L72 x7; Bain 8140500 L90 x13
- **250010300** Mu Lung | Snake Area [String.wz `ossyria`]: foothold x -450..1080 (W 1530), y -687..33 (H 720); 6 flat levels (lengths 942/394/762/346/436/1530); ladders 0, ropes 8; walls 15; conveyor fh 0; flags: none; VR x-450..1080 y-963..210; mobRate 1.2999999523162842; BGM `Bgm15/MureungForest`; mapMark `Murueng`
  - life: Black Porky 4230502 L43 x9; Blue Flower Serpent 4230503 L45 x11; Red Flower Serpent 4230504 L45 x7
- **250010301** Mu Lung | Wild Bear Area 1 [String.wz `ossyria`]: foothold x -405..1575 (W 1980), y -94..543 (H 637); 4 flat levels (lengths 1061/976/706/2132); ladders 0, ropes 9; walls 26; conveyor fh 0; flags: none; VR x-405..1572 y-477..720; mobRate 2; BGM `Bgm15/MureungForest`; mapMark `Murueng`
  - life: Grizzly 5120500 L56 x19
- **250010700** Mu Lung | Peach Farm 3 [String.wz `ossyria`]: foothold x -855..1125 (W 1980), y -327..723 (H 1050); 6 flat levels (lengths 706/408/616/782/706/1834); ladders 4, ropes 4; walls 36; conveyor fh 0; flags: none; VR x-855..1125 y-1080..720; mobRate 1.2000000476837158; BGM `Bgm15/MureungForest`; mapMark `Murueng`
  - life: Reindeer 5120505 L58 x4; Peach Monkey 6130207 L62 x20
- **250020200** Mu Lung | Practice Field : Normal Level [String.wz `ossyria`]: foothold x -180..2160 (W 2340), y -759..51 (H 810); 6 flat levels (lengths 468/1084/468/1409/1615/2340); ladders 6, ropes 0; walls 9; conveyor fh 0; flags: none; VR x-181..2160 y-1010..230; mobRate 1.399999976158142; BGM `Bgm15/MureungHill`; mapMark `Murueng`
  - life: Straw Target Dummy 5120503 L50 x13; Wooden Target Dummy 5120504 L51 x21
- **222010000** Korean Folk Town | Entrance to Black Mountain [String.wz `ossyria`]: foothold x -1530..990 (W 2520), y -627..93 (H 720); 3 flat levels (lengths 848/308/2764); ladders 0, ropes 6; walls 46; conveyor fh 0; flags: none; VR x-1530..990 y-1250..280; mobRate 1.2000000476837158; BGM `Bgm11/DarkMountain`; mapMark `Folkvillige`
  - life: Dark Axe Stump 2130100 L22 x3 [timed x1: mobTime 20s]; Moon Bunny 4230300 L45 x13
- **222010200** Korean Folk Town | Tiger Ridge [String.wz `ossyria`]: foothold x -1530..990 (W 2520), y -537..93 (H 630); 6 flat levels (lengths 308/540/784/308/1260/1080); ladders 0, ropes 6; walls 35; conveyor fh 0; flags: none; VR x-1530..990 y-1000..280; mobRate 1.3000000715255737; BGM `Bgm11/DarkMountain`; mapMark `Folkvillige`
  - life: Hodori 5100003 L50 x10; Hogul 5100005 L53 x3 [timed x1: mobTime 60s]
- **222010300** Korean Folk Town | Fox Ridge [String.wz `ossyria`]: foothold x -360..2880 (W 3240), y -447..153 (H 600); 5 flat levels (lengths 1084/484/630/360/2700); ladders 0, ropes 1; walls 53; conveyor fh 0; flags: none; VR x-360..2880 y-1000..340; mobRate 1; BGM `Bgm11/DarkMountain`; mapMark `Folkvillige`
  - life: Samiho 5100004 L56 x21; Scholar Ghost 6090003 L62 x1 [timed x1: mobTime 3600s] **boss-flagged**
## Part B


Facts (ids, names, levels, widths, flags, life lists, boss stats) are tier A: read from the owner's v83 files with
`wzimport dump` (scripts in this folder: `an.py` geometry/life, `prof.py` platform profile, `boss.py` boss facts,
`cand.py`/`cand.txt` full candidate dump; names/mob rows reused from `_scratch/boss-inventory/`). Marked **(inferred)** =
my judgement, not in the files.

Column key. `W` = foothold x-span (max x - min x of all foothold endpoints), `H` = foothold y-span. `tiers` = number of
distinct 40 px y-bands with >=250 px of walkable foothold (rough, **inferred** from that count). `lad/rope` = ladderRope
entries with `l=1` / `l=0` (**inferred** that l=1 is a ladder). Flags come from `info/`: `swim`, `decHP`, `timeLimit`,
`partyOnly` are absent on every PICK below unless stated; `FL` = `fieldLimit` bitmask; `lv` = `lvLimit` (min entry level,
nothing else). FL values 8 / 72 / 120 / 270456 are (**inferred**) only mystic-door/teleport/portal-scroll/migrate/instance
bits; none of the picks has the move/skill/summon bits 1|2|4 (Aqua town maps with FL=4 are the only ones that do).
Every pick has `info/mapMark`. `mobTime` -1 = script spawn only, N>0 = respawn seconds (listed when present).
String.wz/Map.img group: Leafre, Ludibrium, Time Lane = `ossyria`; Masteria (Phantom Forest, Crimsonwood Mountain/Keep, NLC) = `MasteriaGL`.

Level-100+ ground truth (scan of all 5261 maps, non-swim, no decHP): outside these four areas almost no ordinary
mobs above Lv95 exist (Section 7). Highest regular mob levels: Time Lane 141, Crimson Guardian 120, Skelosaurus 113.

---------------------------------------------------------------------------------------------------------------

### 1. Leafre (Lv 88 -> 113), group `ossyria`, mapMark `Leafre`

All Leafre field maps are 1500-3500 wide but 900-1450 tall: pyramids of rope-linked tiers with one full-width floor
(**inferred** from `prof.py`). The Cave of Life trial rooms are the only flat wide maps. The Wyvern Canyon maps (all ~806
wide, 1350-2100 tall, 10-15 tiers) are vertical shafts: reject.

| # | map id | street - name | W x H | shape | lad/rope | flags | BGM | life (id name Lv xN) |
|---|---|---|---|---|---|---|---|---|
| **1** | **240020400** | Leafre - The Area of Blue Kentaurus | 2790 x 960 | tiers: one 990 floor + 360-wide tiers, 7 tiers | 0/7 | lv15 | Bgm13/AcientForest | 8140103 Blue Kentaurus L88 x22 (Manon's Forest returns here: forcedReturn 240020400, so adjacent; inferred) |
| alt1 | 240020300 | Leafre - Battlefield of Water and Darkness | 2520 x 960 | tiers (a 980 mid platform + three 700-850 floors) | 0/14 | lv15 | AcientForest | 8140101 Black Kentaurus L88 x9, 8140103 Blue Kentaurus L88 x9 |
| alt1 | 240020100 | Leafre - Battlefield of Fire and Darkness | 2340 x 1320 | tiers, taller | 4/6 | lv15 | AcientForest | 8140101 Black Kentaurus x12, 8140102 Red Kentaurus x12 (L88) (Griffey Forest forcedReturn is this map; inferred adjacent) |
| alt1 | 240030000 | Leafre - Entrance to Dragon Forest | 2970 x 960 | pyramid, floor 1170 | 0/11 | lv15 | Bgm14/DragonLoad | 8140700 Blue Dragon Turtle L90 x12, 8140701 Red Dragon Turtle L93 x5 |
| **2** | **240030200** | Leafre - Dragon Forest II | 2970 x 1260 | full-width 2970 floor + pyramid above (1390, 600 tiers) | 0/10 | lv15 | Bgm14/DragonLoad | 8140702 Rexton L95 x10, 8150200 Green Cornian L100 x6 |
| alt2 | 240030300 | Leafre - Dragon Forest III | 2970 x 1020 | 3 floors of 850-1250 + one 530 tier, 5 tiers | 0/11 | lv15 | DragonLoad | 8140703 Brexton L97 x10, 8150201 Dark Cornian L105 x1 |
| alt2 | 240030100 | Leafre - Dragon Forest I | 3510 x 1440 | symmetric pyramid, floor 1530 | 0/22 | lv15 | DragonLoad | 8140701 Red Dragon Turtle L93 x13, 8150200 Green Cornian L100 x2, 8150201 Dark Cornian L105 x2, 8140700 Blue Dragon Turtle L90 x8 |
| alt2 | 240030102 | Leafre - The Forest That Disappeared | 2160 x 1260 | tiers (12) | 0/13 | lv15 | DragonLoad | 8150200 Green Cornian L100 x9, 8150201 Dark Cornian L105 x8 |
| **3** | **240050300** | Cave of Life - Cave of Light | **3240 x 460** | **flat**: floor 2390 + 590 + two small tiers | 0/2 | FL=270456 (instance bits), no lv | Bgm14/CaveOfHontale | 9300077 T-Skelegon in Cave L113 x6 (mobTime -1, script), 9300076 Skelegon 2 in Cave L110 x15 (mobTime 1) |
| alt3 | 240050310 | Cave of Life - Cave of Darkness | 3240 x 540 | flat: one 2970 floor + 5 small tiers | 0/0 | FL=270456 | CaveOfHontale | 9300078 Jr. Newtie in Cave L105 x8 (mobTime -1; **stand-only mob, no `move`**) |
| alt3 | 240040510 | Leafre - Nest of a Dead Dragon | 1604 x 1059 | tiers, floors of 1150/1601 | 0/12 | lv15 | Bgm14/DragonNest | 8190003 Skelegon L110 x11, 8190004 Skelosaurus L113 x6 |
| alt3 | 240040511 | Leafre - The Dragon Nest Left Behind | 1600 x 1365 | tiers (12), narrow | 0/13 | lv15 | DragonNest | 8190003 Skelegon L110 x8, 8190004 Skelosaurus L113 x9 |

Mob rise on the pick: L88 -> L95-100 -> L110-113. Mob facts: Blue/Black/Red Kentaurus 37000 HP, move+chase; Rexton 50000,
Green Cornian 56000, Dark Cornian 67000 (skill 100 self buff); Skelegon 80000 (skill 112), Skelosaurus / T-Skelegon
85000 (skill 110). All have `move` and a `stand`; none has `fly`. The two cave Skelegons share ids 9300076/9300077
(the in-cave copies), the field ones are 8190003/8190004 (same stats).

Boss natives: Manon 240020401 and Griffey 240020101 are 1530 x 90 flat strips (2 tiers, FL=120); Leviathan 240040401 is
806 x 1347 with 8 tiers (vertical shaft, unusable). Their life lists add only 3-6 Kentaurus, so the bosses arrive via
the stage's own boss entry and the arena can be any Leafre map.

---------------------------------------------------------------------------------------------------------------

### 2. Masteria (Lv 80 -> 120), group `MasteriaGL`, mapMark `Crimsonwood` (Phantom Forest, Crimsonwood Mountain, Keep)

Mobs in all picks share ids 9400576-9400582: Windraider 9400576 (L70, 16000 HP, move), Firebrand 9400577 (L90, 21000,
move, **revives into 9400578 Firebrand L90 45000 HP, a `fly` form**), Stormbreaker 9400581 (L80, 38000, move),
Elderwraith 9400580 (L95, 51000, **fly only**), Nightshadow 9400579 (L100, 70000, move/jump), Crimson Guardian 9400582
(L120, 120000, move, skill 120 seal), Phantom Tree 9400588 (L50, 3500, stand/attack only: immobile), Crimson Tree 9400586
(L75, immobile), Leprechaun 9400584 (L45, 45 HP, stand/die, revive 9400583: decoration), Jr. Wraith 3230101 (L35).
Exclude Leprechaun/Phantom Tree/Jr. Wraith (and Windraider if wanted) from `pool_from_life`.

| # | map id | street - name | W x H | shape | lad/rope | flags | BGM | life |
|---|---|---|---|---|---|---|---|---|
| **1** | **610010005** | Phantom Forest - Forgotten Path | 3496 x 1052 | tiers, floors 630+810+630, 11 tiers, no ropes (jump tiers) | 0/0 | FL=8 | BgmGL/PhantomForest | 9400581 Stormbreaker L80 x5, 9400577 Firebrand L90 x3, 9400580 Elderwraith L95 x2, 9400584 Leprechaun L45 x6, 9400588 Phantom Tree L50 x3 (mobTime 1200), **9400575 Bigfoot L110 x1 (mobTime 43200)**, **9400549 Headless Horseman L101 x1 (mobTime 21600)**: both bosses are native here |
| alt1 | 610020010 | Crimsonwood Mountain - Cavern of Fear | 2410 x 625 | one 1190 floor + tiers, 7 tiers | 0/2 | FL=8 | BgmGL/CrimsonwoodKeep | Firebrand L90 x5, Stormbreaker L80 x5 |
| alt1 | 610020011 | ... Cavern of Pain | 2410 x 625 | same layout | 0/1 | FL=8 | CrimsonwoodKeep | Stormbreaker L80 x5, Windraider L70 x5 |
| alt1 | 610010003 | Phantom Forest - Phantom Road | 3316 x 932 | 9 tiers, no ropes | 0/0 | FL=8, mobRate 0.7 | PhantomForest | Windraider L70 x4, Elderwraith L95 x2, Nightshadow L100 x1, Phantom Tree x4 |
| **2** | **610020014** | Crimsonwood Mountain - Cavern of Fortitude | 2230 x 805 | one 1190 floor + tiers, 7 tiers | 0/2 | FL=8 | CrimsonwoodKeep | Firebrand L90 x4, Nightshadow L100 x3, Windraider L70 x4 |
| alt2 | 610020013 | ... Cavern of Honor | 2230 x 805 | same | 0/3 | FL=8 | CrimsonwoodKeep | Windraider L70 x7, Nightshadow L100 x6 |
| alt2 | 610020012 | ... Cavern of Shame | 2230 x 805 | same | 0/2 | FL=8 | CrimsonwoodKeep | Firebrand L90 x7, Windraider L70 x6 |
| alt2 | 610020003 | ... The Path of Strength | 2185 x 1525 | tall, 15 tiers | 0/2 | FL=8 | CrimsonwoodKeep | Firebrand L90 x8, Nightshadow L100 x6, Crimson Tree L75 x5, Elderwraith L95 x2 |
| **3** | **610020006** | Crimsonwood Mountain - Crimsonwood Keep | 1960 x 1159 | two ~1900-wide floors (y0, y-270) + 1225 floor + small tiers | 0/0 | FL=8, mobRate 0.8 | CrimsonwoodKeep | 9400582 Crimson Guardian L120 x8 |
| alt3 | 610030015 | Crimsonwood Keep - Eternal Vigilance | 1780 x 1014 | 1780 floor + 4 tiers | 0/16 | FL=0 | CrimsonwoodKeepInterior | Crimson Guardian L120 x7 |
| alt3 | 610030521 | Party Quest - Mage Mastery Room | **4500 x 1284** | 13 tiers, wide | 0/0 | FL=9080, PQ instance | PartyQuestGL | Firebrand 9400578 (fly form) L90 x13, Stormbreaker L80 x7, Elderwraith L95 x2 (all mobTime -1) |
| alt3 | 610030520 | Party Quest - Mage Mastery Room | **6120 x 1200** | very wide, 5 stacked tiers (1550, 1010, 900, 1280, 1010) | 0/0 | FL=9080, PQ instance | PartyQuestGL | Stormbreaker L80 x12, Elderwraith x2, Firebrand 9400578 x10 (mobTime -1) |

Mob rise on the pick: L80-95 -> L90-100 -> L120. Weak point: the Keep is only 1960 wide (map 3 should be roomiest); the
roomier alternates are PQ instances with lower-level flyers (Mage rooms) or the narrower Keep-interior corridor.

Flat boss arenas (native mobs too low for the pool: Jr. Wraith L35, Phantom Tree L50, Elderwraith L95 only on some):
610010100-104 Twisted Paths **3946 x 212** (one flat 3946 floor, Bigfoot native, FL=8, Bgm Bigfoot, Jr. Wraith L35 x10 +
Phantom Tree x4); 610010010-13 Hidden Evil / Creeping Evil / Evil Rising / The Evil Dead 2056 x 175 flat (Headless Horseman
and/or Bigfoot native; Evil Rising / Evil Dead add Elderwraith L95 x3). 610010200-02 Crossroads 2416 x 752 (5 tiers; Horseman
native, Phantom Tree x7, Windraider). 610030530 Thief Mastery Room (Master Guardian's native, PQ) 2430 x 1380, 9 tiers,
FL=271352, Master Guardian L100 x8: odd instance geometry, not recommended.

---------------------------------------------------------------------------------------------------------------

### 3. Ludibrium Clocktower (Lv 93 -> 108), group `ossyria`, mapMark `Ludibrium`

The Warped and Forgotten Path of Time maps are ~2100-2500 wide but **2000-3000 tall**: stacked 300-870 px platforms 240-450 px
apart, reached by 10-20 ropes and ladders, with one full-width floor at the bottom (**inferred** from `prof.py`).
Wide flat arenas exist only at the end (the two Passages and Deep Inside the Clocktower), and those carry almost no
ordinary mobs, so their pool must be set explicitly (**inferred** need: `pool_from_life` would give only the 2 Gatekeepers
or nothing).

| # | map id | street - name | W x H | shape | lad/rope | flags | BGM | life |
|---|---|---|---|---|---|---|---|---|
| **1** | **220070300** | Ludibrium - Forgotten Path of Time<4> | 2507 x 2265 | tower: floor 2507 at the bottom + ~1150-wide shelves, 15 tiers | 3/15 | lv15, mobRate 0.6 | Bgm10/TimelessB | 8142000 Phantom Watch L95 x26 |
| alt1 | 220060300 | Ludibrium - Warped Path of Time<4> | 2137 x 2368 | tower: floor 2133 + 200-700 platforms, 26 tiers | 6/14 | lv15 | Bgm09/FairyTalediffvers | 8141000 Spirit Viking L93 x14 |
| alt1 | 220070200 | Ludibrium - Forgotten Path of Time<3> | 2507 x 1779 | tower, floor 2507, 13 tiers | 0/15 | lv15 | TimelessB | 7130010 Death Teddy L85 x29 |
| **2** | **220070301** | Hidden Street - Forbidden Time | 2388 x 2429 | tower: 2388 floor + 560-870 tiers, 8 tiers | 2/9 | lv15, mobRate 0.4 | Bgm10/TimelessB | 8143000 Grim Phantom Watch L99 x14 |
| alt2 | 220060301 | Hidden Street - Twisted Time | 2013 x 2865 | tower, 3 shelves ~1200 | 7/2 | lv15 | FairyTalediffvers | 8141100 Gigantic Spirit Viking L98 x26 |
| **3** | **220070400** | Ludibrium - Forgotten Passage | **2995 x 130** | flat (3 low steps) | 0/0 | lv15, mobRate 0.7 | Bgm10/TheWayGrotesque | 8170000 Thanatos L108 x2 (mobTime 30; no boss flag) |
| alt3 | 220060400 | Ludibrium - Warped Passage | **2995 x 0** | one flat 2995 floor | 0/0 | lv15 | Bgm10/BizarreTales | 8160000 Gatekeeper L108 x2 (mobTime 30; no boss flag) |
| alt3 | 220080000 | Ludibrium - Deep Inside the Clocktower | **4143 x 299** | flat 4143 floor + 5 small steps | 0/0 | lv15, FL=72 | Bgm07/WhereverYouAre | none |
| alt3 | 220080001 | Ludibrium - Origin of Clocktower | 1190 x 594 | one 1190 floor + 1 step | 0/1 | lv15, FL=8440, mobRate 5 | Bgm07/WhereverYouAre | none (Papulatus's native arena; small) |

Mob rise on the pick: L95 -> L99 -> L108 (Gatekeeper/Thanatos are plain unflagged mobs: 78000 / 70000 HP, `move`, speed -50;
Thanatos is undead, attack1 type 3 with area warning and skills 125/124/120/121; Gatekeeper attacks type 0 and skill 123
stun). Lower Ludibrium (Toy Factory 3700-4200 wide flat, Path of Time) is Lv34-46: too low. Strict "boss natives"
triple is 220060400 (Gatekeeper) -> 220070400 (Thanatos) -> 220080001 (Papulatus), but the last is tiny and empty.

---------------------------------------------------------------------------------------------------------------

### 4. Temple of Time / Time Lane (Lv 101 -> 131), group `ossyria`, mapMark `TimeTemple`

Every Memory Lane / Road of Regrets / Road to Oblivion 1-5 map is the same 2403-2420 x ~1096 frame: two full-width
~2403 floors (y 180 and y -570) plus partial 700-1250 upper tiers (y -180, y -900), connected by 4-7 ladders (no ropes);
floors are ~750 px apart so ladders are required (**inferred** from `prof.py`). No swim/decHP/timeLimit/partyOnly,
FL=0, lv20, mobRate 1.4-1.5.

| # | map id | street - name | W x H | tiers | lad/rope | BGM | life |
|---|---|---|---|---|---|---|---|
| **1** | **270020400** | Time Lane - Road of Regrets4 | 2404 x 1097 | 13 | 7/0 | Bgm16/Repentance | 8200008 Chief Qualm Guardian L116 x17, 8200007 Qualm Guardian L113 x2, 8200000 Eye of Time L80 x3 |
| alt1 | 270020300 | Road of Regrets3 | 2404 x 1097 | 10 | 5/0 | Repentance | Qualm Guardian L113 x17, Eye of Time x3 |
| alt1 | 270010500 | Memory Lane5 | 2405 x 1094 | 6 | 4/0 | Bgm16/Remembrance | 8200004 Chief Memory Guardian L101 x14, **Dodo L121 x1 (mobTime 3600)**, Eye of Time x4 |
| **2** | **270030200** | Road to Oblivion2 | 2403 x 1096 | 13 | 6/0 | Bgm16/Forgetfulness | 8200010 Oblivion Monk Trainee L124 x22, Eye of Time x2 |
| alt2 | 270030300 | Road to Oblivion3 | 2403 x 1096 | 13 | 6/0 | Forgetfulness | 8200011 Oblivion Guardian L128 x15, Eye of Time x2 |
| alt2 | 270020500 | Road of Regrets5 | 2404 x 1096 | 7 | 4/0 | Repentance | Chief Qualm Guardian L116 x14, **Lilynouch L131 x1 (mobTime 3600)**, Eye of Time x3 |
| **3** | **270030500** | Road to Oblivion5 | 2403 x 1095 | 13 | 7/0 | Forgetfulness | 8200012 Chief Oblivion Guardian L131 x15, **Lyka L141 x1 (mobTime 3600)** |
| alt3 | 270030400 | Road to Oblivion4 | 2404 x 1095 | 7 | 4/0 | Forgetfulness | Chief Oblivion Guardian L131 x14, Oblivion Guardian L128 x3, Eye of Time x1 |
| alt3 | 270030100 | Road to Oblivion1 | 2412 x 1097 | 12 | 6/0 | Forgetfulness | 8200009 Oblivion Monk L121 x22, Eye of Time x2 |

Mob rise on the pick: L116 -> L124 -> L131. All guardians/monks have `stand`+`move`, 2-3 attacks, no skills, no fly:
Chief Qualm Guardian 99000 HP, Oblivion Monk Trainee 123000, Chief Oblivion Guardian 141000 (exp 7060). Eye of Time (8200000,
L80, 24000 HP, `move`, attack1/2) is a low filler: exclude from the pool. "Natural" alternative: the three boss maps
270010500 -> 270020500 -> 270030500 (L101 -> L116 -> L131, one native boss each). Deeper: 270050100 Twilight of Gods (Pink
Bean) has no ordinary mobs (Lv1 NPC mobs), unusable.

---------------------------------------------------------------------------------------------------------------

### 5. Papulatus (all 8500xxx mobs, read from `Mob.wz`)

| id | name | Lv | maxHP | EXP | speed | stances | attacks (type / attackAfter ms / elem / range) | skills (id/lvl, action) | revive |
|---|---|---|---|---|---|---|---|---|---|
| 8500000 | Time Sphere | 100 | 16000 | 0 | 0 | stand, die1 (no move, no hit) | none | none | **8500001** |
| 8500001 | Papulatus Clock | 125 | **23,000,000** | 596,000 | -40 | stand, **move**, attack1-4, skill1-4, hit1, die1 (**no fly**) | a1 type0 1260 L (magic, deadlyAttack, lt-670,-465 rb670,0); a2 type0 810 I (same box); a3 type0 0 L (box -800,-600..800,250); a4 type0 540 F (same box as a1). All `magic`. | 127/1 a1; 126/1 a2; 200/39 a3; 200/40 a3; 114/4 a4; 123/4 a1 | **8500002** |
| 8500002 | Papulatus | 125 | 1,590,000 | 970,000 | **60** | **fly**, stand, hit1, die1 (no move, no attack stance) | none (body attack only; PAD 800 MAD 1000) | none | none |
| 8500003 | High Darkstar | 71 | 10,000 | 0 | 0 | stand, attack1, hit1, die1 | a1 type0 900, range +-65 x 100 up; selfDestruction | none | none |
| 8500004 | Low Darkstar | 80 | 10,000 | 0 | 0 | stand, move, jump, skill1, attack1, hit1, die1 | a1 type0 900, same range; selfDestruction | 100/2 | none |

Revive chain: **Time Sphere 8500000 -> (dies) Papulatus Clock 8500001 (23M, ground) -> (dies) Papulatus 8500002 (1.59M,
flies)**. Total 24.59M HP across the real fight. The Time Sphere is unplaced (no Map.wz life, not in MonsterBook); in
the files only 220080001 (Origin of Clocktower, lvLimit 15, mobRate 5, no life) is tied to it via `mbookID` 8500002
(**inferred** that a script spawns 8500001 there). The flyer is the *second* form (8500002, `fly` only, no attacks, fast:
speed 60); the first form 8500001 has `move` and four attack stances. The Darkstars are summoned by the Clock's
MobSkill 200/39 (High Darkstar 8500003, spawn area lt(-500,-500) rb(500,-150)) and 200/40 (Low Darkstar 8500004,
lt(-500,-150) rb(500,0)): both `interval 1`, `hp<=95%`, `limit 5000`, 4 slots each, i.e. they flood the screen.
MobSkill details: 127/1 (prop 100, interval 1, area +-300x120) and 123/4 (stun-class, time 3, prop 100) are not in the sim's
SUPPORTED set; 126/1 slow (x80, time 10, interval 5, prop 100), 114/4 heal (x30000, y10000, hp<99, interval 1), 200/39+40 are.
Skill-id names are the usual community meanings (127 dispel, 123 stun, 126 slow, 114 heal, 200 summon): **inferred**.
No other 8500xxx mob exists in `Mob.wz`.

---------------------------------------------------------------------------------------------------------------

### 6. Per-boss facts

`move` = has the `move` stance (all but Papulatus form 2 and the Time Sphere). Attack `type` 0 area, 1 targeted, 2 ball,
3/4 other (the sim only takes 0/1/2). Range = lt..rb of `attackN/info/range` (px relative to the boss).

| boss | Lv / HP | speed | stances | attacks (type, attackAfter ms, range) | MobSkill (id/lvl) | revive | native map and usability |
|---|---|---|---|---|---|---|---|
| Manon 8180000 | 105 / 3.7M | -20 | move, stand, attack1-3, hit1, die1 | a1 type0 1750 F deadly (-300,-200..30,10); a2 type0 1040 (-400,-200..30,25); a3 type0 650 (-350,-200..350,30). all magic, facing left side | none | none | 240020401 (10800 s) / 240020402 (1800 s): **1530 x 90 flat**, 2 tiers, FL=120, lv15, Blue Kentaurus x6. Small but flat |
| Griffey 8180001 | 105 / 3.7M | -20 | same as Manon | a1 type0 700 (-320,-180..30,10); a2 type0 400 deadly (-350,-200..350,30); a3 type0 400 L (-350,-200..30,25) | none | none | 240020101 / 240020102: **1530 x 90 flat**, no ropes |
| Leviathan 8220003 | 120 / 13.4M | -20 | move, stand, attack1-2, skill1, hit1, die1 | a1 type0 1800 I (-416,-300..-100,10); a2 type0 1440 F knockback+jumpAttack (-810,-304..-20,10) | 132/2, 122/3, 200/89 (Red Wyvern 8150300 x6), 200/90 (Blue 8150301 x4), 200/91 (Dark 8150302 x4) | none | 240040401: **806 x 1347 vertical**, 8 tiers, 1 ladder 4 ropes: unusable |
| Master Guardian 9400594 | 100 / 7M | -20 | move, stand, skill1, attack1-2, hit1, die1 | a1 type0 1040 magic (-305,-160..272,31); a2 type0 1260 (-69,-56..57,56) | 120/12 (seal) | none | 610030530 PQ Thief Mastery Room: 2430 x 1380, 9 tiers, FL=271352, mobRate 0.6: odd instance geometry |
| Headless Horseman 9400549 | 101 / 3.5M | -15 | move, **chase**, stand, attack1-2, hit1, die1 | a1 type0 1040 (-176,-82..62,-1); a2 type0 350 (-167,-76..-5,0) | none | none | 610010010/11/12/13 (21600 s): 2056 x 175 flat, FL=8; also 610010005, 610010200-02 |
| Bigfoot 9400575 | 110 / 32M | **90** (fast) | move, jump, stand, attack1, hit1, die1 | a1 type0 750 (-97,-146..84,16) | none | none | 610010100-104 Twisted Paths: **3946 x 212 flat**, FL=8 (best arena of the set) |
| Gatekeeper 8160000 | 108 / 78k (no boss flag) | -50 | move, stand, attack1-2, skill1, hit1, die1 | a1 type0 1800 (eff 720) (-321,-272..142,2); a2 type0 1800 L magic (-296,-274..119,0) | 123/1 (stun) | none | 220060400: **2995 x 0 flat** |
| Thanatos 8170000 | 108 / 70k (no boss flag, undead) | -50 | move, stand, attack1, skill1-4, hit1, die1 | a1 **type3**, areaWarning, areaCount 9, attackCount 5, 1080 I magic (-33,-109..44,4): sim rejects type 3 | 125/1, 124/1, 120/1, 121/1 (none in sim) | none | 220070400: **2995 x 130 flat**, 3 low steps |
| Dodo 8220004 | 121 / 5.9M | -70 | move, stand, attack1-2, skill1-2, hit1, die1 | a1 type2 (ball) 1050, sp(-129,-44) r400; a2 type0 960 magic (-320,-310..-87,-6) | 129/2 (banish, supported), 102/3 | none | 270010500: 2405 x 1094, 6 tiers, 4 ladders, 3600 s |
| Lilynouch 8220005 | 131 / 7.6M | -20 | move, stand, attack1-2, skill1-2, hit1, die1 | a1 type0 1250 I (-416,-300..-100,10); a2 type0 1710 F knockback+jumpAttack (-810,-304..-20,10) (same boxes as Leviathan) | 114/23 (heal, supported), 145/1 | none | 270020500: 2404 x 1096, 7 tiers |
| Lyka 8220006 | 141 / 9.3M | -50 | move, stand, attack1-2, skill1-2, hit1, die1 | a1 **type4**, areaWarning, areaCount 15, attackCount 7, 1260 (-40,-200..40,0): sim rejects type 4; a2 type0 960 F magic (-300,-272..100,0) | 100/2 (supported), 128/7 (seduce class, not supported), 114/9 (supported) | none | 270030500: 2403 x 1095, 13 tiers, 7 ladders |
| Papulatus 8500001 -> 8500002 | see Section 5 | | | | | Time Sphere -> Clock -> Papulatus | 220080001: 1190 x 594, 2 tiers: small (use 220080000, 4143 x 299, instead) |

No boss listed has a `fly` stance except Papulatus form 2 (8500002). Only Papulatus has a revive list. Bosses whose
whole kit is already in the sim (types 0/1/2, MobSkill in SUPPORTED): Manon, Griffey, Headless Horseman, Bigfoot,
Master Guardian (120 not supported), Dodo (102 not), Lilynouch (145 not). Blockers: Thanatos (type3 + four debuffs), Lyka
(type4 + 128), Leviathan (132, 122), Gatekeeper (123), Papulatus Clock (127, 123).

---------------------------------------------------------------------------------------------------------------

### 7. Other Lv 90+ arenas (alternates), ordinary non-swim, no decHP

A scan of all 5261 maps with >=4 non-boss mobs and mean level >= 75 outside the four regions finds only these usable
ones; there is no large pool of Lv100-160 maps elsewhere (**the data stops at Time Lane / Crimson Guardian**).

| map id | street - name (group) | mean/max Lv | W x H | shape | lad/rope | flags | life |
|---|---|---|---|---|---|---|---|
| 240070602 | Neo City - Air Battleship Area B (`ossyria`, Tera Forest line) | 93 | 2371 x 689 | three wide floors 2370/2370/1326, 4 ladders | 4/0 | FL=72, lv90, **partyOnly=1** | 8140512 Royal Guard L93 x16 (skill 114/34, `regen` stance) |
| 240070601 | ... Area A | 91-93 | 2252 x 689 | same style | 4/0 | FL=72, lv90, partyOnly=1 | Imperial Guard 8140511 L91 x10, Royal Guard L93 x8 |
| 240070600 | ... Bow | 91 | 2019 x 1193 | 4 tiers | 3/0 | FL=72, lv90, partyOnly=1 | Imperial Guard L91 x16 |
| 800020130 | Zipangu - Encounter with the Buddha (`jp`) | 100 | **2868 x 205** | **one flat floor** | 0/0 | FL=0, forcedReturn 800020120 | 9400013 Dreamy Ghost L100 x16 (68000 HP, move), 9400014 Black Crow L115 boss 35M HP (mobTime 82800) |
| 800020400 | Zipangu - WanWan Spa of Hell | 90 | 2958 x 953 | tiers, 10 | 0/7 | FL=0, mobRate 0.8 | 8140500 Bain L90 x21 (45000) |
| 801040004 | Zipangu - Armory (Showa) | 90 | **3000 x 58** | flat, 2 tiers | 0/0 | FL=228 | Bain L90 x14, 9400122 Male Boss L95 (85000 HP) |
| 551030100 | Malaysia - Entrance to the Spooky World (`singapore`) | 94 | 2302 x 1019 | floor 2302 + 1312 + shelves, 6 tiers | 0/2 | FL=0 | 9420540 Gallopera L94 x17 (43000, skill 114/26) |
| 211042200 | El Nath - The Cave of Trial III | 67 (Bain L90 x13) | **5190 x 516** | very wide, 9 tiers | 0/20 | FL=64 | Firebomb L51 x9, Bain L90 x13, Cerebes L72 x7, Jr. Cerebes L43 x8 (mixed levels) |
| 211042000 / 211042100 | El Nath - The Cave of Trial I / II | L72 | 3930 x 517 / 4290 x 518 | wide, 8-9 tiers | 0/9, 0/12 | FL=64 | Cerebes L72 x11-13, Jr. Cerebes L43 |
| 600020300 | MesoGears - Wolf Spider Cavern (Masteria) | 80 | 3130 x 1657 | 16 tiers | 1/0 | FL=0 | Wolf Spider L80 x64 |

Rejected on purpose: all Aqua Road deep maps (2300400xx: Squid/Shark/Bone Fish L90-102, but `swim=1`, `decHP=6`,
~1000 wide shafts), Wyvern Canyon (806 wide), El Nath outdoor maps (`decHP=10`), Dead Mine (L57), Herb Town (L64-70),
Mu Lung (L<=66), Horntail's Cave 240060200 / Zakum's Altar 280030000 / Pink Bean 270050100 (no ordinary mobs, boss/PQ
instances), the 4 Haunted House rooms (1058 wide).
