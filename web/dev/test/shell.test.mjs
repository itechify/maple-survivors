// DEV ONLY: exercise the actual shell entry points with synthetic DOM/storage and an exclusive lock service.
// No engine, browser profile, real IndexedDB, assets or network is opened.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import * as lib from '../../lib.js';

const source = fs.readFileSync(new URL('../../shell.js', import.meta.url), 'utf8')
	.replace("import './idbfs.js';", '').replace("import * as lib from './lib.js';", '');
const tick = () => new Promise((resolve) => setImmediate(resolve));

function lockService() {
	const held = new Set();
	return { request: async (name, _options, callback) => {
		if (held.has(name)) return callback(null);
		held.add(name);
		try { await callback({ name }); } finally { held.delete(name); }
	} };
}

async function page(locks) {
	const elements = new Map();
	const files = new Map([[lib.SAVE_PATH, 'healthy primary'], [lib.SAVE_PATH + '.bak', 'healthy backup']]);
	const writes = [];
	const calls = { storage: 0, engine: 0, reads: 0 };
	const element = (id) => {
		if (!elements.has(id)) elements.set(id, {
			dataset: {}, style: {}, hidden: false, textContent: '',
			addEventListener() {}, removeAttribute() {},
		});
		return elements.get(id);
	};
	const context = vm.createContext({
		lib, TextEncoder, URLSearchParams,
		setTimeout() { return 1; }, clearTimeout() {},
		console: { log() {}, error() {} },
		window: { addEventListener() {}, location: { search: '' } },
		location: { reload() {} },
		document: { getElementById: element, querySelectorAll() { return []; } },
		navigator: { locks, storage: {
			persisted: async () => { calls.storage++; return false; }, persist: async () => true,
		} },
		// Stop after the ownership gate. A real engine/cache is deliberately unnecessary for these shell tests.
		Engine: { getMissingFeatures() { calls.engine++; return ['synthetic test stop']; } },
		GODOT_THREADS_ENABLED: false,
		IdbFs: {
			async readBytes(path) { calls.reads++; return files.get(path); },
			async writeFile(path, bytes) { writes.push(path); files.set(path, bytes); },
		},
	});
	vm.runInContext(source, context, { filename: 'shell.js' });
	await tick();
	return { context, elements, files, writes, calls, state: context.window.mapleShell };
}

test('shell boot blocks a second tab before storage/engine work and retry takes over only after owner exit', async () => {
	const locks = lockService();
	const first = await page(locks);
	const second = await page(locks);
	assert.equal(first.calls.engine, 1);
	assert.equal(second.calls.engine, 0);
	assert.equal(second.calls.storage, 0);
	assert.equal(second.calls.reads, 0);
	assert.match(second.elements.get('error-text').textContent, /already open in another tab/);
	assert.equal(second.elements.get('btn-retry').textContent, 'Try again');
	await vm.runInContext('storeOwnership.release()', first.context);
	await vm.runInContext('boot()', second.context);
	assert.equal(second.calls.engine, 1);
	assert.equal(second.files.get(lib.SAVE_PATH), 'healthy primary');
	assert.equal(second.files.get(lib.SAVE_PATH + '.bak'), 'healthy backup');
	await vm.runInContext('storeOwnership.release()', second.context);
});

test('shell import stages semantically invalid candidates without touching committed saves or claiming promotion', async () => {
	const p = await page(lockService());
	vm.runInContext('startOrImport = async () => { window.restarted = true; }', p.context);
	for (const patch of [{ slots: [{}, null, null] }, { account: { nx: -1 } }, { history: [{}] }]) {
		const text = JSON.stringify({ format: 2, best: {}, runs: {}, slots: [null, null, null], history: [], ...patch });
		p.context.file = { name: 'candidate.json', text: async () => text };
		await vm.runInContext('importSaveFile(file)', p.context);
		assert.equal(p.files.get(lib.SAVE_PATH), 'healthy primary');
		assert.equal(p.files.get(lib.SAVE_PATH + '.bak'), 'healthy backup');
		assert.equal(new TextDecoder().decode(p.files.get(lib.SAVE_PATH + '.import')), text);
		assert.equal(p.state.lastSaveImport.staged, true);
		assert.equal(p.context.window.restarted, true);
		assert.match(p.elements.get('toast').textContent, /^Save staged/);
	}
	assert.deepEqual(p.writes, Array(3).fill(lib.SAVE_PATH + '.import'));
	await vm.runInContext('storeOwnership.release()', p.context);
});

test('shell reports staging failure without restarting or changing committed files', async () => {
	const p = await page(lockService());
	vm.runInContext('startOrImport = async () => { window.restarted = true; }', p.context);
	p.context.file = { name: 'candidate.json', text: async () => '{"format":1,"best":{},"runs":{}}' };
	p.context.IdbFs.writeFile = async () => { throw new Error('quota'); };
	await vm.runInContext('importSaveFile(file)', p.context);
	assert.match(p.elements.get('save-status').textContent, /current save has been kept/);
	assert.equal(p.context.window.restarted, undefined);
	assert.equal(p.files.get(lib.SAVE_PATH), 'healthy primary');
	assert.equal(p.files.get(lib.SAVE_PATH + '.bak'), 'healthy backup');
	await vm.runInContext('storeOwnership.release()', p.context);
});
