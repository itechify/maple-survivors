//! Little-endian byte reader for WZ data: primitives, compressed ints, encrypted strings and string blocks.

use crate::crypto::Keystream;
use crate::error::{Result, WzError};

/// Cursor over a byte slice. `base` is the absolute file offset of `data[0]` (used for error messages and
/// encrypted directory offsets).
#[derive(Clone)]
pub struct Reader<'a> {
    data: &'a [u8],
    pos: usize,
    base: u64,
}

impl<'a> Reader<'a> {
    /// Reader over `data`, whose first byte sits at absolute file offset `base`.
    pub fn new(data: &'a [u8], base: u64) -> Self {
        Reader { data, pos: 0, base }
    }

    /// Current position relative to the slice start.
    pub fn pos(&self) -> usize {
        self.pos
    }

    /// Current absolute file position.
    pub fn abs_pos(&self) -> u64 {
        self.base + self.pos as u64
    }

    /// Move to `pos` (relative to the slice start).
    pub fn set_pos(&mut self, pos: usize) {
        self.pos = pos;
    }

    /// Length of the underlying slice.
    pub fn len(&self) -> usize {
        self.data.len()
    }

    /// True when the underlying slice is empty.
    pub fn is_empty(&self) -> bool {
        self.data.is_empty()
    }

    /// The whole underlying slice.
    pub fn data(&self) -> &'a [u8] {
        self.data
    }

    /// Read `n` raw bytes.
    pub fn bytes(&mut self, n: usize) -> Result<&'a [u8]> {
        let end = self.pos.checked_add(n).filter(|e| *e <= self.data.len());
        match end {
            Some(end) => {
                let s = &self.data[self.pos..end];
                self.pos = end;
                Ok(s)
            }
            None => Err(WzError::Eof { pos: self.abs_pos(), need: n }),
        }
    }

    /// Skip `n` bytes.
    pub fn skip(&mut self, n: usize) -> Result<()> {
        self.bytes(n).map(|_| ())
    }

    fn arr<const N: usize>(&mut self) -> Result<[u8; N]> {
        let b = self.bytes(N)?;
        let mut a = [0u8; N];
        a.copy_from_slice(b);
        Ok(a)
    }

    pub fn u8(&mut self) -> Result<u8> {
        Ok(self.arr::<1>()?[0])
    }
    pub fn i8(&mut self) -> Result<i8> {
        Ok(self.u8()? as i8)
    }
    pub fn u16(&mut self) -> Result<u16> {
        Ok(u16::from_le_bytes(self.arr()?))
    }
    pub fn i16(&mut self) -> Result<i16> {
        Ok(i16::from_le_bytes(self.arr()?))
    }
    pub fn u32(&mut self) -> Result<u32> {
        Ok(u32::from_le_bytes(self.arr()?))
    }
    pub fn i32(&mut self) -> Result<i32> {
        Ok(i32::from_le_bytes(self.arr()?))
    }
    pub fn i64(&mut self) -> Result<i64> {
        Ok(i64::from_le_bytes(self.arr()?))
    }
    pub fn u64(&mut self) -> Result<u64> {
        Ok(u64::from_le_bytes(self.arr()?))
    }
    pub fn f32(&mut self) -> Result<f32> {
        Ok(f32::from_le_bytes(self.arr()?))
    }
    pub fn f64(&mut self) -> Result<f64> {
        Ok(f64::from_le_bytes(self.arr()?))
    }

    /// Compressed int: i8, where -128 means an i32 follows.
    pub fn cint(&mut self) -> Result<i32> {
        let b = self.i8()?;
        if b == -128 {
            self.i32()
        } else {
            Ok(b as i32)
        }
    }

    /// Compressed long: i8, where -128 means an i64 follows.
    pub fn clong(&mut self) -> Result<i64> {
        let b = self.i8()?;
        if b == -128 {
            self.i64()
        } else {
            Ok(b as i64)
        }
    }

    /// NUL-terminated plain string (the PKG1 copyright).
    pub fn cstring(&mut self) -> Result<String> {
        let start = self.pos;
        while self.u8()? != 0 {}
        Ok(String::from_utf8_lossy(&self.data[start..self.pos - 1]).into_owned())
    }

    /// Encrypted WZ string: i8 length; > 0 UTF-16 (127 -> i32 length), < 0 single-byte (-128 -> i32 length).
    pub fn wz_string(&mut self) -> Result<String> {
        let at = self.abs_pos();
        let len = self.i8()?;
        if len == 0 {
            return Ok(String::new());
        }
        if len > 0 {
            let n = if len == 127 { self.i32()? } else { len as i32 };
            if n < 0 || n as usize > self.data.len() {
                return Err(WzError::format(at, format!("bad UTF-16 string length {n}")));
            }
            let n = n as usize;
            let raw = self.bytes(n * 2)?;
            let ks = Keystream::gms();
            let units: Vec<u16> = ks.with(n * 2, |k| {
                (0..n)
                    .map(|i| {
                        let c = u16::from_le_bytes([raw[2 * i], raw[2 * i + 1]]);
                        let key = u16::from_le_bytes([k[2 * i], k[2 * i + 1]]);
                        c ^ key ^ (0xAAAAu16.wrapping_add(i as u16))
                    })
                    .collect()
            });
            Ok(String::from_utf16_lossy(&units))
        } else {
            let n = if len == -128 { self.i32()? } else { -(len as i32) };
            if n < 0 || n as usize > self.data.len() {
                return Err(WzError::format(at, format!("bad ASCII string length {n}")));
            }
            let n = n as usize;
            let raw = self.bytes(n)?;
            let ks = Keystream::gms();
            Ok(ks.with(n, |k| {
                (0..n).map(|i| cp1252(raw[i] ^ k[i] ^ (0xAAu8.wrapping_add(i as u8)))).collect::<String>()
            }))
        }
    }

    /// String block inside an img: marker 0x00/0x73 = inline string, 0x01/0x1B = i32 offset from the img start.
    pub fn string_block(&mut self) -> Result<String> {
        let at = self.abs_pos();
        match self.u8()? {
            0x00 | 0x73 => self.wz_string(),
            0x01 | 0x1B => {
                let off = self.i32()?;
                if off < 0 || off as usize >= self.data.len() {
                    return Err(WzError::format(at, format!("string offset {off} out of range")));
                }
                let mut sub = Reader { data: self.data, pos: off as usize, base: self.base };
                sub.wz_string()
            }
            m => Err(WzError::format(at, format!("bad string block marker 0x{m:02X}"))),
        }
    }
}

