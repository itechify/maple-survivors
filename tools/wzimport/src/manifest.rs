//! The import manifest (`game/data/asset_manifest.json`) and its expansion into img jobs
//! (docs/ASSET_PIPELINE.md section 4).
//!
//! Expansion reads map and mob imgs to find their dependencies. Requests for the same img are merged:
//! a whole-img request wins; otherwise the union of sub-paths is exported, and a path that has another
//! requested path as a prefix is absorbed by it. Missing imgs named directly by the manifest are errors;
//! missing derived dependencies (a back, a mob sound, a link target) are warnings.
//!
//! The manifest is one main file plus optional include fragments: every `*.json` in the sibling folder named after the
//! main file (`asset_manifest.json` -> `asset_manifest.d/`) is merged in, sorted by file name; a key listed in two
//! files is an error (`Manifest::merge`, docs/ASSET_PIPELINE.md 4.1).
//!
//! `mapimgs` names map-structured imgs outside `Map.wz/Map` (the login scene `UI.wz/MapLogin.img`): they
//! are exported whole and their backs, tiles, objs, BGM, map mark and life are expanded exactly like a map's.

use crate::property::Node;
use crate::wzroot::WzRoot;
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, BTreeSet};
use std::path::{Path, PathBuf};

/// The manifest file.
#[derive(Debug, Default, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct Manifest {
    pub format: u32,
    pub imgs: Vec<ImgSpec>,
    pub maps: Vec<u64>,
    /// Map-structured imgs by full WZ path (`UI.wz/MapLogin.img`), expanded like `maps`.
    pub mapimgs: Vec<String>,
    pub mobs: Vec<u64>,
    pub character: Vec<u64>,
    pub items: Vec<u64>,
}

/// One `imgs[]` entry.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ImgSpec {
    pub img: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub paths: Option<Vec<String>>,
}

/// Keys a manifest file may hold (`_doc` is free text). A fragment with any other key is rejected, so a typo such as
/// `mob` cannot silently drop entries.
const MANIFEST_KEYS: [&str; 8] = ["format", "_doc", "imgs", "maps", "mapimgs", "mobs", "character", "items"];

impl Manifest {
    /// Parse manifest JSON.
    pub fn parse(text: &str) -> Result<Manifest, String> {
        let m: Manifest = serde_json::from_str(text).map_err(|e| format!("manifest: {e}"))?;
        if m.format != 1 {
            return Err(format!("manifest: unsupported format {}", m.format));
        }
        Ok(m)
    }

    /// Parse an include fragment: the same shape as the main file, but `format` is optional (when present it must
    /// be 1) and unknown keys are errors.
    pub fn parse_fragment(text: &str) -> Result<Manifest, String> {
        let v: serde_json::Value = serde_json::from_str(text).map_err(|e| e.to_string())?;
        let obj = v.as_object().ok_or("not a JSON object")?;
        if let Some(k) = obj.keys().find(|k| !MANIFEST_KEYS.contains(&k.as_str())) {
            return Err(format!("unknown key {k:?} (allowed: {})", MANIFEST_KEYS.join(", ")));
        }
        if let Some(f) = obj.get("format") {
            if f.as_u64() != Some(1) {
                return Err(format!("unsupported format {f}"));
            }
        }
        let mut m: Manifest = serde_json::from_value(v).map_err(|e| e.to_string())?;
        m.format = 1;
        Ok(m)
    }

