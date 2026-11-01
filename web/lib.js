// Pure helpers of the web shell (spec #130, ADR 0004): paths, manifest checks, source URL parsing, the block cache
// that sits in front of ranged HTTP reads, the shell-game request marker and save validation. No DOM, no storage and
// no network access in here, so `node --test web/dev/test/*.test.mjs` covers it. Used by shell.js and import_worker.js.

/** The game's user data dir on web: Godot's IDBFS is mounted at /userfs and the project's custom user dir is this. */
export const USER_DIR = '/userfs/MapleSurvivors';
/** AssetCachePaths' default cache root (user://asset_cache/v83). */
export const CACHE_ROOT = USER_DIR + '/asset_cache/v83';
/** user://web_request.json: the game writes it, then quits (docs/ARCHITECTURE.md "Shell-game protocol"). */
export const MARKER_PATH = USER_DIR + '/web_request.json';
/** user://save.json: SaveData.PATH. */
export const SAVE_PATH = USER_DIR + '/save.json';
/** Marker `request` values the shell understands; anything else is logged, deleted and ignored. */
export const REQUEST_KINDS = ['reimport', 'export_save', 'import_save'];

// ---- Manifest -------------------------------------------------------------------------------------------------------
// The Rust importer expands the manifest (map backs, mob links ...) by reading WZ data, so the shell cannot repeat the
// whole expansion. It checks what is deterministic from the manifest alone: the imgs it names, plus the img paths of
// its map, mob, character and item ids (the formulas of tools/wzimport/src/manifest.rs), and for each of them the
// sub-paths the cache index (`paths`) must cover. A cache missing any of those, or whose files are gone, is incomplete.
// Derived dependencies that vanish from a cache are caught by the file check in assessCache(), which looks at every
// img the cache's own index lists.

/** `Map.wz/Map/Map1/104040000.img`. */
export function mapImgPath(id) {
	const s = String(id).padStart(9, '0');
	return `Map.wz/Map/Map${s[0]}/${s}.img`;
}

/** `Mob.wz/0100100.img`. */
export function mobImgPath(id) {
	return `Mob.wz/${String(id).padStart(7, '0')}.img`;
}

/** The Character.wz img of a body, face, hair or equip id, or null for an unknown category. */
export function characterImgPath(id) {
	const cat = Math.floor(id / 10000);
	let dir;
	if (cat === 0 || cat === 1) dir = '';
	else if (cat === 2) dir = 'Face';
	else if (cat === 3) dir = 'Hair';
	else if (cat === 100) dir = 'Cap';
	else if (cat >= 101 && cat <= 103) dir = 'Accessory';
	else if (cat === 104) dir = 'Coat';
	else if (cat === 105) dir = 'Longcoat';
	else if (cat === 106) dir = 'Pants';
	else if (cat === 107) dir = 'Shoes';
	else if (cat === 108) dir = 'Glove';
	else if (cat === 109) dir = 'Shield';
	else if (cat === 110) dir = 'Cape';
	else if (cat === 111) dir = 'Ring';
	else if (cat >= 130 && cat <= 170) dir = 'Weapon';
	else return null;
	const file = String(id).padStart(8, '0');
	return dir ? `Character.wz/${dir}/${file}.img` : `Character.wz/${file}.img`;
}

/** Item categories of the importer's item_path() (tools/wzimport/src/manifest.rs); web/dev/test checks the table. */
export const ITEM_KINDS = { 2: 'Consume', 3: 'Install', 4: 'Etc', 5: 'Cash', 9: 'Special' };

/** {img, sub} of an item id (`Item.wz/Etc/0400.img`, `04000019`), or null for an unknown type. */
export function itemPath(id) {
	const kind = ITEM_KINDS[Math.floor(id / 1000000)];
	if (!kind) return null;
	return { img: `Item.wz/${kind}/${String(Math.floor(id / 10000)).padStart(4, '0')}.img`, sub: String(id).padStart(8, '0') };
}

/** The Item.wz img of an item id (`Item.wz/Etc/0400.img`), or null for an unknown type. */
export function itemImgPath(id) {
	const p = itemPath(id);
	return p ? p.img : null;
}

/** Parses manifest JSON text; throws a readable Error for an unsupported manifest. */
export function parseManifest(text) {
	const m = JSON.parse(text);
	if (!m || m.format !== 1) throw new Error('unsupported asset manifest format');
	return m;
}

