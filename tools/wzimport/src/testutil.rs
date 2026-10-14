//! Test-only synthetic WZ writer: builds PKG1 archives (header, version hash, encrypted directory offsets,
//! type-2 shared names, imgs with every property type) so the reader is tested without Nexon data.

use crate::crypto::{enc_version, encrypt_offset, version_hash, Keystream};
use crate::reader::cp1252_encode;
use flate2::write::ZlibEncoder;
use flate2::Compression;
use std::collections::HashMap;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU32, Ordering};

/// A property value to write.
#[derive(Clone, Debug)]
pub enum W {
    Null,
    Short(i16),
    /// Written with property type 11 (the alternative short type).
    Short11(i16),
    Int(i32),
    Long(i64),
    Float(f32),
    Double(f64),
    Str(String),
    Sub(Vec<(String, W)>),
    Canvas(WCanvas),
    Vector(i32, i32),
    Convex(Vec<(i32, i32)>),
    Sound(WSound),
    Uol(String),
}

/// A canvas: `raw` is the uncompressed pixel data in format `fmt + fmt2`.
#[derive(Clone, Debug)]
pub struct WCanvas {
    pub w: u32,
    pub h: u32,
    pub fmt: i32,
    pub fmt2: u8,
    pub raw: Vec<u8>,
    pub encrypted: bool,
    pub props: Vec<(String, W)>,
}

/// A Sound_DX8 property.
#[derive(Clone, Debug)]
pub struct WSound {
    pub duration_ms: i32,
    pub header: SoundHeader,
    pub data: Vec<u8>,
}

#[derive(Clone, Debug)]
pub enum SoundHeader {
    /// 82-byte header: WAVEFORMATEX + MPEGLAYER3WAVEFORMAT (wfx_len 30).
    Mp3 { channels: u16, rate: u32 },
    /// 70-byte header: plain WAVEFORMATEX (wfx_len 18).
    Pcm { channels: u16, rate: u32, bits: u16 },
    /// 51-byte media type with format declaration 1 and no WAVEFORMATEX.
    NoWfx,
    /// WAVEFORMATEX with an unknown format tag.
    BadTag,
}

/// `(name, value)` pair helper.
pub fn p(name: &str, v: W) -> (String, W) {
    (name.to_string(), v)
}

/// Sub-property helper.
pub fn sub(children: Vec<(String, W)>) -> W {
    W::Sub(children)
}

/// Canvas helper.
pub fn canvas(w: u32, h: u32, format: i32, raw: Vec<u8>, encrypted: bool, props: Vec<(String, W)>) -> W {
    let (fmt, fmt2) = if format == 517 { (513, 4) } else { (format, 0) };
    W::Canvas(WCanvas { w, h, fmt, fmt2, raw, encrypted, props })
}

/// Encrypted WZ string. ASCII form when every char has a single-byte (cp1252) form, unless `force_unicode`.
pub fn encode_wz_string(s: &str, force_unicode: bool) -> Vec<u8> {
    let mut out = Vec::new();
    if s.is_empty() {
        out.push(0);
        return out;
    }
    let single: Option<Vec<u8>> = if force_unicode { None } else { s.chars().map(cp1252_encode).collect() };
    let ks = Keystream::gms();
    match single {
        Some(bytes) => {
            let n = bytes.len();
            if n <= 127 {
                out.push((-(n as i32)) as i8 as u8);
            } else {
                out.push(0x80);
                out.extend_from_slice(&(n as i32).to_le_bytes());
            }
            ks.with(n, |k| {
                for (i, b) in bytes.iter().enumerate() {
                    out.push(b ^ k[i] ^ 0xAAu8.wrapping_add(i as u8));
                }
            });
        }
        None => {
            let units: Vec<u16> = s.encode_utf16().collect();
            let n = units.len();
            if n < 127 {
                out.push(n as u8);
            } else {
                out.push(127);
                out.extend_from_slice(&(n as i32).to_le_bytes());
            }
            ks.with(n * 2, |k| {
                for (i, u) in units.iter().enumerate() {
                    let key = u16::from_le_bytes([k[2 * i], k[2 * i + 1]]);
                    out.extend_from_slice(&(u ^ key ^ 0xAAAAu16.wrapping_add(i as u16)).to_le_bytes());
                }
            });
        }
    }
    out
}

fn cint(out: &mut Vec<u8>, v: i32) {
    if (-127..=127).contains(&v) {
        out.push(v as i8 as u8);
    } else {
        out.push(0x80);
        out.extend_from_slice(&v.to_le_bytes());
    }
}

