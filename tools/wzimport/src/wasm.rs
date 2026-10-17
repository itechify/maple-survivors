//! Synchronous worker API. All host I/O is injected; this module only marshals callbacks and bytes.

use crate::import::{import_sources, Progress};
use crate::sink::Sink;
use crate::source::{NamedSources, ReadAt};
use crate::{Result, WzError};
use js_sys::{Function, Object, Promise, Reflect, Uint8Array};
use std::io;
use std::sync::Arc;
use wasm_bindgen::prelude::*;

fn message(value: JsValue) -> String {
    value
        .as_string()
        .or_else(|| Reflect::get(&value, &"message".into()).ok()?.as_string())
        .unwrap_or_else(|| format!("{value:?}"))
}
fn error(value: JsValue) -> WzError {
    WzError::Other(message(value))
}
fn field(value: &JsValue, key: &str) -> Result<JsValue> {
    Reflect::get(value, &key.into()).map_err(error)
}
fn function(value: &JsValue, key: &str) -> Result<Function> {
    field(value, key)?
        .dyn_into()
        .map_err(|_| WzError::Other(format!("{key} must be a synchronous function")))
}
fn synchronous(value: JsValue) -> Result<()> {
    if value.is_instance_of::<Promise>() {
        return Err(WzError::Other(
            "host callbacks must be synchronous (returned Promise)".into(),
        ));
    }
    Ok(())
}

struct HostReader {
    object: JsValue,
    read: Function,
    len: u64,
}
impl HostReader {
    fn new(object: JsValue) -> Result<Self> {
        let len = field(&object, "length")?
            .as_f64()
            .filter(|n| n.is_finite() && *n >= 0.0 && n.fract() == 0.0 && *n <= 9_007_199_254_740_991.0)
            .ok_or_else(|| WzError::Other("reader.length must be a nonnegative safe integer".into()))?
            as u64;
        let read = function(&object, "readAt")?;
        Ok(Self { object, read, len })
    }
}
impl ReadAt for HostReader {
    fn len(&self) -> u64 {
        self.len
    }
    fn read_exact_at(&self, offset: u64, buf: &mut [u8]) -> io::Result<()> {
        if offset.checked_add(buf.len() as u64).is_none_or(|end| end > self.len) {
            return Err(io::ErrorKind::UnexpectedEof.into());
        }
        for (i, chunk) in buf.chunks_mut(64 * 1024).enumerate() {
            let offset = offset + i as u64 * 64 * 1024;
            let value = self
                .read
                .call2(
                    &self.object,
                    &JsValue::from_f64(offset as f64),
                    &JsValue::from_f64(chunk.len() as f64),
                )
                .map_err(|e| io::Error::other(format!("readAt({offset}): {}", message(e))))?;
            let array = value
                .dyn_into::<Uint8Array>()
                .map_err(|_| io::Error::other("readAt must return Uint8Array synchronously"))?;
            if array.length() as usize != chunk.len() {
                return Err(io::Error::other(format!(
                    "readAt({offset}): expected {} bytes, received {}",
                    chunk.len(),
                    array.length()
                )));
            }
            array.copy_to(chunk);
        }
        Ok(())
    }
}

struct HostSink {
    object: JsValue,
    mkdir: Function,
    write: Function,
}
impl Sink for HostSink {
    fn create_dir(&self, relative: &str) -> Result<()> {
        synchronous(self.mkdir.call1(&self.object, &relative.into()).map_err(error)?)
    }
    fn write_file(&self, relative: &str, bytes: &[u8]) -> Result<()> {
        // Owned JS buffer: IndexedDB may clone it after the Rust img/job has been dropped.
        let array = Uint8Array::from(bytes);
        synchronous(
            self.write
                .call2(&self.object, &relative.into(), &array)
                .map_err(error)?,
        )
    }
}
struct HostProgress(Function);
impl Progress for HostProgress {
    fn update(&self, file: &str, done: usize, total: usize) -> Result<()> {
        synchronous(
            self.0
                .call3(
                    &JsValue::UNDEFINED,
                    &file.into(),
                    &(done as u32).into(),
                    &(total as u32).into(),
                )
                .map_err(error)?,
        )
    }
}

/// `importWz({archives: {"Mob.wz": reader}} | {zip: reader}, manifestJson, sink, progress)`.
/// Returns a JSON report string; failures throw readable strings. See docs/ASSET_PIPELINE.md.
#[wasm_bindgen(js_name = importWz)]
pub fn import_wz(
    sources: JsValue,
    manifest_json: &str,
    sink: JsValue,
    progress: Function,
) -> std::result::Result<String, JsValue> {
    let run = || -> Result<String> {
        let archives = field(&sources, "archives")?;
        let zip = field(&sources, "zip")?;
        let has_archives = !archives.is_undefined() && !archives.is_null();
        let has_zip = !zip.is_undefined() && !zip.is_null();
        if has_archives == has_zip {
            return Err(WzError::Other(
                "sources must contain exactly one of archives or zip".into(),
            ));
        }
        let sources = if has_zip {
            crate::zip::zip_sources(Arc::new(HostReader::new(zip)?))?
        } else {
            if !archives.is_object() {
                return Err(WzError::Other(
                    "sources.archives must be an object keyed by archive basename".into(),
                ));
            }
            let mut named = NamedSources::new();
            for key in Object::keys(&Object::from(archives.clone())).iter() {
                let name = key.as_string().unwrap_or_default();
                if name.contains(['/', '\\']) || !name.ends_with(".wz") {
                    return Err(WzError::Other(format!("invalid archive basename {name:?}")));
                }
                let reader = HostReader::new(Reflect::get(&archives, &key).map_err(error)?)?;
                named.insert(name, Arc::new(reader) as Arc<dyn ReadAt>);
            }
            named
        };
        let sink = HostSink {
            mkdir: function(&sink, "createDir")?,
            write: function(&sink, "writeFile")?,
            object: sink.clone(),
        };
        let report = import_sources(sources, manifest_json, &sink, &HostProgress(progress.clone()))?;
        if !report.errors.is_empty() {
            return Err(WzError::Other(report.errors.join("\n")));
        }
        serde_json::to_string(&serde_json::json!({
            "index":report.index,"written":report.written,"warnings":report.warnings,
            "unresolved_uols":report.unresolved_uols,"uols_resolved":report.uols_resolved,"uols_external":report.uols_external
        })).map_err(|e| WzError::Other(e.to_string()))
    };
    run().map_err(|e| JsValue::from_str(&e.to_string()))
}
