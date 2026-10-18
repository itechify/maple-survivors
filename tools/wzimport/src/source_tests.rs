//! Public source/sink boundary tests using only generated archives.

use crate::archive::WzArchive;
use crate::source::ReadAt;
use crate::testutil::*;
use std::io;
use std::sync::Arc;

struct Memory(Vec<u8>);

#[test]
fn zip_import_visits_imgs_in_physical_order_and_preserves_cache_bytes() {
    let bytes = write_archive(
        &["z.img", "a.img", "m.img"].map(|name| WEntry::Img(name.into(), write_img(&[p("value", W::Int(42))], false))),
        83,
        false,
    );
    let manifest = r#"{"format":1,"imgs":[{"img":"Mob.wz/a.img"},{"img":"Mob.wz/m.img"},{"img":"Mob.wz/z.img"}]}"#;
    let plain = MemorySink::default();
    crate::import::import_sources(
        [("Mob.wz".into(), Arc::new(Memory(bytes.clone())) as Arc<dyn ReadAt>)].into(),
        manifest,
        &plain,
        &|_: &str, _, _| Ok(()),
    )
    .unwrap();
    let zip = write_zip(&[("83/Mob.wz", &bytes, true)]);
    let sources = crate::zip::zip_sources(Arc::new(Memory(zip))).unwrap();
    let zipped = MemorySink::default();
    let visited = std::sync::Mutex::new(Vec::new());
    let report = crate::import::import_sources(sources, manifest, &zipped, &|file: &str, _, _| {
        visited.lock().unwrap().push(file.to_string());
        Ok(())
    })
    .unwrap();
    assert!(report.errors.is_empty());
    assert_eq!(
        *visited.lock().unwrap(),
        ["Mob.wz/z.img", "Mob.wz/a.img", "Mob.wz/m.img"]
    );
    assert_eq!(*plain.0.lock().unwrap(), *zipped.0.lock().unwrap());
    assert_eq!(zipped.0.lock().unwrap()["Mob.wz/z.img.json"], br#"{"value":42}"#);
}
impl ReadAt for Memory {
    fn len(&self) -> u64 {
        self.0.len() as u64
    }
    fn read_exact_at(&self, offset: u64, buf: &mut [u8]) -> io::Result<()> {
        let bytes = self
            .0
            .get(offset as usize..)
            .and_then(|s| s.get(..buf.len()))
            .ok_or_else(|| io::Error::from(io::ErrorKind::UnexpectedEof))?;
        buf.copy_from_slice(bytes);
        Ok(())
    }
}

#[test]
fn archive_reads_edited_v83_from_injected_memory() {
    let bytes = write_archive(
        &[WEntry::Img(
            "edited.img".into(),
            write_img(&[p("value", W::Int(132))], false),
        )],
        83,
        false,
    );
    let archive = WzArchive::from_reader("Mob.wz", Arc::new(Memory(bytes)), Some(83)).unwrap();
    assert_eq!(
        archive
            .load_img("edited.img")
            .unwrap()
            .root
            .child("value")
            .unwrap()
            .as_i64(),
        Some(132)
    );
    assert_eq!(archive.version, 83);
}

#[test]
fn forced_v83_rejects_a_different_encrypted_version_even_with_no_imgs() {
    let bytes = write_archive(&[], 95, false);
    assert!(WzArchive::from_reader("Mob.wz", Arc::new(Memory(bytes)), Some(83)).is_err());
}

#[test]
fn named_sources_report_every_missing_required_archive() {
    let root = crate::wzroot::WzRoot::from_sources(Default::default());
    let manifest =
        crate::manifest::Manifest::parse(r#"{"format":1,"imgs":[{"img":"Sound.wz/a.img"},{"img":"Effect.wz/b.img"}]}"#)
            .unwrap();
    let error = root.require_archives(&manifest).unwrap_err().to_string();
    assert_eq!(error, "Effect.wz, Sound.wz not found in this source");
    let sink = MemorySink::default();
    let error = crate::import::import_sources(
        Default::default(),
        r#"{"format":1,"imgs":[{"img":"Sound.wz/a.img"},{"img":"Effect.wz/b.img"}]}"#,
        &sink,
        &|_: &str, _, _| Ok(()),
    )
    .unwrap_err()
    .to_string();
    assert_eq!(error, "Effect.wz, Sound.wz not found in this source");
    assert!(sink.0.lock().unwrap().is_empty());
}

#[test]
fn nested_zip_stored_and_deflated_entries_support_positional_reads() {
    let a = write_archive(
        &[WEntry::Img("a.img".into(), write_img(&[p("v", W::Int(7))], false))],
        83,
        false,
    );
    let b = write_archive(
        &[WEntry::Img("b.img".into(), write_img(&[p("v", W::Int(9))], false))],
        83,
        false,
    );
    let zip = write_zip(&[
        ("83/Mob.wz", &a, false),
        ("83/data/Effect.wz", &b, true),
        ("readme.txt", b"ignored", false),
    ]);
    let sources = crate::zip::zip_sources(Arc::new(Memory(zip))).unwrap();
    assert_eq!(sources.keys().cloned().collect::<Vec<_>>(), ["Effect.wz", "Mob.wz"]);
    for (name, expected) in [("Mob.wz", &a), ("Effect.wz", &b)] {
        let reader = &sources[name];
        for offset in [expected.len() / 2, 0, 64, expected.len() - 4] {
            let mut got = [0; 4];
            reader.read_exact_at(offset as u64, &mut got).unwrap();
            assert_eq!(got, expected[offset..offset + 4]);
        }
    }
    let root = crate::wzroot::WzRoot::from_sources(sources);
    assert_eq!(
        root.load_img("Effect.wz/b.img")
            .unwrap()
            .root
            .child("v")
            .unwrap()
            .as_i64(),
        Some(9)
    );
}

#[derive(Default)]
struct MemorySink(std::sync::Mutex<std::collections::BTreeMap<String, Vec<u8>>>);
impl crate::sink::Sink for MemorySink {
    fn create_dir(&self, _: &str) -> crate::Result<()> {
        Ok(())
    }
    fn write_file(&self, path: &str, bytes: &[u8]) -> crate::Result<()> {
        self.0.lock().unwrap().insert(path.to_string(), bytes.to_vec());
        Ok(())
    }
}

#[test]
fn folder_and_zip_sources_export_byte_identical_caches_through_sink() {
    let folder = TempDir::new("source-folder");
    let bytes = write_archive(
        &[WEntry::Img(
            "a.img".into(),
            write_img(
                &[
                    p("value", W::Int(42)),
                    p("pixel", canvas(1, 1, 2, vec![3, 2, 1, 255], false, vec![])),
                    p(
                        "audio",
                        W::Sound(WSound {
                            duration_ms: 100,
                            header: SoundHeader::Mp3 {
                                channels: 1,
                                rate: 22050,
                            },
                            data: b"synthetic audio".to_vec(),
                        }),
                    ),
                ],
                false,
            ),
        )],
        83,
        false,
    );
    std::fs::write(folder.path().join("Mob.wz"), &bytes).unwrap();
    let manifest = r#"{"format":1,"imgs":[{"img":"Mob.wz/a.img"}]}"#;
    let folder_sources = [(
        "Mob.wz".into(),
        Arc::new(std::fs::File::open(folder.path().join("Mob.wz")).unwrap()) as Arc<dyn ReadAt>,
    )]
    .into();
    let native = MemorySink::default();
    crate::import::import_sources(folder_sources, manifest, &native, &|_: &str, _, _| Ok(())).unwrap();
    assert_eq!(native.0.lock().unwrap()["Mob.wz/a.img.json"], br#"{"$pages":["Mob.wz/a.img.0.png"],"value":42,"pixel":{"$canvas":[0,0,0,1,1]},"audio":{"$sound":"Mob.wz/a.img/audio.mp3","$ms":100}}"#.to_vec());
    for deflated in [false, true] {
        let zip = write_zip(&[("83/Mob.wz", &bytes, deflated)]);
        let zipped = MemorySink::default();
        let sources = crate::zip::zip_sources(Arc::new(Memory(zip))).unwrap();
        let progress = std::sync::Mutex::new(Vec::new());
        let report = crate::import::import_sources(sources, manifest, &zipped, &|file: &str, done, total| {
            progress.lock().unwrap().push((file.to_string(), done, total));
            Ok(())
        })
        .unwrap();
        assert!(report.errors.is_empty());
        assert_eq!(*native.0.lock().unwrap(), *zipped.0.lock().unwrap());
        assert_eq!(*progress.lock().unwrap(), [("Mob.wz/a.img".into(), 1, 1)]);
    }
}

#[test]
fn large_deflated_entry_does_not_require_archive_sized_host_reads() {
    struct BoundedMemory(Vec<u8>);
    impl ReadAt for BoundedMemory {
        fn len(&self) -> u64 {
            self.0.len() as u64
        }
        fn read_exact_at(&self, offset: u64, buf: &mut [u8]) -> io::Result<()> {
            assert!(buf.len() <= 65557, "zip requested an archive-sized buffer");
            buf.copy_from_slice(&self.0[offset as usize..offset as usize + buf.len()]);
            Ok(())
        }
    }
    let mut data = vec![0; 16 * 1024 * 1024];
    data[..4].copy_from_slice(b"PKG1");
    data[16 * 1024 * 1024 - 4..].copy_from_slice(b"last");
    let zip = write_zip(&[("83/Mob.wz", &data, true)]);
    let sources = crate::zip::zip_sources(Arc::new(BoundedMemory(zip))).unwrap();
    let reader = &sources["Mob.wz"];
    let mut got = [0; 4];
    reader.read_exact_at(16 * 1024 * 1024 - 4, &mut got).unwrap();
    assert_eq!(&got, b"last");
    reader.read_exact_at(0, &mut got).unwrap();
    assert_eq!(&got, b"PKG1");
    assert!(reader.read_exact_at(reader.len() - 2, &mut got).is_err());
}

#[test]
fn zip_rejects_duplicate_basenames_and_truncated_directories() {
    let duplicate = write_zip(&[("one/Mob.wz", b"one", false), ("two/Mob.wz", b"two", false)]);
    assert!(crate::zip::zip_sources(Arc::new(Memory(duplicate)))
        .err()
        .unwrap()
        .to_string()
        .contains("duplicate archive Mob.wz"));
    for n in [0, 3, 21, 45] {
        assert!(crate::zip::zip_sources(Arc::new(Memory(vec![0; n]))).is_err());
    }
}

#[test]
fn zip64_sizes_and_directory_records_expose_the_same_reader() {
    let data = b"synthetic zip64 entry";
    let zip = write_zip(&[("83/Mob.wz", data, false)]);
    let old_end = zip.len() - 22;
    let central_at = u32::from_le_bytes(zip[old_end + 16..old_end + 20].try_into().unwrap()) as usize;
    let mut central = zip[central_at..old_end].to_vec();
    central[20..28].fill(255);
    central[42..46].fill(255);
    central[30..32].copy_from_slice(&28u16.to_le_bytes());
    central.extend_from_slice(&1u16.to_le_bytes());
    central.extend_from_slice(&24u16.to_le_bytes());
    for n in [data.len() as u64, data.len() as u64, 0] {
        central.extend_from_slice(&n.to_le_bytes());
    }
    let mut out = zip[..central_at].to_vec();
    out.extend_from_slice(&central);
    let zip64_at = out.len() as u64;
    out.extend_from_slice(&0x06064b50u32.to_le_bytes());
    out.extend_from_slice(&44u64.to_le_bytes());
    for n in [45u16, 45] {
        out.extend_from_slice(&n.to_le_bytes());
    }
    for n in [0u32, 0] {
        out.extend_from_slice(&n.to_le_bytes());
    }
    for n in [1u64, 1, central.len() as u64, central_at as u64] {
        out.extend_from_slice(&n.to_le_bytes());
    }
    out.extend_from_slice(&0x07064b50u32.to_le_bytes());
    out.extend_from_slice(&0u32.to_le_bytes());
    out.extend_from_slice(&zip64_at.to_le_bytes());
    out.extend_from_slice(&1u32.to_le_bytes());
    let mut end = zip[old_end..].to_vec();
    end[8..20].fill(255);
    out.extend_from_slice(&end);
    let sources = crate::zip::zip_sources(Arc::new(Memory(out))).unwrap();
    let mut got = vec![0; data.len()];
    sources["Mob.wz"].read_exact_at(0, &mut got).unwrap();
    assert_eq!(got, data);
}

#[test]
fn sparse_edited_directory_is_read_without_buffering_a_whole_large_archive() {
    struct Virtual(Vec<u8>);
    impl ReadAt for Virtual {
        fn len(&self) -> u64 {
            640 * 1024 * 1024
        }
        fn read_exact_at(&self, offset: u64, buf: &mut [u8]) -> io::Result<()> {
            assert!(buf.len() <= 16 * 1024 * 1024, "directory tried to buffer the archive");
            buf.fill(0);
            if offset < self.0.len() as u64 {
                let n = buf.len().min(self.0.len() - offset as usize);
                buf[..n].copy_from_slice(&self.0[offset as usize..offset as usize + n]);
            }
            Ok(())
        }
    }
    let mut header = write_archive(&[WEntry::Dir("far".into(), vec![])], 83, false);
    header[70..74].copy_from_slice(&crate::crypto::encrypt_offset(70, 32 * 1024 * 1024, 60, 1876).to_le_bytes());
    let archive = WzArchive::from_reader("Mob.wz", Arc::new(Virtual(header)), Some(83)).unwrap();
    assert!(archive.dir("far").unwrap().entries.is_empty());
}
