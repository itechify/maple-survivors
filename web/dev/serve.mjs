// DEV ONLY: a localhost static file server for testing the web export (spec #130). Never deployed.
//
//   node web/dev/serve.mjs <export dir> [port]      (default port 8060)
//
// Serves the export folder at / and this web/dev/ folder at /dev/ (the cache injection page, dev/inject.html; files
// not found there fall back to web/, so /dev/idbfs.js works as before), on 127.0.0.1 only, with the MIME types Godot's web export needs (application/wasm for streaming compilation) and
// no caching, so a fresh export is always picked up. No dependencies beyond Node.
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const exportDir = path.resolve(process.argv[2] || '');
const port = Number(process.argv[3] || 8060);
const devDir = path.dirname(fileURLToPath(import.meta.url));
const webDir = path.resolve(devDir, '..');
if (!process.argv[2] || !fs.existsSync(path.join(exportDir, 'index.html'))) {
	console.error(`usage: node web/dev/serve.mjs <export dir containing index.html> [port]`);
	process.exit(2);
}

const MIME = {
	'.html': 'text/html; charset=utf-8',
	'.css': 'text/css; charset=utf-8',
	'.js': 'text/javascript; charset=utf-8',
	'.mjs': 'text/javascript; charset=utf-8',
	'.wasm': 'application/wasm',
	'.pck': 'application/octet-stream',
	'.png': 'image/png',
	'.svg': 'image/svg+xml',
	'.json': 'application/json; charset=utf-8',
	'.ico': 'image/x-icon',
	'.zip': 'application/zip',
};

function resolve(urlPath) {
	const rel = decodeURIComponent(urlPath.split('?')[0]);
	const [root, sub] = rel.startsWith('/dev/') ? [devDir, rel.slice('/dev/'.length)] : [exportDir, rel.slice(1)];
	const inside = (r, f) => f.startsWith(r + path.sep) || f === r;
	let file = path.resolve(root, sub || 'index.html');
	if (root === devDir && !fs.existsSync(file)) file = path.resolve(webDir, sub); // release files seen from /dev/
	const allowed = inside(root, file) || (root === devDir && inside(webDir, file));
	return allowed ? file : null;
}

http.createServer((req, res) => {
	const file = resolve(req.url);
	if (!file || !fs.existsSync(file) || !fs.statSync(file).isFile()) {
		res.writeHead(404, { 'Content-Type': 'text/plain' });
		res.end('not found');
		return;
	}
	res.writeHead(200, {
		'Content-Type': MIME[path.extname(file).toLowerCase()] || 'application/octet-stream',
		'Content-Length': fs.statSync(file).size,
		'Cache-Control': 'no-cache',
	});
	if (req.method === 'HEAD') {
		res.end();
		return;
	}
	fs.createReadStream(file).pipe(res);
}).listen(port, '127.0.0.1', () => {
	console.log(`serving ${exportDir} at http://127.0.0.1:${port}/ and ${devDir} at /dev/`);
});