/**
 * What the manifest asks of each img, like the importer's Plan: `Map(img -> {whole, paths: Set})`. A whole-img request
 * wins over sub-paths. Only requests the manifest decides on its own appear: its imgs (with their `paths`), whole map,
 * mob and character imgs, one `Item.wz` sub-path per item id, `MapHelper.img/portal` for any map and one
 * `Sound.wz/Mob.img/<id>` per listed mob.
 */
export function expectedRequests(manifest) {
	const out = new Map();
	const get = (img) => {
		if (!out.has(img)) out.set(img, { whole: false, paths: new Set() });
		return out.get(img);
	};
	const whole = (img) => {
		get(img).whole = true;
	};
	const sub = (img, path) => {
		const p = String(path).replace(/^\/+|\/+$/g, '');
		if (p) get(img).paths.add(p);
		else whole(img);
	};
	for (const spec of manifest.imgs || []) {
		if (Array.isArray(spec.paths)) {
			get(spec.img);
			for (const p of spec.paths) sub(spec.img, p);
		} else whole(spec.img);
	}
	for (const p of manifest.mapimgs || []) whole(p.replace(/^\/+|\/+$/g, ''));
	for (const id of manifest.maps || []) whole(mapImgPath(id));
	for (const id of manifest.mobs || []) whole(mobImgPath(id));
	for (const id of manifest.character || []) {
		const p = characterImgPath(id);
		if (p) whole(p);
	}
	for (const id of manifest.items || []) {
		const p = itemPath(id);
		if (p) sub(p.img, p.sub);
	}
	// Derived by the importer in every case (MapHelper portals for any map, Sound.wz/Mob.img for any mob).
	if ((manifest.maps || []).length || (manifest.mapimgs || []).length) sub('Map.wz/MapHelper.img', 'portal');
	for (const id of manifest.mobs || []) sub('Sound.wz/Mob.img', String(id).padStart(7, '0'));
	return out;
}

/** Every img the manifest names, plus the imgs its ids resolve to; sorted, without duplicates. */
export function expectedImgs(manifest) {
	return Array.from(expectedRequests(manifest).keys()).sort();
}

/**
 * True when a cached img entry (`paths`: null/absent = the whole img, else the sub-paths written) covers a request.
 * A cached path covers itself and everything below it (the importer absorbs paths under a shorter one).
 */
export function entryCovers(entry, request) {
	const cached = entry.paths;
	if (cached === null || cached === undefined) return true;
	if (!Array.isArray(cached)) return false;
	if (request.whole) return false;
	for (const r of request.paths) {
		if (!cached.some((p) => r === p || r.startsWith(p + '/'))) return false;
	}
	return true;
}

/** The .wz archives an import of this manifest reads, sorted (e.g. `Map.wz`, `Mob.wz`). */
export function requiredArchives(manifest) {
	const out = new Set();
	for (const img of expectedImgs(manifest)) out.add(img.split('/')[0]);
	// Map-structured imgs pull their backs, tiles, objs (Map.wz) and music (Sound.wz) with them.
	if ((manifest.maps || []).length || (manifest.mapimgs || []).length) {
		out.add('Map.wz');
		out.add('Sound.wz');
	}
	return Array.from(out).sort();
}

/**
 * Judges a cache against the bundled manifest.
 * `indexText` is the cache's cache.json text (or null), `keys` the absolute paths of the records below CACHE_ROOT (or
 * null to skip the file check). Returns {state: 'ok'|'none'|'invalid'|'incomplete', missing: [{img, reason}]}.
 */
export function assessCache({ manifest, indexText, keys, root = CACHE_ROOT }) {
	if (indexText === null || indexText === undefined) return { state: 'none', missing: [] };
	let index;
	try {
		index = JSON.parse(indexText);
	} catch (e) {
		return { state: 'invalid', missing: [], reason: 'cache.json is not valid JSON' };
	}
	if (!index || typeof index !== 'object' || index.format !== 1 || typeof index.imgs !== 'object' || !index.imgs) {
		return { state: 'invalid', missing: [], reason: 'cache.json has an unsupported format' };
	}
	const present = keys ? new Set(keys) : null;
	const missing = [];
	for (const [img, request] of expectedRequests(manifest)) {
		if (!Object.prototype.hasOwnProperty.call(index.imgs, img)) missing.push({ img, reason: 'not in the cache index' });
		else if (!entryCovers(index.imgs[img], request)) missing.push({ img, reason: 'paths missing' });
	}
	if (present) {
		for (const [img, entry] of Object.entries(index.imgs)) {
			if (missing.some((m) => m.img === img)) continue;
			const json = `${root}/${entry.json || img + '.json'}`;
			let bad = !present.has(json);
			for (let i = 0; !bad && i < (entry.pages || 0); i++) bad = !present.has(`${root}/${img}.${i}.png`);
			if (entry.sounds > 0) {
				bad ||= !Array.isArray(entry.sound_files) || entry.sound_files.length !== entry.sounds
					|| entry.sound_files.some((file) => typeof file !== 'string' || !present.has(`${root}/${file}`));
			}
			if (bad) missing.push({ img, reason: 'files missing' });
		}
	}
	return missing.length ? { state: 'incomplete', missing } : { state: 'ok', missing: [] };
}

