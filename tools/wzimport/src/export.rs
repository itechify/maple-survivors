//! Export of one img to the cache: JSON tree, atlas pages and sound files (docs/ASSET_PIPELINE.md section 5).

use crate::atlas::{self, Region, GAP, PAGE_MAX};
use crate::canvas;
use crate::error::{Result, WzError};
use crate::json;
use crate::manifest::ImgRequest;
use crate::property::{CanvasRef, Img, Node, Value};
use crate::sink::{self, FileSink, Sink};
use crate::sound::{wav_bytes, SoundFormat};
use crate::uol::{resolve_all, UolReport};
use crate::wzroot::{WzPath, WzRoot};
#[cfg(all(feature = "parallel", not(target_arch = "wasm32")))]
use rayon::prelude::*;
use std::collections::{HashMap, HashSet};
use std::path::Path;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;

/// An img blob that canvas/sound nodes of the exported tree point into (`src` index).
pub struct SrcImg {
    pub path: String,
    pub bytes: Arc<Vec<u8>>,
}

/// Result of exporting one img.
#[derive(Debug, Default)]
pub struct ExportOutcome {
    /// Cache-relative JSON path.
    pub json: String,
    pub paths: Option<Vec<String>>,
    pub pages: u32,
    pub canvases: u32,
    pub sounds: u32,
    pub bytes: u64,
    pub warnings: Vec<String>,
    pub errors: Vec<String>,
    pub uol: UolReport,
}

/// Parse, resolve and write one img. `request` says which sub-trees to write.
pub fn export_img(wz: &WzRoot, img_path: &str, request: &ImgRequest, out_dir: &Path) -> Result<ExportOutcome> {
    export_img_to(wz, img_path, request, &FileSink::new(out_dir))
}

