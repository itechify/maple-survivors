//! `cache.json`: the asset cache index (docs/ASSET_PIPELINE.md section 5.1) and incremental-import stamps.

use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::path::Path;
use std::time::{SystemTime, UNIX_EPOCH};

/// Cache format number written to cache.json and checked by the runtime.
pub const CACHE_FORMAT: u32 = 1;

/// The whole index.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct CacheIndex {
    pub format: u32,
    pub importer: String,
    pub wz_root: String,
    pub created: String,
    /// Source archive stamps (`Mob.wz` -> size + mtime).
    pub sources: BTreeMap<String, SourceStamp>,
    /// Exported imgs by WZ path.
    pub imgs: BTreeMap<String, ImgEntry>,
    pub stats: Stats,
}

/// Size and modification time (Unix seconds) of a source archive.
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
pub struct SourceStamp {
    pub size: u64,
    pub mtime: u64,
}

/// One exported img. `sounds` and `bytes` are additions to the documented fields (used for stats).
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ImgEntry {
    pub json: String,
    pub pages: u32,
    pub paths: Option<Vec<String>>,
    pub canvases: u32,
    #[serde(default)]
    pub sounds: u32,
    /// Exported audio payload paths. Legacy entries with sounds must refresh once to populate this list.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub sound_files: Option<Vec<String>>,
    #[serde(default)]
    pub bytes: u64,
}

/// Totals over all exported imgs; `seconds` is the wall time of the import run that wrote the index.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Default)]
pub struct Stats {
    pub imgs: u64,
    pub canvases: u64,
    pub pages: u64,
    pub sounds: u64,
    pub bytes: u64,
    pub seconds: f64,
}

/// Stamp of a file (None when it cannot be read).
pub fn stamp(path: &Path) -> Option<SourceStamp> {
    let md = std::fs::metadata(path).ok()?;
    let mtime = md.modified().ok()?.duration_since(UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0);
    Some(SourceStamp { size: md.len(), mtime })
}

/// Load `cache.json` from a cache root; None when absent or unreadable.
pub fn load(root: &Path) -> Option<CacheIndex> {
    let text = std::fs::read_to_string(root.join("cache.json")).ok()?;
    serde_json::from_str(&text).ok()
}

/// ISO-8601 UTC timestamp (`2026-10-13T20:00:00Z`) of a SystemTime.
pub fn iso8601(t: SystemTime) -> String {
    let secs = t.duration_since(UNIX_EPOCH).map(|d| d.as_secs() as i64).unwrap_or(0);
    let (days, rem) = (secs.div_euclid(86_400), secs.rem_euclid(86_400));
    // Civil date from days since 1970-01-01 (Howard Hinnant's algorithm, public domain description).
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let y = if m <= 2 { y + 1 } else { y };
    format!("{y:04}-{m:02}-{d:02}T{:02}:{:02}:{:02}Z", rem / 3600, rem % 3600 / 60, rem % 60)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::Duration;

    #[test]
    fn iso_dates() {
        assert_eq!(iso8601(UNIX_EPOCH), "1970-01-01T00:00:00Z");
        assert_eq!(iso8601(UNIX_EPOCH + Duration::from_secs(1_266_397_980)), "2010-02-17T09:13:00Z");
        assert_eq!(iso8601(UNIX_EPOCH + Duration::from_secs(1_791_921_600)), "2026-10-13T20:00:00Z");
        assert_eq!(iso8601(UNIX_EPOCH + Duration::from_secs(951_782_400)), "2000-02-29T00:00:00Z");
    }
}
