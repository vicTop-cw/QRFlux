/// WASM/JS export surface for QRFlux.
/// Thin re-exports of the web bindings with stable export names.
///
/// Build: moon build --target js --release
///        moon build --target wasm-gc --release
///
/// STATUS (2026-11-13): exports are configured and verified to appear in
/// the artifact (3 symbols, via `WebAssembly.Module.exports` / ESM
/// `export {...}`). However a long-input decode through this
/// foreign_library build returns wrong bytes on the js backend while the
/// identical logic is correct in normal builds and on native (isolated to
/// cross-package long-string arguments; see memory/2026-11-13.md).
/// The web frontend therefore keeps using the local server API path.

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
