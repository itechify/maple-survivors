// DEV ONLY: tests of the boot manifest check (web/lib.js assessCache) against each cached img's `paths`, and that the
// category tables of web/lib.js equal the importer's (tools/wzimport/src/manifest.rs). Run: `node --test web/dev/test/*.test.mjs`.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import * as lib from '../../lib.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const manifestText = fs.readFileSync(path.join(here, '../../../game/data/asset_manifest.json'), 'utf8');

/** An index from {img: {pages, paths}}; `paths` null = the whole img, like the importer's cache.json. */
function indexWithPaths(imgs) {
	const o = { format: 1, imgs: {} };
	for (const [img, e] of Object.entries(imgs)) o.imgs[img] = { json: img + '.json', pages: e.pages || 0, paths: e.paths ?? null };
	return JSON.stringify(o);
}

const skillManifest = { format: 1, imgs: [{ img: 'Sound.wz/Skill.img', paths: ['0001000', '2001004'] }] };

test('assessCache: a manifest path added inside an already cached partial img is incomplete', () => {
	const old = indexWithPaths({ 'Sound.wz/Skill.img': { paths: ['0001000'] } });
	const r = lib.assessCache({ manifest: skillManifest, indexText: old });
	assert.equal(r.state, 'incomplete');
	assert.deepEqual(r.missing, [{ img: 'Sound.wz/Skill.img', reason: 'paths missing' }]);
	const now = indexWithPaths({ 'Sound.wz/Skill.img': { paths: ['0001000', '2001004'] } });
	assert.equal(lib.assessCache({ manifest: skillManifest, indexText: now }).state, 'ok');
	// The same img cached whole covers any selection.
	assert.equal(lib.assessCache({ manifest: skillManifest, indexText: indexWithPaths({ 'Sound.wz/Skill.img': {} }) }).state, 'ok');
});

test('assessCache: an img that went from a partial selection to the whole img is incomplete', () => {
	const whole = { format: 1, imgs: [{ img: 'Sound.wz/Skill.img' }] };
	const partial = indexWithPaths({ 'Sound.wz/Skill.img': { paths: ['0001000'] } });
	const r = lib.assessCache({ manifest: whole, indexText: partial });
	assert.equal(r.state, 'incomplete');
	assert.equal(r.missing[0].reason, 'paths missing');
	assert.equal(lib.assessCache({ manifest: whole, indexText: indexWithPaths({ 'Sound.wz/Skill.img': {} }) }).state, 'ok');
});

test('assessCache: a cached path covers requests below it, not a sibling or a longer-named neighbour', () => {
	const m = { format: 1, imgs: [{ img: 'A.wz/x.img', paths: ['a/b', 'c'] }] };
	const ok = indexWithPaths({ 'A.wz/x.img': { paths: ['a', 'c'] } });
	assert.equal(lib.assessCache({ manifest: m, indexText: ok }).state, 'ok');
	const sibling = indexWithPaths({ 'A.wz/x.img': { paths: ['a/bc', 'c'] } });
	assert.equal(lib.assessCache({ manifest: m, indexText: sibling }).state, 'incomplete');
	const narrower = indexWithPaths({ 'A.wz/x.img': { paths: ['a/b/d', 'c'] } });
	assert.equal(lib.assessCache({ manifest: m, indexText: narrower }).state, 'incomplete');
});

test('assessCache: item selections need their id path in the cached img', () => {
	const m = { format: 1, items: [4000019, 4000000] };
	const have = indexWithPaths({ 'Item.wz/Etc/0400.img': { paths: ['04000000', '04000019'] } });
	assert.equal(lib.assessCache({ manifest: m, indexText: have }).state, 'ok');
	const lacking = indexWithPaths({ 'Item.wz/Etc/0400.img': { paths: ['04000000'] } });
	const r = lib.assessCache({ manifest: m, indexText: lacking });
	assert.equal(r.state, 'incomplete');
	assert.deepEqual(r.missing, [{ img: 'Item.wz/Etc/0400.img', reason: 'paths missing' }]);
});

