// DEV ONLY: a localhost server that plays the part of "a host the player named" when testing the web shell's URL import
// (spec #130, #133). Never deployed, 127.0.0.1 only, no dependencies. It serves files from a folder (the .wz files, or a
// .zip) in several behaviours, so the shell's range, whole-file and CORS paths can all be exercised:
//
//   node web/dev/serve_sources.mjs <dir> [--port=8070] [--no-range] [--cors=allow|block] [--origin=<origin>]
//
//   (default)     HTTP Range supported (206), CORS open for any origin, Content-Range/Accept-Ranges/Content-Length
//                 exposed, OPTIONS preflight answered.
//   --no-range    the Range header is ignored: always 200 with the whole body, no Accept-Ranges header.
//   --cors=block  no Access-Control-* headers at all, so the browser refuses to let the page read anything.
//   --origin=X    allow only that origin (default: any, "*").
//
// GET /__stats returns {requests, rangeRequests, bytes, byFile} counted since the start (or since GET /__reset), so a
// test can report round trips and bytes served. Test addresses are always http://127.0.0.1:<port>/..., never a real
// mirror (ADR 0004).
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';

const args = process.argv.slice(2);
const flag = (name, def) => {
	const hit = args.find((a) => a === `--${name}` || a.startsWith(`--${name}=`));
	if (!hit) return def;
	return hit.includes('=') ? hit.slice(hit.indexOf('=') + 1) : true;
};
const dir = path.resolve(args.find((a) => !a.startsWith('--')) || '');
const port = Number(flag('port', 8070));
const noRange = flag('no-range', false) === true;
const cors = flag('cors', 'allow');
const origin = flag('origin', '*');
if (!args.find((a) => !a.startsWith('--')) || !fs.existsSync(dir)) {
	console.error('usage: node web/dev/serve_sources.mjs <dir> [--port=8070] [--no-range] [--cors=allow|block] [--origin=<origin>]');
	process.exit(2);
}

const stats = { requests: 0, rangeRequests: 0, bytes: 0, byFile: {} };
const corsHeaders = cors === 'block' ? {} : {
	'Access-Control-Allow-Origin': origin,
	'Access-Control-Allow-Headers': 'Range, Content-Type',
	'Access-Control-Allow-Methods': 'GET, HEAD, OPTIONS',
	'Access-Control-Expose-Headers': 'Content-Range, Content-Length, Accept-Ranges',
};

http.createServer((req, res) => {
	const url = new URL(req.url, 'http://127.0.0.1');
	if (url.pathname === '/__stats') {
		res.writeHead(200, { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' });
		res.end(JSON.stringify(stats));
		return;
	}
	if (url.pathname === '/__reset') {
		stats.requests = stats.rangeRequests = stats.bytes = 0;
		stats.byFile = {};
		res.writeHead(200, { 'Access-Control-Allow-Origin': '*' });
		res.end('ok');
		return;
	}
	if (req.method === 'OPTIONS') {
		res.writeHead(cors === 'block' ? 405 : 204, corsHeaders);
		res.end();
		return;
	}
	const rel = decodeURIComponent(url.pathname).replace(/^\/+/, '');
	const file = path.resolve(dir, rel);
	if (!(file.startsWith(dir + path.sep)) || !fs.existsSync(file) || !fs.statSync(file).isFile()) {
		res.writeHead(404, Object.assign({ 'Content-Type': 'text/plain' }, corsHeaders));
		res.end('not found');
		return;
	}
	const size = fs.statSync(file).size;
	const headers = Object.assign({ 'Content-Type': 'application/octet-stream', 'Cache-Control': 'no-store' }, corsHeaders);
	if (!noRange) headers['Accept-Ranges'] = 'bytes';
	stats.requests++;
	const m = !noRange && /^bytes=(\d+)-(\d*)$/.exec(req.headers.range || '');
	let start = 0;
	let end = size - 1;
	let status = 200;
	if (m) {
		start = Number(m[1]);
		end = m[2] === '' ? size - 1 : Math.min(Number(m[2]), size - 1);
		if (start >= size || start > end) {
			res.writeHead(416, Object.assign({ 'Content-Range': `bytes */${size}` }, headers));
			res.end();
			return;
		}
		status = 206;
		stats.rangeRequests++;
		headers['Content-Range'] = `bytes ${start}-${end}/${size}`;
	}
	headers['Content-Length'] = end - start + 1;
	res.writeHead(status, headers);
	if (req.method === 'HEAD') {
		res.end();
		return;
	}
	const key = path.basename(file);
	stats.byFile[key] = (stats.byFile[key] || 0) + 1;
	const stream = fs.createReadStream(file, { start, end });
	stream.on('data', (c) => { stats.bytes += c.length; });
	stream.on('error', () => res.destroy());
	res.on('close', () => stream.destroy());
	stream.pipe(res);
}).listen(port, '127.0.0.1', () => {
	console.log(`serving ${dir} at http://127.0.0.1:${port}/ (${noRange ? 'no range' : 'range'}, cors ${cors})`);
});
