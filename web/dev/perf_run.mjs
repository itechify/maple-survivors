// DEV ONLY (issue #146; replaces the lost #131/#136 QA driver): plays one `--perf` round of a web export in headed
// Chrome and copies the game's summary.json (and its screenshots) out of the page's IndexedDB. Never shipped; it
// talks only to the localhost server of web/dev/serve.mjs.
//
//   node web/dev/serve.mjs <export dir>                 # in another terminal (http://127.0.0.1:8060/)
//   npm install --prefix <scratch dir> playwright       # once, outside the repo's dependencies (none are committed)
//   PLAYWRIGHT_PREFIX=<scratch dir> node web/dev/perf_run.mjs --out=<abs dir under evidence/> \
//       --profile=<abs scratch dir for the Chrome profile> [--import=<abs v83 folder>] [--name=<label>] \
//       [--url=http://127.0.0.1:8060/] [--uncapped] [--timeout-s=1800] -- <game args...>
//
// Example (the #136 window, uncapped):
//   ... perf_run.mjs --uncapped --out=C:/.../evidence/t146/web --profile=C:/.../_scratch/chrome146 \
//       --import=C:/.../v83-original -- --run=henesys_hg1 --seed=2026 --autoplay --autopick --speed=1 --warp=780 \
//       --perf --vsync=off --shot-every=30 --quit-after=1020
//
// Chrome is the installed one (Playwright channel "chrome"), headed, in a persistent profile so an import survives
// between runs. --uncapped adds --disable-gpu-vsync --disable-frame-rate-limit (with the game's --vsync=off that is the
// "uncapped" of docs/ARCHITECTURE.md 10.1). When the page shows its import screen, --import picks that folder in the
// folder input (the player's own v83 data; nothing is uploaded) and starts the import. `--shots=` is added to the game
// args (/userfs/MapleSurvivors/perf/<name>) unless given. The driver records the rAF rate before the round, wasm and JS
// heap every 10 s, the exit, and writes browser.json, summary.json and the round's PNGs into --out.
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';

const argv = process.argv.slice(2);
const split = argv.indexOf('--');
const own = split >= 0 ? argv.slice(0, split) : argv;
const gameArgs = split >= 0 ? argv.slice(split + 1) : [];
const flag = (name, def) => {
	const hit = own.find((a) => a === `--${name}` || a.startsWith(`--${name}=`));
	if (!hit) return def;
	return hit.includes('=') ? hit.slice(hit.indexOf('=') + 1) : true;
};
const out = flag('out', '');
const profile = flag('profile', '');
const importDir = flag('import', '');
const name = flag('name', 'run' + Date.now());
const base = flag('url', 'http://127.0.0.1:8060/');
const uncapped = flag('uncapped', false) === true;
const timeoutS = Number(flag('timeout-s', 1800));
if (!out || !profile) {
	console.error('usage: PLAYWRIGHT_PREFIX=<dir> node web/dev/perf_run.mjs --out=<dir> --profile=<dir> [--import=<v83 dir>] -- <game args>');
	process.exit(2);
}
const req = createRequire(path.join(path.resolve(process.env.PLAYWRIGHT_PREFIX || '.'), 'package.json'));
const { chromium } = req('playwright');

const shotsDir = `/userfs/MapleSurvivors/perf/${name}`;
const args = gameArgs.some((a) => a.startsWith('--shots=')) ? gameArgs : gameArgs.concat([`--shots=${shotsDir}`]);
const shots = args.find((a) => a.startsWith('--shots=')).slice('--shots='.length);
const url = base + 'index.html?' + args.map((a) => 'arg=' + encodeURIComponent(a)).join('&');
fs.mkdirSync(out, { recursive: true });
const log = (m) => console.log(`[perf_run ${new Date().toISOString().slice(11, 19)}] ${m}`);

const context = await chromium.launchPersistentContext(profile, {
	channel: 'chrome',
	headless: false,
	viewport: { width: 1600, height: 1200 },
	args: uncapped ? ['--disable-gpu-vsync', '--disable-frame-rate-limit'] : [],
});
const page = context.pages()[0] || (await context.newPage());
const consoleLines = [];
page.on('console', (m) => consoleLines.push(`[${m.type()}] ${m.text()}`));
page.on('pageerror', (e) => consoleLines.push(`[pageerror] ${e.message}`));
const screen = () => page.evaluate(() => document.getElementById('plate')?.dataset.screen || '');
const record = { name, browser: 'chrome', uncapped, game_args: args, url, started: new Date().toISOString() };

