/// Web demo: QR code encoding/decoding for JavaScript target.
/// Exposes QR encoding and decoding functions to JavaScript via pub fn.

///|
/// Convert a MoonBit String to UTF-8 bytes (FixedArray[Int32], each 0~255).
fn utf8_to_bytes(s : String) -> FixedArray[Int32] {
  let arr : Array[Int32] = []
  let chars = s.to_array()
  for i = 0; i < chars.length(); i = i + 1 {
    let cp = chars[i].to_int()
    if cp < 0x80 {
      arr.push(cp)
    } else if cp < 0x800 {
      arr.push(0xc0 | (cp >> 6))
      arr.push(0x80 | (cp & 0x3f))
    } else if cp < 0x10000 {
      arr.push(0xe0 | (cp >> 12))
      arr.push(0x80 | ((cp >> 6) & 0x3f))
      arr.push(0x80 | (cp & 0x3f))
    } else {
      arr.push(0xf0 | (cp >> 18))
      arr.push(0x80 | ((cp >> 12) & 0x3f))
      arr.push(0x80 | ((cp >> 6) & 0x3f))
      arr.push(0x80 | (cp & 0x3f))
    }
  }
  let data = FixedArray::make(arr.length(), 0)
  for i = 0; i < arr.length(); i = i + 1 {
    data[i] = arr[i]
  }
  data
}

///|
/// Hex digit (0~15) to char string.
fn hex_digit(d : Int32) -> String {
  if d < 10 {
    (d + 0x30).unsafe_to_char().to_string()
  } else {
    (d + 0x57).unsafe_to_char().to_string()
  }
}

///|
/// Convert a byte array to a display string (printable ASCII or hex).
fn bytes_to_display(bytes : FixedArray[Int32]) -> String {
  let mut all_printable = true
  for i = 0; i < bytes.length(); i = i + 1 {
    let b = bytes[i]
    if b < 0x20 || b > 0x7e {
      all_printable = false
      break
    }
  }
  if all_printable {
    let mut s = ""
    for i = 0; i < bytes.length(); i = i + 1 {
      s = s + bytes[i].unsafe_to_char().to_string()
    }
    s
  } else {
    let mut s = ""
    for i = 0; i < bytes.length(); i = i + 1 {
      let b = bytes[i]
      s = s + hex_digit((b >> 4) & 0x0f) + hex_digit(b & 0x0f)
    }
    s
  }
}

///|
/// Parse ECC level name to factory value.
fn ecl_from_name(name : String) -> @qr.EccLevel {
  match name {
    "L" => @qr.ecc_low()
    "M" => @qr.ecc_medium()
    "Q" => @qr.ecc_quartile()
    _ => @qr.ecc_high()
  }
}

///|
/// Build QR matrix JSON from a QrCode.
fn matrix_to_json(qr : @qr.QrCode) -> String {
  let size = qr.size()
  let rows : Array[String] = []
  for y = 0; y < size; y = y + 1 {
    let mut row = ""
    for x = 0; x < size; x = x + 1 {
      row = row + (if qr.get_module(x, y) { "1" } else { "0" })
    }
    rows.push("\"" + row + "\"")
  }
  "{\"version\":" +
  qr.version().to_string() +
  ",\"size\":" +
  size.to_string() +
  ",\"mask\":" +
  qr.mask().to_string() +
  ",\"matrix\":[" +
  rows.join(",") +
  "]}"
}

///|
/// Encode binary data to QR code matrix for web demo.
/// Returns a JSON string with the QR matrix and metadata.
pub fn web_encode_qr(data : String, version : Int32, ecl : String) -> String {
  let bytes = utf8_to_bytes(data)
  let level = ecl_from_name(ecl)
  let qr = @qr.encode_binary(bytes, level, version)
  matrix_to_json(qr)
}