fn clong(out: &mut Vec<u8>, v: i64) {
    if (-127..=127).contains(&v) {
        out.push(v as i8 as u8);
    } else {
        out.push(0x80);
        out.extend_from_slice(&v.to_le_bytes());
    }
}

/// zlib-compress (default level: `78 9C` header).
pub fn zlib(raw: &[u8]) -> Vec<u8> {
    let mut e = ZlibEncoder::new(Vec::new(), Compression::default());
    e.write_all(raw).unwrap();
    e.finish().unwrap()
}

/// Block-encrypt a zlib stream: blocks of (i32 len, bytes XOR keystream[0..len]).
pub fn block_encrypt(z: &[u8], block: usize) -> Vec<u8> {
    let mut out = Vec::new();
    for chunk in z.chunks(block) {
        out.extend_from_slice(&(chunk.len() as i32).to_le_bytes());
        let mut c = chunk.to_vec();
        Keystream::gms().xor(&mut c);
        out.extend_from_slice(&c);
    }
    out
}

struct ImgW {
    buf: Vec<u8>,
    dedupe: bool,
    seen: HashMap<String, u32>,
}

impl ImgW {
    fn block(&mut self, s: &str, inline: u8, offset: u8) {
        if self.dedupe {
            if let Some(&o) = self.seen.get(s) {
                self.buf.push(offset);
                self.buf.extend_from_slice(&(o as i32).to_le_bytes());
                return;
            }
        }
        self.buf.push(inline);
        let pos = self.buf.len() as u32;
        let enc = encode_wz_string(s, false);
        self.buf.extend_from_slice(&enc);
        if self.dedupe {
            self.seen.insert(s.to_string(), pos);
        }
    }

    fn name(&mut self, s: &str) {
        self.block(s, 0x00, 0x01)
    }

    fn type_name(&mut self, s: &str) {
        self.block(s, 0x73, 0x1B)
    }

    fn prop_list(&mut self, props: &[(String, W)]) {
        cint(&mut self.buf, props.len() as i32);
        for (n, v) in props {
            self.name(n);
            self.value(v);
        }
    }

    fn value(&mut self, v: &W) {
        let b = &mut self.buf;
        match v {
            W::Null => b.push(0),
            W::Short(x) => {
                b.push(2);
                b.extend_from_slice(&x.to_le_bytes());
            }
            W::Short11(x) => {
                b.push(11);
                b.extend_from_slice(&x.to_le_bytes());
            }
            W::Int(x) => {
                b.push(3);
                cint(b, *x);
            }
            W::Long(x) => {
                b.push(20);
                clong(b, *x);
            }
            W::Float(x) => {
                b.push(4);
                if *x == 0.0 {
                    b.push(0);
                } else {
                    b.push(0x80);
                    b.extend_from_slice(&x.to_le_bytes());
                }
            }
            W::Double(x) => {
                b.push(5);
                b.extend_from_slice(&x.to_le_bytes());
            }
            W::Str(s) => {
                b.push(8);
                let s = s.clone();
                self.name(&s);
            }
            _ => {
                b.push(9);
                let at = b.len();
                b.extend_from_slice(&[0, 0, 0, 0]);
                self.object(v);
                let size = (self.buf.len() - at - 4) as u32;
                self.buf[at..at + 4].copy_from_slice(&size.to_le_bytes());
            }
        }
    }

