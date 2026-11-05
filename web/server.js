const http = require('http');
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const PORT = 3000;
const HOST = 'localhost';

// Execute moon run cmd/main with args and return stdout
function moonRun(args) {
  try {
    const cmd = `moon run cmd/main -- ${args}`;
    const stdout = execSync(cmd, {
      encoding: 'utf8',
      timeout: 30000,
      cwd: path.resolve(__dirname, '..')
    });
    return stdout.trim();
  } catch (e) {
    return null;
  }
}

// Parse hex from moon run output (last non-empty line)
function parseHex(output) {
  if (!output) return null;
  const lines = output.split('\n').filter(l => l.trim() && !l.startsWith('#'));
  return lines[lines.length - 1]?.trim() || null;
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

  // Serve static files
  if (req.url === '/' || req.url === '/index.html') {
    const html = fs.readFileSync(path.join(__dirname, 'index.html'), 'utf8');
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    res.end(html);
    return;
  }
  if (req.url === '/camera' || req.url === '/camera.html') {
    const html = fs.readFileSync(path.join(__dirname, 'camera.html'), 'utf8');
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    res.end(html);
    return;
  }

  // API: encode static
  if (req.url === '/api/encode-static' && req.method === 'POST') {
    let body = '';
    req.on('data', chunk => { body += chunk.toString(); });
    req.on('end', () => {
      try {
        const { text, ecl } = JSON.parse(body);
        const output = moonRun(`--text "${text.replace(/"/g, '\\"')}" --encode-static --ecl ${ecl || 'M'} --format hex`);
        const hex = parseHex(output);
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ success: !!hex, hex, output }));
      } catch (e) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: e.message }));
      }
    });
    return;
  }

  // API: decode static
  if (req.url === '/api/decode-static' && req.method === 'POST') {
    let body = '';
    req.on('data', chunk => { body += chunk.toString(); });
    req.on('end', () => {
      try {
        const { hex } = JSON.parse(body);
        const output = moonRun(`--decode-static --hex "${hex}"`);
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ success: !!output, output }));
      } catch (e) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: e.message }));
      }
    });
    return;
  }

  // API: encode dynamic
  if (req.url === '/api/encode-dynamic' && req.method === 'POST') {
    let body = '';
    req.on('data', chunk => { body += chunk.toString(); });
    req.on('end', () => {
      try {
        const { text, frame_size, ecl } = JSON.parse(body);
        const output = moonRun(`--text "${text.replace(/"/g, '\\"')}" --encode-dynamic --frame-size ${frame_size || 50} --ecl ${ecl || 'M'} --format hex`);
        const hex = parseHex(output);
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ success: !!hex, hex, output }));
      } catch (e) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: e.message }));
      }
    });
    return;
  }

  // API: decode dynamic
  if (req.url === '/api/decode-dynamic' && req.method === 'POST') {
    let body = '';
    req.on('data', chunk => { body += chunk.toString(); });
    req.on('end', () => {
      try {
        const { hex } = JSON.parse(body);
        const output = moonRun(`--decode-dynamic --hex "${hex}"`);
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ success: !!output, output }));
      } catch (e) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: e.message }));
      }
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
  console.log('API: /api/encode-static, /api/decode-static, /api/encode-dynamic, /api/decode-dynamic');
});
