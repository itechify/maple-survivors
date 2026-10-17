// DEV ONLY: unit tests of web/lib.js, the pure helpers of the web shell. Run: `node --test web/dev/test/*.test.mjs`
// (Node 20+, no dependencies; browser behaviour is covered by the Playwright runs described in docs/ARCHITECTURE.md).
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import * as lib from '../../lib.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const manifestText = fs.readFileSync(path.join(here, '../../../game/data/asset_manifest.json'), 'utf8');

test('img path formulas match the importer (tools/wzimport/src/manifest.rs tests)', () => {
	assert.equal(lib.mapImgPath(104040000), 'Map.wz/Map/Map1/104040000.img');
	assert.equal(lib.mapImgPath(910000000), 'Map.wz/Map/Map9/910000000.img');
	assert.equal(lib.mapImgPath(10000), 'Map.wz/Map/Map0/000010000.img');
	assert.equal(lib.mobImgPath(100100), 'Mob.wz/0100100.img');
	assert.equal(lib.characterImgPath(2000), 'Character.wz/00002000.img');
	assert.equal(lib.characterImgPath(12000), 'Character.wz/00012000.img');
	assert.equal(lib.characterImgPath(20000), 'Character.wz/Face/00020000.img');
	assert.equal(lib.characterImgPath(30030), 'Character.wz/Hair/00030030.img');
	assert.equal(lib.characterImgPath(1040002), 'Character.wz/Coat/01040002.img');
	assert.equal(lib.characterImgPath(1302000), 'Character.wz/Weapon/01302000.img');
	assert.equal(lib.characterImgPath(1012000), 'Character.wz/Accessory/01012000.img');
	assert.equal(lib.characterImgPath(9990000), null);
	assert.equal(lib.itemImgPath(4000019), 'Item.wz/Etc/0400.img');
	assert.equal(lib.itemImgPath(2000000), 'Item.wz/Consume/0200.img');
	assert.equal(lib.itemImgPath(9000000), null);
});

test('the real manifest needs the twelve archives the desktop import reads', () => {
	const m = lib.parseManifest(manifestText);
	assert.deepEqual(lib.requiredArchives(m), [
		'Base.wz', 'Character.wz', 'Effect.wz', 'Etc.wz', 'Item.wz', 'Map.wz', 'Mob.wz', 'Npc.wz', 'Skill.wz',
		'Sound.wz', 'String.wz', 'UI.wz',
	]);
	const imgs = lib.expectedImgs(m);
	assert.ok(imgs.includes('Mob.wz/0100100.img'));
	assert.ok(imgs.includes('Map.wz/Map/Map1/104040000.img'));
	assert.ok(imgs.includes('UI.wz/MapLogin.img'));
	assert.ok(imgs.includes('Sound.wz/Mob.img'));
	assert.ok(imgs.includes('Item.wz/Etc/0400.img'));
	assert.equal(new Set(imgs).size, imgs.length);
});

test('parseManifest refuses an unknown format', () => {
	assert.throws(() => lib.parseManifest('{"format": 2}'), /unsupported/);
});

const tiny = { format: 1, imgs: [{ img: 'Base.wz/zmap.img' }], mobs: [100100] };
function indexFor(imgs) {
	const o = { format: 1, imgs: {} };
	for (const [img, pages] of Object.entries(imgs)) o.imgs[img] = { json: img + '.json', pages };
	return JSON.stringify(o);
}

test('assessCache: none, invalid, ok and incomplete', () => {
	assert.equal(lib.assessCache({ manifest: tiny, indexText: null }).state, 'none');
	assert.equal(lib.assessCache({ manifest: tiny, indexText: '{nope' }).state, 'invalid');
	assert.equal(lib.assessCache({ manifest: tiny, indexText: '{"format":2,"imgs":{}}' }).state, 'invalid');
	const full = indexFor({ 'Base.wz/zmap.img': 0, 'Mob.wz/0100100.img': 2, 'Sound.wz/Mob.img': 0 });
	assert.equal(lib.assessCache({ manifest: tiny, indexText: full }).state, 'ok');
	const lacking = indexFor({ 'Base.wz/zmap.img': 0, 'Sound.wz/Mob.img': 0 });
	const r = lib.assessCache({ manifest: tiny, indexText: lacking });
	assert.equal(r.state, 'incomplete');
	assert.deepEqual(r.missing, [{ img: 'Mob.wz/0100100.img', reason: 'not in the cache index' }]);
});

