//! PKG1 archive: header, version detection, the directory tree and img blobs.
//!
//! The directory tree is parsed eagerly when the archive is opened (it is small: Map.wz has ~5.6k imgs);
//! img blobs are read on demand with positional reads, so one `WzArchive` can be shared across threads.

use crate::crypto::{decrypt_offset, enc_version, version_hash};
use crate::error::{Result, WzError};
use crate::property::{parse_img, Img};
use crate::reader::Reader;
use std::fs::File;
use std::io;
use std::path::{Path, PathBuf};

/// One opened `.wz` archive.
pub struct WzArchive {
    /// File name, e.g. `Mob.wz`.
    pub name: String,
    pub path: PathBuf,
    file: File,
    pub file_len: u64,
    pub data_start: u32,
    pub copyright: String,
    /// The u16 stored at dataStart.
    pub enc_version: u16,
    /// The detected game version (83 for vanilla GMS v83).
    pub version: u32,
    pub hash: u32,
    pub root: Dir,
}

/// A directory: its entries in archive order.
#[derive(Debug, Clone, Default)]
pub struct Dir {
    pub entries: Vec<Entry>,
}

/// A directory entry (sub-directory or img).
#[derive(Debug, Clone)]
pub struct Entry {
    pub name: String,
    pub kind: EntryKind,
    pub size: i32,
    pub checksum: i32,
    pub offset: u32,
}

#[derive(Debug, Clone)]
pub enum EntryKind {
    Dir(Dir),
    Img,
}

impl Entry {
    /// True for img entries.
    pub fn is_img(&self) -> bool {
        matches!(self.kind, EntryKind::Img)
    }
}

impl Dir {
    /// Child entry by name.
    pub fn get(&self, name: &str) -> Option<&Entry> {
        self.entries.iter().find(|e| e.name == name)
    }
}

/// Read exactly `buf.len()` bytes at `offset` without moving a shared cursor (thread-safe).
pub fn read_exact_at(file: &File, mut buf: &mut [u8], mut offset: u64) -> io::Result<()> {
    while !buf.is_empty() {
        #[cfg(windows)]
        let r = std::os::windows::fs::FileExt::seek_read(file, buf, offset);
        #[cfg(unix)]
        let r = std::os::unix::fs::FileExt::read_at(file, buf, offset);
        match r {
            Ok(0) => return Err(io::Error::new(io::ErrorKind::UnexpectedEof, "unexpected end of file")),
            Ok(n) => {
                buf = &mut buf[n..];
                offset += n as u64;
            }
            Err(e) if e.kind() == io::ErrorKind::Interrupted => {}
            Err(e) => return Err(e),
        }
    }
    Ok(())
}

/// Versions tried when the stored encrypted version does not match v83: every version whose hash gives the
/// same encrypted version, validated by parsing the directory tree.
const MAX_VERSION: u32 = 1000;

impl WzArchive {
    /// Open an archive, detecting the version (v83 first, then any version whose hash matches).
    pub fn open(path: impl AsRef<Path>) -> Result<Self> {
        Self::open_with_version(path, None)
    }