/// Export one img through a host sink (no filesystem or archive-sized output buffer).
pub fn export_img_to(wz: &WzRoot, img_path: &str, request: &ImgRequest, sink: &dyn Sink) -> Result<ExportOutcome> {
    let mut img = wz.load_img(img_path)?;
    let mut out = ExportOutcome {
        json: format!("{img_path}.json"),
        paths: request.output_paths(),
        ..Default::default()
    };
    let mut srcs = vec![SrcImg {
        path: img.path.clone(),
        bytes: img.bytes.clone(),
    }];
    out.uol = resolve_with_external(wz, &mut img, &mut srcs);

    for (p, explicit) in &request.paths {
        if img.root.at(p).is_none() {
            let msg = format!("{img_path}: requested path {p:?} not found");
            if *explicit {
                out.errors.push(msg);
            } else {
                out.warnings.push(msg);
            }
        }
    }
    // Only UOLs inside the written sub-trees matter (the rest of the img is parsed but not exported).
    if let Some(paths) = &out.paths {
        out.uol.unresolved.retain(|u| {
            paths
                .iter()
                .any(|p| u.path == *p || u.path.starts_with(&format!("{p}/")))
        });
    }
    for u in &out.uol.unresolved {
        out.warnings.push(format!(
            "{img_path}: unresolved UOL {} -> {:?} ({})",
            u.path, u.target, u.reason
        ));
    }

    let tree = match &out.paths {
        None => img.root,
        Some(paths) => select(&img.root, paths),
    };

    // Canvases: unique by (source blob, data offset); decode in parallel, pack, write pages.
    let mut uniq: Vec<(CanvasRef, String)> = Vec::new();
    let mut index: HashMap<(u32, u32), usize> = HashMap::new();
    let mut sounds: Vec<SoundOut> = Vec::new();
    let mut sound_index: HashMap<(u32, u32), usize> = HashMap::new();
    collect(&tree, "", &mut |node, path| match &node.value {
        Value::Canvas(c) => {
            index.entry((c.src, c.data_off)).or_insert_with(|| {
                uniq.push(((**c).clone(), path.to_string()));
                uniq.len() - 1
            });
        }
        Value::Sound(s) => {
            sound_index.entry((s.src, s.data_off)).or_insert_with(|| {
                let file = s
                    .format
                    .extension()
                    .map(|ext| format!("{}/{}.{ext}", srcs[s.src as usize].path, s.origin));
                sounds.push(SoundOut {
                    sref: (**s).clone(),
                    file,
                    node_path: path.to_string(),
                });
                sounds.len() - 1
            });
        }
        _ => {}
    });

    // Recheck the selected, UOL-expanded set: external canvases bypass this img's parser budget.
    let mut decoded_bytes = 0;
    for (c, _) in &uniq {
        canvas::add_decode_bytes(&mut decoded_bytes, canvas::rgba_size(c.width, c.height)?)?;
    }
    #[cfg(all(feature = "parallel", not(target_arch = "wasm32")))]
    let iter = uniq.par_iter();
    #[cfg(not(all(feature = "parallel", not(target_arch = "wasm32"))))]
    let iter = uniq.iter();
    let decoded: Vec<Result<Vec<u8>>> = iter
        .map(|(c, _)| canvas::decode(&srcs[c.src as usize].bytes, c))
        .collect();
    let mut sizes = Vec::with_capacity(uniq.len());
    for ((c, path), d) in uniq.iter().zip(&decoded) {
        match d {
            Ok(_) => sizes.push((c.width, c.height)),
            Err(e) => {
                out.errors.push(format!("{img_path}: canvas {path}: {e}"));
                sizes.push((0, 0));
            }
        }
    }
    let layout = atlas::pack(&sizes, PAGE_MAX, GAP);
    let mut page_bytes = 0;
    for &(w, h) in &layout.pages {
        canvas::add_decode_bytes(&mut page_bytes, canvas::rgba_size(w, h)?)?;
    }
    let images: Vec<&[u8]> = decoded.iter().map(|d| d.as_deref().unwrap_or(&[])).collect();
    let page_pixels = atlas::compose(&layout, &images);
    drop(decoded);
    let page_files: Vec<String> = (0..layout.pages.len()).map(|i| format!("{img_path}.{i}.png")).collect();
    #[cfg(all(feature = "parallel", not(target_arch = "wasm32")))]
    let iter = page_pixels.par_iter().zip(layout.pages.par_iter());
    #[cfg(not(all(feature = "parallel", not(target_arch = "wasm32"))))]
    let iter = page_pixels.iter().zip(layout.pages.iter());
    let pngs: Vec<Result<Vec<u8>>> = iter.map(|(px, &(w, h))| atlas::encode_png(w, h, px)).collect();
    drop(page_pixels);
    for (file, png) in page_files.iter().zip(pngs) {
        let png = png?;
        out.bytes += png.len() as u64;
        sink::write(sink, file, &png)?;
    }
    sink.remove_stale_pages(img_path, page_files.len());
    out.pages = page_files.len() as u32;
    out.canvases = uniq.len() as u32;

    // Sounds: one file per unique source sound.
    for s in &sounds {
        let Some(file) = &s.file else {
            if let SoundFormat::Malformed(why) = &s.sref.format {
                out.warnings
                    .push(format!("{img_path}: sound {} skipped: {why}", s.node_path));
            }
            continue;
        };
        let src = &srcs[s.sref.src as usize].bytes;
        let data = &src[s.sref.data_off as usize..(s.sref.data_off + s.sref.data_len) as usize];
        let bytes = match &s.sref.format {
            SoundFormat::Pcm(wf) => wav_bytes(wf, data),
            _ => data.to_vec(),
        };
        out.bytes += bytes.len() as u64;
        sink::write(sink, file, &bytes)?;
        out.sounds += 1;
    }

    // JSON tree.
    let regions: HashMap<(u32, u32), Region> = index.iter().map(|(k, &i)| (*k, layout.regions[i])).collect();
    let sound_files: HashMap<(u32, u32), Option<String>> =
        sound_index.iter().map(|(k, &i)| (*k, sounds[i].file.clone())).collect();
    let ctx = JsonCtx {
        regions: &regions,
        sounds: &sound_files,
    };
    let mut text = String::with_capacity(img.bytes.len().min(1 << 24));
    text.push('{');
    let mut first = true;
    if !uniq.is_empty() {
        text.push_str("\"$pages\":[");
        for (i, f) in page_files.iter().enumerate() {
            if i > 0 {
                text.push(',');
            }
            json::string(&mut text, f);
        }
        text.push(']');
        first = false;
    }
    let mut dups = Vec::new();
    write_members(&mut text, &tree.children, first, &ctx, "", &mut dups);
    text.push('}');
    for d in dups {
        out.warnings
            .push(format!("{img_path}: duplicate key {d:?} (first kept)"));
    }
    out.bytes += text.len() as u64;
    sink::write(sink, &out.json, text.as_bytes())?;
    Ok(out)
}

