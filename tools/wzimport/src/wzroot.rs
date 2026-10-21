//! A folder of `.wz` archives addressed by full WZ paths (`Mob.wz/0100100.img/move/0`).

use crate::archive::WzArchive;
use crate::error::{Result, WzError};
use crate::property::Img;
use crate::source::NamedSources;
use std::collections::{BTreeSet, HashMap};
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};

/// A full WZ path split into its parts.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct WzPath {
    /// `Mob.wz`
    pub archive: String,
    /// Path of the img inside the archive (`Map/Map1/104040000.img`), or of a directory when `img` is false.
    pub inner: String,
    /// True when `inner` names an img (its last component ends in `.img`).
    pub is_img: bool,
    /// Path below the img root (`move/0`), "" for the img itself.
    pub sub: String,
}

impl WzPath {
    /// Split `File.wz/dir/x.img/a/b`. The first component ending in `.img` ends the img part.
    pub fn parse(full: &str) -> Option<WzPath> {
        let parts: Vec<&str> = full.split(['/', '\\']).filter(|p| !p.is_empty()).collect();
        let archive = parts.first()?.to_string();
        if !archive.to_ascii_lowercase().ends_with(".wz") {
            return None;
        }
        let rest = &parts[1..];
        match rest.iter().position(|p| p.ends_with(".img")) {
            Some(i) => Some(WzPath {
                archive,
                inner: rest[..=i].join("/"),
                is_img: true,
                sub: rest[i + 1..].join("/"),
            }),
            None => Some(WzPath {
                archive,
                inner: rest.join("/"),
                is_img: false,
                sub: String::new(),
            }),
        }
    }

    /// `Mob.wz/0100100.img`
    pub fn img_path(&self) -> String {
        if self.inner.is_empty() {
            self.archive.clone()
        } else {
            format!("{}/{}", self.archive, self.inner)
        }
    }
}

/// Lazily opened archives of one WZ folder, shareable across threads.
pub struct WzRoot {
    pub dir: PathBuf,
    archives: Mutex<HashMap<String, Arc<WzArchive>>>,
    sources: Option<NamedSources>,
    version: Option<u32>,
    missing: Mutex<BTreeSet<String>>,
    failures: Mutex<BTreeSet<String>>,
}

impl WzRoot {
    /// Stable archive/offset ordering for img reads whose order is otherwise free.
    pub(crate) fn img_order(&self, path: &str) -> (String, u32, String) {
        let Some(p) = WzPath::parse(path) else {
            return (path.into(), u32::MAX, path.into());
        };
        let offset = self
            .archive(&p.archive)
            .ok()
            .and_then(|a| a.entry(&p.inner).map(|e| e.offset))
            .unwrap_or(u32::MAX);
        (p.archive, offset, p.inner)
    }

    /// Keep forward-only readers out of concurrent random-seek jobs.
    #[cfg(all(feature = "parallel", not(target_arch = "wasm32")))]
    pub(crate) fn prefers_sequential(&self) -> bool {
        self.sources
            .as_ref()
            .is_some_and(|s| s.values().any(|r| r.prefers_sequential()))
    }
    /// A root over the folder holding `Map.wz`, `Mob.wz`, ...
    pub fn new(dir: impl AsRef<Path>) -> Self {
        WzRoot {
            dir: dir.as_ref().to_path_buf(),
            archives: Mutex::new(HashMap::new()),
            sources: None,
            version: None,
            missing: Mutex::new(BTreeSet::new()),
            failures: Mutex::new(BTreeSet::new()),
        }
    }

    /// The game's folder import boundary; diagnostic roots retain version autodetection.
    pub(crate) fn v83_folder(dir: impl AsRef<Path>) -> Self {
        Self { version: Some(83), ..Self::new(dir) }
    }

    /// Lazily open named positional readers, accepting any valid GMS v83 archive.
    pub fn from_sources(sources: NamedSources) -> Self {
        Self {
            sources: Some(sources),
            version: Some(83),
            ..Self::new("")
        }
    }

