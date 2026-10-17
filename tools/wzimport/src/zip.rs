//! ZIP central-directory source. Stored entries are views; deflated entries use optional host scratch storage
//! or a bounded forward decoder that replays on backward seeks. No archive-sized Rust allocation is needed.
//! Record layout: PKWARE APPNOTE 6.3.10, https://pkware.cachefly.net/webdocs/casestudies/APPNOTE.TXT

use crate::source::{HostBound, NamedSources, ReadAt};
use crate::{Result, WzError};
use flate2::bufread::DeflateDecoder;
use std::io::{self, BufReader, Read};
use std::sync::{Arc, Mutex};

/// Work performed by ZIP inflation (uncompressed bytes, including discarded replay).
#[derive(Default, Clone, serde::Serialize)]
pub struct ZipStats {
    pub decoder_resets: u64,
    pub bytes_inflated: u64,
}

/// Optional host scratch storage and inflation instrumentation shared with the caller.
#[derive(Default)]
pub struct ZipOptions {
    pub stats: Arc<Mutex<ZipStats>>,
    pub scratch: Option<Arc<dyn Scratch>>,
}

/// Host-owned temporary storage. Entries are created lazily, once, by archive basename.
pub trait Scratch: HostBound {
    fn create(&self, name: &str, length: u64) -> io::Result<Box<dyn ScratchHandle>>;
}

/// Exact positional writes/reads; close releases the handle (also on a failed import).
/// Native hosts can implement this over a temporary file; wasm hosts use synchronous callbacks.
/// Close is attempted once when the reader is dropped; destructor errors cannot be propagated.
pub trait ScratchHandle: ReadAt {
    fn write(&self, offset: u64, bytes: &[u8]) -> io::Result<()>;
    fn close(&mut self) -> io::Result<()>;
}

struct ScratchFile(Box<dyn ScratchHandle>);
impl Drop for ScratchFile {
    fn drop(&mut self) {
        let _ = self.0.close();
    }
}

const CHUNK: usize = 64 * 1024;

fn invalid(message: impl Into<String>) -> WzError {
    WzError::Other(format!("zip: {}", message.into()))
}
fn u16_at(b: &[u8], at: usize) -> u16 {
    u16::from_le_bytes(b[at..at + 2].try_into().unwrap())
}
fn u32_at(b: &[u8], at: usize) -> u32 {
    u32::from_le_bytes(b[at..at + 4].try_into().unwrap())
}
fn u64_at(b: &[u8], at: usize) -> u64 {
    u64::from_le_bytes(b[at..at + 8].try_into().unwrap())
}
fn bytes(r: &dyn ReadAt, at: u64, len: usize) -> Result<Vec<u8>> {
    if at.checked_add(len as u64).is_none_or(|end| end > r.len()) {
        return Err(invalid("truncated entry"));
    }
    let mut b = vec![0; len];
    r.read_exact_at(at, &mut b).map_err(|e| invalid(e.to_string()))?;
    Ok(b)
}

/// Expose every `.wz` entry by basename, including entries in subfolders. Duplicate basenames fail.
/// Supports ZIP/ZIP64 stored and deflated entries; encryption and multi-disk archives are rejected.
pub fn zip_sources(source: Arc<dyn ReadAt>) -> Result<NamedSources> {
    zip_sources_with_options(source, ZipOptions::default())
}

