import { createServer } from 'node:http';
import { readFile, stat } from 'node:fs/promises';
import { createReadStream } from 'node:fs';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { resolve, extname, sep } from 'node:path';

const root = resolve(fileURLToPath(new URL('../', import.meta.url)));
const types = { '.html': 'text/html; charset=utf-8', '.css': 'text/css; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.svg': 'image/svg+xml', '.png': 'image/png', '.json': 'application/json', '.jpg': 'image/jpeg', '.mp4': 'video/mp4', '.vtt': 'text/vtt; charset=utf-8' };

export function makeServer() {
  return createServer(async (req, res) => {
    try {
      const pathname = decodeURIComponent(new URL(req.url, 'http://localhost').pathname);
      const path = resolve(root, '.' + (pathname.endsWith('/') ? pathname + 'index.html' : pathname));
      if (!path.startsWith(root + sep) || /\/(tooling|node_modules)\//.test(path) || !types[extname(path)]) {
        res.writeHead(404); res.end('Not found'); return;
      }
      if (extname(path) === '.mp4') {
        const { size } = await stat(path);
        let start = 0, end = size - 1;
        const range = req.headers.range;
        if (range) {
          const match = /^bytes=(\d*)-(\d*)$/.exec(range);
          if (!match || (!match[1] && !match[2])) {
            res.writeHead(416, { 'Content-Range': `bytes */${size}` }); res.end(); return;
          }
          if (!match[1]) start = Math.max(0, size - Number(match[2]));
          else { start = Number(match[1]); if (match[2]) end = Math.min(end, Number(match[2])); }
          if (!Number.isSafeInteger(start) || !Number.isSafeInteger(end) || start > end || start >= size) {
            res.writeHead(416, { 'Content-Range': `bytes */${size}` }); res.end(); return;
          }
        }
        res.writeHead(range ? 206 : 200, {
          'Content-Type': 'video/mp4', 'X-Content-Type-Options': 'nosniff',
          'Accept-Ranges': 'bytes', 'Content-Length': end - start + 1,
          ...(range ? { 'Content-Range': `bytes ${start}-${end}/${size}` } : {}),
        });
        if (req.method === 'HEAD') { res.end(); return; }
        const stream = createReadStream(path, { start, end });
        stream.on('error', () => res.destroy());
        res.on('close', () => stream.destroy());
        stream.pipe(res); return;
      }
      const data = await readFile(path);
      res.writeHead(200, { 'Content-Type': types[extname(path)], 'X-Content-Type-Options': 'nosniff' });
      res.end(data);
    } catch {
      res.writeHead(404, { 'Content-Type': 'text/plain' }); res.end('Not found');
    }
  });
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  const port = Number(process.env.PORT || 4173);
  makeServer().listen(port, '127.0.0.1', () => process.stdout.write(`MoodDare preview: http://127.0.0.1:${port}\n`));
}
