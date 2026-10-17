//! Synthetic-fixture tests: archives built by `testutil` are read back and exported.

use crate::archive::{EntryKind, WzArchive};
use crate::atlas::{self, Region};
use crate::canvas;
use crate::export::export_img;
use crate::import::{run_import, ImportOptions};
use crate::manifest::{expand, ImgRequest, Manifest};
use crate::property::{parse_img, Node, Value};
use crate::reader::Reader;
use crate::sound::SoundFormat;
use crate::testutil::*;
use crate::uol::resolve_all;
use crate::wzroot::WzRoot;
use std::collections::BTreeMap;
use std::path::Path;

fn img(props: Vec<(String, W)>) -> crate::property::Img {
    parse_img("Test.wz/t.img".into(), write_img(&props, true), 0).unwrap()
}

fn read_json(path: &Path) -> serde_json::Value {
    serde_json::from_str(&std::fs::read_to_string(path).unwrap()).unwrap()
}

/// Decode a PNG file to (w, h, rgba).
fn read_png(path: &Path) -> (u32, u32, Vec<u8>) {
    let dec = png::Decoder::new(std::io::BufReader::new(std::fs::File::open(path).unwrap()));
    let mut r = dec.read_info().unwrap();
    let mut buf = vec![0u8; r.output_buffer_size().unwrap()];
    let info = r.next_frame(&mut buf).unwrap();
    assert_eq!(info.color_type, png::ColorType::Rgba);
    buf.truncate(info.buffer_size());
    (info.width, info.height, buf)
}

fn crop(page: &(u32, u32, Vec<u8>), x: u32, y: u32, w: u32, h: u32) -> Vec<u8> {
    let mut out = Vec::new();
    for row in y..y + h {
        let s = ((row * page.0 + x) * 4) as usize;
        out.extend_from_slice(&page.2[s..s + (w * 4) as usize]);
    }
    out
}

// ---------------------------------------------------------------- strings, archive, version

#[test]
fn strings_all_forms_roundtrip() {
    let long_ascii = "a".repeat(300);
    let cases: Vec<(String, bool)> = vec![
        (String::new(), false),
        ("Property".into(), false),
        ("x".repeat(127), false), // longest short ASCII form (-127)
        ("y".repeat(128), false), // -128 + i32 long form
        (long_ascii, false),
        ("caf\u{e9} \u{2019}quoted\u{2019}".into(), false), // cp1252 single-byte chars
        ("\u{d55c}\u{ae00}".into(), false),                // UTF-16 short form
        ("u".repeat(126), true),                           // longest short UTF-16 form
        ("v".repeat(127), true),                           // 127 + i32 long form
        ("\u{c2a4}".repeat(400), false),                   // long UTF-16
    ];
    for (s, force) in cases {
        let enc = encode_wz_string(&s, force);
        let mut r = Reader::new(&enc, 0);
        assert_eq!(r.wz_string().unwrap(), s, "len {}", s.chars().count());
        assert_eq!(r.pos(), enc.len());
    }
    // the length prefixes really are the documented forms
    assert_eq!(encode_wz_string(&"x".repeat(127), false)[0] as i8, -127);
    assert_eq!(encode_wz_string(&"y".repeat(128), false)[0] as i8, -128);
    assert_eq!(encode_wz_string(&"u".repeat(126), true)[0], 126);
    assert_eq!(encode_wz_string(&"v".repeat(127), true)[0], 127);
}

fn sample_tree() -> Vec<WEntry> {
    let a = write_img(&[p("v", W::Int(1))], false);
    let b = write_img(&[p("v", W::Int(2))], true);
    vec![
        WEntry::Img("Physics.img".into(), a.clone()),
        WEntry::Dir(
            "Map".into(),
            vec![
                WEntry::Dir("Map1".into(), vec![WEntry::Img("100000000.img".into(), b.clone())]),
                WEntry::Dir("Map2".into(), vec![WEntry::Img("100000000.img".into(), a.clone())]),
            ],
        ),
        WEntry::Dir("Empty".into(), vec![]),
    ]
}

#[test]
fn archive_header_dirs_offsets_and_type2_names() {
    let dir = TempDir::new("archive");
    let path = dir.path().join("Map.wz");
    std::fs::write(&path, write_archive(&sample_tree(), 83, true)).unwrap();
    let a = WzArchive::open(&path).unwrap();
    assert_eq!(a.version, 83);
    assert_eq!(a.hash, 1876);
    assert_eq!(a.enc_version, 0xAC);
    assert_eq!(a.data_start, 60);
    assert_eq!(a.copyright, COPYRIGHT);
    assert_eq!(
        a.img_paths(),
        vec!["Physics.img", "Map/Map1/100000000.img", "Map/Map2/100000000.img"]
    );
    // the second "100000000.img" was written as a type-2 entry pointing at the first one's name
    let raw = std::fs::read(&path).unwrap();
    assert!(raw[62..].contains(&2));
    let e = a.entry("Map/Map2/100000000.img").unwrap();
    assert!(e.is_img());
    let img = a.load_img("Map/Map2/100000000.img").unwrap();
    assert_eq!(img.root.child("v").unwrap().value, Value::Int(1));
    assert_eq!(img.path, "Map.wz/Map/Map2/100000000.img");
    let img = a.load_img("Map/Map1/100000000.img").unwrap();
    assert_eq!(img.root.child("v").unwrap().value, Value::Int(2));
    assert!(matches!(&a.entry("Empty").unwrap().kind, EntryKind::Dir(d) if d.entries.is_empty()));
    assert!(a.entry("Map/Map3").is_none());
}

#[test]
fn version_fallback_detection() {
    let dir = TempDir::new("version");
    // 630 has the same encrypted version as 83 (0xAC): detection must try 83, reject it, and fall back.
    for v in [630u32, 95, 83] {
        let path = dir.path().join(format!("v{v}.wz"));
        std::fs::write(&path, write_archive(&sample_tree(), v, false)).unwrap();
        let a = WzArchive::open(&path).unwrap();
        assert_eq!(a.version, v);
        assert_eq!(a.load_img("Map/Map1/100000000.img").unwrap().root.child("v").unwrap().value, Value::Int(2));
    }
    // a forced wrong version fails cleanly
    let path = dir.path().join("v95.wz");
    assert!(WzArchive::open_with_version(&path, Some(83)).is_err());
}

// ---------------------------------------------------------------- properties

