//! The `import` command: manifest expansion, incremental export of every img, and the cache index.

use crate::cache::{self, CacheIndex, ImgEntry, SourceStamp, Stats, CACHE_FORMAT};
use crate::error::{Result, WzError};
use crate::export::{export_img_to, ExportOutcome};
use crate::manifest::{expand, Manifest};
use crate::sink::{self, FileSink, Sink};
use crate::source::{HostBound, NamedSources};
use crate::wzroot::{WzPath, WzRoot};
use crate::IMPORTER_VERSION;
#[cfg(all(feature = "parallel", not(target_arch = "wasm32")))]
use rayon::prelude::*;
use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicUsize, Ordering};
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
    // The main manifest plus the include fragments beside it (asset_manifest.d/*.json).
    let manifest = Manifest::load(&opts.manifest).map_err(WzError::Other)?;
    let wz = if opts.wz.is_dir() {
        WzRoot::v83_folder(&opts.wz)
    } else if opts.wz.is_file() {
        let file = std::fs::File::open(&opts.wz).map_err(|e| WzError::io(&opts.wz, e))?;
        WzRoot::from_sources(crate::zip::zip_sources(std::sync::Arc::new(file))?)
    } else {
        return Err(WzError::Other(format!("{}: not a folder or zip", opts.wz.display())));
    };
    let sink = FileSink::new(&opts.out);
    let prev = if opts.force || !opts.wz.is_dir() {
        None
    } else {
        cache::load(&opts.out)
    };
    let context = Context {
        prev,
        out: Some(&opts.out),
        label: opts.wz.to_string_lossy().replace('\\', "/"),
        created: cache::iso8601(SystemTime::now()),
        timer: Some(t0),
    };
    execute(&wz, &manifest, &sink, &|_: &str, _, _| Ok(()), context)
}

/// Progress at the img boundary; done/total count completed img jobs, including failures/skips.
pub trait Progress: HostBound {
    fn update(&self, file: &str, done: usize, total: usize) -> Result<()>;
}
impl<F: Fn(&str, usize, usize) -> Result<()> + HostBound> Progress for F {
    fn update(&self, file: &str, done: usize, total: usize) -> Result<()> {
        self(file, done, total)
    }
}

/// Import a named source through host boundaries. Reproducible index metadata (empty label/date, zero
/// seconds, mtime zero) needs no host clock. Imports are fresh; the host owns replacement/cleanup.
pub fn import_sources(
    sources: NamedSources,
    manifest_json: &str,
    sink: &dyn Sink,
    progress: &dyn Progress,
) -> Result<ImportReport> {
    let manifest = Manifest::parse(manifest_json).map_err(WzError::Other)?;
    execute(
        &WzRoot::from_sources(sources),
        &manifest,
        sink,
        progress,
        Context {
            prev: None,
            out: None,
            label: String::new(),
            created: String::new(),
            timer: None,
        },
    )
}

struct Context<'a> {
    prev: Option<CacheIndex>,
    out: Option<&'a Path>,
    label: String,
    created: String,
    timer: Option<Instant>,
}

fn execute(
    wz: &WzRoot,
    manifest: &Manifest,
    sink: &dyn Sink,
    progress: &dyn Progress,
    context: Context<'_>,
) -> Result<ImportReport> {
    wz.require_archives(manifest)?;
    let plan = expand(manifest, wz);
    wz.check_missing()?;
    let mut warnings = plan.warnings.clone();
    let mut errors = plan.errors.clone();
    sink.create_dir("")?;
    let prev = context
        .prev
        .filter(|p| p.format == CACHE_FORMAT && p.importer == IMPORTER_VERSION);
    let mut sources = BTreeMap::new();
    for img in plan.imgs.keys() {
        if let Some(p) = WzPath::parse(img) {
            if let Some(stamp) = wz.source_stamp(&p.archive) {
                sources.insert(p.archive, stamp);
            }
        }
    }
    let mut jobs: Vec<(&String, &crate::manifest::ImgRequest)> = plan.imgs.iter().collect();
    jobs.sort_by_cached_key(|(img, _)| wz.img_order(img));
    let done = AtomicUsize::new(0);
    let run_job = |(img, req): &(&String, &crate::manifest::ImgRequest)| {
        let (img, result) = (|| {
            let archive = WzPath::parse(img).map(|p| p.archive).unwrap_or_default();
            let paths = req.output_paths();
            if let Some(entry) = context.out.and_then(|out| {
                prev.as_ref()
                    .and_then(|p| up_to_date(p, img, &archive, &paths, &sources, out))
            }) {
                return (img.to_string(), JobResult::Skipped(entry));
            }
            match export_img_to(wz, img, req, sink) {
                Ok(o) => (img.to_string(), JobResult::Written(Box::new(o))),
                Err(e) => (img.to_string(), JobResult::Failed(format!("{img}: {e}"))),
            }
        })();
        match progress.update(&img, done.fetch_add(1, Ordering::Relaxed) + 1, jobs.len()) {
            Ok(()) => (img, result),
            Err(e) => (img, JobResult::Failed(format!("progress: {e}"))),
        }
    };
    #[cfg(all(feature = "parallel", not(target_arch = "wasm32")))]
    let mut results: Vec<(String, JobResult)> = if wz.prefers_sequential() {
        jobs.iter().map(run_job).collect()
    } else {
        jobs.par_iter().map(run_job).collect()
    };
    #[cfg(not(all(feature = "parallel", not(target_arch = "wasm32"))))]
    let mut results: Vec<(String, JobResult)> = jobs.iter().map(run_job).collect();
    // Keep report/diagnostic order stable even though the I/O schedule changed.
    results.sort_by(|a, b| a.0.cmp(&b.0));

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
                            sound_files: (!o.sound_files.is_empty()).then_some(o.sound_files),
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
    stats.seconds = context
        .timer
        .map_or(0.0, |t| (t.elapsed().as_secs_f64() * 100.0).round() / 100.0);
    let index = CacheIndex {
        format: CACHE_FORMAT,
        importer: IMPORTER_VERSION.to_string(),
        wz_root: context.label,
        created: context.created,
        sources,
        imgs,
        stats,
    };
    let text = serde_json::to_string_pretty(&index).map_err(|e| WzError::Other(e.to_string()))?;
    sink::write(sink, "cache.json", text.as_bytes())?;
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
    if entry.sounds > 0 {
        let files = entry.sound_files.as_ref()?;
        if files.len() != entry.sounds as usize || files.iter().any(|f| !out.join(f).is_file()) {
            return None;
        }
    }
    Some(entry.clone())
}
