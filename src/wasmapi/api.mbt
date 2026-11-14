/// WASM/JS export surface for QRFlux.
/// Thin re-exports of the web bindings with stable export names.
///
/// Build: moon build --target js --release
///        moon build --target wasm-gc --release
///
/// STATUS (2026-11-13): the three symbols below are present in both the
/// wasm-gc and js artifacts (verified via `WebAssembly.Module.exports`
/// and ESM `export {...}`) and are callable from Node.
///
/// They are NOT wired into the web frontend. Reason: decoding a real
/// screenshot through this foreign_library build returns wrong payload
/// bytes on the js backend, while the identical logic is correct under
/// `moon test --target js` and on native. Isolation so far:
///   - base64 decoding inside this package: byte-exact (PNG signature OK)
///   - grayscale dimensions after PNG decode: correct
///   - final payload: wrong (e.g. "RVTw..." instead of "Hi")
/// Non-strings, Buffer writes, bit arithmetic, string traversal and
/// cross-package calls were each verified correct in isolation.
/// Conclusion: a build-context difference in the artifact (toolchain
/// level); see memory/2026-11-13.md for the full elimination table.
/// The frontend therefore keeps using the local server API path.

///|
/// Encode a QR code; returns a JSON envelope with the module matrix.
#export_name("qrflux_encode_qr")
pub fn qrflux_encode_qr(data : String, version : Int32, ecl : String) -> String {
  @web.web_encode_qr(data, version, ecl)
}

///|
/// Decode a QR code from a base64-encoded PNG screenshot.
#export_name("qrflux_decode_image_png")
pub fn qrflux_decode_image_png(png_b64 : String) -> String {
  @web.web_decode_image_png(png_b64)
}

///|
/// Decode a QR module matrix supplied as JSON text.
#export_name("qrflux_decode_qr")
pub fn qrflux_decode_qr(matrix_json : String) -> String {
  @web.web_decode_qr(matrix_json)
}