#[test]
fn every_property_type_decodes_exactly() {
    let props = vec![
        p("null", W::Null),
        p("short", W::Short(-1234)),
        p("short11", W::Short11(77)),
        p("int_small", W::Int(-5)),
        p("int_big", W::Int(123_456_789)),
        p("int_min", W::Int(i32::MIN)),
        p("long", W::Long(9_000_000_000)),
        p("float0", W::Float(0.0)),
        p("float", W::Float(0.35)),
        p("double", W::Double(-2.5e-3)),
        p("str", W::Str("Bgm01/CavaBien".into())),
        p("str_again", W::Str("Bgm01/CavaBien".into())), // offset form (dedupe)
        p("\u{d55c}", W::Str("\u{ae00}\u{c790}".into())),
        p("vec", W::Vector(-18, 26)),
        p("convex", W::Convex(vec![(0, 0), (10, -5), (3, 7)])),
        p("sub", sub(vec![p("a", W::Int(1)), p("b", sub(vec![p("c", W::Str("deep".into()))]))])),
        p("uol", W::Uol("../x/y".into())),
    ];
    for dedupe in [false, true] {
        let i = parse_img("T.wz/t.img".into(), write_img(&props, dedupe), 0).unwrap();
        let r = &i.root;
        assert_eq!(r.value, Value::Img);
        let names: Vec<&str> = r.children.iter().map(|c| c.name.as_str()).collect();
        assert_eq!(names, props.iter().map(|(n, _)| n.as_str()).collect::<Vec<_>>());
        assert_eq!(r.child("null").unwrap().value, Value::Null);
        assert_eq!(r.child("short").unwrap().value, Value::Short(-1234));
        assert_eq!(r.child("short11").unwrap().value, Value::Short(77));
        assert_eq!(r.child("int_small").unwrap().value, Value::Int(-5));
        assert_eq!(r.child("int_big").unwrap().value, Value::Int(123_456_789));
        assert_eq!(r.child("int_min").unwrap().value, Value::Int(i32::MIN));
        assert_eq!(r.child("long").unwrap().value, Value::Long(9_000_000_000));
        assert_eq!(r.child("float0").unwrap().value, Value::Float(0.0));
        assert_eq!(r.child("float").unwrap().value, Value::Float(0.35));
        assert_eq!(r.child("double").unwrap().value, Value::Double(-2.5e-3));
        assert_eq!(r.child("str").unwrap().value, Value::String("Bgm01/CavaBien".into()));
        assert_eq!(r.child("str_again").unwrap().value, Value::String("Bgm01/CavaBien".into()));
        assert_eq!(r.child("\u{d55c}").unwrap().value, Value::String("\u{ae00}\u{c790}".into()));
        assert_eq!(r.child("vec").unwrap().value, Value::Vector(-18, 26));
        let cv = r.child("convex").unwrap();
        assert_eq!(cv.value, Value::Convex);
        let pts: Vec<Value> = cv.children.iter().map(|c| c.value.clone()).collect();
        assert_eq!(pts, vec![Value::Vector(0, 0), Value::Vector(10, -5), Value::Vector(3, 7)]);
        assert_eq!(r.at("sub/b/c").unwrap().value, Value::String("deep".into()));
        assert_eq!(r.child("uol").unwrap().value, Value::Uol("../x/y".into()));
    }
}

// ---------------------------------------------------------------- canvases

fn canvas_of(i: &crate::property::Img, path: &str) -> crate::property::CanvasRef {
    match &i.root.at(path).unwrap().value {
        Value::Canvas(c) => (**c).clone(),
        v => panic!("{path} is {v:?}"),
    }
}

#[test]
fn canvas_formats_decode_to_exact_rgba() {
    // 2x2 BGRA4444: red opaque, green half, blue transparent-ish, white
    let px4444 = bgra4444(&[(0xF, 0, 0, 0xF), (0, 0xF, 0, 0x8), (0, 0, 0xF, 0x1), (0xF, 0xF, 0xF, 0xF)]);
    let rgba4444 = vec![255, 0, 0, 255, 0, 255, 0, 136, 0, 0, 255, 17, 255, 255, 255, 255];
    // 2x1 BGRA8888
    let px8888 = vec![0x10, 0x20, 0x30, 0x40, 0xAA, 0xBB, 0xCC, 0xDD];
    let rgba8888 = vec![0x30, 0x20, 0x10, 0x40, 0xCC, 0xBB, 0xAA, 0xDD];
    // 2x1 RGB565: pure red, (r=1, g=33, b=30)
    let p2: u16 = (1 << 11) | (33 << 5) | 30;
    let px565 = [0xF800u16.to_le_bytes(), p2.to_le_bytes()].concat();
    // bit replication: r 1 -> 8, g 33 -> (33 << 2) | (33 >> 4) = 134, b 30 -> (30 << 3) | (30 >> 2) = 247
    let rgba565 = vec![255, 0, 0, 255, 8, 134, 247, 255];
    // 517: 20x17 canvas -> 2x2 blocks of 16x16
    let blocks: Vec<u16> = vec![0xF800, 0x07E0, 0x001F, 0xFFFF];
    let px517: Vec<u8> = blocks.iter().flat_map(|b| b.to_le_bytes()).collect();

    for encrypted in [false, true] {
        let props = vec![
            p("c4444", canvas(2, 2, 1, px4444.clone(), encrypted, vec![p("origin", W::Vector(1, 2)), p("delay", W::Int(180))])),
            p("c8888", canvas(2, 1, 2, px8888.clone(), encrypted, vec![])),
            p("c565", canvas(2, 1, 513, px565.clone(), encrypted, vec![])),
            p("c517", canvas(20, 17, 517, px517.clone(), encrypted, vec![])),
        ];
        let i = img(props);
        let c = canvas_of(&i, "c4444");
        assert_eq!((c.width, c.height, c.format()), (2, 2, 1));
        assert_eq!(canvas::decode(&i.bytes, &c).unwrap(), rgba4444);
        assert_eq!(i.root.at("c4444/origin").unwrap().value, Value::Vector(1, 2));
        assert_eq!(i.root.at("c4444/delay").unwrap().value, Value::Int(180));
        assert_eq!(canvas::decode(&i.bytes, &canvas_of(&i, "c8888")).unwrap(), rgba8888);
        assert_eq!(canvas::decode(&i.bytes, &canvas_of(&i, "c565")).unwrap(), rgba565);
        let c517 = canvas_of(&i, "c517");
        assert_eq!((c517.fmt, c517.fmt2, c517.format()), (513, 4, 517));
        let out = canvas::decode(&i.bytes, &c517).unwrap();
        assert_eq!(out.len(), 20 * 17 * 4);
        let at = |x: usize, y: usize| out[(y * 20 + x) * 4..(y * 20 + x) * 4 + 4].to_vec();
        assert_eq!(at(0, 0), vec![255, 0, 0, 255]);
        assert_eq!(at(15, 15), vec![255, 0, 0, 255]);
        assert_eq!(at(16, 0), vec![0, 255, 0, 255]);
        assert_eq!(at(19, 15), vec![0, 255, 0, 255]);
        assert_eq!(at(0, 16), vec![0, 0, 255, 255]);
        assert_eq!(at(19, 16), vec![255, 255, 255, 255]);
        // encrypted data really is not plain zlib
        let data = &i.bytes[c.data_off as usize..];
        assert_eq!(data[..2] == [0x78, 0x9C], !encrypted);
    }
}