struct SoundOut {
    sref: crate::property::SoundRef,
    file: Option<String>,
    node_path: String,
}

/// Resolve UOLs; targets outside the img are loaded, resolved and appended to `srcs`.
fn resolve_with_external(wz: &WzRoot, img: &mut Img, srcs: &mut Vec<SrcImg>) -> UolReport {
    let mut cache: HashMap<String, Img> = HashMap::new();
    let mut loader = |full: &str| -> Option<Node> {
        let p = WzPath::parse(full).filter(|p| p.is_img)?;
        let ip = p.img_path();
        if !cache.contains_key(&ip) {
            let mut e = wz.load_img(&ip).ok()?;
            resolve_all(&mut e.root, &ip, None);
            cache.insert(ip.clone(), e);
        }
        let e = &cache[&ip];
        let mut node = e.root.at(&p.sub)?.clone();
        let k = match srcs.iter().position(|s| s.path == ip) {
            Some(k) => k,
            None => {
                srcs.push(SrcImg {
                    path: ip.clone(),
                    bytes: e.bytes.clone(),
                });
                srcs.len() - 1
            }
        };
        reindex(&mut node, k as u32);
        Some(node)
    };
    let path = img.path.clone();
    resolve_all(&mut img.root, &path, Some(&mut loader))
}

fn reindex(n: &mut Node, src: u32) {
    match &mut n.value {
        Value::Canvas(c) => c.src = src,
        Value::Sound(s) => s.src = src,
        _ => {}
    }
    for c in &mut n.children {
        reindex(c, src);
    }
}

/// The sub-trees named by `paths` (relative to `n`), at their normal place.
pub fn select(n: &Node, paths: &[String]) -> Node {
    let mut out = Node {
        name: n.name.clone(),
        value: n.value.clone(),
        children: Vec::new(),
    };
    for c in &n.children {
        if paths.contains(&c.name) {
            out.children.push(c.clone());
            continue;
        }
        let prefix = format!("{}/", c.name);
        let sub: Vec<String> = paths
            .iter()
            .filter_map(|p| p.strip_prefix(&prefix).map(String::from))
            .collect();
        if !sub.is_empty() {
            out.children.push(select(c, &sub));
        }
    }
    out
}

fn collect(n: &Node, path: &str, f: &mut dyn FnMut(&Node, &str)) {
    for c in &n.children {
        let p = if path.is_empty() {
            c.name.clone()
        } else {
            format!("{path}/{}", c.name)
        };
        f(c, &p);
        collect(c, &p, f);
    }
}

struct JsonCtx<'a> {
    regions: &'a HashMap<(u32, u32), Region>,
    sounds: &'a HashMap<(u32, u32), Option<String>>,
}

fn write_members(
    out: &mut String,
    children: &[Node],
    mut first: bool,
    ctx: &JsonCtx,
    path: &str,
    dups: &mut Vec<String>,
) {
    let mut seen: HashSet<&str> = HashSet::with_capacity(children.len());
    for c in children {
        let p = if path.is_empty() {
            c.name.clone()
        } else {
            format!("{path}/{}", c.name)
        };
        if !seen.insert(c.name.as_str()) {
            dups.push(p);
            continue;
        }
        if !first {
            out.push(',');
        }
        first = false;
        json::string(out, &c.name);
        out.push(':');
        write_value(out, c, ctx, &p, dups);
    }
}

