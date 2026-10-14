//! Atlas packing and PNG output.
//!
//! Canvases are packed into pages of at most `PAGE_MAX` x `PAGE_MAX` with a `GAP` px transparent gap between
//! them (shelf packing, tallest first, page width chosen near the square root of the total area). A canvas
//! larger than a page gets a page of exactly its size. Pages are trimmed to the area actually used.

use crate::error::{Result, WzError};
use std::io::BufWriter;
use std::path::Path;

/// Largest page edge.
pub const PAGE_MAX: u32 = 2048;
/// Transparent gap between canvases.
pub const GAP: u32 = 1;

/// Where a canvas landed: page index and pixel rectangle.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Default)]
pub struct Region {
    pub page: u32,
    pub x: u32,
    pub y: u32,
    pub w: u32,
    pub h: u32,
}

/// Result of packing: page sizes and one region per input size (same order).
#[derive(Clone, Debug, Default)]
pub struct Layout {
    pub pages: Vec<(u32, u32)>,
    pub regions: Vec<Region>,
}

/// Pack rectangles of the given sizes.
pub fn pack(sizes: &[(u32, u32)], max: u32, gap: u32) -> Layout {
    let mut layout = Layout { pages: Vec::new(), regions: vec![Region::default(); sizes.len()] };
    let mut normal: Vec<usize> = Vec::new();
    for (i, &(w, h)) in sizes.iter().enumerate() {
        if w == 0 || h == 0 {
            layout.regions[i] = Region { page: 0, x: 0, y: 0, w, h }; // nothing to draw
            continue;
        }
        if w > max || h > max {
            layout.regions[i] = Region { page: layout.pages.len() as u32, x: 0, y: 0, w, h };
            layout.pages.push((w, h));
        } else {
            normal.push(i);
        }
    }
    if !normal.is_empty() {
        normal.sort_by(|&a, &b| sizes[b].1.cmp(&sizes[a].1).then(sizes[b].0.cmp(&sizes[a].0)).then(a.cmp(&b)));
        let area: u64 = normal.iter().map(|&i| (sizes[i].0 + gap) as u64 * (sizes[i].1 + gap) as u64).sum();
        let widest = normal.iter().map(|&i| sizes[i].0).max().unwrap_or(1);
        let target_w = ((area as f64).sqrt().ceil() as u32).clamp(widest, max);

        let mut page = layout.pages.len() as u32;
        let (mut x, mut shelf_y, mut shelf_h, mut ext_w, mut ext_h) = (0u32, 0u32, 0u32, 0u32, 0u32);
        for &i in &normal {
            let (w, h) = sizes[i];
            if x > 0 && x + w > target_w {
                shelf_y += shelf_h + gap;
                x = 0;
                shelf_h = 0;
            }
            if shelf_y + h > max {
                layout.pages.push((ext_w, ext_h));
                page += 1;
                x = 0;
                shelf_y = 0;
                shelf_h = 0;
                ext_w = 0;
                ext_h = 0;
            }
            layout.regions[i] = Region { page, x, y: shelf_y, w, h };
            ext_w = ext_w.max(x + w);
            ext_h = ext_h.max(shelf_y + h);
            x += w + gap;
            shelf_h = shelf_h.max(h);
        }
        layout.pages.push((ext_w, ext_h));
    }
    if layout.pages.is_empty() && !sizes.is_empty() {
        layout.pages.push((1, 1)); // only empty canvases: keep page 0 valid
    }
    layout
}

/// Blit RGBA8 images into their pages.
pub fn compose(layout: &Layout, images: &[&[u8]]) -> Vec<Vec<u8>> {
    let mut pages: Vec<Vec<u8>> = layout.pages.iter().map(|&(w, h)| vec![0u8; (w * h * 4) as usize]).collect();
    for (r, img) in layout.regions.iter().zip(images) {
        if r.w == 0 || r.h == 0 {
            continue;
        }
        let pw = layout.pages[r.page as usize].0 as usize;
        let page = &mut pages[r.page as usize];
        let row = r.w as usize * 4;
        for y in 0..r.h as usize {
            let dst = ((r.y as usize + y) * pw + r.x as usize) * 4;
            page[dst..dst + row].copy_from_slice(&img[y * row..(y + 1) * row]);
        }
    }
    pages
}

/// Encode RGBA8 pixels as a PNG.
pub fn encode_png(w: u32, h: u32, rgba: &[u8]) -> Result<Vec<u8>> {
    let mut out = Vec::with_capacity(rgba.len() / 4 + 1024);
    {
        let mut enc = png::Encoder::new(&mut out, w, h);
        enc.set_color(png::ColorType::Rgba);
        enc.set_depth(png::BitDepth::Eight);
        enc.set_compression(png::Compression::Fast);
        let mut wr = enc.write_header().map_err(|e| WzError::Other(format!("png: {e}")))?;
        wr.write_image_data(rgba).map_err(|e| WzError::Other(format!("png: {e}")))?;
        wr.finish().map_err(|e| WzError::Other(format!("png: {e}")))?;
    }
    Ok(out)
}

/// Write RGBA8 pixels to a PNG file.
pub fn write_png(path: &Path, w: u32, h: u32, rgba: &[u8]) -> Result<()> {
    let bytes = encode_png(w, h, rgba)?;
    let f = std::fs::File::create(path).map_err(|e| WzError::io(path, e))?;
    let mut bw = BufWriter::new(f);
    std::io::Write::write_all(&mut bw, &bytes).map_err(|e| WzError::io(path, e))?;
    Ok(())
}
