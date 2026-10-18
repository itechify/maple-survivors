//! wzimport: reads original MapleStory v83 `.wz` archives and writes the Maple Survivors asset cache.
//!
//! Contract: docs/ASSET_PIPELINE.md. Everything here is offline: local files in, local files out.
//!
//! Layers, bottom up: `crypto` (keystream, version hash, offsets) -> `reader` (primitives, encrypted strings)
//! -> `archive` (PKG1 header, directory tree) -> `property` (img trees; `sound` headers) -> `uol`, `canvas`
//! -> `atlas`, `export` (one img to JSON + PNG pages + audio) -> `manifest` (what to export), `cache`
//! (index, incremental stamps) -> `import` (the whole run). `wzroot` addresses archives by full WZ path.

pub mod archive;
pub mod atlas;
pub mod cache;
pub mod canvas;
pub mod crypto;
pub mod dump;
pub mod error;
pub mod export;
pub mod import;
pub mod json;
pub mod manifest;
pub mod property;
pub mod reader;
pub mod sink;
pub mod sound;
pub mod source;
pub mod uol;
#[cfg(target_arch = "wasm32")]
pub mod wasm;
pub mod wzroot;
pub mod zip;

#[cfg(test)]
mod source_tests;
#[cfg(test)]
mod tests;
#[cfg(test)]
pub mod testutil;

pub use error::{Result, WzError};
pub use sink::{FileSink, Sink};
pub use source::{NamedSources, ReadAt};

/// Importer version recorded in cache.json; bump it when the output format or decoding changes.
pub const IMPORTER_VERSION: &str = env!("CARGO_PKG_VERSION");
