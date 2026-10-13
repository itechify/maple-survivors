# Research

Phase 0 investigation, 2026-10-13. Five parallel investigations produced the full reports in `docs/research/`
(evidence with file:line, URLs and command output). This file is the summary and the decision trail.

| Report | Question |
|---|---|
| [`research/cosmic-data.md`](research/cosmic-data.md) | What the Cosmic server offers as reference data and formulas |
| [`research/prior-art.md`](research/prior-art.md) | Algorithms in open-source v83 client reimplementations and WZ tools, and their licences |
| [`research/wz-inventory.md`](research/wz-inventory.md) | What the vanilla v83 WZ files contain (from-scratch read-only parser) |
| [`research/rea-client.md`](research/rea-client.md) | Can REA recover behaviour from the v83 client binary? |
| [`research/godot-probe.md`](research/godot-probe.md) | Measured feasibility of Godot 4.7.2 + GDScript as the runtime |

## 1. Source repositories

| Repo | What it really is | Licence |
|---|---|---|
| [P0nk/Cosmic-client](https://github.com/P0nk/Cosmic-client) | Git LFS store of three things: the original `MapleGlobal-v83-setup.exe` (1.76 GB, Nexon Game Manager stub + 2 CAB volumes), `HeavenMS-localhost-WINDOW.exe` (modified client), and `cosmic-wz/` (HeavenMS-edited WZ). No source code. | none stated; contents are Nexon's |
| [P0nk/Cosmic](https://github.com/P0nk/Cosmic) | Java 21 server emulator: MySQL 8, login server TCP 8484, channel servers TCP 7575+, GraalVM JS scripts, `wz/` XML export with no pixels or audio (555,619 canvases, 0 bitmaps) | AGPL-3.0 ("only version 3" OdinMS headers) |
| [morluto/rea](https://github.com/morluto/rea) | MCP server + CLI (`rea-agents` 6.4.0) for reverse engineering; native analysis needs Hopper (macOS/Linux), Ghidra (+JDK 21) or IDA | MIT |

Observations from the brief, validated:

- *Cosmic-client provides binaries and assets, not client source*: **true**.
- *Cosmic is Java and needs MySQL and networking*: **true** (`cosmic-data.md` §1).
- *The server XML has gameplay data but not sprites*: **true**, and it is HeavenMS-edited with at least one wrong float
  (`Physics.img` `flyJumpDec` 35.0 vs 0.35 in the original).
- *The original WZ files contain the art/animation/sound*: **true**; all 16 PKG1 archives parse; every needed asset
  class is present (`wz-inventory.md`).
- *Adapting the network-driven client is harder than a new runtime*: **true, and stronger than expected**: the
  original exe is protected (below), so it cannot even be studied statically.

## 2. Getting the original v83 assets

`MapleGlobal-v83-setup.exe` was extracted without executing it: 7-Zip identifies a PE stub (`NGMSetup.exe`, Nexon
Game Manager 1.0.1.9928) with a 1.76 GB overlay; the overlay holds an `NGM` manifest (`"MapleStory_1.cab",
"-1724043038","1048576000"` / `"MapleStory_2.cab","1130405477","711654917"`) followed by a two-volume MS CAB set that
7-Zip extracts: 51 files dated 2010-02-17/21 including every `.wz` and `MapleStory.exe` (`docs/ASSET_PIPELINE.md` §1).

## 3. Reverse engineering findings (REA)

- `MapleStory.exe` (v83, 4,286,088 B, SHA-256 `ed5a6994…2848`, linked 2010-02-17) is **packed/protected**: random
  section names `ytkjcptk`, `albasygk` (entry point), `jbhyjsdw`; first section raw 3.0 MB vs virtual 8.4 MB,
  entropy 7.98; a single import `kernel32!IsValidCodePage`; zero plaintext strings for `Physics`, `walkForce`,
  `CVecCtrl`, `.img`. Consistent with Themida/WinLicense 2.x (vendor attribution unverified).
- REA on this Windows host: Ghidra not configured (no Java), Hopper unsupported on win32, IDA absent; REA's
  provider-neutral tools confirmed a non-managed PE32 x86 and refused the resource directory as not file-backed (a
  packing symptom).
- **Conclusion:** without unpacking (circumvention, out of scope; also excluded by REA's DISCLAIMER) REA cannot recover
  behaviour from this client. Installing Ghidra + JDK would only show the protector stub.
- The modified client `HeavenMS-localhost-WINDOW.exe` was detected by Microsoft Defender as **Trojan:MSIL/Cryptor!rfn**
  (severity 5) while Git LFS downloaded it, and removed. A surviving LFS object was deleted from the scratch clone; it
  was never executed or analysed. **Owner decision (open):** whether a static, non-executing analysis of that unpacked
  build is acceptable. It is not needed for Phase 1.
- What replaces RE: physics constants are data (`Map.wz/Physics.img`, verified), animation timing/origins/hitboxes are
  data, and the integration rules come from documented reimplementations with provenance tiers (`GAME_DESIGN.md` §11).

## 4. What the data gives us (verified in v83 files)

- Physics.img: walkForce 140000, walkSpeed 125, walkDrag 80000, slipForce 60000, slipSpeed 120, floatDrag1 100000,
  floatDrag2 10000, floatCoefficient 0.01, swimForce 120000, swimSpeed 140, flyForce 120000, flySpeed 200,
  gravityAcc 2000, fallSpeed 670, jumpSpeed 555, maxFriction 2, minFriction 0.05, swimSpeedDec 0.9, flyJumpDec 0.35.
- Henesys Hunting Ground I (104040000): bgm `Bgm01/CavaBien`, 5 `grassySoil` backgrounds (types 3, 4, 0, 0, 1 with
  rx/ry -5..-15), tileset `grassySoil` on layer 1 (288 tiles), 135 objects, 181 footholds (bbox x -489..1749,
  y -1105..480), 8 ladders/ropes, 18 portals, **no VR bounds** (miniMap 2317x1832 centred at 530,1278 is the fallback).
- Mobs: Snail 0100100 (Lv1, HP 8, speed -65, EXP 3), Blue Snail 0100101, Red Snail 0130101, Shroom 0120100, Slime
  0210100 (jump), Pig 1210100 (jump), Orange Mushroom 1210102 (Lv8, HP 80, EXP 15, jump), Green Mushroom 1110100; all
  with `stand/move/hit1/die1` and per-frame `origin`, `lt/rb`, `head`, `delay`, and die fades `a0=255 a1=0`.
- Character: body 00002000 (157 stances; skill stances reference basic ones with negative delays), head 00012000,
  `Base.wz/zmap.img` (151 layers front-to-back), `smap.img`; MakeCharInfo default looks; anchors navel/neck/hand/brow.
- Skills: Three Snails keeps a per-level shell projectile at `Skill.wz/000.img/skill/0001000/level/N/ball` (green,
  blue, red) and `fixdamage` 10/25/40; Energy Bolt/Fire Arrow/Poison Breath have `ball`; Magic Claw is instant with
  `CharLevel` visuals. No `ball` has a speed: projectile speed is a design value.
- Effects/UI/Sound: BasicEff digit sets NoRed/NoCri/NoBlue/NoViolet (0 = small, 1 = large), LevelUp (21 frames),
  JobChanged (13 frames), Tomb.img; UI StatusBar.img (800x71), Basic.img LevelNo; BGM MP3 (CavaBien MPEG-2 L3 22.05 kHz).

## 5. Engine probe (measured on the dev PC: Ryzen 7 7800X3D, RTX 4070 SUPER)

- Full per-mob GDScript sim (chase, gravity, foothold lookup, spatial hash, 200 projectiles, 100 damage numbers):
  ~2 µs/mob/tick; 1000 mobs = 2.5-3.3 ms/frame; 60 FPS breaks between 4000 and 8000 mobs.
- Render-only: Sprite2D breaks at 16k-32k, MultiMesh/RenderingServer hold 32k.
- `PackedByteArray.decompress(DEFLATE)` accepts WZ's zlib streams at native speed, but per-pixel conversion in
  GDScript is 10-40x slower than native -> WZ decoding goes to a Rust importer.
- Runtime PNG and MP3 loading from outside `res://` works in exported release builds; a BGM carved from v83 Sound.wz
  plays through `AudioStreamMP3`.
- 800x600 with `stretch/mode=viewport` + `scale_mode=integer` + nearest filtering: 0 blurred blocks in a desktop
  capture of the real window.

## 6. Open unknowns (implemented as labelled, tunable constants)

| Unknown | Current choice | Tier |
|---|---|---|
| Client physics timestep / integrator | 60 Hz ticks, 2 player sub-steps, NoLifeStory-style model | B/C |
| Mob speed-stat conversion | (speed+100) × 0.625 px/s | C |
| Mob hit stun, push, death fade, regen fade | 0.24 s, 12 px, WZ `a0/a1`, 0.3 s | C |
| Projectile speeds and ranges | per skill in `skills.json` | C |
| Climb speed, ladder grab range | 100 px/s, 10 px | C |
| Camera smoothing and vertical anchor | exponential follow, player at 58% height | C |
| Damage formulas (touch, magic, defence) | `GAME_DESIGN.md` §6 | C |
| Which digit colour is "damage taken" | NoViolet (has a Miss glyph; HeavenClient agrees) | C |
| Default frame delay when `delay` is missing | 100 ms | C |
| Negative delays in skill stances | treated as absolute value for timing | C |
| Owner decision: analyse the Defender-flagged modified client? | not done | – |

## 7. Licensing summary

| Source | Licence | Use in this project |
|---|---|---|
| Original v83 WZ / exe | Nexon proprietary | Player-supplied, read locally, never committed or shipped |
| Cosmic (server, XML, scripts) | AGPL-3.0 | Facts only (EXP table values, job thresholds); no code |
| HeavenClient, JourneyClient, MortalClient, NoLifeStory | AGPL-3.0 | Algorithm descriptions and constants only, labelled by tier |
| Harepacker-resurrected / MapleLib | MPL-2.0 / GPL-3.0 | Facts only |
| WzComparerR2, MapleNecrocer, wz-reader-rs | MIT | Could be ported with attribution; our importer is written from the verified format spec |
| Godot 4.7.2 | MIT (+ third-party notices) | Engine |
| REA | MIT | Investigation tool only |
