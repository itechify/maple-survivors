//! UOL resolution with deep-copy semantics.
//!
//! A UOL's path is relative to the UOL's parent; `..` walks up, and walking above the img root continues in the
//! img's directory (an external target, loaded through a callback). A resolved UOL node keeps its name and
//! receives a deep copy of the target's value and children, so a canvas copy keeps the target's data
//! reference (and therefore its atlas region) and its child properties (`origin`, `z`, `map`, ...).
//!
//! Resolution runs to a fixed point: a UOL is copied only once its target sub-tree holds no pending UOL,
//! so chains resolve in dependency order. A target that is the UOL itself or one of its ancestors is a
//! cycle. Anything left unresolved keeps its `Value::Uol` (exported as `{"$uol": path}`) and is reported.

use crate::property::{Node, Value};
use std::collections::BTreeSet;

/// Loads a node outside the img by full WZ path (`Mob.wz/0100101.img/move/0`), already UOL-resolved.
pub type ExternalLoader<'a> = &'a mut dyn FnMut(&str) -> Option<Node>;

/// What happened to an img's UOLs.
#[derive(Debug, Default, Clone)]
pub struct UolReport {
    pub resolved: usize,
    /// Of `resolved`, how many targets were outside the img.
    pub external: usize,
    pub unresolved: Vec<Unresolved>,
}

/// A UOL that could not be resolved.
#[derive(Debug, Clone, PartialEq)]
pub struct Unresolved {
    /// Path of the UOL node inside the img.
    pub path: String,
    /// The UOL's target path as stored.
    pub target: String,
    pub reason: String,
}

enum Step {
    Done(Node, bool),
    NotReady,
    Fail(String),
}

/// Resolve every UOL below `root` (an img root whose WZ path is `img_path`).
pub fn resolve_all(root: &mut Node, img_path: &str, mut ext: Option<ExternalLoader>) -> UolReport {
    let mut pending = BTreeSet::new();
    collect(root, &mut Vec::new(), &mut pending);
    let mut report = UolReport::default();
    loop {
        let mut progress = false;
        for p in pending.clone() {
            match try_resolve(root, &p, &pending, img_path, &mut ext) {
                Step::Done(target, external) => {
                    let n = node_at_mut(root, &p);
                    n.value = target.value;
                    n.children = target.children;
                    pending.remove(&p);
                    report.resolved += 1;
                    if external {
                        report.external += 1;
                    }
                    progress = true;
                }
                Step::NotReady => {}
                Step::Fail(reason) => {
                    report.unresolved.push(unresolved(root, &p, reason));
                    pending.remove(&p);
                    progress = true;
                }
            }
        }
        if !progress {
            break;
        }
    }
    for p in &pending {
        report.unresolved.push(unresolved(root, p, "cycle between UOLs".into()));
    }
    report.unresolved.sort_by(|a, b| a.path.cmp(&b.path));
    report
}

fn unresolved(root: &Node, p: &[u32], reason: String) -> Unresolved {
    let target = match &node_at(root, p).value {
        Value::Uol(t) => t.clone(),
        _ => String::new(),
    };
    Unresolved { path: path_string(root, p), target, reason }
}

fn collect(n: &Node, stack: &mut Vec<u32>, out: &mut BTreeSet<Vec<u32>>) {
    for (i, c) in n.children.iter().enumerate() {
        stack.push(i as u32);
        if matches!(c.value, Value::Uol(_)) {
            out.insert(stack.clone());
        }
        collect(c, stack, out);
        stack.pop();
    }
}

fn node_at<'a>(root: &'a Node, p: &[u32]) -> &'a Node {
    p.iter().fold(root, |n, i| &n.children[*i as usize])
}

fn node_at_mut<'a>(root: &'a mut Node, p: &[u32]) -> &'a mut Node {
    p.iter().fold(root, |n, i| &mut n.children[*i as usize])
}

fn path_string(root: &Node, p: &[u32]) -> String {
    let mut n = root;
    let mut parts = Vec::with_capacity(p.len());
    for i in p {
        n = &n.children[*i as usize];
        parts.push(n.name.as_str());
    }
    parts.join("/")
}

fn has_pending_in(pending: &BTreeSet<Vec<u32>>, prefix: &[u32]) -> bool {
    pending.range(prefix.to_vec()..).next().is_some_and(|q| q.starts_with(prefix))
}

fn try_resolve(
    root: &Node,
    p: &[u32],
    pending: &BTreeSet<Vec<u32>>,
    img_path: &str,
    ext: &mut Option<ExternalLoader>,
) -> Step {
    let Value::Uol(target) = &node_at(root, p).value else { return Step::Fail("not a UOL".into()) };
    let comps: Vec<&str> = target.split(['/', '\\']).filter(|c| !c.is_empty() && *c != ".").collect();
    let mut cur: Vec<u32> = p[..p.len() - 1].to_vec();
    for (i, comp) in comps.iter().enumerate() {
        if *comp == ".." {
            if cur.is_empty() {
                return external(img_path, &comps[i..], target, ext);
            }
            cur.pop();
            continue;
        }
        let node = node_at(root, &cur);
        if matches!(node.value, Value::Uol(_)) {
            return if pending.contains(&cur) { Step::NotReady } else { Step::Fail("path goes through an unresolved UOL".into()) };
        }
        match node.children.iter().position(|c| c.name == *comp) {
            Some(idx) => cur.push(idx as u32),
            None => return Step::Fail(format!("target {target:?} not found")),
        }
    }
    if p.starts_with(&cur) {
        return Step::Fail("cycle: the target contains the UOL itself".into());
    }
    if has_pending_in(pending, &cur) {
        return Step::NotReady;
    }
    let t = node_at(root, &cur);
    Step::Done(Node { name: String::new(), value: t.value.clone(), children: t.children.clone() }, false)
}

/// `ups_and_rest` starts with the `..` that leaves the img root.
fn external(img_path: &str, ups_and_rest: &[&str], target: &str, ext: &mut Option<ExternalLoader>) -> Step {
    let Some(loader) = ext.as_mut() else {
        return Step::Fail(format!("target {target:?} leaves the img"));
    };
    // The img's directory: "Character.wz/00012000.img" -> ["Character.wz"].
    let mut dir: Vec<&str> = img_path.split('/').collect();
    dir.pop();
    let mut rest = ups_and_rest;
    // The first `..` moves from the img root to its directory.
    rest = &rest[1..];
    while let Some(&"..") = rest.first() {
        if dir.len() <= 1 {
            return Step::Fail(format!("target {target:?} leaves the archive"));
        }
        dir.pop();
        rest = &rest[1..];
    }
    if rest.contains(&"..") {
        return Step::Fail(format!("target {target:?} is not supported (.. after a name outside the img)"));
    }
    let full = dir.iter().chain(rest.iter()).copied().collect::<Vec<_>>().join("/");
    match loader(&full) {
        Some(n) => Step::Done(n, true),
        None => Step::Fail(format!("external target {full:?} not found")),
    }
}
