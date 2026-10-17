// Callback/lifetime checks through generated wasm glue; no proprietary fixtures or browser needed.
// node tools/wzimport/tests/wasm_scratch.mjs <build_wasm.sh output directory>
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { deflateRawSync } from 'node:zlib';

const directory = path.resolve(process.argv[2]);
const { default: init, importWz } = await import(pathToFileURL(path.join(directory, 'wzimport.js')));
await init({ module_or_path: fs.readFileSync(path.join(directory, 'wzimport_bg.wasm')) });

// Empty synthetic v83 PKG1: opening it succeeds; requesting an absent img then fails.
const wz = Buffer.alloc(64);
wz.write('PKG1');
wz.writeUInt32LE(60, 12);
wz.writeUInt16LE(0xac, 60);
function zip(deflated = true) {
  const name = Buffer.from('83/Mob.wz');
  const payload = deflated ? deflateRawSync(wz) : wz;
  const local = Buffer.alloc(30);
  local.writeUInt32LE(0x04034b50);
  local.writeUInt16LE(deflated ? 8 : 0, 8);
  local.writeUInt32LE(payload.length, 18);
  local.writeUInt32LE(wz.length, 22);
  local.writeUInt16LE(name.length, 26);
  const central = Buffer.alloc(46);
  central.writeUInt32LE(0x02014b50);
  central.writeUInt16LE(deflated ? 8 : 0, 10);
  central.writeUInt32LE(payload.length, 20);
  central.writeUInt32LE(wz.length, 24);
  central.writeUInt16LE(name.length, 28);
  const end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50);
  end.writeUInt16LE(1, 8);
  end.writeUInt16LE(1, 10);
  end.writeUInt32LE(central.length + name.length, 12);
  end.writeUInt32LE(local.length + name.length + payload.length, 16);
  return Buffer.concat([local, name, payload, central, name, end]);
}
const manifest = JSON.stringify({ format: 1, imgs: [{ img: 'Mob.wz/missing.img' }] });
const sink = { createDir() {}, writeFile() {} };
let passed = 0;
for (const mode of ['normal', 'writeThrows', 'writePromise', 'readShort', 'readPromise', 'missingWrite']) {
  let created = 0, closed = 0, written = 0;
  const scratch = { create(name, length) {
    assert.equal(this, scratch);
    assert.equal(name, 'Mob.wz');
    assert.equal(length, wz.length);
    created++;
    const data = Buffer.alloc(length);
    const handle = {
      write(offset, bytes) {
        assert.equal(this, handle);
        assert.equal(offset, written);
        assert.ok(bytes.length <= 65536);
        if (mode === 'writeThrows') throw Error('quota exhausted');
        if (mode === 'writePromise') return Promise.resolve();
        data.set(bytes, offset); written += bytes.length;
      },
      readAt(offset, length) {
        assert.equal(this, handle);
        if (mode === 'readPromise') return Promise.resolve(data);
        return data.slice(offset, offset + length - (mode === 'readShort' ? 1 : 0));
      },
      close() { assert.equal(this, handle); closed++; }
    };
    if (mode === 'missingWrite') delete handle.write;
    return handle;
  } };
  const bytes = zip();
  const expected = { normal: /manifest img/, writeThrows: /quota exhausted/, writePromise: /synchronous/,
    readShort: /expected 64 bytes, received 63/, readPromise: /Uint8Array synchronously/,
    missingWrite: /write must be a synchronous function/ }[mode];
  assert.throws(() => importWz({ zip: { length: bytes.length, readAt: (o, n) => bytes.slice(o, o + n) }, scratch }, manifest, sink, () => {}), expected);
  assert.equal(created, 1);
  assert.equal(closed, 1);
  if (mode === 'normal') assert.equal(written, wz.length);
  passed++;
}
const stored = zip(false);
assert.throws(() => importWz({ zip: { length: stored.length, readAt: (o, n) => stored.slice(o, o + n) },
  scratch: { create() { assert.fail('stored entries must not use scratch'); } } }, manifest, sink, () => {}), /manifest img/);
console.log(`${passed + 1} wasm scratch callback checks passed`);
