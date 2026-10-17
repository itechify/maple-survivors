//! Cache output boundary. Paths are relative to the root chosen by the host.

use crate::source::HostBound;
use crate::{Result, WzError};
use std::path::{Path, PathBuf};

/// A host destination. Writes must consume/copy bytes before returning, never retain a wasm view.
pub trait Sink: HostBound {
    fn create_dir(&self, relative: &str) -> Result<()>;
    fn write_file(&self, relative: &str, bytes: &[u8]) -> Result<()>;
    /// Native incremental imports remove surplus atlas pages. Fresh host imports need no cleanup.
    fn remove_stale_pages(&self, _img: &str, _from: usize) {}
}

/// Filesystem output, retaining native atomic file replacement and incremental page cleanup.
pub struct FileSink(pub PathBuf);
impl Sink for FileSink {
    fn create_dir(&self, relative: &str) -> Result<()> {
        let path = self.0.join(relative);
        std::fs::create_dir_all(&path).map_err(|e| WzError::io(path, e))
    }
    fn write_file(&self, relative: &str, bytes: &[u8]) -> Result<()> {
        crate::export::write_file(&self.0, relative, bytes)
    }
    fn remove_stale_pages(&self, img: &str, from: usize) {
        crate::export::remove_stale_pages(&self.0, img, from)
    }
}
impl FileSink {
    pub fn new(root: impl AsRef<Path>) -> Self {
        Self(root.as_ref().to_path_buf())
    }
}

/// Validate a cache path, create every parent, then write the file through the host boundary.
pub fn write(sink: &dyn Sink, relative: &str, bytes: &[u8]) -> Result<()> {
    if let Some(bad) = relative.split('/').find(|c| crate::export::bad_file_component(c)) {
        return Err(WzError::Other(format!(
            "{relative}: {bad:?} is not a valid file name on Windows"
        )));
    }
    for (i, _) in relative.match_indices('/') {
        sink.create_dir(&relative[..i])?;
    }
    sink.write_file(relative, bytes)
}