// ---- Sources --------------------------------------------------------------------------------------------------------

/**
 * Parses what the player typed into the URL field. A path ending in .zip is a zip source; anything else is a base
 * folder URL whose archives are `<base>/Mob.wz` and so on. Returns {ok, kind, url, base?, host?} or {ok:false, error}.
 */
export function parseSourceUrl(text) {
	const raw = String(text || '').trim();
	if (!raw) return { ok: false, error: 'Enter an address first.' };
	let u;
	try {
		u = new URL(raw);
	} catch (e) {
		return { ok: false, error: 'That is not a full web address (it should start with https://).' };
	}
	if (u.protocol !== 'http:' && u.protocol !== 'https:') {
		return { ok: false, error: 'Only http:// and https:// addresses can be used.' };
	}
	u.hash = '';
	if (u.pathname.toLowerCase().endsWith('.zip')) {
		return { ok: true, kind: 'zip', url: u.href, host: u.host };
	}
	if (u.pathname.toLowerCase().endsWith('.wz')) {
		return { ok: false, error: 'Enter the folder that holds the .wz files, or a .zip file, not a single .wz file.' };
	}
	if (!u.pathname.endsWith('/')) u.pathname += '/';
	return { ok: true, kind: 'base', url: u.href, base: u.href, host: u.host };
}

/** The address of one archive below a base folder URL (query strings are kept after the file name). */
export function archiveUrl(base, name) {
	const u = new URL(base);
	u.pathname += encodeURIComponent(name);
	return u.href;
}

/**
 * Finds the folder holding the required archives among picked files (`[{path, size, ...}]`, `path` relative like a
 * webkitRelativePath: `v83/Mob.wz`). Names match case-insensitively; the folder with the most required archives wins
 * (the shallowest on a tie). Returns {dir, found: {'Mob.wz': entry}, missing: [names]}.
 */
export function pickArchiveFolder(entries, required) {
	const want = new Map(required.map((n) => [n.toLowerCase(), n]));
	const groups = new Map();
	for (const e of entries) {
		const parts = String(e.path).split('/');
		const base = parts[parts.length - 1];
		const canon = want.get(base.toLowerCase());
		if (!canon) continue;
		const dir = parts.slice(0, -1).join('/');
		if (!groups.has(dir)) groups.set(dir, {});
		groups.get(dir)[canon] = e;
	}
	let best = null;
	for (const [dir, found] of groups) {
		const count = Object.keys(found).length;
		const depth = dir ? dir.split('/').length : 0;
		if (!best || count > best.count || (count === best.count && depth < best.depth)) best = { dir, found, count, depth };
	}
	const found = best ? best.found : {};
	return { dir: best ? best.dir : '', found, missing: required.filter((n) => !found[n]) };
}

/** "1.8 GB", "640 MB", "12 KB", "0 B". */
export function formatBytes(n) {
	if (!Number.isFinite(n) || n < 0) return '?';
	if (n < 1024) return `${n} B`;
	const units = ['KB', 'MB', 'GB', 'TB'];
	let v = n / 1024;
	let i = 0;
	while (v >= 1024 && i < units.length - 1) {
		v /= 1024;
		i++;
	}
	return `${v >= 100 ? v.toFixed(0) : v.toFixed(1)} ${units[i]}`;
}

/**
 * A reader {length, readAt(offset, len)} over a ranged fetch with an LRU of aligned blocks, so the importer's reads of
 * at most 64 KiB do not each cost a round trip. `fetchRange(start, endExclusive)` returns exactly that many bytes
 * (fewer only at the end of the file). `stats` counts requests, bytes fetched and cache hits.
 */
