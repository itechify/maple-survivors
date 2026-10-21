// The Maple Survivors web shell page logic (spec #130, ADR 0004). See index.html for what the shell is.
//
// Flow: boot -> check the asset cache in IndexedDB (/userfs, the storage behind Godot's user://) against the bundled
// asset_manifest.json -> import screen (folder / zip / web address, run by import_worker.js) or start the engine ->
// when the engine exits, read user://web_request.json and handle the request -> start a NEW Engine.
//
// Rule that keeps saves safe: IndexedDB /userfs is only WRITTEN here while no engine is mounted (before the first start
// and after an exit), because a running engine's next sync would delete records it does not know (docs/ARCHITECTURE.md
// "Web build"). Reading is always fine.
import './idbfs.js';
import * as lib from './lib.js';

const IdbFs = globalThis.IdbFs;
const $ = (id) => document.getElementById(id);
const SHELL_DB = 'maple-shell'; // separate from /userfs: handles and shell state must never live where an engine syncs
const META_KEY = 'maple.source';
const URL_KEY = 'maple.url';

const state = {
	screen: 'boot',
	manifestText: '',
	manifest: null,
	persist: 'checking', // 'persistent' | 'best-effort' | 'unsupported'
	cacheOk: false,
	pending: null, // the source the player picked: {kind, label, ...}
	autoTried: false,
	lastImport: null,
	lastExit: null,
	events: [],
	engineRunning: false,
	toldStorage: false, // the storage result toast was shown (once per page load)
	persistReady: null, // promise of the boot-time storage state read (never waits on the persist() prompt), set at boot
};
// For browser automation and bug reports (read-only by convention).
window.mapleShell = state;

function note(text) {
	state.events.push(text);
	console.log('[shell] ' + text);
}

// ---- Screens ----------------------------------------------------------------------------------------------------------

function setScreen(name, subtitle) {
	state.screen = name;
	$('plate').dataset.screen = name;
	$('shell').hidden = false;
	for (const el of document.querySelectorAll('[data-screens]')) {
		el.hidden = !el.dataset.screens.split(' ').includes(name);
	}
	$('btn-back').hidden = $('btn-back').hidden || !state.cacheOk;
	if (subtitle) $('subtitle').textContent = subtitle;
}

function hideShell() {
	$('shell').hidden = true;
}

function showError(message, back) {
	$('error-text').textContent = message;
	state.errorBack = back || (() => showImport());
	setScreen('error', 'Something went wrong');
	note('error: ' + message);
}

function toast(text) {
	const t = $('toast');
	t.textContent = text;
	t.hidden = false;
	clearTimeout(toast.timer);
	toast.timer = setTimeout(() => { t.hidden = true; }, 5000);
}

function logTo(id, line) {
	const el = $(id);
	el.textContent += line + '\n';
	el.scrollTop = el.scrollHeight;
}

function setStatus(text, kind, detail) {
	const el = $('pick-status');
	el.textContent = text;
	el.className = 'status' + (kind ? ' ' + kind : '');
	$('pick-detail').textContent = detail || '';
}

// ---- Storage persistence ------------------------------------------------------------------------------------------------

// The footer shows the current state at once; the browser's permission prompt (Firefox) is answered in the background
// and a grant only upgrades the line. Nothing here waits on it (lib.createPersistence).
const persistence = lib.createPersistence({
	storage: navigator.storage,
	onChange(snapshot) {
		state.persist = snapshot.persist;
		const status = lib.storageStatus(snapshot);
		const line = $('storage-line');
		line.textContent = status.text;
		line.className = 'storage ' + (status.good ? 'good' : 'warn');
		note('persist: ' + state.persist);
	},
});

/** Reads the storage state, shows it, and asks for persistence in the background. Resolves without the prompt. */
function requestPersistence() {
	return persistence.request();
}

// ---- Remembered source ----------------------------------------------------------------------------------------------------

function readMeta() {
	try {
		return JSON.parse(localStorage.getItem(META_KEY)) || null;
	} catch (e) {
		return null;
	}
}

function writeMeta(meta) {
	try {
		localStorage.setItem(META_KEY, JSON.stringify(meta));
	} catch (e) {
		/* storage disabled */
	}
}

