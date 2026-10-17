//! Public source/sink boundary tests using only generated archives.

use crate::archive::WzArchive;
use crate::source::ReadAt;
use crate::testutil::*;
use std::io;
use std::sync::Arc;

struct Memory(Vec<u8>);
impl ReadAt for Memory {
    fn len(&self) -> u64 { self.0.len() as u64 }
    fn read_exact_at(&self, offset: u64, buf: &mut [u8]) -> io::Result<()> {
        let bytes = self.0.get(offset as usize..).and_then(|s| s.get(..buf.len()))
            .ok_or_else(|| io::Error::from(io::ErrorKind::UnexpectedEof))?;
        buf.copy_from_slice(bytes);
        Ok(())
    }
}

#[test]
fn archive_reads_edited_v83_from_injected_memory() {
    let bytes = write_archive(&[WEntry::Img("edited.img".into(), write_img(&[p("value", W::Int(132))], false))], 83, false);
    let archive = WzArchive::from_reader("Mob.wz", Arc::new(Memory(bytes)), Some(83)).unwrap();
    assert_eq!(archive.load_img("edited.img").unwrap().root.child("value").unwrap().as_i64(), Some(132));
    assert_eq!(archive.version, 83);
}

#[test]
fn named_sources_report_every_missing_required_archive() {
    let root = crate::wzroot::WzRoot::from_sources(Default::default());
    let manifest = crate::manifest::Manifest::parse(r#"{"format":1,"imgs":[{"img":"Sound.wz/a.img"},{"img":"Effect.wz/b.img"}]}"#).unwrap();
    let error = root.require_archives(&manifest).unwrap_err().to_string();
    assert_eq!(error, "Effect.wz, Sound.wz not found in this source");
}
