//! The import manifest (`game/data/asset_manifest.json`) and its expansion into img jobs
//! (docs/ASSET_PIPELINE.md section 4).
//!
//! Expansion reads map and mob imgs to find their dependencies. Requests for the same img are merged:
//! a whole-img request wins; otherwise the union of sub-paths is exported, and a path that has another
//! requested path as a prefix is absorbed by it. Missing imgs named directly by the manifest are errors;
//! missing derived dependencies (a back, a mob sound, a link target) are warnings.
//!
//! `mapimgs` names map-structured imgs outside `Map.wz/Map` (the login scene `UI.wz/MapLogin.img`): they
//! are exported whole and their backs, tiles, objs, BGM, map mark and life are expanded exactly like a map's.

use crate::property::Node;
use crate::wzroot::WzRoot;
use serde::Deserialize;
use std::collections::{BTreeMap, BTreeSet};

/// The manifest file.
#[derive(Debug, Default, Deserialize)]
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
#[derive(Debug, Clone, Deserialize)]
pub struct ImgSpec {
    pub img: String,
    #[serde(default)]
    pub paths: Option<Vec<String>>,
}

impl Manifest {
    /// Parse manifest JSON.
    pub fn parse(text: &str) -> Result<Manifest, String> {
        let m: Manifest = serde_json::from_str(text).map_err(|e| format!("manifest: {e}"))?;
        if m.format != 1 {
            return Err(format!("manifest: unsupported format {}", m.format));
        }
        Ok(m)
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