    fn object(&mut self, v: &W) {
        match v {
            W::Sub(props) => {
                self.type_name("Property");
                self.buf.extend_from_slice(&[0, 0]);
                self.prop_list(props);
            }
            W::Canvas(c) => {
                self.type_name("Canvas");
                self.buf.push(0);
                if c.props.is_empty() {
                    self.buf.push(0);
                } else {
                    self.buf.push(1);
                    self.buf.extend_from_slice(&[0, 0]);
                    self.prop_list(&c.props);
                }
                cint(&mut self.buf, c.w as i32);
                cint(&mut self.buf, c.h as i32);
                cint(&mut self.buf, c.fmt);
                self.buf.push(c.fmt2);
                self.buf.extend_from_slice(&0i32.to_le_bytes());
                let z = zlib(&c.raw);
                let data = if c.encrypted { block_encrypt(&z, 5.max(z.len() / 3)) } else { z };
                self.buf.extend_from_slice(&((data.len() + 1) as i32).to_le_bytes());
                self.buf.push(0);
                self.buf.extend_from_slice(&data);
            }
            W::Vector(x, y) => {
                self.type_name("Shape2D#Vector2D");
                cint(&mut self.buf, *x);
                cint(&mut self.buf, *y);
            }
            W::Convex(pts) => {
                self.type_name("Shape2D#Convex2D");
                cint(&mut self.buf, pts.len() as i32);
                for (x, y) in pts {
                    self.object(&W::Vector(*x, *y));
                }
            }
            W::Sound(s) => {
                self.type_name("Sound_DX8");
                self.buf.push(0);
                cint(&mut self.buf, s.data.len() as i32);
                cint(&mut self.buf, s.duration_ms);
                let mut media = vec![0u8; 51];
                media[0] = if matches!(s.header, SoundHeader::NoWfx) { 1 } else { 2 };
                media[1..17].copy_from_slice(&[0x83, 0xEB, 0x36, 0xE4, 0x4F, 0x52, 0xCE, 0x11, 0x9F, 0x53, 0x00, 0x20, 0xAF, 0x0B, 0xA7, 0x70]);
                self.buf.extend_from_slice(&media);
                let wfx = |tag: u16, ch: u16, rate: u32, bits: u16, extra: &[u8]| {
                    let align = (ch as u32 * bits as u32 / 8).max(1);
                    let mut w = Vec::new();
                    w.extend_from_slice(&tag.to_le_bytes());
                    w.extend_from_slice(&ch.to_le_bytes());
                    w.extend_from_slice(&rate.to_le_bytes());
                    w.extend_from_slice(&(rate * align).to_le_bytes());
                    w.extend_from_slice(&(align as u16).to_le_bytes());
                    w.extend_from_slice(&bits.to_le_bytes());
                    w.extend_from_slice(&(extra.len() as u16).to_le_bytes());
                    w.extend_from_slice(extra);
                    w
                };
                let w = match &s.header {
                    SoundHeader::Mp3 { channels, rate } => Some(wfx(0x55, *channels, *rate, 0, &[1, 0, 2, 0, 0, 0, 0x0A, 0x02, 1, 0, 0, 0])),
                    SoundHeader::Pcm { channels, rate, bits } => Some(wfx(1, *channels, *rate, *bits, &[])),
                    SoundHeader::NoWfx => None,
                    SoundHeader::BadTag => Some(wfx(0x3344, 3, 1234, 0, &[])),
                };
                if let Some(w) = w {
                    cint(&mut self.buf, w.len() as i32);
                    self.buf.extend_from_slice(&w);
                }
                self.buf.extend_from_slice(&s.data);
            }
            W::Uol(path) => {
                self.type_name("UOL");
                self.buf.push(0);
                let path = path.clone();
                self.name(&path);
            }
            _ => unreachable!("not an extended object"),
        }
    }
}

/// Serialize an img: `0x73 "Property" u16 0` + property list. `dedupe` writes repeated strings in offset form.
pub fn write_img(props: &[(String, W)], dedupe: bool) -> Vec<u8> {
    let mut w = ImgW { buf: Vec::new(), dedupe, seen: HashMap::new() };
    w.object(&W::Sub(props.to_vec()));
    w.buf
}

/// A directory entry to write.
#[derive(Clone, Debug)]
pub enum WEntry {
    Dir(String, Vec<WEntry>),
    Img(String, Vec<u8>),
}

struct Block {
    entries: Vec<(String, FlatKind)>,
}

enum FlatKind {
    Dir(usize),
    Img(usize),
}

fn flatten(entries: &[WEntry], blocks: &mut Vec<Block>, imgs: &mut Vec<Vec<u8>>) -> usize {
    let idx = blocks.len();
    blocks.push(Block { entries: Vec::new() });
    let mut list = Vec::new();
    let mut subdirs = Vec::new();
    for e in entries {
        match e {
            WEntry::Img(name, bytes) => {
                imgs.push(bytes.clone());
                list.push((name.clone(), FlatKind::Img(imgs.len() - 1)));
            }
            WEntry::Dir(name, children) => {
                list.push((name.clone(), FlatKind::Dir(usize::MAX)));
                subdirs.push((list.len() - 1, children));
            }
        }
    }
    for (pos, children) in subdirs {
        let b = flatten(children, blocks, imgs);
        list[pos].1 = FlatKind::Dir(b);
    }
    blocks[idx].entries = list;
    idx
}

pub const COPYRIGHT: &str = "Package file v1.0 Copyright 2002 Wizet, ZMS";