    /// Open an archive; `version` forces a specific game version instead of detecting it.
    pub fn open_with_version(path: impl AsRef<Path>, version: Option<u32>) -> Result<Self> {
        let path = path.as_ref();
        let file = File::open(path).map_err(|e| WzError::io(path, e))?;
        let file_len = file.metadata().map_err(|e| WzError::io(path, e))?.len();
        let head_len = file_len.min(4096) as usize;
        let mut head = vec![0u8; head_len];
        read_exact_at(&file, &mut head, 0).map_err(|e| WzError::io(path, e))?;
        let mut r = Reader::new(&head, 0);
        let magic = r.bytes(4)?;
        if magic != b"PKG1" {
            return Err(WzError::Other(format!("{}: not a PKG1 archive", path.display())));
        }
        let _data_size = r.u64()?;
        let data_start = r.u32()?;
        let copyright = r.cstring()?;
        if (data_start as usize) + 2 > head.len() {
            return Err(WzError::format(12, format!("dataStart {data_start} out of range")));
        }
        r.set_pos(data_start as usize);
        let enc = r.u16()?;

        let candidates: Vec<u32> = match version {
            Some(v) => vec![v],
            None => {
                let mut c = Vec::new();
                if enc_version(version_hash(83)) == enc {
                    c.push(83);
                }
                c.extend((1..=MAX_VERSION).filter(|v| *v != 83 && enc_version(version_hash(*v)) == enc));
                c
            }
        };
        let mut last_err = None;
        for v in candidates {
            let hash = version_hash(v);
            match parse_tree(&file, file_len, data_start, hash) {
                Ok(root) => {
                    if let Err(e) = validate(&file, &root) {
                        last_err = Some(e);
                        continue;
                    }
                    let name = path.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
                    return Ok(WzArchive {
                        name,
                        path: path.to_path_buf(),
                        file,
                        file_len,
                        data_start,
                        copyright,
                        enc_version: enc,
                        version: v,
                        hash,
                        root,
                    });
                }
                Err(e) => last_err = Some(e),
            }
        }
        Err(WzError::Other(format!(
            "{}: could not detect the WZ version (encrypted version 0x{enc:04X}){}",
            path.display(),
            last_err.map(|e| format!("; last error: {e}")).unwrap_or_default()
        )))
    }

    /// Entry at a `/`-separated path inside the archive (`Map/Map1/104040000.img`). "" is not an entry.
    pub fn entry(&self, path: &str) -> Option<&Entry> {
        let mut dir = &self.root;
        let parts: Vec<&str> = path.split('/').filter(|p| !p.is_empty()).collect();
        for (i, part) in parts.iter().enumerate() {
            let e = dir.get(part)?;
            if i + 1 == parts.len() {
                return Some(e);
            }
            match &e.kind {
                EntryKind::Dir(d) => dir = d,
                EntryKind::Img => return None,
            }
        }
        None
    }

    /// Directory at a path ("" = root).
    pub fn dir(&self, path: &str) -> Option<&Dir> {
        if path.trim_matches('/').is_empty() {
            return Some(&self.root);
        }
        match &self.entry(path)?.kind {
            EntryKind::Dir(d) => Some(d),
            EntryKind::Img => None,
        }
    }

    /// Raw bytes of an img entry.
    pub fn img_bytes(&self, entry: &Entry) -> Result<Vec<u8>> {
        if !entry.is_img() || entry.size < 0 {
            return Err(WzError::Other(format!("{}: {} is not an img", self.name, entry.name)));
        }
        let mut buf = vec![0u8; entry.size as usize];
        read_exact_at(&self.file, &mut buf, entry.offset as u64).map_err(|e| WzError::io(&self.path, e))?;
        Ok(buf)
    }

    /// Parse the img at `path` (relative to the archive root). `full_path` names it in messages.
    pub fn load_img(&self, path: &str) -> Result<Img> {
        let entry = self
            .entry(path)
            .filter(|e| e.is_img())
            .ok_or_else(|| WzError::NotFound(format!("{}/{}", self.name, path)))?;
        let bytes = self.img_bytes(entry)?;
        parse_img(format!("{}/{}", self.name, path.trim_matches('/')), bytes, entry.offset as u64)
    }

    /// Every img path in the archive (relative to the archive root), in archive order.
    pub fn img_paths(&self) -> Vec<String> {
        fn walk(d: &Dir, prefix: &str, out: &mut Vec<String>) {
            for e in &d.entries {
                let p = if prefix.is_empty() { e.name.clone() } else { format!("{prefix}/{}", e.name) };
                match &e.kind {
                    EntryKind::Dir(sub) => walk(sub, &p, out),
                    EntryKind::Img => out.push(p),
                }
            }
        }
        let mut out = Vec::new();
        walk(&self.root, "", &mut out);
        out
    }
}