fn write_value(out: &mut String, n: &Node, ctx: &JsonCtx, path: &str, dups: &mut Vec<String>) {
    match &n.value {
        Value::Null => out.push_str("null"),
        Value::Short(v) => json::int(out, *v as i64),
        Value::Int(v) => json::int(out, *v as i64),
        Value::Long(v) => json::int(out, *v),
        Value::Float(v) => json::f32(out, *v),
        Value::Double(v) => json::f64(out, *v),
        Value::String(s) => json::string(out, s),
        Value::Sub | Value::Img => {
            out.push('{');
            write_members(out, &n.children, true, ctx, path, dups);
            out.push('}');
        }
        Value::Canvas(c) => {
            let r = ctx.regions.get(&(c.src, c.data_off)).copied().unwrap_or_default();
            out.push_str("{\"$canvas\":[");
            for (i, v) in [r.page, r.x, r.y, r.w, r.h].iter().enumerate() {
                if i > 0 {
                    out.push(',');
                }
                json::int(out, *v as i64);
            }
            out.push(']');
            write_members(out, &n.children, false, ctx, path, dups);
            out.push('}');
        }
        Value::Vector(x, y) => {
            out.push_str("{\"$v\":[");
            json::int(out, *x as i64);
            out.push(',');
            json::int(out, *y as i64);
            out.push_str("]}");
        }
        Value::Convex => {
            out.push_str("{\"$convex\":[");
            for (i, c) in n.children.iter().enumerate() {
                if i > 0 {
                    out.push(',');
                }
                match c.value {
                    Value::Vector(x, y) => {
                        out.push('[');
                        json::int(out, x as i64);
                        out.push(',');
                        json::int(out, y as i64);
                        out.push(']');
                    }
                    _ => out.push_str("null"),
                }
            }
            out.push_str("]}");
        }
        Value::Sound(s) => match ctx.sounds.get(&(s.src, s.data_off)).cloned().flatten() {
            Some(file) => {
                out.push_str("{\"$sound\":");
                json::string(out, &file);
                out.push_str(",\"$ms\":");
                json::int(out, s.duration_ms as i64);
                out.push('}');
            }
            None => out.push_str("null"),
        },
        Value::Uol(t) => {
            out.push_str("{\"$uol\":");
            json::string(out, t);
            out.push('}');
        }
    }
}

/// True when a path component cannot be a Windows file name.
pub fn bad_file_component(s: &str) -> bool {
    const RESERVED: [&str; 22] = [
        "CON", "PRN", "AUX", "NUL", "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9", "LPT1",
        "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9",
    ];
    let stem = s.split('.').next().unwrap_or("").to_ascii_uppercase();
    s.is_empty()
        || s.ends_with('.')
        || s.ends_with(' ')
        || s.chars().any(|c| (c as u32) < 0x20 || "<>:\"|?*\\".contains(c))
        || RESERVED.contains(&stem.as_str())
}

/// Write `bytes` to `out_dir/rel` (creating directories) through a temporary file and a rename.
pub fn write_file(out_dir: &Path, rel: &str, bytes: &[u8]) -> Result<()> {
    if let Some(bad) = rel.split('/').find(|c| bad_file_component(c)) {
        return Err(WzError::Other(format!(
            "{rel}: {bad:?} is not a valid file name on Windows"
        )));
    }
    let path = out_dir.join(rel);
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent).map_err(|e| WzError::io(parent, e))?;
    }
    static SEQ: AtomicU64 = AtomicU64::new(0);
    let tmp = path.with_file_name(format!(
        "{}.{}-{}.tmp",
        path.file_name()
            .map(|n| n.to_string_lossy().into_owned())
            .unwrap_or_default(),
        std::process::id(),
        SEQ.fetch_add(1, Ordering::Relaxed)
    ));
    std::fs::write(&tmp, bytes).map_err(|e| WzError::io(&tmp, e))?;
    std::fs::rename(&tmp, &path).map_err(|e| WzError::io(&path, e))?;
    Ok(())
}

pub(crate) fn remove_stale_pages(out_dir: &Path, img_path: &str, from: usize) {
    for i in from.. {
        let p = out_dir.join(format!("{img_path}.{i}.png"));
        if !p.exists() || std::fs::remove_file(&p).is_err() {
            break;
        }
    }
}
