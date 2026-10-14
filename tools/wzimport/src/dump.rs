//! Human-readable listings for the `dump` and `ls` commands.
//!
//! The line format (`name = value`, two-space indent, `Canvas WxH fmt=a+b`, `(x, y)`, `UOL -> path`, JSON-quoted
//! strings, `[Property N]`) deliberately matches the research explorer (`wz.js dump`) so the two can be diffed.

use crate::archive::{Dir, EntryKind};
use crate::property::{Node, Value};
use crate::sound::SoundFormat;
use std::fmt::Write;

/// One-line description of a node's value.
pub fn fmt_value(n: &Node) -> String {
    match &n.value {
        Value::Null => "null".into(),
        Value::Short(v) => v.to_string(),
        Value::Int(v) => v.to_string(),
        Value::Long(v) => format!("{v}L"),
        Value::Float(v) => fmt_f64(*v as f64),
        Value::Double(v) => fmt_f64(*v),
        Value::String(s) => serde_json::to_string(s).unwrap_or_default(),
        Value::Sub => format!("[Property {}]", n.children.len()),
        Value::Img => format!("[img {}]", n.children.len()),
        Value::Convex => format!("[Convex {}]", n.children.len()),
        Value::Canvas(c) => format!("Canvas {}x{} fmt={}+{}", c.width, c.height, c.fmt, c.fmt2),
        Value::Vector(x, y) => format!("({x}, {y})"),
        Value::Uol(p) => format!("UOL -> {p}"),
        Value::Sound(s) => match &s.format {
            SoundFormat::Mp3(wf) if wf.rate == 0 => {
                format!("Sound len={} dur={}ms mp3 without WAVEFORMATEX", s.data_len, s.duration_ms)
            }
            SoundFormat::Mp3(wf) | SoundFormat::Pcm(wf) => format!(
                "Sound len={} dur={}ms tag=0x{:x} {}Hz ch={} avgBps={}",
                s.data_len, s.duration_ms, wf.tag, wf.rate, wf.channels, wf.avg_bytes
            ),
            SoundFormat::Malformed(why) => format!("Sound len={} dur={}ms malformed: {why}", s.data_len, s.duration_ms),
        },
    }
}

/// Shortest round-trip decimal, like JavaScript's number formatting for ordinary magnitudes.
pub fn fmt_f64(v: f64) -> String {
    if v.is_nan() {
        "NaN".into()
    } else if v.is_infinite() {
        if v > 0.0 { "Infinity".into() } else { "-Infinity".into() }
    } else {
        format!("{v}")
    }
}

/// Recursive listing of a node, `depth` levels below it.
pub fn dump_node(n: &Node, depth: usize) -> String {
    let mut out = String::new();
    fn rec(n: &Node, depth: usize, indent: usize, out: &mut String) {
        let _ = writeln!(out, "{}{} = {}", "  ".repeat(indent), n.name, fmt_value(n));
        if depth > 0 {
            for c in &n.children {
                rec(c, depth - 1, indent + 1, out);
            }
        }
    }
    rec(n, depth, 0, &mut out);
    out
}

/// Recursive listing of a directory (`name = [dir N]`, imgs as `name = [img size=S]`).
pub fn dump_dir(name: &str, d: &Dir, depth: usize) -> String {
    let mut out = String::new();
    fn rec(name: &str, d: &Dir, depth: usize, indent: usize, out: &mut String) {
        let _ = writeln!(out, "{}{} = [dir {}]", "  ".repeat(indent), name, d.entries.len());
        if depth == 0 {
            return;
        }
        for e in &d.entries {
            match &e.kind {
                EntryKind::Dir(sub) => rec(&e.name, sub, depth - 1, indent + 1, out),
                EntryKind::Img => {
                    let _ = writeln!(out, "{}{} = [img size={}]", "  ".repeat(indent + 1), e.name, e.size);
                }
            }
        }
    }
    rec(name, d, depth, 0, &mut out);
    out
}

/// One line per directory entry: kind, name, size and offset.
pub fn ls_dir(d: &Dir) -> String {
    let mut out = String::new();
    for e in &d.entries {
        let kind = match e.kind {
            EntryKind::Dir(_) => "dir",
            EntryKind::Img => "img",
        };
        let _ = writeln!(out, "{kind:<8} {} size={} off={}", e.name, e.size, e.offset);
    }
    out
}