#[test]
fn corrupt_canvas_data_is_an_error() {
    let mut raw = write_img(&[p("c", canvas(4, 4, 1, solid4444(4, 4, (1, 2, 3, 4)), false, vec![]))], false);
    let i = parse_img("T.wz/t.img".into(), raw.clone(), 0).unwrap();
    let c = canvas_of(&i, "c");
    for b in &mut raw[c.data_off as usize + 2..(c.data_off + c.data_len) as usize] {
        *b = 0xFF;
    }
    assert!(canvas::decode(&raw, &c).is_err());
}

// ---------------------------------------------------------------- sounds

#[test]
fn sound_headers_mp3_pcm_and_malformed() {
    let mp3 = vec![0xFF, 0xF2, 0x90, 0x40, 1, 2, 3, 4, 5];
    let pcm: Vec<u8> = (0..20u8).collect();
    let id3 = b"ID3\x03\x00rest-of-mp3".to_vec();
    let props = vec![
        p("bgm", W::Sound(WSound { duration_ms: 128000, header: SoundHeader::Mp3 { channels: 2, rate: 22050 }, data: mp3.clone() })),
        p("pcm", W::Sound(WSound { duration_ms: 5, header: SoundHeader::Pcm { channels: 1, rate: 44100, bits: 16 }, data: pcm.clone() })),
        p("id3", W::Sound(WSound { duration_ms: 7, header: SoundHeader::NoWfx, data: id3.clone() })),
        p("bad", W::Sound(WSound { duration_ms: 9, header: SoundHeader::BadTag, data: vec![1, 2, 3] })),
        p("after", W::Int(42)),
    ];
    let i = img(props);
    let s = |n: &str| match &i.root.child(n).unwrap().value {
        Value::Sound(s) => (**s).clone(),
        v => panic!("{v:?}"),
    };
    let bgm = s("bgm");
    assert_eq!(bgm.duration_ms, 128000);
    assert!(matches!(bgm.format, SoundFormat::Mp3(wf) if wf.channels == 2 && wf.rate == 22050));
    assert_eq!(&i.bytes[bgm.data_off as usize..(bgm.data_off + bgm.data_len) as usize], &mp3[..]);
    assert_eq!(bgm.origin, "bgm");
    let pc = s("pcm");
    assert!(matches!(pc.format, SoundFormat::Pcm(wf) if wf.channels == 1 && wf.rate == 44100 && wf.bits == 16));
    assert_eq!(&i.bytes[pc.data_off as usize..(pc.data_off + pc.data_len) as usize], &pcm[..]);
    assert!(matches!(s("id3").format, SoundFormat::Mp3(_)));
    assert!(matches!(s("bad").format, SoundFormat::Malformed(_)));
    // parsing continues correctly after every sound
    assert_eq!(i.root.child("after").unwrap().value, Value::Int(42));

    if let SoundFormat::Pcm(wf) = pc.format {
        let wav = crate::sound::wav_bytes(&wf, &pcm);
        assert_eq!(&wav[0..4], b"RIFF");
        assert_eq!(u32::from_le_bytes(wav[4..8].try_into().unwrap()), 36 + 20);
        assert_eq!(&wav[8..16], b"WAVEfmt ");
        assert_eq!(u16::from_le_bytes(wav[20..22].try_into().unwrap()), 1);
        assert_eq!(u16::from_le_bytes(wav[22..24].try_into().unwrap()), 1);
        assert_eq!(u32::from_le_bytes(wav[24..28].try_into().unwrap()), 44100);
        assert_eq!(u32::from_le_bytes(wav[28..32].try_into().unwrap()), 88200);
        assert_eq!(u16::from_le_bytes(wav[32..34].try_into().unwrap()), 2);
        assert_eq!(u16::from_le_bytes(wav[34..36].try_into().unwrap()), 16);
        assert_eq!(&wav[36..40], b"data");
        assert_eq!(u32::from_le_bytes(wav[40..44].try_into().unwrap()), 20);
        assert_eq!(&wav[44..], &pcm[..]);
    }
}

// ---------------------------------------------------------------- UOLs

fn uol_img() -> Vec<(String, W)> {
    let head = canvas(2, 2, 1, solid4444(2, 2, (0xF, 0, 0, 0xF)), false, vec![
        p("origin", W::Vector(19, 17)),
        p("map", sub(vec![p("brow", W::Vector(-4, -5))])),
        p("z", W::Str("head".into())),
    ]);
    vec![
        p("front", sub(vec![p("head", head)])),
        p("stand1", sub(vec![
            p("0", sub(vec![p("head", W::Uol("../../front/head".into())), p("delay", W::Int(500))])),
            p("1", W::Uol("0".into())),                 // sibling UOL to a sub-tree that itself holds a UOL
            p("2", W::Uol("1".into())),                 // chain
        ])),
        p("cycle", sub(vec![p("self", W::Uol("..".into()))])),
        p("loopA", W::Uol("loopB".into())),
        p("loopB", W::Uol("loopA".into())),
        p("missing", W::Uol("nowhere/at/all".into())),
        p("str", W::Uol("../front/head/z".into())), // ".." from the img root's child level
    ]
}

#[test]
fn uol_resolution_deep_copies_and_guards() {
    let mut i = img(uol_img());
    let report = resolve_all(&mut i.root, "Test.wz/t.img", None);
    let head = i.root.at("front/head").unwrap().clone();
    let copy = i.root.at("stand1/0/head").unwrap();
    assert_eq!(copy.name, "head");
    assert_eq!(copy.value, head.value); // same canvas data reference
    assert_eq!(copy.children, head.children); // origin, map, z copied
    assert_eq!(i.root.at("stand1/1/head").unwrap().value, head.value);
    assert_eq!(i.root.at("stand1/1/delay").unwrap().value, Value::Int(500));
    assert_eq!(i.root.at("stand1/2/head/origin").unwrap().value, Value::Vector(19, 17));
    assert_eq!(i.root.child("str").unwrap().value, Value::Uol("../front/head/z".into()));
    let un: Vec<&str> = report.unresolved.iter().map(|u| u.path.as_str()).collect();
    assert_eq!(un, vec!["cycle/self", "loopA", "loopB", "missing", "str"]);
    assert_eq!(report.resolved, 3);
    assert!(report.unresolved[0].reason.starts_with("cycle: the target contains"), "{:?}", report.unresolved[0]);
    assert_eq!(report.unresolved[1].reason, "cycle between UOLs");
    assert!(matches!(i.root.at("cycle/self").unwrap().value, Value::Uol(_)));
}

