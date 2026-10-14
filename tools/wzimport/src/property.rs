//! Img property trees: node types and the img parser.
//!
//! Canvas pixels and sound data are not decoded here: canvas/sound nodes keep offsets into the img blob
//! (`src` indexes the list of img blobs an export works with; 0 = the img itself).

use crate::error::{Result, WzError};
use crate::reader::Reader;
use crate::sound::{parse_sound, SoundFormat};
use std::collections::HashMap;
use std::sync::Arc;

/// A parsed img: its WZ path (`Mob.wz/0100100.img`), raw bytes and property tree.
#[derive(Clone)]
pub struct Img {
    pub path: String,
    pub bytes: Arc<Vec<u8>>,
    pub root: Node,
}

/// One property node. `children` holds sub-properties, canvas properties and convex vertices.
#[derive(Clone, Debug, PartialEq)]
pub struct Node {
    pub name: String,
    pub value: Value,
    pub children: Vec<Node>,
}

#[derive(Clone, Debug, PartialEq)]
pub enum Value {
    Null,
    Short(i16),
    Int(i32),
    Long(i64),
    Float(f32),
    Double(f64),
    String(String),
    /// `Property` sub-tree.
    Sub,
    /// The img root.
    Img,
    Canvas(Box<CanvasRef>),
    Vector(i32, i32),
    /// `Shape2D#Convex2D`: vertices are the children (vector nodes named "0", "1", ...).
    Convex,
    Sound(Box<SoundRef>),
    Uol(String),
}

/// Where a canvas's pixel data lives.
#[derive(Clone, Debug, PartialEq)]
pub struct CanvasRef {
    /// Index of the img blob holding the data (0 = this img).
    pub src: u32,
    pub width: u32,
    pub height: u32,
    pub fmt: i32,
    pub fmt2: u8,
    /// Offset of the pixel data (after the leading 0 byte) inside the img blob.
    pub data_off: u32,
    pub data_len: u32,
}

impl CanvasRef {
    /// Effective pixel format (`fmt + fmt2`): 1, 2, 513 or 517 in v83.
    pub fn format(&self) -> i32 {
        self.fmt + self.fmt2 as i32
    }
}

/// Where a sound's data lives and how it is encoded.
#[derive(Clone, Debug, PartialEq)]
pub struct SoundRef {
    pub src: u32,
    /// Path of the sound node inside its img (`0100100/Damage`), used for the output file name.
    pub origin: String,
    pub data_off: u32,
    pub data_len: u32,
    pub duration_ms: i32,
    pub format: SoundFormat,
}

impl Node {
    /// A node with no children.
    pub fn leaf(name: impl Into<String>, value: Value) -> Self {
        Node { name: name.into(), value, children: Vec::new() }
    }

    /// Child by name.
    pub fn child(&self, name: &str) -> Option<&Node> {
        self.children.iter().find(|c| c.name == name)
    }

    /// Descendant by `/`-separated path ("" = self). UOLs are not followed.
    pub fn at(&self, path: &str) -> Option<&Node> {
        let mut n = self;
        for part in path.split('/').filter(|p| !p.is_empty()) {
            n = n.child(part)?;
        }
        Some(n)
    }

    /// Integer value of int-like nodes (short, int, long, and strings holding an integer).
    pub fn as_i64(&self) -> Option<i64> {
        match &self.value {
            Value::Short(v) => Some(*v as i64),
            Value::Int(v) => Some(*v as i64),
            Value::Long(v) => Some(*v),
            Value::Float(v) => Some(*v as i64),
            Value::Double(v) => Some(*v as i64),
            Value::String(s) => s.trim().parse().ok(),
            _ => None,
        }
    }

    /// Number value as f64.
    pub fn as_f64(&self) -> Option<f64> {
        match &self.value {
            Value::Float(v) => Some(*v as f64),
            Value::Double(v) => Some(*v),
            _ => self.as_i64().map(|v| v as f64),
        }
    }

    /// String value (numbers are formatted).
    pub fn as_str(&self) -> Option<String> {
        match &self.value {
            Value::String(s) => Some(s.clone()),
            Value::Short(_) | Value::Int(_) | Value::Long(_) => self.as_i64().map(|v| v.to_string()),
            _ => None,
        }
    }

    /// Number of nodes in this sub-tree (including self).
    pub fn count(&self) -> usize {
        1 + self.children.iter().map(Node::count).sum::<usize>()
    }
}

/// Parse an img blob. `path` is its WZ path; `file_offset` is where the blob starts in the archive.
pub fn parse_img(path: String, bytes: Vec<u8>, file_offset: u64) -> Result<Img> {
    let name = path.rsplit('/').next().unwrap_or("").to_string();
    let root = {
        let mut p = Parser { r: Reader::new(&bytes, file_offset), strings: HashMap::new() };
        let end = bytes.len();
        let mut root = p.object(name, end)?;
        if root.value != Value::Sub {
            return Err(WzError::Other(format!("{path}: img root is not a Property")));
        }
        root.value = Value::Img;
        root
    };
    let mut img = Img { path, bytes: Arc::new(bytes), root };
    let mut stack = Vec::new();
    fill_sound_origins(&mut img.root.children, &mut stack);
    Ok(img)
}

