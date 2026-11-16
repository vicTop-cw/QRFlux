/// WASM/JS export surface for QRFlux.
/// Thin re-exports of the web bindings with stable export names.
///
/// Build: moon build --target js --release
///        moon build --target wasm-gc --release
///
/// STATUS (2026-11-15): ENABLED. Root cause of the earlier wrong
/// payloads was found with help from moonbitlang/moon#2527: it was an
/// application bug, not a toolchain issue — `digits[i].to_string()` on
/// the js backend formats the UTF-16 code unit ("f" -> "102") because
/// `String[i]` yields a code-unit Int there. Fixed by replacing the
/// indexed lookup with an integer match (`web_hex_digit`).
/// After the fix the js artifact decodes PNG and BMP screenshots
/// end-to-end with correct payloads and is wired into web/camera.html
/// as the primary in-browser decoder (imported from /wasmapi.js,
/// served by web/server.js from this build output).
///
/// wasm-gc note: the artifact's 75 string-constant globals are non-null
/// `(ref extern)`, which the current JS API cannot express; the js
/// backend artifact is the wired one.

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
  @web.web_decode_image(png_b64)
}

///|
/// Decode a QR module matrix supplied as JSON text.
#export_name("qrflux_decode_qr")
pub fn qrflux_decode_qr(matrix_json : String) -> String {
  @web.web_decode_qr(matrix_json)
}
