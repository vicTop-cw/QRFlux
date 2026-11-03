/// Web demo: QR code encoding for JavaScript target.
/// Exposes QR encoding functions to JavaScript via @export.

///|
/// Encode binary data to QR code matrix for web demo.
/// Returns a JSON string with the QR matrix and metadata.
@export
pub fn web_encode_qr(data : String, version : Int, ecl : String) -> String {
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
  let qr = @qr.encode_binary(data, level, version)
  
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
/// Encode data to QR frames for web demo (dynamic stream protocol).
@export
pub fn web_encode_stream(data : String, max_payload : Int) -> String {
  // Convert string to byte array
  let bytes = FixedArray::make(data.length(), 0)
  for i = 0; i < data.length(); i = i + 1 {
    bytes[i] = data.code_point_at(i).unwrap_or(0)
  }
  
  // Split into frames
  let frames = @qr.split_into_frames(bytes, max_payload)
  
  // Convert frames to JSON
  let mut frame_data = Array::make(0, "")
  for i = 0; i < frames.length(); i = i + 1 {
    let frame = frames[i]
    let mut bytes_str = ""
    for j = 0; j < frame.length(); j = j + 1 {
      if j > 0 { bytes_str = bytes_str + "," }
      bytes_str = bytes_str + frame[j].to_string()
    }
    frame_data.push("[" + bytes_str + "]")
  }
  
  "{" +
    "\"total_frames\":" + frames.length().to_string() + "," +
    "\"frames\":[" + frame_data.join(",") + "]" +
  "}"
}

///|
/// Get QR capacity info for web demo.
@export
pub fn web_get_capacity(ecl : String, version : Int) -> String {
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