function shellDb() {
	return new Promise((resolve, reject) => {
		const req = indexedDB.open(SHELL_DB, 1);
		req.onupgradeneeded = () => req.result.createObjectStore('handles');
		req.onsuccess = () => resolve(req.result);
		req.onerror = () => reject(req.error);
	});
}

async function storeHandle(handle) {
	try {
		const db = await shellDb();
		await new Promise((resolve, reject) => {
			const tx = db.transaction('handles', 'readwrite');
			if (handle) tx.objectStore('handles').put(handle, 'wz-folder');
			else tx.objectStore('handles').delete('wz-folder');
			tx.oncomplete = resolve;
			tx.onerror = () => reject(tx.error);
		});
		db.close();
	} catch (e) {
		note('could not store the folder handle: ' + e);
	}
}

async function loadHandle() {
	try {
		const db = await shellDb();
		const handle = await new Promise((resolve, reject) => {
			const req = db.transaction('handles').objectStore('handles').get('wz-folder');
			req.onsuccess = () => resolve(req.result || null);
			req.onerror = () => reject(req.error);
		});
		db.close();
		return handle;
	} catch (e) {
		return null;
	}
}

// ---- Cache check --------------------------------------------------------------------------------------------------------

async function assessStoredCache() {
	const indexText = await IdbFs.readText(lib.CACHE_ROOT + '/cache.json');
	const keys = indexText === null ? null : await IdbFs.listPaths(lib.CACHE_ROOT + '/');
	const result = lib.assessCache({ manifest: state.manifest, indexText, keys });
	note(`cache: ${result.state}${result.missing.length ? ' (' + result.missing.length + ' missing)' : ''}`);
	return result;
}

// ---- Choosing a source ----------------------------------------------------------------------------------------------------

function selectTab(name) {
	for (const b of document.querySelectorAll('.tabs button')) b.setAttribute('aria-selected', String(b.dataset.tab === name));
	for (const p of document.querySelectorAll('.pane')) p.hidden = p.dataset.pane !== name;
	state.tab = name;
	state.pending = null;
	$('btn-import').disabled = true;
	setStatus('');
}

function setPending(pending) {
	state.pending = pending;
	$('btn-import').disabled = !pending;
}

async function acceptFolderEntries(entries, label, handle) {
	const required = lib.requiredArchives(state.manifest);
	const picked = lib.pickArchiveFolder(entries, required);
	setPending(null);
	if (!Object.keys(picked.found).length) {
		setStatus('No .wz files here. Pick the folder that holds Map.wz, Mob.wz, Character.wz ...', 'bad');
		return;
	}
	if (picked.missing.length) {
		setStatus('Missing: ' + picked.missing.join(', '), 'bad');
		return;
	}
	const files = {};
	let total = 0;
	for (const name of required) {
		const e = picked.found[name];
		const file = e.file || (await e.handle.getFile());
		files[name] = file;
		total += file.size;
	}
	setPending({ kind: 'folder', label, files, total, handle });
	setStatus(`All ${required.length} .wz files found (${lib.formatBytes(total)}).`, 'good');
}

async function chooseFolder() {
	if (window.showDirectoryPicker) {
		let handle;
		try {
			handle = await window.showDirectoryPicker({ id: 'maple-v83', mode: 'read' });
		} catch (e) {
			if (e && e.name === 'AbortError') return;
			note('showDirectoryPicker failed, using the input: ' + e);
			$('input-folder').click();
			return;
		}
		await acceptHandle(handle);
	} else {
		$('input-folder').click();
	}
}

async function entriesFromHandle(dir) {
	const entries = [];
	async function scan(h, prefix, depth) {
		for await (const [name, child] of h.entries()) {
			if (child.kind === 'file') {
				if (/\.wz$/i.test(name)) entries.push({ path: prefix + name, handle: child });
			} else if (depth < 1) {
				await scan(child, prefix + name + '/', depth + 1);
			}
		}
	}
	await scan(dir, '', 0);
	return entries;
}

async function acceptHandle(handle) {
	try {
		await acceptFolderEntries(await entriesFromHandle(handle), handle.name, handle);
	} catch (e) {
		setStatus('Could not read that folder: ' + (e && e.message ? e.message : e), 'bad');
	}
}

function acceptInputFolder(fileList) {
	const files = Array.from(fileList);
	if (!files.length) return;
	const entries = files.filter((f) => /\.wz$/i.test(f.name)).map((f) => ({ path: f.webkitRelativePath || f.name, file: f }));
	const label = (files[0].webkitRelativePath || '').split('/')[0] || 'folder';
	return acceptFolderEntries(entries, label, null);
}