    /// Merge the main manifest with its include fragments. `main` and each fragment are `(display name, JSON text)`;
    /// fragments are merged in the order given (callers pass them sorted by file name), appended after the main file's
    /// entries. A key named by two different files is an error that names both files: an `imgs[]` entry is keyed by
    /// (img, sub-path), or by img when it exports the whole img (a whole-img entry in one file conflicts with any entry
    /// for that img in another); a `maps`/`mobs`/`character`/`items` id by its id; a `mapimgs` entry by its path.
    /// Repeats inside one file are tolerated, as before.
    pub fn merge(main: (&str, &str), fragments: &[(String, String)]) -> Result<Manifest, String> {
        let mut out = Manifest::parse(main.1).map_err(|e| format!("{}: {e}", main.0))?;
        let mut keys = KeyOwners::default();
        keys.claim(&out, main.0)?;
        for (name, text) in fragments {
            let frag = Manifest::parse_fragment(text).map_err(|e| format!("manifest fragment {name}: {e}"))?;
            keys.claim(&frag, name)?;
            out.imgs.extend(frag.imgs);
            out.maps.extend(frag.maps);
            out.mapimgs.extend(frag.mapimgs);
            out.mobs.extend(frag.mobs);
            out.character.extend(frag.character);
            out.items.extend(frag.items);
        }
        Ok(out)
    }

    /// Load a manifest file plus the `*.json` fragments in `fragment_dir(path)` (sorted by file name; the folder may be
    /// absent). Errors are readable strings naming the file.
    pub fn load(path: &Path) -> Result<Manifest, String> {
        let main = std::fs::read_to_string(path).map_err(|e| format!("{}: {e}", path.display()))?;
        let dir = fragment_dir(path);
        let mut fragments = Vec::new();
        if dir.is_dir() {
            let mut files: Vec<PathBuf> = std::fs::read_dir(&dir)
                .map_err(|e| format!("{}: {e}", dir.display()))?
                .filter_map(|e| e.ok().map(|e| e.path()))
                .filter(|p| p.is_file() && p.extension().is_some_and(|x| x == "json"))
                .collect();
            files.sort_by(|a, b| a.file_name().cmp(&b.file_name()));
            for f in files {
                let text = std::fs::read_to_string(&f).map_err(|e| format!("{}: {e}", f.display()))?;
                let name = f.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
                fragments.push((name, text));
            }
        }
        let main_name = path.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
        Manifest::merge((&main_name, &main), &fragments)
    }

    /// Every selection as one sorted line, the form of `tests/fixtures/manifest_golden.txt`: `img <img> *` (whole img),
    /// `img <img> <path>` per sub-path, `map|mapimg|mob|character|item <id or path>`. Independent of which file an
    /// entry lives in, so moving an entry between files leaves it unchanged.
    pub fn canonical_lines(&self) -> Vec<String> {
        let mut lines = Vec::new();
        for e in &self.imgs {
            match &e.paths {
                None => lines.push(format!("img {} *", e.img)),
                Some(paths) => lines.extend(paths.iter().map(|p| format!("img {} {p}", e.img))),
            }
        }
        lines.extend(self.maps.iter().map(|id| format!("map {id}")));
        lines.extend(self.mapimgs.iter().map(|p| format!("mapimg {p}")));
        lines.extend(self.mobs.iter().map(|id| format!("mob {id}")));
        lines.extend(self.character.iter().map(|id| format!("character {id}")));
        lines.extend(self.items.iter().map(|id| format!("item {id}")));
        lines.sort();
        lines
    }
}

/// The include-fragment folder of a manifest file: `<dir>/asset_manifest.json` -> `<dir>/asset_manifest.d`.
pub fn fragment_dir(manifest: &Path) -> PathBuf {
    let stem = manifest.file_stem().map(|s| s.to_string_lossy().into_owned()).unwrap_or_default();
    manifest.with_file_name(format!("{stem}.d"))
}

/// Which file first claimed each manifest key, for the duplicate check of `Manifest::merge`.
#[derive(Default)]
struct KeyOwners {
    ids: BTreeMap<String, String>,
    whole: BTreeMap<String, String>,
    paths: BTreeMap<(String, String), String>,
    partial: BTreeMap<String, String>,
}

