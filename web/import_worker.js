// The import worker of the web shell (spec #130, ADR 0004, docs/ASSET_PIPELINE.md 2.2).
//
// It runs the wasm importer (wzimport.js, built by scripts/build_wasm.sh) against the player's own v83 data and writes
// the resulting asset cache straight into the IndexedDB database behind Godot's /userfs (idbfs.js), so it is there
// when the engine starts. Three kinds of source, one per import:
//   folder  {kind:'folder', files: {'Mob.wz': File, ...}}   Blob readers (FileReaderSync)
//   zip     {kind:'zip', file: File}                        Blob reader (no scratch: docs/ASSET_PIPELINE.md 2.3)
//   url     {kind:'url', parsed, probe}                     sync XHR with Range behind a block cache, or a whole-file
//                                                           download into a Blob when the host has no range support
// The page talks to it with messages: {type:'probe', id, parsed, manifestText} and {type:'import', id, source,
// manifestText}; it answers {type:'probed'|'progress'|'done'|'error', id, ...}. The worker never runs while a game
// engine is mounted: the page only starts an import before an engine starts or after it has exited.
//
// Network use is limited to the import source the player named (probe and ranged reads). Nothing else is requested.
import './idbfs.js';
import init, { importWz } from './wzimport.js';
import * as lib from './lib.js';

const IdbFs = globalThis.IdbFs;

let wasmReady = null;
function ensureWasm() {
	if (!wasmReady) wasmReady = init();
	return wasmReady;
}

function fail(code, message) {
	return Object.assign(new Error(message), { code });
}

function describe(e) {
	if (typeof e === 'string') return e;
	return e && e.message ? e.message : String(e);
}

// ---- URL probing (async, before the player confirms) ---------------------------------------------------------------

// Tells a CORS refusal from an unreachable host: a no-cors request succeeds (opaque) when something answers at all.
async function explainFetchFailure(url, error) {
	try {
		const ctl = new AbortController();
		const res = await fetch(url, { method: 'HEAD', mode: 'no-cors', cache: 'no-store', signal: ctl.signal });
		ctl.abort();
		if (res) {
			return fail('cors', `The host answered, but it does not allow this page to read its files (CORS): ${new URL(url).host} would have to send `
				+ 'an Access-Control-Allow-Origin header. Download the files and import them as a folder or a zip instead.');
		}
	} catch (e) {
		/* unreachable */
	}
	return fail('network', `Could not reach ${new URL(url).host}. Check the address and your connection (${describe(error)}).`);
}

async function probeOne(url) {
	let res;
	try {
		res = await fetch(url, { headers: { Range: 'bytes=0-0' }, cache: 'no-store' });
	} catch (e) {
		throw await explainFetchFailure(url, e);
	}
	const name = decodeURIComponent(new URL(url).pathname.split('/').pop());
	if (res.status === 404 || res.status === 410) {
		if (res.body) res.body.cancel();
		throw fail('notfound', `${name} was not found at that address.`);
	}
	if (res.status !== 200 && res.status !== 206) {
		if (res.body) res.body.cancel();
		throw fail('http', `${name}: the host answered HTTP ${res.status}.`);
	}
	const ranged = res.status === 206;
	let size = NaN;
	if (ranged) {
		const m = /\/(\d+)\s*$/.exec(res.headers.get('Content-Range') || '');
		if (m) size = Number(m[1]);
	} else {
		size = Number(res.headers.get('Content-Length'));
	}
	if (res.body) res.body.cancel();
	if (!Number.isFinite(size) || size <= 0) {
		// Cross-origin hosts only show Content-Length unless they expose Content-Range; ask for the length.
		try {
			const head = await fetch(url, { method: 'HEAD', cache: 'no-store' });
			size = Number(head.headers.get('Content-Length'));
		} catch (e) {
			/* handled below */
		}
	}
	if (!Number.isFinite(size) || size <= 0) {
		throw fail('size', `Could not read the size of ${name}. The host would have to send Content-Length or expose Content-Range.`);
	}
	return { url, name, size, ranged };
}