function acceptZip(file) {
	if (!file) return;
	if (!/\.zip$/i.test(file.name)) {
		setStatus(`${file.name} is not a .zip file.`, 'bad');
		setPending(null);
		return;
	}
	selectTab('zip');
	setPending({ kind: 'zip', label: file.name, file, total: file.size });
	setStatus(`${file.name} (${lib.formatBytes(file.size)}). Ready to import.`, 'good');
}

async function checkUrl() {
	const parsed = lib.parseSourceUrl($('input-url').value);
	setPending(null);
	if (!parsed.ok) {
		setStatus(parsed.error, 'bad');
		return;
	}
	setStatus(`Asking ${parsed.host} for the file sizes...`);
	$('btn-check').disabled = true;
	try {
		const probe = await callWorker({ type: 'probe', parsed, manifestText: state.manifestText });
		const wholeBytes = probe.files.filter((f) => !f.ranged).reduce((a, f) => a + f.size, 0);
		const how = probe.allRanged
			? 'The host supports partial downloads, so only the parts the game needs are fetched (usually a fraction of this).'
			: `The host does not support partial downloads, so ${lib.formatBytes(wholeBytes)} is downloaded in full and kept in the browser only until the import ends.`;
		setPending({ kind: 'url', label: parsed.url, parsed, probe, total: probe.total });
		setStatus(`${probe.files.length} file${probe.files.length === 1 ? '' : 's'} found, ${lib.formatBytes(probe.total)} in total.`, 'good',
			`${how} The download comes straight from ${probe.host}, the host you named.`);
		try {
			localStorage.setItem(URL_KEY, parsed.url);
		} catch (e) {
			/* storage disabled */
		}
	} catch (e) {
		setStatus(e.message, 'bad');
		note(`probe failed (${e.code}): ${e.message}`);
	} finally {
		$('btn-check').disabled = false;
	}
}

// ---- Worker ---------------------------------------------------------------------------------------------------------------

let activeCall = null;

function callWorker(message, onProgress) {
	return new Promise((resolve, reject) => {
		let worker;
		try {
			worker = new Worker('import_worker.js', { type: 'module' });
		} catch (e) {
			reject(Object.assign(new Error('This browser cannot run the importer (module workers are missing).'), { code: 'worker' }));
			return;
		}
		const id = Math.floor(Math.random() * 1e9);
		const finish = (fn, value) => {
			worker.terminate();
			activeCall = null;
			fn(value);
		};
		activeCall = { cancel: () => finish(reject, Object.assign(new Error('Cancelled.'), { code: 'cancelled' })) };
		worker.onmessage = (ev) => {
			const m = ev.data;
			if (m.type === 'ready') {
				worker.postMessage(Object.assign({ id }, message));
			} else if (m.id !== id) {
				/* a stale message */
			} else if (m.type === 'progress') {
				if (onProgress) onProgress(m);
			} else if (m.type === 'probed') {
				finish(resolve, m.result);
			} else if (m.type === 'done') {
				finish(resolve, m);
			} else if (m.type === 'error') {
				finish(reject, Object.assign(new Error(m.message), { code: m.code }));
			}
		};
		worker.onerror = (ev) => {
			finish(reject, Object.assign(new Error('The importer could not start' + (ev.message ? ': ' + ev.message : '')
				+ '. wzimport.js and wzimport_bg.wasm must sit next to index.html.'), { code: 'worker' }));
		};
	});
}

// ---- Import -------------------------------------------------------------------------------------------------------------

function workerSource(pending) {
	if (pending.kind === 'folder') return { kind: 'folder', files: pending.files };
	if (pending.kind === 'zip') return { kind: 'zip', file: pending.file };
	return { kind: 'url', probe: pending.probe };
}