impl KeyOwners {
    /// Check `m` (from file `file`) against the earlier files, then record its keys.
    fn claim(&mut self, m: &Manifest, file: &str) -> Result<(), String> {
        let dup = |what: String, other: &String| format!("manifest entry {what} is listed in both {other} and {file}");
        let mut ids = Vec::new();
        ids.extend(m.maps.iter().map(|id| format!("map {id}")));
        ids.extend(m.mapimgs.iter().map(|p| format!("mapimg {p}")));
        ids.extend(m.mobs.iter().map(|id| format!("mob {id}")));
        ids.extend(m.character.iter().map(|id| format!("character {id}")));
        ids.extend(m.items.iter().map(|id| format!("item {id}")));
        for k in &ids {
            if let Some(o) = self.ids.get(k) {
                return Err(dup(format!("`{k}`"), o));
            }
        }
        let (mut whole, mut paths) = (Vec::new(), Vec::new());
        for e in &m.imgs {
            match &e.paths {
                None => whole.push(e.img.clone()),
                Some(ps) => paths.extend(ps.iter().map(|p| (e.img.clone(), p.clone()))),
            }
        }
        for img in &whole {
            if let Some(o) = self.whole.get(img).or_else(|| self.partial.get(img)) {
                return Err(dup(format!("`img {img}`"), o));
            }
        }
        for (img, p) in &paths {
            if let Some(o) = self.whole.get(img) {
                return Err(dup(format!("`img {img}` (path {p:?})"), o));
            }
            if let Some(o) = self.paths.get(&(img.clone(), p.clone())) {
                return Err(dup(format!("`img {img}` path {p:?}"), o));
            }
        }
        for k in ids {
            self.ids.insert(k, file.to_string());
        }
        for img in whole {
            self.whole.insert(img, file.to_string());
        }
        for (img, p) in paths {
            self.partial.insert(img.clone(), file.to_string());
            self.paths.insert((img, p), file.to_string());
        }
        Ok(())
    }
}

/// What to export from one img.
#[derive(Debug, Clone, PartialEq, Default)]
pub struct ImgRequest {
    /// True when the whole img is exported.
    pub whole: bool,
    /// Requested sub-paths and whether the manifest named them directly (explicit) or expansion derived them.
    pub paths: BTreeMap<String, bool>,
}

impl ImgRequest {
    /// The sub-paths to write (None = whole img): sorted, with paths covered by a shorter requested path removed.
    pub fn output_paths(&self) -> Option<Vec<String>> {
        if self.whole {
            return None;
        }
        let all: Vec<&String> = self.paths.keys().collect();
        let kept = all
            .iter()
            .filter(|p| !all.iter().any(|q| q.len() < p.len() && p.starts_with(q.as_str()) && p.as_bytes()[q.len()] == b'/'))
            .map(|p| p.to_string())
            .collect();
        Some(kept)
    }
}

/// Expanded manifest: img path -> request, plus diagnostics.
#[derive(Debug, Default)]
pub struct Plan {
    pub imgs: BTreeMap<String, ImgRequest>,
    pub warnings: Vec<String>,
    pub errors: Vec<String>,
    /// Every mob id that was expanded (manifest, map life, info/link targets).
    pub mobs: BTreeSet<u32>,
}

impl Plan {
    fn add_whole(&mut self, img: &str) {
        self.imgs.entry(img.to_string()).or_default().whole = true;
    }

    fn add_path(&mut self, img: &str, path: &str, explicit: bool) {
        let path = path.trim_matches('/');
        if path.is_empty() {
            return self.add_whole(img);
        }
        let e = self.imgs.entry(img.to_string()).or_default().paths.entry(path.to_string()).or_insert(false);
        *e |= explicit;
    }
}

/// `Map.wz/Map/Map1/104040000.img`
pub fn map_img_path(id: u64) -> String {
    let s = format!("{id:09}");
    format!("Map.wz/Map/Map{}/{s}.img", &s[..1])
}

/// `Mob.wz/0100100.img`
pub fn mob_img_path(id: u32) -> String {
    format!("Mob.wz/{id:07}.img")
}

