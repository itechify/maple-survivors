//! Error type for WZ reading and cache writing.

use thiserror::Error;

/// Everything that can go wrong while reading WZ data or writing the cache.
#[derive(Debug, Error)]
pub enum WzError {
    #[error("resource limit exceeded: {0}")]
    ResourceLimit(String),
    #[error("unexpected end of data at 0x{pos:X} (needed {need} bytes)")]
    Eof { pos: u64, need: usize },
    #[error("format error at 0x{pos:X}: {msg}")]
    Format { pos: u64, msg: String },
    #[error("not found: {0}")]
    NotFound(String),
    #[error("{0}")]
    Other(String),
    #[error("{path}: {source}")]
    Io { path: String, source: std::io::Error },
}

impl WzError {
    /// A format error at absolute position `pos`.
    pub fn format(pos: u64, msg: impl Into<String>) -> Self {
        WzError::Format { pos, msg: msg.into() }
    }

    /// An I/O error annotated with the path it concerns.
    pub fn io(path: impl AsRef<std::path::Path>, source: std::io::Error) -> Self {
        WzError::Io { path: path.as_ref().display().to_string(), source }
    }
}

pub type Result<T> = std::result::Result<T, WzError>;