/// Single-byte WZ strings are Windows-1252 (GMS); map the 0x80-0x9F range, the rest equals Latin-1.
fn cp1252(b: u8) -> char {
    const HIGH: [u16; 32] = [
        0x20AC, 0x0081, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, 0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x008D,
        0x017D, 0x008F, 0x0090, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014, 0x02DC, 0x2122, 0x0161, 0x203A,
        0x0153, 0x009D, 0x017E, 0x0178,
    ];
    if (0x80..0xA0).contains(&b) {
        char::from_u32(HIGH[(b - 0x80) as usize] as u32).unwrap_or('\u{FFFD}')
    } else {
        b as char
    }
}

/// Inverse of the single-byte decoding, for the test writer. None when a char has no single-byte form.
pub fn cp1252_encode(c: char) -> Option<u8> {
    let u = c as u32;
    if u < 0x80 || (0xA0..0x100).contains(&u) {
        return Some(u as u8);
    }
    (0x80u8..0xA0).find(|b| cp1252(*b) == c)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn compressed_ints() {
        let data = [0x05u8, 0xFB, 0x80, 0x78, 0x56, 0x34, 0x12, 0x80, 1, 0, 0, 0, 0, 0, 0, 0x80];
        let mut r = Reader::new(&data, 0);
        assert_eq!(r.cint().unwrap(), 5);
        assert_eq!(r.cint().unwrap(), -5);
        assert_eq!(r.cint().unwrap(), 0x12345678);
        assert_eq!(r.clong().unwrap(), i64::MIN + 1);
        assert!(matches!(r.u8(), Err(WzError::Eof { .. })));
    }

    #[test]
    fn cp1252_roundtrip() {
        for b in 0u8..=255 {
            let c = cp1252(b);
            assert_eq!(cp1252_encode(c), Some(b), "byte {b:#x}");
        }
        assert_eq!(cp1252(0x92), '\u{2019}');
    }
}
