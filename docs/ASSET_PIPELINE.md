# Asset pipeline

Tree boss manifest additions: Mob9300003 and6220000 automatically include their original Sound.wz/Mob.img
entries; Effect.wz/Summon.img/3 accompanies King Slime's canonical skill200/2. The existing whole MobSkill.img
and UIWindow.img include Dyle's repeat-marked immunity icon and both MobGage icons. No decoded art is committed.
The stunned-mob stars (#187): `Skill.wz/111.img` with `paths: ["skill/1111008/mob"]` in the main manifest (Hero's Shout;
the same three frames are the `mob` node of every v83 stunning skill, e.g. 510.img 5101002, so a later Pirate fragment
that imports a whole stunning-skill book need not repeat it).

The game renders the player's own MapleStory v83 data. Nothing proprietary is in this repository. A local, offline
importer (`tools/wzimport`, Rust) reads the original `.wz` archives and writes an **asset cache** that the Godot runtime
loads. This document is the contract between the two.

## 1. What you need

A GMS v83 install, i.e. the `.wz` files from the official v83 installer `MapleGlobal-v83-setup.exe`
(Feb 2010, `Wizet` PKG1 archives, encrypted version `0x00AC`). These files are needed:
`Base.wz Character.wz Effect.wz Etc.wz Item.wz Map.wz Mob.wz Morph.wz Npc.wz Skill.wz Sound.wz String.wz UI.wz` (`Morph.wz` since
#194: Oak Barrel's barrel).

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

### 2.1 Portable importer and ZIP input (#132)

`wzimport import --wz <file.zip> --manifest <manifest.json> --out <private-cache>` also accepts a ZIP. Entries may
be nested (`83/Mob.wz`); archive basenames must be unique. ZIP and ZIP64 stored/deflated entries are supported.
Encrypted entries, other compression methods and multi-disk ZIPs fail with readable errors. ZIP imports are fresh
imports (no mtime-based skip); folder imports keep their existing incremental behaviour. Nothing changes the manifest
or the cache format. Any PKG1 archive with the GMS v83 version hash is accepted, including edited archives; there
is no known-file hash list. Native inspection commands retain version autodetection for other WZ versions.

The public Rust boundaries are `ReadAt` (`len() -> u64`, `read_exact_at(offset, &mut [u8]) -> io::Result<()>`),
`NamedSources` (`BTreeMap<String, Arc<dyn ReadAt>>`), and `Sink` (`create_dir(relative)`,
`write_file(relative, bytes)`, both returning `wzimport::Result<()>`). `File` implements `ReadAt`; `FileSink` uses
the existing atomic filesystem writer. `WzArchive::from_reader(name, reader, version)` reads an injected archive;
`zip::zip_sources(reader)` produces named readers. `import::import_sources(sources, manifest_json, sink, progress)`
imports them; progress implements `Progress::update(current_img, done, total) -> Result<()>` (closures work).
`zip::zip_sources_with_options(reader, ZipOptions)` additionally accepts shared `stats: Arc<Mutex<ZipStats>>`
counters (see `zip_stats` below). Deflated entries always use the bounded forward decoder; a host scratch store was
measured and not adopted (2.3).
Missing archives, including dependencies found while expanding maps/mobs, fail with names such as
`Effect.wz, Sound.wz not found in this source`. Errors while opening archives retain their underlying reader error.
Native reader/sink/progress implementations must be `Send + Sync`; wasm callbacks stay in one worker.

Portable imports always export the requested selection. They use reproducible index provenance (`wz_root` and
`created` empty, source `mtime` zero, `stats.seconds` zero), without accessing a platform clock. Native folder imports
retain their normal provenance and timings. The host owns staging, replacement and removal of obsolete files for
portable imports. It must treat an error/report with errors as a failed import and must not start the engine on it.

### 2.2 Wasm build and worker API

Prerequisites: Rust with `wasm32-unknown-unknown`, and `wasm-bindgen-cli` matching the locked `wasm-bindgen` crate
(currently **0.2.105**, pinned together with `js-sys` 0.3.82). Install the dev tools, then build:

```bash
rustup target add wasm32-unknown-unknown
cargo install wasm-bindgen-cli --version 0.2.105 --locked
bash scripts/build_wasm.sh [output-directory]    # default: _scratch/wasm/
# Rust-only compile check (without JS glue):
cargo build --locked --manifest-path tools/wzimport/Cargo.toml --lib \
  --target wasm32-unknown-unknown --no-default-features
```

Use Git Bash for these scripts on Windows. The build script checks the tool version against Cargo.lock, honours
`CARGO_TARGET_DIR`, and emits `wzimport.js`, `wzimport_bg.wasm` and TypeScript declarations into the chosen output
directory. These are generated artifacts; never commit them. Cargo's default-on `parallel` feature enables rayon
for native builds. The wasm implementation is sequential even if the feature is accidentally enabled; the supported
build command disables it. Rust includes no browser readers, requests or networking dependencies. The adapter
only invokes host callbacks, using [wasm-bindgen](https://wasm-bindgen.github.io/wasm-bindgen/).

In the web export the build is part of `bash scripts/export.sh --web` (docs/ARCHITECTURE.md section 10.3): it runs
`scripts/build_wasm.sh` into `WASM_DIR` (default `_scratch/wasm/`) and copies `wzimport.js` and `wzimport_bg.wasm` next
to `index.html`, where `import_worker.js` loads them. The CI workflow (`.github/workflows/pages.yml`) installs the
wasm target and the `wasm-bindgen-cli` version read from `Cargo.lock`, so the glue always matches the locked crate. The
wasm-only crates (`wasm-bindgen`, `js-sys` and their build macros) are in `WZIMPORT_LICENSES.txt` beside the site, which
`export.sh --web` refuses to finish without. No WZ data and no decoded cache is ever part of the export:
`scripts/check_web_artifact.sh` fails the build on a `.wz`, `.img`, `*.img.json`, atlas `*.N.png`, `.mp3`/`.wav` or any
file starting with the WZ signature.

The ES module exports default async `init` and synchronous **`importWz`** (the JS name avoids the `import` keyword):

```js
import init, { importWz } from './wzimport.js';
await init(); // resolves wzimport_bg.wasm beside the JS module
// Reader = { length: number, readAt(offset: number, length: number): Uint8Array }
const sources = { archives: { 'Mob.wz': mobReader, 'Sound.wz': soundReader /* ... */ } };
// Alternatively, exactly one ZIP reader: const sources = { zip: zipReader };
const report = JSON.parse(importWz(sources, manifestJson, {
  createDir(relativePath) { /* create a directory record, including '' for the cache root */ },
  writeFile(relativePath, bytes) { /* enqueue an owned Uint8Array into the host's destination */ }
}, (currentImg, done, total) => {
  postMessage({ currentImg, done, total });
}));
// Await all host writes/transactions before reporting success or starting Godot.
```

Reader lengths and offsets are nonnegative JS safe integers (numbers, not BigInt). `readAt` receives at most 64 KiB
per call and must return exactly that many bytes synchronously. All callbacks may throw an Error or a string;
the API throws a readable string, including context. Callback promises are unsupported (sink/progress promises
are rejected). Progress fires after each img job, `done = 1..total`; there are no progress events for a zero-job
manifest or while expanding its dependencies. The returned JSON string contains `index`, `written`, `warnings`,
`unresolved_uols`, `uols_resolved`, and `uols_external`. Per-img failures throw a joined error string.
The additive `zip_stats` report field contains `decoder_resets` and `bytes_inflated` (uncompressed bytes produced,
including bytes discarded during forward skips/replay); both are zero for non-ZIP input or stored entries.

`createDir` receives each cumulative parent (duplicates are allowed); `writeFile` receives a validated, slash-separated
relative cache path and a JS-owned copy of bytes, safe to retain after returning. No absolute cache root or browser
filesystem is baked into Rust. #133 chooses `/userfs/MapleSurvivors/asset_cache/v83` and creates all its ancestor
records in IndexedDB while no engine is mounted. Its worker supplies the synchronous readers and queues/flushes
IndexedDB writes. Reader callbacks may depend on `this`, which is bound to their reader object; sink callbacks are
bound to their sink object. Report progress from the worker with `postMessage`, since the import itself is synchronous.

### 2.3 ZIP memory trade-off

The ZIP reader scans the central directory using small records (the end search is at most 65,557 bytes), then
exposes stored entries as offset views. A deflated entry keeps a forward raw-DEFLATE decoder with a 64 KiB
compressed input buffer and the decoder's fixed-size history. Reads ahead discard through a 64 KiB scratch buffer;
a backward read resets the decoder and replays from the entry start. No inflated entry, full compressed archive,
spill file or archive-sized wasm allocation is retained. Each active entry has constant decoder/buffer overhead
(roughly a few hundred KiB), whether its WZ is 480 MiB or 640 MiB. This favours bounded memory and portability over
CPU time: repeated backward reads can repeatedly decompress most of a large entry. Stored ZIPs/folder readers are
faster for random access. ZIP metadata is used for positional access; this is not a full-entry CRC verification pass.

Map dependency reads, currently available mob/link dependency reads, and export jobs are ordered by archive and
img offset where their order is free. Export reports retain their original name order; output bytes are unchanged.
Native replay readers advertise `ReadAt::prefers_sequential()` so rayon cannot undo the forward traversal with
concurrent seeks. Native folder/stored readers retain parallel exports. Dependency discovery, WZ metadata
and external UOL targets can still require backwards reads; sorting alone cannot eliminate replay.

Host scratch storage (inflate each used deflated entry once into host temporary storage, then read from it) was
prototyped and measured in #132b (below) and not adopted: it saves about 4 s of 18 s for about 1.78 GiB of temporary
storage, so the prototype was removed and the bounded replay path is the only one.

WZ directory records are read at their own positions, including sparse layouts in edited archives. Each local
metadata read window starts at 4 KiB and is capped at 16 MiB; oversized metadata records fail explicitly instead of
buffering an entire WZ. The import additionally holds one img's compressed bytes, parsed tree, decoded canvases/atlas pages
and any external UOL target imgs needed for that job. Peak memory therefore depends on the largest requested img,
not just the input buffer; it does not include a whole 480–640 MiB WZ. JS reader fallbacks and queued sink writes
have their own host memory costs. The host must dispose of a failed worker/staging cache and flush successful writes.

Validation on the dev PC (#132, Node 24, release wasm): a generated 640 MiB sparse WZ with its img at the end,
inside a 652,228-byte deflated ZIP, imported with a peak wasm linear memory of 1,507,328 bytes (1.4 MiB). This checks
the inflation strategy, not a real img's decoding cost. The complete real v83 manifest (157 imgs) peaked at
266,469,376 bytes (254.1 MiB); all 484 asset files matched the native importer byte for byte, with zero warnings.
In both checks each JS reader call was at most 65,536 bytes. The native before/after `cache.json` also matched after
excluding only `created` and `stats.seconds`; synthetic portable folder/stored-ZIP/deflated-ZIP caches matched
including `cache.json`. The external harness and private outputs stay outside the repo; these are Node worker-API
checks, not browser/storage/UI QA (owned by #133/#136).

Rust synthetic tests compare complete caches from folder, stored-zip and deflated-zip sources and check the physical
img traversal order.

Follow-up #132b timing (2026-10-17, Ryzen 7 7800X3D, Windows, Node 24.21.0, release builds): the full current
manifest's 12 original v83 archives were packed with 7-Zip Deflate at normal compression (`-tzip -mm=Deflate -mx=5`),
1,907,592,640 bytes uncompressed / 1,694,345,144 bytes zipped. Each run imports all 157 imgs, synchronously compares
all 484 asset files with the previous native output, and reports zero warnings. Native measurements use the same
portable API with `--no-default-features` to match wasm's sequential execution. The benchmark sink validates output
instead of persisting another asset cache; times include those comparisons and, for scratch, temporary file I/O.
These are one-run warm-filesystem measurements. Importer benchmarks ran serially with this ticket's build/test
work paused; background processes from other worktrees were not controlled. They are not isolated-machine,
browser/OPFS or network timings. The earlier baseline was re-run after compilation finished to avoid that contention.

| Full-manifest strategy | Node wasm seconds | Native seconds | Decoder resets | Bytes inflated |
|---|---:|---:|---:|---:|
| Before offset ordering, bounded replay | 68.87 | 41.11 | 241 | 20,462,604,993 |
| Offset ordering only, bounded replay | 18.07 | 9.46 | 164 | 4,095,533,688 |
| Offset ordering + Node temp-file scratch (prototype, removed) | 13.81 | not measured | 0 | 1,907,592,640 |

Wasm linear-memory peaks were 268,042,240 / 267,059,200 / 266,338,304 bytes respectively; host read calls never
exceeded 65,536 bytes. The scratch run created and closed exactly 12 handles and wrote 1,907,592,640 temporary bytes
(about 1.78 GiB). Its asset files and portable `cache.json` matched both replay variants byte for byte. Sorting alone
cuts inflated work by 80%; scratch eliminates the remaining replay at the cost of fully inflating and retaining
each used archive in host storage, even if the manifest needs only a few of its imgs. A JS in-memory scratch would
pay that 1.78 GiB in host RAM instead. This is why scratch was not adopted and the bounded no-scratch path is the only one.
The private ZIP, Node/native harnesses and JSON measurements are outside the repo under
`maple-survivors-refs/research/spec130/t132/round2/`; no proprietary input or decoded output is committed.
Follow-up validation: 60 Rust tests passed (including all 17 real-data tests with `MAPLE_WZ_ROOT` set), with no skips;
all 13 source-boundary tests also passed without default features (the wasm callback script and the scratch tests have since been removed with the prototype).
The isolated full Godot suite ran 822 tests: 816 passed, six failed, zero skipped. The six failures are the existing
#103 key-config/key-window/run-scene/Teleport binding family documented in the spec's integration baseline.
### 2.4 Web import sources (#133)

The web shell (`web/import_worker.js`, docs/ARCHITECTURE.md 10.2) feeds `importWz` from three kinds of source. The
worker is created per import and terminated afterwards; the importer's memory goes with it. The source is always one
the player picks or types (one source per import); the repo, the site and these docs name no host and no default
address, and the page requests nothing from any address the player has not entered.

| Source | `importWz` sources | Reader |
|---|---|---|
| Folder (`showDirectoryPicker` or `<input webkitdirectory>`) | `{archives}`: the archives the manifest needs, matched case-insensitively in the chosen folder (or one folder level below it) | `File` slices through `FileReaderSync`, one call per importer read |
| Zip (file picker or drop) | `{zip}` | the same `File` reader; stored and deflated entries both work |
| URL: folder base (`<base>/Mob.wz`) or a `.zip` | `{archives}` or `{zip}` | host supports `Range`: synchronous `XMLHttpRequest` with `Range` behind a block cache (1 MiB aligned blocks, 16-block LRU, adjacent missing blocks fetched in one request); host does not: the whole file is streamed into a `Blob` first (browsers may keep it on disk) and read like a folder file |

The archives an import needs are derived from the manifest (`requiredArchives` in `web/lib.js`): the archive of every
named img, `Map.wz` and `Sound.wz` when there are maps (backs, tiles, objs, music), `Mob.wz` and `Sound.wz` for mobs,
`Character.wz` for characters, `Item.wz` for items. For the shipped manifest that is the same 13 archives the desktop
import reads. The sink only queues (`createDir`, `writeFile`); after `importWz` returns the worker deletes the old cache
records and writes the new ones into IndexedDB (cache.json last), so a failed import leaves the old cache untouched
until the write phase, and an interrupted write leaves no `cache.json`. Scratch storage for deflated zips was measured
(2.3) and not adopted: 13.8 s against 18 s does not justify about 1.78 GiB of temporary OPFS storage, so deflated zips
use the offset-ordered bounded replay.

A re-import for missing imgs is a complete import of the manifest; the importer has no incremental mode in portable
mode, and a partial manifest would write partial copies of imgs shared between entries (`MapHelper.img`, `Mob.img`).
The shell's manifest check (`assessCache`) is exact for the imgs the manifest names and for the files every listed img
needs, not for dependencies the importer derives by reading WZ data.

Browser measurements (Chrome 155, dev PC, local files and a localhost host, the full manifest: 157 imgs, 485 files,
about 150 MB read, 95 MB stored in IndexedDB; whole-import time as the worker reports it, including the write):

| Source | Time | Notes |
|---|---:|---|
| Folder (`<input webkitdirectory>`) | 6.7 s | 2,841 reads, 6.2 s importing + 0.5 s writing |
| Stored zip (1.8 GB) | 7.1 s | |
| Deflated zip (1.6 GB, #132b offset-ordered reads) | 44.5 s | 56,695 reads, 3.7 GB read from the blob |
| URL folder, ranged | 6.9 s | 337 requests, 348 MB transferred (block-cache read amplification about 2.3x) |
| URL `.zip`, ranged (stored) | 7.1 s | 379 requests, 402 MB |
| URL folder, no Range support | 10.2 s | 1.9 GB downloaded whole (about 4.2 s of it before importing) |
| Folder through a stored `FileSystemDirectoryHandle` (OPFS stand-in) | 11.7 s | |

The localhost host has no network latency or bandwidth limit, so the URL rows only show request counts and bytes.

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
| `character[]` | body `00002000` -> `Character.wz/00002000.img`; head `12000`; face `2xxxx` -> `Character.wz/Face/000xxxxx.img`; hair `3xxxx` -> `Hair/`; equips by `id/10000`: 100 Cap, 101-103 Accessory, 104 Coat, 105 Longcoat, 106 Pants, 107 Shoes, 108 Glove, 109 Shield, 110 Cape, 111 Ring, 130-170 Weapon; the spec #33 equipment drop list (`survivor/equipment_drops/<line>.json`, #109) adds every dropped cap, coat, longcoat, pants, shoes, glove, wand and staff here, whole imgs (info, `iconRaw` for the ground icon, and the drawing frames) |
| `items[]` | `Item.wz/<Type>/<id/10000 as 4 digits>.img/<8-digit id>` (Type by id/1000000: 2 Consume, 3 Install, 4 Etc, 5 Cash, 9 Special: the meso coins) |

### 4.1 Include fragments (`game/data/asset_manifest.d/<line>.json`)

Pirate (#186): `pirate.json` owns whole Skill.wz 500/510/520 books, their active-skill Sound.wz nodes, Kyrin
1090000 and her String.wz name, regular knuckles/guns 1482000-9 / 1492000-9, and bullets 2330000-2. Kyrin moved
from the main manifest; the first knuckle, gun and bullets moved from `common`. Shared afterimages and Weapon.img
sounds remain in `common`. The five survivor `pirate.json` line files ship through the existing export filter.

`asset_manifest.json` keeps the job-neutral entries (maps, mobs, UI, effects, the creation weapons,
items, the shared equipment). Everything that belongs to one job line lives in a fragment beside it, so parallel class
specs each add their own file and do not conflict on the main manifest. A fragment has the same shape as the main file,
plus a `_doc` saying what it holds; `format` may be left out (when present it must be 1) and unknown keys are errors.

| File | Holds |
|---|---|
| `asset_manifest.json` | shared: everything not listed below |
| `asset_manifest.d/common.json` | what every weapon line shares (#154): the `Character.wz/Afterimage` imgs of the non-Warrior families (`swordOL`, `mace`, `bow`, `crossBow`, `gun`, `knuckle`; variant `0` only) with the `hit.img` sparks (sword1/2, mace1/2), the whole `Sound.wz/Weapon.img`, and one representative weapon item per non-Warrior family for the weapon gallery and tests (`character[]` 1332000 dagger, 1452000 bow, 1462000 crossbow, 1472000 claw, 1482000 knuckle, 1492000 gun; the creation weapons stay in the main file, wands and staves in `magician.json`, every Warrior weapon in `warrior.json`); the ammo items (#155, `items[]`: arrows 2060000-2060003 and 2061000-2061003, stars 2070001-2070006 and 2070015, bullets 2330000-2330002; info, icon and the `bullet` flight animation) |
| `asset_manifest.d/beginner.json` | `Skill.wz/000.img`; `Sound.wz/Skill.img` `0001000`/`0001001`/`0001002` and `1001004` (Three Snails' UOL target) |
| `asset_manifest.d/magician.json` | `Skill.wz/200.img`, `210`, `220`, `230`; their `Sound.wz/Skill.img` paths (`2001002`-`2301005`); instructor Grendel (`String.wz/Npc.img` `1032001`, `Npc.wz/1032001.img`); the Teleport effect (`Effect.wz/BasicEff.img` `Teleport`); the 212 `character[]` equipment ids whose canonical `reqJob` is the Magician bit (wands, staves, robes, hats, gloves, shoes; all in `survivor/equipment_drops/magician.json`) |
| `asset_manifest.d/warrior.json` | spec #151 #158: the 37 non-cash `Character.wz/Shield` items a Warrior can wear (`reqJob` 1, or 0 for any job); #159: the 88 Warrior-bit weapons of `survivor/equipment_drops/warrior.json` (sword 130xxxx/140xxxx, axe 131/141, blunt 132/142, spear 143, polearm 144), which includes the Two-handed Sword `Weapon/01402000` the shield's two-handed rule is tested with, and the `Afterimage` imgs those weapons name that no other fragment lists (`swordOS`, `swordTS`, `swordTL`, `axe`, `spear`, `poleArm`, variant 0; #154 left them here, so `common.json` does not list them); #163: the skill book `Skill.wz/100.img` whole (the five Warrior skills with icons, effects and hit art) and `Sound.wz/Skill.img` `1001003` and `1001005` (Power Strike's `1001004` sound is in `beginner.json`) and, for the second job (spec #165 #180), `Skill.wz/110.img`, `120.img` and `130.img` whole plus the `Sound.wz/Skill.img` nodes of the 12 active second-job skills (`1101004`-`1101007`, `1201004`-`1201007`, `1301004`-`1301007`; the 12 passives have no sound node, and the importer errors on a requested path that does not exist) (the five advancement weapons `1302008`, `1312005`, `1322014`, `1432002` and `1442001` are in the 88-weapon list); and the two Lv 10 advancement grants (owner change after the spec): the Beginner Warrior's sword `Weapon/01302077` and the Steel Pipe `Weapon/01322006` (the granted Spear `01432000` is in the 88-weapon list) (a later ticket that needs the same item moves or removes it: duplicates across files are an error) |

Why some Beginner-ish entries stay shared: the creation weapons are used by every weapon line, the instructors (Warrior `1022000`, Bowman `1012100`, Thief `1052001`, Pirate `1090000`; the job window draws all four
while it lists them) stay in the main file, and equipment with `reqJob` 0 (any job) is shared. Move an entry to its line's fragment when that line
becomes playable.

- **Merge:** `wzimport import --manifest M` (and every other reader: `AssetManifest` in GDScript, `wzimport manifest` for
  the web export) reads `M` and then every `*.json` in the sibling folder named after it (`asset_manifest.json` ->
  `asset_manifest.d/`, a missing folder is fine), sorted by file name, appending each file's lists after the main
  file's. `Manifest::load` / `Manifest::merge` in `tools/wzimport/src/manifest.rs` define the rules; the GDScript
  (`game/scripts/assets/asset_manifest.gd`) and JS (`web/dev/manifest_files.mjs`) twins follow them and are tested the same.
- **Duplicates:** a key listed in two *different* files is an error naming both files, so two specs cannot silently
  claim the same entry. Keys: an `imgs[]` entry with `paths` is keyed per (img, path), a whole-img entry by img (a whole-img
  entry in one file and sub-paths of the same img in another also conflict); `maps`/`mobs`/`character`/`items` by id;
  `mapimgs` by path. Different paths of the same img in different files are fine (the importer unions them, which is how
  each line adds its own `Sound.wz/Skill.img` skill ids). A repeat inside one file is tolerated, as it always was.
- **Adding a line (a class spec):** create `game/data/asset_manifest.d/<line>.json` with a `_doc`, put the line's skill
  books (`Skill.wz/<job>.img`), its `Sound.wz/Skill.img` paths, instructor NPC and line-only equipment in it, and delete
  any of those ids from the shared file in the same change. If the importer reports `listed in both`, the entry is already
  claimed: leave it in the owner's file, or move it to the shared file when both lines use it.
- **Golden:** `tools/wzimport/tests/fixtures/manifest_golden.txt` is the sorted list of every selection the shipping
  manifest makes (`img <img> *`, `img <img> <path>`, `map|mapimg|mob|character|item <id>`), captured from the single-file
  manifest before the split; `cargo test` fails if `asset_manifest.json` plus its fragments select anything else (and
  `web/dev/test/manifest_merge.test.mjs` checks the same file from JS). The import output of the split manifest was
  compared with the single-file manifest's on the real v83 data and was byte-identical except `cache.json`'s timestamp
  and seconds. When a class spec intentionally adds assets, regenerate the golden in the same change:
  `UPDATE_MANIFEST_GOLDEN=1 cargo test --manifest-path tools/wzimport/Cargo.toml shipping_manifest`, then review the diff:
  it must contain only the added lines.
- **Where fragments must travel:** the Windows build merges them inside the pck (`import_screen.gd` writes the merged
  `user://import/asset_manifest.json` for the child importer), so `game/export_presets.cfg` must include
  `data/asset_manifest.d/*.json` (`scripts/export.sh` warns when it does not mention `asset_manifest.d`). The web build ships ONE file: `export.sh --web`
  writes the merged manifest with `wzimport manifest --manifest game/data/asset_manifest.json --out <dir>/asset_manifest.json`
  because the page cannot list a folder; `web/shell.js` is unchanged.

The 116 curated cash equipment ids of `game/data/survivor/cash_items.json` (spec #34) are in `character[]` (caps,
accessories, coats, longcoats, pants, shoes, gloves, shields, capes and `Weapon/01702xxx` covers). The importer resolves
their UOLs (most covers reach their 37/38 art through links to another weapon type); the few it cannot resolve (some
rare stances of overalls 1052135 and 1052194: heal, prone, shoot, stab; their link targets are missing in v83 itself)
stay `$uol` nodes, so those sleeves are not drawn in those stances. `AvatarRenderer` follows any `$uol` that does
resolve through `WzImg.node`.
`Etc.wz/Commodity.img` is exported whole so a test can check each catalog price and SN.
The Cash Shop screen (#118) adds `UI.wz/CashShop.img` (`Base`, `CSChar`, `CSInventory`, `CSTab`, `CSList`, `CSStatus`, `CSNotice`), the
three pet species (`Item.wz/Pet/5000000-5000002.img` `info`: icons) and `String.wz/Pet.img` for them, and the four pet equips
`Character.wz/PetEquip/01812002-01812005.img` (`info`: icons; their names are already in `String.wz/Eqp.img`).

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
selected by the implementation agent after the owner reserved `EnchantSuccess` for scrolling (now played by #110).
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
not NPCs): `Npc.wz/9030000.img`, `9030100.img`, `9250025.img`, `9000069.img`, plus their String.wz/Npc.img names. The four scroll
NPCs of the shops (#111) are the same kind of entry: `Npc.wz/1032103.img` (El Moth), `2022002.img` (Barun),
`1052104.img` (Tulcus) and `2041016.img` (Vega), with their `String.wz/Npc.img` paths.
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

## Scrolls (#110)

The manifest adds whole `Item.wz/Consume/0204.img` (the scrolls: `info/success`, `info/cursed` for the dark ones, the
`inc*` stats and the icons; 754 entries, only the ids in `game/data/survivor/scrolls/<line>.json` are used) and
`Enchant` to the `Effect.wz/BasicEff.img` paths (`Enchant/Success` and `Enchant/Failure`, 21 and 16 frames at 50 ms).
`Sound.wz/Game.img` (`EnchantSuccess`, `EnchantFailure`) and `String.wz/Consume.img` (scroll names and descriptions)
were already whole. No scroll in the 0204 img carries `info/slotMax`; stacks use 100. `DataRepo.scroll_info` copies
only the numbers a scroll needs (`success`, `cursed`, `slotMax`, `inc*`) into `setup.scroll_info` ({id: info}); a
roster scroll absent from the cache is listed in `missing`. After pulling this change re-import
(`scripts/import.sh`) so the Item.wz and Enchant entries appear.

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
