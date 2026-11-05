// Web package tests.
// Tests utf8_to_bytes, hex_digit, bytes_to_display (indirectly via public API),
// and public web functions directly.

///|
/// Helper: check if a string contains a substring.
fn str_contains(s : String, sub : String) -> Bool {
  let s_chars = s.to_array()
  let sub_chars = sub.to_array()
  let n = s_chars.length()
  let m = sub_chars.length()
  if m == 0 {
    return true
  }
  if m > n {
    return false
  }
  for i = 0; i <= n - m; i = i + 1 {
    let mut ok = true
    for j = 0; j < m; j = j + 1 {
      if s_chars[i + j] != sub_chars[j] {
        ok = false
      }
    }
    if ok {
      return true
    }
  }
  false
}

///|
/// Helper: extract matrix text from web_encode_qr JSON output.
/// Parses the "matrix":["...","...",...] part and joins rows with newline,
/// producing text suitable for web_decode_qr input.
fn extract_matrix_text(json : String) -> String {
  let chars = json.to_array()
  let n = chars.length()
  // Find "matrix":[
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
  // Extract rows: each row is "..." separated by commas.
  let rows : Array[String] = []
  let mut pos = matrix_start
  while pos < n {
    if chars[pos].to_int() == 0x22 {
      // Start of quoted string
      pos = pos + 1
      let mut row = ""
      while pos < n && chars[pos].to_int() != 0x22 {
        row = row + chars[pos].to_string()
        pos = pos + 1
      }
      rows.push(row)
      pos = pos + 1 // skip closing "
    } else {
      pos = pos + 1
    }
  }
  // Join rows with newline.
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
test "web: utf8 ascii" {
  // Pure ASCII string encodes to one byte per char (0~127).
  // Verify via web_encode_qr producing valid JSON output.
  let result = @web.web_encode_qr("Hello", 1, "L")
  assert_true(result.length() > 0)
  // Should be a JSON object starting with '{'.
  assert_true(result[0].to_int() == 0x7B)
  // Should contain "version" field.
  assert_true(str_contains(result, "version"))
}

///|
test "web: utf8 chinese" {
  // Chinese characters -> multi-byte UTF-8, should still encode successfully.
  let result = @web.web_encode_qr("中", 1, "L")
  assert_true(result.length() > 0)
  // Should contain "matrix" field.
  assert_true(str_contains(result, "matrix"))
}

///|
test "web: utf8 empty" {
  // Empty string -> empty byte array, should still produce a valid QR.
  let result = @web.web_encode_qr("", 1, "L")
  assert_true(result.length() > 0)
  assert_true(str_contains(result, "version"))
}

///|
test "web: hex_digit 0-9" {
  // hex_digit is used by bytes_to_display for non-printable bytes.
  // Test indirectly: encode "AB" (printable), decode, verify output.
  let encoded = @web.web_encode_qr("AB", 1, "L")
  let matrix_text = extract_matrix_text(encoded)
  let decoded = @web.web_decode_qr(matrix_text)
  // Decoded JSON should contain "AB" (printable -> original string).
  assert_true(str_contains(decoded, "AB"))
}

///|
test "web: hex_digit 10-15" {
  // Verify hex_digit produces lowercase a-f for values 10-15.
  // Encode "中" (UTF-8: 0xE4 0xB8 0xAD, all > 0x7E non-printable).
  // bytes_to_display should produce hex "e4b8ad" using hex_digit.
  let encoded = @web.web_encode_qr("中", 1, "L")
  let matrix_text = extract_matrix_text(encoded)
  let decoded = @web.web_decode_qr(matrix_text)
  // The decoded data should be hex "e4b8ad" (lowercase, uses hex_digit(14)=e,
  // hex_digit(11)=b, hex_digit(8)=8, hex_digit(10)=a, hex_digit(13)=d).
  assert_true(str_contains(decoded, "e4b8ad"))
}

///|
test "web: bytes_to_display printable" {
  // Printable ASCII bytes -> original string in decode output.
  let encoded = @web.web_encode_qr("Hello", 1, "L")
  let matrix_text = extract_matrix_text(encoded)
  let decoded = @web.web_decode_qr(matrix_text)
  // The decoded data should contain "Hello" (printable -> as-is).
  assert_true(str_contains(decoded, "Hello"))
}

///|
test "web: bytes_to_display non-printable" {
  // Non-printable bytes -> hex representation in decode output.
  // "中" = 0xE4 0xB8 0xAD, all > 0x7E so bytes_to_display uses hex.
  let encoded = @web.web_encode_qr("中", 1, "L")
  let matrix_text = extract_matrix_text(encoded)
  let decoded = @web.web_decode_qr(matrix_text)
  // The decoded data should be hex "e4b8ad" (lowercase).
  assert_true(str_contains(decoded, "e4b8ad"))
  // Should NOT contain the raw Chinese character (non-printable path).
  assert_true(!str_contains(decoded, "中"))
}

///|
test "web: web encode produces output" {
  // web_encode_qr should return a non-empty JSON string with matrix data.
  let result = @web.web_encode_qr("Test123", 1, "M")
  assert_true(result.length() > 0)
  // Verify JSON structure: contains "version", "size", "matrix".
  assert_true(str_contains(result, "version"))
  assert_true(str_contains(result, "size"))
  assert_true(str_contains(result, "matrix"))
  // Also test web_encode_static.
  let static_result = @web.web_encode_static("Test123", "L")
  assert_true(static_result.length() > 0)
  // Also test web_get_capacity.
  let cap = @web.web_get_capacity("L", 1)
  assert_true(str_contains(cap, "capacity_bytes"))
}