test('assessCache: a listed img whose files are gone is missing', () => {
	const root = lib.CACHE_ROOT;
	const text = indexFor({ 'Base.wz/zmap.img': 0, 'Mob.wz/0100100.img': 2, 'Sound.wz/Mob.img': 0 });
	const keys = [`${root}/Base.wz/zmap.img.json`, `${root}/Mob.wz/0100100.img.json`, `${root}/Mob.wz/0100100.img.0.png`,
		`${root}/Sound.wz/Mob.img.json`];
	const r = lib.assessCache({ manifest: tiny, indexText: text, keys });
	assert.equal(r.state, 'incomplete');
	assert.deepEqual(r.missing.map((m) => m.img), ['Mob.wz/0100100.img']);
	keys.push(`${root}/Mob.wz/0100100.img.1.png`);
	assert.equal(lib.assessCache({ manifest: tiny, indexText: text, keys }).state, 'ok');
});

test('parseSourceUrl: zip, base folder, and refusals', () => {
	let r = lib.parseSourceUrl('  https://example.test/files/v83.zip ');
	assert.deepEqual([r.ok, r.kind, r.url, r.host], [true, 'zip', 'https://example.test/files/v83.zip', 'example.test']);
	r = lib.parseSourceUrl('http://127.0.0.1:8070/v83');
	assert.deepEqual([r.ok, r.kind, r.base], [true, 'base', 'http://127.0.0.1:8070/v83/']);
	assert.equal(lib.parseSourceUrl('https://example.test/V83.ZIP?x=1#frag').kind, 'zip');
	assert.equal(lib.parseSourceUrl('').ok, false);
	assert.equal(lib.parseSourceUrl('not a url').ok, false);
	assert.equal(lib.parseSourceUrl('ftp://example.test/a.zip').ok, false);
	assert.match(lib.parseSourceUrl('https://example.test/Mob.wz').error, /folder/);
	assert.equal(lib.archiveUrl('http://127.0.0.1:8070/v83/', 'Mob.wz'), 'http://127.0.0.1:8070/v83/Mob.wz');
});

test('pickArchiveFolder finds the folder with the most archives, ignoring case', () => {
	const files = [
		{ path: 'MapleStory/Mob.wz' }, { path: 'MapleStory/map.wz' }, { path: 'MapleStory/MapleStory.exe' },
		{ path: 'MapleStory/Data/Mob.wz' },
	];
	const r = lib.pickArchiveFolder(files, ['Map.wz', 'Mob.wz', 'Npc.wz']);
	assert.equal(r.dir, 'MapleStory');
	assert.deepEqual(Object.keys(r.found).sort(), ['Map.wz', 'Mob.wz']);
	assert.deepEqual(r.missing, ['Npc.wz']);
	assert.equal(lib.pickArchiveFolder([], ['Map.wz']).missing[0], 'Map.wz');
});

test('formatBytes', () => {
	assert.equal(lib.formatBytes(0), '0 B');
	assert.equal(lib.formatBytes(1536), '1.5 KB');
	assert.equal(lib.formatBytes(635444895), '606 MB');
	assert.equal(lib.formatBytes(1.9 * 1024 ** 3), '1.9 GB');
});

function fakeFile(size) {
	const data = new Uint8Array(size);
	for (let i = 0; i < size; i++) data[i] = (i * 31 + (i >> 8)) & 255;
	const calls = [];
	return { data, calls, fetchRange: (s, e) => { calls.push([s, e]); return data.slice(s, e); } };
}

test('block reader: returns exact bytes, caches blocks and merges adjacent misses', () => {
	const f = fakeFile(1000);
	const r = lib.createBlockReader({ length: 1000, fetchRange: f.fetchRange, blockSize: 100, maxBlocks: 4 });
	assert.deepEqual(r.readAt(10, 20), f.data.slice(10, 30));
	assert.deepEqual(f.calls, [[0, 100]]);
	assert.deepEqual(r.readAt(90, 30), f.data.slice(90, 120)); // block 0 cached, block 1 fetched
	assert.deepEqual(f.calls, [[0, 100], [100, 200]]);
	assert.deepEqual(r.readAt(450, 200), f.data.slice(450, 650)); // blocks 4..6 in ONE request
	assert.deepEqual(f.calls.at(-1), [400, 700]);
	assert.deepEqual(r.readAt(990, 10), f.data.slice(990, 1000)); // last block, end of file
	assert.equal(r.readAt(5, 0).length, 0);
	assert.equal(r.stats.requests, f.calls.length);
});