async function probe(parsed, manifestText) {
	const manifest = lib.parseManifest(manifestText);
	let targets;
	if (parsed.kind === 'zip') {
		targets = [parsed.url];
	} else {
		targets = lib.requiredArchives(manifest).map((n) => lib.archiveUrl(parsed.base, n));
	}
	const results = await Promise.allSettled(targets.map(probeOne));
	const rejected = results.filter((r) => r.status === 'rejected').map((r) => r.reason);
	if (rejected.length) {
		// One clear message: a CORS or network failure outranks per-file problems.
		const first = rejected.find((e) => e.code === 'cors') || rejected.find((e) => e.code === 'network') || rejected[0];
		if (first.code === 'notfound' && rejected.length > 1) {
			throw fail('notfound', 'These files were not found at that address: '
				+ rejected.map((e) => e.message.replace(/ was not found.*/, '')).join(', ') + '.');
		}
		throw first;
	}
	const files = results.map((r) => r.value);
	return {
		kind: parsed.kind,
		host: parsed.host,
		files,
		total: files.reduce((a, f) => a + f.size, 0),
		allRanged: files.every((f) => f.ranged),
	};
}

// ---- Readers ----------------------------------------------------------------------------------------------------------

function blobReader(blob, stats) {
	const sync = new FileReaderSync();
	return {
		length: blob.size,
		readAt(offset, length) {
			stats.reads++;
			stats.bytes += length;
			return new Uint8Array(sync.readAsArrayBuffer(blob.slice(offset, offset + length)));
		},
	};
}

function xhrRange(url, start, endExclusive) {
	const x = new XMLHttpRequest();
	x.open('GET', url, false);
	x.responseType = 'arraybuffer';
	x.setRequestHeader('Range', `bytes=${start}-${endExclusive - 1}`);
	try {
		x.send();
	} catch (e) {
		throw new Error(`request to ${new URL(url).host} failed (${describe(e)})`);
	}
	if (x.status === 200) {
		throw new Error(`${new URL(url).host} stopped honouring range requests for ${decodeURIComponent(new URL(url).pathname.split('/').pop())}`);
	}
	if (x.status !== 206) throw new Error(`HTTP ${x.status} for bytes ${start}-${endExclusive - 1}`);
	return new Uint8Array(x.response);
}

function urlReader(url, size, stats) {
	const reader = lib.createBlockReader({ length: size, fetchRange: (s, e) => xhrRange(url, s, e) });
	stats.readers.push(reader.stats);
	return reader;
}

// Downloads a whole file into a Blob (the browser may keep it on disk), reporting bytes as they arrive.
async function downloadToBlob(url, size, onBytes) {
	let res;
	try {
		res = await fetch(url, { cache: 'no-store' });
	} catch (e) {
		throw await explainFetchFailure(url, e);
	}
	if (!res.ok) throw fail('http', `HTTP ${res.status} while downloading ${new URL(url).pathname}`);
	const chunks = [];
	let got = 0;
	const reader = res.body.getReader();
	for (;;) {
		const { done, value } = await reader.read();
		if (done) break;
		chunks.push(value);
		got += value.length;
		onBytes(value.length);
	}
	if (got !== size) throw fail('size', `Downloaded ${got} bytes of ${new URL(url).pathname} but the host said ${size}.`);
	return new Blob(chunks);
}

// ---- The import -------------------------------------------------------------------------------------------------------

