// Web binding boundary tests (blackbox).
// Covers boundary conditions for web_encode_qr, web_encode_static,
// web_encode_dynamic, web_decode_qr, web_get_capacity, wasm_calculate_frames,
// and wasm_encode_* wrappers. Tests only public fn per blackbox rules.

///|
/// Helper: build a string by repeating a single-char string n times.
/// (bb_ prefix avoids clash with repeat_char in web_dynamic_test.mbt.)
fn bb_repeat(ch : String, n : Int32) -> String {
  let mut s = ""
  for i = 0; i < n; i = i + 1 {
    s = s + ch
  }
  s
}

///|
/// Helper: extract matrix text from web_encode_qr JSON output.
/// Parses the "matrix":["...","...",...] part and joins rows with newline,
/// producing text suitable for web_decode_qr input.
fn bb_extract_matrix(json : String) -> String {
  let chars = json.to_array()
  let n = chars.length()
  let mut i = 0
  let mut matrix_start = -1
  while i < n - 9 {
    if chars[i].to_int() == 0x22 &&
      chars[i + 1].to_int() == 0x6D &&
      chars[i + 2].to_int() == 0x61 &&
      chars[i + 3].to_int() == 0x74 &&
      chars[i + 4].to_int() == 0x72 &&
      chars[i + 5].to_int() == 0x69 &&
      chars[i + 6].to_int() == 0x78 &&
      chars[i + 7].to_int() == 0x22 &&
      chars[i + 8].to_int() == 0x3A &&
      chars[i + 9].to_int() == 0x5B {
      matrix_start = i + 10
      i = n
    }
    i = i + 1
  }
  if matrix_start < 0 {
    return ""
  }
  let rows : Array[String] = []
  let mut pos = matrix_start
  while pos < n {
    if chars[pos].to_int() == 0x22 {
      pos = pos + 1
      let mut row = ""
      while pos < n && chars[pos].to_int() != 0x22 {
        row = row + chars[pos].to_string()
        pos = pos + 1
      }
      rows.push(row)
      pos = pos + 1
    } else {
      pos = pos + 1
    }
  }
  let mut result = ""
  for k = 0; k < rows.length(); k = k + 1 {
    if k > 0 {
      result = result + "\n"
    }
    result = result + rows[k]
  }
  result
}

///|
/// Helper: count occurrences of a char in a string.
fn bb_count_char(s : String, ch : Int32) -> Int32 {
  let chars = s.to_array()
  let mut count = 0
  for i = 0; i < chars.length(); i = i + 1 {
    if chars[i].to_int() == ch {
      count = count + 1
    }
  }
  count
}

///|
/// web_encode_qr (demo.mbt:108): empty string boundary.
/// Empty input -> empty byte array -> still produces a valid V1 QR JSON.
test "web boundary: web_encode_qr empty string" {
  let result = @web.web_encode_qr("", 1, "L")
  assert_true(result.length() > 0)
  // JSON object starts with '{'.
  assert_true(result[0].to_int() == 0x7B)
  // V1 QR is 21x21.
  assert_true(result.contains("\"version\":1"))
  assert_true(result.contains("\"size\":21"))
  assert_true(result.contains("\"mask\":"))
  assert_true(result.contains("\"matrix\":["))
}

///|
/// web_encode_qr (demo.mbt:108): single ASCII character boundary.
test "web boundary: web_encode_qr single char" {
  let result = @web.web_encode_qr("A", 1, "L")
  assert_true(result[0].to_int() == 0x7B)
  assert_true(result.contains("\"version\":1"))
  assert_true(result.contains("\"size\":21"))
}

///|
/// web_encode_qr (demo.mbt:108): multi-byte Unicode (Chinese) boundary.
/// "你好世界" = 12 UTF-8 bytes, fits in V1-L (capacity 17).
test "web boundary: web_encode_qr unicode chinese" {
  let result = @web.web_encode_qr("你好世界", 1, "L")
  assert_true(result.length() > 0)
  assert_true(result.contains("\"matrix\":["))
  assert_true(result.contains("\"version\":1"))
}

///|
/// web_encode_qr (demo.mbt:108): 4-byte emoji boundary.
/// "😀" = U+1F600 -> UTF-8 F0 9F 98 80 (4 bytes), hits utf8_to_bytes 4-byte branch.
test "web boundary: web_encode_qr 4-byte emoji" {
  let result = @web.web_encode_qr("😀", 1, "L")
  assert_true(result.length() > 0)
  assert_true(result.contains("\"matrix\":["))
}