function describeProgress(m) {
	const bar = $('run-bar');
	const detail = $('run-detail');
	if (m.phase === 'download') {
		$('run-title').textContent = 'Downloading...';
		bar.max = m.total || 1;
		bar.value = m.done || 0;
		detail.textContent = `${m.text} ${lib.formatBytes(m.done || 0)} of ${lib.formatBytes(m.total || 0)}`;
	} else if (m.phase === 'import') {
		$('run-title').textContent = 'Importing...';
		if (m.total) {
			bar.max = m.total;
			bar.value = m.done;
			detail.textContent = `Image ${m.done} of ${m.total}: ${m.text}`;
		} else {
			bar.removeAttribute('value');
			detail.textContent = m.text;
		}
	} else if (m.phase === 'write') {
		$('run-title').textContent = 'Saving...';
		bar.max = m.total || 1;
		bar.value = m.done || 0;
		detail.textContent = `${m.text} ${m.done || 0} of ${m.total || 0} files`;
	} else {
		bar.removeAttribute('value');
		detail.textContent = m.text || '';
	}
}

async function runImport(pending, options = {}) {
	$('run-log').textContent = '';
	$('run-bar').removeAttribute('value');
	$('run-detail').textContent = '';
	$('run-title').textContent = options.title || 'Importing...';
	setScreen('running', 'Importing your MapleStory v83 data');
	logTo('run-log', `Source: ${pending.kind} ${pending.label}${pending.total ? ' (' + lib.formatBytes(pending.total) + ')' : ''}`);
	if (options.reason) logTo('run-log', options.reason);
	const started = performance.now();
	try {
		const result = await callWorker({ type: 'import', source: workerSource(pending), manifestText: state.manifestText }, describeProgress);
		state.lastImport = Object.assign({ source: pending.kind, wallMs: performance.now() - started }, result);
		const t = result.timing;
		logTo('run-log', `Imported ${result.imgs} images (${result.files} files, ${lib.formatBytes(result.bytes)}) in ${(t.totalMs / 1000).toFixed(1)} s: `
			+ `read ${(t.importMs / 1000).toFixed(1)} s, saved ${(t.writeMs / 1000).toFixed(1)} s.`);
		if (result.io.httpRequests) {
			logTo('run-log', `${result.io.httpRequests} requests, ${lib.formatBytes(result.io.httpBytes)} downloaded.`);
		}
		if (result.warningCount) logTo('run-log', `${result.warningCount} warnings (first: ${result.warnings[0]})`);
		writeMeta({ kind: pending.kind, label: pending.label, url: pending.kind === 'url' ? pending.parsed.url : undefined,
			hasHandle: !!pending.handle, at: new Date().toISOString() });
		if (pending.kind === 'folder') await storeHandle(pending.handle || null);
		requestPersistence();
		note(`import done (${pending.kind}) in ${Math.round(t.totalMs)} ms`);
		$('run-title').textContent = 'Import complete';
		$('run-bar').max = 1;
		$('run-bar').value = 1;
		$('run-detail').textContent = 'Starting the game...';
		await new Promise((r) => setTimeout(r, 600));
		await startOrImport({ afterImport: true });
	} catch (e) {
		if (e.code === 'cancelled') {
			note('import cancelled');
			await showImport();
			return;
		}
		note(`import failed (${e.code}): ${e.message}`);
		await showImport({ error: `The import failed: ${e.message}` });
	}
}

// ---- Import screen ---------------------------------------------------------------------------------------------------------

async function showImport(options = {}) {
	const meta = readMeta();
	const handle = await loadHandle();
	state.cacheOk = !!options.cacheOk;
	$('btn-back').hidden = !state.cacheOk;
	const notice = $('notice');
	notice.className = 'notice' + (options.error ? ' bad' : '');
	notice.textContent = options.error || options.notice || '';
	notice.hidden = !notice.textContent;
	$('btn-reuse').hidden = true;
	if (handle && meta && meta.kind === 'folder') {
		$('btn-reuse').textContent = `Use "${handle.name}" again`;
		$('btn-reuse').hidden = false;
		state.storedHandle = handle;
	}
	let url = '';
	try {
		url = localStorage.getItem(URL_KEY) || '';
	} catch (e) {
		/* storage disabled */
	}
	if (url && !$('input-url').value) $('input-url').value = url;
	selectTab(options.tab || (meta && ['folder', 'zip', 'url'].includes(meta.kind) ? meta.kind : 'folder'));
	setScreen('import', 'Import your MapleStory v83 data');
	if (options.error) setStatus('');
}

