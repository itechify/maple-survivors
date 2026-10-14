//! The `import` command: manifest expansion, incremental export of every img, and the cache index.

use crate::cache::{self, CacheIndex, ImgEntry, SourceStamp, Stats, CACHE_FORMAT};
use crate::error::{Result, WzError};
use crate::export::{export_img, write_file, ExportOutcome};
use crate::manifest::{expand, Manifest};
use crate::wzroot::{WzPath, WzRoot};
use crate::IMPORTER_VERSION;
use rayon::prelude::*;
use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use std::time::{Instant, SystemTime};

/// Inputs of an import run.
#[derive(Debug, Clone)]
pub struct ImportOptions {
    pub wz: PathBuf,
    pub manifest: PathBuf,
    pub out: PathBuf,
    /// Rewrite every img even when its stamp is unchanged.
    pub force: bool,
}

/// What an import run did.
#[derive(Debug)]
pub struct ImportReport {
    pub index: CacheIndex,
    /// Imgs exported by this run.
    pub written: Vec<String>,
    /// Imgs skipped because they were up to date.
    pub skipped: Vec<String>,
    pub warnings: Vec<String>,
    pub errors: Vec<String>,
    /// `img: uol path -> target (reason)` for every UOL left unresolved.
    pub unresolved_uols: Vec<String>,
    /// UOLs resolved by this run (in written imgs), and how many of those pointed outside their img.
    pub uols_resolved: usize,
    pub uols_external: usize,
}

/// Run an import. Errors in single imgs are collected in the report; only setup failures return Err.
pub fn run_import(opts: &ImportOptions) -> Result<ImportReport> {
    let t0 = Instant::now();
    let text = std::fs::read_to_string(&opts.manifest).map_err(|e| WzError::io(&opts.manifest, e))?;
    let manifest = Manifest::parse(&text).map_err(WzError::Other)?;
    if !opts.wz.is_dir() {
        return Err(WzError::Other(format!("{}: not a folder", opts.wz.display())));
    }
    std::fs::create_dir_all(&opts.out).map_err(|e| WzError::io(&opts.out, e))?;
    let wz = WzRoot::new(&opts.wz);
    let plan = expand(&manifest, &wz);
    let mut warnings = plan.warnings.clone();
    let mut errors = plan.errors.clone();

    let prev = if opts.force { None } else { cache::load(&opts.out) };
    let prev = prev.filter(|p| p.format == CACHE_FORMAT && p.importer == IMPORTER_VERSION);

    let mut sources: BTreeMap<String, SourceStamp> = BTreeMap::new();
    for img in plan.imgs.keys() {
        if let Some(p) = WzPath::parse(img) {
            if !sources.contains_key(&p.archive) {
                if let Some(s) = cache::stamp(&wz.archive_path(&p.archive)) {
                    sources.insert(p.archive.clone(), s);
                }
            }
        }
    }

    let jobs: Vec<(&String, &crate::manifest::ImgRequest)> = plan.imgs.iter().collect();
    let results: Vec<(String, JobResult)> = jobs
        .par_iter()
        .map(|(img, req)| {
            let archive = WzPath::parse(img).map(|p| p.archive).unwrap_or_default();
            let paths = req.output_paths();
            if let Some(entry) = prev.as_ref().and_then(|p| up_to_date(p, img, &archive, &paths, &sources, &opts.out)) {
                return (img.to_string(), JobResult::Skipped(entry));
            }
            match export_img(&wz, img, req, &opts.out) {
                Ok(o) => (img.to_string(), JobResult::Written(Box::new(o))),
                Err(e) => (img.to_string(), JobResult::Failed(format!("{img}: {e}"))),
            }
        })
        .collect();

    let mut imgs = BTreeMap::new();
    let (mut written, mut skipped, mut unresolved) = (Vec::new(), Vec::new(), Vec::new());
    let (mut uols_resolved, mut uols_external) = (0, 0);
    for (img, r) in results {
        match r {
            JobResult::Skipped(entry) => {
                skipped.push(img.clone());
                imgs.insert(img, entry);
            }
            JobResult::Written(o) => {
                let o: ExportOutcome = *o;
                warnings.extend(o.warnings);
                uols_resolved += o.uol.resolved;
                uols_external += o.uol.external;
                for u in &o.uol.unresolved {
                    unresolved.push(format!("{img}: {} -> {:?} ({})", u.path, u.target, u.reason));
                }
                // An img with errors is written but not recorded, so the next run retries it.
                if o.errors.is_empty() {
                    imgs.insert(
                        img.clone(),
                        ImgEntry {
                            json: o.json,
                            pages: o.pages,
                            paths: o.paths,
                            canvases: o.canvases,
                            sounds: o.sounds,
                            bytes: o.bytes,
                        },
                    );
                }
                errors.extend(o.errors);
                written.push(img);
            }
            JobResult::Failed(e) => errors.push(e),
        }
    }

    let mut stats = Stats::default();
    for e in imgs.values() {
        stats.imgs += 1;
        stats.canvases += e.canvases as u64;
        stats.pages += e.pages as u64;
        stats.sounds += e.sounds as u64;
        stats.bytes += e.bytes;
    }
    stats.seconds = (t0.elapsed().as_secs_f64() * 100.0).round() / 100.0;
    let index = CacheIndex {
        format: CACHE_FORMAT,
        importer: IMPORTER_VERSION.to_string(),
        wz_root: opts.wz.to_string_lossy().replace('\\', "/"),
        created: cache::iso8601(SystemTime::now()),
        sources,
        imgs,
        stats,
    };
    let text = serde_json::to_string_pretty(&index).map_err(|e| WzError::Other(e.to_string()))?;
    write_file(&opts.out, "cache.json", text.as_bytes())?;
    Ok(ImportReport {
        index,
        written,
        skipped,
        warnings,
        errors,
        unresolved_uols: unresolved,
        uols_resolved,
        uols_external,
    })
}

enum JobResult {
    Skipped(ImgEntry),
    Written(Box<ExportOutcome>),
    Failed(String),
}

/// The previous entry when the img can be skipped: same importer version (checked by the caller), same
/// source stamp, same exported paths, and its files still exist.
fn up_to_date(
    prev: &CacheIndex,
    img: &str,
    archive: &str,
    paths: &Option<Vec<String>>,
    sources: &BTreeMap<String, SourceStamp>,
    out: &Path,
) -> Option<ImgEntry> {
    let entry = prev.imgs.get(img)?;
    let same_source = prev.sources.contains_key(archive) && prev.sources.get(archive) == sources.get(archive);
    if !same_source || &entry.paths != paths || !out.join(&entry.json).is_file() {
        return None;
    }
    if (0..entry.pages).any(|i| !out.join(format!("{img}.{i}.png")).is_file()) {
        return None;
    }
    Some(entry.clone())
}
