const http = require('http');
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

const PORT = 3000;
const HOST = 'localhost';
const ROOT = path.resolve(__dirname, '..');

// Execute the moon CLI with an argv array. spawnSync passes argv directly
// to CreateProcess (no cmd.exe), avoiding the ~8 KB shell command-line
// limit that silently breaks long base64 arguments.
function moonRun(args) {
  const r = spawnSync('moon', ['run', 'cmd/main', '--', ...args], {
    encoding: 'utf8',
    timeout: 60000,
    maxBuffer: 64 * 1024 * 1024,
    cwd: ROOT,
  });
  if (r.error || r.status !== 0) return null;
  return (r.stdout || '').trim();
}

// Parse the payload line from CLI output (skip '#' comment lines).
function parseLastDataLine(output) {
  if (!output) return null;
  const lines = output
    .split('\n')
    .map((l) => l.trim())
    .filter((l) => l && !l.startsWith('#'));
  return lines.length ? lines[lines.length - 1] : null;
}

// Upper bound for base64 image payloads. Windows CreateProcess caps the
// whole command line at ~32 KB; leave headroom for the argument prefix.
const MAX_B64 = 30000;

function readBody(req, cb) {
  let body = '';
  req.on('data', (c) => { body += c.toString(); });
  req.on('end', () => cb(body));
}

function json(res, code, obj) {
  res.writeHead(code, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(obj));
}

const server = http.createServer((req, res) => {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    res.writeHead(200);
    res.end();
    return;
  }

  // Static pages
  if (req.url === '/' || req.url === '/index.html') {
    try {
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
      res.end(fs.readFileSync(path.join(__dirname, 'index.html'), 'utf8'));
    } catch (e) {
      res.writeHead(500, { 'Content-Type': 'text/plain' });
      res.end('index.html not found');
    }
    return;
  }
  if (req.url === '/camera' || req.url === '/camera.html') {
    try {
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
      res.end(fs.readFileSync(path.join(__dirname, 'camera.html'), 'utf8'));
    } catch (e) {
      res.writeHead(500, { 'Content-Type': 'text/plain' });
      res.end('camera.html not found');
    }
    return;
  }

  if (req.method === 'POST' && req.url === '/api/encode-static') {
    readBody(req, (body) => {
      try {
        const { text, ecl } = JSON.parse(body);
        const out = moonRun(['--text', text, '--encode-static', '--ecl', ecl || 'M', '--format', 'hex']);
        json(res, 200, { success: !!out, hex: parseLastDataLine(out), output: out });
      } catch (e) { json(res, 400, { error: e.message }); }
    });
    return;
  }

  if (req.method === 'POST' && req.url === '/api/decode-static') {
    readBody(req, (body) => {
      try {
        const { hex } = JSON.parse(body);
        const out = moonRun(['--decode-static', '--hex', hex]);
        json(res, 200, { success: !!out, output: out });
      } catch (e) { json(res, 400, { error: e.message }); }
    });
    return;
  }

  if (req.method === 'POST' && req.url === '/api/encode-dynamic') {
    readBody(req, (body) => {
      try {
        const { text, frame_size, ecl } = JSON.parse(body);
        const out = moonRun([
          '--text', text, '--encode-dynamic',
          '--frame-size', String(frame_size || 50),
          '--ecl', ecl || 'M', '--format', 'hex',
        ]);
        json(res, 200, { success: !!out, hex: parseLastDataLine(out), output: out });
      } catch (e) { json(res, 400, { error: e.message }); }
    });
    return;
  }

  if (req.method === 'POST' && req.url === '/api/decode-dynamic') {
    readBody(req, (body) => {
      try {
        const { hex } = JSON.parse(body);
        const out = moonRun(['--decode-dynamic', '--hex', hex]);
        json(res, 200, { success: !!out, output: out });
      } catch (e) { json(res, 400, { error: e.message }); }
    });
    return;
  }

  // Self-implemented image decode: base64 PNG -> PNG decode -> Otsu ->
  // finder locate -> resample -> payload.
  if (req.method === 'POST' && req.url === '/api/decode-image') {
    readBody(req, (body) => {
      try {
        const { image } = JSON.parse(body);
        const b64 = String(image || '').replace(/^data:image\/\w+;base64,/, '');
        if (!b64) return json(res, 400, { error: 'missing image' });
        if (b64.length > MAX_B64) {
          return json(res, 200, {
            success: false,
            error: 'image too large for CLI argument transport (' + b64.length +
              ' chars, max ' + MAX_B64 + '); crop or zoom in on the QR region',
          });
        }
        const out = moonRun(['--decode-image-b64', b64]);
        const failed = !out || /^Error/.test(out.trim());
        json(res, 200, {
          success: !failed,
          decoded: failed ? '' : parseLastDataLine(out),
          output: out,
        });
      } catch (e) { json(res, 400, { error: e.message }); }
    });
    return;
  }

  res.writeHead(404, { 'Content-Type': 'text/plain' });
  res.end('Not Found');
});

server.listen(PORT, HOST, () => {
  console.log(`QRFlux server running at http://${HOST}:${PORT}/`);
  console.log(`  主页: http://${HOST}:${PORT}/`);
  console.log(`  摄像头: http://${HOST}:${PORT}/camera`);
  console.log('API: /api/encode-static, /api/decode-static, /api/encode-dynamic, /api/decode-dynamic, /api/decode-image');
});