#[test]
fn uol_into_another_img_of_the_same_directory() {
    let dir = TempDir::new("uolext");
    let a = write_img(&[p("x", canvas(1, 1, 1, bgra4444(&[(1, 2, 3, 4)]), false, vec![p("origin", W::Vector(5, 6))]))], false);
    let b = write_img(&[p("y", sub(vec![p("ref", W::Uol("../../a.img/x".into()))]))], false);
    write_wz_root(dir.path(), &[("E.wz", vec![WEntry::Img("a.img".into(), a), WEntry::Img("b.img".into(), b)])]);
    let wz = WzRoot::new(dir.path());
    let out = dir.path().join("cache");
    let r = export_img(&wz, "E.wz/b.img", &ImgRequest { whole: true, ..Default::default() }, &out).unwrap();
    assert_eq!(r.uol.external, 1);
    assert!(r.errors.is_empty() && r.warnings.is_empty(), "{:?} {:?}", r.errors, r.warnings);
    let j = read_json(&out.join("E.wz/b.img.json"));
    assert_eq!(j["$pages"], serde_json::json!(["E.wz/b.img.0.png"]));
    assert_eq!(j["y"]["ref"]["origin"]["$v"], serde_json::json!([5, 6]));
    let page = read_png(&out.join("E.wz/b.img.0.png"));
    let c = &j["y"]["ref"]["$canvas"];
    assert_eq!(crop(&page, c[1].as_u64().unwrap() as u32, c[2].as_u64().unwrap() as u32, 1, 1), vec![17, 34, 51, 68]);
}

// ---------------------------------------------------------------- atlas

#[test]
fn atlas_regions_do_not_overlap_and_keep_a_gap() {
    let mut seed = 12345u32;
    let mut rnd = |m: u32| {
        seed = seed.wrapping_mul(1_103_515_245).wrapping_add(12345);
        (seed >> 8) % m + 1
    };
    let mut sizes: Vec<(u32, u32)> = (0..600).map(|_| (rnd(300), rnd(200))).collect();
    sizes.push((2500, 340)); // wider than a page
    sizes.push((100, 3000)); // taller than a page
    sizes.push((2048, 2048)); // exactly a page
    sizes.push((0, 5)); // empty
    let l = atlas::pack(&sizes, 2048, 1);
    assert_eq!(l.regions.len(), sizes.len());
    for (i, r) in l.regions.iter().enumerate() {
        assert_eq!((r.w, r.h), sizes[i]);
        if r.w == 0 || r.h == 0 {
            continue;
        }
        let (pw, ph) = l.pages[r.page as usize];
        assert!(r.x + r.w <= pw && r.y + r.h <= ph, "region {i} {r:?} outside page {pw}x{ph}");
        assert!(pw <= 2048 && ph <= 2048 || (r.x == 0 && r.y == 0 && (pw, ph) == (r.w, r.h)));
    }
    let big = |w, h| l.regions[sizes.iter().position(|s| *s == (w, h)).unwrap()];
    for (w, h) in [(2500, 340), (100, 3000)] {
        let r = big(w, h);
        assert_eq!(l.pages[r.page as usize], (w, h), "oversize canvas gets its own page of exactly its size");
    }
    let overlap = |a: &Region, b: &Region| {
        // expand a by the 1 px gap: rectangles must not even touch
        a.page == b.page && a.x < b.x + b.w + 1 && b.x < a.x + a.w + 1 && a.y < b.y + b.h + 1 && b.y < a.y + a.h + 1
    };
    let live: Vec<&Region> = l.regions.iter().filter(|r| r.w > 0 && r.h > 0).collect();
    for i in 0..live.len() {
        for j in i + 1..live.len() {
            assert!(!overlap(live[i], live[j]), "{:?} and {:?} overlap or touch", live[i], live[j]);
        }
    }
}

// ---------------------------------------------------------------- export: JSON shape, dedupe, paths

#[test]
fn export_json_shape_pages_and_dedupe() {
    let dir = TempDir::new("export");
    let red = solid4444(3, 2, (0xF, 0, 0, 0xF));
    let blue = solid4444(2, 2, (0, 0, 0xF, 0x8));
    let t = vec![
        p("info", sub(vec![p("level", W::Int(1)), p("speed", W::Int(-65)), p("rate", W::Float(1.5)), p("name", W::Str("Snail".into()))])),
        p("move", sub(vec![
            p("zigzag", W::Int(1)),
            p("0", canvas(3, 2, 1, red, false, vec![p("origin", W::Vector(1, 2)), p("delay", W::Int(180))])),
            p("1", canvas(2, 2, 1, blue, true, vec![p("origin", W::Vector(0, 2))])),
            p("2", W::Uol("0".into())),
        ])),
        p("shape", W::Convex(vec![(1, 2), (3, 4)])),
        p("nothing", W::Null),
        p("sfx", W::Sound(WSound { duration_ms: 384, header: SoundHeader::Mp3 { channels: 1, rate: 22050 }, data: vec![0xFF, 0xFB, 1, 2] })),
        p("pcm", W::Sound(WSound { duration_ms: 10, header: SoundHeader::Pcm { channels: 1, rate: 8000, bits: 8 }, data: vec![1, 2, 3] })),
        p("bad", W::Sound(WSound { duration_ms: 1, header: SoundHeader::BadTag, data: vec![9] })),
        p("dangling", W::Uol("../nope".into())),
    ];
    write_wz_root(dir.path(), &[("Mob.wz", vec![WEntry::Img("0100100.img".into(), write_img(&t, true))])]);
    let wz = WzRoot::new(dir.path());
    let out = dir.path().join("cache");
    let r = export_img(&wz, "Mob.wz/0100100.img", &ImgRequest { whole: true, ..Default::default() }, &out).unwrap();
    assert_eq!(r.canvases, 2, "the UOL copy of move/0 shares its canvas");
    assert_eq!(r.pages, 1);
    assert_eq!(r.sounds, 2);
    assert!(r.errors.is_empty(), "{:?}", r.errors);
    assert_eq!(r.warnings.len(), 2, "{:?}", r.warnings); // malformed sound + unresolved UOL
    let text = std::fs::read_to_string(out.join("Mob.wz/0100100.img.json")).unwrap();
    let j: serde_json::Value = serde_json::from_str(&text).unwrap();
    let c0 = j["move"]["0"]["$canvas"].clone();
    let c1 = j["move"]["1"]["$canvas"].clone();
    let expected = format!(
        concat!(
            r#"{{"$pages":["Mob.wz/0100100.img.0.png"],"info":{{"level":1,"speed":-65,"rate":1.5,"name":"Snail"}},"#,
            r#""move":{{"zigzag":1,"0":{{"$canvas":{c0},"origin":{{"$v":[1,2]}},"delay":180}},"#,
            r#""1":{{"$canvas":{c1},"origin":{{"$v":[0,2]}}}},"#,
            r#""2":{{"$canvas":{c0},"origin":{{"$v":[1,2]}},"delay":180}}}},"#,
            r#""shape":{{"$convex":[[1,2],[3,4]]}},"nothing":null,"#,
            r#""sfx":{{"$sound":"Mob.wz/0100100.img/sfx.mp3","$ms":384}},"#,
            r#""pcm":{{"$sound":"Mob.wz/0100100.img/pcm.wav","$ms":10}},"bad":null,"#,
            r#""dangling":{{"$uol":"../nope"}}}}"#
        ),
        c0 = c0,
        c1 = c1
    );
    assert_eq!(text, expected);
    // keys keep WZ order (serde_json without preserve_order sorts, so compare the raw text order)
    assert!(text.find("\"info\"").unwrap() < text.find("\"move\"").unwrap());
    assert!(text.find("\"zigzag\"").unwrap() < text.find("\"0\"").unwrap());

    // regions line up with the page pixels
    let page = read_png(&out.join("Mob.wz/0100100.img.0.png"));
    let reg = |c: &serde_json::Value| -> Vec<u32> { c.as_array().unwrap().iter().map(|v| v.as_u64().unwrap() as u32).collect() };
    let (r0, r1) = (reg(&c0), reg(&c1));
    assert_eq!((r0[0], r0[3], r0[4]), (0, 3, 2));
    assert_eq!(crop(&page, r0[1], r0[2], 3, 2), [255u8, 0, 0, 255].repeat(6));
    assert_eq!(crop(&page, r1[1], r1[2], 2, 2), [0u8, 0, 255, 136].repeat(4));
    assert_eq!(std::fs::read(out.join("Mob.wz/0100100.img/sfx.mp3")).unwrap(), vec![0xFF, 0xFB, 1, 2]);
    let wav = std::fs::read(out.join("Mob.wz/0100100.img/pcm.wav")).unwrap();
    assert_eq!(&wav[0..4], b"RIFF");
    assert_eq!(&wav[44..47], &[1, 2, 3]);
}

