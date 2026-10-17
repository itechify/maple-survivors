# Third-party notices

| Component | Licence | Where |
|---|---|---|
| Godot Engine 4.7.2 | MIT (plus its bundled third-party licences, e.g. zlib, libpng, dr_mp3) | runtime; `scripts/export.sh` (and `export.sh --web`) writes the engine's licence, its components' copyrights and their licence texts to `GODOT_LICENSES.txt` next to the exported exe or the web build's `index.html` |
| Arimo (variable font, `game/assets/fonts/arimo/Arimo-Variable.ttf`) | SIL Open Font License 1.1, Copyright The Arimo Project Authors (https://github.com/googlefonts/arimo); licence text in `game/assets/fonts/arimo/OFL.txt`, taken with the font from the `ofl/arimo` folder of google/fonts | the web build's text: bundled as the fallback for the Arial/Tahoma/Dotum `SystemFont`s (`MapleFonts`), because a browser has no system fonts; unmodified. `scripts/export.sh` (also `--web`) copies the licence to `ARIMO_OFL.txt` next to the exported exe or `index.html` |
| Rust crates used by `tools/wzimport` | listed in the table below; all MIT, Apache-2.0, Zlib or similar permissive licences | importer binary and the web build's wasm importer; `scripts/export.sh` collects every crate's licence files (all targets, so the wasm-only crates too) into `WZIMPORT_LICENSES.txt` next to `wzimport.exe` or `index.html`, and copies this file there; the web import screen links all four notice files |

Reference projects consulted for facts only (no code copied): Cosmic (AGPL-3.0), HeavenClient / JourneyClient /
MortalClient / NoLifeStory (AGPL-3.0), Harepacker-resurrected (MPL-2.0), MapleLib (GPL-3.0), WzComparerR2 and
MapleNecrocer (MIT). See `docs/RESEARCH.md` §7.

MapleStory and all of its assets are © NEXON Korea Corporation and NEXON America Inc. They are not part of this
repository and are never redistributed.

## Rust crates in `tools/wzimport` (from `tools/wzimport/Cargo.lock`)

All are permissive (MIT, Apache-2.0, Zlib, 0BSD, Unlicense or Unicode-3.0); none is network-capable (enforced by the
`no_network_deps` test). Licences as declared by each crate's `Cargo.toml` (`cargo metadata`). Rows marked wasm-only
and their supporting proc macros compile for the wasm library; rayon and its worker dependencies are optional and
disabled by the wasm build script. `zlib-rs` is a lock-file-only optional flate2 backend (we use `miniz_oxide`),
and `libc` is used by `cpufeatures` on non-Windows targets only. The separately installed `wasm-bindgen-cli` is a
development tool, not part of the importer's dependency graph or distributed worker.

| Crate | Version | Licence | Use |
|---|---|---|---|
| aes | 0.8.4 | MIT OR Apache-2.0 | direct: GMS keystream (AES-256-ECB) |
| anyhow | 1.0.104 | MIT OR Apache-2.0 | direct: CLI errors |
| clap | 4.6.7 | MIT OR Apache-2.0 | direct: command line |
| flate2 | 1.1.10 | MIT OR Apache-2.0 | direct: zlib inflate (miniz_oxide backend) |
| png | 0.18.1 | MIT OR Apache-2.0 | direct: atlas page PNGs |
| rayon | 1.12.0 | MIT OR Apache-2.0 | direct: parallel export |
| serde | 1.0.229 | MIT OR Apache-2.0 | direct: manifest / cache.json |
| serde_json | 1.0.154 | MIT OR Apache-2.0 | direct: manifest / cache.json |
| thiserror | 2.0.21 | MIT OR Apache-2.0 | direct: error type |
| wasm-bindgen | 0.2.105 | MIT OR Apache-2.0 | direct, wasm only: worker callback/byte boundary |
| js-sys | 0.3.82 | MIT OR Apache-2.0 | direct, wasm only: functions, objects and typed arrays |
| bumpalo | 3.20.3 | MIT OR Apache-2.0 | transitive (wasm-bindgen build macros) |
| once_cell | 1.21.4 | MIT OR Apache-2.0 | transitive (wasm-bindgen) |
| rustversion | 1.0.23 | MIT OR Apache-2.0 | transitive (wasm-bindgen build macros) |
| syn | 2.0.119 | MIT OR Apache-2.0 | transitive (wasm-bindgen proc macros; alongside the native syn version below) |
| wasm-bindgen-macro | 0.2.105 | MIT OR Apache-2.0 | transitive (proc macro) |
| wasm-bindgen-macro-support | 0.2.105 | MIT OR Apache-2.0 | transitive (proc macro) |
| wasm-bindgen-shared | 0.2.105 | MIT OR Apache-2.0 | transitive (wasm ABI definitions) |
| adler2 | 2.0.1 | 0BSD OR MIT OR Apache-2.0 | transitive |
| anstream | 1.0.0 | MIT OR Apache-2.0 | transitive |
| anstyle | 1.0.14 | MIT OR Apache-2.0 | transitive |
| anstyle-parse | 1.0.0 | MIT OR Apache-2.0 | transitive |
| anstyle-query | 1.1.5 | MIT OR Apache-2.0 | transitive |
| anstyle-wincon | 3.0.11 | MIT OR Apache-2.0 | transitive |
| bitflags | 2.13.2 | MIT OR Apache-2.0 | transitive |
| cfg-if | 1.0.5 | MIT OR Apache-2.0 | transitive |
| cipher | 0.4.4 | MIT OR Apache-2.0 | transitive |
| clap_builder | 4.6.7 | MIT OR Apache-2.0 | transitive |
| clap_derive | 4.6.7 | MIT OR Apache-2.0 | transitive (proc macro) |
| clap_lex | 1.1.1 | MIT OR Apache-2.0 | transitive |
| colorchoice | 1.0.5 | MIT OR Apache-2.0 | transitive |
| cpufeatures | 0.2.17 | MIT OR Apache-2.0 | transitive |
| crc32fast | 1.5.2 | MIT OR Apache-2.0 | transitive |
| crossbeam-deque | 0.8.8 | MIT OR Apache-2.0 | transitive |
| crossbeam-epoch | 0.9.21 | MIT OR Apache-2.0 | transitive |
| crossbeam-utils | 0.8.23 | MIT OR Apache-2.0 | transitive |
| crypto-common | 0.1.7 | MIT OR Apache-2.0 | transitive |
| either | 1.19.0 | MIT OR Apache-2.0 | transitive |
| fdeflate | 0.3.7 | MIT OR Apache-2.0 | transitive |
| generic-array | 0.14.7 | MIT | transitive |
| heck | 0.5.0 | MIT OR Apache-2.0 | transitive (proc macro) |
| inout | 0.1.4 | MIT OR Apache-2.0 | transitive |
| is_terminal_polyfill | 1.70.2 | MIT OR Apache-2.0 | transitive |
| itoa | 1.0.18 | MIT OR Apache-2.0 | transitive |
| libc | 0.2.190 | MIT OR Apache-2.0 | transitive (non-Windows only) |
| memchr | 2.8.3 | Unlicense OR MIT | transitive |
| miniz_oxide | 0.8.9 / 0.9.1 | MIT OR Zlib OR Apache-2.0 | transitive |
| once_cell_polyfill | 1.70.2 | MIT OR Apache-2.0 | transitive |
| proc-macro2 | 1.0.107 | MIT OR Apache-2.0 | transitive (proc macro) |
| quote | 1.0.47 | MIT OR Apache-2.0 | transitive (proc macro) |
| rayon-core | 1.13.0 | MIT OR Apache-2.0 | transitive |
| serde_core | 1.0.229 | MIT OR Apache-2.0 | transitive |
| serde_derive | 1.0.229 | MIT OR Apache-2.0 | transitive (proc macro) |
| simd-adler32 | 0.3.10 | MIT | transitive |
| strsim | 0.11.1 | MIT | transitive |
| syn | 3.0.9 | MIT OR Apache-2.0 | transitive (proc macro) |
| thiserror-impl | 2.0.21 | MIT OR Apache-2.0 | transitive (proc macro) |
| typenum | 1.20.1 | MIT OR Apache-2.0 | transitive |
| unicode-ident | 1.0.27 | (MIT OR Apache-2.0) AND Unicode-3.0 | transitive (proc macro) |
| utf8parse | 0.2.2 | Apache-2.0 OR MIT | transitive |
| version_check | 0.9.5 | MIT/Apache-2.0 | transitive (build script) |
| windows-link | 0.2.1 | MIT OR Apache-2.0 | transitive |
| windows-sys | 0.61.2 | MIT OR Apache-2.0 | transitive |
| zlib-rs | 0.6.8 | Zlib | lock file only (not compiled) |
| zmij | 1.0.23 | MIT | transitive (serde_json float formatting) |

The WZ reader in `tools/wzimport` is original code written from the format description in `docs/ASSET_PIPELINE.md`
and `docs/research/wz-inventory.md`; no third-party WZ library code was ported.