/// Character.wz img of a body, head, face, hair or equip id; None for an unknown category.
pub fn character_img_path(id: u64) -> Option<String> {
    let dir = match id / 10000 {
        0 | 1 => "",
        2 => "Face",
        3 => "Hair",
        100 => "Cap",
        101..=103 => "Accessory",
        104 => "Coat",
        105 => "Longcoat",
        106 => "Pants",
        107 => "Shoes",
        108 => "Glove",
        109 => "Shield",
        110 => "Cape",
        111 => "Ring",
        130..=170 => "Weapon",
        _ => return None,
    };
    Some(if dir.is_empty() { format!("Character.wz/{id:08}.img") } else { format!("Character.wz/{dir}/{id:08}.img") })
}

/// (img, sub-path) of an item id: `Item.wz/Etc/0400.img`, `04000019`; None for an unknown type.
pub fn item_path(id: u64) -> Option<(String, String)> {
    let kind = match id / 1_000_000 {
        2 => "Consume",
        3 => "Install",
        4 => "Etc",
        5 => "Cash",
        9 => "Special", // the meso coin sprites 09000000-09000003
        _ => return None,
    };
    Some((format!("Item.wz/{kind}/{:04}.img", id / 10000), format!("{id:08}")))
}

fn str_at(n: &Node, path: &str) -> Option<String> {
    n.at(path).and_then(|v| v.as_str()).map(|s| s.trim().to_string()).filter(|s| !s.is_empty())
}

/// Expand the manifest against the WZ files.
pub fn expand(m: &Manifest, wz: &WzRoot) -> Plan {
    let mut plan = Plan::default();
    for spec in &m.imgs {
        if !wz.img_exists(&spec.img) {
            plan.errors.push(format!("manifest img {} not found", spec.img));
            continue;
        }
        match &spec.paths {
            None => plan.add_whole(&spec.img),
            Some(paths) => {
                for p in paths {
                    plan.add_path(&spec.img, p, true);
                }
            }
        }
    }

    let mut mob_queue: Vec<(u32, String)> = m.mobs.iter().map(|id| (*id as u32, String::new())).collect();
    if !m.maps.is_empty() || !m.mapimgs.is_empty() {
        plan.add_path("Map.wz/MapHelper.img", "portal", false);
    }
    let mut map_jobs: Vec<_> = m
        .maps
        .iter()
        .map(|&id| (map_img_path(id), format!("map {id}")))
        .chain(m.mapimgs.iter().map(|p| (p.trim_matches('/').to_string(), format!("mapimg {}", p.trim_matches('/'))))).collect();
    map_jobs.sort_by_cached_key(|(path, _)| wz.img_order(path));
    for (img_path, label) in map_jobs {
        let img = match wz.load_img(&img_path) {
            Ok(img) => img,
            Err(e) => {
                plan.errors.push(format!("manifest {label}: {e}"));
                continue;
            }
        };
        plan.add_whole(&img_path);
        expand_map(&img.root, &label, wz, &mut plan, &mut mob_queue);
    }

    // A mob named by the manifest is an error when missing, even if a map's life reached it first.
    let explicit_mobs: BTreeSet<u64> = m.mobs.iter().copied().collect();
    let mut seen = BTreeSet::new();
    while !mob_queue.is_empty() {
        // Links may add new jobs; choose the next lowest available offset each time.
        let next = (0..mob_queue.len()).min_by_key(|&i| wz.img_order(&mob_img_path(mob_queue[i].0))).unwrap();
        let (id, via) = mob_queue.remove(next);
        if !seen.insert(id) {
            continue;
        }
        let img_path = mob_img_path(id);
        let img = match wz.load_img(&img_path) {
            Ok(img) => img,
            Err(e) => {
                if via.is_empty() || explicit_mobs.contains(&(id as u64)) {
                    plan.errors.push(format!("manifest mob {id}: {e}"));
                } else {
                    plan.warnings.push(format!("mob {id} ({via}): {e}"));
                }
                continue;
            }
        };
        plan.mobs.insert(id);
        plan.add_whole(&img_path);
        plan.add_path("Sound.wz/Mob.img", &format!("{id:07}"), false);
        if let Some(link) = img.root.at("info/link").and_then(|n| n.as_i64()) {
            mob_queue.push((link as u32, format!("info/link of {id:07}")));
        }
    }

    for &id in &m.character {
        match character_img_path(id) {
            Some(p) if wz.img_exists(&p) => plan.add_whole(&p),
            Some(p) => plan.errors.push(format!("manifest character {id}: {p} not found")),
            None => plan.errors.push(format!("manifest character {id}: unknown id category {}", id / 10000)),
        }
    }

    for &id in &m.items {
        match item_path(id) {
            Some((img, sub)) if wz.img_exists(&img) => plan.add_path(&img, &sub, true),
            Some((img, _)) => plan.errors.push(format!("manifest item {id}: {img} not found")),
            None => plan.errors.push(format!("manifest item {id}: unknown item type {}", id / 1_000_000)),
        }
    }
    plan
}

