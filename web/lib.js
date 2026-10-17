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
// its map, mob, character and item ids (the formulas of tools/wzimport/src/manifest.rs). A cache missing any of those,
// or whose files are gone, is incomplete. Derived dependencies that vanish from a cache are caught by the file check
// in assessCache(), which looks at every img the cache's own index lists.

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

/** The Item.wz img of an item id (`Item.wz/Etc/0400.img`), or null for an unknown type. */
export function itemImgPath(id) {
	const kinds = { 2: 'Consume', 3: 'Install', 4: 'Etc', 5: 'Cash' };
	const kind = kinds[Math.floor(id / 1000000)];
	if (!kind) return null;
	return `Item.wz/${kind}/${String(Math.floor(id / 10000)).padStart(4, '0')}.img`;
}

/** Parses manifest JSON text; throws a readable Error for an unsupported manifest. */
export function parseManifest(text) {
	const m = JSON.parse(text);
	if (!m || m.format !== 1) throw new Error('unsupported asset manifest format');
	return m;
}

/** Every img the manifest names, plus the imgs its ids resolve to; sorted, without duplicates. */
export function expectedImgs(manifest) {
	const out = new Set();
	for (const spec of manifest.imgs || []) out.add(spec.img);
	for (const p of manifest.mapimgs || []) out.add(p.replace(/^\/+|\/+$/g, ''));
	for (const id of manifest.maps || []) out.add(mapImgPath(id));
	for (const id of manifest.mobs || []) out.add(mobImgPath(id));
	for (const id of manifest.character || []) {
		const p = characterImgPath(id);
		if (p) out.add(p);
	}
	for (const id of manifest.items || []) {
		const p = itemImgPath(id);
		if (p) out.add(p);
	}
	// Derived by the importer in every case (MapHelper portals for any map, Sound.wz/Mob.img for any mob).
	if ((manifest.maps || []).length || (manifest.mapimgs || []).length) out.add('Map.wz/MapHelper.img');
	if ((manifest.mobs || []).length) out.add('Sound.wz/Mob.img');
	return Array.from(out).sort();
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
	for (const img of expectedImgs(manifest)) {
		if (!Object.prototype.hasOwnProperty.call(index.imgs, img)) missing.push({ img, reason: 'not in the cache index' });
	}
	if (present) {
		for (const [img, entry] of Object.entries(index.imgs)) {
			if (missing.some((m) => m.img === img)) continue;
			const json = `${root}/${entry.json || img + '.json'}`;
			let bad = !present.has(json);
			for (let i = 0; !bad && i < (entry.pages || 0); i++) bad = !present.has(`${root}/${img}.${i}.png`);
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
 * A light check of a save file before it replaces the player's save: it parses, has SaveData's top-level shape
 * (format 1 or 2, best and runs objects; for format 2 exactly 3 slots and a history array). The game still validates
 * the contents in full when it loads the file. Returns {ok: true, slots} or {ok: false, error}.
 */
export function validateSaveText(text) {
	let s;
	try {
		s = JSON.parse(text);
	} catch (e) {
		return { ok: false, error: 'That file is not valid JSON, so it was not imported.' };
	}
	if (!isObject(s) || !isWhole(s.format) || ![1, 2].includes(s.format)) {
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