///|
/// Encode data using static pipeline (compress + package + QR).
/// Returns JSON with matrix, algo_id, compressed flag.
pub fn web_encode_static(data : String, ecl : String) -> String {
  let bytes = utf8_to_bytes(data)
  let level = ecl_from_name(ecl)
  match @qr.encode_static(bytes, level, 1) {
    None => "{\"error\":\"data too large for static pipeline\"}"
    Some(r) => {
      let qr = r.qr()
      let base = matrix_to_json(qr)
      // Insert algo and compressed fields before closing brace
      let n = base.length()
      base[:n - 1].to_owned() +
      ",\"algo\":" +
      r.algo_id().to_string() +
      ",\"compressed\":" +
      (if r.compressed() { "true" } else { "false" }) +
      "}"
    }
  }
}

///|
/// Encode data using dynamic stream pipeline (split into frames).
/// Returns JSON array of frame matrices.
pub fn web_encode_dynamic(
  data : String,
  max_payload : Int32,
  ecl : String,
) -> String {
  let bytes = utf8_to_bytes(data)
  let level = ecl_from_name(ecl)
  let frames = @qr.split_into_frames(bytes, max_payload)
  let frame_jsons : Array[String] = []
  for i = 0; i < frames.length(); i = i + 1 {
    let qr = @qr.encode_binary(frames[i], level, 1)
    let size = qr.size()
    let rows : Array[String] = []
    for y = 0; y < size; y = y + 1 {
      let mut row = ""
      for x = 0; x < size; x = x + 1 {
        row = row + (if qr.get_module(x, y) { "1" } else { "0" })
      }
      rows.push("\"" + row + "\"")
    }
    frame_jsons.push(
      "{\"frame_id\":" +
      i.to_string() +
      ",\"version\":" +
      qr.version().to_string() +
      ",\"size\":" +
      size.to_string() +
      ",\"matrix\":[" +
      rows.join(",") +
      "]}",
    )
  }
  "{\"total_frames\":" +
  frames.length().to_string() +
  ",\"frames\":[" +
  frame_jsons.join(",") +
  "]}"
}

///|
/// Decode a QR matrix (0/1 text, one row per line) to raw bytes.
/// Uses the project's self-developed decoder.
/// Returns JSON with decoded data and length.
pub fn web_decode_qr(matrix_text : String) -> String {
  // Parse matrix from text: each line is a row of '0'/'1' characters.
  let rows : Array[FixedArray[Int32]] = []
  let chars = matrix_text.to_array()
  let n = chars.length()
  let mut row_start = 0
  let mut i = 0
  while i <= n {
    if i == n || chars[i].to_int() == 0x0a {
      // newline or end: extract row [row_start, i)
      if i > row_start {
        let row = FixedArray::make(i - row_start, 0)
        for j = row_start; j < i; j = j + 1 {
          row[j - row_start] = if chars[j].to_int() == 0x31 { 1 } else { 0 }
        }
        rows.push(row)
      }
      row_start = i + 1
    }
    i = i + 1
  }
  if rows.length() == 0 {
    return "{\"error\":\"no rows parsed\"}"
  }
  // Build FixedArray[FixedArray[Int32]] for decoder
  let matrix = FixedArray::make(rows.length(), FixedArray::make(0, 0))
  for r = 0; r < rows.length(); r = r + 1 {
    matrix[r] = rows[r]
  }
  match @qr.decode_qr(matrix) {
    None => "{\"error\":\"decode failed\"}"
    Some(bytes) =>
      "{\"data\":\"" +
      bytes_to_display(bytes) +
      "\",\"length\":" +
      bytes.length().to_string() +
      "}"
  }
}

///|
/// Get QR capacity info for web demo.
pub fn web_get_capacity(ecl : String, version : Int32) -> String {
  let level = ecl_from_name(ecl)
  let capacity = @qr.num_data_codewords(version, level)
  "{\"version\":" +
  version.to_string() +
  ",\"ecl\":\"" +
  ecl +
  "\",\"capacity_bytes\":" +
  capacity.to_string() +
  "}"
}
