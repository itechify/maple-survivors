# Third-party notices

| Component | Licence | Where |
|---|---|---|
| Godot Engine 4.7.2 | MIT (plus its bundled third-party licences, e.g. zlib, libpng, dr_mp3) | runtime; notices ship with exported builds |
| Rust crates used by `tools/wzimport` | listed in the table below; all MIT, Apache-2.0, Zlib or similar permissive licences | importer binary |

Reference projects consulted for facts only (no code copied): Cosmic (AGPL-3.0), HeavenClient / JourneyClient /
MortalClient / NoLifeStory (AGPL-3.0), Harepacker-resurrected (MPL-2.0), MapleLib (GPL-3.0), WzComparerR2 and
MapleNecrocer (MIT). See `docs/RESEARCH.md` §7.

MapleStory and all of its assets are © NEXON Korea Corporation and NEXON America Inc. They are not part of this
repository and are never redistributed.

## Rust crates in `tools/wzimport` (from `tools/wzimport/Cargo.lock`)

All are permissive (MIT, Apache-2.0, Zlib, 0BSD, Unlicense or Unicode-3.0); none is network-capable (enforced by the
`no_network_deps` test). Licences as declared by each crate's `Cargo.toml` (`cargo metadata`). The importer binary
compiles every crate below except `zlib-rs` (an optional flate2 backend that is only listed in the lock file; flate2
uses the pure-Rust `miniz_oxide` backend) and `libc` (used by `cpufeatures` on non-Windows targets only).

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
