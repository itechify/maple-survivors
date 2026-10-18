# wzimport

Offline Rust CLI that reads the player's original MapleStory v83 `.wz` archives and writes the Maple Survivors
asset cache (JSON trees, RGBA8 PNG atlas pages, MP3/WAV audio). The cache format is the contract in
[`docs/ASSET_PIPELINE.md`](../../docs/ASSET_PIPELINE.md) §5. No networking code or network-capable crate is used
(`tests/no_network_deps.rs` checks `Cargo.lock`).

## Usage

```bash
bash scripts/import.sh "C:/Nexon/MapleStory"            # build + import into %APPDATA%/MapleSurvivors/asset_cache/v83
cargo build --release                                    # in tools/wzimport
wzimport import --wz <wz folder> --manifest game/data/asset_manifest.json --out <cache root> [--force]   # also reads game/data/asset_manifest.d/*.json
wzimport manifest --manifest game/data/asset_manifest.json [--out merged.json]   # the merged manifest as one JSON file (web export)
wzimport dump   --wz <wz folder> Mob.wz/0100100.img/move 2     # tree listing (dir, img or node), optional depth
wzimport dump   --wz <wz folder> Map.wz/Back --imgs            # every img below a directory
wzimport ls     --wz <wz folder> Map.wz/Back                   # directory entries: kind, name, size, offset
wzimport canvas --wz <wz folder> Mob.wz/0100100.img/move/0 out.png   # one canvas (UOLs followed); .rgba = raw bytes
```

`--wz` defaults to `$MAPLE_WZ_ROOT`. `import` prints totals, every warning and every error, and exits 1 when there
was an error. It is incremental: an img is skipped when its source archive's size + mtime, the importer version
and the img's exported path set are unchanged and its files still exist; `--force` rewrites everything.

## Design

| Module | Role |
|---|---|
| `crypto` | GMS keystream (AES-256-ECB chained from IV `4D23C72B` x4, grown on demand, shared across threads), version hash, offset decryption |
| `reader` | little-endian cursor: compressed int/long, encrypted strings (ASCII/cp1252 and UTF-16, short and long forms), string blocks |
| `archive` | PKG1 header, v83 check with fallback detection (every version whose hash gives the stored encrypted version, validated by parsing the tree and checking img headers), eager directory tree, positional img reads |
| `property` | img property trees; canvases and sounds keep offsets into the img blob (decoded lazily) |
| `sound` | Sound_DX8 headers: MP3 (82-byte header), PCM (70-byte header, written as RIFF WAV), media types without WAVEFORMATEX (sniffed: ID3/MPEG sync = MP3), anything else = skipped with a warning |
| `canvas` | zlib or block-encrypted data; formats 1, 2, 513, 517 to straight RGBA8 (nibbles `* 17`, RGB565 bit replication) |
| `uol` | fixed-point UOL resolution with deep-copy semantics, `..` relative to the UOL's parent, targets in sibling imgs, cycle guard; unresolved UOLs stay `{"$uol": path}` |
| `manifest` | manifest parsing, include-fragment merge (`asset_manifest.d/*.json`, duplicates are errors) and expansion (maps, mobs + `info/link`, character ids, items); requests for one img are merged |
| `atlas` | shelf packing into pages <= 2048x2048 with a 1 px gap; oversize canvases get their own page |
| `export` | one img: resolve, select `paths`, dedupe canvases by source offset, decode + pack + PNG in parallel, write sounds and JSON (keys in WZ order) |
| `cache`, `import` | `cache.json`, incremental stamps, the parallel run over all imgs |

Choices beyond the contract text (also listed in the importer report):

- Several requests for one img merge: a whole-img request wins, otherwise the union of paths; a path under another
  requested path is absorbed (`mark` covers `mark/Henesys`).
- With `paths`, only canvases inside the written sub-trees are packed.
- A sound file is named after the node that holds the data, so a UOL copy (`Sound.wz/Skill.img/0001000/Use` ->
  `../1001004/Use`) points at the target's file, which is written even when the target is outside `paths`.
- A canvas copied from another img through a UOL is packed into this img's own pages (listed in its `$pages`).
- Floats (`f32`) are written as the shortest decimal that round-trips as f32 (`flyJumpDec` 0.35), doubles as the
  shortest f64 decimal. Duplicate keys inside one property keep the first (with a warning).
- Missing imgs named by the manifest, missing explicit `paths`, and undecodable canvases are errors; missing derived
  dependencies (a back, a mob sound, a link target), unresolved UOLs and skipped sounds are warnings. An img with an
  error is not recorded in `cache.json`, so the next run retries it.
- `cache.json` img entries also carry `sounds` and `bytes` (used for the totals in `stats`).

## Tests

```bash
cargo test                                               # synthetic fixtures only
MAPLE_WZ_ROOT="C:/path/to/v83" cargo test                # + real-data integration tests (tests/real_data.rs)
```

- `src/testutil.rs` (test-only) writes synthetic PKG1 archives: header and version hash, encrypted offsets,
  type-2 shared names, both string encodings including the 127/-128 long forms, inline and offset string blocks,
  every property type, canvases 1/2/513/517 plain and block-encrypted, Sound_DX8 MP3/PCM/headerless/bad, UOLs.
- `src/tests.rs` checks decoded values, exact pixel bytes, origins, UOL copies and guards, atlas regions (inside
  the page, no overlap, 1 px gap, oversize pages), the exact JSON text, `paths` selection, manifest expansion on a
  synthetic map, a full import with incremental skips and `--force`.
- `src/manifest.rs` tests cover the include fragments (`game/data/asset_manifest.d/*.json`, merged in file-name order,
  a key in two files is an error, a missing folder is fine) and check that the shipping manifest plus its fragments
  selects exactly `tests/fixtures/manifest_golden.txt`; regenerate it after an intended change with
  `UPDATE_MANIFEST_GOLDEN=1 cargo test shipping_manifest` (docs/ASSET_PIPELINE.md 4.1).
- `tests/real_data.rs` runs only with `MAPLE_WZ_ROOT` (it prints SKIP otherwise, which proves nothing): all 16
  archives are v83, Physics.img values, Snail and Slime (block-encrypted) frames, 104040000 footholds/bgm, String.wz
  names, CavaBien MP3, PCM sounds, and a real import whose page regions are compared with direct canvas decodes.
- Differential check against the research explorer (`docs/research/wz-inventory.md`): `wzimport dump --imgs` and
  the explorer's dump were identical for every img of all 16 archives (12M+ nodes); the only difference is
  `Sound.wz/BgmGL.img/Amorianchallenge`, which the explorer misreads as a malformed WAVEFORMATEX (it has none; the
  data is an ID3-tagged MP3). Canvas pixels matched byte for byte, except format 517, where the explorer expands
  RGB565 with `* 255 / 31` instead of the contract's bit replication (max difference 1).

Real import of the Phase 1 manifest on the dev PC (16 threads): 58 imgs, 8111 canvases, 58 pages, 83 sounds,
84 MB, 0.3 s (plus the `cargo build` check in `scripts/import.sh`).
