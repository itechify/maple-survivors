// Reads and writes the IndexedDB database behind Godot's persistent `user://` (spec #130, ADR 0004). Used by the web
// shell page and its import worker; the spike's dev cache injection (web/dev/inject.html) loads the same file.
//
// Godot's web export mounts Emscripten's IDBFS at /userfs; the game's user data dir is /userfs/<custom_user_dir_name>
// (/userfs/MapleSurvivors), so user://asset_cache/v83 is /userfs/MapleSurvivors/asset_cache/v83. IDBFS keeps one
// IndexedDB database per mount point, named after it ("/userfs"), version 21, with one object store "FILE_DATA"
// (out-of-line keys = absolute paths) and an index "timestamp" on the "timestamp" field. Records:
//   directory: { timestamp: Date, mode: 0o40777 }
//   file:      { timestamp: Date, mode: 0o100666, contents: Uint8Array }
// On engine start IDBFS copies every record into memory (sorted by path, so a file's directory records must exist),
// and every sync of a running engine makes the database equal to its in-memory tree, deleting records it does not
// have. So: WRITE here only while no engine is running (before start, or after it has quit). Reading is always safe.
//
// Dual-use script: it has no import/export statements, so it loads as a classic <script> (dev pages) and as
// `import './idbfs.js'` from a module or module worker. Either way it defines globalThis.IdbFs.
(function () {
	const DB_NAME = '/userfs';
	const DB_VERSION = 21;
	const STORE = 'FILE_DATA';
	const DIR_MODE = 0o40777;
	const FILE_MODE = 0o100666;
	// A batch is written in one transaction: at most this many records or bytes (IndexedDB copies each value).
	const BATCH_FILES = 50;
	const BATCH_BYTES = 32 * 1024 * 1024;

	function promisify(req) {
		return new Promise(function (resolve, reject) {
			req.onsuccess = function () { resolve(req.result); };
			req.onerror = function () { reject(req.error); };
		});
	}

	// Opens the database, creating the store and index exactly as Emscripten's IDBFS does when it is new. Whoever
	// creates the database first must do this: Godot opens it at the same version, gets no upgrade and would silently
	// run without persistence otherwise.
	function open() {
		return new Promise(function (resolve, reject) {
			const req = indexedDB.open(DB_NAME, DB_VERSION);
			req.onupgradeneeded = function () {
				const db = req.result;
				const store = db.objectStoreNames.contains(STORE)
					? req.transaction.objectStore(STORE) : db.createObjectStore(STORE);
				if (!store.indexNames.contains('timestamp')) {
					store.createIndex('timestamp', 'timestamp', { unique: false });
				}
			};
			req.onsuccess = function () { resolve(req.result); };
			req.onerror = function () { reject(req.error); };
			req.onblocked = function () { reject(new Error('IndexedDB /userfs is open elsewhere (is the game running?)')); };
		});
	}

	function done(tx) {
		return new Promise(function (resolve, reject) {
			tx.oncomplete = function () { resolve(); };
			tx.onerror = tx.onabort = function () { reject(tx.error); };
		});
	}

	// The directories strictly below /userfs that contain `path` ('/userfs/a/b/c.txt' -> '/userfs/a', '/userfs/a/b').
	function ancestors(path) {
		const out = [];
		const parts = path.split('/').filter(Boolean); // ['userfs', 'MapleSurvivors', ..., file]
		for (let i = 2; i < parts.length; i++) {
			out.push('/' + parts.slice(0, i).join('/'));
		}
		return out;
	}

	// Every directory record needed so that the files at `paths` load (ancestors only, deduplicated, parents first).
	function directoriesFor(paths) {
		const dirs = new Set();
		for (const p of paths) {
			ancestors(p).forEach(function (d) { dirs.add(d); });
		}
		return Array.from(dirs).sort();
	}

	function asBytes(data) {
		return data instanceof Uint8Array ? data : new Uint8Array(data);
	}

	// Writes directory records for `dirs` (absolute paths; their ancestors are added too).
	async function writeDirs(dirs) {
		const db = await open();
		try {
			const now = new Date();
			const all = new Set();
			for (const d of dirs) {
				all.add(d);
				ancestors(d + '/x').forEach(function (a) { all.add(a); });
			}
			const tx = db.transaction([STORE], 'readwrite');
			for (const d of all) {
				tx.objectStore(STORE).put({ timestamp: now, mode: DIR_MODE }, d);
			}
			await done(tx);
		} finally {
			db.close();
		}
	}

	// Writes files: [{path: '/userfs/...', data: ArrayBuffer|Uint8Array}], with their directory records, in batches.
	// onProgress(filesDone, filesTotal) is called after each batch.
	async function writeFiles(files, onProgress) {
		const db = await open();
		try {
			const now = new Date();
			let tx = db.transaction([STORE], 'readwrite');
			for (const d of directoriesFor(files.map(function (f) { return f.path; }))) {
				tx.objectStore(STORE).put({ timestamp: now, mode: DIR_MODE }, d);
			}
			await done(tx);
			let i = 0;
			while (i < files.length) {
				tx = db.transaction([STORE], 'readwrite');
				let bytes = 0;
				let n = 0;
				while (i < files.length && n < BATCH_FILES && (n === 0 || bytes < BATCH_BYTES)) {
					const f = files[i++];
					const contents = asBytes(f.data);
					bytes += contents.byteLength;
					n++;
					tx.objectStore(STORE).put({ timestamp: now, mode: FILE_MODE, contents: contents }, f.path);
				}
				await done(tx);
				if (onProgress) onProgress(i, files.length);
			}
		} finally {
			db.close();
		}
	}

	// Writes one file (and its directory records).
	function writeFile(path, data) {
		return writeFiles([{ path: path, data: data }]);
	}

	// Deletes every record at or below `prefix` (e.g. '/userfs/MapleSurvivors/asset_cache').
	async function deletePrefix(prefix) {
		const db = await open();
		try {
			const tx = db.transaction([STORE], 'readwrite');
			tx.objectStore(STORE).delete(prefix);
			tx.objectStore(STORE).delete(IDBKeyRange.bound(prefix + '/', prefix + '/￿'));
			await done(tx);
		} finally {
			db.close();
		}
	}

	// Deletes the single record at `path`.
	async function remove(path) {
		const db = await open();
		try {
			const tx = db.transaction([STORE], 'readwrite');
			tx.objectStore(STORE).delete(path);
			await done(tx);
		} finally {
			db.close();
		}
	}

	// The record at `path` ({timestamp, mode, contents?}) or null.
	async function readRecord(path) {
		const db = await open();
		try {
			return (await promisify(db.transaction([STORE], 'readonly').objectStore(STORE).get(path))) || null;
		} finally {
			db.close();
		}
	}

	// The file at `path` as bytes, or null.
	async function readBytes(path) {
		const rec = await readRecord(path);
		if (!rec || !rec.contents) return null;
		const c = rec.contents;
		return c instanceof Uint8Array ? c : ArrayBuffer.isView(c) ? new Uint8Array(c.buffer, c.byteOffset, c.byteLength)
			: new Uint8Array(c);
	}

	// The file at `path` as text, or null.
	async function readText(path) {
		const bytes = await readBytes(path);
		return bytes ? new TextDecoder().decode(bytes) : null;
	}

	// Every key (absolute path) at or below `prefix` (a directory path or a plain string prefix).
	async function listPaths(prefix) {
		const db = await open();
		try {
			const range = prefix ? IDBKeyRange.bound(prefix, prefix + '￿') : undefined;
			return await promisify(db.transaction([STORE], 'readonly').objectStore(STORE).getAllKeys(range));
		} finally {
			db.close();
		}
	}

	globalThis.IdbFs = {
		DB_NAME, DB_VERSION, STORE, DIR_MODE, FILE_MODE,
		open, ancestors, directoriesFor, writeDirs, writeFiles, writeFile, deletePrefix, remove, readRecord,
		readBytes, readText, listPaths,
	};
}());
