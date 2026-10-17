//! Positional input boundary. Hosts provide bytes; archive decoding has no knowledge of their origin.

use std::fs::File;
use std::io;
use std::collections::BTreeMap;
use std::sync::Arc;

/// A single import source, keyed by archive basename (not a mix of fallback sources).
pub type NamedSources = BTreeMap<String, Arc<dyn ReadAt>>;

/// Native workers share readers/sinks across threads. Wasm hosts are confined to one worker.
#[cfg(not(target_arch = "wasm32"))]
pub trait HostBound: Send + Sync {}
#[cfg(not(target_arch = "wasm32"))]
impl<T: Send + Sync + ?Sized> HostBound for T {}
#[cfg(target_arch = "wasm32")]
pub trait HostBound {}
#[cfg(target_arch = "wasm32")]
impl<T: ?Sized> HostBound for T {}

/// Immutable length and exact positional reads, without changing a shared cursor.
pub trait ReadAt: HostBound {
    fn len(&self) -> u64;
    fn is_empty(&self) -> bool { self.len() == 0 }
    fn read_exact_at(&self, offset: u64, buf: &mut [u8]) -> io::Result<()>;
}

impl ReadAt for File {
    fn len(&self) -> u64 { self.metadata().map(|m| m.len()).unwrap_or(0) }
    fn read_exact_at(&self, mut offset: u64, mut buf: &mut [u8]) -> io::Result<()> {
        while !buf.is_empty() {
            #[cfg(windows)]
            let r = std::os::windows::fs::FileExt::seek_read(self, buf, offset);
            #[cfg(unix)]
            let r = std::os::unix::fs::FileExt::read_at(self, buf, offset);
            #[cfg(not(any(windows, unix)))]
            let r: io::Result<usize> = Err(io::Error::new(io::ErrorKind::Unsupported, "native file reads unavailable on this target"));
            match r {
                Ok(0) => return Err(io::ErrorKind::UnexpectedEof.into()),
                Ok(n) => { buf = &mut buf[n..]; offset += n as u64; }
                Err(e) if e.kind() == io::ErrorKind::Interrupted => {},
                Err(e) => return Err(e),
            }
        }
        Ok(())
    }
}
