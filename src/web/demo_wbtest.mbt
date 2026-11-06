/// Whitebox tests for demo.mbt internal functions.
/// Directly tests private fn: utf8_to_bytes, bytes_to_display,
/// ecl_from_name, matrix_to_json — covering multi-byte UTF-8 branches,
/// hex display branch, invalid ECC name fallback, and JSON matrix structure.

///|
/// Helper: check if a string contains a substring (wb-local, avoids clash
/// with str_contains defined in web_test.mbt).
fn wb_str_contains(s : String, sub : String) -> Bool {
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
/// Helper: build a FixedArray[Int32] from a literal Array[Int32].
fn wb_mk_bytes(xs : Array[Int32]) -> FixedArray[Int32] {
  let n = xs.length()
  let fa = FixedArray::make(n, 0)
  for i = 0; i < n; i = i + 1 {
    fa[i] = xs[i]
  }
  fa
}

///|
/// utf8_to_bytes (demo.mbt:6): 1-byte ASCII branch (cp < 0x80).
test "demo_wb: utf8_to_bytes ascii 1-byte" {
  // 'A' = U+0041, UTF-8: 0x41 — hits the cp < 0x80 single-byte branch.
  let bytes = utf8_to_bytes("A")
  assert_eq(bytes.length(), 1)
  assert_eq(bytes[0], 0x41)
}

///|
/// utf8_to_bytes (demo.mbt:6): 3-byte Chinese branch (0x800 <= cp < 0x10000).
test "demo_wb: utf8_to_bytes 3-byte chinese" {
  // "中" = U+4E2D, UTF-8: E4 B8 AD — hits the cp < 0x10000 three-byte branch.
  let bytes = utf8_to_bytes("中")
  assert_eq(bytes.length(), 3)
  assert_eq(bytes[0], 0xE4)
  assert_eq(bytes[1], 0xB8)
  assert_eq(bytes[2], 0xAD)
}

///|
/// utf8_to_bytes (demo.mbt:6): 4-byte emoji branch (cp >= 0x10000).
test "demo_wb: utf8_to_bytes 4-byte emoji" {
  // 😀 = U+1F600, UTF-8: F0 9F 98 80 — hits the else four-byte branch.
  let bytes = utf8_to_bytes("😀")
  assert_eq(bytes.length(), 4)
  assert_eq(bytes[0], 0xF0)
  assert_eq(bytes[1], 0x9F)
  assert_eq(bytes[2], 0x98)
  assert_eq(bytes[3], 0x80)
}

///|
/// ecl_from_name (demo.mbt:73): invalid input falls back to ecc_high.
test "demo_wb: ecl_from_name invalid defaults to high" {
  // "X" is not L/M/Q/H — hits the `_ => @qr.ecc_high()` default branch.
  let level = ecl_from_name("X")
  assert_true(level == @qr.ecc_high())
  // Also verify a few more invalid inputs all default to High.
  assert_true(ecl_from_name("") == @qr.ecc_high())
  assert_true(ecl_from_name("l") == @qr.ecc_high())
}

///|
/// ecl_from_name (demo.mbt:73): valid inputs L/M/Q/H map to correct enum.
test "demo_wb: ecl_from_name valid inputs" {
  // Each valid name hits its dedicated match arm.
  assert_true(ecl_from_name("L") == @qr.ecc_low())
  assert_true(ecl_from_name("M") == @qr.ecc_medium())
  assert_true(ecl_from_name("Q") == @qr.ecc_quartile())
  assert_true(ecl_from_name("H") == @qr.ecc_high())
}

///|
/// bytes_to_display (demo.mbt:46): non-printable byte (0x80) triggers hex.
test "demo_wb: bytes_to_display hex branch" {
  // 0x80 is outside [0x20, 0x7e] → all_printable=false → hex path.
  // 0x80 -> "80", 0xE4 -> "e4", 0x41 -> "41" (even though 'A' is printable,
  // the presence of any non-printable byte forces hex for the whole array).
  let bytes = wb_mk_bytes([0x80, 0xE4, 0x41])
  let result = bytes_to_display(bytes)
  assert_eq(result, "80e441")
}

///|
/// bytes_to_display (demo.mbt:46): all printable ASCII → ASCII string.
test "demo_wb: bytes_to_display ascii branch" {
  // All bytes in [0x20, 0x7e]: 0x41='A', 0x42='B', 0x43='C' → ASCII path.
  let bytes = wb_mk_bytes([0x41, 0x42, 0x43])
  let result = bytes_to_display(bytes)
  assert_eq(result, "ABC")
  // Boundary: 0x20 (space) and 0x7e ('~') are the printable extremes.
  let bounds = wb_mk_bytes([0x20, 0x7e])
  assert_eq(bytes_to_display(bounds), " ~")
}

///|
/// matrix_to_json (demo.mbt:84): V1 QR JSON has version/size/mask/matrix.
test "demo_wb: matrix_to_json v1 structure" {
  // Encode a single byte 'A' into a V1-L QR, then serialize via matrix_to_json.
  let data = wb_mk_bytes([0x41])
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let json = matrix_to_json(qr)
  // V1 QR is 21x21.
  assert_true(wb_str_contains(json, "\"version\":1"))
  assert_true(wb_str_contains(json, "\"size\":21"))
  assert_true(wb_str_contains(json, "\"mask\":"))
  assert_true(wb_str_contains(json, "\"matrix\":["))
  // JSON object delimiters.
  assert_true(json[0].to_int() == 0x7B)
  assert_true(json[json.length() - 1].to_int() == 0x7D)
}