/// Open ZIP entries with instrumentation retained by the caller.
pub fn zip_sources_with_options(source: Arc<dyn ReadAt>, options: ZipOptions) -> Result<NamedSources> {
    let tail_len = source.len().min(65535 + 22) as usize;
    let tail_start = source.len() - tail_len as u64;
    let tail = bytes(source.as_ref(), tail_start, tail_len)?;
    let end = (0..tail_len.saturating_sub(21))
        .rev()
        .find(|&i| tail[i..i + 4] == *b"PK\x05\x06" && i + 22 + u16_at(&tail, i + 20) as usize == tail_len)
        .ok_or_else(|| invalid("central directory not found"))?;
    if u16_at(&tail, end + 4) != 0 || u16_at(&tail, end + 6) != 0 || u16_at(&tail, end + 8) != u16_at(&tail, end + 10) {
        return Err(invalid("multi-disk archives are unsupported"));
    }
    let mut count = u16_at(&tail, end + 10) as u64;
    let mut size = u32_at(&tail, end + 12) as u64;
    let mut at = u32_at(&tail, end + 16) as u64;
    let eocd = tail_start + end as u64;
    if count == 65535 || size == u32::MAX as u64 || at == u32::MAX as u64 {
        let locator = bytes(
            source.as_ref(),
            eocd.checked_sub(20).ok_or_else(|| invalid("missing ZIP64 locator"))?,
            20,
        )?;
        if u32_at(&locator, 0) != 0x07064b50 || u32_at(&locator, 4) != 0 || u32_at(&locator, 16) != 1 {
            return Err(invalid("invalid ZIP64 locator"));
        }
        let record = bytes(source.as_ref(), u64_at(&locator, 8), 56)?;
        if u32_at(&record, 0) != 0x06064b50
            || u64_at(&record, 4) < 44
            || u32_at(&record, 16) != 0
            || u32_at(&record, 20) != 0
            || u64_at(&record, 24) != u64_at(&record, 32)
        {
            return Err(invalid("invalid ZIP64 directory"));
        }
        count = u64_at(&record, 32);
        size = u64_at(&record, 40);
        at = u64_at(&record, 48);
    }
    let central_end = at
        .checked_add(size)
        .filter(|&v| v <= eocd)
        .ok_or_else(|| invalid("central directory out of bounds"))?;
    if count > size / 46 {
        return Err(invalid("invalid entry count"));
    }
    let mut out = NamedSources::new();
    for _ in 0..count {
        if at.checked_add(46).is_none_or(|v| v > central_end) {
            return Err(invalid("truncated directory"));
        }
        let h = bytes(source.as_ref(), at, 46)?;
        if u32_at(&h, 0) != 0x02014b50 {
            return Err(invalid("bad directory signature"));
        }
        let name_len = u16_at(&h, 28) as usize;
        let extra_len = u16_at(&h, 30) as usize;
        let next = at + 46 + name_len as u64 + extra_len as u64 + u16_at(&h, 32) as u64;
        if next > central_end {
            return Err(invalid("entry extends past directory"));
        }
        let name = bytes(source.as_ref(), at + 46, name_len)?;
        let name = String::from_utf8_lossy(&name);
        let basename = name.rsplit(['/', '\\']).next().unwrap_or("");
        if basename.to_ascii_lowercase().ends_with(".wz") {
            if u16_at(&h, 8) & (1 | 64) != 0 {
                return Err(invalid(format!("{name}: encrypted entry")));
            }
            let method = u16_at(&h, 10);
            if method != 0 && method != 8 {
                return Err(invalid(format!("{name}: compression method {method} unsupported")));
            }
            let mut compressed = u32_at(&h, 20) as u64;
            let mut len = u32_at(&h, 24) as u64;
            let mut offset = u32_at(&h, 42) as u64;
            let mut disk = u16_at(&h, 34) as u32;
            if [compressed, len, offset].contains(&(u32::MAX as u64)) || disk == 65535 {
                let extra = bytes(source.as_ref(), at + 46 + name_len as u64, extra_len)?;
                let mut p = 0;
                let mut found = false;
                while p + 4 <= extra.len() {
                    let tag = u16_at(&extra, p);
                    let n = u16_at(&extra, p + 2) as usize;
                    p += 4;
                    if p + n > extra.len() {
                        return Err(invalid("truncated extra field"));
                    }
                    if tag == 1 {
                        let field = &extra[p..p + n];
                        let mut q = 0;
                        for v in [&mut len, &mut compressed, &mut offset] {
                            if *v == u32::MAX as u64 {
                                if q + 8 > n {
                                    return Err(invalid("truncated ZIP64 field"));
                                }
                                *v = u64_at(field, q);
                                q += 8;
                            }
                        }
                        if disk == 65535 {
                            if q + 4 > n {
                                return Err(invalid("truncated ZIP64 disk"));
                            }
                            disk = u32_at(field, q);
                        }
                        found = true;
                        break;
                    }
                    p += n;
                }
                if !found {
                    return Err(invalid("missing ZIP64 sizes"));
                }
            }
            if disk != 0 {
                return Err(invalid("multi-disk entry"));
            }
            let local = bytes(source.as_ref(), offset, 30)?;
            if u32_at(&local, 0) != 0x04034b50 || u16_at(&local, 8) != method || u16_at(&local, 6) & (1 | 64) != 0 {
                return Err(invalid("invalid local header"));
            }
            let start = offset
                .checked_add(30 + u16_at(&local, 26) as u64 + u16_at(&local, 28) as u64)
                .ok_or_else(|| invalid("entry offset overflow"))?;
            if start.checked_add(compressed).is_none_or(|v| v > at.min(central_end)) {
                return Err(invalid("entry data out of bounds"));
            }
            let view = View {
                source: source.clone(),
                start,
                len: compressed,
            };
            let reader: Arc<dyn ReadAt> = if method == 0 {
                if compressed != len {
                    return Err(invalid("stored size mismatch"));
                }
                Arc::new(view)
            } else if let Some(scratch) = &options.scratch {
                Arc::new(ScratchEntry {
                    name: basename.into(),
                    view,
                    len,
                    scratch: scratch.clone(),
                    stats: options.stats.clone(),
                    state: Mutex::new(ScratchState::New),
                })
            } else {
                Arc::new(Inflated {
                    stats: options.stats.clone(),
                    state: Mutex::new(InflateState::new(view.clone())),
                    view,
                    len,
                })
            };
            if out.insert(basename.to_string(), reader).is_some() {
                return Err(invalid(format!("duplicate archive {basename}")));
            }
        }
        at = next;
    }
    Ok(out)
}

