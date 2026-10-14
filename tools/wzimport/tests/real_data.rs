//! Integration tests against the player's real v83 WZ files. They run only when MAPLE_WZ_ROOT is set
//! (otherwise they print SKIP and pass, which proves nothing).

use std::path::PathBuf;
use wzimport::archive::WzArchive;
use wzimport::canvas;
use wzimport::import::{run_import, ImportOptions};
use wzimport::property::{CanvasRef, Node, Value};
use wzimport::sound::SoundFormat;
use wzimport::wzroot::WzRoot;

fn wz_root() -> Option<PathBuf> {
    match std::env::var_os("MAPLE_WZ_ROOT") {
        Some(p) => Some(PathBuf::from(p)),
        None => {
            eprintln!("SKIP: MAPLE_WZ_ROOT not set");
            None
        }
    }
}

fn node<'a>(root: &'a Node, path: &str) -> &'a Node {
    root.at(path).unwrap_or_else(|| panic!("{path} not found"))
}

fn canvas_ref(n: &Node) -> CanvasRef {
    match &n.value {
        Value::Canvas(c) => (**c).clone(),
        v => panic!("{} is {v:?}, not a canvas", n.name),
    }
}

#[test]
fn every_archive_is_version_83() {
    let Some(root) = wz_root() else { return };
    let mut n = 0;
    for name in [
        "Base.wz", "Character.wz", "Effect.wz", "Etc.wz", "Item.wz", "Map.wz", "Mob.wz", "Morph.wz", "Npc.wz", "Quest.wz",
        "Reactor.wz", "Skill.wz", "Sound.wz", "String.wz", "TamingMob.wz", "UI.wz",
    ] {
        let a = WzArchive::open(root.join(name)).unwrap_or_else(|e| panic!("{name}: {e}"));
        assert_eq!(a.version, 83, "{name}");
        assert_eq!(a.enc_version, 0xAC, "{name}");
        assert_eq!(a.data_start, 60, "{name}");
        n += 1;
    }
    assert_eq!(n, 16);
}

#[test]
fn physics_img_values() {
    let Some(root) = wz_root() else { return };
    let img = WzRoot::new(&root).load_img("Map.wz/Physics.img").unwrap();
    let f = |k: &str| node(&img.root, k).as_f64().unwrap();
    assert_eq!(f("walkSpeed"), 125.0);
    assert_eq!(f("jumpSpeed"), 555.0);
    assert_eq!(f("gravityAcc"), 2000.0);
    assert_eq!(f("fallSpeed"), 670.0);
    assert!(matches!(node(&img.root, "flyJumpDec").value, Value::Float(_)));
    assert!((f("flyJumpDec") - 0.35).abs() < 1e-6);
    assert_eq!(img.root.children.len(), 19);
}

#[test]
fn snail_move_frame() {
    let Some(root) = wz_root() else { return };
    let img = WzRoot::new(&root).load_img("Mob.wz/0100100.img").unwrap();
    let f = node(&img.root, "move/0");
    let c = canvas_ref(f);
    assert_eq!((c.width, c.height, c.format()), (37, 26, 1));
    assert_eq!(node(f, "origin").value, Value::Vector(18, 26));
    assert_eq!(node(f, "delay").value, Value::Int(180));
    assert_eq!(canvas::decode(&img.bytes, &c).unwrap().len(), 37 * 26 * 4);
}

#[test]
fn henesys_hunting_ground_footholds_and_bgm() {
    let Some(root) = wz_root() else { return };
    let img = WzRoot::new(&root).load_img("Map.wz/Map/Map1/104040000.img").unwrap();
    let fh: usize = node(&img.root, "foothold")
        .children
        .iter()
        .flat_map(|layer| layer.children.iter())
        .map(|group| group.children.len())
        .sum();
    assert_eq!(fh, 181);
    assert_eq!(node(&img.root, "info/bgm").value, Value::String("Bgm01/CavaBien".into()));
}

#[test]
fn string_mob_name() {
    let Some(root) = wz_root() else { return };
    let img = WzRoot::new(&root).load_img("String.wz/Mob.img").unwrap();
    assert_eq!(node(&img.root, "100100/name").value, Value::String("Snail".into()));
}