test('block reader: evicts the least recently used block, and refuses reads outside the file', () => {
	const f = fakeFile(1000);
	const r = lib.createBlockReader({ length: 1000, fetchRange: f.fetchRange, blockSize: 100, maxBlocks: 2 });
	r.readAt(0, 1); r.readAt(100, 1); r.readAt(0, 1); // block 0 is now newer than block 1
	r.readAt(200, 1); // evicts block 1
	const n = f.calls.length;
	r.readAt(0, 1);
	assert.equal(f.calls.length, n); // block 0 still cached
	r.readAt(100, 1);
	assert.equal(f.calls.length, n + 1); // block 1 had to be fetched again
	assert.throws(() => r.readAt(995, 10), /outside/);
	assert.throws(() => r.readAt(-1, 1), /outside/);
});

test('block reader: a short fetch is an error, not silent corruption', () => {
	const r = lib.createBlockReader({ length: 300, fetchRange: (s, e) => new Uint8Array(e - s - 1), blockSize: 100 });
	assert.throws(() => r.readAt(0, 10), /short read/);
});

test('block reader: a 64 KiB read in a 1 MiB block world costs one request per block', () => {
	const f = fakeFile(5 << 20);
	const r = lib.createBlockReader({ length: 5 << 20, fetchRange: f.fetchRange });
	for (let off = 0; off < (2 << 20); off += 65536) r.readAt(off, 65536);
	assert.equal(f.calls.length, 2);
});

test('parseMarker', () => {
	assert.deepEqual(lib.parseMarker('{"format": 1, "request": "reimport"}'), { ok: true, kind: 'reimport' });
	assert.equal(lib.parseMarker('{"format": 1, "request": "export_save"}').kind, 'export_save');
	assert.equal(lib.parseMarker('{"format": 1, "request": "import_save"}').kind, 'import_save');
	const unknown = lib.parseMarker('{"format": 1, "request": "teleport"}');
	assert.deepEqual([unknown.ok, unknown.unknown], [false, true]);
	assert.equal(lib.parseMarker('{"format": 2, "request": "reimport"}').ok, false);
	assert.equal(lib.parseMarker('garbage').ok, false);
	assert.equal(lib.parseMarker('[]').ok, false);
});

test('validateSaveText: accepts the SaveData shapes and refuses others before anything is written', () => {
	const slots = [{ name: 'Alpha' }, null, { name: 'Gamma' }];
	const v2 = JSON.stringify({ format: 2, best: {}, runs: {}, slots, history: [] });
	assert.deepEqual(lib.validateSaveText(v2), { ok: true, slots: 2 });
	assert.deepEqual(lib.validateSaveText('{"format":1,"best":{},"runs":{}}'), { ok: true, slots: 0 });
	for (const bad of ['{', '[]', '{"format":3,"best":{},"runs":{}}', '{"format":2,"best":{},"runs":{}}',
		JSON.stringify({ format: 2, best: {}, runs: {}, slots: [null, null], history: [] }),
		JSON.stringify({ format: 2, best: [], runs: {}, slots: [null, null, null], history: [] })]) {
		const r = lib.validateSaveText(bad);
		assert.equal(r.ok, false, bad);
		assert.ok(r.error.length > 0);
	}
});

test('saveFileName is timestamped in local time', () => {
	assert.equal(lib.saveFileName(new Date(2026, 9, 7, 4, 5, 9)), 'maple-survivors-save-20261007-040509.json');
});

test('isAudioTeardownError recognises the Godot web shutdown TypeError', () => {
	assert.ok(lib.isAudioTeardownError("TypeError: Cannot read properties of null (reading 'currentTime')"));
	assert.ok(!lib.isAudioTeardownError('TypeError: x is not a function'));
});