#[test]
fn export_paths_writes_only_selected_subtrees() {
    let dir = TempDir::new("paths");
    let t = vec![
        p("back", sub(vec![
            p("0", canvas(4, 4, 1, solid4444(4, 4, (1, 1, 1, 15)), false, vec![])),
            p("1", canvas(5, 5, 1, solid4444(5, 5, (2, 2, 2, 15)), false, vec![])),
            p("2", canvas(6, 6, 1, solid4444(6, 6, (3, 3, 3, 15)), false, vec![])),
        ])),
        p("ani", sub(vec![p("0", sub(vec![p("0", W::Uol("../../back/1".into()))]))])),
        p("other", W::Int(5)),
    ];
    write_wz_root(dir.path(), &[("Map.wz", vec![WEntry::Dir("Back".into(), vec![WEntry::Img("x.img".into(), write_img(&t, true))])])]);
    let wz = WzRoot::new(dir.path());
    let out = dir.path().join("cache");
    let mut req = ImgRequest::default();
    req.paths.insert("back/2".into(), false);
    req.paths.insert("ani/0".into(), false);
    req.paths.insert("back/9".into(), false); // missing derived path -> warning
    let r = export_img(&wz, "Map.wz/Back/x.img", &req, &out).unwrap();
    assert_eq!(r.paths, Some(vec!["ani/0".to_string(), "back/2".to_string(), "back/9".to_string()]));
    assert_eq!(r.canvases, 2, "only canvases of written sub-trees are packed (back/2 and the UOL copy of back/1)");
    assert_eq!(r.warnings.len(), 1, "{:?}", r.warnings);
    let text = std::fs::read_to_string(out.join("Map.wz/Back/x.img.json")).unwrap();
    let j: serde_json::Value = serde_json::from_str(&text).unwrap();
    assert_eq!(j["back"].as_object().unwrap().keys().collect::<Vec<_>>(), vec!["2"]);
    assert_eq!(j["ani"]["0"]["0"]["$canvas"][3], 5);
    assert!(j.get("other").is_none());
    assert!(text.find("\"back\"").unwrap() < text.find("\"ani\"").unwrap(), "WZ order, not request order");

    // an explicit missing path is an error
    let mut req = ImgRequest::default();
    req.paths.insert("nope".into(), true);
    let r = export_img(&wz, "Map.wz/Back/x.img", &req, &out).unwrap();
    assert_eq!(r.errors.len(), 1);
}

// ---------------------------------------------------------------- manifest expansion

#[test]
fn potion_manifest_exports_item_use_sounds_and_resolves_links() {
    let dir = TempDir::new("potion_sounds");
    let data = vec![0xFF, 0xF2, 0x90, 0x40, 1, 2, 3, 4];
    let mut items = vec![p("02000000", sub(vec![p("Use", W::Sound(WSound {
        duration_ms: 433,
        header: SoundHeader::Mp3 { channels: 1, rate: 22050 },
        data: data.clone(),
    }))]))];
    for id in 2000001..=2000006 {
        items.push(p(&format!("{id:08}"), sub(vec![p("Use", W::Uol("../02000000/Use".into()))])));
    }
    items.push(p("02000007", sub(vec![p("Use", W::Int(99))])));
    write_wz_root(dir.path(), &[("Sound.wz", vec![WEntry::Img("Item.img".into(), write_img(&items, true))])]);
    // Use the shipping selection, restricted to this fixture's archive.
    let shipping: serde_json::Value = serde_json::from_str(include_str!("../../../game/data/asset_manifest.json")).unwrap();
    let entry = shipping["imgs"].as_array().unwrap().iter()
        .find(|e| e["img"] == "Sound.wz/Item.img").expect("manifest must select potion use sounds");
    let manifest = dir.path().join("manifest.json");
    std::fs::write(&manifest, serde_json::json!({"format": 1, "imgs": [entry]}).to_string()).unwrap();
    let out = dir.path().join("cache");
    let r = run_import(&ImportOptions { wz: dir.path().to_path_buf(), manifest, out: out.clone(), force: false }).unwrap();
    assert!(r.errors.is_empty(), "{:?}", r.errors);
    assert!(r.warnings.is_empty(), "{:?}", r.warnings);
    let exported = read_json(&out.join("Sound.wz/Item.img.json"));
    for id in 2000000..=2000006 {
        assert_eq!(exported[format!("{id:08}")]["Use"], serde_json::json!({
            "$sound": "Sound.wz/Item.img/02000000/Use.mp3", "$ms": 433
        }));
    }
    assert_eq!(std::fs::read(out.join("Sound.wz/Item.img/02000000/Use.mp3")).unwrap(), data);
    assert!(exported.get("02000007").is_none());
}