async function reuseStoredFolder() {
	const handle = state.storedHandle;
	if (!handle) return;
	try {
		let permission = handle.queryPermission ? await handle.queryPermission({ mode: 'read' }) : 'granted';
		if (permission !== 'granted' && handle.requestPermission) permission = await handle.requestPermission({ mode: 'read' });
		if (permission !== 'granted') {
			setStatus('Permission to read that folder was not given.', 'bad');
			return;
		}
	} catch (e) {
		setStatus('Could not reopen that folder: ' + e, 'bad');
		return;
	}
	selectTab('folder');
	await acceptHandle(handle);
	if (state.pending) await runImport(state.pending, { reason: 'Re-reading your saved folder.' });
}

// ---- Engine lifecycle ---------------------------------------------------------------------------------------------------------

let session = 0;
let engineSession = 0;
let exitHandled = true;

function userArgs() {
	const list = new URLSearchParams(window.location.search).getAll('arg');
	return list.length ? ['--'].concat(list) : [];
}

function godotStatus() {
	return {
		overlay: $('status'), progress: $('status-progress'), notice: $('status-notice'),
	};
}

function startEngine() {
	const mine = ++session;
	engineSession = mine;
	exitHandled = false;
	state.engineRunning = true;
	hideShell();
	const g = godotStatus();
	g.overlay.style.visibility = 'visible';
	g.progress.style.display = 'block';
	g.progress.removeAttribute('value');
	g.notice.style.display = 'none';
	// A fresh canvas per engine: the previous engine's WebGL context belongs to the old one.
	const old = $('canvas');
	const fresh = old.cloneNode(false);
	old.replaceWith(fresh);
	const engine = new Engine(GODOT_CONFIG);
	window.godotEngine = engine;
	window.godotExitCode = null;
	note('engine start');
	if (!state.toldStorage) {
		// The persistence request's result, once per page load, unobtrusively.
		state.toldStorage = true;
		Promise.resolve(state.persistReady).then(() => toast($('storage-line').textContent));
	}
	engine.startGame({
		args: userArgs(),
		onProgress(current, total) {
			if (current > 0 && total > 0) {
				g.progress.value = current;
				g.progress.max = total;
			}
		},
		onExit(code) {
			afterExit(mine, 'onExit', code);
		},
	}).then(() => {
		if (mine === session) g.overlay.style.visibility = 'hidden';
	}, (err) => {
		if (mine !== session) return;
		console.error(err);
		state.engineRunning = false;
		showError(err instanceof Error ? err.message : String(err), () => startOrImport());
		g.overlay.style.visibility = 'hidden';
	});
}

// Godot 4.7.2's web teardown throws a TypeError on a closed AudioContext when a sample is still playing, and onExit
// never fires (spike #131). The final IndexedDB sync has already run by then, so the exit is handled from the error.
function onPageError(message) {
	if (state.engineRunning && lib.isAudioTeardownError(message)) afterExit(engineSession, 'audio teardown error', null);
}
window.addEventListener('error', (ev) => onPageError(ev.message || (ev.error && ev.error.message)));
window.addEventListener('unhandledrejection', (ev) => onPageError(ev.reason && ev.reason.message ? ev.reason.message : ev.reason));

async function afterExit(mine, how, code) {
	if (mine !== engineSession || exitHandled) return;
	exitHandled = true;
	state.engineRunning = false;
	window.godotExitCode = code;
	state.lastExit = { how, code };
	note(`engine exit (${how})`);
	godotStatus().overlay.style.visibility = 'hidden';
	try {
		await handleRequest();
	} catch (e) {
		showError('The game quit and the shell could not read its request: ' + (e && e.message ? e.message : e), () => startOrImport());
	}
}

async function handleRequest() {
	const raw = await IdbFs.readText(lib.MARKER_PATH);
	if (raw === null) {
		showExited('The game has quit.');
		return;
	}
	await IdbFs.remove(lib.MARKER_PATH);
	const marker = lib.parseMarker(raw);
	state.lastExit.request = marker.ok ? marker.kind : null;
	if (!marker.ok) {
		note('ignored request marker: ' + marker.error);
		showExited('The game has quit.');
		return;
	}
	note('request: ' + marker.kind);
	if (marker.kind === 'reimport') {
		await showImport({ cacheOk: true, notice: 'Choose your data again to import it a second time. The game keeps using the current data until the new import has finished.' });
	} else if (marker.kind === 'export_save') {
		await exportSave();
	} else if (marker.kind === 'import_save') {
		showSaveImport();
	}
}

function showExited(text) {
	$('exited-text').textContent = text;
	setScreen('exited', 'See you next time');
}

