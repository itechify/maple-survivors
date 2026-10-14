//! The importer must stay offline: no networking crate may appear anywhere in the dependency graph.

const FORBIDDEN: &[&str] =
    &["reqwest", "hyper", "ureq", "curl", "tokio", "async-std", "native-tls", "rustls", "openssl", "isahc", "surf"];

#[test]
fn no_network_deps() {
    let lock_path = concat!(env!("CARGO_MANIFEST_DIR"), "/Cargo.lock");
    let lock = std::fs::read_to_string(lock_path).expect("Cargo.lock must exist (commit it)");
    let names: Vec<&str> = lock
        .lines()
        .filter_map(|l| l.strip_prefix("name = \""))
        .filter_map(|l| l.strip_suffix('"'))
        .collect();
    assert!(names.contains(&"wzimport"), "Cargo.lock does not look like this crate's lock file");
    let bad: Vec<&&str> = names
        .iter()
        .filter(|n| FORBIDDEN.iter().any(|f| **n == *f || n.starts_with(&format!("{f}-")) || n.starts_with(&format!("{f}_"))))
        .collect();
    assert!(bad.is_empty(), "network-capable crates in Cargo.lock: {bad:?}");
}
