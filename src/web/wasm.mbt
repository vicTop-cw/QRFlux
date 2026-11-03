// WASM exports for QRFlux web demo.
// Provides JavaScript bindings for QR encoding.

///|
/// Encode string to QR code matrix for web demo.
/// Returns JSON string with QR matrix and metadata.
@export
pub fn wasm_encode_qr(data : String, version : Int, ecl : String) -> String {
  // Convert string to byte array
  let bytes = FixedArray::make(data.length(), 0)
  for i = 0; i < data.length(); i = i + 1 {
    bytes[i] = data.code_point_at(i).unwrap_or(0)
  }
  
  // Parse ECC level
  let level = match ecl {
    "L" => @qr.ecc_low()
    "M" => @qr.ecc_medium()
    "Q" => @qr.ecc_quartile()
    _ => @qr.ecc_high()
  }
  
  // Encode
  let qr = @qr.encode_binary(bytes, level, version)
  
  // Convert matrix to JSON
  let size = qr.size()
  let mut rows = Array::make(0, "")
  for y = 0; y < size; y = y + 1 {
    let mut row = ""
    for x = 0; x < size; x = x + 1 {
      row = row + (if qr.get_module(x, y) { "1" } else { "0" })
    }
    rows.push("\"" + row + "\"")
  }
  
  "{" +
    "\"version\":" + qr.version().to_string() + "," +
    "\"size\":" + size.to_string() + "," +
    "\"mask\":" + qr.mask().to_string() + "," +
    "\"matrix\":[" + rows.join(",") + "]" +
  "}"
}

///|
/// Get QR capacity info for web demo.
@export
pub fn wasm_get_capacity(ecl : String, version : Int) -> String {
  let level = match ecl {
    "L" => @qr.ecc_low()
    "M" => @qr.ecc_medium()
    "Q" => @qr.ecc_quartile()
    _ => @qr.ecc_high()
  }
  
  let capacity = @qr.num_data_codewords(version, level)
  
  "{" +
    "\"version\":" + version.to_string() + "," +
    "\"ecl\":\"" + ecl + "\"," +
    "\"capacity_bytes\":" + capacity.to_string() +
  "}"
}

///|
/// Calculate frames needed for dynamic stream.
@export
pub fn wasm_calculate_frames(data_size : Int, max_payload : Int, compress : Bool) -> String {
  let frames = @qr.calculate_frames_needed(data_size, max_payload, compress)
  
  "{" +
    "\"data_size\":" + data_size.to_string() + "," +
    "\"max_payload\":" + max_payload.to_string() + "," +
    "\"frames_needed\":" + frames.to_string() + "," +
    "\"compressed\":" + (if compress { "true" } else { "false" }) +
  "}"
}