export function createBlockReader({ length, fetchRange, blockSize = 1 << 20, maxBlocks = 16 }) {
	const blocks = new Map(); // block index -> Uint8Array, in least-recently-used order
	const stats = { requests: 0, bytes: 0, hits: 0, reads: 0 };
	function touch(i) {
		const b = blocks.get(i);
		blocks.delete(i);
		blocks.set(i, b);
		return b;
	}
	function load(first, last) {
		const start = first * blockSize;
		const end = Math.min(length, (last + 1) * blockSize);
		const data = fetchRange(start, end);
		stats.requests++;
		stats.bytes += data.length;
		if (data.length !== end - start) {
			throw new Error(`short read at ${start}: wanted ${end - start} bytes, got ${data.length}`);
		}
		for (let i = first; i <= last; i++) {
			blocks.set(i, data.subarray((i - first) * blockSize, Math.min(data.length, (i - first + 1) * blockSize)));
		}
		while (blocks.size > maxBlocks) blocks.delete(blocks.keys().next().value);
	}
	return {
		length,
		stats,
		readAt(offset, len) {
			stats.reads++;
			if (!Number.isInteger(offset) || !Number.isInteger(len) || offset < 0 || len < 0 || offset + len > length) {
				throw new Error(`read ${offset}+${len} is outside the ${length}-byte file`);
			}
			if (len === 0) return new Uint8Array(0);
			const first = Math.floor(offset / blockSize);
			const last = Math.floor((offset + len - 1) / blockSize);
			// Fetch each run of missing blocks with one request.
			for (let i = first; i <= last; i++) if (blocks.has(i)) stats.hits++;
			let runStart = -1;
			for (let i = first; i <= last + 1; i++) {
				const missing = i <= last && !blocks.has(i);
				if (missing && runStart < 0) runStart = i;
				if (!missing && runStart >= 0) {
					load(runStart, i - 1);
					runStart = -1;
				}
			}
			const out = new Uint8Array(len);
			let written = 0;
			for (let i = first; i <= last; i++) {
				const block = blocks.has(i) ? touch(i) : null;
				if (!block) throw new Error('block cache evicted a block mid-read; raise maxBlocks');
				const from = Math.max(offset, i * blockSize) - i * blockSize;
				const to = Math.min(offset + len, (i + 1) * blockSize) - i * blockSize;
				out.set(block.subarray(from, to), written);
				written += to - from;
			}
			return out;
		},
	};
}

// ---- Shell-game protocol and saves ------------------------------------------------------------------------------------

/** Parses the text of user://web_request.json: {ok: true, kind} or {ok: false, error}. */
export function parseMarker(text) {
	let m;
	try {
		m = JSON.parse(text);
	} catch (e) {
		return { ok: false, error: 'the request marker is not valid JSON' };
	}
	if (!m || typeof m !== 'object' || m.format !== 1 || typeof m.request !== 'string') {
		return { ok: false, error: 'the request marker has no format 1 request' };
	}
	if (!REQUEST_KINDS.includes(m.request)) return { ok: false, error: `unknown request "${m.request}"`, unknown: true };
	return { ok: true, kind: m.request };
}

const isWhole = (v) => typeof v === 'number' && Number.isFinite(v) && v >= 0 && Math.floor(v) === v;
const isObject = (v) => v !== null && typeof v === 'object' && !Array.isArray(v);

/**
 * A light check before staging a candidate: it parses, has SaveData's top-level shape
 * (format 1, 2 or 3, best and runs objects; for formats 2 and 3 exactly 3 slots and a history array). The game still validates
 * the contents in full when it loads the file. Returns {ok: true, slots} or {ok: false, error}.
 */
export function validateSaveText(text) {
	let s;
	try {
		s = JSON.parse(text);
	} catch (e) {
		return { ok: false, error: 'That file is not valid JSON, so it was not imported.' };
	}
	if (!isObject(s) || !isWhole(s.format) || ![1, 2, 3].includes(s.format)) {
		return { ok: false, error: 'That file is not a Maple Survivors save (unknown format).' };
	}
	if (!isObject(s.best) || !isObject(s.runs)) {
		return { ok: false, error: 'That file is not a Maple Survivors save (no best results).' };
	}
	if (s.format === 1) return { ok: true, slots: 0 };
	if (!Array.isArray(s.slots) || s.slots.length !== 3 || !Array.isArray(s.history)) {
		return { ok: false, error: 'That file is not a Maple Survivors save (slots or history missing).' };
	}
	return { ok: true, slots: s.slots.filter((x) => x !== null).length };
}

/** Stage only. SaveData validates all nested data before promoting this sibling to the persistent save. */
export async function stageSaveImport(text, writeFile) {
	const check = validateSaveText(text);
	if (check.ok) await writeFile(SAVE_PATH + '.import', new TextEncoder().encode(text));
	return check;
}