#[derive(Clone)]
struct View {
    source: Arc<dyn ReadAt>,
    start: u64,
    len: u64,
}
impl ReadAt for View {
    fn len(&self) -> u64 {
        self.len
    }
    fn read_exact_at(&self, offset: u64, buf: &mut [u8]) -> io::Result<()> {
        if offset.checked_add(buf.len() as u64).is_none_or(|v| v > self.len) {
            return Err(io::ErrorKind::UnexpectedEof.into());
        }
        self.source.read_exact_at(self.start + offset, buf)
    }
}

struct Cursor {
    view: View,
    pos: u64,
}

enum ScratchState {
    New,
    Ready(ScratchFile),
    Failed(String),
}
struct ScratchEntry {
    name: String,
    view: View,
    len: u64,
    scratch: Arc<dyn Scratch>,
    stats: Arc<Mutex<ZipStats>>,
    state: Mutex<ScratchState>,
}
impl ScratchEntry {
    fn inflate(&self) -> io::Result<ScratchFile> {
        let file = ScratchFile(self.scratch.create(&self.name, self.len)?);
        let mut decoder = InflateState::new(self.view.clone()).decoder;
        let mut buffer = [0; CHUNK];
        let mut offset = 0;
        loop {
            let n = decoder.read(&mut buffer)?;
            if n == 0 {
                break;
            }
            self.stats.lock().unwrap().bytes_inflated += n as u64;
            if offset + n as u64 > self.len {
                return Err(io::Error::other("deflated entry exceeds declared length"));
            }
            file.0.write(offset, &buffer[..n])?;
            offset += n as u64;
        }
        if offset != self.len {
            return Err(io::ErrorKind::UnexpectedEof.into());
        }
        Ok(file)
    }
}
impl ReadAt for ScratchEntry {
    fn len(&self) -> u64 {
        self.len
    }
    fn read_exact_at(&self, offset: u64, buf: &mut [u8]) -> io::Result<()> {
        if offset.checked_add(buf.len() as u64).is_none_or(|end| end > self.len) {
            return Err(io::ErrorKind::UnexpectedEof.into());
        }
        let mut state = self.state.lock().unwrap();
        if matches!(*state, ScratchState::New) {
            *state = match self.inflate() {
                Ok(file) => ScratchState::Ready(file),
                Err(e) => ScratchState::Failed(format!("scratch {}: {e}", self.name)),
            };
        }
        match &*state {
            ScratchState::Ready(file) => file.0.read_exact_at(offset, buf),
            ScratchState::Failed(message) => Err(io::Error::other(message.clone())),
            ScratchState::New => unreachable!(),
        }
    }
}
impl Read for Cursor {
    fn read(&mut self, buf: &mut [u8]) -> io::Result<usize> {
        let n = (self.view.len - self.pos).min(buf.len() as u64).min(CHUNK as u64) as usize;
        self.view.read_exact_at(self.pos, &mut buf[..n])?;
        self.pos += n as u64;
        Ok(n)
    }
}
struct InflateState {
    decoder: DeflateDecoder<BufReader<Cursor>>,
    pos: u64,
}
impl InflateState {
    fn new(view: View) -> Self {
        Self {
            decoder: DeflateDecoder::new(BufReader::with_capacity(CHUNK, Cursor { view, pos: 0 })),
            pos: 0,
        }
    }
}
struct Inflated {
    stats: Arc<Mutex<ZipStats>>,
    view: View,
    len: u64,
    state: Mutex<InflateState>,
}
impl ReadAt for Inflated {
    fn prefers_sequential(&self) -> bool {
        true
    }
    fn len(&self) -> u64 {
        self.len
    }
    fn read_exact_at(&self, offset: u64, buf: &mut [u8]) -> io::Result<()> {
        if offset.checked_add(buf.len() as u64).is_none_or(|v| v > self.len) {
            return Err(io::ErrorKind::UnexpectedEof.into());
        }
        let mut state = self.state.lock().unwrap();
        if offset < state.pos {
            self.stats.lock().unwrap().decoder_resets += 1;
            *state = InflateState::new(self.view.clone());
        }
        let mut skip = [0; CHUNK];
        while state.pos < offset {
            let n = (offset - state.pos).min(CHUNK as u64) as usize;
            state.decoder.read_exact(&mut skip[..n])?;
            state.pos += n as u64;
            self.stats.lock().unwrap().bytes_inflated += n as u64;
        }
        state.decoder.read_exact(buf)?;
        state.pos += buf.len() as u64;
        self.stats.lock().unwrap().bytes_inflated += buf.len() as u64;
        Ok(())
    }
}
