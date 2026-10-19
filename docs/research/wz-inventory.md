# wz-inventory: vanilla GMS v83 WZ inventory, using a throwaway Node explorer

Asset root: `C:\Users\itech\Coding\maple-survivors-refs\v83-original\` (files dated 2010-02-17; UI.wz is dated 2010-02-21).
Explorer and scratch output: `C:\Users\itech\Coding\maple-survivors-refs\research\wz-inventory\`
- `wz.js` is the read-only WZ parser and CLI. Usage: `node wz.js info|ls|dump|png <File.wz> [path] [depth|out.png]`. It uses only Node built-ins: fs, zlib and crypto (`aes-256-ofb`).
- `tasks.js` is the task driver. It writes `out/1-base.txt` … `out/10-perf.txt`.
- `census.js` does a full parse of every WZ file and writes `out/census.txt`. `scan-info.js` checks the `info` keys of all 5261 maps (`out/scan-info.txt`). `check-odd.js` covers encrypted canvases and format 517.
- Decoded PNGs used for visual checks are in `out/` (snail, Henesys back, encrypted mob frame, Three Snails shells). `out/CavaBien.mp3` is a raw BGM extract. `out/list-wz.txt` is the decoded List.wz.

Run on Node v24.21.0 under Windows 11. All numbers below come from these scripts. The `out/*.txt` file named next to a claim is its evidence.

## Summary

- **Version and key.** Every PKG1 file (all 16 except List.wz) has encVersion `0x00AC` = 172. 172 matches `encVer(hash("83"))`, with hash = 1876. Among versions 1..399, 83 is the only one that produces 172. Strings and directory names decode only with the **GMS keystream** (IV `4D23C72B`). The KMS IV and an all-zero key both give garbage (`out/1-base.txt`).
- **The format refresher is mostly correct.** Corrections:
  - Header `fileSize` is the file length minus dataStart, not the full file length.
  - Pixel format really is `fmt + fmt2`: format 517 is stored as fmt=513 with fmt2=4.
  - The Sound_DX8 header is 82 bytes only for MP3. PCM entries have a 70-byte header.
  - Dir entry type 1 and property types 19 and 20 never occur in v83. Type 11 occurs once.
  - **Block-encrypted canvas data does occur.** It appears in 9,669 Mob.wz canvases across 319 imgs, including the stage mobs Slime 0210100 and Pig 1210100. It decodes with the GMS keystream; the zero key fails.
- **Pixel formats in v83** (all 16 files parsed with 0 errors; `out/census.txt`): 99.9% BGRA4444 (format 1; 544,240 of 544,718 canvases), plus 278 BGRA8888 (2), 198 RGB565 (513, all in UI.wz) and 2 RGB565-16x16-block (517, both Map.wz Back). There are **no DXT3/DXT5** canvases.
- **Physics.img** has 19 values, all doubles except `flyJumpDec`, which is a float. Examples: walkSpeed 125, jumpSpeed 555, gravityAcc 2000, fallSpeed 670 (full table below).
- **Map 104040000** ("Henesys Hunting Ground I"):
  - bgm `Bgm01/CavaBien`, 5 grassySoil backs, layer-1 tileset `grassySoil`, 181 footholds with bbox x[-489,1749] y[-1105,480], 8 ladders/ropes, 18 portals.
  - Mob pool: 0120100 Shroom ×10, 0100101 Blue Snail ×8, 0130101 Red Snail ×12, 1210100 Pig ×9.
  - **No VRLeft/VRTop/VRRight/VRBottom and no fieldLimit.** Only 4050 of the 5261 maps have VR bounds.
- **Mobs.**
  - None of the five requested mobs has `info/link`, although 405 other Mob.wz imgs do.
  - All five have `move`, `stand`, `hit1` and `die1`; Slime 0210100 and Orange Mushroom 1210102 also have `jump`.
  - Every frame is BGRA4444 and has `origin` and `head`. `lt`/`rb` (hitbox) appear on all non-die frames. `delay` is present whenever a stance has more than one frame (single-frame `stand` frames have none). The last die frame fades with `a0=255 a1=0`.
- **Character.**
  - Body 00002000.img has 157 stances (plus `info`). The basic stances hold canvases. Skill stances (e.g. `magic1`, `savage`) are lists of `{action, frame, delay}` references into the basic stances, and negative delays are common.
  - `stand1/0` is `body` + `arm` with anchors `navel`/`neck`/`hand`. The head anchors face and hair via `brow`.
  - Beginner creation equips come from `Etc.wz/MakeCharInfo.img`; all the requested ids exist.
- **Skills.**
  - Three Snails (0001000) keeps its **snail-shell projectile per level** at `000.img/skill/0001000/level/{1,2,3}/ball` (3 frames, 90 ms each), with a per-level `hit/0` (6 frames). L1 is a green shell and L3 is a red shell (verified by decoding).
  - Energy Bolt 2001004, Fire Arrow 2101004 and Poison Breath 2101005 have a `ball` node.
  - Magic Guard 2001002 and Magic Claw 2001005 have `effect`; Magic Armor 2001003 has neither. Magic Claw 2001005 has no ball, and its hit and effect visuals vary by `CharLevel/{10,15,20,25}`.
- **Effect / UI / Sound.**
  - BasicEff.img has damage digit sets NoRed0/1, NoBlue0/1, NoCri0/1 and NoViolet0/1, plus `Miss`, `LevelUp` (21 frames) and `JobChanged` (13 frames).
  - UI.wz has StatusBar `gauge`/`number`, `Basic.img/LevelNo` (level digits, 11×13), Notice/YesNo windows and buttons.
  - BGM is MP3 (MPEG-2 Layer III). CavaBien is 22050 Hz joint stereo at 80 kbps, 128000 ms long.
- **Performance** (Node, warm OS file cache): opening Map.wz and reading its root dir takes 0.3 ms. Parsing 104040000.img (55,569 bytes, 5,197 nodes) takes 4–10 ms. Parsing **all 5261 maps** takes 1.56 s. Decoding the largest stage back (2493×340 BGRA4444) takes 8–12 ms. A full parse of Character.wz (3.43M nodes) takes 3.4 s.

## Detailed findings

### 1. Base facts (`out/1-base.txt`, `out/census.txt`)

**Header.** Evidence is `xxd -l 96 Base.wz` and the `info` command:

```
00000000: 504b 4731 5019 0000 0000 0000 3c00 0000  PKG1P.......<...
00000030: 2057 697a 6574 2c20 5a4d 5300 ac00 ...    Wizet, ZMS.....
```

The u64 field reads 6480 while Base.wz is 6540 bytes, so the field equals the file length minus dataStart (60). This holds for every file; for example Map.wz has field 635444835 and is 635444895 bytes. Copyright is `"Package file v1.0 Copyright 2002 Wizet, ZMS"`. The u16 at offset 60 is `0x00AC`.

**Version.** `versionHash("83")` = 1876 (0x754), and encVer = `0xFF^0^0^0x07^0x54` = 0xAC = 172. Every file returns `candidates=[83]`, and its root directory parses with valid offsets.

**String key test.** Evidence is `out/1-base.txt`, lines starting with `IV`:
- `IV gms`: `["GuestEULA.img","Consume.img","MonsterBook.img","NameChange.img","Skill.img"]`
- `IV kms`: garbage (`"z¾\u0013Ò[rßÖ#ë…"`)
- `IV zero`: garbage (`"ÑÛZ×<¿Ü…"`)

So v83 GMS uses AES-256 with the trimmed user key and IV `4D 23 C7 2B` ×4. That keystream is exactly AES-256-OFB over zeros (`wz.js:13-24`).

**List.wz** is not PKG1. It is a sequence of entries, each an i32 length, then UTF-16 characters XORed with the GMS keystream (no incrementing mask), then a u16 terminator. Decoded, it has 371 entries: `dummy` plus 370 `mob/XXXXXXX.img`, and the last entry's final character is garbled (`mob/9500335.im/`). All 319 Mob.wz imgs with block-encrypted canvases appear in List.wz. The other 51 listed imgs have only zlib canvases. List.wz is therefore the client's list of imgs that need the encrypted-canvas path (`out/list-wz.txt`).

**Per-file inventory.** "Dirs" and "imgs" are recursive totals. "Top-level" is the root listing.

| File | Size (bytes) | Dirs | Imgs | Top-level |
|---|---|---|---|---|
| Base.wz | 6,540 | 15 stubs (size 0, offsets 337–351 inside Base.wz; not real) | 3 | smap.img, zmap.img, StandardPDD.img + stub dirs UI, Effect, Sound, Map, Character, Item, TamingMob, Etc, Npc, Reactor, Skill, Morph, String, Mob, Quest |
| Character.wz | 186,792,151 | 17 | 7,201 | 18 body/head imgs = 9 skins × (body 0000200X + head 0001200X) for skins X = 0,1,2,3,4,5,9,10,11 (no 6/7/8) + Longcoat 491, Weapon 1220, Ring 112, Shoes 417, Pants 404, PetEquip 69, Glove 236, Cap 908, Cape 178, Hair 1518, Afterimage 15, Dragon 12, Accessory 500, Shield 58, Coat 462, TamingMob 47, Face 536 |
| Effect.wz | 63,334,965 | 0 | 17 | MapEff, ItemEff, Direction(1-3), BasicEff, SkillName1-4, Tomb, PetEff, OnUserEff, SetEff, CharacterEff, Summon |
| Etc.wz | 1,201,101 | 0 | 22 | incl. MakeCharInfo, Commodity, ItemMake, NpcLocation, ForbiddenName… |
| Item.wz | 18,361,778 | 6 | 155 | Special 4, Pet 54, Cash 49, Etc 18, Install 2, Consume 28 |
| Map.wz | 635,444,895 | 14 | 5,602 | Physics.img, Effect.img, MapHelper.img, Tile 102, WorldMap 21, Obj 107, Back 107, Map/ (AreaCode.img + Map0,1,2,3,5,6,7,8,9 = 5261 maps; there is no Map4) |
| Mob.wz | 479,665,103 | 1 | 1,568 | 1564 mob imgs + QuestCountGroup/ 4 |
| Morph.wz | 6,204,606 | 0 | 42 | |
| Npc.wz | 51,137,866 | 0 | 1,620 | |
| Quest.wz | 5,971,537 | 0 | 6 | |
| Reactor.wz | 54,133,811 | 0 | 419 | |
| Skill.wz | 76,874,780 | 0 | 76 | 000, 100…522, 1000…1512, 2000…2112, 800, 900, 910, MobSkill, ItemSkill, MCSkill, MCGuardian, BFSkill |
| Sound.wz | 363,261,964 | 0 | 44 | Bgm00–Bgm21, BgmEvent, BgmGL, BgmJp, BgmMY, BgmSG, BgmUI, Game, UI, Field, Skill, Item, Mob, Pet, Reactor, Summon, Weapon, Object, MiniGame, Jukebox, CashEffect, ConsumeEffect, Radio |
| String.wz | 3,251,564 | 0 | 20 | Mob, Map, Skill, Eqp, Etc, Consume, Ins, Cash, Pet, Npc, MonsterBook, EULA(s), ToolTipHelp, PetDialog, … |
| TamingMob.wz | 797 | 0 | 7 | |
| UI.wz | 28,259,933 | 0 | 19 | Logo, StatusBar, Basic, UIWindow, Login, CashShop, ITC, MapLogin, ChatBalloon, NameTag, GuildMark, MapleTV, tutorial, BuffIcon… |

**Census of property types and formats.** All 16 files parse with 0 errors; the full table is in `out/census.txt`.
- Property raw types used: 0 (null), 2 (short), 3 (cint), 4 (float), 5 (double), 8 (string), 9 (extended).
- Type 11 (short) appears once, in Quest.wz. Types 19 and 20 never appear, so compressed-long parsing is untested.
- All six extended types appear.
- The u16 after "Property" in the img header is always 0.
- Canvas fields: the leading u8 is always 0, the i32 after format2 is always 0, and the header byte before the data is always 0.

| Canvas fmt+fmt2 | Count | Where |
|---|---|---|
| 1+0 (BGRA4444) | 544,240 of 544,718 canvases: Character 391,184 · Mob 50,787 · Map 32,422 · Item 16,843 · Skill 15,738 · Npc 15,453 · UI 10,571 · Effect 5,024 · Reactor 4,384 · Morph 1,824 · Etc 10 | everywhere |
| 2+0 (BGRA8888) | 278 (Map 118, Effect 90, UI 70) | big backs (timeTemple, laboratory, folkvillige…), Obj/tower |
| 513+0 (RGB565) | 198 | UI.wz only |
| 513+4 (=517, RGB565 per 16×16 block) | 2 | `Map.wz/Back/dryRock.img/back/0` (256×256, inflates to 512 bytes) and `Back/midForest.img/back/0` (128×128, inflates to 128 bytes). The midForest one is the type-3 base back of stage 100020000. |
| 1026 / 2050 (DXT) | 0 | none |

Sampled decodes: 2,569 canvases inflated to exactly `expectedRawSize`, with 0 mismatches. Visual checks: `out/mob0100100-stand0.png` (snail), `out/largest-back.png` (Henesys hill) and `out/encrypted-mob-canvas.png` all render correctly.

**Encrypted canvases.** Example: `Mob.wz/6230601.img/move/0`. The data starts with `02000000 ee32…`, which is i32 blockLen=2 followed by XORed bytes. After XOR with the GMS keystream, the result is `789c…` and inflates to 22,344 bytes, the expected size. With the zero key, inflate fails with "invalid distance too far back" (`check-odd.js`). Affected stage mobs include `0210100.img` (16 canvases) and `1210100.img` (11 canvases).

### 2. Map.wz/Physics.img (`out/2-physics.txt`)

| Key | Value | Type |
|---|---|---|
| walkForce | 140000 | double |
| walkSpeed | 125 | double |
| walkDrag | 80000 | double |
| slipForce | 60000 | double |
| slipSpeed | 120 | double |
| floatDrag1 | 100000 | double |
| floatDrag2 | 10000 | double |
| floatCoefficient | 0.01 | double |
| swimForce | 120000 | double |
| swimSpeed | 140 | double |
| flyForce | 120000 | double |
| flySpeed | 200 | double |
| gravityAcc | 2000 | double |
| fallSpeed | 670 | double |
| jumpSpeed | 555 | double |
| maxFriction | 2 | double |
| minFriction | 0.05 | double |
| swimSpeedDec | 0.9 | double |
| flyJumpDec | 0.35 (0.3499999940395355) | float |

### 3. Maps (`out/3-maps.txt`, `out/scan-info.txt`)

**104040000** (`Map/Map1/104040000.img`, 55,569 bytes). Top-level children: `info, back, life, 0..7, reactor(empty), ToolTip(8), foothold, ladderRope, miniMap, portal`.

`info`:

| Key | Value |
|---|---|
| version | 10 |
| cloud | 0 |
| town | 0 |
| returnMap | 100000000 |
| mobRate | 1.4999983 |
| bgm | `Bgm01/CavaBien` |
| mapDesc | "" |
| forcedReturn | 999999999 |
| hideMinimap | 0 |
| moveLimit | 0 |
| mapMark | `Henesys` |

The map has **no VR\*, no fieldLimit, no swim/fly**. Across all 5261 maps, VRLeft/VRTop/VRRight/VRBottom appear in 4050, fieldLimit in 5153 and swim in 4998. A map without VR bounds needs its camera bounds derived from footholds or the minimap.

`back` (columns: bS, no, x, y, rx, ry, cx, cy, type, a, front, ani, f):

| # | bS | no | x | y | rx | ry | cx | cy | type | a | front | ani | f |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 0 | grassySoil | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 3 | 255 | 0 | 0 | 0 |
| 1 | grassySoil | 1 | -16 | -184 | -5 | -5 | 0 | 0 | 4 | 255 | 0 | 0 | 0 |
| 2 | grassySoil | 2 | 441 | 74 | -8 | -8 | 0 | 0 | 0 | 255 | 0 | 0 | 0 |
| 3 | grassySoil | 3 | 320 | -230 | -8 | -8 | 0 | 0 | 0 | 255 | 0 | 0 | 0 |
| 4 | grassySoil | 4 | -171 | 195 | -15 | -15 | 0 | 0 | 1 | 255 | 0 | 0 | 0 |

Back no=2 is `Map.wz/Back/grassySoil.img/back/2`, a 2493×340 BGRA4444 canvas.

Layers (tS = tileset):

| Layer | tS | Tiles | Objs | Contents |
|---|---|---|---|---|
| 0 | – | 0 | 59 | objs all `acc1/grassySoil/nature/*` |
| 1 | grassySoil | 288 | 44 | tiles enH0 72, enH1 72, bsc 96, edD 20, edU 20, enV0/enV1 8; objs grassySoil market/nature + `guide/milepost` |
| 2 | – | 0 | 30 | objs `connect/ladder/0/*` and `connect/rope/0/*` (the ladder/rope graphics are Obj, not tiles) |
| 3 | – | 0 | 2 | |
| 4–7 | – | 0 | 0 | empty |

Footholds: 181, all in foothold layer 1 (10 groups). Bbox is x −489..1749, y −1105..480. A sample foothold: `x1=1311 y1=-85 x2=1389 y2=-85 prev=14 next=2`.

ladderRope (fields l, uf, x, y1, y2, page):

| # | l | uf | x | y1 | y2 | page |
|---|---|---|---|---|---|---|
| 1 | 1 | 1 | −70 | −83 | 105 | 2 |
| 2 | 1 | 1 | 1280 | −83 | 57 | 2 |
| 3 | 0 | 1 | 336 | −323 | −127 | 2 |
| 4 | 0 | 1 | 675 | −83 | 143 | 2 |
| 5 | 1 | 1 | 1237 | −323 | −238 | 2 |
| 6 | 1 | 1 | 1158 | −563 | −480 | 2 |
| 7 | 0 | 1 | 708 | −563 | −367 | 2 |
| 8 | 0 | 1 | 958 | −1103 | −668 | 2 |

Portals: 18 in total.
- 14 spawn points (`pn=sp pt=0`).
- `in00` pt=3 at (958,−851), leading to 104040001 `st00`.
- `st01` pt=1 at (1058,−695).
- `west00` pt=2 at (−322,215), leading to 104030000 `east00`.
- `east00` pt=2 at (1625,216), leading to 100000000 `west00`.

Life: 40 entries (39 mobs + 1 hidden NPC 9000068). Each entry has fields `type, id, x, y, mobTime=0, f, hide, fh, cy, rx0, rx1`.

miniMap: a 144×114 canvas with width=2317, height=1832, centerX=530, centerY=1278, mag=4.

**Other stage candidates.** Mob names come from String.wz.

| Map | Name (String.wz) | bgm | Backs (bS) | Layer tS | Footholds / bbox | Ladders | Portals | Mob pool |
|---|---|---|---|---|---|---|---|---|
| 104040000 | Henesys Hunting Ground I | Bgm01/CavaBien | 5 grassySoil | L1 grassySoil | 181 / x−489..1749 y−1105..480 | 8 | 18 | Shroom 0120100 ×10, Blue Snail 0100101 ×8, Red Snail 0130101 ×12, Pig 1210100 ×9 |
| 104040001 | Henesys Hunting Ground II | Bgm01/CavaBien | 5 grassySoil (same as above) | L1 grassySoil (252 tiles) | 175 / x−309..1479 y−1045..120 | 8 | 10 | Pig 1210100 ×8, Orange Mushroom 1210102 ×9, Ribbon Pig 1210101 ×12, Green Mushroom 1110100 ×7, event "Strange" mobs 9400614–9400617 ×7 |
| 100010000 | The Hill East of Henesys | Bgm00/RestNPeace | 6 grassySoil | L0/L1/L2 grassySoil | 205 / x−669..2019 y−595..720 | 6 | 18 | Blue Snail ×17, Red Snail ×11, Shroom ×9, Pig ×13, Cynical Orange Mushroom 9300274 ×2 |
| 100020000 | The Rain-Forest East of Henesys | Bgm00/RestNPeace | 5 midForest (back 0 is format 517) | L0/L1 grassySoil | 108 / x−759..1569 y−175..540 | 2 | 9 | Pig ×6, Orange Mushroom ×4 |
| 101010100 | The Tree That Grew I | Bgm01/MoonlightShadow | 15 shineWood (uses cx/cy scrolling: cx=548, cy=548) | none (objects only, L1 43 objs) | 246 / x−1770..66 y730..2086 | 3 | 20 | Slime 0210100 ×25, Red Snail ×5 |

Towns, for reference:
- 100000000 Henesys: bgm Bgm00/FloralLife, tS woodMarble, has fieldLimit=0, no mobs.
- 104000000 Lith Harbor: bgm Bgm02/AboveTheTreetops.
- 101000000 Ellinia: bgm Bgm02/WhenTheMorningComes.
- 102000000 Perion: bgm Bgm00/Nightmare.
- 103000000 Kerning: bgm Bgm01/BadGuys.

Snail 0100100 does not spawn in any of these maps.

### 4. Mobs (`out/4-mobs.txt`)

None of these mobs has `info/link`. Across Mob.wz, 405 imgs use a link, e.g. `9300106.img→9300119` and `9500328.img→8150000`. A loader must follow `info/link` to reach another mob's frames. All canvases are fmt 1+0.

| Mob | Name | info |
|---|---|---|
| 0100100 | Snail | level 1, maxHP 8, maxMP 0, speed −65, PADamage 12, PDDamage 0, MADamage 0, MDDamage 0, acc 20, eva 0, exp 3, undead 0, pushed 1, bodyAttack 1, fs 10, summonType 1, mobType 0 |
| 0100101 | Blue Snail | level 2, HP 15, MP 15, speed −50, PAD 17, acc 20, exp 4, mobType 0 (other fields as Snail) |
| 0210100 | Slime | level 6, HP 50, MP 35, speed −20, PAD 32, PDD 5, MDD 10, acc 35, eva 1, exp 10, elemAttr "L3", mobType 5 |
| 1210102 | Orange Mushroom | level 8, HP 80, MP 45, speed 0, PAD 42, MDD 10, acc 42, eva 1, exp 15, mobType 4 |
| 0120100 | Shroom | level 2, HP 20, MP 15, speed −30, PAD 17, acc 30, exp 5, mobType 4 |

Frame data. Format for each frame: `w×h origin lt rb head delay`. Frames without `delay` carry none in the WZ.
- **0100100 Snail**
  - `move` has 5 frames at 180 ms, and the stance has `zigzag=1`. Frame 0: 37×26, o(18,26), lt(−18,−26), rb(19,0), head(−13,−24).
  - `stand` has 1 frame, 37×26 o(18,26), with no delay.
  - `hit1` has 1 frame: 43×33, o(21,33), delay 600.
  - `die1` has 9 frames: 120 ms each, except frame 8 at 300 ms with `a0=255 a1=0`.
- **0100101 Blue Snail**
  - `move` has 4 frames at 120 ms, `zigzag=1`. Frame 0: 35×34, o(16,34), lt(−16,−34), rb(19,0), head(−4,−34).
  - `stand` has 1 frame.
  - `hit1` has 1 frame: 41×39, delay 600.
  - `die1` has 3 frames: 180, 180 and 300 ms.
- **0210100 Slime**
  - `move` has 7 frames with delays 200, 50, 150, 150, 100, 100, 300. The origin y varies (51→94) because the slime hops.
  - `stand` has 3 frames: 200, 300, 250 ms.
  - `jump` has 1 frame at 150 ms.
  - `hit1` has 1 frame at 600 ms.
  - `die1` has 4 frames: 180, 180, 180, 300 ms.
- **1210102 Orange Mushroom**
  - `move` has 3 frames: 180, 120, 180 ms.
  - `stand` has 2 frames at 180 ms.
  - `jump` has 1 frame.
  - `hit1` has 1 frame at 600 ms.
  - `die1` has 3 frames: 180, 180, 300 ms.
- **0120100 Shroom**
  - `move` has 4 frames at 180 ms.
  - `stand` has 3 frames (180, 100, 180 ms) and `zigzag=1`.
  - `hit1` has 1 frame at 600 ms.
  - `die1` has 4 frames: 120 ×3, then 300 ms.

Notes:
- `lt` and `rb` (body hitbox) are absent on die frames.
- `head` is present on every frame.

### 5. Character (`out/5-character.txt`)

**Base.wz.**
- `zmap.img` has 151 null children. Their **order is the z-order, front to back**: index 0 `mobEquipFront`, …, 8 `characterStart`, …, and the last 10 are `Ay, As, Ae, Am, Af, At, Fc, Hr, Hd, Bd`. Positions of the commonly used layers: weaponOverArm 21, armOverHair 25, hairOverHead 30, hair 34, face 42, hairShade 44, head 45, mailArm 48, arm 51, weapon 52, mailChest 66, pants 71, shoes 72, mailChestBelowPants 74, body 76, backHair 89, backBody 110. A lower index is drawn on top; this is inferred from the names (`*Front` first, `Bd`/`backBody` last) and from consistency (face 42 < head 45, arm 51 < body 76). UNVERIFIED against the client.
- `smap.img` has 147 children: the first 8 (`mobEquipFront`…`emotionOverBody`) and the last 5 are null, and the rest are strings mapping a z-layer to slot codes, e.g. `weaponWristOverGlove="Wp"`, `capeOverHead="Sr"`, `mailArmOverHair="MaGw"`, `body="Bd"`, `head="Hd"`, `face="Fc"`, `hair="H2"`, `hairOverHead="H1"`, `pants="PnSo"`.
- `StandardPDD.img` has 6 children.

**Body 00002000.img** (136,666 bytes) has `info` (islot=vslot="Bd", cash=0) plus 157 stances.
- The basic stances contain canvases:
  - walk1 / walk2: 4 frames at 180 ms
  - stand1 / stand2 / alert: 3 frames at 500 ms
  - swingO1/O2/O3, swingT1/T2/T3, swingP1/P2, shoot1, heal: 3 frames each (swing/shoot/heal 300, 150, 350 ms)
  - swingOF / swingTF / swingPF / stabTF: 4 frames
  - stabO1 / stabO2: 2 frames (350, 450 ms)
  - stabOF / stabT1 / stabT2 / shootF: 3 frames
  - shoot2: 5 frames
  - proneStab: 2 frames
  - prone / sit / dead: 1 frame with no delay
  - fly: 2 frames at 300 ms
  - jump: 1 frame at 200 ms
  - ladder / rope: 2 frames at 250 ms, `face=0`
- The skill stances (magic1–5, savage, alert2–6, …) are **references, not images**. For example, `magic1` = `[{action:"shootF",frame:1,delay:-900},{action:"swingO3",frame:1,delay:200},{action:"swingO3",frame:2,delay:200}]`. Negative delays appear throughout these stances. Their meaning is UNVERIFIED, but they probably mark the pre-hit portion of the animation.

**stand1/0 composition.** Frame-level fields are `face=1` and `delay=500`.
- `body`: 21×31, origin (16,31), `map{neck(−4,−32), navel(−8,−21)}`, `z="body"`, `group="skin"`.
- `arm`: 10×19, origin (5,9), `map{navel(−13,−1), hand(−1,5)}`, `z="arm"`, `group="skin"`.
- Head 00012000.img `stand1/0/head` is a UOL to `../../front/head`: 39×35, origin (19,17), `map{neck(0,15), earOverHead(15,10), earBelowHead(−17,9), brow(−4,−5)}`, z "head".
- Face `Face/00020000.img/default/face`: 26×16, origin (13,8), `map{brow(−1,−12)}`, z "face".
- Hair `Hair/00030000.img/stand1/0/{hairOverHead,hair,hairShade}` are UOLs to `default/*`. hairOverHead: 38×22, o(15,14), brow(0,0). hair: 35×20, o(14,12), brow(0,0). The hair's info `vslot` is `H1H2H3H4H5H6HfHsHb`.
- Coat 01040002 `stand1/0`: `mail` 14×14, o(11,9), navel(−8,1), z "mailChest"; `mailArm` 5×7, o(3,4), navel(−12,4), z "mailArm".

The data implies this assembly: body is placed at the character origin; arm and coat are attached by matching `navel` to the body's navel; the head matches `neck` to the body's neck; face and hair match `brow` to the head's brow. This is consistent with all values but UNVERIFIED against the client.

**Head 00012000.img** has 36 children: info, front, back, and 33 stances that mirror the body's basic stances. Its frames contain UOLs only, with no delay.

**Beginner defaults.** The authoritative list is `Etc.wz/MakeCharInfo.img` (`Info/CharMale`, `Info/CharFemale`; Premium* and OrientChar* variants also exist). Slot meanings: 0 = face, 1 = hair, 2 = hair colour, 3 = skin, 4 = coat, 5 = pants, 6 = shoes, 7 = weapon.

| Slot | Male | Female |
|---|---|---|
| 0 face | 20000, 20001, 20002 | 21000, 21001, 21002 |
| 1 hair | 30030 Buzz, 30020 Rebel, 30000 Toben | 31000 Sammy, 31040 Edgy, 31050 Connie |
| 2 hair colour | 0 Black, 7 Brown, 3 Blond, 2 Orange | same |
| 3 skin | 0 Light, 1 Tanned, 2 Dark, 3 Pale | same |
| 4 coat | 1040002, 1040006, 1040010 | 1041002, 1041006, 1041010, 1041011 |
| 5 pants | 1060002, 1060006 | 1061002, 1061008 |
| 6 shoes | 1072001, 1072005, 1072037, 1072038 | same |
| 7 weapon | 1302000 (sword), 1322005, 1312004 | same |

These all exist in Character.wz: Face/00020000.img (13,123 B), Hair/00030000.img, Coat/01040002.img (incPDD 3, price 25), Pants/01060002.img, Shoes/01072001.img and Weapon/01302000.img (incPAD 17, attackSpeed 4, afterImage swordOL, sfx swordL).

### 6. Skills (`out/6-skills.txt`)

**000.img/skill/0001000 Three Snails** has children `icon`, `iconMouseOver` and `iconDisabled` (each 32×32, origin (0,32)) and `level/1..3`. There is **no top-level ball, hit or effect**.

| Level | hs | mpCon | fixdamage | ball | hit |
|---|---|---|---|---|---|
| 1 | h1 | 3 | 10 | 3 frames: 32×35 o(17,17), 33×31 o(19,13), 34×30 o(19,16), all 90 ms | `hit/0` 6 frames (76×79 … 73×62), 90 ms each |
| 2 | h2 | 5 | 25 | same sizes and origins | same |
| 3 | h3 | 7 | 40 | same sizes and origins, different pixels | same |

So **the snail-shell projectile lives at `Skill.wz/000.img/skill/0001000/level/N/ball`**. Decoding shows L1 is a green shell and L3 a red shell (`out/threesnails-L*-ball0.png`). The shell items also exist as Item.wz/Etc/0400.img: `04000019` Snail Shell, `04000000` Blue Snail Shell and `04000016` Red Snail Shell, each with info/icon 26×27 and iconRaw 25×25. HeavenClient (AGPL-3.0) maps the levels to these item ids (`Gameplay/Combat/Skill.cpp` ~L222-233) but looks them up under `Item/Consume`, where they do not exist in v83. The WZ `level/N/ball` node is the better source.

Sound for Three Snails: `Sound.wz/Skill.img/0001000/Use` is a UOL to `../1001004/Use`. There is no Hit sound.

| Skill | Children | ball | hit | effect | affected | Other |
|---|---|---|---|---|---|---|
| 2001002 Magic Guard | icon×3, action[0]="alert2", level 1..20 (time 111→600, mpCon 6→12, x 11→80), effect | – | – | 12 frames at 100 ms (last frame z=1, a0=255→a1=0) | – | |
| 2001003 Magic Armor | icon×3, action, level 1..20 (time 54→400, mpCon 8→16, pdd 2→40), req{2001002} | – | – | – | – | |
| 2001004 Energy Bolt | icon×3, level 1..20 (mpCon 6→14, mad 20→55, mastery 1→10), ball, hit | 4 frames, 33×33 o(16,16), 80 ms | hit/0 and hit/1, each a set of 3 frames | – | – | no `action` node |
| 2001005 Magic Claw | icon×3, level 1..20 (mpCon 10→20, mad 11→40, attackCount 2), req{2001004}, hit, effect, CharLevel{10,15,20,25}/{hit,effect} | – | hit/0 5 frames (120, 90, 120, 90, 150 ms) | 4 frames at 80 ms | – | visuals scale with character level |
| 2101004 Fire Arrow | icon×3, elemAttr "f", action[0]="shoot1", level 1..30 (mpCon 14→28, mad 33→120), effect, ball, hit | 3 frames, 84×20 o(42,10), 30 ms | hit/0 5 frames | 10 frames at 100 ms | – | |
| 2101005 Poison Breath | icon×3, elemAttr "s", action[0]="swingO3", level 1..30 (mad 12→70, prop 31→60, time 4→40), effect, ball, hit, mob | 2 frames, 36×26 / 41×26 o(18,13), no delay | hit/0 6 frames | 5 frames (100…120 ms) | – | `mob` is the poisoned-mob overlay: 5 frames at 70 ms, pos=2, repeat=1 |

No skill checked here has an `affected` node. Hit animations are nested one level deeper, at `hit/<variant>/<frame>`.

### 7. Effect.wz (`out/7-effect.txt`)

BasicEff.img children:
- AranGetSkill, Assaulter, Buff(8), Catch, Combo, ComboCommand, CoolHit, EmptyCanvas, Enchant, Event1, FindPrize, Flame, Flying, Flying1, GetParao, IncEXP
- ItemLevelUp, ItemMake, ItemSkill, **JobChanged**(13 frames + z), **LevelUp**(21 frames), MonsterBook, **NoBlue0/1, NoCri0/1, NoRed0/1, NoViolet0/1**
- QuestAlert, QuestClear(11), SkillBook, SoulRush, Summoned, Teleport(4), TombUpgrade, Transform, TransformOnLadder, VerticalJump, Wedding

Damage digits (all fmt 1+0; origin is roughly bottom-centre):

| Set | Digit size range | Example origins | Extra |
|---|---|---|---|
| NoRed0 (small digits) | 22–31 × 32–33 | "0" 31×33 o(15,32); "1" 22×32 o(11,31) | `Miss` 98×38 o(49,37) |
| NoRed1 (large first digit) | 25–37 × 37–39 | "0" 37×38 o(18,37) | |
| NoBlue0 / NoBlue1 | identical sizes and origins to NoRed0 / NoRed1 | | |
| NoViolet0 / NoViolet1 | identical to NoRed0 / NoRed1 | | NoViolet0 has `Miss` |
| NoCri0 | 25–37 × 38–39 | "0" 37×38 o(18,37) | |
| NoCri1 | 29–43 × 44–48 | "0" 43×48 o(21,45) | `effect` 62×57 o(41,70) (crit splash) |

Which colour belongs to which damage source (player-dealt vs taken) is UNVERIFIED from data alone.

- **LevelUp**: 21 frames with no `delay` child, so the client default applies (the value is UNVERIFIED). Frame sizes run from 86×70 o(43,70) up to 296×329, ending at 178×50.
- **JobChanged**: 13 frames at 100 ms each, 104×108 → 166×311, plus `z=-1`.
- **QuestClear**: 11 frames at 100 ms, z=1.
- **Teleport**: 4 frames at 80 ms.
  Rechecked directly in original v83 `Effect.wz/BasicEff.img/Teleport` for #60 (2026-10-15, tier A),
  using `node wz.js dump Effect.wz BasicEff.img/Teleport 3`: frames 0-3 are 62x172, 45x143,
  36x116 and 33x57, with origins (34,122), (25,105), (20,94), (17,61); every delay is 80 ms.
  `node wz.js ls Skill.wz 210.img/skill/2101002` lists `icon`, `iconMouseOver`, `iconDisabled`
  and `level` only; there is no skill-local effect node. The shared BasicEff path is exported by the manifest.
- The matching sounds are `Sound.wz/Game.img/LevelUp` (MP3 22050 Hz mono, 3586 ms) and `Game.img/JobChanged`.

### 8. UI.wz and Sound.wz (`out/8-ui-sound.txt`)

**StatusBar.img** (v83 bottom HUD):
- `base/backgrnd` 800×71, `backgrnd2` 570×71, `quickSlot` 151×80, `chat` 566×5, `chatTarget`, `box`, `iconRed`, `iconBlue`, `iconMemo`.
- `gauge/{bar 340×31, graduation 340×31, gray 1×16, tempExp 1×16, hpFlash[0..4], mpFlash[0..4]}`. Flash frames are 109×18 at 130 ms; frames 2–4 are UOLs.
- `number/{0-9 5×7, Lbracket, Rbracket, slash, percent}`.
- Buttons, each with `normal`, `pressed`, `disabled` and `mouseOver` states: BtShop, BtMenu (54×34), BtNPT, BtShort, BtWhisper, BtClaim, EquipKey, InvenKey, StatKey, SkillKey, KeySet, QuickSlot, QuickSlotD.
- Also `key[8]` and `FontMemo`.

**Basic.img**:
- **`LevelNo/{0-9, blank}`**: 11×13 level digits.
- `Notice` / `YesNo` backgrnd 264×132; Notice2–5; YesNo2/3.
- Buttons: BtOK (65×24, plus keyFocused), BtCancel, BtYes, BtNo, BtClose, BtMin, BtMax.
- Tab1–7, ComboBox1–5, VScr/HScr scrollbars, `Cursor/{0..}` (animated cursors), CheckBox, Slider, ItemNo, ShowLevel.

**Tab backgrounds (#219).** The window tab canvases hold only the *text*: `UIWindow.img/{Item,PersonalShop,Trunk,Quest,
UserList,Skill,Shop/TabSell,Shop/TabBuy}/Tab/{enabled,disabled}/<i>` are pure-white glyphs (5-12 px tall, origin 0,0;
`enabled` and `disabled` differ only in glyph width / shadow), so on their own they float on the window's light grey
strip. The tab shapes are a separate skin in **`Basic.img/Tab`, `Tab2`-`Tab7`**, the client's tab control (nine canvases
per set): `left0/1` and `right0/1` the two row ends (6 px), `fill0/1` a 1 px body column to repeat, `middle0/1/2` the 12 px
join between two tabs (divider at column 5). State 0 is a hidden tab (grey), state 1 the shown tab (pink with a black outline
and white highlight); `middle0` joins hidden | hidden, `middle1` shown | hidden, `middle2` hidden | shown. Sets: `Tab5` 21 rows
(19 + 2 red base rows, grey/pink) and `Tab3` 21 rows (same shapes, grey base): the strips on the red rule of Item, Skill and
Shop (rows 23-41 at x 4-170 in Item/Skill `backgrnd`, the red rule at rows 42-44; Shop's 25-row strip at rows 91-115, red 116-118);
`Tab2` 19 rows (grey/pink with dark dividers); `Tab`, `Tab4`, `Tab6` and `Tab7` are other skins (24, 29, 20-21 and 20 rows; not used here). `UIWindow.img/Item/New/Tab0` / `Tab1` (five 34x18 frames each) are not tab backgrounds: they are the grey / pink
"new item" flash overlays drawn over a tab (HeavenClient draws them at the tab's glyph position minus (2, 1..3)); their width
is the best evidence that the Item tabs are one equal width (34 px incl. a 1 px shared outline). No canvas under Item/ Equip/
Skill/Shop carries tab positions (all origins are 0,0 in the cache); the tab cut positions are tier C. Third-party clients
(HeavenClient / MortalClient, read for facts only) draw only the glyph TwoSpriteButtons, hence the usual "floating text".

**UIWindow.img**:
- `Skill/{backgrnd 175×289, skill0/skill1 141×35, BtSpUp, Tab, CoolTime[0..15] 32×32}`.
- `MobGage/{backgrnd…, Mob/<id> 25×25 boss icons}`.
- `Notice/{0-4 286×146, btOK}`, `FloatNotice`, `UtilDlgEx` (NPC dialog), `Stat`, `Item`, `Equip`, `Quest`, `MiniMap`, `KeyConfig`, `GameMenu`, `EnergyBar` and about 120 more windows.

**Sound.wz** has 44 imgs: Bgm00–Bgm21, BgmEvent, BgmGL, BgmJp, BgmMY, BgmSG, BgmUI, Game(27), UI(31), Field, Skill(383), Item(216), Mob(1256), Pet, Reactor, Summon, Weapon, Object, MiniGame, Jukebox, CashEffect, ConsumeEffect and Radio (empty).

Stage BGM: `Sound.wz/Bgm01.img/CavaBien`.
- Sound_DX8 fields: dataLen 1,280,000, durationMs 128,000, header 82 bytes.
- The 51-byte GUID header is `0283eb36e44f52ce119f530020af0ba7708beb36…0055595a`.
- WAVEFORMATEX (wfLen 30, not encrypted): wFormatTag 0x55 (MP3), 2 channels, 22050 Hz, avgBytes 10000, blockAlign 1, cbSize 12. The MPEGLAYER3 extension is wID 1, flags 2, blockSize 522, framesPerBlock 1, codecDelay 0.
- The data starts with `fff29040`: MPEG-2 Layer III, bitrate index 9 (80 kbps), 22050 Hz, joint stereo, and no ID3 tag. 10000 B/s × 128 s = 1,280,000 bytes, which matches dataLen.

Encodings across all 3,956 sounds in Sound.wz:

| Encoding | Count |
|---|---|
| MP3 22050 Hz mono | 3642 |
| MP3 22050 Hz stereo | 118 |
| MP3 44100 Hz stereo | 78 |
| MP3 44100 Hz mono | 74 |
| MP3 8000 Hz mono | 3 |
| PCM 16-bit 44100 Hz mono (wfLen 18, 70-byte header; Pet.img 5000048/5000049/5000053) | 40 |
| Malformed header (`BgmGL.img/Amorianchallenge`, wfLen 73, tag 0x3344) | 1 |

Older BGMs (Bgm00–08) are mostly 22050 Hz at 80 kbps, with exceptions such as `Bgm07/FunnyTimeMaker` at 44100 Hz and 192 kbps. Newer ones (Bgm09/10/14/15/21, …) are mostly 44100 Hz at 128–256 kbps.

Mob sounds use the path `Sound.wz/Mob.img/<7-digit id>/{Damage,Die}`. For example, 0100100 has Damage 226 ms and Die 384 ms.

### 9. String.wz (`out/9-strings.txt`)

Key formats differ between imgs:
- **Mob.img** keys are integers without leading zeros: `Mob.img/100100` exists and `0100100` does not.
- **Skill.img** keys are 7-digit, zero-padded: `Skill.img/0001000`. Job books are keyed `000`, `200`, `210` and hold `bookName`.
- **Map.img** is grouped by region: maple, victoria, ossyria, elin, weddingGL, MasteriaGL, HalloweenGL, jp, etc, singapore, event, Episode1GL.

Mobs:

| Id | Name |
|---|---|
| 100100 | Snail |
| 100101 | Blue Snail |
| 210100 | Slime |
| 1210102 | Orange Mushroom |
| 120100 | Shroom |
| 130101 | Red Snail |
| 1210100 | Pig |
| 1210101 | Ribbon Pig |
| 1110100 | Green Mushroom |

Skills:

| Id | Name | Notes |
|---|---|---|
| 0001000 | Three Snails | h1 "MP -3; Damage 10", h2 "MP -5; Damage 25", h3 "MP -7; Damage 40" |
| 2001002 | Magic Guard | |
| 2001003 | Magic Armor | |
| 2001004 | Energy Bolt | |
| 2001005 | Magic Claw | |
| 2101004 | Fire Arrow | |
| 2101005 | Poison Breath | |

Job books: 000 "Beginner's Basics", 200 "Intro. to Magic", 210 "Fire & Poison Basics".

Maps (all in region `victoria`, streetName "Victoria Road"):

| Id | mapName |
|---|---|
| 104040000 | Henesys Hunting Ground I |
| 104040001 | Henesys Hunting Ground II |
| 100010000 | The Hill East of Henesys |
| 100020000 | The Rain-Forest East of Henesys |
| 101010100 | The Tree That Grew I |
| 100000000 | Henesys |
| 104000000 | Lith Harbor |

### 10. Performance (`out/10-perf.txt`, `out/scan-info.txt`, `out/census.txt`)

| Operation | Time |
|---|---|
| `new WzFile(Map.wz)` + root dir | 0.3–0.4 ms |
| Walk Map/Map1 dirs + parse 104040000.img (55,569 B → 5,197 nodes) | 4.0 ms (1st), 10.3 ms (2nd, new instance) |
| Parse all 5261 map imgs (skeleton only, canvases not decoded) | 1,557 ms |
| Decode `Back/grassySoil.img/back/2` (2493×340 fmt1, 364,999 B zlib → 1,695,240 B) to RGBA | 12.2 ms / 8.2 ms |
| Full census parse: Character.wz (7201 imgs, 3.43M nodes) | 3.4 s |
| Full census parse: Map.wz (7.9M nodes) | 2.7 s |
| Full census parse: Mob.wz | 0.96 s |

Caveats: these numbers are single-threaded JS with a warm OS cache (the files had just been read), and they are not a GDScript or Godot measurement. The parser reads the whole img blob in one `readSync` and decodes canvases lazily.

## Format refresher: verification results

| Claim | Result |
|---|---|
| Header "PKG1", u64 size, u32 dataStart, copyright, u16 encVer at dataStart | ✔. Correction: u64 = file length − dataStart (data region size). dataStart = 60 for every file. |
| hash/encVer formula, v83 → 172 | ✔ (only candidate in 1..399) |
| Compressed int | ✔. Compressed long is never used in v83 (no type 20), so it is untested. |
| Dir types 1/2/3/4 + size, checksum, offset | 2/3/4 ✔. Type 1 never occurs (skipped count 0 in every file), so its layout is UNVERIFIED. Base.wz contains 15 dir stubs of size 0. |
| Offset decryption formula | ✔ (all offsets land in range, and every img starts with 0x73 "Property") |
| String decryption (unicode/ascii masks, keystream) | ✔ with GMS IV `4D23C72B`. KMS IV and zero key fail. |
| Img header + property types | ✔ for 0, 2, 3, 4 (0x80 + f32), 5, 8, 9. 11 is seen once. 19 and 20 are never seen. |
| Extended types | ✔ all six. UOL parses as `u8` + marker byte + string (inline or at an offset). The parser accepts both 0x00/0x01 and 0x73/0x1B markers; which variant actually occurs was not recorded. |
| Canvas layout | ✔. The leading u8, the i32 after format2 and the header byte are always 0. |
| Canvas data zlib or block-encrypted | ✔. Both occur. Encrypted data appears only in Mob.wz (9,669 canvases, 319 imgs listed in List.wz). |
| Pixel format = format + format2 | ✔. 517 is stored as fmt 513 + fmt2 4. No DXT formats in v83. |
| Vector | ✔ |
| Sound_DX8 (82-byte media header) | ✔ for MP3. PCM uses an 18-byte WAVEFORMATEX, giving a 70-byte header. One entry has a malformed 73-byte header. WAVEFORMATEX is never encrypted in v83. |
| List.wz "not a normal WZ" | ✔. It is i32-length UTF-16 strings XORed with the keystream (no mask) and lists encrypted-canvas mob imgs. |

## Licensing notes

- **Explorer code** (`wz.js`, `tasks.js`, `census.js`, `scan-info.js`, `check-odd.js`) was written from scratch for this task using the refresher spec plus empirical checks. No third-party source was copied, and it uses only Node built-ins.
- **Cosmic** (P0nk/Cosmic) is AGPL-3.0, as stated in the task. It was not used here.
- **rea** (morluto/rea) is MIT, as stated in the task. It was not needed: `MapleStory.exe` is packed (sections `ytkjcptk`, `albasygk`, `jbhyjsdw`, and `.text` has raw size 3,002,368 against virtual size 8,355,840), and none of the probe strings appear in plaintext.
- **HeavenClient** (`ryantpayton/MapleStory-Client`) is AGPL-3.0, verified with `gh api repos/ryantpayton/MapleStory-Client` → `AGPL-3.0`. It was read only for the Three Snails bullet-id fact; no code was copied.
- **The WZ assets and the extracted PNG/MP3 files in `out/` are Nexon IP.** They were extracted for research only. Shipping or distributing them is a legal question outside this topic.

## Unknowns and risks

- Dir entry type 1, property types 19 and 20, and compressed long never occur in v83, so the parser's handling of them is untested. This is harmless for v83.
- The meaning of negative `delay` values in body skill stances and the default frame delay for frames without `delay` (e.g. LevelUp, mob `stand` with a single frame) are UNVERIFIED. They need client knowledge from another investigation.
- The back `type` semantics (0–7: tiling and scrolling) and how `rx`, `ry`, `cx` and `cy` are applied are not derivable from data. They are UNVERIFIED here.
- Which damage-digit colour set the client uses for which case (dealt, taken, crit, party) is UNVERIFIED.
- The stage maps lack VR bounds, so camera limits must come from foothold bboxes or the miniMap; for example 104040000 has footholds x −489..1749 and a miniMap of 2317×1832 centred at (530,1278).
- Format 517 appears in the midForest back used by 100020000, so the Godot importer must support it, along with formats 1, 2 and 513. It never needs DXT for v83.
- Mob.wz block-encrypted canvases include stage mobs (Slime, Pig). The importer must implement the XOR-block path using the GMS keystream.
- 405 mobs use `info/link`, so the importer must resolve links. Frames and stances can also be UOLs (`../../front/head`, `0`), so UOL resolution is mandatory.
- Performance numbers were measured with a warm OS cache on Node, not in Godot. Cold-disk timings are UNVERIFIED.
- `BgmGL.img/Amorianchallenge` has a malformed sound header. It is not needed for our stages.