#[test]
fn slime_block_encrypted_canvas() {
    let Some(root) = wz_root() else { return };
    let img = WzRoot::new(&root).load_img("Mob.wz/0210100.img").unwrap();
    let c = canvas_ref(node(&img.root, "move/0"));
    let data = &img.bytes[c.data_off as usize..(c.data_off + c.data_len) as usize];
    assert!(!canvas::looks_like_zlib(data), "expected a block-encrypted canvas");
    let rgba = canvas::decode(&img.bytes, &c).unwrap();
    assert_eq!(rgba.len(), (c.width * c.height * 4) as usize);
    assert!(rgba.chunks(4).any(|p| p[3] == 255), "decoded canvas has opaque pixels");
}

#[test]
fn cavabien_is_mp3_of_128_seconds() {
    let Some(root) = wz_root() else { return };
    let img = WzRoot::new(&root).load_img("Sound.wz/Bgm01.img").unwrap();
    let Value::Sound(s) = &node(&img.root, "CavaBien").value else { panic!("not a sound") };
    assert_eq!(s.duration_ms, 128000);
    assert_eq!(s.data_len, 1_280_000);
    assert!(matches!(s.format, SoundFormat::Mp3(wf) if wf.tag == 0x55 && wf.rate == 22050 && wf.channels == 2));
    let data = &img.bytes[s.data_off as usize..];
    assert_eq!(&data[..2], &[0xFF, 0xF2], "MPEG-2 Layer III frame sync");
}

#[test]
fn pcm_and_headerless_mp3_sounds() {
    let Some(root) = wz_root() else { return };
    let wz = WzRoot::new(&root);
    let pet = wz.load_img("Sound.wz/Pet.img").unwrap();
    let mut pcm = 0;
    let mut stack = vec![&pet.root];
    while let Some(n) = stack.pop() {
        if let Value::Sound(s) = &n.value {
            if let SoundFormat::Pcm(wf) = s.format {
                assert_eq!((wf.channels, wf.rate, wf.bits), (1, 44100, 16));
                pcm += 1;
            }
        }
        stack.extend(n.children.iter());
    }
    assert_eq!(pcm, 27, "Pet.img holds 27 of the 40 PCM sounds (the other 13 are in Mob.img)");
    let gl = wz.load_img("Sound.wz/BgmGL.img").unwrap();
    let Value::Sound(s) = &node(&gl.root, "Amorianchallenge").value else { panic!("not a sound") };
    assert!(matches!(s.format, SoundFormat::Mp3(wf) if wf.rate == 0), "{:?}", s.format);
    assert_eq!(&gl.bytes[s.data_off as usize..s.data_off as usize + 3], b"ID3");
}

/// Decode a cache page PNG.
fn read_png(path: &std::path::Path) -> (u32, Vec<u8>) {
    let mut r = png::Decoder::new(std::io::BufReader::new(std::fs::File::open(path).unwrap())).read_info().unwrap();
    let mut buf = vec![0u8; r.output_buffer_size().unwrap()];
    let info = r.next_frame(&mut buf).unwrap();
    buf.truncate(info.buffer_size());
    (info.width, buf)
}