// rAF rate with nothing running, on a blank page of the same origin.
await page.goto(base + 'dev/inject.html');
record.browser_version = await page.evaluate(() => navigator.userAgent.match(/Chrome\/[\d.]+/)?.[0] || '');
record.raf = await page.evaluate(() => new Promise((resolve) => {
	const t = [];
	const tick = (now) => {
		t.push(now);
		if (t.length < 241) requestAnimationFrame(tick);
		else {
			const d = t.slice(1).map((v, i) => v - t[i]).sort((a, b) => a - b);
			const median = d[Math.floor(d.length / 2)];
			resolve({ median_ms: median, hz: 1000 / median });
		}
	};
	requestAnimationFrame(tick);
}));
log(`rAF ${record.raf.hz.toFixed(1)} Hz; opening ${url}`);
await page.goto(url);
const t0 = Date.now();
let sawEngine = false;
const memory = [];
let peakWasm = 0;
let peakJs = 0;
while (true) {
	await page.waitForTimeout(1000);
	const s = await screen();
	if (s === 'import') {
		if (!importDir) throw new Error('the page asks for an import; pass --import=<v83 folder>');
		log(`import screen: picking ${importDir}`);
		await page.setInputFiles('#input-folder', importDir);
		await page.waitForFunction(() => !document.getElementById('btn-import').disabled, null, { timeout: 120000 });
		log('import: ' + (await page.textContent('#pick-status')));
		await page.click('#btn-import');
		continue;
	}
	if (s === 'error') throw new Error('shell error: ' + (await page.textContent('#error-text')));
	const engine = await page.evaluate(() => !!window.godotEngine && document.getElementById('shell').hidden);
	sawEngine = sawEngine || engine;
	const elapsed = (Date.now() - t0) / 1000;
	if (engine && Math.round(elapsed) % 10 === 0) {
		const m = await page.evaluate(() => {
			let wasm = 0;
			try {
				const mod = window.godotEngine && window.godotEngine.rtenv;
				if (mod && mod.HEAPU8) wasm = mod.HEAPU8.buffer.byteLength;
			} catch (e) { /* not exposed */ }
			return { wasm, js: performance.memory ? performance.memory.usedJSHeapSize : 0 };
		});
		const sample = { t: Math.round(elapsed), wasm_mib: +(m.wasm / 1048576).toFixed(1), js_used_mib: +(m.js / 1048576).toFixed(1) };
		memory.push(sample);
		peakWasm = Math.max(peakWasm, sample.wasm_mib);
		peakJs = Math.max(peakJs, sample.js_used_mib);
	}
	if (sawEngine && s === 'exited') break;
	if (elapsed > timeoutS) throw new Error(`no exit after ${timeoutS} s (screen ${s})`);
}
record.real_seconds = (Date.now() - t0) / 1000;
record.exit_code = await page.evaluate(() => window.godotExitCode);
record.peak_wasm_heap_mib = peakWasm;
record.peak_js_heap_used_mib = peakJs;
record.memory_samples = memory;
log(`exited after ${record.real_seconds.toFixed(0)} s; reading ${shots}`);
// The engine has quit, so its IndexedDB is final and safe to read.
const files = await page.evaluate(async (dir) => {
	const db = await new Promise((resolve, reject) => {
		const r = indexedDB.open('/userfs');
		r.onsuccess = () => resolve(r.result);
		r.onerror = () => reject(r.error);
	});
	const store = db.transaction('FILE_DATA', 'readonly').objectStore('FILE_DATA');
	const keys = await new Promise((resolve) => {
		const r = store.getAllKeys();
		r.onsuccess = () => resolve(r.result);
	});
	const out = {};
	for (const k of keys.filter((k) => String(k).startsWith(dir + '/'))) {
		const rec = await new Promise((resolve) => {
			const r = db.transaction('FILE_DATA', 'readonly').objectStore('FILE_DATA').get(k);
			r.onsuccess = () => resolve(r.result);
		});
		if (rec && rec.contents) out[String(k).slice(dir.length + 1)] = Array.from(rec.contents);
	}
	return out;
}, shots);
for (const [rel, bytes] of Object.entries(files)) {
	fs.mkdirSync(path.dirname(path.join(out, rel)), { recursive: true });
	fs.writeFileSync(path.join(out, rel), Buffer.from(bytes));
}
record.files = Object.keys(files).length;
fs.writeFileSync(path.join(out, 'browser.json'), JSON.stringify(record, null, '\t'));
fs.writeFileSync(path.join(out, 'console.log'), consoleLines.join('\n'));
log(`${record.files} files -> ${out}`);
await context.close();