test('assessCache: mob sounds and map portals are path requests, a whole-img request wins over paths', () => {
	const m = { format: 1, mobs: [100100], maps: [104040000], imgs: [{ img: 'Map.wz/MapHelper.img', paths: ['other'] }] };
	const full = indexWithPaths({
		'Mob.wz/0100100.img': {}, 'Sound.wz/Mob.img': { paths: ['0100100'] }, 'Map.wz/Map/Map1/104040000.img': {},
		'Map.wz/MapHelper.img': { paths: ['other', 'portal'] },
	});
	assert.equal(lib.assessCache({ manifest: m, indexText: full }).state, 'ok');
	const noSound = full.replace('"0100100"', '"0100200"');
	assert.deepEqual(lib.assessCache({ manifest: m, indexText: noSound }).missing.map((x) => x.img), ['Sound.wz/Mob.img']);
	const req = lib.expectedRequests({ format: 1, imgs: [{ img: 'Q.wz/a.img', paths: ['x'] }, { img: 'Q.wz/a.img' }] });
	assert.equal(req.get('Q.wz/a.img').whole, true);
});

test('assessCache: the real manifest is ok against an index of its own requests; dropping the meso img is detected', () => {
	const m = lib.parseManifest(manifestText);
	const imgs = {};
	for (const [img, r] of lib.expectedRequests(m)) imgs[img] = { paths: r.whole ? null : Array.from(r.paths) };
	assert.equal(lib.assessCache({ manifest: m, indexText: indexWithPaths(imgs) }).state, 'ok');
	// The meso coin sprites (items 9000000-9000003) live in Item.wz/Special/0900.img.
	assert.ok(imgs['Item.wz/Special/0900.img'], 'the real manifest requests the meso imgs');
	delete imgs['Item.wz/Special/0900.img'];
	const r = lib.assessCache({ manifest: m, indexText: indexWithPaths(imgs) });
	assert.equal(r.state, 'incomplete');
	assert.deepEqual(r.missing, [{ img: 'Item.wz/Special/0900.img', reason: 'not in the cache index' }]);
});

// ---- The category tables equal the importer's -----------------------------------------------------------------------

const rustSource = fs.readFileSync(path.join(here, '../../../tools/wzimport/src/manifest.rs'), 'utf8');

/** The `match` arms of a Rust function as a function category -> string|null, parsed from the source text. */
function rustTable(fnName, scrutinee) {
	const start = rustSource.indexOf(`fn ${fnName}(`);
	assert.ok(start >= 0, `fn ${fnName} not found in manifest.rs`);
	const open = rustSource.indexOf(scrutinee + ' {', start);
	assert.ok(open >= 0, `match ${scrutinee} not found in ${fnName}`);
	const body = rustSource.slice(open + scrutinee.length + 2, rustSource.indexOf('};', open));
	const arms = [];
	for (const line of body.split('\n')) {
		const m = line.match(/^\s*([0-9_ |.=]+?)\s*=>\s*(?:"([A-Za-z]*)"|return None)/);
		if (!m) continue;
		const ranges = m[1].split('|').map((part) => {
			const [lo, hi] = part.trim().split('..=').map((n) => Number(n.replace(/_/g, '')));
			return [lo, hi === undefined ? lo : hi];
		});
		arms.push({ ranges, value: m[2] === undefined ? null : m[2] });
	}
	assert.ok(arms.length >= 5, `parsed too few arms of ${fnName}`);
	return (cat) => {
		for (const a of arms) if (a.ranges.some(([lo, hi]) => cat >= lo && cat <= hi)) return a.value;
		return null;
	};
}

test('web/lib.js character directories equal the importer table for every category', () => {
	const dir = rustTable('character_img_path', 'match id / 10000');
	for (let cat = 0; cat <= 1200; cat++) {
		const want = dir(cat);
		const id = cat * 10000 + 123;
		const got = lib.characterImgPath(id);
		if (want === null) assert.equal(got, null, `category ${cat}`);
		else {
			const file = String(id).padStart(8, '0');
			assert.equal(got, want === '' ? `Character.wz/${file}.img` : `Character.wz/${want}/${file}.img`, `category ${cat}`);
		}
	}
});

test('web/lib.js item categories equal the importer table for every type', () => {
	const kind = rustTable('item_path', 'match id / 1_000_000');
	for (let t = 0; t <= 99; t++) {
		const want = kind(t);
		const got = lib.itemPath(t * 1000000 + 19);
		if (want === null) assert.equal(got, null, `item type ${t}`);
		else {
			assert.equal(got.img, `Item.wz/${want}/${String(t * 100).padStart(4, '0')}.img`, `item type ${t}`);
			assert.equal(got.sub, String(t * 1000000 + 19).padStart(8, '0'));
		}
	}
	assert.deepEqual(Object.values(lib.ITEM_KINDS).sort(), ['Cash', 'Consume', 'Etc', 'Install', 'Special']);
});
