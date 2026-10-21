//! The importer must stay offline: besides the dependency scan (`no_network_deps`), no source file of the importer may
//! use the standard library's networking.

use std::path::{Path, PathBuf};

const FORBIDDEN: &[&str] = &[
    "std::net", "TcpStream", "TcpListener", "UdpSocket", "ToSocketAddrs", "SocketAddr",
    "std::process::Command", "process::Command", "Command::new", "Command as", "process::{",
];

fn forbidden_tokens(src: &str) -> Vec<&'static str> {
    // Compact whitespace to catch qualified paths split over multiple lines.
    let compact: String = src.chars().filter(|c| !c.is_whitespace()).collect();
    FORBIDDEN.iter().copied().filter(|token| {
        compact.contains(&token.chars().filter(|c| !c.is_whitespace()).collect::<String>())
    }).collect()
}

#[test]
fn subprocess_scan_rejects_synthetic_calls_without_running_them() {
    for src in [
        "std::process::Command::new(\"curl\")", "use std::process::Command as Runner;",
        "use std::process::{Command};", "use std::process::*; Command::new(\"curl\");",
        "std :: process :: Command :: new(\"curl\")",
    ] {
        assert!(!forbidden_tokens(src).is_empty(), "missed {src}");
    }
    assert!(forbidden_tokens("std::fs::read(path)").is_empty());
}

fn rust_files(dir: &Path, out: &mut Vec<PathBuf>) {
    for entry in std::fs::read_dir(dir).expect("readable source dir") {
        let path = entry.expect("dir entry").path();
        if path.is_dir() {
            rust_files(&path, out);
        } else if path.extension().is_some_and(|e| e == "rs") {
            out.push(path);
        }
    }
}

#[test]
fn no_network_in_sources() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let mut files = Vec::new();
    rust_files(&root.join("src"), &mut files);
    rust_files(&root.join("tests"), &mut files);
    let build = root.join("build.rs");
    if build.exists() {
        files.push(build);
    }
    assert!(files.iter().any(|p| p.ends_with("main.rs")), "did not find the importer's sources");
    let this = Path::new(file!()).file_name().unwrap().to_owned();
    let mut bad = Vec::new();
    for path in &files {
        if path.file_name() == Some(this.as_os_str()) {
            continue;
        }
        let src = std::fs::read_to_string(path).expect("readable source");
        for token in forbidden_tokens(&src) {
            bad.push(format!("{}: {token}", path.display()));
        }
    }
    assert!(bad.is_empty(), "networking in the importer's sources: {bad:?}");
}
