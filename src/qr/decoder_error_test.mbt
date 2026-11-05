// Decoder error path tests.
// Tests decode_qr, decode_from_qrcode, decode_static on invalid/corrupted inputs.
// Focus: ensure error paths return None or tolerate corruption without crashing.

///|
/// Helper: build an Int32 matrix of given size filled with a constant value.
/// Each row is an independent FixedArray (no shared references).
fn dec_err_make_matrix_const(
  size : Int32,
  value : Int32,
) -> FixedArray[FixedArray[Int32]] {
  let matrix = FixedArray::make(size, FixedArray::make(0, 0))
  for y = 0; y < size; y = y + 1 {
    matrix[y] = FixedArray::make(size, value)
  }
  matrix
}

///|
/// Helper: build an Int32 matrix of given size filled with pseudo-random 0/1.
fn dec_err_make_matrix_random(
  size : Int32,
  seed : Int32,
) -> FixedArray[FixedArray[Int32]] {
  let matrix = FixedArray::make(size, FixedArray::make(0, 0))
  let mut s = seed
  for y = 0; y < size; y = y + 1 {
    let row = FixedArray::make(size, 0)
    for x = 0; x < size; x = x + 1 {
      s = (s * 1103515245 + 12345) & 0x7FFFFFFF
      row[x] = (s >> 16) & 1
    }
    matrix[y] = row
  }
  matrix
}

///|
/// Helper: convert a QrCode's Bool modules to an Int32 matrix.
fn dec_err_qrcode_to_matrix(qr : @qr.QrCode) -> FixedArray[FixedArray[Int32]] {
  let size = qr.size()
  let matrix = FixedArray::make(size, FixedArray::make(0, 0))
  for y = 0; y < size; y = y + 1 {
    let row = FixedArray::make(size, 0)
    for x = 0; x < size; x = x + 1 {
      row[x] = if qr.get_module(x, y) { 1 } else { 0 }
    }
    matrix[y] = row
  }
  matrix
}

///|
/// Helper: check two FixedArray[Int32] equal.
fn dec_err_bytes_eq(a : FixedArray[Int32], b : FixedArray[Int32]) -> Bool {
  if a.length() != b.length() {
    return false
  }
  for i = 0; i < a.length(); i = i + 1 {
    if a[i] != b[i] {
      return false
    }
  }
  true
}

///|
test "decoder error: decode_qr empty matrix" {
  // 0x0 matrix: size < 21, should return None.
  let matrix = FixedArray::make(0, FixedArray::make(0, 0))
  let result = @qr.decode_qr(matrix)
  assert_true(result is None)
}

///|
test "decoder error: decode_qr wrong size" {
  // Size 22 is not a valid QR size (valid: 21, 25, 29, ...).
  let matrix = dec_err_make_matrix_const(22, 0)
  let result = @qr.decode_qr(matrix)
  assert_true(result is None)
}

///|
test "decoder error: decode_qr all zeros" {
  // 21x21 all-white matrix. Format info all zero -> likely None.
  // Just verify no crash.
  let matrix = dec_err_make_matrix_const(21, 0)
  let result = @qr.decode_qr(matrix)
  let _ = result
}

///|
test "decoder error: decode_qr all ones" {
  // 21x21 all-black matrix. Verify no crash.
  let matrix = dec_err_make_matrix_const(21, 1)
  let result = @qr.decode_qr(matrix)
  let _ = result
}

///|
test "decoder error: decode_qr random noise" {
  // 21x21 random noise. Verify no crash.
  let matrix = dec_err_make_matrix_random(21, 42)
  let result = @qr.decode_qr(matrix)
  let _ = result
}

///|
test "decoder error: decode_qr corrupted finder" {
  // Encode valid data, then corrupt the finder pattern (top-left).
  let data = FixedArray::make(5, 0x42)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let matrix = dec_err_qrcode_to_matrix(qr)
  // Corrupt finder pattern: flip modules in the top-left 7x7 area.
  matrix[0][0] = 1 - matrix[0][0]
  matrix[0][1] = 1 - matrix[0][1]
  matrix[1][0] = 1 - matrix[1][0]
  matrix[3][3] = 1 - matrix[3][3]
  let result = @qr.decode_qr(matrix)
  let _ = result
}

///|
test "decoder error: decode_qr corrupted format" {
  // Encode valid data, then corrupt format info area.
  let data = FixedArray::make(5, 0x42)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let matrix = dec_err_qrcode_to_matrix(qr)
  // Corrupt format info bits around top-left finder.
  // Format info is at (8,0), (8,1), ..., (8,5), (7,8), (8,8), (8,7), (8,5..0).
  matrix[0][8] = 1 - matrix[0][8]
  matrix[1][8] = 1 - matrix[1][8]
  matrix[2][8] = 1 - matrix[2][8]
  matrix[3][8] = 1 - matrix[3][8]
  matrix[4][8] = 1 - matrix[4][8]
  matrix[5][8] = 1 - matrix[5][8]
  matrix[7][8] = 1 - matrix[7][8]
  matrix[8][8] = 1 - matrix[8][8]
  matrix[8][7] = 1 - matrix[8][7]
  let result = @qr.decode_qr(matrix)
  let _ = result
}

///|
test "decoder error: decode_static invalid input" {
  // Random bytes that don't form a valid package header.
  let data = FixedArray::make(50, 0)
  let mut s = 12345
  for i = 0; i < 50; i = i + 1 {
    s = (s * 1103515245 + 12345) & 0x7FFFFFFF
    data[i] = (s >> 16) & 0xFF
  }
  let result = @qr.decode_static(data)
  // Invalid magic/version -> None.
  assert_true(result is None)
}

///|
test "decoder error: decode_static empty" {
  // Empty array: length < 32 -> None.
  let data = FixedArray::make(0, 0)
  let result = @qr.decode_static(data)
  assert_true(result is None)
}

///|
test "decoder error: decode_from_qrcode valid" {
  // Encode then decode should return original data.
  let data = FixedArray::make(10, 0)
  for i = 0; i < 10; i = i + 1 {
    data[i] = 0x30 + i
  }
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let decoded = @qr.decode_from_qrcode(qr)
  match decoded {
    Some(d) => assert_true(dec_err_bytes_eq(d, data))
    None => abort("decode_from_qrcode valid returned None")
  }
}

///|
test "decoder error: decode_from_qrcode corrupted" {
  // Encode valid data, then corrupt a data module and decode.
  // With ECC, small corruption may still decode correctly or return None.
  let data = FixedArray::make(10, 0x42)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  // Corrupt one module in the data area (avoid function patterns).
  // Module at (10, 10) is typically a data module for V1.
  qr.modules[10][10] = !qr.modules[10][10]
  let decoded = @qr.decode_from_qrcode(qr)
  // With ECC this may still decode correctly, or return None.
  // Just verify no crash.
  let _ = decoded
}
