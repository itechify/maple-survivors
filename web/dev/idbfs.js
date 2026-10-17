// DEV ONLY (spec #130 spike #131): read and write the IndexedDB database behind Godot's persistent `user://`.
//
// Godot's web export mounts Emscripten's IDBFS at /userfs; the game's user data dir is /userfs/<custom_user_dir_name>
// (/userfs/MapleSurvivors), so user://asset_cache/v83 is /userfs/MapleSurvivors/asset_cache/v83. IDBFS keeps one
// IndexedDB database per mount point, named after it ("/userfs"), version 21, with one object store "FILE_DATA"
// (out-of-line keys = absolute paths) and an index "timestamp" on the "timestamp" field. Records:
//   directory: { timestamp: Date, mode: 0o40777 }
//   file:      { timestamp: Date, mode: 0o100666, contents: Uint8Array }
// On engine start IDBFS copies every record into memory (sorted by path, so a file's directory records must exist),
// and every sync of a running engine makes the database equal to its in-memory tree, deleting records it does not
// have. So: write here only while no engine is running (before start, or after it has quit).
//
// Classic script; defines window.IdbFs.
(function () {
	const DB_NAME = '/userfs';
	const DB_VERSION = 21;
	const STORE = 'FILE_DATA';
	const DIR_MODE = 0o40777;
	const FILE_MODE = 0o100666;

	function promisify(req) {
		return new Promise(function (resolve, reject) {
			req.onsuccess = function () { resolve(req.result); };
			req.onerror = function () { reject(req.error); };
		});
	}

	// Opens the database, creating the store and index exactly as Emscripten's IDBFS does when it is new.
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

	// The directories strictly below /userfs that contain `path`.
	function ancestors(path) {
		const out = [];
		const parts = path.split('/').filter(Boolean); // ['userfs', 'MapleSurvivors', ..., file]
		for (let i = 2; i < parts.length; i++) {
			out.push('/' + parts.slice(0, i).join('/'));
		}
		return out;
	}

	// Writes files: [{path: '/userfs/...', data: ArrayBuffer|Uint8Array}], with their directory records, in batches.
	async function writeFiles(files, onProgress) {
		const db = await open();
		try {
			const now = new Date();
			const dirs = new Set();
			for (const f of files) {
				ancestors(f.path).forEach(function (d) { dirs.add(d); });
			}
			let tx = db.transaction([STORE], 'readwrite');
			for (const d of dirs) {
				tx.objectStore(STORE).put({ timestamp: now, mode: DIR_MODE }, d);
			}
			await done(tx);
			const BATCH = 50;
			for (let i = 0; i < files.length; i += BATCH) {
				const batch = files.slice(i, i + BATCH);
				tx = db.transaction([STORE], 'readwrite');
				for (const f of batch) {
					const contents = f.data instanceof Uint8Array ? f.data : new Uint8Array(f.data);
					tx.objectStore(STORE).put({ timestamp: now, mode: FILE_MODE, contents: contents }, f.path);
				}
				await done(tx);
				if (onProgress) onProgress(Math.min(i + BATCH, files.length), files.length);
			}
		} finally {
			db.close();
		}
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

	// The record at `path` ({timestamp, mode, contents?}) or null.
	async function readRecord(path) {
		const db = await open();
		try {
			return (await promisify(db.transaction([STORE], 'readonly').objectStore(STORE).get(path))) || null;
		} finally {
			db.close();
		}
	}

	// The file at `path` as text, or null.
	async function readText(path) {
		const rec = await readRecord(path);
		return rec && rec.contents ? new TextDecoder().decode(rec.contents) : null;
	}

	// Every key (absolute path) at or below `prefix`.
	async function listPaths(prefix) {
		const db = await open();
		try {
			const range = prefix ? IDBKeyRange.bound(prefix, prefix + '￿') : undefined;
			return await promisify(db.transaction([STORE], 'readonly').objectStore(STORE).getAllKeys(range));
		} finally {
			db.close();
		}
	}

	window.IdbFs = {
		DB_NAME, DB_VERSION, STORE, DIR_MODE, FILE_MODE,
		open, writeFiles, deletePrefix, readRecord, readText, listPaths,
	};
}());