/// Parse the directory tree. The tree lives near the file start; read a window and widen it if a read
/// runs past the window.
fn parse_tree(file: &File, file_len: u64, data_start: u32, hash: u32) -> Result<Dir> {
    let mut window = file_len.min(1 << 20);
    loop {
        let mut buf = vec![0u8; window as usize];
        read_exact_at(file, &mut buf, 0).map_err(|e| WzError::Other(e.to_string()))?;
        let ctx = DirCtx { buf: &buf, file_len, data_start, hash };
        match ctx.parse_dir(data_start as usize + 2, 0) {
            Err(WzError::Eof { .. }) if window < file_len => window = file_len.min(window * 4),
            other => return other,
        }
    }
}

struct DirCtx<'a> {
    buf: &'a [u8],
    file_len: u64,
    data_start: u32,
    hash: u32,
}

impl DirCtx<'_> {
    fn reader_at(&self, pos: u64) -> Result<Reader<'_>> {
        if pos >= self.file_len {
            return Err(WzError::format(pos, "position past end of file"));
        }
        if pos >= self.buf.len() as u64 {
            return Err(WzError::Eof { pos, need: 1 });
        }
        let mut r = Reader::new(self.buf, 0);
        r.set_pos(pos as usize);
        Ok(r)
    }

    fn parse_dir(&self, pos: usize, depth: u32) -> Result<Dir> {
        if depth > 32 {
            return Err(WzError::format(pos as u64, "directory nesting too deep"));
        }
        let mut r = self.reader_at(pos as u64)?;
        let count = r.cint()?;
        if !(0..=200_000).contains(&count) {
            return Err(WzError::format(pos as u64, format!("bad directory entry count {count}")));
        }
        let mut entries = Vec::with_capacity(count as usize);
        for _ in 0..count {
            let at = r.abs_pos();
            let t = r.u8()?;
            let (kind, name) = match t {
                2 => {
                    let off = r.i32()?;
                    let p = self.data_start as i64 + off as i64;
                    if p < 0 {
                        return Err(WzError::format(at, "negative name offset"));
                    }
                    let mut s = self.reader_at(p as u64)?;
                    let t2 = s.u8()?;
                    (t2, s.wz_string()?)
                }
                3 | 4 => (t, r.wz_string()?),
                1 => return Err(WzError::format(at, "directory entry type 1 (not used in v83) is not supported")),
                _ => return Err(WzError::format(at, format!("bad directory entry type {t}"))),
            };
            let size = r.cint()?;
            let checksum = r.cint()?;
            let fpos = r.abs_pos() as u32;
            let stored = r.u32()?;
            let offset = decrypt_offset(fpos, stored, self.data_start, self.hash);
            if offset as u64 >= self.file_len {
                return Err(WzError::format(at, format!("entry {name}: offset {offset} out of range")));
            }
            let kind = match kind {
                3 => EntryKind::Dir(Dir::default()),
                4 => {
                    if size < 0 || offset as u64 + size as u64 > self.file_len {
                        return Err(WzError::format(at, format!("img {name}: size {size} out of range")));
                    }
                    EntryKind::Img
                }
                k => return Err(WzError::format(at, format!("entry {name}: bad kind {k}"))),
            };
            entries.push(Entry { name, kind, size, checksum, offset });
        }
        for e in entries.iter_mut() {
            if let EntryKind::Dir(d) = &mut e.kind {
                *d = self.parse_dir(e.offset as usize, depth + 1)?;
            }
        }
        Ok(Dir { entries })
    }
}

/// Spot-check that imgs start with the `0x73 "Property"` header byte (catches a wrong version hash).
fn validate(file: &File, root: &Dir) -> Result<()> {
    let mut checked = 0;
    let mut stack = vec![root];
    while let Some(d) = stack.pop() {
        for e in &d.entries {
            match &e.kind {
                EntryKind::Dir(sub) => stack.push(sub),
                EntryKind::Img if e.size > 0 && checked < 32 => {
                    let mut b = [0u8; 1];
                    read_exact_at(file, &mut b, e.offset as u64).map_err(|e| WzError::Other(e.to_string()))?;
                    if b[0] != 0x73 {
                        return Err(WzError::format(e.offset as u64, format!("img {} has no 0x73 header", e.name)));
                    }
                    checked += 1;
                }
                EntryKind::Img => {}
            }
        }
    }
    Ok(())
}
