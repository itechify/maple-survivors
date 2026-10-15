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
fn real_import_of_basic_weapon_afterimages_and_sounds() {
    let Some(root) = wz_root() else { return };
    let source: serde_json::Value = serde_json::from_str(include_str!("../../../game/data/asset_manifest.json")).unwrap();
    let names = ["Character.wz/Afterimage/swordOL.img", "Character.wz/Afterimage/mace.img", "Character.wz/Afterimage/hit.img", "Sound.wz/Weapon.img"];
    let imgs: Vec<_> = source["imgs"].as_array().unwrap().iter().filter(|e| names.contains(&e["img"].as_str().unwrap())).cloned().collect();
    assert_eq!(imgs.len(), 4, "all basic-attack manifest entries");
    let tmp = std::env::temp_dir().join(format!("wzimport-real-basic-{}", std::process::id()));
    std::fs::create_dir_all(&tmp).unwrap();
    let manifest = tmp.join("manifest.json");
    std::fs::write(&manifest, serde_json::to_vec(&serde_json::json!({"format": 1, "imgs": imgs, "character": [2000, 1302000, 1372005]})).unwrap()).unwrap();
    let out = tmp.join("cache");
    let result = run_import(&ImportOptions { wz: root, manifest, out: out.clone(), force: true }).unwrap();
    assert!(result.errors.is_empty(), "{:?}", result.errors);
    assert!(result.warnings.is_empty(), "{:?}", result.warnings);
    let json = |p: &str| -> serde_json::Value { serde_json::from_str(&std::fs::read_to_string(out.join(p)).unwrap()).unwrap() };
    for (id, pad, mad, speed, image, sfx) in [(1302000,17,0,4,"swordOL","swordL"),(1372005,15,23,6,"mace","mace")] {
        let weapon = json(&format!("Character.wz/Weapon/{id:08}.img.json"));
        assert_eq!(weapon["info"]["incPAD"], pad);
        assert_eq!(weapon["info"]["incMAD"].as_i64().unwrap_or(0), mad);
        assert_eq!(weapon["info"]["attackSpeed"], speed);
        assert_eq!(weapon["info"]["afterImage"], image);
        assert_eq!(weapon["info"]["sfx"], sfx);
        let ai = json(&format!("Character.wz/Afterimage/{image}.img.json"));
        for action in ["swingO1","swingO2","swingO3","stabO1","stabO2"] {
            let node = &ai["0"][action];
            assert!(node["lt"]["$v"].is_array() && node["rb"]["$v"].is_array());
            let frame = node.as_object().unwrap().iter().find(|(k,_)| k.parse::<u32>().is_ok()).unwrap().1;
            assert!(frame["0"]["$canvas"].is_array(), "{image}/{action} numbered afterimage frame");
        }
        let sound = json("Sound.wz/Weapon.img.json");
        let path = sound[sfx]["Attack"]["$sound"].as_str().unwrap();
        assert!(std::fs::metadata(out.join(path)).unwrap().len() > 0);
    }
    let body = json("Character.wz/00002000.img.json");
    assert_eq!(body["swingO1"]["0"]["delay"], 300);
    assert_eq!(body["swingO1"]["1"]["delay"], 150);
    let hit = json("Character.wz/Afterimage/hit.img.json");
    for family in ["sword1","sword2","mace1","mace2"] { assert!(hit[family]["0"]["$canvas"].is_array()); }
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

#[test]
fn real_import_of_potion_icons_and_restore_specs() {
    let Some(root) = wz_root() else { return };
    let source: serde_json::Value = serde_json::from_str(include_str!("../../../game/data/asset_manifest.json")).unwrap();
    let items: Vec<u32> = (2000000..=2000006).collect();
    for id in &items {
        assert!(source["items"].as_array().unwrap().contains(&serde_json::json!(id)), "manifest omits {id}");
    }
    let tmp = std::env::temp_dir().join(format!("wzimport-real-potions-{}", std::process::id()));
    std::fs::create_dir_all(&tmp).unwrap();
    let manifest = tmp.join("manifest.json");
    std::fs::write(&manifest, serde_json::to_vec(&serde_json::json!({"format": 1, "items": items})).unwrap()).unwrap();
    let out = tmp.join("cache");
    let result = run_import(&ImportOptions { wz: root, manifest, out: out.clone(), force: true }).unwrap();
    assert!(result.errors.is_empty(), "{:?}", result.errors);
    let img: serde_json::Value = serde_json::from_str(&std::fs::read_to_string(out.join("Item.wz/Consume/0200.img.json")).unwrap()).unwrap();
    for (id, field, amount) in [(2000000, "hp", 50), (2000001, "hp", 150), (2000002, "hp", 300),
        (2000003, "mp", 100), (2000006, "mp", 300)] {
        assert_eq!(img[format!("{id:08}")]["spec"][field], amount, "canonical restore {id}");
    }
    for id in items {
        for icon in ["icon", "iconRaw"] {
            let region = img[format!("{id:08}")]["info"][icon]["$canvas"].as_array().unwrap();
            assert!(region[3].as_u64().unwrap() > 0 && region[4].as_u64().unwrap() > 0);
            let page = img["$pages"][region[0].as_u64().unwrap() as usize].as_str().unwrap();
            assert!(out.join(page).is_file(), "{id}/{icon} atlas");
        }
    }
    std::fs::remove_dir_all(tmp).unwrap();
}

#[test]
fn real_import_of_recovery_values_effect_and_use_sound() {
    let Some(root) = wz_root() else { return };
    let source: serde_json::Value = serde_json::from_str(include_str!("../../../game/data/asset_manifest.json")).unwrap();
    let entry = source["imgs"].as_array().unwrap().iter().find(|v| v["img"] == "Sound.wz/Skill.img").unwrap();
    assert!(entry["paths"].as_array().unwrap().contains(&serde_json::json!("0001001")));
    let tmp = std::env::temp_dir().join(format!("wzimport-real-recovery-{}", std::process::id()));
    std::fs::create_dir_all(&tmp).unwrap();
    let manifest = tmp.join("manifest.json");
    std::fs::write(&manifest, serde_json::to_vec(&serde_json::json!({"format": 1, "imgs": [
        {"img": "Skill.wz/000.img", "paths": ["skill/0001001"]},
        {"img": "Sound.wz/Skill.img", "paths": ["0001001"]}
    ]})).unwrap()).unwrap();
    let out = tmp.join("cache");
    let result = run_import(&ImportOptions { wz: root, manifest, out: out.clone(), force: true }).unwrap();
    assert!(result.errors.is_empty(), "{:?}", result.errors);
    assert!(result.unresolved_uols.is_empty(), "{:?}", result.unresolved_uols);
    let read_json = |p: &str| -> serde_json::Value {
        serde_json::from_str(&std::fs::read_to_string(out.join(p)).unwrap()).unwrap()
    };
    let skill = read_json("Skill.wz/000.img.json");
    let recovery = &skill["skill"]["0001001"];
    for (level, cost, heal) in [("1", 5, 4), ("2", 10, 8), ("3", 15, 12)] {
        let row = &recovery["level"][level];
        assert_eq!(row["mpCon"], cost);
        assert_eq!(row["x"], heal);
        assert_eq!(row["time"], 30);
        assert_eq!(row["cooltime"], 120);
    }
    assert!(recovery["icon"]["$canvas"].is_array());
    assert_eq!(recovery["effect"].as_object().unwrap().len(), 13);
    let sound = read_json("Sound.wz/Skill.img.json");
    let audio = sound["0001001"]["Use"]["$sound"].as_str().unwrap();
    assert!(std::fs::metadata(out.join(audio)).unwrap().len() > 0, "same-image UOL resolves to original Heal audio");
    std::fs::remove_dir_all(tmp).unwrap();
}

#[test]
fn real_import_of_mano_skill_tables_and_summon_effect() {
    let Some(root) = wz_root() else { return };
    let manifest: serde_json::Value = serde_json::from_str(include_str!("../../../game/data/asset_manifest.json")).unwrap();
    assert!(manifest["imgs"].as_array().unwrap().iter().any(|v| v["img"] == "Effect.wz/Summon.img" && v["paths"].as_array().unwrap().contains(&serde_json::json!("1"))));
    let tmp = std::env::temp_dir().join(format!("wzimport-real-mano-{}", std::process::id()));
    std::fs::create_dir_all(&tmp).unwrap();
    let input = tmp.join("manifest.json");
    std::fs::write(&input, serde_json::to_vec(&serde_json::json!({"format":1,"imgs":[{"img":"Skill.wz/MobSkill.img"},{"img":"Effect.wz/Summon.img","paths":["1"]}],"mobs":[2220000]})).unwrap()).unwrap();
    let out = tmp.join("cache");
    let result = run_import(&ImportOptions { wz: root, manifest: input, out: out.clone(), force: true }).unwrap();
    assert!(result.errors.is_empty(), "{:?}", result.errors);
    let read = |p: &str| -> serde_json::Value { serde_json::from_str(&std::fs::read_to_string(out.join(p)).unwrap()).unwrap() };
    let table = read("Skill.wz/MobSkill.img.json");
    let slow = &table["126"]["level"]["7"];
    assert_eq!(slow["interval"],15); assert_eq!(slow["time"],15); assert_eq!(slow["x"],80);
    assert_eq!(slow["lt"]["$v"],serde_json::json!([-300,-120]));
    assert_eq!(slow["rb"]["$v"],serde_json::json!([300,120]));
    assert_eq!(slow["affected"]["repeat"],1);
    let summon = &table["200"]["level"]["78"];
    assert_eq!(summon["interval"],10); assert_eq!(summon["hp"],90); assert_eq!(summon["limit"],30); assert_eq!(summon["summonEffect"],1);
    for (index,id) in [100100,100100,100101,100101,130101,130101].into_iter().enumerate() { assert_eq!(summon[index.to_string()],id); }
    for id in ["112","113"] {
        let buff = &table[id]["level"]["1"];
        assert_eq!(buff["interval"],10); assert_eq!(buff["time"],30); assert_eq!(buff["x"],85);
        assert_eq!(buff["lt"]["$v"],serde_json::json!([-300,-200])); assert_eq!(buff["rb"]["$v"],serde_json::json!([300,200]));
    }
    let effect = read("Effect.wz/Summon.img.json");
    assert_eq!(effect["1"].as_object().unwrap().len(),4);
    let region = effect["1"]["0"]["$canvas"].as_array().unwrap();
    assert_eq!(region[3..],[48,55]);
    assert!(out.join(effect["$pages"][region[0].as_u64().unwrap() as usize].as_str().unwrap()).is_file());
    let boss = read("Mob.wz/2220000.img.json");
    assert_eq!(boss["info"]["skill"]["0"]["skill"],126);
    assert_eq!(boss["skill1"]["0"]["delay"],150);
    std::fs::remove_dir_all(tmp).unwrap();
}

#[test]
fn real_import_of_stumpy_projectile_heal_and_sounds() {
    let Some(root) = wz_root() else { return };
    let source: serde_json::Value = serde_json::from_str(include_str!("../../../game/data/asset_manifest.json")).unwrap();
    assert!(source["mobs"].as_array().unwrap().contains(&serde_json::json!(3220000)), "manifest omits Stumpy");
    let tmp = std::env::temp_dir().join(format!("wzimport-real-stumpy-{}", std::process::id()));
    std::fs::create_dir_all(&tmp).unwrap();
    let manifest = tmp.join("manifest.json");
    std::fs::write(&manifest, serde_json::to_vec(&serde_json::json!({"format": 1, "mobs": [3220000],
        "imgs": [{"img": "Skill.wz/MobSkill.img", "paths": ["114/level/15"]}]})).unwrap()).unwrap();
    let out = tmp.join("cache");
    let result = run_import(&ImportOptions { wz: root, manifest, out: out.clone(), force: true }).unwrap();
    assert!(result.errors.is_empty(), "{:?}", result.errors);
    let read = |p: &str| -> serde_json::Value {
        serde_json::from_str(&std::fs::read_to_string(out.join(p)).unwrap()).unwrap()
    };
    let boss = read("Mob.wz/3220000.img.json");
    assert_eq!(boss["info"]["maxHP"], 7000);
    let attack = &boss["attack2"]["info"];
    assert_eq!(attack["type"], 2);
    assert_eq!(attack["bulletSpeed"], 140);
    assert_eq!(attack["attackAfter"], 1320);
    assert_eq!(attack["range"]["r"], 200);
    assert_eq!(attack["ball"]["0"]["delay"], 90);
    assert!(attack["ball"]["0"]["$canvas"].is_array());
    let skills = read("Skill.wz/MobSkill.img.json");
    let heal = &skills["114"]["level"]["15"];
    assert_eq!(heal["x"], 700);
    assert_eq!(heal["y"], 200);
    assert_eq!(heal["hp"], 80);
    assert_eq!(heal["interval"], 30);
    assert!(heal["mob0"]["1"]["$canvas"].is_array());
    let sounds = read("Sound.wz/Mob.img.json");
    for action in ["Attack1", "Attack2", "Skill1", "Damage", "Die"] {
        let path = sounds["3220000"][action]["$sound"].as_str().unwrap();
        assert!(std::fs::metadata(out.join(path)).unwrap().len() > 0, "{action} sound");
    }
    std::fs::remove_dir_all(tmp).unwrap();
}

#[test]
fn real_import_of_king_slime_dyle_kits_bars_and_sounds() {
    let Some(root) = wz_root() else { return };
    let source: serde_json::Value = serde_json::from_str(include_str!("../../../game/data/asset_manifest.json")).unwrap();
    for id in [9300003, 6220000] {
        assert!(source["mobs"].as_array().unwrap().contains(&serde_json::json!(id)));
    }
    assert!(source["imgs"].as_array().unwrap().iter().any(|v| v["img"] == "Effect.wz/Summon.img" && v["paths"].as_array().unwrap().contains(&serde_json::json!("3"))));
    let tmp = std::env::temp_dir().join(format!("wzimport-real-tree-bosses-{}", std::process::id()));
    std::fs::create_dir_all(&tmp).unwrap();
    let manifest = tmp.join("manifest.json");
    std::fs::write(&manifest, serde_json::to_vec(&serde_json::json!({"format":1,"mobs":[9300003,6220000],
        "imgs":[{"img":"Skill.wz/MobSkill.img"},{"img":"Effect.wz/Summon.img","paths":["3"]},
        {"img":"UI.wz/UIWindow.img","paths":["MobGage"]}]})).unwrap()).unwrap();
    let out = tmp.join("cache");
    let result = run_import(&ImportOptions { wz: root, manifest, out: out.clone(), force: true }).unwrap();
    assert!(result.errors.is_empty(), "{:?}", result.errors);
    assert!(result.unresolved_uols.is_empty(), "{:?}", result.unresolved_uols);
    let read = |p: &str| -> serde_json::Value { serde_json::from_str(&std::fs::read_to_string(out.join(p)).unwrap()).unwrap() };
    let king = read("Mob.wz/9300003.img.json");
    assert_eq!(king["info"]["maxHP"],8000); assert!(king["info"].get("boss").is_none());
    assert_eq!(king["attack1"]["info"]["attackAfter"],900); assert_eq!(king["attack1"]["info"]["jumpAttack"],1);
    assert_eq!(king["attack1"]["info"]["PADamage"],165);
    assert_eq!(king["info"]["revive"].as_object().unwrap().len(),11);
    assert!(king["info"]["revive"].as_object().unwrap().values().all(|v| *v == 210100));
    let dyle = read("Mob.wz/6220000.img.json");
    assert_eq!(dyle["info"]["maxHP"],31000); assert_eq!(dyle["info"]["boss"],1);
    let skills = read("Skill.wz/MobSkill.img.json");
    let summon = &skills["200"]["level"]["2"];
    assert_eq!(summon["interval"],50); assert_eq!(summon["hp"],50); assert_eq!(summon["limit"],15);
    assert_eq!(summon["summonEffect"],3);
    for i in 0..3 { assert_eq!(summon[i.to_string()],210100); }
    let heal = &skills["114"]["level"]["17"];
    assert_eq!(heal["x"],5000); assert_eq!(heal["y"],500); assert_eq!(heal["hp"],90); assert_eq!(heal["interval"],20);
    let immunity = &skills["140"]["level"]["8"];
    assert_eq!(immunity["interval"],30); assert_eq!(immunity["time"],5); assert_eq!(immunity["hp"],80);
    assert_eq!(immunity["mob"]["repeat"],1); assert_eq!(immunity["mob"]["pos"],2);
    assert_eq!(immunity["mob"]["0"]["origin"]["$v"],serde_json::json!([17,44]));
    assert!(immunity["mob"]["0"]["$canvas"].is_array());
    let summon_art = read("Effect.wz/Summon.img.json");
    assert!(summon_art["3"]["0"]["$canvas"].is_array());
    let ui = read("UI.wz/UIWindow.img.json");
    for id in ["9300003","6220000"] { assert!(ui["MobGage"]["Mob"][id]["$canvas"].is_array()); }
    let sounds = read("Sound.wz/Mob.img.json");
    for (id, actions) in [("9300003",vec!["Attack1","Skill1","Damage","Die"]), ("6220000",vec!["Skill1","Damage","Die"])] {
        for action in actions {
            let path = sounds[id][action]["$sound"].as_str().unwrap();
            assert!(std::fs::metadata(out.join(path)).unwrap().len() > 0,"{id}/{action}");
        }
    }
    std::fs::remove_dir_all(tmp).unwrap();
}