fn fill_sound_origins(nodes: &mut [Node], stack: &mut Vec<String>) {
    for n in nodes {
        stack.push(n.name.clone());
        if let Value::Sound(s) = &mut n.value {
            s.origin = stack.join("/");
        }
        fill_sound_origins(&mut n.children, stack);
        stack.pop();
    }
}

struct Parser<'a> {
    r: Reader<'a>,
    strings: HashMap<usize, String>,
}

impl Parser<'_> {
    /// String block with a small cache for offset-form strings (property names repeat a lot).
    fn string_block(&mut self) -> Result<String> {
        let at = self.r.pos();
        let marker = self.r.u8()?;
        if marker == 0x01 || marker == 0x1B {
            let off = self.r.i32()?;
            if off < 0 || off as usize >= self.r.len() {
                return Err(WzError::format(self.r.abs_pos(), format!("string offset {off} out of range")));
            }
            if let Some(s) = self.strings.get(&(off as usize)) {
                return Ok(s.clone());
            }
            let mut sub = self.r.clone();
            sub.set_pos(off as usize);
            let s = sub.wz_string()?;
            self.strings.insert(off as usize, s.clone());
            return Ok(s);
        }
        self.r.set_pos(at);
        self.r.string_block()
    }

    fn prop_list(&mut self, out: &mut Vec<Node>, end: usize) -> Result<()> {
        let at = self.r.abs_pos();
        let count = self.r.cint()?;
        if count < 0 || count as usize > end.saturating_sub(self.r.pos()) {
            return Err(WzError::format(at, format!("bad property count {count}")));
        }
        out.reserve(count as usize);
        for _ in 0..count {
            let name = self.string_block()?;
            let tat = self.r.abs_pos();
            let t = self.r.u8()?;
            let node = match t {
                0 => Node::leaf(name, Value::Null),
                2 | 11 => Node::leaf(name, Value::Short(self.r.i16()?)),
                3 | 19 => Node::leaf(name, Value::Int(self.r.cint()?)),
                20 => Node::leaf(name, Value::Long(self.r.clong()?)),
                4 => {
                    let v = if self.r.u8()? == 0x80 { self.r.f32()? } else { 0.0 };
                    Node::leaf(name, Value::Float(v))
                }
                5 => Node::leaf(name, Value::Double(self.r.f64()?)),
                8 => {
                    let s = self.string_block()?;
                    Node::leaf(name, Value::String(s))
                }
                9 => {
                    let size = self.r.u32()? as usize;
                    let obj_end = self.r.pos() + size;
                    if obj_end > end {
                        return Err(WzError::format(tat, format!("{name}: extended size {size} out of range")));
                    }
                    let node = self.object(name, obj_end)?;
                    self.r.set_pos(obj_end);
                    node
                }
                _ => return Err(WzError::format(tat, format!("{name}: unknown property type {t}"))),
            };
            out.push(node);
        }
        Ok(())
    }

    /// Extended object (type name string block, then its body); `end` bounds its data.
    fn object(&mut self, name: String, end: usize) -> Result<Node> {
        let at = self.r.abs_pos();
        let tname = self.string_block()?;
        let mut node = Node::leaf(name, Value::Null);
        match tname.as_str() {
            "Property" => {
                self.r.skip(2)?;
                node.value = Value::Sub;
                self.prop_list(&mut node.children, end)?;
            }
            "Canvas" => {
                self.r.skip(1)?;
                if self.r.u8()? == 1 {
                    self.r.skip(2)?;
                    self.prop_list(&mut node.children, end)?;
                }
                let w = self.r.cint()?;
                let h = self.r.cint()?;
                let fmt = self.r.cint()?;
                let fmt2 = self.r.u8()?;
                self.r.skip(4)?;
                let len = self.r.i32()?;
                if w < 0 || h < 0 || len < 1 {
                    return Err(WzError::format(at, format!("{}: bad canvas header {w}x{h} len {len}", node.name)));
                }
                self.r.skip(1)?;
                let data_off = self.r.pos();
                let data_len = (len - 1) as usize;
                if data_off + data_len > end {
                    return Err(WzError::format(at, format!("{}: canvas data out of range", node.name)));
                }
                self.r.set_pos(data_off + data_len);
                node.value = Value::Canvas(Box::new(CanvasRef {
                    src: 0,
                    width: w as u32,
                    height: h as u32,
                    fmt,
                    fmt2,
                    data_off: data_off as u32,
                    data_len: data_len as u32,
                }));
            }
            "Shape2D#Vector2D" => {
                let x = self.r.cint()?;
                let y = self.r.cint()?;
                node.value = Value::Vector(x, y);
            }
            "Shape2D#Convex2D" => {
                let count = self.r.cint()?;
                if count < 0 || count as usize > end.saturating_sub(self.r.pos()) {
                    return Err(WzError::format(at, format!("{}: bad convex count {count}", node.name)));
                }
                node.value = Value::Convex;
                for i in 0..count {
                    let child = self.object(i.to_string(), end)?;
                    node.children.push(child);
                }
            }
            "Sound_DX8" => {
                let s = parse_sound(&mut self.r, end)?;
                node.value = Value::Sound(Box::new(s));
            }
            "UOL" => {
                self.r.skip(1)?;
                let target = self.string_block()?;
                node.value = Value::Uol(target);
            }
            other => return Err(WzError::format(at, format!("{}: unknown object type {other:?}", node.name))),
        }
        Ok(node)
    }
}