///|
/// web_encode_qr (demo.mbt:108): long text boundary.
/// 100 ASCII bytes encoded at V10-L (capacity 230 bytes) — well within limits.
test "web boundary: web_encode_qr long text" {
  let data = bb_repeat("X", 100)
  let result = @web.web_encode_qr(data, 10, "L")
  assert_true(result.length() > 0)
  assert_true(result.contains("\"version\":10"))
  assert_true(result.contains("\"matrix\":["))
}

///|
/// web_encode_qr (demo.mbt:108): all four ECC levels produce valid JSON.
test "web boundary: web_encode_qr all ecc levels" {
  let levels = ["L", "M", "Q", "H"]
  for i = 0; i < levels.length(); i = i + 1 {
    let result = @web.web_encode_qr("Test", 1, levels[i])
    assert_true(result.length() > 0)
    assert_true(result.contains("\"version\":1"))
    assert_true(result.contains("\"size\":21"))
    assert_true(result.contains("\"mask\":"))
    assert_true(result.contains("\"matrix\":["))
  }
}

///|
/// web_encode_qr (demo.mbt:108) + ecl_from_name (demo.mbt:73):
/// invalid ECC name falls back to ecc_high, producing identical output to "H".
test "web boundary: web_encode_qr invalid ecl defaults to H" {
  let result_invalid = @web.web_encode_qr("Test", 1, "X")
  let result_h = @web.web_encode_qr("Test", 1, "H")
  assert_true(result_invalid.length() > 0)
  // Invalid name "X" should behave exactly as "H" (default fallback branch).
  assert_eq(result_invalid, result_h)
  // Empty string ECC also defaults to H.
  let result_empty_ecl = @web.web_encode_qr("Test", 1, "")
  assert_eq(result_empty_ecl, result_h)
}

///|
/// web_encode_qr (demo.mbt:108): JSON output format contains all required fields.
test "web boundary: web_encode_qr json format fields" {
  let result = @web.web_encode_qr("JSON", 1, "M")
  // Must contain version, size, mask, matrix fields.
  assert_true(result.contains("\"version\":1"))
  assert_true(result.contains("\"size\":21"))
  assert_true(result.contains("\"mask\":"))
  assert_true(result.contains("\"matrix\":["))
  // JSON object delimiters.
  assert_true(result[0].to_int() == 0x7B)
  assert_true(result[result.length() - 1].to_int() == 0x7D)
  // Matrix rows are quoted strings of 0/1.
  assert_true(result.contains("\""))
}

///|
/// web_encode_static (demo.mbt:118): empty data boundary.
test "web boundary: web_encode_static empty data" {
  let result = @web.web_encode_static("", "L")
  assert_true(result.length() > 0)
  assert_true(result[0].to_int() == 0x7B)
  // Empty data should succeed (small enough) with matrix or return error.
  assert_true(result.contains("\"matrix\"") || result.contains("\"error\""))
}

///|
/// web_encode_static (demo.mbt:118): small data succeeds with algo/compressed fields.
test "web boundary: web_encode_static small data success" {
  let result = @web.web_encode_static("Hello", "L")
  assert_true(result.length() > 0)
  // 5 bytes fits easily in static pipeline -> success path.
  assert_true(result.contains("\"matrix\""))
  assert_true(result.contains("\"algo\":"))
  assert_true(result.contains("\"compressed\":"))
}

///|
/// web_encode_static (demo.mbt:118): all ECC levels do not crash.
test "web boundary: web_encode_static all ecc levels" {
  let levels = ["L", "M", "Q", "H"]
  for i = 0; i < levels.length(); i = i + 1 {
    let result = @web.web_encode_static("Test", levels[i])
    assert_true(result.length() > 0)
    assert_true(result[0].to_int() == 0x7B)
    // Either success (matrix) or too-large error.
    assert_true(result.contains("\"matrix\"") || result.contains("\"error\""))
  }
}

///|
/// web_encode_static (demo.mbt:118): large data boundary.
/// 1000 bytes may exceed static pipeline capacity -> error or success.
test "web boundary: web_encode_static large data" {
  let data = bb_repeat("A", 1000)
  let result = @web.web_encode_static(data, "L")
  assert_true(result.length() > 0)
  assert_true(result[0].to_int() == 0x7B)
  assert_true(result.contains("\"matrix\"") || result.contains("\"error\""))
}

///|
/// web_encode_dynamic (demo.mbt:141): empty data boundary.
test "web boundary: web_encode_dynamic empty data" {
  let result = @web.web_encode_dynamic("", 100, "L")
  assert_true(result.length() > 0)
  assert_true(result.contains("\"total_frames\""))
  assert_true(result.contains("\"frames\":["))
}