    /// Fail with all missing archive names before exporting an incomplete cache.
    pub fn require_archives(&self, manifest: &crate::manifest::Manifest) -> Result<()> {
        let mut names = BTreeSet::new();
        for path in manifest
            .imgs
            .iter()
            .map(|s| s.img.as_str())
            .chain(manifest.mapimgs.iter().map(String::as_str))
        {
            if let Some(p) = WzPath::parse(path) {
                names.insert(p.archive);
            }
        }
        if !manifest.maps.is_empty() || !manifest.mapimgs.is_empty() {
            names.insert("Map.wz".into());
        }
        if !manifest.mobs.is_empty() {
            names.extend(["Mob.wz".into(), "Sound.wz".into()]);
        }
        if !manifest.character.is_empty() {
            names.insert("Character.wz".into());
        }
        if !manifest.items.is_empty() {
            names.insert("Item.wz".into());
        }
        for name in names {
            if !self.has_archive(&name) {
                self.missing.lock().unwrap().insert(name);
            }
        }
        self.check_missing()
    }

    fn has_archive(&self, name: &str) -> bool {
        self.sources
            .as_ref()
            .map_or_else(|| self.archive_path(name).is_file(), |s| s.contains_key(name))
    }

    /// Include archives discovered during map/mob dependency expansion.
    pub fn check_missing(&self) -> Result<()> {
        let missing = self.missing.lock().unwrap();
        if !missing.is_empty() {
            return Err(WzError::Other(format!(
                "{} not found in this source",
                missing.iter().cloned().collect::<Vec<_>>().join(", ")
            )));
        }
        let failures = self.failures.lock().unwrap();
        if failures.is_empty() {
            return Ok(());
        }
        Err(WzError::Other(failures.iter().cloned().collect::<Vec<_>>().join("\n")))
    }

    /// Source stamp; injected readers have no modification time.
    pub fn source_stamp(&self, name: &str) -> Option<crate::cache::SourceStamp> {
        match &self.sources {
            Some(s) => s.get(name).map(|r| crate::cache::SourceStamp {
                size: r.len(),
                mtime: 0,
            }),
            None => crate::cache::stamp(&self.archive_path(name)),
        }
    }

    /// Path of an archive file in the folder.
    pub fn archive_path(&self, name: &str) -> PathBuf {
        self.dir.join(name)
    }

    /// The archive called `name` (opened on first use).
    pub fn archive(&self, name: &str) -> Result<Arc<WzArchive>> {
        if let Some(a) = self.archives.lock().unwrap().get(name) {
            return Ok(a.clone());
        }
        let path = self.archive_path(name);
        if !self.has_archive(name) {
            self.missing.lock().unwrap().insert(name.to_string());
            return Err(WzError::NotFound(format!("{} (no such file)", path.display())));
        }
        let opened = match &self.sources {
            Some(s) => WzArchive::from_reader(name, s[name].clone(), self.version),
            None => WzArchive::open_with_version(&path, self.version),
        };
        let a = Arc::new(opened.inspect_err(|e| {
            self.failures.lock().unwrap().insert(format!("{name}: {e}"));
        })?);
        let mut map = self.archives.lock().unwrap();
        Ok(map.entry(name.to_string()).or_insert(a).clone())
    }

    /// True when the img at the WZ path exists (archive opened if needed).
    pub fn img_exists(&self, img_path: &str) -> bool {
        let Some(p) = WzPath::parse(img_path) else {
            return false;
        };
        if !p.is_img {
            return false;
        }
        self.archive(&p.archive)
            .map(|a| a.entry(&p.inner).is_some_and(|e| e.is_img()))
            .unwrap_or(false)
    }

    /// Parse the img at a WZ path (`Mob.wz/0100100.img`; any sub-path is ignored).
    pub fn load_img(&self, path: &str) -> Result<Img> {
        let p = WzPath::parse(path)
            .filter(|p| p.is_img)
            .ok_or_else(|| WzError::NotFound(path.to_string()))?;
        self.archive(&p.archive)?.load_img(&p.inner)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn split_paths() {
        let p = WzPath::parse("Map.wz/Map/Map1/104040000.img/back/0").unwrap();
        assert_eq!(p.archive, "Map.wz");
        assert_eq!(p.inner, "Map/Map1/104040000.img");
        assert!(p.is_img);
        assert_eq!(p.sub, "back/0");
        assert_eq!(p.img_path(), "Map.wz/Map/Map1/104040000.img");
        let d = WzPath::parse("Map.wz/Back").unwrap();
        assert!(!d.is_img);
        assert_eq!(d.inner, "Back");
        assert_eq!(WzPath::parse("Mob.wz").unwrap().img_path(), "Mob.wz");
        assert!(WzPath::parse("nope/0.img").is_none());
    }
}