/// Adds the dependencies of a map-structured img root (backs, tiles, objs, BGM, map mark, life mobs); `label`
/// ("map 104040000", "mapimg UI.wz/MapLogin.img") prefixes warnings.
fn expand_map(root: &Node, label: &str, wz: &WzRoot, plan: &mut Plan, mobs: &mut Vec<(u32, String)>) {
    let add_dep = |plan: &mut Plan, img: String, sub: Option<String>, what: String| {
        if !wz.img_exists(&img) {
            plan.warnings.push(format!("{label}: {what}: {img} not found"));
            return;
        }
        match sub {
            Some(s) => plan.add_path(&img, &s, false),
            None => plan.add_whole(&img),
        }
    };
    if let Some(back) = root.child("back") {
        for b in &back.children {
            let Some(bs) = str_at(b, "bS") else { continue };
            let no = b.at("no").and_then(|n| n.as_i64()).unwrap_or(0);
            let kind = if b.at("ani").and_then(|n| n.as_i64()).unwrap_or(0) == 1 { "ani" } else { "back" };
            add_dep(plan, format!("Map.wz/Back/{bs}.img"), Some(format!("{kind}/{no}")), format!("back/{}", b.name));
        }
    }
    for layer in 0..8 {
        let Some(l) = root.child(&layer.to_string()) else { continue };
        if let Some(ts) = str_at(l, "info/tS") {
            add_dep(plan, format!("Map.wz/Tile/{ts}.img"), None, format!("layer {layer} tS"));
        }
        if let Some(objs) = l.child("obj") {
            for o in &objs.children {
                let (Some(os), Some(l0), Some(l1), Some(l2)) =
                    (str_at(o, "oS"), str_at(o, "l0"), str_at(o, "l1"), str_at(o, "l2"))
                else {
                    plan.warnings.push(format!("{label}: layer {layer} obj {} lacks oS/l0/l1/l2", o.name));
                    continue;
                };
                add_dep(plan, format!("Map.wz/Obj/{os}.img"), Some(format!("{l0}/{l1}/{l2}")), format!("layer {layer} obj {}", o.name));
            }
        }
    }
    if let Some(bgm) = str_at(root, "info/bgm") {
        match bgm.split_once('/') {
            Some((img, name)) => add_dep(plan, format!("Sound.wz/{img}.img"), Some(name.to_string()), "bgm".into()),
            None => plan.warnings.push(format!("{label}: bgm {bgm:?} is not <img>/<name>")),
        }
    }
    // "None" is how v83 says "no mark" (UI.wz/MapLogin.img and many fields); there is no mark/None canvas.
    if let Some(mark) = str_at(root, "info/mapMark").filter(|m| m != "None") {
        plan.add_path("Map.wz/MapHelper.img", &format!("mark/{mark}"), false);
    }
    if let Some(life) = root.child("life") {
        for l in &life.children {
            if str_at(l, "type").as_deref() == Some("m") {
                if let Some(mid) = l.at("id").and_then(|n| n.as_i64()) {
                    mobs.push((mid as u32, format!("life of {label}")));
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn id_paths() {
        assert_eq!(map_img_path(104040000), "Map.wz/Map/Map1/104040000.img");
        assert_eq!(map_img_path(910000000), "Map.wz/Map/Map9/910000000.img");
        assert_eq!(map_img_path(10000), "Map.wz/Map/Map0/000010000.img");
        assert_eq!(mob_img_path(100100), "Mob.wz/0100100.img");
        assert_eq!(character_img_path(2000).unwrap(), "Character.wz/00002000.img");
        assert_eq!(character_img_path(12000).unwrap(), "Character.wz/00012000.img");
        assert_eq!(character_img_path(20000).unwrap(), "Character.wz/Face/00020000.img");
        assert_eq!(character_img_path(30030).unwrap(), "Character.wz/Hair/00030030.img");
        assert_eq!(character_img_path(1040002).unwrap(), "Character.wz/Coat/01040002.img");
        assert_eq!(character_img_path(1302000).unwrap(), "Character.wz/Weapon/01302000.img");
        assert_eq!(character_img_path(1372005).unwrap(), "Character.wz/Weapon/01372005.img");
        assert_eq!(character_img_path(1012000).unwrap(), "Character.wz/Accessory/01012000.img");
        assert!(character_img_path(1802000).is_none());
        assert_eq!(item_path(4000019).unwrap(), ("Item.wz/Etc/0400.img".to_string(), "04000019".to_string()));
        assert_eq!(item_path(2000000).unwrap().0, "Item.wz/Consume/0200.img");
        assert_eq!(item_path(9000003).unwrap(), ("Item.wz/Special/0900.img".to_string(), "09000003".to_string()));
        assert!(item_path(1000000).is_none());
    }

    const MAIN: &str = r#"{"format":1,"_doc":"x","imgs":[{"img":"A.wz/a.img"},{"img":"S.wz/s.img","paths":["1","2"]}],"maps":[1],"mobs":[7],"character":[2000],"items":[4000000]}"#;

    fn frag(name: &str, text: &str) -> (String, String) {
        (name.to_string(), text.to_string())
    }

    #[test]
    fn fragments_merge_after_the_main_file() {
        let m = Manifest::merge(
            ("asset_manifest.json", MAIN),
            &[
                frag("a.json", r#"{"_doc":"line a","imgs":[{"img":"S.wz/s.img","paths":["3"]},{"img":"B.wz/b.img"}],"mobs":[8]}"#),
                frag("b.json", r#"{"format":1,"maps":[2],"mapimgs":["U.wz/m.img"],"character":[1372000],"items":[4000001]}"#),
            ],
        )
        .unwrap();
        assert_eq!(m.format, 1);
        assert_eq!(m.imgs.len(), 4);
        assert_eq!((m.maps.clone(), m.mobs.clone()), (vec![1, 2], vec![7, 8]));
        assert_eq!((m.character.clone(), m.items.clone()), (vec![2000, 1372000], vec![4000000, 4000001]));
        assert_eq!(m.mapimgs, vec!["U.wz/m.img"]);
        // A second entry for the same img with other paths is not a duplicate; the plan unions the paths.
        let lines = m.canonical_lines();
        assert!(lines.contains(&"img S.wz/s.img 3".to_string()) && lines.contains(&"img S.wz/s.img 1".to_string()));
        assert!(lines.windows(2).all(|w| w[0] <= w[1]), "sorted");
    }

    #[test]
    fn a_key_in_two_files_is_an_error_naming_both() {
        let dup = |frag_text: &str| {
            Manifest::merge(("asset_manifest.json", MAIN), &[frag("wizard.json", frag_text)]).unwrap_err()
        };
        for (text, what) in [
            (r#"{"maps":[1]}"#, "`map 1`"),
            (r#"{"mobs":[7]}"#, "`mob 7`"),
            (r#"{"character":[2000]}"#, "`character 2000`"),
            (r#"{"items":[4000000]}"#, "`item 4000000`"),
            (r#"{"imgs":[{"img":"A.wz/a.img"}]}"#, "`img A.wz/a.img`"),
            (r#"{"imgs":[{"img":"S.wz/s.img","paths":["2","9"]}]}"#, "`img S.wz/s.img` path \"2\""),
            // whole img in one file, sub-paths of it in another (and the other way round)
            (r#"{"imgs":[{"img":"A.wz/a.img","paths":["x"]}]}"#, "`img A.wz/a.img`"),
            (r#"{"imgs":[{"img":"S.wz/s.img"}]}"#, "`img S.wz/s.img`"),
        ] {
            let e = dup(text);
            assert!(e.contains(what), "{e}");
            assert!(e.contains("asset_manifest.json") && e.contains("wizard.json"), "{e}");
        }
        // Two fragments clash too, and a repeat inside one file is tolerated.
        let e = Manifest::merge(
            ("asset_manifest.json", MAIN),
            &[frag("a.json", r#"{"mobs":[9]}"#), frag("b.json", r#"{"mobs":[9]}"#)],
        )
        .unwrap_err();
        assert!(e.contains("a.json") && e.contains("b.json") && e.contains("mob 9"), "{e}");
        assert!(Manifest::merge(("m.json", MAIN), &[frag("a.json", r#"{"mobs":[9,9]}"#)]).is_ok());
    }

    /// Spec #449 C0: a region fragment (`region_<key>.json`) lists its maps, mobs and EXP items, and a mob two regions
    /// share (Panda Teddy in Ludibrium and Magatia, say) must be claimed by one of them: the second is an error naming both.
    #[test]
    fn region_fragments_hold_maps_mobs_and_items_and_do_not_overlap() {
        let a = r#"{"_doc":"region a","maps":[220011000],"mobs":[3230101,4130103],"items":[4000100]}"#;
        let b = r#"{"_doc":"region b","maps":[221040000],"mobs":[3230102],"items":[4000101]}"#;
        let m = Manifest::merge(
            ("asset_manifest.json", MAIN),
            &[frag("region_a.json", a), frag("region_b.json", b)],
        )
        .unwrap();
        assert_eq!(m.maps, vec![1, 220011000, 221040000]);
        assert_eq!(m.mobs, vec![7, 3230101, 4130103, 3230102]);
        assert_eq!(m.items, vec![4000000, 4000100, 4000101]);
        for (text, what) in [(r#"{"mobs":[3230101]}"#, "`mob 3230101`"), (r#"{"maps":[220011000]}"#, "`map 220011000`"),
                (r#"{"items":[4000100]}"#, "`item 4000100`")] {
            let e = Manifest::merge(
                ("asset_manifest.json", MAIN),
                &[frag("region_a.json", a), frag("region_c.json", text)],
            )
            .unwrap_err();
            assert!(e.contains(what) && e.contains("region_a.json") && e.contains("region_c.json"), "{e}");
        }
    }

    #[test]
    fn bad_fragments_are_rejected() {
        for (text, what) in [
            (r#"{"mob":[1]}"#, "unknown key"),
            (r#"{"format":2}"#, "unsupported format"),
            (r#"[1]"#, "not a JSON object"),
            (r#"{"mobs":"7"}"#, "invalid type"),
            ("{", "EOF"),
        ] {
            let e = Manifest::merge(("m.json", MAIN), &[frag("bad.json", text)]).unwrap_err();
            assert!(e.contains("bad.json") && e.contains(what), "{e}");
        }
    }

    #[test]
    fn load_merges_the_sibling_folder_sorted_by_name() {
        let dir = crate::testutil::TempDir::new("manifest_load");
        let main = dir.path().join("asset_manifest.json");
        std::fs::write(&main, MAIN).unwrap();
        // No fragment folder: just the main file.
        assert_eq!(Manifest::load(&main).unwrap().mobs, vec![7]);
        let d = dir.path().join("asset_manifest.d");
        std::fs::create_dir(&d).unwrap();
        std::fs::write(d.join("b.json"), r#"{"mobs":[2]}"#).unwrap();
        std::fs::write(d.join("a.json"), r#"{"mobs":[1]}"#).unwrap();
        std::fs::write(d.join("notes.txt"), "not json at all").unwrap();
        std::fs::create_dir(d.join("sub.json")).unwrap();
        assert_eq!(Manifest::load(&main).unwrap().mobs, vec![7, 1, 2]);
        // A duplicate across files fails the load, naming the files; so does an unreadable main file.
        std::fs::write(d.join("c.json"), r#"{"mobs":[7]}"#).unwrap();
        let e = Manifest::load(&main).unwrap_err();
        assert!(e.contains("asset_manifest.json") && e.contains("c.json"), "{e}");
        assert!(Manifest::load(&dir.path().join("nope.json")).is_err());
        // run_import goes through the same loader.
        let opts = crate::import::ImportOptions {
            wz: dir.path().to_path_buf(),
            manifest: main,
            out: dir.path().join("out"),
            force: false,
        };
        assert!(crate::import::run_import(&opts).unwrap_err().to_string().contains("c.json"));
    }

    /// The shipping manifest plus `asset_manifest.d/*.json` selects exactly what the single-file manifest selected before
    /// it was split (docs/ASSET_PIPELINE.md 4.1). UPDATE_MANIFEST_GOLDEN=1 rewrites the golden after an intended change.
    #[test]
    fn shipping_manifest_with_fragments_matches_the_golden() {
        let root = Path::new(env!("CARGO_MANIFEST_DIR"));
        let golden_path = root.join("tests/fixtures/manifest_golden.txt");
        let main = root.join("../../game/data/asset_manifest.json");
        let merged = Manifest::load(&main).unwrap();
        let got = merged.canonical_lines();
        let old = std::fs::read_to_string(&golden_path).unwrap();
        if std::env::var_os("UPDATE_MANIFEST_GOLDEN").is_some() {
            let mut text: String = old.lines().filter(|l| l.starts_with('#')).map(|l| format!("{l}\n")).collect();
            text.push_str(&got.join("\n"));
            text.push('\n');
            std::fs::write(&golden_path, text).unwrap();
            return;
        }
        let want: Vec<String> = old.lines().filter(|l| !l.starts_with('#') && !l.is_empty()).map(String::from).collect();
        let missing: Vec<_> = want.iter().filter(|l| !got.contains(l)).collect();
        let extra: Vec<_> = got.iter().filter(|l| !want.contains(l)).collect();
        assert!(missing.is_empty() && extra.is_empty(), "manifest drifted from the golden (UPDATE_MANIFEST_GOLDEN=1 to accept): missing {missing:?}, extra {extra:?}");
        assert_eq!(got, want);
        assert!(got.windows(2).all(|w| w[0] != w[1]), "no repeated selection");

        // Every fragment is a documented, parseable file of its own.
        let frags = fragment_dir(&main);
        let mut names: Vec<String> = std::fs::read_dir(&frags).unwrap().map(|e| e.unwrap().file_name().to_string_lossy().into_owned()).collect();
        names.sort();
        for line in ["common.json", "beginner.json", "magician.json"] {
            assert!(names.iter().any(|n| n == line), "missing fragment {line}");
        }
        for n in &names {
            let v: serde_json::Value = serde_json::from_str(&std::fs::read_to_string(frags.join(n)).unwrap()).unwrap();
            assert!(v["_doc"].as_str().is_some_and(|d| !d.is_empty()), "{n} needs a _doc");
            Manifest::parse_fragment(&v.to_string()).unwrap();
        }
    }

    #[test]
    fn requests_merge_and_absorb() {
        let mut plan = Plan::default();
        plan.add_path("A.wz/x.img", "mark/Henesys", false);
        plan.add_path("A.wz/x.img", "mark", true);
        plan.add_path("A.wz/x.img", "portal", false);
        plan.add_path("A.wz/x.img", "markers", false);
        let r = &plan.imgs["A.wz/x.img"];
        assert_eq!(r.output_paths().unwrap(), vec!["mark", "markers", "portal"]);
        assert!(r.paths["mark"]);
        plan.add_whole("A.wz/x.img");
        assert_eq!(plan.imgs["A.wz/x.img"].output_paths(), None);
    }
}
