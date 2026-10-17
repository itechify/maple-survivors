# Asset pipeline

Tree boss manifest additions: Mob9300003 and6220000 automatically include their original Sound.wz/Mob.img
entries; Effect.wz/Summon.img/3 accompanies King Slime's canonical skill200/2. The existing whole MobSkill.img
and UIWindow.img include Dyle's repeat-marked immunity icon and both MobGage icons. No decoded art is committed.

The game renders the player's own MapleStory v83 data. Nothing proprietary is in this repository. A local, offline
importer (`tools/wzimport`, Rust) reads the original `.wz` archives and writes an **asset cache** that the Godot runtime
loads. This document is the contract between the two.

## 1. What you need

A GMS v83 install, i.e. the `.wz` files from the official v83 installer `MapleGlobal-v83-setup.exe`
(Feb 2010, `Wizet` PKG1 archives, encrypted version `0x00AC`). These files are needed:
`Base.wz Character.wz Effect.wz Etc.wz Item.wz Map.wz Mob.wz Npc.wz Skill.wz Sound.wz String.wz UI.wz`.

**How to get them.** Install with the official installer, or extract them without running it: the installer is a
Nexon Game Manager stub followed by a two-volume CAB set. On the dev machine this worked:

```bash
# overlay = MSCF header after the "PADDINGXNFO300" manifest; offsets for the Cosmic-client copy of the installer
dd if=MapleGlobal-v83-setup.exe of=MapleStory_1.cab bs=4M iflag=skip_bytes,count_bytes skip=3371141 count=1048576000
dd if=MapleGlobal-v83-setup.exe of=MapleStory_2.cab bs=4M iflag=skip_bytes,count_bytes skip=1051947141 count=711654917
"C:/Program Files/7-Zip/7z.exe" x MapleStory_1.cab -ov83 "*.wz"
```

Use the **vanilla** files. The HeavenMS/Cosmic `cosmic-wz` set is edited (e.g. `Character.wz` 206 MB vs 186 MB) and
the server XML export has wrong floats (`flyJumpDec` 35.0 instead of 0.35); neither is a canonical source.

## 2. Running the importer

```bash
bash scripts/import.sh "C:/Nexon/MapleStory"          # builds tools/wzimport if needed, then imports
# equivalent:
tools/wzimport/target/release/wzimport import --wz "C:/Nexon/MapleStory" \
    --manifest game/data/asset_manifest.json --out "$APPDATA/MapleSurvivors/asset_cache/v83"
tools/wzimport/target/release/wzimport dump --wz "C:/Nexon/MapleStory" Mob.wz/0100100.img/move 2   # inspect a tree
```

The game can also run it: if the cache is missing, the first screen asks for the v83 folder and launches the bundled
`wzimport` as a local child process. The cache location can be overridden with `MAPLE_SURVIVORS_CACHE`; the WZ folder
with `MAPLE_WZ_ROOT` (also used by tests).

Import is incremental: an img is rewritten only when its source archive (size + mtime) or the importer version changed,
or `--force` is given.

## 3. WZ format facts (v83, verified)

Verified against all 16 PKG1 archives of the vanilla install (0 parse errors, `docs/research/wz-inventory.md`):

