//! Minimal streaming JSON output that keeps keys in the order they are written (WZ order).

use std::fmt::Write;

/// Append `s` as a JSON string literal.
pub fn string(out: &mut String, s: &str) {
    out.push('"');
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            '\u{08}' => out.push_str("\\b"),
            '\u{0C}' => out.push_str("\\f"),
            c if (c as u32) < 0x20 => {
                let _ = write!(out, "\\u{:04x}", c as u32);
            }
            c => out.push(c),
        }
    }
    out.push('"');
}

/// Append an f64 as a JSON number (shortest round-trip form); NaN/infinity become `null`.
pub fn f64(out: &mut String, v: f64) {
    if v.is_finite() {
        let _ = write!(out, "{v}");
    } else {
        out.push_str("null");
    }
}

/// Append an f32 as a JSON number using the shortest decimal that round-trips as f32 (0.35, not 0.3499999940395355).
pub fn f32(out: &mut String, v: f32) {
    if v.is_finite() {
        let _ = write!(out, "{v}");
    } else {
        out.push_str("null");
    }
}

/// Append an integer.
pub fn int(out: &mut String, v: i64) {
    let _ = write!(out, "{v}");
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn escapes_and_numbers() {
        let mut s = String::new();
        string(&mut s, "a\"b\\c\nd\u{1}é");
        assert_eq!(s, "\"a\\\"b\\\\c\\nd\\u0001é\"");
        let v: serde_json::Value = serde_json::from_str(&s).unwrap();
        assert_eq!(v, "a\"b\\c\nd\u{1}é");
        let mut n = String::new();
        f64(&mut n, 125.0);
        n.push(',');
        f32(&mut n, 0.35);
        n.push(',');
        f64(&mut n, f64::NAN);
        n.push(',');
        f64(&mut n, -0.05);
        assert_eq!(n, "125,0.35,null,-0.05");
    }
}
