# Prior art: open-source MapleStory client reimplementations and WZ tooling, mined for the runtime algorithms to reproduce

Research date: 2026-10-13. Clones live in `C:\Users\itech\Coding\maple-survivors-refs\research\prior-art\<owner>_<repo>` (shallow, SHAs listed in the licensing table). Every fact marked **[A]** was read straight from the original GMS v83 WZ files with my scratch tool `research\prior-art\_scratch\wzdump.mjs`. It is a read-only PKG1 reader written from scratch for this task, with no copied code. The command is `node wzdump.mjs <file.wz> [img/path] [depth]`. Its saved outputs (`physics.txt`, `zmap.txt`, `smap.txt`, `basiceff.txt`, `statusbar.txt`, `skill200.txt`, `skill210.txt`, `body2000.txt`, `head12000.txt`, `face20000.txt`, `makecharinfo.txt`, `henesys.txt`) are in the same folder.

**Provenance tiers, used in every table:**
- **A**: verified in the original v83 data via wzdump.
- **B**: comes from someone's reverse engineering of an official client binary (usually GMS v95, which shipped with debug symbols) or reads like decompiled logic. The source code is cited, but I have not confirmed it against the v83 executable.
- **C**: a reimplementation's own guess or tuning. These are not facts about MapleStory.

---

## Summary

