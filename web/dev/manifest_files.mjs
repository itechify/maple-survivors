// DEV ONLY (never copied into the web artifact): reads game/data/asset_manifest.json together with its include fragments
// game/data/asset_manifest.d/*.json, the way tools/wzimport (manifest.rs) and game/scripts/assets/asset_manifest.gd do.
// The shipped page cannot list a folder, so `scripts/export.sh --web` writes the merged manifest (`wzimport manifest`) into
// the artifact as the one asset_manifest.json that web/shell.js fetches; the dev tests use this helper on the source files.
//
// Rules (docs/ASSET_PIPELINE.md 4.1): fragments are merged in file-name order after the main file; a key listed in two
// files is an error naming both (an imgs entry is keyed by (img, path), or by img when it exports the whole img; ids by
// id; mapimgs by path); repeats inside one file are tolerated; fragments may omit `format` and may not have unknown keys.
import fs from 'node:fs';
import path from 'node:path';

const KEYS = ['format', '_doc', 'imgs', 'maps', 'mapimgs', 'mobs', 'character', 'items'];
const LISTS = ['imgs', 'maps', 'mapimgs', 'mobs', 'character', 'items'];
const ID_WORD = { maps: 'map', mapimgs: 'mapimg', mobs: 'mob', character: 'character', items: 'item' };

/** The fragment folder of a manifest file: `<dir>/asset_manifest.json` -> `<dir>/asset_manifest.d`. */
export function fragmentDir(manifestPath) {
	const { dir, name } = path.parse(manifestPath);
	return path.join(dir, `${name}.d`);
}

/**
 * Merges the parsed main manifest with fragments (`[{ name, data }]`, in merge order) into one manifest object.
 * Throws an Error naming both files for a duplicate key.
 */
export function mergeManifests(main, fragments = []) {
	if (!main.data || main.data.format !== 1) throw new Error(`${main.name}: unsupported format`);
	const out = { format: 1, _doc: main.data._doc ?? '' };
	for (const k of LISTS) out[k] = [];
	const owner = new Map();
	[main, ...fragments].forEach((file, i) => {
		const { name, data } = file;
		if (i > 0) {
			if (!data || typeof data !== 'object' || Array.isArray(data)) throw new Error(`manifest fragment ${name}: not a JSON object`);
			for (const k of Object.keys(data)) {
				if (!KEYS.includes(k)) throw new Error(`manifest fragment ${name}: unknown key "${k}" (allowed: ${KEYS.join(', ')})`);
			}
			if (data.format !== undefined && data.format !== 1) throw new Error(`manifest fragment ${name}: unsupported format ${data.format}`);
		}
		const claim = (key, what) => {
			const first = owner.get(key);
			if (first !== undefined && first !== name) throw new Error(`manifest entry ${what} is listed in both ${first} and ${name}`);
		};
		const keys = [];
		for (const [list, word] of Object.entries(ID_WORD)) {
			for (const id of data[list] || []) {
				claim(`id|${word} ${id}`, `\`${word} ${id}\``);
				keys.push(`id|${word} ${id}`);
			}
		}
		for (const e of data.imgs || []) {
			if (e.paths == null) {
				claim(`whole|${e.img}`, `\`img ${e.img}\``);
				claim(`partial|${e.img}`, `\`img ${e.img}\``);
				keys.push(`whole|${e.img}`);
			} else {
				claim(`whole|${e.img}`, `\`img ${e.img}\` (paths)`);
				for (const p of e.paths) {
					claim(`path|${e.img}|${p}`, `\`img ${e.img}\` path "${p}"`);
					keys.push(`path|${e.img}|${p}`, `partial|${e.img}`);
				}
			}
		}
		for (const k of keys) owner.set(k, name);
		for (const k of LISTS) out[k].push(...(data[k] || []));
	});
	return out;
}

/** Reads a manifest file plus its sibling fragment folder (absent is fine) and returns the merged manifest object. */
export function readMergedManifest(manifestPath) {
	const main = { name: path.basename(manifestPath), data: JSON.parse(fs.readFileSync(manifestPath, 'utf8')) };
	const dir = fragmentDir(manifestPath);
	const fragments = [];
	if (fs.existsSync(dir)) {
		const names = fs.readdirSync(dir, { withFileTypes: true }).filter((d) => d.isFile() && d.name.endsWith('.json')).map((d) => d.name).sort();
		for (const name of names) fragments.push({ name, data: JSON.parse(fs.readFileSync(path.join(dir, name), 'utf8')) });
	}
	return mergeManifests(main, fragments);
}

/** The sorted selection lines of tools/wzimport/tests/fixtures/manifest_golden.txt (`img <img> *`, `img <img> <path>`, `map 1` ...). */
export function canonicalLines(manifest) {
	const lines = [];
	for (const e of manifest.imgs || []) {
		if (e.paths == null) lines.push(`img ${e.img} *`);
		else for (const p of e.paths) lines.push(`img ${e.img} ${p}`);
	}
	for (const [list, word] of Object.entries(ID_WORD)) for (const id of manifest[list] || []) lines.push(`${word} ${id}`);
	return lines.sort();
}