// ---- Save backup ---------------------------------------------------------------------------------------------------------------

async function exportSave() {
	const bytes = await IdbFs.readBytes(lib.SAVE_PATH);
	if (!bytes) {
		toast('There is no save to export yet.');
		await startOrImport();
		return;
	}
	const name = lib.saveFileName(new Date());
	const url = URL.createObjectURL(new Blob([bytes], { type: 'application/json' }));
	const a = document.createElement('a');
	a.href = url;
	a.download = name;
	document.body.appendChild(a);
	a.click();
	a.remove();
	setTimeout(() => URL.revokeObjectURL(url), 60000);
	state.lastSaveExport = { name, bytes: bytes.length };
	note('save exported: ' + name);
	toast('Save exported as ' + name);
	await startOrImport();
}

function showSaveImport() {
	$('save-status').textContent = '';
	$('save-status').className = 'status';
	state.cacheOk = true;
	$('btn-back').hidden = false;
	setScreen('saveimport', 'Import a save');
}

async function importSaveFile(file) {
	const status = $('save-status');
	const fail = (text) => {
		status.textContent = text;
		status.className = 'status bad';
	};
	if (!file) return;
	let text;
	try {
		text = await file.text();
	} catch (e) {
		fail('Could not read that file.');
		return;
	}
	let check;
	try {
		check = await lib.stageSaveImport(text, (path, bytes) => IdbFs.writeFile(path, bytes));
	} catch (e) {
		fail('Could not stage that save. Your current save has been kept.');
		return;
	}
	if (!check.ok) {
		fail(check.error);
		note('save import refused: ' + check.error);
		return;
	}
	state.lastSaveImport = { name: file.name, slots: check.slots, staged: true };
	note(`save staged: ${file.name}`);
	toast('Save staged. The game will check it before replacing your current save.');
	await startOrImport();
}

// ---- Start / re-import decision ---------------------------------------------------------------------------------------------

async function startOrImport(options = {}) {
	const assessed = await assessStoredCache();
	if (assessed.state === 'ok') {
		state.cacheOk = true;
		startEngine();
		return;
	}
	state.cacheOk = false;
	if (options.afterImport) {
		await showImport({ error: 'The import finished but the saved data is still incomplete'
			+ (assessed.missing.length ? ` (missing ${assessed.missing[0].img}).` : '.') });
		return;
	}
	const meta = readMeta();
	if (assessed.state === 'incomplete') {
		const sample = assessed.missing.slice(0, 3).map((m) => m.img).join(', ');
		const why = `${assessed.missing.length} image${assessed.missing.length === 1 ? ' is' : 's are'} missing from your saved data (${sample}${assessed.missing.length > 3 ? ', ...' : ''}).`;
		if (meta && meta.kind === 'url' && meta.url && !state.autoTried) {
			state.autoTried = true;
			await autoReimport(meta.url, why);
			return;
		}
		const again = meta && meta.kind === 'zip' ? 'Choose your zip file again to repair it.'
			: meta && meta.kind === 'url' ? 'Check the web address again to repair it.' : 'Choose your folder again to repair it.';
		await showImport({ notice: `${why} ${again}`, tab: meta ? meta.kind : undefined });
		return;
	}
	if (assessed.state === 'invalid') {
		await showImport({ notice: `Your saved data could not be used (${assessed.reason}). Import it again.` });
		return;
	}
	await showImport({});
}

async function autoReimport(url, why) {
	setScreen('running', 'Repairing your saved data');
	$('run-log').textContent = '';
	$('run-title').textContent = 'Re-importing...';
	$('run-bar').removeAttribute('value');
	$('run-detail').textContent = '';
	logTo('run-log', why);
	const parsed = lib.parseSourceUrl(url);
	logTo('run-log', `Importing again, automatically, from the address you used before (${parsed.ok ? parsed.host : url}).`);
	try {
		const probe = await callWorker({ type: 'probe', parsed, manifestText: state.manifestText });
		await runImport({ kind: 'url', label: parsed.url, parsed, probe, total: probe.total }, {
			title: 'Re-importing...',
			reason: `${why}\nImporting again, automatically, from the address you used before (${parsed.host}).`,
		});
	} catch (e) {
		if (e.code === 'cancelled') {
			await showImport({ tab: 'url' });
			return;
		}
		$('input-url').value = url;
		await showImport({ error: `${why} Re-importing from the saved address failed: ${e.message}`, tab: 'url' });
	}
}

