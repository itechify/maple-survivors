//! Canvas decoding: zlib or block-encrypted data, pixel formats 1/2/513/517 -> straight-alpha RGBA8.
//!
//! Formats (`fmt + fmt2`): 1 BGRA4444 (nibbles expanded `n * 17`), 2 BGRA8888, 513 RGB565 (bit replication,
//! opaque), 517 RGB565 with one stored pixel per 16x16 block. Block-encrypted data is a sequence of
//! (i32 block_len, block XOR keystream[0..block_len]) whose concatenation is the zlib stream.

use crate::crypto::Keystream;
use crate::error::{Result, WzError};
use crate::property::CanvasRef;
use flate2::{Decompress, FlushDecompress, Status};

/// Bytes of decompressed pixel data for a canvas, or None for an unsupported format.
pub fn raw_size(width: u32, height: u32, format: i32) -> Option<usize> {
    let (w, h) = (width as usize, height as usize);
    match format {
        1 | 513 => Some(w * h * 2),
        2 => Some(w * h * 4),
        517 => Some(w.div_ceil(16) * h.div_ceil(16) * 2),
        _ => None,
    }
}

/// Decode a canvas whose data lives in `bytes` (the img blob named by `c.src`) to RGBA8 (`w * h * 4` bytes).
pub fn decode(bytes: &[u8], c: &CanvasRef) -> Result<Vec<u8>> {
    let format = c.format();
    let expected = raw_size(c.width, c.height, format)
        .ok_or_else(|| WzError::Other(format!("unsupported canvas format {} + {}", c.fmt, c.fmt2)))?;
    let start = c.data_off as usize;
    let end = start + c.data_len as usize;
    if end > bytes.len() {
        return Err(WzError::Other("canvas data out of range".into()));
    }
    let raw = unpack_data(&bytes[start..end], expected)?;
    pixels_to_rgba(&raw, c.width, c.height, format)
}

/// True when `data` starts with a valid zlib header (CM = 8, FCHECK ok).
pub fn looks_like_zlib(data: &[u8]) -> bool {
    data.len() >= 2 && data[0] & 0x0F == 8 && (((data[0] as u16) << 8) | data[1] as u16).is_multiple_of(31)
}

/// Inflate canvas data that is either a plain zlib stream or block-encrypted; returns `expected` bytes.
pub fn unpack_data(data: &[u8], expected: usize) -> Result<Vec<u8>> {
    if expected == 0 {
        return Ok(Vec::new());
    }
    let mut first_err = None;
    if looks_like_zlib(data) {
        match inflate(data, expected) {
            Ok(v) => return Ok(v),
            Err(e) => first_err = Some(e),
        }
    }
    match decrypt_blocks(data).and_then(|plain| inflate(&plain, expected)) {
        Ok(v) => Ok(v),
        Err(e) => Err(first_err.unwrap_or(e)),
    }
}

/// Concatenate XOR-decrypted blocks of a block-encrypted canvas.
pub fn decrypt_blocks(data: &[u8]) -> Result<Vec<u8>> {
    let mut out = Vec::with_capacity(data.len());
    let mut pos = 0usize;
    let ks = Keystream::gms();
    while pos + 4 <= data.len() {
        let len = i32::from_le_bytes([data[pos], data[pos + 1], data[pos + 2], data[pos + 3]]);
        pos += 4;
        if len <= 0 || pos + len as usize > data.len() {
            return Err(WzError::Other(format!("bad encrypted canvas block length {len}")));
        }
        let start = out.len();
        out.extend_from_slice(&data[pos..pos + len as usize]);
        ks.xor(&mut out[start..]);
        pos += len as usize;
    }
    Ok(out)
}

/// Inflate a zlib stream to exactly `expected` bytes (trailing data and a missing checksum are tolerated).
pub fn inflate(data: &[u8], expected: usize) -> Result<Vec<u8>> {
    let mut out = vec![0u8; expected];
    let mut d = Decompress::new(true);
    loop {
        let before_in = d.total_in();
        let before_out = d.total_out();
        let status = d
            .decompress(&data[before_in as usize..], &mut out[before_out as usize..], FlushDecompress::Finish)
            .map_err(|e| WzError::Other(format!("zlib: {e}")))?;
        let done_out = d.total_out() as usize;
        if done_out == expected {
            return Ok(out);
        }
        let progressed = d.total_in() != before_in || d.total_out() != before_out;
        if status == Status::StreamEnd || !progressed {
            return Err(WzError::Other(format!("zlib: canvas inflated to {done_out} bytes, expected {expected}")));
        }
    }
}

#[inline]
fn expand565(p: u16) -> [u8; 4] {
    let r = ((p >> 11) & 0x1F) as u8;
    let g = ((p >> 5) & 0x3F) as u8;
    let b = (p & 0x1F) as u8;
    [(r << 3) | (r >> 2), (g << 2) | (g >> 4), (b << 3) | (b >> 2), 255]
}

/// Convert decompressed pixel data to straight-alpha RGBA8.
pub fn pixels_to_rgba(raw: &[u8], width: u32, height: u32, format: i32) -> Result<Vec<u8>> {
    let (w, h) = (width as usize, height as usize);
    let need = raw_size(width, height, format).ok_or_else(|| WzError::Other(format!("unsupported format {format}")))?;
    if raw.len() < need {
        return Err(WzError::Other(format!("pixel data is {} bytes, expected {need}", raw.len())));
    }
    let mut out = vec![0u8; w * h * 4];
    match format {
        1 => {
            for (px, o) in raw.as_chunks::<2>().0.iter().zip(out.as_chunks_mut::<4>().0.iter_mut()) {
                let (b0, b1) = (px[0], px[1]);
                o[0] = (b1 & 0x0F) * 17;
                o[1] = (b0 >> 4) * 17;
                o[2] = (b0 & 0x0F) * 17;
                o[3] = (b1 >> 4) * 17;
            }
        }
        2 => {
            for (px, o) in raw.as_chunks::<4>().0.iter().zip(out.as_chunks_mut::<4>().0.iter_mut()) {
                o.copy_from_slice(&[px[2], px[1], px[0], px[3]]);
            }
        }
        513 => {
            for (px, o) in raw.as_chunks::<2>().0.iter().zip(out.as_chunks_mut::<4>().0.iter_mut()) {
                o.copy_from_slice(&expand565(u16::from_le_bytes([px[0], px[1]])));
            }
        }
        517 => {
            let bw = w.div_ceil(16);
            for y in 0..h {
                for x in 0..w {
                    let i = (y / 16) * bw + x / 16;
                    let p = u16::from_le_bytes([raw[2 * i], raw[2 * i + 1]]);
                    out[(y * w + x) * 4..(y * w + x) * 4 + 4].copy_from_slice(&expand565(p));
                }
            }
        }
        _ => unreachable!(),
    }
    Ok(out)
}