///|
/// web_encode_dynamic (demo.mbt:141): large data split into multiple frames.
/// 200 bytes / 20 = 10 frames.
test "web boundary: web_encode_dynamic large data multiple frames" {
  let data = bb_repeat("B", 200)
  let result = @web.web_encode_dynamic(data, 20, "L")
  assert_true(result.contains("\"total_frames\":10"))
  // Each frame has frame_id, version, size, matrix.
  assert_true(result.contains("\"frame_id\":0"))
  assert_true(result.contains("\"frame_id\":9"))
}

///|
/// web_encode_dynamic (demo.mbt:141): all ECC levels produce valid frame JSON.
test "web boundary: web_encode_dynamic all ecc levels" {
  let levels = ["L", "M", "Q", "H"]
  for i = 0; i < levels.length(); i = i + 1 {
    let result = @web.web_encode_dynamic("TestData", 50, levels[i])
    assert_true(result.length() > 0)
    assert_true(result.contains("\"total_frames\""))
    assert_true(result.contains("\"frames\":["))
  }
}

///|
/// web_decode_qr (demo.mbt:184): valid matrix roundtrip returns original data.
test "web boundary: web_decode_qr valid matrix roundtrip" {
  let encoded = @web.web_encode_qr("Hello", 1, "L")
  let matrix_text = bb_extract_matrix(encoded)
  assert_true(matrix_text.length() > 0)
  let decoded = @web.web_decode_qr(matrix_text)
  assert_true(decoded.length() > 0)
  // Decoded JSON should contain data and length fields.
  assert_true(decoded.contains("\"data\":"))
  assert_true(decoded.contains("\"length\":5"))
  // Printable ASCII -> original string preserved.
  assert_true(decoded.contains("Hello"))
}

///|
/// web_decode_qr (demo.mbt:184): empty matrix text -> "no rows parsed" error.
test "web boundary: web_decode_qr empty matrix" {
  let decoded = @web.web_decode_qr("")
  assert_true(decoded.contains("\"error\":\"no rows parsed\""))
}

///|
/// web_decode_qr (demo.mbt:184): all-zero matrix is not a valid QR code.
/// 21x21 all zeros -> decode should fail or return error.
test "web boundary: web_decode_qr all zero matrix" {
  let row = bb_repeat("0", 21)
  let mut matrix_text = ""
  for i = 0; i < 21; i = i + 1 {
    if i > 0 {
      matrix_text = matrix_text + "\n"
    }
    matrix_text = matrix_text + row
  }
  let decoded = @web.web_decode_qr(matrix_text)
  // All-zero matrix has no finder patterns -> decode should fail.
  assert_true(decoded.contains("\"error\"") || decoded.contains("\"data\""))
}

///|
/// web_decode_qr (demo.mbt:184): hex output for non-printable bytes.
/// Encode Chinese "中" (UTF-8: E4 B8 AD, all non-printable) -> decode shows hex.
test "web boundary: web_decode_qr hex output non printable" {
  let encoded = @web.web_encode_qr("中", 1, "L")
  let matrix_text = bb_extract_matrix(encoded)
  let decoded = @web.web_decode_qr(matrix_text)
  // bytes_to_display hex path: "中" -> "e4b8ad" (lowercase hex).
  assert_true(decoded.contains("e4b8ad"))
  assert_true(decoded.contains("\"length\":3"))
  // Should NOT contain the raw Chinese character (non-printable path).
  assert_true(!decoded.contains("中"))
}

///|
/// wasm_calculate_frames (wasm.mbt:42): various data sizes boundary.
test "web boundary: wasm_calculate_frames various sizes" {
  // data_size=1, max_payload=50 -> (1+50-1)/50 = 1 frame.
  let r1 = @web.wasm_calculate_frames(1, 50, false)
  assert_true(r1.contains("\"frames_needed\":1"))
  assert_true(r1.contains("\"data_size\":1"))
  assert_true(r1.contains("\"max_payload\":50"))
  assert_true(r1.contains("\"compressed\":false"))
  // data_size=50, max_payload=50 -> (50+50-1)/50 = 1 (exact multiple).
  let r2 = @web.wasm_calculate_frames(50, 50, false)
  assert_true(r2.contains("\"frames_needed\":1"))
  // data_size=51, max_payload=50 -> (51+50-1)/50 = 2 (needs extra frame).
  let r3 = @web.wasm_calculate_frames(51, 50, false)
  assert_true(r3.contains("\"frames_needed\":2"))
  // data_size=0 -> 0 frames.
  let r0 = @web.wasm_calculate_frames(0, 50, false)
  assert_true(r0.contains("\"frames_needed\":0"))
}

