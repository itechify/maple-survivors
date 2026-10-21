// DEV ONLY: tests of scripts/check_web_artifact.sh, the guard that keeps WZ data and cache-shaped files out of the
// web build (and so out of GitHub Pages). Run: `node --test web/dev/test/*.test.mjs` (needs bash; Git Bash on Windows).
// Every fixture is synthetic: tiny files with the shape (name or magic bytes) of what must never ship.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const script = path.join(here, '../../../scripts/check_web_artifact.sh');

/** Files a clean web export holds (names as Godot 4.7.2 and export.sh --web write them). */
const CLEAN = {
	'index.html': '<!DOCTYPE html>',
	'index.js': 'var Godot;',
	'index.wasm': '\0asm\x01\0\0\0',
	'index.pck': 'GDPC',
	'index.png': 'png',
	'index.icon.png': 'png',
	'index.apple-touch-icon.png': 'png',
	'index.audio.worklet.js': '//',
	'index.audio.position.worklet.js': '//',
	'shell.css': 'body{}',
	'shell.js': '//',
	'lib.js': '//',
	'idbfs.js': '//',
	'import_worker.js': '//',
	'title.jpg': 'jpg',
	'favicon.ico': 'ico',
	'favicon-16x16.png': 'png',
	'favicon-32x32.png': 'png',
	'apple-touch-icon.png': 'png',
	'android-chrome-192x192.png': 'png',
	'android-chrome-512x512.png': 'png',
	'site.webmanifest': '{}',
	'wzimport.js': '//',
	'wzimport_bg.wasm': '\0asm\x01\0\0\0',
	'asset_manifest.json': '{}',
	'GODOT_LICENSES.txt': 'MIT',
	'WZIMPORT_LICENSES.txt': 'MIT',
	'THIRD_PARTY_NOTICES.md': '# notices',
	'ARIMO_OFL.txt': 'OFL',
};

function bash() {
	// Prefer Git Bash on Windows: `bash` on PATH can be WSL, which cannot see Windows paths.
	const git = 'C:/Program Files/Git/bin/bash.exe';
	return process.platform === 'win32' && fs.existsSync(git) ? git : 'bash';
}

function makeDir(extra = {}, without = []) {
	const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'webcheck-'));
	for (const [name, body] of Object.entries({ ...CLEAN, ...extra })) {
		if (without.includes(name)) continue;
		const p = path.join(dir, name);
		fs.mkdirSync(path.dirname(p), { recursive: true });
		fs.writeFileSync(p, body);
	}
	return dir;
}

function run(dir) {
	const r = spawnSync(bash(), [script, dir], { encoding: 'utf8' });
	return { code: r.status, out: `${r.stdout}${r.stderr}` };
}

test('a clean export passes', () => {
	const dir = makeDir();
	const r = run(dir);
	assert.equal(r.code, 0, r.out);
	fs.rmSync(dir, { recursive: true, force: true });
});

const PLANTED = {
	'a WZ archive': 'Mob.wz',
	'a WZ archive in a subfolder, upper-case extension': 'data/Map.WZ',
	'a WZ image file': 'Mob.wz/0100100.img',
	'an image tree json': 'Mob.wz/0100100.img.json',
	'an atlas page': 'Mob.wz/0100100.img.0.png',
	'an atlas page in any folder': 'sprites/stand.12.png',
	'an mp3': 'Sound.wz/Bgm00/FloralLife.mp3',
	'a wav': 'Sound.wz/Mob.img/Attack.wav',
	'the cache index': 'asset_cache/v83/cache.json',
	'an unexpected decoded image': 'unlisted.png',
	'an unexpected archive': 'unlisted.zip',
	'an unexpected nested file': 'backup/readme.txt',
};

for (const [what, name] of Object.entries(PLANTED)) {
	test(`rejects ${what} (${name})`, () => {
		const dir = makeDir({ [name]: 'x' });
		const r = run(dir);
		assert.notEqual(r.code, 0, `${name} should have failed the check`);
		assert.match(r.out, new RegExp(path.basename(name).replace(/\./g, '\\.')));
		fs.rmSync(dir, { recursive: true, force: true });
	});
}

test('rejects a file with WZ magic bytes under an innocent name', () => {
	const dir = makeDir({ 'notes.txt': 'PKG1\0\0\0\0' });
	const r = run(dir);
	assert.notEqual(r.code, 0);
	assert.match(r.out, /notes\.txt/);
	fs.rmSync(dir, { recursive: true, force: true });
});

test('rejects a ZIP containing synthetic WZ data, even with an allowed image name', () => {
	// Valid stored ZIP: Mob.wz with the four bytes PKG1. All bytes are synthetic.
	const name = Buffer.from('Mob.wz'), body = Buffer.from('PKG1');
	let crc = 0xffffffff;
	for (const b of body) {
		crc ^= b;
		for (let i = 0; i < 8; i++) crc = (crc >>> 1) ^ ((crc & 1) ? 0xedb88320 : 0);
	}
	crc = (crc ^ 0xffffffff) >>> 0;
	const local = Buffer.alloc(30); local.writeUInt32LE(0x04034b50); local.writeUInt16LE(20, 4);
	local.writeUInt32LE(crc, 14); local.writeUInt32LE(4, 18); local.writeUInt32LE(4, 22); local.writeUInt16LE(name.length, 26);
	const central = Buffer.alloc(46); central.writeUInt32LE(0x02014b50); central.writeUInt16LE(20, 4); central.writeUInt16LE(20, 6);
	central.writeUInt32LE(crc, 16); central.writeUInt32LE(4, 20); central.writeUInt32LE(4, 24); central.writeUInt16LE(name.length, 28);
	const end = Buffer.alloc(22); end.writeUInt32LE(0x06054b50); end.writeUInt16LE(1, 8); end.writeUInt16LE(1, 10);
	end.writeUInt32LE(central.length + name.length, 12); end.writeUInt32LE(local.length + name.length + body.length, 16);
	const zip = Buffer.concat([local, name, body, central, name, end]);
	for (const name of ['unlisted.zip', 'favicon-32x32.png']) {
		const dir = makeDir({ [name]: zip });
		assert.notEqual(run(dir).code, 0, name);
		fs.rmSync(dir, { recursive: true, force: true });
	}
});

test('fails when a required file is missing', () => {
	for (const name of ['index.html', 'index.wasm', 'index.pck', 'wzimport_bg.wasm', 'GODOT_LICENSES.txt', 'ARIMO_OFL.txt']) {
		const dir = makeDir({}, [name]);
		const r = run(dir);
		assert.notEqual(r.code, 0, `${name} missing should fail`);
		assert.match(r.out, new RegExp(name.replace(/\./g, '\\.')));
		fs.rmSync(dir, { recursive: true, force: true });
	}
});

test('fails on a folder that does not exist', () => {
	const r = run(path.join(os.tmpdir(), 'webcheck-does-not-exist'));
	assert.notEqual(r.code, 0);
});
