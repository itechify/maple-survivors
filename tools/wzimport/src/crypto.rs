//! GMS v83 WZ cryptography: the AES keystream, the version hash and the offset key.
//!
//! The keystream is AES-256-ECB applied repeatedly to the IV: `block0 = E(IV)`, `blockN = E(blockN-1)`
//! (equivalently AES-256-OFB over zeros). It XOR-masks WZ strings and block-encrypted canvas data.
//! Facts: docs/ASSET_PIPELINE.md section 3.

use aes::cipher::{generic_array::GenericArray, BlockEncrypt, KeyInit};
use aes::Aes256;
use std::sync::{OnceLock, RwLock};

/// The GMS "user key" trimmed to every 4th byte (32 bytes for AES-256).
pub const GMS_USER_KEY: [u8; 32] = [
    0x13, 0x00, 0x00, 0x00, 0x08, 0x00, 0x00, 0x00, 0x06, 0x00, 0x00, 0x00, 0xB4, 0x00, 0x00, 0x00, 0x1B, 0x00, 0x00,
    0x00, 0x0F, 0x00, 0x00, 0x00, 0x33, 0x00, 0x00, 0x00, 0x52, 0x00, 0x00, 0x00,
];

/// The GMS IV (repeated 4 times to make a 16-byte block).
pub const GMS_IV: [u8; 4] = [0x4D, 0x23, 0xC7, 0x2B];

/// Constant subtracted in the directory offset decryption.
pub const OFFSET_KEY: u32 = 0x581C_3F6D;

/// A lazily grown, thread-safe keystream.
pub struct Keystream {
    cipher: Aes256,
    iv: [u8; 16],
    bytes: RwLock<Vec<u8>>,
}

impl Keystream {
    /// Keystream for `key` and a 4-byte IV repeated to 16 bytes.
    pub fn new(key: &[u8; 32], iv4: [u8; 4]) -> Self {
        let mut iv = [0u8; 16];
        for (i, b) in iv.iter_mut().enumerate() {
            *b = iv4[i % 4];
        }
        Keystream { cipher: Aes256::new(GenericArray::from_slice(key)), iv, bytes: RwLock::new(Vec::new()) }
    }

    /// The process-wide GMS keystream.
    pub fn gms() -> &'static Keystream {
        static KS: OnceLock<Keystream> = OnceLock::new();
        KS.get_or_init(|| Keystream::new(&GMS_USER_KEY, GMS_IV))
    }

    /// Make sure at least `len` keystream bytes exist.
    pub fn ensure(&self, len: usize) {
        if self.bytes.read().unwrap().len() >= len {
            return;
        }
        let mut bytes = self.bytes.write().unwrap();
        if bytes.len() >= len {
            return;
        }
        let have = bytes.len();
        let target = len.max(have * 2).max(4096).next_multiple_of(16);
        let mut block = if bytes.is_empty() {
            GenericArray::clone_from_slice(&self.iv)
        } else {
            GenericArray::clone_from_slice(&bytes[bytes.len() - 16..])
        };
        bytes.reserve(target - have);
        while bytes.len() < target {
            self.cipher.encrypt_block(&mut block);
            bytes.extend_from_slice(&block);
        }
    }

    /// Run `f` with a view of the first `len` keystream bytes.
    pub fn with<R>(&self, len: usize, f: impl FnOnce(&[u8]) -> R) -> R {
        self.ensure(len);
        let bytes = self.bytes.read().unwrap();
        f(&bytes[..len])
    }

    /// XOR `data` in place with the keystream starting at keystream byte 0.
    pub fn xor(&self, data: &mut [u8]) {
        self.with(data.len(), |ks| {
            for (d, k) in data.iter_mut().zip(ks) {
                *d ^= *k;
            }
        });
    }
}

/// WZ version hash of a decimal version string: `h = 32*h + c + 1` over its characters.
pub fn version_hash(version: u32) -> u32 {
    let mut h: u32 = 0;
    for c in version.to_string().bytes() {
        h = h.wrapping_mul(32).wrapping_add(c as u32).wrapping_add(1);
    }
    h
}

/// The encrypted version stored at dataStart: `0xFF ^ b3 ^ b2 ^ b1 ^ b0` of the hash.
pub fn enc_version(hash: u32) -> u16 {
    let b = hash.to_le_bytes();
    (0xFF ^ b[0] ^ b[1] ^ b[2] ^ b[3]) as u16
}

/// Decrypt a directory-entry offset. `pos` is the file position of the stored u32 itself.
pub fn decrypt_offset(pos: u32, stored: u32, data_start: u32, hash: u32) -> u32 {
    let o = offset_mask(pos, data_start, hash);
    (o ^ stored).wrapping_add(data_start.wrapping_mul(2))
}

/// Inverse of [`decrypt_offset`] (used by the test writer).
pub fn encrypt_offset(pos: u32, actual: u32, data_start: u32, hash: u32) -> u32 {
    let o = offset_mask(pos, data_start, hash);
    o ^ actual.wrapping_sub(data_start.wrapping_mul(2))
}

fn offset_mask(pos: u32, data_start: u32, hash: u32) -> u32 {
    let mut o = !(pos.wrapping_sub(data_start));
    o = o.wrapping_mul(hash);
    o = o.wrapping_sub(OFFSET_KEY);
    o.rotate_left(o & 31)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn v83_hash_and_enc_version() {
        assert_eq!(version_hash(83), 1876);
        assert_eq!(enc_version(1876), 0xAC);
        let candidates: Vec<u32> = (1..400).filter(|v| enc_version(version_hash(*v)) == 0xAC).collect();
        assert_eq!(candidates, vec![83]);
    }

    #[test]
    fn keystream_matches_aes_ecb_chain() {
        // First two blocks of E(IV), E(E(IV)) computed independently with Node's crypto (aes-256-ecb, no padding).
        let expected: [u8; 32] = [
            0x96, 0xAE, 0x3F, 0xA4, 0x48, 0xFA, 0xDD, 0x90, 0x46, 0x76, 0x05, 0x61, 0x97, 0xCE, 0x78, 0x68, 0x2B, 0xA0,
            0x44, 0x8F, 0xC1, 0x56, 0x7E, 0x32, 0xFC, 0xE1, 0xF5, 0xB3, 0x14, 0x14, 0xC5, 0x22,
        ];
        let ks = Keystream::new(&GMS_USER_KEY, GMS_IV);
        ks.with(32, |b| assert_eq!(b, &expected));
        // growing past the first chunk keeps the prefix and continues the chain
        ks.ensure(10_000);
        ks.with(32, |b| assert_eq!(b, &expected));
        let a = ks.with(10_000, |b| b[9_984..10_000].to_vec());
        let fresh = Keystream::new(&GMS_USER_KEY, GMS_IV);
        assert_eq!(fresh.with(10_000, |b| b[9_984..10_000].to_vec()), a);
    }

    #[test]
    fn offset_roundtrip() {
        for (pos, actual) in [(62u32, 1000u32), (12345, 98_765_432), (60, 60), (4_000_000, 7)] {
            let stored = encrypt_offset(pos, actual, 60, 1876);
            assert_eq!(decrypt_offset(pos, stored, 60, 1876), actual);
        }
    }
}