| Item | Value |
|---|---|
| Header | `PKG1`, u64 data size (file length - dataStart), u32 dataStart (= 60), NUL-terminated copyright; u16 encrypted version at dataStart = `0x00AC` |
| Version hash | `h = 0; for c in "83": h = 32*h + c + 1` -> 1876; `enc = 0xFF ^ b3 ^ b2 ^ b1 ^ b0` = 0xAC (unique in 1..399) |
| Keystream | AES-256-ECB, key `13 00 00 00 08 00 00 00 06 00 00 00 B4 00 00 00 1B 00 00 00 0F 00 00 00 33 00 00 00 52 00 00 00`, IV `4D 23 C7 2B` x4; block0 = E(IV), blockN = E(blockN-1) (= AES-256-OFB over zeros) |
| Compressed int | i8; -128 -> i32 follows |
| Strings | i8 len; >0 UTF-16 (127 -> i32 len) XOR mask 0xAAAA+i XOR key u16; <0 ASCII (-128 -> i32 len) XOR mask 0xAA+i XOR key byte |
| Offsets | `o = (~(pos - start)) * hash - 0x581C3F6D; o = rotl(o, o & 31) ^ stored; o += start*2` (u32 arithmetic) |
| Directory entries | type 2 (name at offset), 3 (dir), 4 (img), then cint size, cint checksum, encrypted u32 offset. Type 1 never occurs in v83 |
| Img | `0x73 "Property" u16 0`, property list |
| Properties | 0 null, 2/11 i16, 3 cint, 4 float (byte 0x80 then f32, else 0), 5 f64, 8 string block, 9 extended (u32 size + object). Types 19/20 never occur in v83 |
| String blocks | 0x00/0x73 inline; 0x01/0x1B i32 offset from img start |
| Extended objects | `Property`, `Canvas`, `Shape2D#Vector2D`, `Shape2D#Convex2D`, `Sound_DX8`, `UOL` |
| Canvas | u8 0, u8 has_props (1 -> u16 + props), cint w, cint h, cint fmt, u8 fmt2, i32 0, i32 len, u8 0, `len-1` data bytes |
| Canvas data | zlib (`78 9C`) or block-encrypted: repeated (i32 block_len, block XOR keystream[0..]) then zlib. Block encryption occurs in 9,669 Mob.wz canvases (incl. Slime 0210100, Pig 1210100) |
| Pixel formats (fmt+fmt2) | 1 BGRA4444 (99.9%), 2 BGRA8888, 513 RGB565 (UI.wz), 517 RGB565 with one pixel per 16x16 block (2 backs, incl. midForest of 100020000). No DXT in v83 |
| Sound_DX8 | u8 0, cint data_len, cint duration_ms, media-type header (82 bytes for MP3: 51-byte GUID block + u8 wfx_len + WAVEFORMATEX(30)), then data. PCM entries (40: 27 in Pet.img, 13 in Mob.img) have a 70-byte header (wfx_len 18). Tag 0x55 = MP3 (MPEG-1/2 Layer III), 0x01 = PCM. WAVEFORMATEX is never encrypted in v83. A media type whose format-declaration byte is 1 has no wfx_len/WAVEFORMATEX (51-byte header); its only v83 use, `BgmGL.img/Amorianchallenge`, is an ID3-tagged MP3 (not malformed) |
| UOL | u8 0, string block; path relative to the UOL's parent; `..` walks up |
| List.wz | not PKG1: list of mob imgs with encrypted canvases; not needed |

## 4. Manifest (`game/data/asset_manifest.json`)

The manifest says what to import. The importer expands convenience entries into images and sub-paths:

```json
{
  "format": 1,
  "imgs": [
    {"img": "Map.wz/Physics.img"},
    {"img": "Effect.wz/BasicEff.img", "paths": ["NoRed0", "NoRed1", "LevelUp"]}
  ],
  "maps": [104040000],
  "mapimgs": ["UI.wz/MapLogin.img"],
  "mobs": [100100, 210100, 1210102],
  "character": [2000, 12000, 20000, 30030, 1040002, 1060002, 1072001, 1302000],
  "items": [4000019]
}
```

