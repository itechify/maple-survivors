//! `wzimport` command line: import, dump, ls.

use anyhow::{bail, Context};
use clap::{Parser, Subcommand};
use std::path::PathBuf;
use wzimport::dump;
use wzimport::wzroot::{WzPath, WzRoot};

#[derive(Parser)]
#[command(name = "wzimport", version, about = "Offline MapleStory v83 WZ importer for Maple Survivors")]
struct Cli {
    #[command(subcommand)]
    cmd: Cmd,
}

#[derive(Subcommand)]
enum Cmd {
    /// Build or update the asset cache from a manifest.
    Import {
        /// Folder holding the .wz files, or a ZIP of them (default: $MAPLE_WZ_ROOT).
        #[arg(long, env = "MAPLE_WZ_ROOT")]
        wz: PathBuf,
        /// Manifest JSON (game/data/asset_manifest.json).
        #[arg(long)]
        manifest: PathBuf,
        /// Cache root to write.
        #[arg(long)]
        out: PathBuf,
        /// Rewrite every img even if it is up to date.
        #[arg(long)]
        force: bool,
    },
    /// Print a tree: an archive directory, an img or a node (e.g. Mob.wz/0100100.img/move 2).
    Dump {
        /// Folder holding the .wz files (default: $MAPLE_WZ_ROOT).
        #[arg(long, env = "MAPLE_WZ_ROOT")]
        wz: PathBuf,
        /// WZ path: File.wz[/dir][/x.img[/path/in/img]]
        path: String,
        /// Levels to print below the node (default: all).
        depth: Option<usize>,
        /// For a directory path: dump every img below it ("## <path>" + tree) instead of the directory listing.
        #[arg(long)]
        imgs: bool,
    },
    /// Decode one canvas (UOLs followed) to a PNG, or to raw RGBA8 bytes when OUT ends in .rgba.
    Canvas {
        #[arg(long, env = "MAPLE_WZ_ROOT")]
        wz: PathBuf,
        /// WZ path of the canvas, e.g. Mob.wz/0100100.img/move/0
        path: String,
        /// Output file (.png or .rgba)
        out: PathBuf,
    },
    /// List a directory of an archive (e.g. Map.wz/Back).
    Ls {
        #[arg(long, env = "MAPLE_WZ_ROOT")]
        wz: PathBuf,
        /// File.wz[/dir]
        path: String,
    },
}

fn main() -> anyhow::Result<()> {
    let cli = Cli::parse();
    match cli.cmd {
        Cmd::Import { wz, manifest, out, force } => {
            let opts = wzimport::import::ImportOptions { wz, manifest, out: out.clone(), force };
            let r = wzimport::import::run_import(&opts)?;
            let s = &r.index.stats;
            println!(
                "wzimport {}: {} imgs ({} written, {} up to date) -> {}",
                wzimport::IMPORTER_VERSION,
                s.imgs,
                r.written.len(),
                r.skipped.len(),
                out.display()
            );
            println!(
                "canvases {}, pages {}, sounds {}, {:.1} MB, {:.2} s; UOLs resolved {} ({} external), unresolved {}",
                s.canvases,
                s.pages,
                s.sounds,
                s.bytes as f64 / 1e6,
                s.seconds,
                r.uols_resolved,
                r.uols_external,
                r.unresolved_uols.len()
            );
            println!("warnings: {}", r.warnings.len());
            for w in &r.warnings {
                println!("  warning: {w}");
            }
            println!("errors: {}", r.errors.len());
            for e in &r.errors {
                println!("  error: {e}");
            }
            if !r.errors.is_empty() {
                std::process::exit(1);
            }
        }
        Cmd::Dump { wz, path, depth, imgs } => {
            let root = WzRoot::new(&wz);
            let p = WzPath::parse(&path).context("path must start with File.wz")?;
            let a = root.archive(&p.archive)?;
            let depth = depth.unwrap_or(usize::MAX);
            if p.is_img {
                let img = a.load_img(&p.inner)?;
                let node = img.root.at(&p.sub).with_context(|| format!("{path}: not found"))?;
                print!("{}", dump::dump_node(node, depth));
            } else if imgs {
                use std::io::Write;
                let prefix = p.inner.trim_matches('/').to_string();
                let out = std::io::stdout();
                let mut out = std::io::BufWriter::new(out.lock());
                for ip in a.img_paths().into_iter().filter(|ip| prefix.is_empty() || ip.starts_with(&format!("{prefix}/"))) {
                    let img = a.load_img(&ip)?;
                    write!(out, "## {ip}
{}", dump::dump_node(&img.root, depth))?;
                }
            } else {
                let d = a.dir(&p.inner).with_context(|| format!("{path}: no such directory"))?;
                let name = if p.inner.is_empty() { p.archive.clone() } else { p.inner.clone() };
                print!("{}", dump::dump_dir(&name, d, depth));
            }
        }
        Cmd::Canvas { wz, path, out } => {
            let root = WzRoot::new(&wz);
            let p = WzPath::parse(&path).filter(|p| p.is_img).context("path must name a node inside an img")?;
            let mut img = root.load_img(&p.img_path())?;
            wzimport::uol::resolve_all(&mut img.root, &img.path, None);
            let node = img.root.at(&p.sub).with_context(|| format!("{path}: not found"))?;
            let wzimport::property::Value::Canvas(c) = &node.value else { bail!("{path} is not a canvas") };
            let rgba = wzimport::canvas::decode(&img.bytes, c)?;
            if out.extension().is_some_and(|e| e == "rgba") {
                std::fs::write(&out, &rgba)?;
            } else {
                wzimport::atlas::write_png(&out, c.width, c.height, &rgba)?;
            }
            println!("wrote {} {}x{} format {}", out.display(), c.width, c.height, c.format());
        }
        Cmd::Ls { wz, path } => {
            let root = WzRoot::new(&wz);
            let p = WzPath::parse(&path).context("path must start with File.wz")?;
            let a = root.archive(&p.archive)?;
            if p.is_img {
                bail!("{path} is an img; use dump");
            }
            let d = a.dir(&p.inner).with_context(|| format!("{path}: no such directory"))?;
            print!("{}", dump::ls_dir(d));
        }
    }
    Ok(())
}