// ---- Wiring ---------------------------------------------------------------------------------------------------------------------

function wire() {
	for (const b of document.querySelectorAll('.tabs button')) b.addEventListener('click', () => selectTab(b.dataset.tab));
	$('btn-folder').addEventListener('click', chooseFolder);
	$('btn-reuse').addEventListener('click', reuseStoredFolder);
	$('input-folder').addEventListener('change', async (ev) => {
		await acceptInputFolder(ev.target.files);
		ev.target.value = '';
	});
	$('btn-zip').addEventListener('click', () => $('input-zip').click());
	$('input-zip').addEventListener('change', (ev) => {
		acceptZip(ev.target.files[0]);
		ev.target.value = '';
	});
	$('btn-check').addEventListener('click', checkUrl);
	$('input-url').addEventListener('keydown', (ev) => {
		if (ev.key === 'Enter') checkUrl();
	});
	$('input-url').addEventListener('input', () => {
		if (state.pending && state.pending.kind === 'url') setPending(null);
	});
	$('btn-import').addEventListener('click', () => {
		if (state.pending) runImport(state.pending);
	});
	$('btn-cancel').addEventListener('click', () => {
		if (activeCall) activeCall.cancel();
	});
	$('btn-back').addEventListener('click', () => startOrImport());
	$('btn-again').addEventListener('click', () => startOrImport());
	$('btn-retry').addEventListener('click', () => {
		const back = state.errorBack;
		if (back) back();
	});
	$('btn-save-file').addEventListener('click', () => $('input-save').click());
	$('input-save').addEventListener('change', async (ev) => {
		const file = ev.target.files[0];
		ev.target.value = '';
		await importSaveFile(file);
	});

	// Drag and drop: a .zip, or (where the browser can give a directory handle) a folder.
	let dragDepth = 0;
	const overImport = () => state.screen === 'import';
	window.addEventListener('dragenter', (ev) => {
		if (!overImport()) return;
		ev.preventDefault();
		dragDepth++;
		$('drop-hint').hidden = false;
	});
	window.addEventListener('dragover', (ev) => {
		if (overImport()) ev.preventDefault();
	});
	window.addEventListener('dragleave', () => {
		if (!overImport()) return;
		dragDepth = Math.max(0, dragDepth - 1);
		if (!dragDepth) $('drop-hint').hidden = true;
	});
	window.addEventListener('drop', async (ev) => {
		if (!overImport()) return;
		ev.preventDefault();
		dragDepth = 0;
		$('drop-hint').hidden = true;
		const item = ev.dataTransfer.items && ev.dataTransfer.items[0];
		if (item && item.getAsFileSystemHandle) {
			const handle = await item.getAsFileSystemHandle();
			if (handle && handle.kind === 'directory') {
				selectTab('folder');
				await acceptHandle(handle);
				return;
			}
		}
		const file = ev.dataTransfer.files[0];
		if (file) acceptZip(file);
	});
}

const storeOwnership = lib.createStoreOwnership(navigator.locks);

async function boot() {
	setScreen('boot', 'Maple Survivors');
	try {
		if (!await storeOwnership.acquire()) {
			showError('Maple Survivors is already open in another tab. Close that tab, then choose Try again to play here.', () => boot());
			$('btn-retry').textContent = 'Try again';
			return;
		}
	} catch (e) {
		showError(e.message, () => boot());
		return;
	}
	$('btn-retry').textContent = 'Back';
	state.persistReady = requestPersistence();
	const missing = Engine.getMissingFeatures({ threads: GODOT_THREADS_ENABLED });
	if (missing.length) {
		showError('This browser lacks features the game needs:\n' + missing.join('\n'), () => location.reload());
		return;
	}
	try {
		const res = await fetch('asset_manifest.json', { cache: 'no-store' });
		if (!res.ok) throw new Error(`HTTP ${res.status}`);
		state.manifestText = await res.text();
		state.manifest = lib.parseManifest(state.manifestText);
	} catch (e) {
		showError('Could not load asset_manifest.json from this site: ' + (e && e.message ? e.message : e), () => location.reload());
		return;
	}
	await startOrImport();
}

wire();
boot().catch((e) => {
	console.error(e);
	showError(String(e && e.message ? e.message : e), () => location.reload());
});