| Entry | Expands to |
|---|---|
| `imgs[]` | the img; `paths` limits the output to those child sub-trees (the whole img is still parsed so UOLs resolve) |
| `maps[]` (9-digit id) | `Map.wz/Map/Map<d>/<id>.img` (d = first digit of the zero-padded id) + every `Map.wz/Back/<bS>.img` (sub-paths `back/<no>` or `ani/<no>` used), `Map.wz/Tile/<tS>.img`, `Map.wz/Obj/<oS>.img` (sub-paths `<l0>/<l1>/<l2>` used), the BGM `Sound.wz/<Bgm..>.img/<name>`, `Map.wz/MapHelper.img/mark/<mapMark>` (not for `"None"`, v83's "no mark"), and every mob in `life` (as a `mobs[]` entry) |
| `mapimgs[]` (full WZ path) | a map-structured img outside `Map.wz/Map` (the v83 login scene `UI.wz/MapLogin.img`: `back`, layers `0`-`7` with `obj`/`tile`, `info/bgm`): the whole img plus exactly the dependencies a `maps[]` entry gets (backs, tiles, objs, BGM, map mark, life mobs). A missing img is an error |
| `mobs[]` | `Mob.wz/<7-digit>.img` + its `info/link` target(s) + `Sound.wz/Mob.img/<7-digit>` |
| `character[]` | body `00002000` -> `Character.wz/00002000.img`; head `12000`; face `2xxxx` -> `Character.wz/Face/000xxxxx.img`; hair `3xxxx` -> `Hair/`; equips by `id/10000`: 100 Cap, 101-103 Accessory, 104 Coat, 105 Longcoat, 106 Pants, 107 Shoes, 108 Glove, 109 Shield, 110 Cape, 111 Ring, 130-170 Weapon |
| `items[]` | `Item.wz/<Type>/<id/10000 as 4 digits>.img/<8-digit id>` (Type by id/1000000: 2 Consume, 3 Install, 4 Etc, 5 Cash, 9 Special: the meso coins) |

The manifest explicitly selects `Sound.wz/Item.img` paths `02000000/Use` through `02000006/Use` for potion
items 2000000–2000006. Verified in original v83 data (tier A): `02000000/Use` is an MP3 Sound_DX8 node;
the other six `Use` nodes are UOLs to `../02000000/Use`. The importer resolves these links and exports the
shared audio once. RunScene plays the consumed item's eight-digit path from `potion_used.item_id`, including
after tier upgrades; missing sounds remain silent and enter the normal playtest `missing` list.

`Sound.wz/Skill.img` also selects `0001002` for Nimble Feet. Its `Use` node is a canonical UOL to
`../1111005/Use`; normal importer resolution exports that sound for the buff's own path. Whole `Skill.wz/000.img`
and `200.img` already supply Nimble Feet and Improved MaxMP Increase icons, level tables and the Nimble Feet
effect. The removed Max HP card no longer needs the extra `Skill.wz/100.img/skill/1000001` manifest selection.

## 5. Cache format (contract)

Character creation (#70) imports `Etc.wz/MakeCharInfo.img` `Info/CharMale`, `Info/CharFemale` and their `Name`
subtrees through the generic img importer (no archive-specific decoder). The numeric columns are face, hair,
hair colour, skin, top, bottom, shoes and weapon, in that order (tier A, original v83 data). `CharacterCreation`
reads these at runtime; the manifest selects every allowed face, all base-hair/colour combinations, four body/head
skins, clothes and weapons. The existing whole `UI.wz/Login.img` selection supplies CharSelect, NewChar and Gender.
`DataRepo.build_setup` reads the same MakeCharInfo weapon column to load each weapon's original info and afterimage.
Synthetic Rust import coverage checks Etc numeric columns and names; real-cache Godot coverage checks all variants.


```
<cache_root>/                                       %APPDATA%/MapleSurvivors/asset_cache/v83 by default
  cache.json                                        index (below)
  Map.wz/Physics.img.json                           one JSON tree per exported img, path = WZ path + ".json"
  Mob.wz/0100100.img.json
  Mob.wz/0100100.img.0.png                          atlas pages of that img (RGBA8 PNG)
  Sound.wz/Bgm01.img/CavaBien.mp3                   audio, path = WZ path of the sound node + extension
```

### 5.1 `cache.json`

```json
{
  "format": 1,
  "importer": "0.1.0",
  "wz_root": "C:/Nexon/MapleStory",
  "created": "2026-10-13T20:00:00Z",
  "sources": {"Mob.wz": {"size": 479665103, "mtime": 1266397980}},
  "imgs": {"Mob.wz/0100100.img": {"json": "Mob.wz/0100100.img.json", "pages": 1, "paths": null, "canvases": 17}},
  "stats": {"imgs": 120, "canvases": 9000, "pages": 140, "sounds": 60, "bytes": 52000000, "seconds": 9.4}
}
```

Img entries also carry `sounds` and `bytes` (per-img totals behind `stats`); readers ignore keys they do not know.
`stats.seconds` is the wall time of the run that wrote the index.

### 5.2 Img JSON trees

The file is a JSON object holding the img root's children, in WZ order (Godot dictionaries keep insertion order).
Keys are the WZ names verbatim (`"0100100"`, `"0"`, `"move"`). Values:

| WZ property | JSON |
|---|---|
| sub-property / img directory | object `{ child: value, ... }` |
| null | `null` |
| short / int / long | number |
| float / double | number |
| string | string |
| Vector2D | `{"$v": [x, y]}` |
| Convex2D | `{"$convex": [[x, y], ...]}` |
| Canvas | object `{"$canvas": [page, x, y, w, h], ...canvas child props}`: `page` indexes the img's `$pages` list; `x, y, w, h` is the region in that page; children (`origin`, `delay`, `z`, `head`, `lt`, `rb`, `a0`, `a1`, `map`, ...) are ordinary keys |
| Sound_DX8 | `{"$sound": "Sound.wz/Bgm01.img/CavaBien.mp3", "$ms": 128000}` (path relative to the cache root; `.mp3` or `.wav`) |
| UOL | resolved by the importer: replaced by a deep copy of its target's JSON (a canvas copy keeps the target's page/region and children). Unresolvable UOLs stay `{"$uol": "<path>"}` and are logged |

Every img JSON with canvases also has a root key `"$pages": ["Mob.wz/0100100.img.0.png", ...]` (paths relative to the
cache root). A canvas copied from another img through a UOL references a page appended to this list. Keys starting
with `$` are reserved for the cache format and never collide with WZ names.

With `paths`, only those sub-trees are written (at their normal place in the tree).

Details fixed by the importer (tools/wzimport 0.1.0):

- Requests for the same img from several manifest entries merge: a whole-img request wins, otherwise the union of
  `paths`; a path below another requested path is covered by it. Only canvases inside the written sub-trees are packed.
- A sound file is named after the node that holds the data, so a UOL copy (`Sound.wz/Skill.img/0001000/Use` ->
  `../1001004/Use`) points at the target's file; that file is written even when the target is outside `paths`.
- A canvas copied from another img through a UOL is packed into this img's own pages (so it is in this `$pages`).
- `float` (f32) values are written as the shortest decimal that round-trips as f32 (`flyJumpDec` 0.35, not
  0.3499999940395355); doubles as the shortest f64 decimal.
- A sound whose header is neither MP3 nor PCM is written as `null` (with a warning). If a property has two children
  with the same name, the first is kept (with a warning).

### 5.3 Atlas pages

- Every canvas of an img is decoded to straight-alpha RGBA8 (BGRA4444 nibbles expanded `n * 17`; RGB565 expanded with
  bit replication; 517 blocks expanded to 16x16) and packed into pages of at most 2048x2048 with a 1 px transparent gap.
- A canvas larger than a page gets its own page of exactly its size.
- Identical canvases (same source offset, e.g. UOL targets) are stored once.
- Pixels are never scaled, trimmed or filtered: `w, h` equal the WZ canvas size, so `origin` offsets stay valid.

### 5.4 Audio

MP3 data is written byte-for-byte (`.mp3`). PCM entries are written as `.wav` with a canonical RIFF header built from
the WAVEFORMATEX. Godot loads them at runtime with `AudioStreamMP3.load_from_buffer` / `AudioStreamWAV.load_from_buffer`.

The Unique / Legendary reward-offer cue is `Sound.wz/Game.img/mCardGet`, the original v83 Monster Card sound
selected by the implementation agent after the owner reserved `EnchantSuccess` for future scrolling.
The existing whole-`Game.img` manifest entry already exports it as
`Sound.wz/Game.img/mCardGet.mp3`; the cache reports 2664 ms (tier A). Its use for survivor reward offers is tier C.
`RunScene` preloads the stream, and `LevelUpWindow.open` plays it once if the displayed cards include either high
tier, including boss rewards. Automatic picks that display no window do not play this cue; hover/click retain their
existing UI sounds. The real-cache window test checks the exact stream and voice count, and the debug gallery logs
its advancing playback position and `missing` list. Windowed evidence used the WASAPI driver with `missing=[]`.
The agent verified actual playback through these checks. On 2026-10-15 the owner auditioned the replacement cue
and approved its fit for Unique / Legendary offers, completing listening acceptance.

## 6. Runtime consumption (Godot)

Free Market (#71) selects map 910000000. The map expansion includes its backgrounds, objects, tiles, portal art,
FreeMarket mark and `Sound.wz/Bgm00.img/FloralLife`. NPCs are explicit manifest entries (maps expand life mobs,
not NPCs): `Npc.wz/9030000.img`, `9030100.img`, `9250025.img`, `9000069.img`, plus their String.wz/Npc.img names.
Spec #32 branch imports use private caches per the binding decisions; #71 uses
`C:/Users/itech/Coding/maple-survivors-refs/research/spec32/cache-t71`. No decoded assets are committed.

`Assets` (`scripts/assets/asset_library.gd`):

| Call | Returns |
|---|---|
| `Assets.has_cache()` | the cache exists and its `format` is supported |
| `Assets.img("Mob.wz/0100100.img") -> WzImg` | parsed tree (cached); `WzImg.root`, `WzImg.node("move/0")`, `WzImg.texture(canvas_dict) -> AtlasTexture` |
| `Assets.node("Mob.wz/0100100.img/move/0")` | any node by full path |
| `Assets.anim("Mob.wz/0100100.img/move") -> SpriteAnim` | frames `{texture, origin, delay_s, a0, a1, extras}` for children "0", "1", ...; missing `delay` = 100 ms (tier C, HeavenClient) |
| `Assets.frame("UI.wz/StatusBar.img/gauge/bar") -> SpriteFrame` | one canvas as a frame (icons, UI pieces) |
| `Assets.sound("Sound.wz/Mob.img/0100100/Die") -> AudioStream` | MP3/WAV stream (cached) |
| `Assets.string_name("Mob", 100100)` | `String.wz` lookups (Mob keys are unpadded ints, Skill keys 7-digit, Map keys grouped by region) |

A `SpriteFrame`'s `texture` is the canvas itself (an `AtlasTexture` of its region, made on first use) for Node drawing
(`TextureRect`, `Sprite2D`); batched and RenderingServer drawing uses `page` (the shared atlas page) + `region` instead.

Page textures are loaded on first use with `Image.load_from_file` + `ImageTexture.create_from_image` (0.09 ms per small
PNG measured in an exported build).

## 7. Testing

- `cargo test` builds synthetic WZ archives with the test-only writer (`src/testutil.rs`): header/version hash, both
  string encodings, encrypted offsets, every property type, canvases in formats 1/2/513/517 (plain and block-encrypted),
  UOLs (including `..` chains), Sound_DX8 MP3 and PCM. Tests check decoded values, pixel bytes and origins exactly.
- With `MAPLE_WZ_ROOT` set, integration tests check known v83 facts (Physics.img values, Snail frame sizes/origins, map
  104040000 foothold count 181).
- Godot tests read a tiny cache written by the test itself (no Nexon data), plus `require_cache()` integration tests
  against the real cache.

## Equip and Item windows (#108)

The whole `UI.wz/UIWindow.img` already holds the `Equip` and `Item` window art, `IconBase`, `KeyConfig/icon/0-1`
and the `ToolTip/Equip` label art the windows and the item tooltip draw; `Basic.img` holds `YesNo`, `BtYes`,
`BtNo` and the `ItemNo` stack digits. The manifest adds whole `String.wz/Consume.img` (potion and scroll names and
descriptions; keys are unpadded item ids, `desc` carries literal `\n`) and the `character` entries 1002001 (Metal
Gear, a CpH1H5 full-cover cap), 1002067 (Green Headband, CpH5), 1050018 (Blue Sauna Robe) and 1050049 (Dark Calas,
Longcoats), 1050035 (Brown Starlight) and 1082002 (Work Gloves), so the Cap, Longcoat and Glove categories draw
and the evidence character can wear a hat, an overall and gloves. Equipment names come from `String.wz/Eqp.img`
(`Eqp/<Character.wz folder>/<id>`), use items from `Consume.img/<id>` (InventoryModel.string_path).

## Second-job asset expansion (#53)

The manifest exports whole `Skill.wz/210.img`, `220.img` and `230.img`, including canonical tables, icons and effects
for sibling tickets. Every sound-bearing second-job skill entry is selected: `2101001`-`2101005`,
`2201001`-`2201005`, `2301001`-`2301005`. Original v83 `Sound.wz/Skill.img` has no `2100000`, `2200000` or
`2300000` entry (MP Eater is passive). Reimport without `--force` preserves existing assets and expands the sound
JSON without removing prior selections; no skill behavior is introduced by importing these assets.

Teleport (#60) also selects `Effect.wz/BasicEff.img/Teleport`. A direct dump of the original v83
`Effect.wz` confirms four canvases (62x172, 45x143, 36x116, 33x57), each with `delay=80` ms
(tier A). `Skill.wz/210.img/skill/2101002` contains only the three icons and `level`, so the runtime
uses this shared BasicEff animation at both endpoints. The authorized incremental import wrote only
BasicEff (83 other imgs up to date), adding four canvases without removing existing selections.
