/// Whitebox regression tests for the RS Forney algorithm fix.
/// Before the fix, the Forney formula in rs_correct omitted the error-position
/// factor X_k = alpha^pos, computing error_val = omega/lambda' instead of the
/// correct error_val = (X_k * omega) / lambda'. This caused rs_decode to
/// produce wrong error values for every position where X_k != 1 (i.e. pos != 0),
/// so single-byte errors at pos != 0 were "corrected" to wrong values.
/// These tests verify that rs_decode now corrects errors at ALL positions and
/// up to the full RS correction capacity, by directly calling the private
/// rs_decode function (whitebox, no @qr prefix).

///|
/// Build deterministic test data of length n with a simple linear pattern.
/// Uses a non-trivial pattern so codeword bytes are spread across 0..255.
fn forney_make_data(n : Int32) -> FixedArray[Int32] {
  let result = FixedArray::make(n, 0)
  for i = 0; i < n; i = i + 1 {
    result[i] = (i * 7 + 13) % 256
  }
  result
}

///|
/// Element-wise equality check for two FixedArray[Int32].
fn forney_eq(a : FixedArray[Int32], b : FixedArray[Int32]) -> Bool {
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
/// Build a valid RS codeword [data..., ecc...] using the encoder's
/// rs_compute_divisor / rs_compute_remainder so the resulting codeword
/// has all-zero syndromes (i.e. is a valid RS codeword).
fn forney_build_codeword(
  data : FixedArray[Int32],
  num_ec : Int32,
) -> FixedArray[Int32] {
  let rsdiv = rs_compute_divisor(num_ec)
  let ecc = rs_compute_remainder(data, rsdiv)
  let total = data.length() + num_ec
  let codeword = FixedArray::make(total, 0)
  for i = 0; i < data.length(); i = i + 1 {
    codeword[i] = data[i]
  }
  for i = 0; i < num_ec; i = i + 1 {
    codeword[data.length() + i] = ecc[i]
  }
  codeword
}

///|
/// Copy a FixedArray (helper for corrupting codewords in tests).
fn forney_copy(src : FixedArray[Int32]) -> FixedArray[Int32] {
  let dst = FixedArray::make(src.length(), 0)
  for i = 0; i < src.length(); i = i + 1 {
    dst[i] = src[i]
  }
  dst
}

///|
/// Introduce errors at multiple positions (XOR error_val into each) and
/// verify rs_decode corrects them back to the original. Returns true on
/// success. Used to test multi-byte error correction concisely.
fn forney_correct_multi(
  original : FixedArray[Int32],
  num_ec : Int32,
  positions : Array[Int32],
  error_val : Int32,
) -> Bool {
  let corrupted = forney_copy(original)
  for pos in positions {
    corrupted[pos] = corrupted[pos] ^ error_val
  }
  match rs_decode(corrupted, num_ec) {
    Some(v) => forney_eq(v, original)
    None => false
  }
}

// ==================== Single-byte error correction ====================
// RS(26,20): 20 data + 6 ECC = 26 codewords, corrects up to 3 errors.
// Before the Forney fix, only pos=0 (where X_k=alpha^0=1) was corrected
// correctly; all other positions produced wrong error values.

///|
/// Single error at pos 0: this position worked even before the fix
/// (X_k = alpha^0 = 1), so it serves as a baseline.
test "forney reg: single error at pos 0" {
  let data = forney_make_data(20)
  let original = forney_build_codeword(data, 6)
  let corrupted = forney_copy(original)
  corrupted[0] = corrupted[0] ^ 0x37
  match rs_decode(corrupted, 6) {
    Some(v) => assert_true(forney_eq(v, original))
    None => assert_true(false)
  }
}

///|
/// Single error at pos 1: X_k = alpha^1 = 2 != 1. Before the fix this
/// produced a wrong error value; after the fix it must be corrected.
test "forney reg: single error at pos 1" {
  let data = forney_make_data(20)
  let original = forney_build_codeword(data, 6)
  let corrupted = forney_copy(original)
  corrupted[1] = corrupted[1] ^ 0x37
  match rs_decode(corrupted, 6) {
    Some(v) => assert_true(forney_eq(v, original))
    None => assert_true(false)
  }
}

///|
/// Single error at pos 5: a mid-data position with X_k != 1.
test "forney reg: single error at pos 5" {
  let data = forney_make_data(20)
  let original = forney_build_codeword(data, 6)
  let corrupted = forney_copy(original)
  corrupted[5] = corrupted[5] ^ 0x37
  match rs_decode(corrupted, 6) {
    Some(v) => assert_true(forney_eq(v, original))
    None => assert_true(false)
  }
}

///|
/// Single error at pos 10: another mid-data position.
test "forney reg: single error at pos 10" {
  let data = forney_make_data(20)
  let original = forney_build_codeword(data, 6)
  let corrupted = forney_copy(original)
  corrupted[10] = corrupted[10] ^ 0x37
  match rs_decode(corrupted, 6) {
    Some(v) => assert_true(forney_eq(v, original))
    None => assert_true(false)
  }
}

///|
/// Single error at pos 15: near the data/ECC boundary.
test "forney reg: single error at pos 15" {
  let data = forney_make_data(20)
  let original = forney_build_codeword(data, 6)
  let corrupted = forney_copy(original)
  corrupted[15] = corrupted[15] ^ 0x37
  match rs_decode(corrupted, 6) {
    Some(v) => assert_true(forney_eq(v, original))
    None => assert_true(false)
  }
}

///|
/// Single error at pos 20: first ECC byte (data region ends at 19).
test "forney reg: single error at pos 20" {
  let data = forney_make_data(20)
  let original = forney_build_codeword(data, 6)
  let corrupted = forney_copy(original)
  corrupted[20] = corrupted[20] ^ 0x37
  match rs_decode(corrupted, 6) {
    Some(v) => assert_true(forney_eq(v, original))
    None => assert_true(false)
  }
}

///|
/// Single error at pos 25: last codeword position (ECC region).
test "forney reg: single error at pos 25" {
  let data = forney_make_data(20)
  let original = forney_build_codeword(data, 6)
  let corrupted = forney_copy(original)
  corrupted[25] = corrupted[25] ^ 0x37
  match rs_decode(corrupted, 6) {
    Some(v) => assert_true(forney_eq(v, original))
    None => assert_true(false)
  }
}

///|
/// Single error at every position 0..25: all 26 positions must be corrected.
/// This is the comprehensive regression test for the Forney X_k factor: before
/// the fix, only pos=0 and pos=25 (which maps to internal pos=0) would pass.
test "forney reg: single error all positions" {
  let data = forney_make_data(20)
  let original = forney_build_codeword(data, 6)
  let mut all_ok = true
  for pos = 0; pos < 26; pos = pos + 1 {
    let corrupted = forney_copy(original)
    corrupted[pos] = corrupted[pos] ^ 0x55
    match rs_decode(corrupted, 6) {
      Some(v) => if !forney_eq(v, original) { all_ok = false }
      None => all_ok = false
    }
  }
  assert_true(all_ok)
}

// ==================== Multi-byte error correction ====================

///|
/// Two errors correctable: RS(26,20) with 6 ECC corrects up to 3 errors.
/// Two errors at pos 3 and 17 must be corrected.
test "forney reg: two errors correctable" {
  let data = forney_make_data(20)
  let original = forney_build_codeword(data, 6)
  assert_true(forney_correct_multi(original, 6, [3, 17], 0x42))
}

///|
/// Five errors correctable: 12 ECC corrects up to 6 errors.
/// Uses 14 data + 12 ECC = 26 codewords, with 5 errors spread across.
test "forney reg: five errors correctable" {
  let data = forney_make_data(14)
  let original = forney_build_codeword(data, 12)
  assert_true(forney_correct_multi(original, 12, [1, 4, 8, 13, 20], 0x37))
}

///|
/// Ten errors correctable: 20 ECC corrects up to 10 errors (maximum capacity).
/// Uses 6 data + 20 ECC = 26 codewords, with 10 errors at spread positions.
/// This exercises the Forney formula at the full correction boundary.
test "forney reg: ten errors correctable" {
  let data = forney_make_data(6)
  let original = forney_build_codeword(data, 20)
  assert_true(
    forney_correct_multi(
      original,
      20,
      [0, 3, 6, 9, 12, 15, 18, 21, 24, 25],
      0x5A,
    ),
  )
}

///|
/// Different error values (0x01, 0x37, 0xFF) at various positions.
/// Verifies the Forney formula handles the full range of error magnitudes,
/// including the smallest (0x01) and largest (0xFF) nonzero field elements.
test "forney reg: different error values" {
  let data = forney_make_data(20)
  let original = forney_build_codeword(data, 6)
  // 0x01 at pos 2
  let c1 = forney_copy(original)
  c1[2] = c1[2] ^ 0x01
  match rs_decode(c1, 6) {
    Some(v) => assert_true(forney_eq(v, original))
    None => assert_true(false)
  }
  // 0x37 at pos 10
  let c2 = forney_copy(original)
  c2[10] = c2[10] ^ 0x37
  match rs_decode(c2, 6) {
    Some(v) => assert_true(forney_eq(v, original))
    None => assert_true(false)
  }
  // 0xFF at pos 20
  let c3 = forney_copy(original)
  c3[20] = c3[20] ^ 0xFF
  match rs_decode(c3, 6) {
    Some(v) => assert_true(forney_eq(v, original))
    None => assert_true(false)
  }
}

// ==================== Boundary cases ====================

///|
/// No error: rs_decode returns a codeword equal to the original.
test "forney reg: no error returns original" {
  let data = forney_make_data(20)
  let original = forney_build_codeword(data, 6)
  match rs_decode(original, 6) {
    Some(v) => assert_true(forney_eq(v, original))
    None => assert_true(false)
  }
}

///|
/// Different RS parameters: RS(10,4) with 4 ECC and 6 data bytes.
/// Corrects up to 2 errors; we introduce 1 error at pos 7 (ECC region).
test "forney reg: different rs parameters" {
  let data = forney_make_data(6)
  let original = forney_build_codeword(data, 4)
  let corrupted = forney_copy(original)
  corrupted[7] = corrupted[7] ^ 0x73
  match rs_decode(corrupted, 4) {
    Some(v) => assert_true(forney_eq(v, original))
    None => assert_true(false)
  }
}

///|
/// Error in data region vs ECC region: both must be corrected.
/// RS(26,20): data occupies pos 0..19, ECC occupies pos 20..25.
test "forney reg: error in data vs ecc region" {
  let data = forney_make_data(20)
  let original = forney_build_codeword(data, 6)
  // Error in data region (pos 5)
  let c1 = forney_copy(original)
  c1[5] = c1[5] ^ 0x44
  match rs_decode(c1, 6) {
    Some(v) => assert_true(forney_eq(v, original))
    None => assert_true(false)
  }
  // Error in ECC region (pos 23 = data.length() + 3)
  let c2 = forney_copy(original)
  c2[23] = c2[23] ^ 0x44
  match rs_decode(c2, 6) {
    Some(v) => assert_true(forney_eq(v, original))
    None => assert_true(false)
  }
}
