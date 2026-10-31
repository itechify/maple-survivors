// DEV ONLY: tests of web/dev/manifest_files.mjs, the JS twin of the importer's manifest merge (tools/wzimport/src/manifest.rs),
// and that the shipping manifest plus its asset_manifest.d fragments selects exactly the golden list the importer is tested
// against. Run: `node --test web/dev/test/*.test.mjs`.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { canonicalLines, fragmentDir, mergeManifests, readMergedManifest } from '../manifest_files.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const repo = path.join(here, '../../..');

const MAIN = {
	name: 'asset_manifest.json',
	data: { format: 1, _doc: 'x', imgs: [{ img: 'A.wz/a.img' }, { img: 'S.wz/s.img', paths: ['1', '2'] }], maps: [1], mobs: [7], character: [2000], items: [4000000] },
};
const frag = (name, data) => ({ name, data });

test('fragments are appended after the main file, other paths of the same img are fine', () => {
	const m = mergeManifests(MAIN, [
		frag('a.json', { _doc: 'a', imgs: [{ img: 'S.wz/s.img', paths: ['3'] }, { img: 'B.wz/b.img' }], mobs: [8] }),
		frag('b.json', { format: 1, maps: [2], mapimgs: ['U.wz/m.img'], character: [1372000], items: [4000001] }),
	]);
	assert.equal(m.imgs.length, 4);
	assert.deepEqual([m.maps, m.mobs, m.character, m.items, m.mapimgs], [[1, 2], [7, 8], [2000, 1372000], [4000000, 4000001], ['U.wz/m.img']]);
	assert.ok(canonicalLines(m).includes('img S.wz/s.img 3'));
});

test('a key in two files is an error naming both files', () => {
	const cases = [
		[{ maps: [1] }, '`map 1`'], [{ mobs: [7] }, '`mob 7`'], [{ character: [2000] }, '`character 2000`'], [{ items: [4000000] }, '`item 4000000`'],
		[{ imgs: [{ img: 'A.wz/a.img' }] }, '`img A.wz/a.img`'], [{ imgs: [{ img: 'S.wz/s.img', paths: ['2', '9'] }] }, 'path "2"'],
		[{ imgs: [{ img: 'A.wz/a.img', paths: ['x'] }] }, '`img A.wz/a.img`'], [{ imgs: [{ img: 'S.wz/s.img' }] }, '`img S.wz/s.img`'],
	];
	for (const [data, what] of cases) {
		assert.throws(() => mergeManifests(MAIN, [frag('wizard.json', data)]), (e) => e.message.includes(what) && e.message.includes('asset_manifest.json') && e.message.includes('wizard.json'), what);
	}
	assert.throws(() => mergeManifests(MAIN, [frag('a.json', { mobs: [9] }), frag('b.json', { mobs: [9] })]), /a\.json and b\.json/);
	assert.doesNotThrow(() => mergeManifests(MAIN, [frag('a.json', { mobs: [9, 9] })]));
});

test('region fragments hold maps, mobs and items; a mob two regions both list is an error naming both (spec #449 C0)', () => {
	const a = frag('region_a.json', { _doc: 'region a', maps: [220011000], mobs: [3230101, 4130103], items: [4000100] });
	const m = mergeManifests(MAIN, [a, frag('region_b.json', { maps: [221040000], mobs: [3230102], items: [4000101] })]);
	assert.deepEqual([m.maps, m.mobs, m.items], [[1, 220011000, 221040000], [7, 3230101, 4130103, 3230102], [4000000, 4000100, 4000101]]);
	for (const [data, what] of [[{ mobs: [3230101] }, '`mob 3230101`'], [{ maps: [220011000] }, '`map 220011000`'], [{ items: [4000100] }, '`item 4000100`']]) {
		assert.throws(() => mergeManifests(MAIN, [a, frag('region_c.json', data)]), (e) => e.message.includes(what) && e.message.includes('region_a.json') && e.message.includes('region_c.json'), what);
	}
});

test('bad fragments are rejected', () => {
	for (const data of [{ mob: [1] }, { format: 2 }, []]) assert.throws(() => mergeManifests(MAIN, [frag('bad.json', data)]), /bad\.json/);
	assert.throws(() => mergeManifests({ name: 'm.json', data: { format: 2 } }, []), /m\.json/);
});

test('readMergedManifest reads the sibling folder sorted by file name; a missing folder is fine', () => {
	const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'manifest-merge-'));
	const main = path.join(dir, 'asset_manifest.json');
	fs.writeFileSync(main, JSON.stringify(MAIN.data));
	assert.deepEqual(readMergedManifest(main).mobs, [7]);
	fs.mkdirSync(fragmentDir(main));
	fs.writeFileSync(path.join(fragmentDir(main), 'b.json'), '{"mobs":[2]}');
	fs.writeFileSync(path.join(fragmentDir(main), 'a.json'), '{"mobs":[1]}');
	fs.writeFileSync(path.join(fragmentDir(main), 'notes.txt'), 'not json');
	assert.deepEqual(readMergedManifest(main).mobs, [7, 1, 2]);
	fs.rmSync(dir, { recursive: true, force: true });
});

test('the shipping manifest with its fragments selects exactly the golden list of tools/wzimport', () => {
	const golden = fs.readFileSync(path.join(repo, 'tools/wzimport/tests/fixtures/manifest_golden.txt'), 'utf8')
		.split('\n').filter((l) => l && !l.startsWith('#'));
	const got = canonicalLines(readMergedManifest(path.join(repo, 'game/data/asset_manifest.json')));
	assert.deepEqual(got, golden);
});