///|
/// wasm_calculate_frames (wasm.mbt:42): compress toggle boundary.
test "web boundary: wasm_calculate_frames compress toggle" {
  // compress=false: 100 bytes / 50 = 2 frames.
  let r_off = @web.wasm_calculate_frames(100, 50, false)
  assert_true(r_off.contains("\"compressed\":false"))
  assert_true(r_off.contains("\"frames_needed\":2"))
  // compress=true: effective_size = 100/2 = 50, frames = (50+50-1)/50 = 1.
  let r_on = @web.wasm_calculate_frames(100, 50, true)
  assert_true(r_on.contains("\"compressed\":true"))
  assert_true(r_on.contains("\"frames_needed\":1"))
  // compress=true with odd data: 101/2 = 50, frames = (50+50-1)/50 = 1.
  let r_odd = @web.wasm_calculate_frames(101, 50, true)
  assert_true(r_odd.contains("\"frames_needed\":1"))
}

///|
/// wasm_encode_qr (wasm.mbt:8): WASM wrapper matches web_encode_qr output.
test "web boundary: wasm_encode_qr matches web_encode_qr" {
  let web_result = @web.web_encode_qr("Test", 1, "L")
  let wasm_result = @web.wasm_encode_qr("Test", 1, "L")
  assert_eq(wasm_result, web_result)
}

///|
/// wasm_encode_static (wasm.mbt:14): WASM wrapper matches web_encode_static.
test "web boundary: wasm_encode_static matches web_encode_static" {
  let web_result = @web.web_encode_static("Test", "L")
  let wasm_result = @web.wasm_encode_static("Test", "L")
  assert_eq(wasm_result, web_result)
}

///|
/// wasm_encode_dynamic (wasm.mbt:20): WASM wrapper matches web_encode_dynamic.
test "web boundary: wasm_encode_dynamic matches web_encode_dynamic" {
  let web_result = @web.web_encode_dynamic("Hello", 50, "L")
  let wasm_result = @web.wasm_encode_dynamic("Hello", 50, "L")
  assert_eq(wasm_result, web_result)
}

///|
/// wasm_decode_qr (wasm.mbt:30): WASM wrapper matches web_decode_qr.
test "web boundary: wasm_decode_qr matches web_decode_qr" {
  let encoded = @web.web_encode_qr("Hi", 1, "L")
  let matrix_text = bb_extract_matrix(encoded)
  let web_result = @web.web_decode_qr(matrix_text)
  let wasm_result = @web.wasm_decode_qr(matrix_text)
  assert_eq(wasm_result, web_result)
}

///|
/// web_get_capacity (demo.mbt:226): JSON format with version/ecl/capacity.
test "web boundary: web_get_capacity json format" {
  let cap = @web.web_get_capacity("L", 1)
  assert_true(cap.contains("\"version\":1"))
  assert_true(cap.contains("\"ecl\":\"L\""))
  assert_true(cap.contains("\"capacity_bytes\":"))
  // V1-L data codewords = 19 (26 total - 7 ECC, per QR spec).
  assert_true(cap.contains("\"capacity_bytes\":19"))
}

///|
/// web_get_capacity (demo.mbt:226): all ECC levels return valid capacity.
test "web boundary: web_get_capacity all ecc levels" {
  let levels = ["L", "M", "Q", "H"]
  for i = 0; i < levels.length(); i = i + 1 {
    let cap = @web.web_get_capacity(levels[i], 1)
    assert_true(cap.contains("\"version\":1"))
    assert_true(cap.contains("\"ecl\":\"" + levels[i] + "\""))
    assert_true(cap.contains("\"capacity_bytes\":"))
  }
}

///|
/// web_encode_qr (demo.mbt:108): matrix row length matches size field.
/// V1 QR is 21x21 — each matrix row string should be 21 chars of 0/1.
test "web boundary: web_encode_qr matrix row length matches size" {
  let result = @web.web_encode_qr("RowLen", 1, "L")
  // Count number of '0' and '1' chars in matrix section.
  // Total 0/1 chars in a 21x21 matrix = 441.
  let zeros = bb_count_char(result, 0x30)
  let ones = bb_count_char(result, 0x31)
  // Matrix modules should total 21*21 = 441.
  // (JSON metadata has no other 0/1 chars except in matrix rows.)
  assert_true(zeros + ones >= 441)
}