/// Build a PKG1 archive for game `version`. `type2_names` writes repeated (kind, name) entries as type 2.
pub fn write_archive(entries: &[WEntry], version: u32, type2_names: bool) -> Vec<u8> {
    let mut blocks = Vec::new();
    let mut imgs = Vec::new();
    flatten(entries, &mut blocks, &mut imgs);
    let data_start = 16 + COPYRIGHT.len() as u32 + 1;
    assert_eq!(data_start, 60);
    let hash = version_hash(version);

    let emit = |block_pos: &[u32], img_pos: &[u32]| -> (Vec<u8>, Vec<u32>) {
        let mut out = Vec::new();
        let base = data_start + 2;
        let mut sizes = Vec::new();
        let mut seen: HashMap<(u8, String), u32> = HashMap::new();
        for b in &blocks {
            let start = out.len();
            cint(&mut out, b.entries.len() as i32);
            for (name, kind) in &b.entries {
                let t = match kind {
                    FlatKind::Dir(_) => 3u8,
                    FlatKind::Img(_) => 4u8,
                };
                let here = base + out.len() as u32;
                match seen.get(&(t, name.clone())) {
                    Some(&pos) if type2_names => {
                        out.push(2);
                        out.extend_from_slice(&((pos - data_start) as i32).to_le_bytes());
                    }
                    _ => {
                        seen.insert((t, name.clone()), here);
                        out.push(t);
                        out.extend_from_slice(&encode_wz_string(name, false));
                    }
                }
                let (size, checksum, target) = match kind {
                    FlatKind::Dir(i) => (0, 0, block_pos[*i]),
                    FlatKind::Img(i) => {
                        let sum = imgs[*i].iter().fold(0i32, |a, b| a.wrapping_add(*b as i32));
                        (imgs[*i].len() as i32, sum, img_pos[*i])
                    }
                };
                cint(&mut out, size);
                cint(&mut out, checksum);
                let fpos = base + out.len() as u32;
                out.extend_from_slice(&encrypt_offset(fpos, target, data_start, hash).to_le_bytes());
            }
            sizes.push((out.len() - start) as u32);
        }
        (out, sizes)
    };

    let (_, sizes) = emit(&vec![0; blocks.len()], &vec![0; imgs.len()]);
    let mut block_pos = Vec::new();
    let mut pos = data_start + 2;
    for s in &sizes {
        block_pos.push(pos);
        pos += s;
    }
    let mut img_pos = Vec::new();
    for i in &imgs {
        img_pos.push(pos);
        pos += i.len() as u32;
    }
    let (dirs, _) = emit(&block_pos, &img_pos);

    let mut out = Vec::new();
    out.extend_from_slice(b"PKG1");
    out.extend_from_slice(&0u64.to_le_bytes());
    out.extend_from_slice(&data_start.to_le_bytes());
    out.extend_from_slice(COPYRIGHT.as_bytes());
    out.push(0);
    out.extend_from_slice(&enc_version(hash).to_le_bytes());
    out.extend_from_slice(&dirs);
    for i in &imgs {
        out.extend_from_slice(i);
    }
    let data_size = (out.len() as u64) - data_start as u64;
    out[4..12].copy_from_slice(&data_size.to_le_bytes());
    out
}

/// A temporary directory removed on drop.
pub struct TempDir(pub PathBuf);

impl TempDir {
    /// Fresh empty directory under the system temp dir.
    pub fn new(tag: &str) -> TempDir {
        static N: AtomicU32 = AtomicU32::new(0);
        let p = std::env::temp_dir().join(format!(
            "wzimport-test-{}-{}-{tag}",
            std::process::id(),
            N.fetch_add(1, Ordering::Relaxed)
        ));
        let _ = std::fs::remove_dir_all(&p);
        std::fs::create_dir_all(&p).unwrap();
        TempDir(p)
    }

    pub fn path(&self) -> &Path {
        &self.0
    }
}

impl Drop for TempDir {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

/// Write archives (`("Mob.wz", entries)`) into `dir` as version-83 files with type-2 names enabled.
pub fn write_wz_root(dir: &Path, archives: &[(&str, Vec<WEntry>)]) {
    for (name, entries) in archives {
        std::fs::write(dir.join(name), write_archive(entries, 83, true)).unwrap();
    }
}

/// Raw BGRA4444 bytes from (r, g, b, a) nibbles.
pub fn bgra4444(px: &[(u8, u8, u8, u8)]) -> Vec<u8> {
    px.iter().flat_map(|&(r, g, b, a)| [(g << 4) | b, (a << 4) | r]).collect()
}

/// A solid-colour BGRA4444 canvas of w x h (nibbles).
pub fn solid4444(w: u32, h: u32, rgba: (u8, u8, u8, u8)) -> Vec<u8> {
    bgra4444(&vec![rgba; (w * h) as usize])
}