/** One exclusive browser owner for all /userfs mounts, shell operations and workers. Held until page exit. */
export function createStoreOwnership(locks) {
	let held = false;
	let pending = null;
	let finished = null;
	let release = null;
	return {
		acquire() {
			if (held) return Promise.resolve(true);
			if (pending) return pending;
			pending = new Promise((resolve, reject) => {
				if (!locks || typeof locks.request !== 'function') {
					reject(new Error('This browser needs Web Locks to protect your save. Use a current browser over HTTPS or localhost.'));
					return;
				}
				finished = locks.request('maple-survivors-userfs', { ifAvailable: true, mode: 'exclusive' }, async (lock) => {
					if (!lock) { resolve(false); return; }
					held = true;
					const lifetime = new Promise((done) => { release = done; });
					resolve(true);
					await lifetime;
					held = false;
				});
				finished.catch(reject);
			}).finally(() => { pending = null; });
			return pending;
		},
		// For deterministic tests. The shell never releases a mounted engine's lock; the browser does so on page exit/crash.
		async release() {
			if (release) release();
			if (finished) await finished;
		},
	};
}

/** `maple-survivors-save-20261017-142530.json` (local time). */
export function saveFileName(date) {
	const p = (n, w = 2) => String(n).padStart(w, '0');
	return `maple-survivors-save-${date.getFullYear()}${p(date.getMonth() + 1)}${p(date.getDate())}`
		+ `-${p(date.getHours())}${p(date.getMinutes())}${p(date.getSeconds())}.json`;
}

/** True when the error is Godot's web teardown failing on a closed AudioContext (after a quit; spike notes 2). */
export function isAudioTeardownError(message) {
	return /currentTime/.test(String(message)) && /null|undefined/.test(String(message));
}

// ---- Storage persistence (#148) ---------------------------------------------------------------------------------------
// navigator.storage.persist() may wait for the player's answer to a permission prompt (Firefox), possibly forever in an
// unattended window. So the shell shows the current state at once and treats a granted request as an upgrade.

/** The footer storage line for a persistence state: `{text, good}`. `snapshot` is `{persist, usage}` (usage in bytes). */
export function storageStatus(snapshot) {
	const base = {
		persistent: 'Storage: kept (persistent)',
		'best-effort': 'Storage: best effort (the browser may clear it when space runs short)',
		unsupported: 'Storage: not confirmed by this browser',
	}[snapshot.persist] || 'Storage: checking...';
	const usage = snapshot.usage ? ` (${formatBytes(snapshot.usage)} used)` : '';
	return { text: base + usage, good: snapshot.persist === 'persistent' };
}

/**
 * The persistence state machine, with the storage API injected (`navigator.storage`; may be missing or throw).
 * `request()` reads `persisted()` without prompting, reports that state through `onChange(state)` and resolves, then
 * asks `persist()` in the background: a grant upgrades the state to 'persistent', a refusal or error keeps it. While a
 * request is still running, further `request()` calls join it; once kept, or while `persist()` is pending, they only
 * refresh the usage estimate and start no new `persist()`.
 * `state` is `{persist: 'checking'|'persistent'|'best-effort'|'unsupported', usage, pending}`.
 */
export function createPersistence({ storage, onChange = () => {} }) {
	const state = { persist: 'checking', usage: 0, pending: false };
	let starting = null; // the running request() promise
	const emit = () => onChange({ ...state });
	async function readUsage() {
		try {
			const est = await storage.estimate();
			if (est && est.usage) state.usage = est.usage;
		} catch (e) {
			/* no estimate */
		}
	}
	async function ask() {
		state.pending = true;
		try {
			if (await storage.persist()) state.persist = 'persistent';
		} catch (e) {
			/* refused or failed: keep the best-effort line */
		}
		state.pending = false;
		emit();
	}
	async function run() {
		if (!storage || !storage.persist || !storage.persisted) {
			state.persist = 'unsupported';
		} else {
			try {
				state.persist = (await storage.persisted()) ? 'persistent' : 'best-effort';
			} catch (e) {
				state.persist = 'unsupported';
			}
		}
		emit();
		if (state.persist === 'best-effort') ask();
		if (storage && storage.estimate) {
			await readUsage();
			emit();
		}
		return { ...state };
	}
	async function refreshUsage() {
		if (storage && storage.estimate) {
			await readUsage();
			emit();
		}
		return { ...state };
	}
	function request() {
		if (starting) return starting;
		// Already kept, or the prompt is still open: only the usage figure can have changed (e.g. after an import).
		const work = state.pending || state.persist === 'persistent' ? refreshUsage() : run();
		starting = work.finally(() => { starting = null; });
		return starting;
	}
	return { state, request };
}