fn synthetic_world(dir: &Path) {
    let map = write_img(
        &[
            p("info", sub(vec![p("bgm", W::Str("Bgm01/CavaBien".into())), p("mapMark", W::Str("Henesys".into()))])),
            p("back", sub(vec![
                p("0", sub(vec![p("bS", W::Str("grassySoil".into())), p("no", W::Int(0)), p("ani", W::Int(0))])),
                p("1", sub(vec![p("bS", W::Str("grassySoil".into())), p("no", W::Int(2)), p("ani", W::Int(1))])),
                p("2", sub(vec![p("bS", W::Str("".into())), p("no", W::Int(0)), p("ani", W::Int(0))])),
                p("3", sub(vec![p("bS", W::Str("missingBack".into())), p("no", W::Int(0)), p("ani", W::Int(0))])),
            ])),
            p("life", sub(vec![
                p("0", sub(vec![p("type", W::Str("m".into())), p("id", W::Str("0100101".into()))])),
                p("1", sub(vec![p("type", W::Str("n".into())), p("id", W::Str("9000068".into()))])),
                p("2", sub(vec![p("type", W::Str("m".into())), p("id", W::Str("0100101".into()))])),
            ])),
            p("0", sub(vec![
                p("info", sub(vec![])),
                p("tile", sub(vec![])),
                p("obj", sub(vec![p("0", sub(vec![
                    p("oS", W::Str("acc1".into())),
                    p("l0", W::Str("grassySoil".into())),
                    p("l1", W::Str("nature".into())),
                    p("l2", W::Str("0".into())),
                ]))])),
            ])),
            p("1", sub(vec![p("info", sub(vec![p("tS", W::Str("grassySoil".into()))])), p("tile", sub(vec![])), p("obj", sub(vec![]))])),
        ],
        true,
    );
    let small = |_n: &str| canvas(2, 2, 1, solid4444(2, 2, (9, 9, 9, 15)), false, vec![]);
    let back = write_img(
        &[
            p("back", sub(vec![p("0", canvas(2, 2, 1, solid4444(2, 2, (1, 2, 3, 15)), false, vec![]))])),
            p("ani", sub(vec![p("2", sub(vec![p("0", canvas(2, 2, 1, solid4444(2, 2, (3, 2, 1, 15)), false, vec![p("delay", W::Int(100))]))]))])),
        ],
        false,
    );
    let helper = write_img(
        &[
            p("portal", sub(vec![p("game", sub(vec![p("pv", small("0"))]))])),
            p("mark", sub(vec![p("Henesys", canvas(2, 2, 1, solid4444(2, 2, (5, 5, 5, 15)), false, vec![])), p("Ellinia", W::Null)])),
        ],
        false,
    );
    let obj = write_img(&[p("grassySoil", sub(vec![p("nature", sub(vec![p("0", small("0")), p("1", small("0"))]))]))], false);
    let tile = write_img(&[p("bsc", sub(vec![p("0", small("0"))]))], false);
    write_wz_root(
        dir,
        &[
            (
                "Map.wz",
                vec![
                    WEntry::Img("MapHelper.img".into(), helper),
                    WEntry::Dir("Back".into(), vec![WEntry::Img("grassySoil.img".into(), back)]),
                    WEntry::Dir("Obj".into(), vec![WEntry::Img("acc1.img".into(), obj)]),
                    WEntry::Dir("Tile".into(), vec![WEntry::Img("grassySoil.img".into(), tile)]),
                    WEntry::Dir("Map".into(), vec![WEntry::Dir("Map1".into(), vec![WEntry::Img("104040000.img".into(), map)])]),
                ],
            ),
            (
                "Mob.wz",
                vec![
                    WEntry::Img("0100101.img".into(), write_img(&[p("info", sub(vec![p("link", W::Str("0100100".into()))]))], false)),
                    WEntry::Img(
                        "0100100.img".into(),
                        write_img(&[p("info", sub(vec![p("level", W::Int(1))])), p("stand", sub(vec![p("0", small("x"))]))], false),
                    ),
                ],
            ),
            (
                "Sound.wz",
                vec![
                    WEntry::Img(
                        "Bgm01.img".into(),
                        write_img(
                            &[
                                p("CavaBien", W::Sound(WSound { duration_ms: 128000, header: SoundHeader::Mp3 { channels: 2, rate: 22050 }, data: vec![0xFF, 0xF2, 0, 0] })),
                                p("Other", W::Sound(WSound { duration_ms: 1, header: SoundHeader::Mp3 { channels: 2, rate: 22050 }, data: vec![0xFF, 0xF2, 9, 9] })),
                            ],
                            false,
                        ),
                    ),
                    WEntry::Img(
                        "Mob.img".into(),
                        write_img(&[p("0100100", sub(vec![p("Die", W::Sound(WSound { duration_ms: 384, header: SoundHeader::Mp3 { channels: 1, rate: 22050 }, data: vec![0xFF, 0xF3, 1] }))]))], false),
                    ),
                ],
            ),
            ("Item.wz", vec![WEntry::Dir("Etc".into(), vec![WEntry::Img("0400.img".into(), write_img(&[p("04000019", sub(vec![p("info", sub(vec![]))]))], false))])]),
        ],
    );
}

