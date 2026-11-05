/// WASM exports for QRFlux web demo.
/// Provides JavaScript bindings for QR encoding and decoding.
/// These functions wrap the web demo functions for WASM target.

///|
/// Encode string to QR code matrix for WASM target.
/// Returns JSON string with QR matrix and metadata.
pub fn wasm_encode_qr(data : String, version : Int32, ecl : String) -> String {
  web_encode_qr(data, version, ecl)
}

///|
/// Encode using static pipeline for WASM target.
pub fn wasm_encode_static(data : String, ecl : String) -> String {
  web_encode_static(data, ecl)
}

///|
/// Encode using dynamic stream pipeline for WASM target.
pub fn wasm_encode_dynamic(
  data : String,
  max_payload : Int32,
  ecl : String,
) -> String {
  web_encode_dynamic(data, max_payload, ecl)
}

///|
/// Decode a QR matrix to raw bytes for WASM target.
pub fn wasm_decode_qr(matrix_json : String) -> String {
  web_decode_qr(matrix_json)
}

///|
/// Get QR capacity info for WASM target.
pub fn wasm_get_capacity(ecl : String, version : Int32) -> String {
  web_get_capacity(ecl, version)
}

///|
/// Calculate frames needed for dynamic stream.
pub fn wasm_calculate_frames(
  data_size : Int32,
  max_payload : Int32,
  compress : Bool,
) -> String {
  let frames = @qr.calculate_frames_needed(data_size, max_payload, compress)
  "{" +
  "\"data_size\":" +
  data_size.to_string() +
  "," +
  "\"max_payload\":" +
  max_payload.to_string() +
  "," +
  "\"frames_needed\":" +
  frames.to_string() +
  "," +
  "\"compressed\":" +
  (if compress { "true" } else { "false" }) +
  "}"
}