async function runImport(id, source, manifestText) {
	const post = (msg) => self.postMessage(Object.assign({ id }, msg));
	const t0 = performance.now();
	const manifest = lib.parseManifest(manifestText);
	const stats = { reads: 0, bytes: 0, readers: [] };
	const timing = {};
	try {
		await ensureWasm();
		post({ type: 'progress', phase: 'prepare', text: 'Preparing the importer...' });
		let sources;
		if (source.kind === 'folder') {
			const archives = {};
			for (const name of lib.requiredArchives(manifest)) {
				const file = source.files[name];
				if (!file) throw fail('missing', `${name} is not in the folder you chose.`);
				archives[name] = blobReader(file, stats);
			}
			sources = { archives };
		} else if (source.kind === 'zip') {
			sources = { zip: blobReader(source.file, stats) };
		} else if (source.kind === 'url') {
			const files = source.probe.files;
			const readers = {};
			let downloaded = 0;
			const wholeFiles = files.filter((f) => !f.ranged);
			const wholeTotal = wholeFiles.reduce((a, f) => a + f.size, 0);
			for (const f of files) {
				if (f.ranged) {
					readers[f.name] = urlReader(f.url, f.size, stats);
				} else {
					post({ type: 'progress', phase: 'download', text: `Downloading ${f.name}...`, done: downloaded, total: wholeTotal });
					const blob = await downloadToBlob(f.url, f.size, (n) => {
						downloaded += n;
						post({ type: 'progress', phase: 'download', text: `Downloading ${f.name}...`, done: downloaded, total: wholeTotal });
					});
					readers[f.name] = blobReader(blob, stats);
				}
			}
			if (source.probe.kind === 'zip') sources = { zip: readers[files[0].name] };
			else sources = { archives: readers };
		} else {
			throw fail('source', `unknown source kind ${source.kind}`);
		}
		timing.prepareMs = performance.now() - t0;

		// Importing is synchronous: the sink only queues, and everything is written after importWz returns.
		const queue = [];
		const dirs = new Set();
		let queuedBytes = 0;
		const sink = {
			createDir(rel) {
				dirs.add(rel);
			},
			writeFile(rel, bytes) {
				queue.push({ rel, bytes });
				queuedBytes += bytes.length;
			},
		};
		const t1 = performance.now();
		post({ type: 'progress', phase: 'import', text: 'Reading the data...', done: 0, total: 0 });
		const reportText = importWz(sources, manifestText, sink, (img, done, total) => {
			post({ type: 'progress', phase: 'import', text: img, done, total });
		});
		timing.importMs = performance.now() - t1;
		const report = JSON.parse(reportText);

		// Write phase: no engine is mounted, so the records go straight into IndexedDB. cache.json goes last and the old
		// cache is removed first, so an interrupted write leaves no cache.json and the shell treats it as "no cache".
		const t2 = performance.now();
		post({ type: 'progress', phase: 'write', text: 'Saving to browser storage...', done: 0, total: queue.length });
		await IdbFs.deletePrefix(lib.CACHE_ROOT);
		await IdbFs.writeDirs(Array.from(dirs).map((d) => (d ? `${lib.CACHE_ROOT}/${d}` : lib.CACHE_ROOT)));
		const indexEntry = queue.find((q) => q.rel === 'cache.json');
		const files = queue.filter((q) => q.rel !== 'cache.json').map((q) => ({ path: `${lib.CACHE_ROOT}/${q.rel}`, data: q.bytes }));
		await IdbFs.writeFiles(files, (n, total) => post({ type: 'progress', phase: 'write', text: 'Saving to browser storage...', done: n, total }));
		if (!indexEntry) throw fail('importer', 'The importer produced no cache.json.');
		await IdbFs.writeFile(`${lib.CACHE_ROOT}/cache.json`, indexEntry.bytes);
		timing.writeMs = performance.now() - t2;
		timing.totalMs = performance.now() - t0;

		const requests = stats.readers.reduce((a, s) => a + s.requests, 0);
		const fetched = stats.readers.reduce((a, s) => a + s.bytes, 0);
		post({
			type: 'done',
			imgs: Object.keys(report.index.imgs).length,
			files: queue.length,
			bytes: queuedBytes,
			warnings: report.warnings.slice(0, 20),
			warningCount: report.warnings.length,
			timing,
			io: { readCalls: stats.reads + stats.readers.reduce((a, s) => a + s.reads, 0), httpRequests: requests, httpBytes: fetched, blobBytes: stats.bytes },
			zipStats: report.zip_stats || null,
		});
	} catch (e) {
		post({ type: 'error', code: e && e.code ? e.code : 'import', message: describe(e) });
	}
}

self.onmessage = async (ev) => {
	const m = ev.data;
	try {
		if (m.type === 'probe') {
			const result = await probe(m.parsed, m.manifestText);
			self.postMessage({ type: 'probed', id: m.id, result });
		} else if (m.type === 'import') {
			await runImport(m.id, m.source, m.manifestText);
		}
	} catch (e) {
		self.postMessage({ type: 'error', id: m.id, code: e && e.code ? e.code : 'worker', message: describe(e) });
	}
};
self.postMessage({ type: 'ready' });