#[test]
fn manifest_expansion_on_a_synthetic_map() {
    let dir = TempDir::new("manifest");
    synthetic_world(dir.path());
    let wz = WzRoot::new(dir.path());
    let m = Manifest::parse(r#"{"format":1,"_doc":"x","maps":[104040000],"items":[4000019],"imgs":[{"img":"Map.wz/MapHelper.img","paths":["mark"]}]}"#).unwrap();
    let plan = expand(&m, &wz);
    let got: BTreeMap<&str, Option<Vec<String>>> = plan.imgs.iter().map(|(k, v)| (k.as_str(), v.output_paths())).collect();
    let s = |v: &[&str]| Some(v.iter().map(|x| x.to_string()).collect::<Vec<_>>());
    let expected: BTreeMap<&str, Option<Vec<String>>> = [
        ("Item.wz/Etc/0400.img", s(&["04000019"])),
        ("Map.wz/Back/grassySoil.img", s(&["ani/2", "back/0"])),
        ("Map.wz/Map/Map1/104040000.img", None),
        ("Map.wz/MapHelper.img", s(&["mark", "portal"])),
        ("Map.wz/Obj/acc1.img", s(&["grassySoil/nature/0"])),
        ("Map.wz/Tile/grassySoil.img", None),
        ("Mob.wz/0100100.img", None),
        ("Mob.wz/0100101.img", None),
        ("Sound.wz/Bgm01.img", s(&["CavaBien"])),
        ("Sound.wz/Mob.img", s(&["0100100", "0100101"])),
    ]
    .into_iter()
    .collect();
    assert_eq!(got, expected);
    assert_eq!(plan.errors, Vec::<String>::new());
    assert_eq!(plan.warnings.len(), 1, "{:?}", plan.warnings); // missingBack.img
    assert!(plan.mobs.contains(&100100) && plan.mobs.contains(&100101));

    let bad = Manifest::parse(r#"{"format":1,"maps":[999999999],"mobs":[1],"character":[1802000],"imgs":[{"img":"Map.wz/Nope.img"}]}"#).unwrap();
    assert_eq!(expand(&bad, &wz).errors.len(), 4);
    assert!(Manifest::parse(r#"{"format":2}"#).is_err());
}

/// A login-scene-like world: `UI.wz/MapLogin.img` is map-structured (backs, layer objs, BGM, map mark) and its
/// dependencies live in Map.wz / Sound.wz like a normal map's.
fn synthetic_login_world(dir: &Path) {
    let login = write_img(
        &[
            p("info", sub(vec![p("bgm", W::Str("BgmUI/Title".into())), p("mapMark", W::Str("None".into()))])),
            p("back", sub(vec![
                p("0", sub(vec![p("bS", W::Str("login".into())), p("no", W::Int(11)), p("ani", W::Int(0))])),
                p("1", sub(vec![p("bS", W::Str("login".into())), p("no", W::Int(0)), p("ani", W::Int(1))])),
            ])),
            p("life", sub(vec![])),
            p("0", sub(vec![
                p("info", sub(vec![])),
                p("tile", sub(vec![])),
                p("obj", sub(vec![p("0", sub(vec![
                    p("oS", W::Str("login".into())),
                    p("l0", W::Str("Title".into())),
                    p("l1", W::Str("logo".into())),
                    p("l2", W::Str("0".into())),
                ]))])),
            ])),
            p("4", sub(vec![
                p("info", sub(vec![])),
                p("tile", sub(vec![])),
                p("obj", sub(vec![p("0", sub(vec![
                    p("oS", W::Str("login".into())),
                    p("l0", W::Str("Title".into())),
                    p("l1", W::Str("signboard".into())),
                    p("l2", W::Str("0".into())),
                ]))])),
            ])),
        ],
        true,
    );
    let small = || canvas(2, 2, 1, solid4444(2, 2, (9, 9, 9, 15)), false, vec![]);
    let back = write_img(
        &[
            p("back", sub(vec![p("11", small()), p("12", small())])),
            p("ani", sub(vec![p("0", sub(vec![p("0", small())]))])),
        ],
        false,
    );
    let obj = write_img(
        &[p("Title", sub(vec![
            p("logo", sub(vec![p("0", sub(vec![p("0", small())]))])),
            p("signboard", sub(vec![p("0", sub(vec![p("0", small())]))])),
            p("effect", sub(vec![p("0", sub(vec![p("0", small())]))])),
        ]))],
        false,
    );
    let helper = write_img(&[p("portal", sub(vec![p("game", sub(vec![p("pv", small())]))])), p("mark", sub(vec![]))], false);
    let mp3 = |d: u8| W::Sound(WSound { duration_ms: 1000, header: SoundHeader::Mp3 { channels: 2, rate: 44100 }, data: vec![0xFF, 0xFB, d] });
    write_wz_root(
        dir,
        &[
            ("UI.wz", vec![WEntry::Img("MapLogin.img".into(), login)]),
            (
                "Map.wz",
                vec![
                    WEntry::Img("MapHelper.img".into(), helper),
                    WEntry::Dir("Back".into(), vec![WEntry::Img("login.img".into(), back)]),
                    WEntry::Dir("Obj".into(), vec![WEntry::Img("login.img".into(), obj)]),
                ],
            ),
            ("Sound.wz", vec![WEntry::Img("BgmUI.img".into(), write_img(&[p("Title", mp3(1)), p("WCSelect", mp3(2))], false))]),
        ],
    );
}

#[test]
fn mapimgs_expand_like_maps() {
    let dir = TempDir::new("mapimgs");
    synthetic_login_world(dir.path());
    let wz = WzRoot::new(dir.path());
    let m = Manifest::parse(r#"{"format":1,"mapimgs":["UI.wz/MapLogin.img"]}"#).unwrap();
    let plan = expand(&m, &wz);
    let got: BTreeMap<&str, Option<Vec<String>>> = plan.imgs.iter().map(|(k, v)| (k.as_str(), v.output_paths())).collect();
    let s = |v: &[&str]| Some(v.iter().map(|x| x.to_string()).collect::<Vec<_>>());
    let expected: BTreeMap<&str, Option<Vec<String>>> = [
        ("UI.wz/MapLogin.img", None),
        ("Map.wz/Back/login.img", s(&["ani/0", "back/11"])),
        ("Map.wz/Obj/login.img", s(&["Title/logo/0", "Title/signboard/0"])),
        ("Map.wz/MapHelper.img", s(&["portal"])), // mapMark "None" = no mark
        ("Sound.wz/BgmUI.img", s(&["Title"])),
    ]
    .into_iter()
    .collect();
    assert_eq!(got, expected);
    assert_eq!(plan.errors, Vec::<String>::new());
    assert!(plan.warnings.is_empty(), "{:?}", plan.warnings);

    // a missing mapimg is an error naming it
    let bad = Manifest::parse(r#"{"format":1,"mapimgs":["UI.wz/Nope.img"]}"#).unwrap();
    let errs = expand(&bad, &wz).errors;
    assert_eq!(errs.len(), 1);
    assert!(errs[0].contains("mapimg UI.wz/Nope.img"), "{errs:?}");

    // the import writes the scene and its dependencies (only the used back/obj sub-trees and the BGM)
    let manifest = dir.path().join("manifest.json");
    std::fs::write(&manifest, r#"{"format":1,"mapimgs":["UI.wz/MapLogin.img"]}"#).unwrap();
    let out = dir.path().join("out");
    let r = run_import(&ImportOptions { wz: dir.path().to_path_buf(), manifest, out: out.clone(), force: false }).unwrap();
    assert!(r.errors.is_empty(), "{:?}", r.errors);
    assert_eq!(r.written.len(), 5);
    let scene = read_json(&out.join("UI.wz/MapLogin.img.json"));
    assert_eq!(scene["info"]["bgm"], "BgmUI/Title");
    assert_eq!(scene["back"]["0"]["bS"], "login");
    let back = read_json(&out.join("Map.wz/Back/login.img.json"));
    assert!(back["back"]["11"]["$canvas"].is_array());
    assert!(back["back"].get("12").is_none());
    let obj = read_json(&out.join("Map.wz/Obj/login.img.json"));
    assert!(obj["Title"]["logo"]["0"]["0"]["$canvas"].is_array());
    assert!(obj["Title"].get("effect").is_none());
    assert!(out.join("Sound.wz/BgmUI.img/Title.mp3").is_file());
    assert!(!out.join("Sound.wz/BgmUI.img/WCSelect.mp3").exists());
}

// ---------------------------------------------------------------- full import + incremental

#[test]
fn import_etc_creation_options_preserves_numeric_columns_and_names() {
    let dir = TempDir::new("etc_creation");
    write_wz_root(dir.path(), &[("Etc.wz", vec![WEntry::Img("MakeCharInfo.img".into(), write_img(&[
        ("Info".into(), W::Sub(vec![("CharMale".into(), W::Sub(vec![
            ("7".into(), W::Sub(vec![("0".into(), W::Int(1234567)), ("1".into(), W::Int(7654321))]))
        ]))])),
        ("Name".into(), W::Sub(vec![("CharMale".into(), W::Sub(vec![
            ("2".into(), W::Sub(vec![("7".into(), W::Str("Synthetic brown".into()))]))
        ]))])),
    ], true))])]);
    let manifest = dir.path().join("manifest.json");
    std::fs::write(&manifest, r#"{"format":1,"imgs":[{"img":"Etc.wz/MakeCharInfo.img","paths":["Info/CharMale","Name/CharMale"]}]}"#).unwrap();
    let out = dir.path().join("out");
    let result = run_import(&ImportOptions { wz: dir.path().into(), manifest, out: out.clone(), force: false }).unwrap();
    assert!(result.errors.is_empty(), "{:?}", result.errors);
    let tree = read_json(&out.join("Etc.wz/MakeCharInfo.img.json"));
    assert_eq!(tree["Info"]["CharMale"]["7"], serde_json::json!({"0":1234567,"1":7654321}));
    assert_eq!(tree["Name"]["CharMale"]["2"]["7"], "Synthetic brown");
    assert!(result.index.sources.contains_key("Etc.wz"));
}

#[test]
fn import_writes_cache_and_skips_up_to_date_imgs() {
    let dir = TempDir::new("import");
    synthetic_world(dir.path());
    let manifest = dir.path().join("manifest.json");
    std::fs::write(&manifest, r#"{"format":1,"maps":[104040000],"items":[4000019],"imgs":[{"img":"Map.wz/MapHelper.img","paths":["mark"]}]}"#).unwrap();
    let out = dir.path().join("out");
    let opts = ImportOptions { wz: dir.path().to_path_buf(), manifest: manifest.clone(), out: out.clone(), force: false };
    let r1 = run_import(&opts).unwrap();
    assert!(r1.errors.is_empty(), "{:?}", r1.errors);
    assert_eq!(r1.written.len(), 10);
    assert!(r1.skipped.is_empty());
    let idx = read_json(&out.join("cache.json"));
    assert_eq!(idx["format"], 1);
    assert_eq!(idx["importer"], crate::IMPORTER_VERSION);
    assert_eq!(idx["stats"]["imgs"], 10);
    assert!(idx["sources"]["Map.wz"]["size"].as_u64().unwrap() > 0);
    assert_eq!(idx["imgs"]["Mob.wz/0100100.img"]["json"], "Mob.wz/0100100.img.json");
    assert_eq!(idx["imgs"]["Mob.wz/0100100.img"]["pages"], 1);
    assert_eq!(idx["imgs"]["Mob.wz/0100100.img"]["paths"], serde_json::Value::Null);
    assert_eq!(idx["imgs"]["Sound.wz/Bgm01.img"]["paths"], serde_json::json!(["CavaBien"]));
    assert!(out.join("Sound.wz/Bgm01.img/CavaBien.mp3").is_file());
    assert!(!out.join("Sound.wz/Bgm01.img/Other.mp3").exists());
    let bgm = read_json(&out.join("Sound.wz/Bgm01.img.json"));
    assert_eq!(bgm, serde_json::json!({"CavaBien": {"$sound": "Sound.wz/Bgm01.img/CavaBien.mp3", "$ms": 128000}}));
    let helper = read_json(&out.join("Map.wz/MapHelper.img.json"));
    assert!(helper["mark"]["Henesys"]["$canvas"].is_array() && helper["portal"]["game"]["pv"].is_object());

    // second run: everything up to date, nothing rewritten
    let json_path = out.join("Mob.wz/0100100.img.json");
    let before = std::fs::metadata(&json_path).unwrap().modified().unwrap();
    std::thread::sleep(std::time::Duration::from_millis(30));
    let r2 = run_import(&opts).unwrap();
    assert!(r2.written.is_empty(), "{:?}", r2.written);
    assert_eq!(r2.skipped.len(), 10);
    assert_eq!(std::fs::metadata(&json_path).unwrap().modified().unwrap(), before);
    assert_eq!(read_json(&out.join("cache.json"))["stats"]["imgs"], 10);

    // a manifest change that adds a sub-path re-exports only that img
    std::fs::write(&manifest, r#"{"format":1,"maps":[104040000],"items":[4000019],"imgs":[{"img":"Map.wz/MapHelper.img","paths":["mark"]},{"img":"Sound.wz/Bgm01.img","paths":["Other"]}]}"#).unwrap();
    let r3 = run_import(&opts).unwrap();
    assert_eq!(r3.written, vec!["Sound.wz/Bgm01.img".to_string()]);
    assert!(out.join("Sound.wz/Bgm01.img/Other.mp3").is_file());

    // a deleted page forces a rewrite of that img; --force rewrites everything
    std::fs::remove_file(out.join("Mob.wz/0100100.img.0.png")).unwrap();
    let r4 = run_import(&opts).unwrap();
    assert_eq!(r4.written, vec!["Mob.wz/0100100.img".to_string()]);
    let r5 = run_import(&ImportOptions { force: true, ..opts.clone() }).unwrap();
    assert_eq!(r5.written.len(), 10);
}

#[test]
fn node_helpers() {
    let n = Node { name: "r".into(), value: Value::Sub, children: vec![Node::leaf("a", Value::String("12".into()))] };
    assert_eq!(n.at("a").unwrap().as_i64(), Some(12));
    assert_eq!(n.count(), 2);
}

/// Item.wz `Special` items (type 9, the meso coins 09000000-09000003) resolve to `Item.wz/Special/0900.img` and export
/// their sub-tree (spec #33 / #107).
#[test]
fn special_items_resolve_and_export() {
    let dir = TempDir::new("special_items");
    let frame = |c: u8| canvas(2, 2, 1, solid4444(2, 2, (c, 0, 0, 15)), false, vec![]);
    let coin = |frames: u8| {
        sub(vec![p("info", sub(vec![p("iconRaw", sub((0..frames).map(|i| p(&i.to_string(), frame(i))).collect()))]))])
    };
    let img = write_img(&[p("09000000", coin(4)), p("09000001", coin(4)), p("09000009", coin(1))], false);
    write_wz_root(dir.path(), &[("Item.wz", vec![WEntry::Dir("Special".into(), vec![WEntry::Img("0900.img".into(), img)])])]);
    let wz = WzRoot::new(dir.path());
    let m = Manifest::parse(r#"{"format":1,"items":[9000000,9000001]}"#).unwrap();
    let plan = expand(&m, &wz);
    assert_eq!(plan.errors, Vec::<String>::new());
    let got: BTreeMap<&str, Option<Vec<String>>> = plan.imgs.iter().map(|(k, v)| (k.as_str(), v.output_paths())).collect();
    assert_eq!(got["Item.wz/Special/0900.img"], Some(vec!["09000000".to_string(), "09000001".to_string()]));

    let manifest = dir.path().join("manifest.json");
    std::fs::write(&manifest, r#"{"format":1,"items":[9000000,9000001]}"#).unwrap();
    let out = dir.path().join("out");
    let r = run_import(&ImportOptions { wz: dir.path().to_path_buf(), manifest, out: out.clone(), force: false }).unwrap();
    assert!(r.errors.is_empty(), "{:?}", r.errors);
    let tree = read_json(&out.join("Item.wz/Special/0900.img.json"));
    assert!(tree["09000000"]["info"]["iconRaw"]["3"]["$canvas"].is_array());
    assert!(tree["09000001"]["info"]["iconRaw"]["0"]["$canvas"].is_array());
    assert!(tree.get("09000009").is_none(), "only the requested items export");
}