#[test]
fn real_import_of_a_small_manifest() {
    let Some(root) = wz_root() else { return };
    let tmp = std::env::temp_dir().join(format!("wzimport-real-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&tmp);
    std::fs::create_dir_all(&tmp).unwrap();
    let manifest = tmp.join("manifest.json");
    std::fs::write(&manifest, r#"{"format":1,"maps":[104040000],"character":[12000,1040002,1060002,1072001,1302000,1372005],"mobs":[210100],"imgs":[{"img":"Skill.wz/MobSkill.img"}]}"#).unwrap();
    let out = tmp.join("cache");
    let r = run_import(&ImportOptions { wz: root, manifest, out: out.clone(), force: false }).unwrap();
    assert!(r.errors.is_empty(), "{:?}", r.errors);
    let json = |p: &str| -> serde_json::Value { serde_json::from_str(&std::fs::read_to_string(out.join(p)).unwrap()).unwrap() };
    // UOL copy: the head of stand1/0 is front/head, with the same atlas region and its children
    let head = json("Character.wz/00012000.img.json");
    assert_eq!(head["stand1"]["0"]["head"], head["front"]["head"]);
    assert_eq!(head["stand1"]["0"]["head"]["origin"]["$v"], serde_json::json!([19, 17]));
    assert_eq!(head["front"]["head"]["$canvas"].as_array().unwrap()[3..], [39, 35]);
    // The canonical starter equipment and boss skill tables are available to run setup.
    let coat = json("Character.wz/Coat/01040002.img.json");
    let pants = json("Character.wz/Pants/01060002.img.json");
    let shoes = json("Character.wz/Shoes/01072001.img.json");
    assert_eq!(coat["info"]["incPDD"].as_i64().unwrap()
        + pants["info"]["incPDD"].as_i64().unwrap()
        + shoes["info"]["incPDD"].as_i64().unwrap(), 7);
    assert_eq!(json("Character.wz/Weapon/01302000.img.json")["info"]["attackSpeed"], 4);
    assert_eq!(json("Character.wz/Weapon/01372005.img.json")["info"]["incMAD"], 23);
    let mob_skill = json("Skill.wz/MobSkill.img.json");
    for skill in ["112", "113", "114", "126", "140", "200"] {
        assert!(!mob_skill[skill]["level"].as_object().unwrap().is_empty(), "{skill}");
    }
    // backs: only the used sub-paths, back/2 is the 2493x340 hill on its own page
    let back = json("Map.wz/Back/grassySoil.img.json");
    assert_eq!(back["back"].as_object().unwrap().len(), 5);
    assert_eq!(back["back"]["2"]["$canvas"].as_array().unwrap()[1..], [0, 0, 2493, 340]);
    let map = json("Map.wz/Map/Map1/104040000.img.json");
    assert_eq!(map["info"]["bgm"], "Bgm01/CavaBien");
    let mp3 = std::fs::read(out.join("Sound.wz/Bgm01.img/CavaBien.mp3")).unwrap();
    assert_eq!(mp3.len(), 1_280_000);
    let bgm = json("Sound.wz/Bgm01.img.json");
    assert_eq!(bgm["CavaBien"], serde_json::json!({"$sound": "Sound.wz/Bgm01.img/CavaBien.mp3", "$ms": 128000}));
    // the map's mobs were pulled in, and the encrypted Slime exported
    for id in ["0120100", "0100101", "0130101", "1210100", "0210100"] {
        assert!(out.join(format!("Mob.wz/{id}.img.json")).is_file(), "{id}");
    }
    let slime = json("Mob.wz/0210100.img.json");
    assert_eq!(slime["move"]["0"]["$canvas"].as_array().unwrap()[3..], [70, 51]);
    // every Slime region cut from its page equals the canvas decoded straight from Mob.wz
    let src = WzRoot::new(std::env::var_os("MAPLE_WZ_ROOT").unwrap()).load_img("Mob.wz/0210100.img").unwrap();
    let pages: Vec<(u32, Vec<u8>)> =
        slime["$pages"].as_array().unwrap().iter().map(|p| read_png(&out.join(p.as_str().unwrap()))).collect();
    let mut checked = 0;
    for stance in ["move", "stand", "hit1", "die1", "jump"] {
        for (frame, v) in slime[stance].as_object().unwrap() {
            let Some(region) = v["$canvas"].as_array() else { continue };
            let r: Vec<u32> = region.iter().map(|x| x.as_u64().unwrap() as u32).collect();
            let (pw, px) = &pages[r[0] as usize];
            let mut cut = Vec::new();
            for y in r[2]..r[2] + r[4] {
                let s = ((y * pw + r[1]) * 4) as usize;
                cut.extend_from_slice(&px[s..s + (r[3] * 4) as usize]);
            }
            let c = canvas_ref(node(&src.root, &format!("{stance}/{frame}")));
            assert_eq!(cut, canvas::decode(&src.bytes, &c).unwrap(), "{stance}/{frame}");
            checked += 1;
        }
    }
    assert_eq!(checked, 16);
    let _ = std::fs::remove_dir_all(&tmp);
}

#[test]
fn real_import_of_henesys_flyers_and_sounds() {
    let Some(root) = wz_root() else { return };
    let source: serde_json::Value = serde_json::from_str(include_str!("../../../game/data/asset_manifest.json")).unwrap();
    let flyers = [9300063_u32, 9300062, 9300064, 2300100];
    for id in flyers {
        assert!(source["mobs"].as_array().unwrap().contains(&serde_json::json!(id)), "manifest omits {id}");
    }
    let tmp = std::env::temp_dir().join(format!("wzimport-real-flyers-{}", std::process::id()));
    std::fs::create_dir_all(&tmp).unwrap();
    let manifest = tmp.join("manifest.json");
    std::fs::write(&manifest, serde_json::to_vec(&serde_json::json!({"format": 1, "mobs": flyers})).unwrap()).unwrap();
    let out = tmp.join("cache");
    let result = run_import(&ImportOptions { wz: root, manifest, out: out.clone(), force: true }).unwrap();
    assert!(result.errors.is_empty(), "{:?}", result.errors);
    let read_json = |p: &str| -> serde_json::Value {
        serde_json::from_str(&std::fs::read_to_string(out.join(p)).unwrap()).unwrap()
    };
    let sounds = read_json("Sound.wz/Mob.img.json");
    for (id, level, hp, pad) in [(9300063, 6, 60, 22), (9300062, 8, 80, 25), (9300064, 11, 155, 35), (2300100, 20, 300, 85)] {
        let mob = read_json(&format!("Mob.wz/{id:07}.img.json"));
        assert_eq!(mob["info"]["level"], level);
        assert_eq!(mob["info"]["maxHP"], hp);
        assert_eq!(mob["info"]["PADamage"], pad);
        assert_eq!(mob["info"]["bodyAttack"], 1);
        assert!(mob["info"]["flySpeed"].is_number());
        assert!(mob.get("attack1").is_none(), "{id} has only touch damage");
        for stance in ["fly", "hit1", "die1"] {
            let region = mob[stance]["0"]["$canvas"].as_array().unwrap_or_else(|| panic!("{id}/{stance}"));
            assert!(region[3].as_u64().unwrap() > 0 && region[4].as_u64().unwrap() > 0);
            let page = mob["$pages"][region[0].as_u64().unwrap() as usize].as_str().unwrap();
            assert!(out.join(page).is_file(), "{id}/{stance} page");
        }
        for action in ["Damage", "Die"] {
            let path = sounds[format!("{id:07}")][action]["$sound"].as_str().unwrap_or_else(|| panic!("{id}/{action}"));
            assert!(std::fs::metadata(out.join(path)).unwrap().len() > 0, "{id}/{action} audio");
        }
    }
    std::fs::remove_dir_all(tmp).unwrap();
}

#[test]
fn real_import_of_henesys_bosses_and_sounds() {
    let Some(root) = wz_root() else { return };
    let source: serde_json::Value = serde_json::from_str(include_str!("../../../game/data/asset_manifest.json")).unwrap();
    let bosses = [2220000_u32, 6130101, 9400205];
    for id in bosses {
        assert!(source["mobs"].as_array().unwrap().contains(&serde_json::json!(id)), "manifest omits {id}");
    }
    let tmp = std::env::temp_dir().join(format!("wzimport-real-bosses-{}", std::process::id()));
    std::fs::create_dir_all(&tmp).unwrap();
    let manifest = tmp.join("manifest.json");
    std::fs::write(&manifest, serde_json::to_vec(&serde_json::json!({"format": 1, "mobs": bosses})).unwrap()).unwrap();
    let out = tmp.join("cache");
    let result = run_import(&ImportOptions { wz: root, manifest, out: out.clone(), force: true }).unwrap();
    assert!(result.errors.is_empty(), "{:?}", result.errors);
    let read_json = |p: &str| -> serde_json::Value {
        serde_json::from_str(&std::fs::read_to_string(out.join(p)).unwrap()).unwrap()
    };
    let sounds = read_json("Sound.wz/Mob.img.json");
    for (id, hp, pad) in [(2220000, 2000, 90), (6130101, 20000, 200), (9400205, 200000, 450)] {
        let mob = read_json(&format!("Mob.wz/{id:07}.img.json"));
        assert_eq!(mob["info"]["maxHP"], hp);
        assert_eq!(mob["info"]["PADamage"], pad);
        assert_eq!(mob["info"]["boss"], 1);
        assert!(mob["move"]["0"]["$canvas"].is_array(), "{id} movement art");
        for action in ["Damage", "Die"] {
            let path = sounds[format!("{id:07}")][action]["$sound"].as_str().unwrap_or_else(|| panic!("{id}/{action}"));
            assert!(std::fs::metadata(out.join(path)).unwrap().len() > 0, "{id}/{action} audio");
        }
    }
    std::fs::remove_dir_all(tmp).unwrap();
}