- **Data-driven physics is real, and the actual v83 values are now verified [A].** Map.wz/Physics.img contains walkForce 140000, walkSpeed 125, walkDrag 80000, slipForce 60000, slipSpeed 120, floatDrag1 100000, floatDrag2 10000, floatCoefficient 0.01, swimForce 120000, swimSpeed 140, flyForce 120000, flySpeed 200, gravityAcc 2000, fallSpeed 670, jumpSpeed 555, maxFriction 2, minFriction 0.05, swimSpeedDec 0.9 and flyJumpDec 0.35. Units are px, px/s and px/s² with an implied mass of 100. **A player with 100% speed walks at 125 px/s.** A 100% jump gives a 555 px/s take-off and an apex of about 77 px (555²/(2·2000)).
- **NoLifeStory's `physics.cpp` (AGPL-3.0) is the closest open model of the client's CVecCtrl.** It runs fixed 10 ms substeps, uses all of the Physics.img constants plus "shoe" attributes, and handles slope slip, near-zero air control, a 162.5 px/s landing clamp and down-jump at 0.35355·jumpSpeed. HeavenClient, JourneyClient and MapleNecrocer use hand-tuned per-tick constants instead (tier C).
- **The prior-art reference data is unreliable in three places.** The Cosmic/HeavenMS `Physics.img.xml` has `flyJumpDec=35.0`, but the original is 0.35. Harepacker's `PhysicsConstants.cs` defaults (walkSpeed 1250, jumpSpeed 1555, walkForce 999999) do not match v83. HeavenClient/JourneyClient load `StatusBar2.img` and `StatusBar3.img`, but v83 UI.wz only has `StatusBar.img` [A].
- **Background parallax and scrolling are triangulated.** Screen position is `x + rx·camCenterX/100 + const` (rx=0 pins the layer to the screen, rx=-100 pins it to the world). Types 4–7 auto-scroll at **rx·5 px/s** (three independent sources agree; HeavenClient's ≈7.8 px/s is the outlier). Tiling follows `type`: 1=H, 2=V, 3=both, 4=H+scrollH, 5=V+scrollV, 6=both+scrollH, 7=both+scrollV.
- **Map draw order (WzComparerR2 MapRender, MIT):** non-front backs (by index) → layers 0..7, each drawn as [objs sorted by (obj `z`, index)] → reactors → [tiles sorted by (tile-canvas `z`, index)] → life on footholds of that layer. After the layers come portals/ladders, then front backs (`front=1`), then effects. `zM` is ignored for sorting.
- **Character layering is data-driven.** Base.wz/zmap.img lists every layer name **front-to-back** [A]: 151 entries (`tail -n +5 zmap.txt | wc -l`), from `mobEquipFront … characterStart … body … backBody … characterEnd …` plus the 2-letter slot codes. smap.img maps most z-names to the equip slot codes they occupy [A]. It has 147 keys, not identical to zmap: it lacks saddleMid, backSaddleFront and backPantsOverShoesBelowMailChest, and orders mailChest differently. WzComparerR2 sorts parts by their zmap index, and anchors each part by its `map` vectors (navel/neck/hand/brow/handMove).
- **Damage numbers [A + B]:** BasicEff has NoRed0/1, NoBlue0/1, NoCri0/1, NoViolet0/1. The large set ("1") is used for the first digit and the small set ("0") for the rest. NoCri1/effect (62×57, origin 41,70) is the critical burst. v95 RE says: hold 400 ms, then fade plus a 30 px rise over 600 ms; digit advance overlap is `3·(originX−width)/5`.
- **Projectile speed, mob speed→px/s, hit-stun, death fade, climb speed and the per-mob HP bar are NOT data-driven in v83 and have no trustworthy open source.** v83 `ball` nodes contain no `speed` [A], and every implementation guesses differently. These are listed under Unknowns.
- **WZ format [A + code]:** PKG1 header; v83 data starts at 60; the encrypted version is 0xAC, giving version 83 and hash 1876. AES-256-ECB keystream from IV 4D 23 C7 2B. Offset key 0x581C3F6D. Canvas formats 1/2/513/517/1026/2050. v83 uses `UOL` links but no `_inlink`/`_outlink` in the images I sampled.
- **License reality:** only WzComparerR2, MapleNecrocer, wz-reader-rs and @tybys/wz are MIT, so we may port their code with attribution. All the "game-logic" clients are AGPL-3.0 (HeavenClient, JourneyClient, NoLifeStory, MortalClient) or MPL-2.0/GPL-3.0 (Harepacker/MapleLib). From those we take algorithms and constants only and re-implement them from prose.

---

## Candidate projects surveyed

| Project | Lang | License | Last push | Relevance |
|---|---|---|---|---|
| ryantpayton/MapleStory-Client ("HeavenClient"; the old `ryantpayton/HeavenClient` URL redirects here) | C++ | AGPL-3.0 | 2026-02-25 | Full v83 client: physics, footholds, backgrounds, CharLook, mobs, damage numbers (tier C constants) |
| SYJourney/JourneyClient | C++ | AGPL-3.0 | 2022 (code 2016) | Ancestor of HeavenClient; same algorithms |
| HypatiaOfAlexandria/MortalClient | C++ | AGPL-3.0 | 2019 | Fork of HeavenClient |
| NoLifeDev/NoLifeStory | C++ | AGPL-3.0 | 2017 | **Best physics model** (Physics.img-based), backgrounds, camera |
| ryantpayton/NoLifeWzToNx | C++ | AGPL headers in `NoLifeWzToNx.cpp`/`Keys.cpp`; no LICENSE file | 2026-03 | WZ→NX converter |
| lastbattle/Harepacker-resurrected (HaCreator + MapSimulator) | C# | MPL-2.0 (repo); MapleLib submodule is GPL-3.0 | 2026-10-06 | MonoGame map simulator with v95-binary "parity" work; damage-number RE doc; v95 StringPool dump |
| lastbattle/MapleLib | C# | GPL-3.0 | 2026-10 | WZ library (`WzAESConstant.cs:36` offset constant) |
| Kagamia/WzComparerR2 (+ MapRender, Avatar plugins) | C# | MIT | 2026-10-04 | **Best MIT reference** for WZ decoding, map rendering order/backgrounds and avatar compositing |
| Elem8100/MapleNecrocer | C# | MIT | 2026-04 | MIT client emulator (map/char/mob); tier C physics |
| Elem8100/MapleStory-GM-Client | Pascal | MPL-2.0 | 2023 | Older predecessor of MapleNecrocer |
| spd789562/wz-reader-rs (crate `wz_reader` 0.0.26, 15k downloads) | Rust | MIT | 2026-09 | WZ reader port of WzComparerR2.WzLib/MapleLib |
| davipk/wzlib-rs | Rust→WASM | MIT | 2026-09 | Not cloned; WZ parser |
| toyobayashi/wz (npm `@tybys/wz` 1.7.1) | TS | MIT per package.json, no LICENSE file | 2026-07 | Node/browser WZ reader |
| npm `wz-parser` 0.0.4, `libwz` 0.1.1 | JS | MIT | 2021 / 2026 | Not evaluated beyond `npm search` |
| nmnsnv/maplestory-wasm | C | AGPL-3.0 | 2026-10 | Not cloned (HeavenClient-derived per description) |
| wuzekang/maple-rs | Rust | **none** | 2025 | v83 Rust PoC; unusable (no license) |
| diamondo25/webstory | JS | **none** | 2025 | Unusable (no license) |

Evidence: `gh api repos/<r> --jq '[.full_name,.license.spdx_id,.language,.pushed_at]'` plus `gh search repos ...` (output in the session); LICENSE heads were checked per clone.

---

## 1. Physics

### 1a. Physics.img values (v83 original) [A]
Command: `node wzdump.mjs v83-original/Map.wz Physics.img`. Physics.img is at offset 162502 and is 405 bytes.

| key | v83 value | type | Cosmic XML (`cosmic-server/wz/Map.wz/Physics.img.xml`) | Harepacker `PhysicsConstants.cs:68-98` default |
|---|---|---|---|---|
| walkForce | 140000 | double | 140000 | 999999 ✗ |
| walkSpeed | 125 | double | 125 | 1250 ✗ |
| walkDrag | 80000 | double | 80000 | 10000 ✗ (then hard-overridden to 80000 at :139) |
| slipForce | 60000 | double | 60000 | 90000 ✗ |
| slipSpeed | 120 | double | 120 | 420 ✗ |
| floatDrag1 | 100000 | double | 100000 | 300000 ✗ |
| floatDrag2 | 10000 | double | 10000 | 30000 ✗ |
| floatCoefficient | 0.01 | double | "0,01" (locale comma) | 0.03 ✗ |
| swimForce | 120000 | double | 120000 | 320000 ✗ |
| swimSpeed | 140 | double | 140 | 440 ✗ |
| flyForce | 120000 | double | 120000 | 420000 ✗ |
| flySpeed | 200 | double | 200 | 600 ✗ |
| gravityAcc | 2000 | double | 2000 | 3000 ✗ (overridden to 2000 at :171) |
| fallSpeed | 670 | double | 670 | 1670 ✗ (overridden to 670 at :178) |
| jumpSpeed | 555 | double | 555 | 1555 ✗ (overridden to 555 at :185) |
| maxFriction | 2 | double | 2 | 10 ✗ |
| minFriction | 0.05 | double | "0,05" | 0.2 ✗ |
| swimSpeedDec | 0.9 | double | "0,9" | 0.1 ✗ |
| flyJumpDec | **0.35** (float 0.34999999) | float | **"35.0" ✗** | 0.15 ✗ |

Takeaways:
- The HeavenMS XML dumps are not safe for floats. They use locale commas and one value is wrong by 100×. Read the binary WZ.
- Harepacker's comment that "Speed 100 = 100 px/s" (`PhysicsConstants.cs:118-130`) is wrong for v83. The file contradicts itself: `:40` says Speed 100 → 125 px/s.

### 1b. Most faithful algorithm: NoLifeStory `src/client/physics.cpp` (AGPL-3.0, f73fb8f) [B]

**Constants (`physics.cpp:28-62`).** It hard-codes exactly the v83 Physics.img values above (flyJumpDec 0.35) plus "shoe" attributes: shoe_mass 100, walk_acc 1, walk_drag 1, walk_jump 1.0, walk_slant 0.9, walk_speed 1.0, swim_acc 1, swim_speed_h/v 1, fly_acc 0, fly_speed 0. It also hard-codes derived constants with no stated provenance: `down_jump_multiplier 0.35355339` (=1/(2√2)), `max_land_speed 162.5`, `float_multiplier 0.0008928571` (=1/1120), `swim_jump 700`.

**Timestep (`:99-101`).** `while (delta_total > laststep) { laststep += 0.01; delta = 0.01; ... }` is a fixed **10 ms** step.

**Ground walk (`:103-132`).**
- Velocity is projected onto the foothold direction: `mvr = vx·len/fx`.
- `fs = (map.info.fs or 1)/mass·Δ`, `maxf = walkSpeed·shoeWalkSpeed` (×swimSpeedDec in swim maps), `drag = clamp(shoeWalkDrag, minFriction, maxFriction)·walkDrag`.
- If `|fy/len| > shoe_walk_slant (0.9)` the foothold is too steep. The character slips along it: `mvr → toward slipSpeed·slip` at rate `slipForce·slip·Δ`.
- Otherwise:
  - Holding a direction accelerates by `walkForce·fs` (1400 px/s² at mass 100) up to ±maxf (125 px/s). If already above maxf, it decelerates by `drag·fs` (800 px/s²).
  - With no input it decelerates toward 0 by `drag·fs` (800 px/s²).
- The foothold's own `force` is added back: `mvr += fh->force` (conveyor footholds).

**Airborne, non-swim (`:153-169`).**
- `vy` is first dragged toward 0 by floatDrag2/mass·Δ (100 px/s²), then `vy = min(vy + 2000·Δ, 670)`.
- Horizontal air control is tiny. If you hold a direction and |vx| < floatDrag2·float_multiplier (≈8.93 px/s), vx changes by `2·floatDrag2/mass·Δ` (200 px/s²) up to that cap. Above the cap, input does nothing (momentum is kept).
- With no input, vx decays by `floatCoefficient·floatDrag2/mass` (1 px/s²) while still accelerating vertically, or by 100 px/s² once at fall speed.

**Jump (`:71-92`).**
- `vy = −jumpSpeed·shoeWalkJump` (×0.7 in swim maps).
- If a direction is held, vx is clamped into `[0.8·fmax, fmax]` in that direction. fmax = 125, raised by `(1 + fy²/(fx²+fy²))` when jumping uphill.
- Swimming jump: `vy = −700·swimSpeedV`.

**Down-jump (`:74-79`).** Requires `down && !fh.cantThrough && !fh.forbidFallDown` and some other foothold spanning x below. Then `djump = fh; vx = 0; vy = −555·0.35355339` ≈ −196 px/s. The `djump` foothold is ignored for collision until the character lands on another one (`:245`, `:254`).

**Walking off footholds / walls (`:187-229`).**
- On passing x2:
  - `next == null` → fall off the edge.
  - Next foothold is a normal floor (x1 < x2) → continue onto it, with velocity re-projected by a dot product.
  - Next foothold is vertical going up (y1 > y2) → **wall**: stop, vx = vy = 0.
  - Next foothold is vertical going down → fall off.
- The mirror logic applies on passing x1 using `prev`.

**Landing (`:239-272`).**
- Segment-intersection of the motion vector against all footholds. Only crossings with `denom < 0` count, i.e. arriving from above on left-to-right footholds.
- Group rule: `group == f.group || dx2 > 0 || f.group == 0 || f.cant_through`.
- Footholds with x1 > x2 act as ceilings (nudge down, no landing). Footholds with x1 == x2 are walls (nudge sideways).
- On landing: `vy = min(vy, 162.5)`, then velocity is projected onto the foothold.

**Ladders.** The `lr` branch is empty; ladders are not implemented.

### 1c. HeavenClient (AGPL-3.0, cbb0fe2) [C], useful as a simple fallback model
- **Timestep:** 8 ms (`Constants.h:29`, `TIMESTEP = 8`). Speeds are in px per tick, so ×125 gives px/s.
- **Constants (`Gameplay/Physics/Physics.cpp:22-28`):** GRAVFORCE 0.14 (≈2187 px/s²), SWIMGRAVFORCE 0.03, FRICTION 0.5, SLOPEFACTOR 0.1, GROUNDSLIP 3.0, FLYFRICTION 0.05, SWIMFRICTION 0.08. It does **not** read Physics.img.
- **Ground (`Physics.cpp:66-103`):** `hacc -= (FRICTION + SLOPEFACTOR·(1 + clamp(slope,±0.5)·−inertia))·inertia`, where `inertia = hspeed/3`. In the air, `vacc += GRAVFORCE`. There is no terminal-velocity cap.
- **Player forces (`Character/Player.cpp:465-483`):**
  - walk = `0.05 + 0.11·SPEED/100` px/tick². The steady state is about 0.8 px/tick ≈ 100 px/s, not 125.
  - jump = `1.0 + 3.5·JUMP/100` = 4.5 px/tick ≈ 562 px/s.
  - climb = `SPEED/100` px/tick (= 125 px/s at 100%).
  - fly = 0.25.
- **Air control (`PlayerStates.cpp:216-221`):** ±0.025 px/tick² only when reversing direction.
- **Knockback when hit (`Player.cpp:354-357`):** `hspeed = ±1.5` px/tick (187.5 px/s) away from the attacker and `vforce −= 3.5`. It is skipped on ladders, when dead, or when the stance stat roll succeeds.
- **Down-jump:**
  - `FootholdTree.cpp:205-221` sets `enablejd` only if a foothold exists below within 600 px.
  - `PlayerStates.cpp:154-158, 250-254` then teleport y to `ground+1` (`groundbelow`).
  - It does **not** check cantThrough or forbidFallDown.
- **Ladder exit jump (`PlayerStates.cpp:400-405`):** `hspeed = ±8·walkforce`, `vspeed = −jumpforce/1.5`. There is a 1000 ms re-grab cooldown (`Player.cpp:455-458`).
- **Walls (`FootholdTree.cpp:243-277`):** checks `prev`/`prev.prev` (or `next`/`next.next`) for a vertical foothold overlapping `[y−50, y−1]`. Otherwise it uses the map walls.
- **Map edges (`FootholdTree.cpp:91-92`):** walls = (min foothold x + 25, max foothold x − 25); borders = (min foothold y − 300, max foothold y + 100).

### 1d. Harepacker MapSimulator `Physics/CVecCtrl.cs` (MPL-2.0, 4d7fcec) [B for the formulas, C for its numbers]
- States its source as "MapleStory client's CVecCtrl class from IDA Pro analysis" (`CVecCtrl.cs:11`). The docs target **GMS v95** (`docs/mapsimulator/*`: 75× "v95").
- `AccSpeed(v, force, mass, vMax, t)`: `v += force/mass·t`, clamped to ±vMax (`:113-129`).
- `DecSpeed(v, drag, mass, vTarget, t)`: `v −= drag/mass·t` toward vTarget (`:140-156`).
- `CalcWalk`: no input → DecSpeed; same-direction input → AccSpeed; opposite input → DecSpeed, then AccSpeed once the sign flips (`:1267-1313`).
- `CalcFloat` uses the same pattern on both axes (`:1330-1380`).
- The doc comment claims trapezoidal position integration, `pos += (v_old+v_new)/2·t` (`PhysicsConstants.cs:10-13`). This is consistent with NoLifeStory's structure.
- The mob knockback and air-drag multipliers (`CVecCtrl.cs:93-98`, `AirDrag 0.98`, `GroundFriction 0.85`) are tuned (tier C).

### 1e. MapleNecrocer (MIT, 2aeb7db) [C]
Per-frame at 60 fps (`Client/MapleCharacter.cs:136-138, 715-746`):
- walk accelerates +1.5 per frame up to 2.5 px/frame (150 px/s) and decays by 0.25 per frame;
- jump 9.5 px/frame (570 px/s);
- gravity 0.6 px/frame² (2160 px/s²);
- max fall 8 px/frame (480 px/s).

None of these come from Physics.img.

### 1f. Climbing, swim, fly
- **Ladder/rope data [A]:** Henesys `ladderRope/N` has `l` (1 = ladder, 0 = rope), `uf` (1 = can climb off at the top), `x`, `y1`, `y2`, `page` (layer). Command: `node wzdump.mjs Map.wz Map/Map1/100000000.img 5`; see `henesys.txt`.
- MapleNecrocer uses `uf` and `L` the same way (`MapleCharacter.cs:552-592`).
- **Climb speed** is UNVERIFIED. HeavenClient = SPEED/100 px/tick (125 px/s); NoLifeStory has no implementation.
- **Swim and fly** are only in NoLifeStory (`:134-152`): vertical caps are 0.3·vmax up and 1.5·vmax down, with a passive sink.

---

## 2. Footholds

- **Layout [A]:** `foothold/<layer 0-7>/<group>/<id>/{x1,y1,x2,y2,prev,next}`. In Henesys, all 338 footholds have exactly these 6 keys, so no `piece`, `cantThrough`, `forbidFallDown` or `force` appear there (see `henesys.txt`).
- The optional keys read by NoLifeStory `foothold.cpp:29-41` are `force`, `piece`, `cantThrough` and `forbidFallDown`. **`piece` is read everywhere but used nowhere.**
- **Direction semantics (NoLifeStory `physics.cpp:239-266`):**
  - Walkable floors run x1 < x2 (left to right) and are only landed on from above.
  - x1 > x2 means a ceiling or underside.
  - x1 == x2 means a wall. Its direction (y1 > y2 or y1 < y2) decides whether walking into it blocks you or lets you fall.
- **Linking:** `prev`/`next` are foothold IDs, with 0 meaning none. Edges are footholds with prev==0 or next==0 (HeavenClient `Foothold.cpp:105-113`).
- **"Foothold below (x, y)" (HeavenClient `FootholdTree.cpp:315-336`):**
  1. Index every non-wall foothold at each integer x in [l, r] (`:82-86`).
  2. For a query, take candidates at `int(x)` and pick the minimum `ground_below(x)` that is ≥ y.
- **Ground y (`Foothold.cpp:145-148`):** `is_floor ? y1 : y1 + (y2−y1)/(x2−x1)·(x−x1)`. Slope = `vdelta/hdelta`, and 0 for walls (`:140-143`).
- **VR bounds fallback when VRLeft etc. are absent.** This happens in real maps: **Henesys 100000000 has no VR keys [A]** (`grep -c VR henesys.txt` → 0). Implementations differ:

| Source | Fallback rule | Tier |
|---|---|---|
| HeavenClient `MapInfo.cpp:26-35` + `FootholdTree.cpp:91-92` | uses VR if `info/VRLeft` is an int; else walls = fh-bbox x ± 25 inward, borders = fh-bbox top −300, bottom +100 | C |
| NoLifeStory `view.cpp:92-101` | fh-bbox, then top −300, bottom +75 | C |
| WzComparerR2 `MapData.cs:546-598` | union of fh rects, then Y −250 and height +450 (i.e. bottom +200), plus a union with ladder rects | C |

The real client rule is UNVERIFIED. The v95 field-bounds logic is in MapleLib `ClientLib/CWvsPhysicalSpace2D.cs` (GPL-3.0), which I did not read in depth.

---

## 3. Map rendering

**Backgrounds (map node `back/N`) [A]:** keys `no, x, y, rx, ry, type, cx, cy, bS, a, front, ani, f` (Henesys `back/0..`). Resources come from `Map.wz/Back/<bS>.img/{back|ani}/<no>` (ani=1 → animated frames).

**Tile mode by `type`.** These all agree: WzComparerR2 `Patches2/BackItem.cs:79-91`, NoLifeStory `background.cpp:58-102`, HeavenClient `MapBackgrounds.cpp:69-97`, MapleNecrocer `MapBack.cs:63-96`.

| type | tiling | motion |
|---|---|---|
| 0 | none | parallax |
| 1 | horizontal | parallax |
| 2 | vertical | parallax |
| 3 | both | parallax |
| 4 | horizontal | auto-scroll X at rx·5 px/s, parallax Y |
| 5 | vertical | auto-scroll Y at ry·5 px/s, parallax X |
| 6 | both | auto-scroll X |
| 7 | both | auto-scroll Y |

**Parallax** (WzComparerR2 `FrmMapRender2.SceneRendering.cs:845-862`): `worldPos = back.x + camCenterX·(100+rx)/100`. After the camera transform, screen x = back.x + camCenterX·rx/100 + screenW/2. So rx=0 means the layer is fixed to the screen and rx=−100 means it is fixed to the world.
- HeavenClient: `shift_x = rx·(W/2 − viewx)/100 + W/2` (`MapBackgrounds.cpp:110`), the same formula.
- NoLifeStory: `rx·(xmin + W/2)/100 + W/2` (`background.cpp:55`). Its Y formula is anchored differently: `ry·(ymax−300)/100 + H/2 + (H−600)/2` (`:56`).
- Position is floored before drawing (WzComparerR2 `:866-867`).

**Auto-scroll speed:**
- WzComparerR2 `offset = rate·100·t_ms/20000` gives rate·5 px/s, modulo cx (`:816-823`). It uses `flowX/flowY` if present, which are post-v83 keys.
- NoLifeStory `delta_total·rx·5` (`background.cpp:82,88,93,100`).
- MapleNecrocer `RX·5/60` per frame at 60 fps (`MapBack.cs:287,296`).
- **Consensus: 5 px/s per unit.** HeavenClient's `rx/16` per 8 ms tick (`MapBackgrounds.cpp:91,95`) ≈ 7.8 px/s is the outlier.

**cx/cy:** the tile period. If 0, use the canvas width/height (WzComparerR2 `:807-814`; HeavenClient `:60-64`). The tile count must cover the screen plus margins (WzComparerR2 `:871-905`).

**Other background keys:**
- `a` = alpha 0–255 (HeavenClient `:39`, drawn as `opacity/255`).
- `f` = flip X. For a flipped canvas, origin.x becomes `width − origin.x` (MapleNecrocer `MapBack.cs:217-222`).
- **Front** backgrounds (`front=1`) are drawn after all layers (WzComparerR2 `MapData.cs:227-237` puts them in `Scene.Front`).
- If `back/0/bS` is empty, the screen is cleared to black (HeavenClient `MapBackgrounds.cpp:179,186-187`).

**Layers 0–7 and draw order (WzComparerR2 `MapScene.cs:11-24, 56-67`):** Back → Layers[0..7] {Obj, Reactor, Tile, Foothold-attached life} → Fly {Portal, LadderRope, Sky…} → Front → Effect.
- Inside a container, MapRender2 sorts by (Z0, Z1) (`MeshItem.cs:22-27`):
  - objs: Z0 = map obj `z`, Z1 = node index (`SceneRendering.cs:953-954`);
  - tiles: Z0 = tile **canvas** `z`, Z1 = index (`:976-977`).
- The legacy renderer (`FrmMapRender.cs:1350-1358, 1405-1412, 1075-1084`) sorts by [layer, Obj<Tile, z, loadIndex]. It explicitly marks `zM` as "not use for sort".
- HeavenClient: per layer it draws objs (multimap by obj `z`), then tiles (by canvas `z`, falling back to `zM` if z==0) (`MapTilesObjs.cpp:24-46`, `Tile.cpp:56-59`).
- Tile layer `info/tS` names the tileset: `Map.wz/Tile/<tS>.img/<u>/<no>`. Obj path: `Map.wz/Obj/<oS>.img/<l0>/<l1>/<l2>` (HeavenClient `Obj.cpp:28`).

**Origins:** draw at `pos − origin`; with flip, mirror around the anchor (WzComparerR2 `AvatarCanvas.cs:957-960` uses the same convention for characters).

**Animated frames (HeavenClient `Graphics/Animation.cpp:33-70`):**
- `delay` defaults to 100 ms if missing.
- `a0/a1` are start/end alpha for the frame, interpolated linearly. If only one is given, the other is 255 minus it.
- `z0/z1` are start/end scale percentages.
- WzComparerR2 also reads `repeat` for objs (`FrmMapRender.cs:1360`).

**Camera smoothing [C, all differ]:**
- HeavenClient `Camera.cpp:44-64`: moves 12/W (or 12/H) of the remaining delta per 8 ms tick, with a dead zone of 5 px, then clamps to VR bounds.
- NoLifeStory `view.cpp:119-130`: step = `(|d|−28)^1.5 + 28`·Δ·0.2 with a 28 px dead zone. The view is anchored so the player is 250 px above the screen bottom (`:47, :155`). Bounds use `leftin = left + W/2` etc. (`:53-60`).

**Logical resolution:** v83 UI assets are authored for 800 wide: StatusBar `base/backgrnd` is **800×71** [A]. The real client's vertical camera anchor is UNVERIFIED.

---

## 4. Character compositing

**zmap.img [A]** (`node wzdump.mjs Base.wz zmap.img`) is an ordered list of 151 names (saved as `_scratch/zmap.txt`), **front-most first**:

> mobEquipFront, tamingMobFront, mobEquipMid, saddleFront, mobEquipUnderSaddle, tamingMobMid, saddleMid, backSaddleFront, characterStart, emotionOverBody, weaponWristOverGlove, capeOverHead, weaponOverGlove, gloveWristOverHair, gloveOverHair, handOverHair, weaponOverHand, shieldOverHair, gloveWristBelowWeapon, gloveBelowWeapon, handBelowWeapon, weaponOverArm, gloveWristBelowMailArm, mailArmOverHair, gloveBelowMailArm, armOverHair, mailArmOverHairBelowWeapon, armOverHairBelowWeapon, weaponBelowArm, capOverHair, hairOverHead, accessoryEyeOverCap, capAccessory, cap, hair, accessoryEye, accessoryEyeShadow, accessoryFace, capAccessoryBelowAccFace, accessoryEar, capBelowAccessory, accessoryFaceOverFaceBelowCap, face, accessoryFaceBelowFace, hairShade, head, cape, gloveWrist, mailArm, glove, hand, arm, weapon, shield, weaponOverArmBelowHead, gloveWristBelowHead, mailArmBelowHeadOverMailChest, gloveBelowHead, armBelowHeadOverMailChest, mailArmBelowHead, armBelowHead, weaponOverBody, mailChestTop, gloveWristOverBody, mailChestOverHighest, pantsOverMailChest, mailChest, shoesTop, pantsOverShoesBelowMailChest, shoesOverPants, mailChestOverPants, pants, shoes, pantsBelowShoes, mailChestBelowPants, gloveOverBody, body, gloveWristBelowBody, gloveBelowBody, capAccessoryBelowBody, shieldBelowBody, capeBelowBody, hairBelowBody, weaponBelowBody, backHairOverCape, backWing, backWeaponOverShield, backShield, backCapOverHair, backHair, backCap, backWeaponOverHead, backHairBelowCapWide, backHairBelowCapNarrow, backHairBelowCap, backCape, backAccessoryFaceOverHead, backHead, backMailChestOverPants, backPantsOverMailChest, backMailChest, backPantsOverShoesBelowMailChest, backShoes, backPants, backShoesBelowPants, backPantsBelowShoes, backMailChestBelowPants, backWeaponOverGlove, backGloveWrist, backGlove, backBody, backAccessoryEar, backAccessoryFace, backCapAccessory, backMailChestAccessory, backShieldBelowBody, backHairBelowHead, backWeapon, characterEnd, saddleRear, tamingMobRear, mobEquipRear, backMobEquipFront, backTamingMobFront, backMobEquipMid, backSaddle, backMobEquipUnderSaddle, backTamingMobMid, Sd, Tm, Sr, Wg, Ma, Ws, Pn, So, Si, Wp, Gv, Ri, Cp, Ay, As, Ae, Am, Af, At, Fc, Hr, Hd, Bd

- "Front-to-back" is confirmed by WzComparerR2, which sorts descending by zmap index (`AvatarCanvas.cs:894`), and by Harepacker's comment "zmap.img is enumerated from front to back; drawing needs back to front" (`CharacterData.cs:3979-3981`).
- Each canvas has `z` = one of these names (or an int; see `AvatarCanvas.cs:750-760, 980-991`). An unknown name goes to the very back.

**smap.img [A]** maps a z-name to 2-letter slot codes. Examples: `cap = "CpHdH1H2H3H4H5H6HsHfHbAfAyAsAe"`, `hair = "H2"`, `hairOverHead = "H1"`, `backHair = "H1"`, `backHairBelowCap = "H6"`, `face = "Fc"`, `head = "Hd"`, `body/arm/hand = "Bd"`, `mailChest = "MaGw"`, `pants = "PnSo"`, `shoes = "So"`, `weapon = "Wp"`, `shield = "Si"`, `cape = "Sr"`.
- Equip `info/vslot` and `info/islot` use the same codes, which decide which body and hair layers a cap or overall hides. Full output: `_scratch/smap.txt`.
- Harepacker shows the visibility resolution in `CharacterAssembler.cs:2112-2147` (intersecting layer tokens with the part's `vslot`) and `CharacterData.cs:3906-3920` (priority from `islot`).

**Map vectors [A]:** `Character.wz/00002000.img/stand1/0`:
- `body` 21×31, origin (16,31), `map/neck (−4,−32)`, `map/navel (−8,−21)`, z "body", group "skin";
- `arm` 10×19, origin (5,9), `map/navel (−13,−1)`, `map/hand (−1,5)`, z "arm";
- `face=1`, `delay=500`.

How the vectors compose:
- **WzComparerR2 (MIT) uses generic bones** (`AvatarCanvas.cs:684-858`). The first map entry of a part becomes its anchor bone; a part whose anchor already exists is attached with offset `−mapOrigin`. Any further map entries create child bones. Pixel position = sum of bone positions − canvas origin (`:950-960`).
- **HeavenClient (AGPL) hard-codes the vectors** (`BodyDrawInfo.cpp:93-102`):
  - body = navel;
  - arm = arm.hand − arm.navel + body.navel;
  - head = body.neck − head.neck;
  - face = body.neck − head.neck + head.brow;
  - hair = head.brow − head.neck + body.neck;
  - handMove comes from `handBelowWeapon`.

**Stances in v83 `00002000.img` [A]:** info, walk1, walk2, stand1, stand2, alert, swingO1–3, swingOF, swingT1–3, swingTF, swingP1–2, swingPF, stabO1–2, stabOF, stabT1–2, stabTF, shoot1, shoot2, shootF, proneStab, prone, heal, fly, jump, sit, ladder, rope, dead, plus about 130 skill-specific actions (savage, alert2–6, magic1–5, …, dragon*).

**Frame delays [A]:**

| stance | delays (ms) |
|---|---|
| stand1 / stand2 / alert | 500, 500, 500 |
| walk1 / walk2 | 180 ×4 |
| jump | 200 |
| ladder / rope | 250, 250 |
| swingO1/O2/O3/T1, shoot1, heal | 300, 150, 350 |
| stabO1 | 350, 450 |
| proneStab | 300, 400 |
| shoot2 | 160, 160, 250, 100, 150 |
| fly | 300, 300 |
| magic1 | −900, 200, 200 (negative delay is present in the data) |

- `prone`, `sit` and `dead` frames have no delay key.
- Ladder/rope frames use z `backBody` and `face=0`, i.e. drawn from behind with no face.
- The default delay when the key is missing is UNVERIFIED: HeavenClient uses 100 (`BodyDrawInfo.cpp:67-68`), WzComparerR2 uses 120 (`AvatarCanvas.cs:474`).

**Face expressions [A]:** `Character.wz/Face/00020000.img`: default, blink, hit, smile, troubled, cry, angry, bewildered, stunned, vomit, oops, cheers, chu, wink, pain, glitter, despair, love, shine, blaze, hum, bowing, hot, dam.

**Default beginner look [A]:** `Etc.wz/MakeCharInfo.img/Info/CharMale`:

| slot | options (first listed first) |
|---|---|
| 0 face | 20000, 20001, 20002 |
| 1 hair | 30030, 30020, 30000 |
| 2 hair colour | 0, 7, 3, 2 |
| 3 skin | 0, 1, 2, 3 |
| 4 top | 1040002, 1040006, 1040010 |
| 5 bottom | 1060002, 1060006 |
| 6 shoes | 1072001, 1072005, 1072037, 1072038 |
| 7 weapon | 1302000, 1322005, 1312004 |

- CharFemale: face 21000–21002; hair 31000, 31040, 31050; top 1041002/6/10/11; bottom 1061002/8.
- Body and head are 00002000 / 00012000 (+skin).
- NoLifeStory `player.cpp:41-49` uses placeholder IDs (1000000, 1050000, …), not real defaults.

---

## 5. Mobs (mostly UNVERIFIED; no open source is authoritative)

- **Animation nodes** read by HeavenClient `Mob.cpp:60-73`: `stand`, `move`, `fly` (replaces stand and move for flyers), `jump`, `hit1`, `die1`. Info keys: `speed`, `flySpeed`, `pushed` (`:44-46`).
- **Speed stat → motion [C, inconsistent]:**
  - HeavenClient: force = (speed+100)·0.001 px/tick² against its friction, giving terminal ≈ (speed+100)·0.625 px/s (`Mob.cpp:82-86`).
  - MapleNecrocer: `(1+speed/100)·2` px/frame = 120·(1+speed/100) px/s (`Client/Mob.cs:149`).
  - Hypothesis (UNVERIFIED): the client treats the mob like a walker with maxSpeed = 125·(100+speed)/100 px/s.
- **`pushed` knockback threshold:** HeavenClient enters HIT only when `damage >= pushed` (`Mob.cpp:567-571`). The knockback force is 0.2 px/tick² on the ground and 0.1 in the air (`:226-231`). [C]
- **Hit stun:** HeavenClient sets counter=170 and leaves HIT at >200 ticks, i.e. 30 ticks × 8 ms = **240 ms** (`:245-249, :570`). [C]
- **Death:** HeavenClient plays `die1` to completion. Fade/fade-in is opacity ∓0.025 per 8 ms tick, i.e. a 320 ms fade (`:153-175`). [C]
- **Regen:** spawn fade-in, same rate (`:108-116`). [C]
- **Harepacker `Entities/MobMovementInfo.cs`:** its MapleNecrocer-derived per-60fps constants are tier C (`:1135, :1198-1230`).

---

## 6. Combat feedback

**Digit sets [A]** (`node wzdump.mjs Effect.wz BasicEff.img 3`, then `basiceff.txt`). All are form 1 (ARGB4444):

| set | digits 0–9 size range | typical origin | extras |
|---|---|---|---|
| NoRed0 (small) | 22–31 × 32–33 | (15,32); "1" (11,31) | `Miss` 98×38 o(49,37) |
| NoRed1 (large) | 25–37 × 37–39 | (18,37) | – |
| NoBlue0 / NoBlue1 | same as Red | same | **no Miss** |
| NoViolet0 / NoViolet1 | same as Red | same | NoViolet0 has `Miss` |
| NoCri0 | 25–37 × 38–39 | (18,37) | – |
| NoCri1 | 29–43 × 44–48 | (21,45) | `effect` 62×57 o(41,70) |

**Which set for what:**
- Harepacker's v95 RE says color case 0 = Red (Cri when critical), 1 = Blue (damage to player), 2 = Violet (party/summon) (`docs/mapsimulator/damage_number_analysis.md:200-222`).
- HeavenClient maps damage *to the player* to NoViolet: `Char.cpp:197` constructs `DamageNumber::Type::TOPLAYER`, and `DamageNumber.cpp:200-201` maps TOPLAYER to NoViolet1/NoViolet0.
- Inference for v83, not a verdict: damage to the player = **Violet**, because NoViolet0 carries a `Miss` glyph, which only makes sense for "monster missed you". NoBlue lacks one, so Blue is more likely for MP/heal or other numbers. UNVERIFIED.

**First digit uses the large set and the remaining digits use the small set:**
- HeavenClient `DamageNumber.cpp:48-68, 96-107`;
- Harepacker `Effects/DamageNumberRenderer.cs:692-715` (`useLargeDigitSet` true only for the first digit).

**Spacing:**
- [B] Harepacker, from v95 `Effect_HP @0x444eb0`: `relX = acc + width − prevOverlap; acc = acc − prevOverlap + originX; prevOverlap = 3·(originX − width)/5` (`DamageNumberRenderer.cs:700-713`, comment at `:467-478`). Critical numbers get +30 px leading space (`:43`).
- [C] HeavenClient: fixed advance table {24,20,22,22,24,23,24,22,24,24} for digits 0–9, plus 2 on the first digit (critical: +8 first, +4 others). It averages adjacent advances and applies a ±2 px alternating vertical jitter (`:106, :129-170`).

**Timing [B]** (`damage_number_analysis.md:16-35, 122-141, 166-192`):
- 400 ms static at alpha 255, then 600 ms of linear fade 255→0 while rising 30 px (50 px/s); total 1000 ms.
- The critical `NoCri1/effect` appears about 250 ms in, at y−30.
- There is no random offset and no scaling.
- Multi-hit numbers are stacked by the caller. HeavenClient uses row heights of 30 (normal) and 36 (critical) (`DamageNumber.cpp:187-190`, `Combat.cpp:397`). Harepacker's "20 px / 100 ms" is a stated *suggestion* (tier C).
- HeavenClient differs: rise −0.25 px/tick (31 px/s), opacity 1.5→0 over 500 ms per unit (`:78-79, :181`; `DamageNumber.h:53`) [C].

**Mob HP bar:**
- HeavenClient draws a primitive 50×10 bar (black border, white inset, light-green fill) at `headpos − 3·height` (`Graphics/Geometry.cpp:115-128`, `Geometry.h:79-80`) [C].
- Boss bar assets exist in v95 as `UI/UIWindow.img/MobGage/{backgrnd…, Mob/%d, Gage/%d/0|1}` (Harepacker `MapleStoryStringPool.g.cs:3334-3340`). The v83 equivalent was not checked.
- Whether v83 draws a per-mob bar, and its exact look: UNVERIFIED.

**Hit effect placement:** HeavenClient `Mob::show_effect` pos 0 = the mob's `head` vector of the current frame (`Mob.cpp:433-444, 383-391`). Other `pos` values are unimplemented.

---

## 7. Skill effects

**Node shapes [A]** (`node wzdump.mjs Skill.wz 200.img 6` / `210.img`):

| skill | nodes present | frames |
|---|---|---|
| 2001004 Energy Bolt | `ball` (projectile) + `hit/0`, `hit/1`; no `effect` | ball 4×33×33, o(16,16), 80 ms; hit/0 3 frames 80 ms (frame 2 z=1); hit/1 has **no delay keys** |
| 2001005 Magic Claw | `effect` (on caster) + `hit/0` (on mob) + `CharLevel/10/{effect,hit}`; no `ball` | effect 4 frames 80 ms, origin ≈(39–43,69–73); hit 5 frames 90–150 ms |
| 2101004 Fire Arrow | `action/0 = "shoot1"`, `elemAttr = "f"`, `effect` (10 frames × 100 ms), `ball` (3 frames 84×20, o(42,10), 30 ms), `hit/0` (5 frames × 90 ms) | |

- **No `speed` key exists in any `ball` node** (`grep -c speed skill200.txt skill210.txt` → 0, 0), so projectile speed is hard-coded in the client and UNVERIFIED.
- HeavenClient: `hspeed = clamp(dx/32, 3..6)` px/tick (375–750 px/s), spawned at ±30 px horizontally and −26 px vertically from the user, and hits when within 10 px (`Gameplay/Combat/Bullet.cpp:22-65`) [C].
- Harepacker defaults to 400 px/s (`SkillLoader.cs:14631`) [C].

**Selection logic (HeavenClient `Skill.cpp:41-150`, `SkillUseEffect.cpp`, `SkillHitEffect.cpp`):**
- `effect` vs `effect0..N` (multi), `CharLevel/<lvl>/effect` (pick the highest level ≤ the player's level), and `effect/0|1` (one- vs two-handed).
- `hit/0` vs `hit/1` (second weapon), and `level/<n>/hit` or `level/<n>/ball`.
- `affected` = buff overlay on the target (2101001 has `affected/`). `prepare` is not present in the sampled skills.
- The anchor of the user effect relative to the character is UNVERIFIED (not read).

---

## 8. UI (v83 [A])

- **UI.wz images** (`node wzdump.mjs UI.wz "" 1`): Logo, GuildBBS, BuffIcon, Npt_GuideLine, CashShopPreview, ITCPreview, MapLogin, GuildMark, MapleTV, tutorial, **StatusBar**, DialogImage, **Basic**, CashShop, NameTag, Login, ChatBalloon, ITC, **UIWindow**. There is **no StatusBar2 or StatusBar3**.
- **StatusBar.img** (`statusbar.txt`): `base/{backgrnd 800×71, backgrnd2 570×71, quickSlot 151×80, chatTarget, box, iconRed, iconBlue, iconMemo, chat 566×5}`.
- **gauge/:** `graduation` 340×31, `bar` 340×31, `gray` 1×16, `tempExp` 1×16, `hpFlash/0..4` and `mpFlash/0..4` (109×18, frames 2–4 are UOL links back to 0/1).
- **Buttons:** BtShop, BtMenu, BtNPT, BtShort, BtWhisper, BtClaim, EquipKey, InvenKey, StatKey, SkillKey, KeySet, QuickSlot, QuickSlotD, key/.
- **number/:** digits 0–9 (5×7), Lbracket, Rbracket, slash, percent. **FontMemo/** has 0–9 at 6×7.
- The 1-pixel `gray`/`tempExp` strips suggest the HP/MP/EXP fills are stretched or drawn by code. The exact fill colours and geometry are UNVERIFIED.
- **Level digits:** `UI.wz/Basic.img/LevelNo` exists (contents not dumped).
- **Notice/selection windows:** `Basic.img/{Notice, Notice2, Notice3, Notice4, YesNo, YesNo2, YesNo3, BtOK…, BtYes, BtNo}`, plus `UIWindow.img` for game windows.
- JourneyClient's `UIStatusbar.cpp:32-78` (StatusBar2.img/mainBar …) and HeavenClient's UI therefore come from a later client and are **not** v83 references.

---

## WZ format facts

| Fact | Value | Evidence |
|---|---|---|
| Header | "PKG1", u64 file size, u32 data start, copyright "Package file v1.0 Copyright 2002 Wizet, ZMS" | wzdump on Base.wz: `fstart=60`; `xxd Base.wz` shows `PKG1 … ac00` at 0x3C [A] |
| Encrypted version | u16 at data start = 0x00AC | [A] |
| Version hash | `h = fold(h*32 + ascii(c) + 1)` over the decimal string; `enc = 0xFF ^ b3 ^ b2 ^ b1 ^ b0`. "83" → hash 1876, enc 0xAC (unique in 1..499) | wz-reader-rs `src/util/version/pkg1.rs:17-26,32-37` (MIT); wzdump output `versionCandidates=83 hash=1876` [A] |
| Offset decrypt | `o = ~(pos − fstart) * hash − 0x581C3F6D; o = rol(o, o & 31) ^ stored; o += fstart*2` | WzComparerR2 `Compatibility/WzOffsetCalc.cs:81-92` (MIT); MapleLib `WzAESConstant.cs:36` (GPL) [A: correct directory offsets in all files I tested] |
| Keystream | AES-256-ECB, key = 32 bytes `13 00 00 00 08 00 00 00 06 00 00 00 B4 00 00 00 1B 00 00 00 0F 00 00 00 33 00 00 00 52 00 00 00` (the GMS "user key" trimmed to every 4th byte); block0 = E(IV×4 = `4D 23 C7 2B` ×4), block_n = E(block_{n−1}) | WzComparerR2 `Wz_Crypto.cs:105, 185-207, 290-297` [A: string decode works] |
| Strings | sbyte len >0: UTF-16, xor mask 0xAAAA (+1 per char) ^ key; <0: ASCII, xor 0xAA (+1) ^ key; 127/−128 means an i32 length follows | wzdump `R.str()` [A] |
| Dir entries | type 1 = skip 10 bytes; 2 = i32 offset to (type, name) at fstart+off; 3 = dir; 4 = img; then cint size, cint checksum, encrypted u32 offset | [A] |
| IMG prop flags | 0 null, 2/11 i16, 3/19 cint, 20 clong, 4 cfloat (sbyte, −128 → f32), 5 f64, 8 string, 9 object (u32 len) | WzComparerR2 `Wz_Image.cs:464-520` [A] |
| Image string tags | 0x00/0x73 inline, 0x01/0x1B i32 offset from image start | [A] |
| Objects | `Property` (skip 2, cint count), `Canvas`, `Shape2D#Vector2D` (2 cints), `Shape2D#Convex2D`, `UOL`, `Sound_DX8` | `Wz_Image.cs:241-302` |
| Canvas | skip 1, has-props byte (1 → skip 2 + props), cint w, cint h, cint format, byte format2/scale, 4 bytes (v83: zeros; newer: pages + unknown), i32 dataLen, zlib data (header 0x78 0x9C, else a list.wz-style encrypted chunk stream) | `Wz_Image.cs:259-280`, `Wz_Png.cs:143-165` |
| Pixel formats | 1 = ARGB4444 (all v83 BasicEff/StatusBar/Skill canvases sampled [A]), 2 = ARGB8888, 257 = ARGB1555, 513 = RGB565, **517** = 513 + scale 4 → RGB565 at 1/16 resolution, each pixel expanded to a 16×16 block, 1026 = DXT3, 2050 = DXT5 (later 4097 = DXT1, 4098 = BC7 …) | `Wz_Png.cs:57-66, 196-247, 375-392` |
| Sound_DX8 | skip 1 byte, cint dataLen, cint duration_ms, then AM_MEDIA_TYPE: byte formatDecl; 16-byte majortype GUID; 16-byte subtype GUID; byte fixedSize; byte temporalCompression; 16-byte formattype GUID; if decl==2: cint len + WAVEFORMATEX (may be encrypted; try key variants); then raw MP3/PCM data | `Wz_Image.cs:303-345` |
| UOL | string path relative to the UOL node's **parent**; ".." walks up and may leave the img to its directory | `Wz_Uol.cs:25-50`; v83 uses UOLs (e.g. `StatusBar.img/gauge/hpFlash/2 = uol:"0"`; 21 UOLs in 00002000.img) [A] |
| `_inlink` / `_outlink` / `source` | `_inlink`: path inside the same img; `_outlink`/`source`: global path like `Map/Tile/...` | WzComparerR2 `Common/Wz_NodeExtension2.cs:11-31`; HeavenClient `Tile.cpp:31-52`. **Absent in all v83 files I dumped** (`grep -c _inlink` = 0 for BasicEff, StatusBar, Skill 200, body/head) — a post-v83 feature |

---

## Exact numbers and IDs (quick reference)

| Item | Value | Tier | Source |
|---|---|---|---|
| Walk max speed @100% speed | 125 px/s | A+B | Physics.img walkSpeed; NoLifeStory `physics.cpp:110` |
| Walk accel / ground decel | 1400 / 800 px/s² (force/mass 100) | A+B | Physics.img; `physics.cpp:112-129` |
| Jump take-off / gravity / terminal | 555 px/s / 2000 px/s² / 670 px/s | A | Physics.img |
| Down-jump take-off | 196.2 px/s up (555·0.35355339), vx=0 | B | `physics.cpp:28,79` |
| Landing vy clamp | 162.5 px/s | B | `physics.cpp:41,267` |
| Steep-slope threshold | \|sin\| > 0.9 → slip at slipForce 60000/slipSpeed 120 | B | `physics.cpp:52,115-120` |
| Air control | ≤ ≈8.93 px/s at 200 px/s² | B | `physics.cpp:157-164` |
| Physics step | 10 ms (NoLifeStory) / 8 ms (HeavenClient) / real client UNVERIFIED | B/C | `physics.cpp:100`; `Constants.h:29` |
| Background auto-scroll | rx·5 px/s | B (3 sources) | see §3 |
| Damage number life | 400 ms hold + 600 ms fade/rise 30 px | B (v95) | `damage_number_analysis.md` |
| Critical burst | `BasicEff.img/NoCri1/effect`, 62×57, o(41,70), +250 ms, y−30 | A+B | basiceff.txt; doc :166-184 |
| Player knockback | ±187.5 px/s horizontal, upward impulse | C | HeavenClient `Player.cpp:354-357` |
| Mob hit stun | 240 ms | C | HeavenClient `Mob.cpp:245-249,570` |
| Mob death fade | 320 ms | C | HeavenClient `Mob.cpp:156-165` |
| Default look (male) | face 20000, hair 30030, top 1040002, bottom 1060002, shoes 1072001, weapon 1302000 | A | MakeCharInfo.img |
| StatusBar width | 800 | A | `StatusBar.img/base/backgrnd` 800×71 |

---

## Licensing notes

| Project (commit) | License | What we may take |
|---|---|---|
| Kagamia/WzComparerR2 (6212518) | MIT | Code may be ported with attribution (keep the copyright notice): WZ decode (crypto, offsets, canvas/sound), MapRender ordering/background math, Avatar bone compositing |
| Elem8100/MapleNecrocer (2aeb7db) | MIT (its bundled WzComparerR2.WzLib copy is MIT) | Code may be ported with attribution; its physics is tuned, not authentic |
| spd789562/wz-reader-rs (c991fbd) | MIT | Rust crate usable directly as a dependency or ported (attribution) |
| toyobayashi/wz `@tybys/wz` (744f4bc) | MIT (package.json only; no LICENSE file) | Usable, but get a LICENSE text before shipping |
| davipk/wzlib-rs | MIT (per GitHub API) | Not reviewed |
| lastbattle/Harepacker-resurrected (4d7fcec) | MPL-2.0 (file-level copyleft) | Facts, constants and algorithm descriptions. Copying files would force those files to stay MPL; **recommend re-implementing from prose** |
| lastbattle/MapleLib (580146f; Harepacker submodule) | GPL-3.0 | Facts only; no code into the shipped game |
| ryantpayton/MapleStory-Client "HeavenClient" (cbb0fe2), SYJourney/JourneyClient (5546c99), HypatiaOfAlexandria/MortalClient (29304f6), NoLifeDev/NoLifeStory (f73fb8f), nmnsnv/maplestory-wasm | AGPL-3.0 | Facts, constants and algorithm descriptions only; re-implement from prose. No code copying |
| ryantpayton/NoLifeWzToNx (73bddde) | AGPL headers in source, no LICENSE file | Facts only |
| Elem8100/MapleStory-GM-Client (ffb8918) | MPL-2.0 | Facts (not reviewed in depth) |
| wuzekang/maple-rs (4bb6abf), diamondo25/webstory | No license (all rights reserved) | **Nothing**; do not read for code |
| HeavenMS/Cosmic XML (`cosmic-server/wz`) | Server is AGPL-3.0; the data is Nexon's | Do not use as a data source (proven float errors) |
| Original v83 WZ/exe | Nexon proprietary | The project premise; out of scope here |

My scratch tool `_scratch/wzdump.mjs` is original work written from format knowledge. Its constants match the MIT WzComparerR2 implementation, so it is safe to reuse.

---

## Unknowns and risks

1. **The real client's timestep and integrator** (fixed step size, explicit vs trapezoidal) are UNVERIFIED for v83. Recommendation: confirm in `MapleStory.exe` (v83) around CVecCtrl::CalcWalk / CalcFloat by string-anchoring the Physics.img key names, using REA (not done here).
2. **Mob speed → px/s, mob jump, `pushed` semantics, hit-stun and death-fade durations, regen fade** have no authoritative open source.
3. **Projectile (`ball`) speed** for Energy Bolt / Fire Arrow / Magic Claw is not in the data. Magic Claw has no ball at all (it is an instant hit).
4. **Climb speed and ladder grab/exit rules** are only implemented heuristically (HeavenClient); NoLifeStory skips them.
5. **Damage-to-player colour set** (Violet vs Blue) is an inference from Miss-glyph presence. Small/large set selection beyond "first digit large" is only v95-sourced.
6. **The v83 per-mob HP bar** look and existence, and the StatusBar HP/MP/EXP fill rendering, are unverified.
7. **The camera rule** (dead zone, smoothing, vertical anchor, VR fallback margins) differs across all three implementations; the real rule is unverified. Henesys itself lacks VR keys, so the fallback matters on day one.
8. **Default frame delay** when `delay` is missing: 100 ms (HeavenClient) vs 120 ms (WzComparerR2). Energy Bolt `hit/1` and prone/sit/dead body frames need this.
9. **Harepacker MapSimulator targets v95.** Its "parity" claims (addresses like `0x444eb0`) refer to v95, not v83, and several of its numbers are tuned or placeholders despite "binary analysis" labels. Verify before relying on them.
10. **Stand/alert animation looping** (0-1-2-0 vs ping-pong 0-1-2-1) was not established.
