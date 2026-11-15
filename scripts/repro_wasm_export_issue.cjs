#!/usr/bin/env node
/**
 * Reproduction: build-context dependent behavior.
 *
 * The same source, compiled as a `foreign_library` package for the `js`
 * backend, returns WRONG results, while `moon test --target js` and the
 * native build of the same code are correct.
 *
 * Usage:
 *   moon build --target js
 *   node scripts/repro_wasm_export_issue.cjs
 *
 * Exit code 0 means the artifact behaved correctly (issue not
 * reproduced); exit code 1 means the wrong result was reproduced.
 */
const { spawnSync } = require('child_process');
const { pathToFileURL } = require('url');
const path = require('path');
const fs = require('fs');

const ROOT = path.resolve(__dirname, '..');
const ARTIFACT = path.join(ROOT, '_build/js/debug/build/src/wasmapi/wasmapi.js');
const PAYLOAD = 'Hi';

function runCli(args) {
  const r = spawnSync('moon', ['run', 'cmd/main', '--', ...args], {
    cwd: ROOT,
    encoding: 'utf8',
    maxBuffer: 64 * 1024 * 1024,
  });
  return (r.stdout || '')
    .split('\n')
    .map((s) => s.trim())
    .filter((s) => s && !s.startsWith('#'))[0];
}

(async () => {
  console.log('moon   :', spawnSync('moon', ['version'], { encoding: 'utf8' }).stdout.trim());
  console.log('node   :', process.version);
  console.log('payload:', JSON.stringify(PAYLOAD));

  if (!fs.existsSync(ARTIFACT)) {
    console.error('\nartifact not found:', ARTIFACT);
    console.error('run `moon build --target js` first.');
    process.exit(2);
  }

  // 1) Generate a PNG with the project's own encoder (CLI, native).
  const b64 = runCli(['--text', PAYLOAD, '--format', 'png']);
  if (!b64) {
    console.error('failed to generate a PNG via the CLI');
    process.exit(2);
  }
  console.log('png b64 length:', b64.length);

  // 2) Decode with the foreign_library js artifact.
  const mod = await import(pathToFileURL(ARTIFACT).href + '?repro=' + Date.now());
  const jsRaw = String(mod.qrflux_decode_image_png(b64));
  let jsHex = null;
  let jsError = null;
  try {
    const j = JSON.parse(jsRaw);
    jsHex = j.hex || null;
    jsError = j.error || null;
  } catch (e) {
    jsError = 'non-JSON output: ' + jsRaw.slice(0, 60);
  }

  // 3) Decode the same input with the native CLI (reference).
  const nativeOut = runCli(['--decode-image-b64', b64]);

  const expectedHex = Buffer.from(PAYLOAD, 'utf8').toString('hex');
  console.log('\nexpected payload hex :', expectedHex);
  console.log('native CLI (correct) :', nativeOut, '  hex:', expectedHex);
  console.log('js artifact (foreign):', jsError ? '<ERROR> ' + jsError : jsHex);

  const jsOk = jsHex === expectedHex;
  const nativeOk = nativeOut === PAYLOAD;
  console.log('\nnative:', nativeOk ? 'OK' : 'WRONG', '| js artifact:', jsOk ? 'OK' : 'WRONG');

  if (!nativeOk) {
    console.error('reference (native) itself failed — environment problem, not the reported issue');
    process.exit(2);
  }
  if (jsOk) {
    console.log('not reproduced');
    process.exit(0);
  }
  console.log(
    '\nREPRODUCED: the js foreign_library artifact returns wrong payload bytes\n' +
    'while the identical logic passes `moon test --target js` and is correct on native.'
  );
  process.exit(1);
})().catch((e) => {
  console.error('unexpected error:', e.message);
  process.exit(2);
});
