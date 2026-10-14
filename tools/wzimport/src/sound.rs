//! `Sound_DX8` properties: header parsing and output encoding.
//!
//! Layout: u8 0, cint data_len, cint duration_ms, a 51-byte DirectShow media-type block (u8 format
//! declaration, major type GUID, subtype GUID, two flag bytes, format type GUID), cint wfx_len, a
//! WAVEFORMATEX of wfx_len bytes (30 for MP3, 18 for PCM), then the data. The data always ends the
//! extended property, so it is located from the end; the header is validated against that.
//! A media type with format declaration != 2 has no wfx_len/WAVEFORMATEX at all; its data is sniffed
//! (one v83 BGM is a plain MP3 file with an ID3 tag stored that way).

use crate::error::{Result, WzError};
use crate::property::SoundRef;
use crate::reader::Reader;

/// How a sound is encoded.
#[derive(Clone, Debug, PartialEq)]
pub enum SoundFormat {
    /// MPEG audio (WAVE_FORMAT_MPEGLAYER3, tag 0x55): written byte-for-byte as `.mp3`.
    Mp3(WaveFormat),
    /// PCM (tag 0x01): written as `.wav` with a RIFF header.
    Pcm(WaveFormat),
    /// Header that does not describe MP3 or PCM; skipped with a warning.
    Malformed(String),
}

impl SoundFormat {
    /// Output file extension, or None for malformed sounds.
    pub fn extension(&self) -> Option<&'static str> {
        match self {
            SoundFormat::Mp3(_) => Some("mp3"),
            SoundFormat::Pcm(_) => Some("wav"),
            SoundFormat::Malformed(_) => None,
        }
    }
}

/// The WAVEFORMATEX fields needed for a RIFF header.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct WaveFormat {
    pub tag: u16,
    pub channels: u16,
    pub rate: u32,
    pub avg_bytes: u32,
    pub block_align: u16,
    pub bits: u16,
}

/// Size of the media-type block before wfx_len.
pub const MEDIA_TYPE_LEN: usize = 51;

/// Parse a Sound_DX8 body (reader positioned after the type name); `end` is the end of the extended property.
pub fn parse_sound(r: &mut Reader, end: usize) -> Result<SoundRef> {
    let at = r.abs_pos();
    r.skip(1)?;
    let data_len = r.cint()?;
    let duration_ms = r.cint()?;
    let header_start = r.pos();
    if data_len < 0 || header_start + data_len as usize > end {
        return Err(WzError::format(at, format!("sound data length {data_len} out of range")));
    }
    let data_off = end - data_len as usize;
    let header_len = data_off - header_start;
    let data = &r.data()[data_off..end];
    let format = parse_header(r, header_len, data).unwrap_or_else(SoundFormat::Malformed);
    r.set_pos(end);
    Ok(SoundRef {
        src: 0,
        origin: String::new(),
        data_off: data_off as u32,
        data_len: data_len as u32,
        duration_ms,
        format,
    })
}

fn parse_header(r: &mut Reader, header_len: usize, data: &[u8]) -> std::result::Result<SoundFormat, String> {
    let e = |e: WzError| e.to_string();
    if header_len < MEDIA_TYPE_LEN {
        return Err(format!("media header is only {header_len} bytes"));
    }
    let decl = r.u8().map_err(e)?;
    if header_len == MEDIA_TYPE_LEN && decl != 2 {
        // No WAVEFORMATEX (format declaration 1, null format type): v83 has one such entry,
        // BgmGL.img/Amorianchallenge, whose data is an MP3 file with an ID3 tag.
        return if looks_like_mp3(data) {
            Ok(SoundFormat::Mp3(WaveFormat { tag: 0x55, channels: 0, rate: 0, avg_bytes: 0, block_align: 0, bits: 0 }))
        } else {
            Err(format!("no WAVEFORMATEX (format declaration {decl}) and the data is not MP3"))
        };
    }
    if header_len < MEDIA_TYPE_LEN + 1 {
        return Err(format!("{header_len}-byte media header has no WAVEFORMATEX"));
    }
    r.skip(MEDIA_TYPE_LEN - 1).map_err(e)?;
    let wfx_len = r.cint().map_err(e)?;
    if wfx_len < 16 || MEDIA_TYPE_LEN + 1 + wfx_len as usize != header_len {
        return Err(format!("media header is {header_len} bytes but WAVEFORMATEX length is {wfx_len}"));
    }
    let wf = WaveFormat {
        tag: r.u16().map_err(e)?,
        channels: r.u16().map_err(e)?,
        rate: r.u32().map_err(e)?,
        avg_bytes: r.u32().map_err(e)?,
        block_align: r.u16().map_err(e)?,
        bits: r.u16().map_err(e)?,
    };
    match wf.tag {
        0x55 => Ok(SoundFormat::Mp3(wf)),
        0x01 if wf.channels > 0 && wf.rate > 0 && matches!(wf.bits, 8 | 16 | 24 | 32) => Ok(SoundFormat::Pcm(wf)),
        tag => Err(format!(
            "unsupported WAVEFORMATEX (tag 0x{tag:04X}, {} ch, {} Hz, {} bits)",
            wf.channels, wf.rate, wf.bits
        )),
    }
}

/// True for data that starts with an ID3v2 tag or an MPEG audio frame sync.
pub fn looks_like_mp3(data: &[u8]) -> bool {
    data.starts_with(b"ID3") || (data.len() >= 2 && data[0] == 0xFF && data[1] & 0xE0 == 0xE0)
}

/// A canonical RIFF/WAVE file for PCM data.
pub fn wav_bytes(wf: &WaveFormat, data: &[u8]) -> Vec<u8> {
    let pad = data.len() % 2;
    let mut out = Vec::with_capacity(44 + data.len() + pad);
    out.extend_from_slice(b"RIFF");
    out.extend_from_slice(&((36 + data.len() + pad) as u32).to_le_bytes());
    out.extend_from_slice(b"WAVE");
    out.extend_from_slice(b"fmt ");
    out.extend_from_slice(&16u32.to_le_bytes());
    out.extend_from_slice(&1u16.to_le_bytes());
    out.extend_from_slice(&wf.channels.to_le_bytes());
    out.extend_from_slice(&wf.rate.to_le_bytes());
    out.extend_from_slice(&wf.avg_bytes.to_le_bytes());
    out.extend_from_slice(&wf.block_align.to_le_bytes());
    out.extend_from_slice(&wf.bits.to_le_bytes());
    out.extend_from_slice(b"data");
    out.extend_from_slice(&(data.len() as u32).to_le_bytes());
    out.extend_from_slice(data);
    if pad == 1 {
        out.push(0);
    }
    out
}
