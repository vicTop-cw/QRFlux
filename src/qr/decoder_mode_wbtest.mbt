/// Whitebox tests for decode_segments numeric/alphanumeric/mixed modes.
/// The encoder only produces byte-mode segments, so the numeric (mode=1) and
/// alphanumeric (mode=2) decode paths are never exercised by round-trip tests.
/// These tests construct raw data codewords with each mode indicator and
/// verify that decode_segments recovers the expected character bytes.

///|
/// Pack a bit array (MSB first) into bytes, zero-padding to a byte boundary.
fn dmode_pack_bits(bits : Array[Int32]) -> FixedArray[Int32] {
  let padded_len = (bits.length() + 7) / 8 * 8
  let bytes_count = padded_len / 8
  let result = FixedArray::make(bytes_count, 0)
  for i = 0; i < bytes_count; i = i + 1 {
    let mut byte = 0
    for j = 0; j < 8; j = j + 1 {
      let idx = i * 8 + j
      let bit = if idx < bits.length() { bits[idx] } else { 0 }
      byte = (byte << 1) | bit
    }
    result[i] = byte
  }
  result
}

///|
/// Push the low n bits of value (MSB first) into the bit array.
fn dmode_push_bits(bits : Array[Int32], value : Int32, n : Int32) -> Unit {
  for i = n - 1; i >= 0; i = i - 1 {
    bits.push((value >> i) & 1)
  }
}

///|
/// Build a numeric-mode segment bitstream (including mode prefix):
/// mode(4)=0001 + count(ccbits) + digit groups. No terminator appended.
/// `digits` are 0-9 values (not ASCII codes).
fn dmode_numeric_segment(
  count : Int32,
  digits : Array[Int32],
  ccbits : Int32,
) -> Array[Int32] {
  let bits : Array[Int32] = []
  dmode_push_bits(bits, 1, 4) // mode = 1 (numeric)
  dmode_push_bits(bits, count, ccbits)
  let mut i = 0
  let mut remaining = count
  while remaining > 0 {
    if remaining >= 3 {
      let n = digits[i] * 100 + digits[i + 1] * 10 + digits[i + 2]
      dmode_push_bits(bits, n, 10)
      i = i + 3
      remaining = remaining - 3
    } else if remaining == 2 {
      let n = digits[i] * 10 + digits[i + 1]
      dmode_push_bits(bits, n, 7)
      i = i + 2
      remaining = 0
    } else {
      dmode_push_bits(bits, digits[i], 4)
      i = i + 1
      remaining = 0
    }
  }
  bits
}

///|
/// Build an alphanumeric-mode segment bitstream (including mode prefix):
/// mode(4)=0010 + count(ccbits) + char groups. No terminator appended.
/// `chars` are alphanumeric table indices (0-44).
fn dmode_alpha_segment(
  count : Int32,
  chars : Array[Int32],
  ccbits : Int32,
) -> Array[Int32] {
  let bits : Array[Int32] = []
  dmode_push_bits(bits, 2, 4) // mode = 2 (alphanumeric)
  dmode_push_bits(bits, count, ccbits)
  let mut i = 0
  let mut remaining = count
  while remaining > 0 {
    if remaining >= 2 {
      let n = chars[i] * 45 + chars[i + 1]
      dmode_push_bits(bits, n, 11)
      i = i + 2
      remaining = remaining - 2
    } else {
      dmode_push_bits(bits, chars[i], 6)
      i = i + 1
      remaining = 0
    }
  }
  bits
}

///|
/// Build a byte-mode segment bitstream (including mode prefix):
/// No terminator appended.
fn dmode_byte_segment(
  count : Int32,
  bytes : Array[Int32],
  ccbits : Int32,
) -> Array[Int32] {
  let bits : Array[Int32] = []
  dmode_push_bits(bits, 4, 4) // mode = 4 (byte)
  dmode_push_bits(bits, count, ccbits)
  for i = 0; i < count; i = i + 1 {
    dmode_push_bits(bits, bytes[i], 8)
  }
  bits
}

///|
/// Append a 4-bit terminator (0000) to the bit array.
fn dmode_terminator(bits : Array[Int32]) -> Unit {
  dmode_push_bits(bits, 0, 4)
}

///|
/// Compare two FixedArray[Int32] for element-wise equality.
fn dmode_fa_eq(a : FixedArray[Int32], b : FixedArray[Int32]) -> Bool {
  if a.length() != b.length() {
    return false
  }
  let mut ok = true
  for i = 0; i < a.length(); i = i + 1 {
    if a[i] != b[i] {
      ok = false
    }
  }
  ok
}

///|
/// Build a FixedArray from a literal array.
fn dmode_mk_fa(xs : Array[Int32]) -> FixedArray[Int32] {
  let fa = FixedArray::make(xs.length(), 0)
  for i = 0; i < xs.length(); i = i + 1 {
    fa[i] = xs[i]
  }
  fa
}

///|
/// Decode a single numeric segment at the given version and compare to expected.
fn dmode_check_numeric(
  count : Int32,
  digits : Array[Int32],
  version : Int32,
  expected : Array[Int32],
) -> Bool {
  let ccbits = char_count_bits(mode_numeric(), version)
  let bits = dmode_numeric_segment(count, digits, ccbits)
  dmode_terminator(bits)
  let cw = dmode_pack_bits(bits)
  match decode_segments(cw, version) {
    Some(v) => dmode_fa_eq(v, dmode_mk_fa(expected))
    None => false
  }
}

///|
/// Decode a single alphanumeric segment at the given version and compare to expected.
fn dmode_check_alpha(
  count : Int32,
  chars : Array[Int32],
  version : Int32,
  expected : Array[Int32],
) -> Bool {
  let ccbits = char_count_bits(mode_alphanumeric(), version)
  let bits = dmode_alpha_segment(count, chars, ccbits)
  dmode_terminator(bits)
  let cw = dmode_pack_bits(bits)
  match decode_segments(cw, version) {
    Some(v) => dmode_fa_eq(v, dmode_mk_fa(expected))
    None => false
  }
}

// ==================== Numeric mode tests ====================

///|
/// Numeric mode: 3 digits "123" -> ASCII 49,50,51. V1 ccbits=10, 10-bit group.
test "decode mode: numeric 3 digits" {
  assert_true(dmode_check_numeric(3, [1, 2, 3], 1, [49, 50, 51]))
}

///|
/// Numeric mode: 2 digits "12" -> ASCII 49,50. Uses 7-bit remainder group.
test "decode mode: numeric 2 digits" {
  assert_true(dmode_check_numeric(2, [1, 2], 1, [49, 50]))
}

///|
/// Numeric mode: 1 digit "5" -> ASCII 53. Uses 4-bit remainder group.
test "decode mode: numeric 1 digit" {
  assert_true(dmode_check_numeric(1, [5], 1, [53]))
}

///|
/// Numeric mode: 12 digits "123456789012" -> 4 full 10-bit groups.
test "decode mode: numeric many digits" {
  assert_true(
    dmode_check_numeric(12, [1, 2, 3, 4, 5, 6, 7, 8, 9, 0, 1, 2], 1, [
      49, 50, 51, 52, 53, 54, 55, 56, 57, 48, 49, 50,
    ]),
  )
}

///|
/// Numeric mode: 7 digits "1234567" -> 2 full groups + 1-digit remainder.
test "decode mode: numeric mixed remainders" {
  assert_true(
    dmode_check_numeric(7, [1, 2, 3, 4, 5, 6, 7], 1, [
      49, 50, 51, 52, 53, 54, 55,
    ]),
  )
}

///|
/// Numeric mode at V10: ccbits=12 (version group 10-26).
test "decode mode: numeric version 10" {
  assert_true(dmode_check_numeric(3, [1, 2, 3], 10, [49, 50, 51]))
}

///|
/// Numeric mode: "000" -> all zeros, n=0 encodes as 10 zero bits.
test "decode mode: numeric all zeros" {
  assert_true(dmode_check_numeric(3, [0, 0, 0], 1, [48, 48, 48]))
}

// ==================== Alphanumeric mode tests ====================

///|
/// Alphanumeric mode: "AB" (indices 10,11) -> ASCII 65,66. V1 ccbits=9.
test "decode mode: alphanumeric 2 chars" {
  assert_true(dmode_check_alpha(2, [10, 11], 1, [65, 66]))
}

///|
/// Alphanumeric mode: "A" (index 10) -> ASCII 65. Uses 6-bit single group.
test "decode mode: alphanumeric 1 char" {
  assert_true(dmode_check_alpha(1, [10], 1, [65]))
}

///|
/// Alphanumeric mode: "ABCDEFGHIJ" (10 chars) -> 5 full 11-bit groups.
test "decode mode: alphanumeric many chars" {
  assert_true(
    dmode_check_alpha(10, [10, 11, 12, 13, 14, 15, 16, 17, 18, 19], 1, [
      65, 66, 67, 68, 69, 70, 71, 72, 73, 74,
    ]),
  )
}

///|
/// Alphanumeric mode: " $%" (indices 36,37,38) -> ASCII 32,36,37.
/// Tests special symbol decoding via the alphanumeric table.
test "decode mode: alphanumeric special chars" {
  assert_true(dmode_check_alpha(3, [36, 37, 38], 1, [32, 36, 37]))
}

///|
/// Alphanumeric mode at V10: ccbits=11 (version group 10-26).
test "decode mode: alphanumeric version 10" {
  assert_true(dmode_check_alpha(2, [10, 11], 10, [65, 66]))
}

///|
/// Alphanumeric mode: "0123456789" (all digit indices) -> ASCII 48-57.
test "decode mode: alphanumeric all digits" {
  assert_true(
    dmode_check_alpha(10, [0, 1, 2, 3, 4, 5, 6, 7, 8, 9], 1, [
      48, 49, 50, 51, 52, 53, 54, 55, 56, 57,
    ]),
  )
}

// ==================== Mixed mode tests ====================

///|
/// Mixed: numeric "12" then byte "X" (ASCII 88). V1: numeric ccbits=10, byte ccbits=8.
test "decode mode: numeric then byte" {
  let bits = dmode_numeric_segment(2, [1, 2], 10)
  let seg2 = dmode_byte_segment(1, [88], 8)
  for i = 0; i < seg2.length(); i = i + 1 {
    bits.push(seg2[i])
  }
  dmode_terminator(bits)
  let cw = dmode_pack_bits(bits)
  match decode_segments(cw, 1) {
    Some(v) => assert_true(dmode_fa_eq(v, dmode_mk_fa([49, 50, 88])))
    None => assert_true(false)
  }
}

///|
/// Mixed: byte "X" then alphanumeric "AB". V1: byte ccbits=8, alpha ccbits=9.
test "decode mode: byte then alphanumeric" {
  let bits = dmode_byte_segment(1, [88], 8)
  let seg2 = dmode_alpha_segment(2, [10, 11], 9)
  for i = 0; i < seg2.length(); i = i + 1 {
    bits.push(seg2[i])
  }
  dmode_terminator(bits)
  let cw = dmode_pack_bits(bits)
  match decode_segments(cw, 1) {
    Some(v) => assert_true(dmode_fa_eq(v, dmode_mk_fa([88, 65, 66])))
    None => assert_true(false)
  }
}

///|
/// Mixed: numeric "1" + alphanumeric "A" + byte "X" — all three modes in one stream.
test "decode mode: all three modes" {
  let bits = dmode_numeric_segment(1, [1], 10)
  let seg2 = dmode_alpha_segment(1, [10], 9)
  for i = 0; i < seg2.length(); i = i + 1 {
    bits.push(seg2[i])
  }
  let seg3 = dmode_byte_segment(1, [88], 8)
  for i = 0; i < seg3.length(); i = i + 1 {
    bits.push(seg3[i])
  }
  dmode_terminator(bits)
  let cw = dmode_pack_bits(bits)
  match decode_segments(cw, 1) {
    Some(v) => assert_true(dmode_fa_eq(v, dmode_mk_fa([49, 65, 88])))
    None => assert_true(false)
  }
}

// ==================== Error path tests ====================

///|
/// Error path: mode=numeric but fewer than ccbits(10) bits remain for count.
/// Construct 1 byte (8 bits): mode=0001 + 4 zero bits. total_bits=8 < 4+10=14.
test "decode mode: insufficient bits for count" {
  let bits : Array[Int32] = []
  dmode_push_bits(bits, 1, 4) // mode = numeric
  dmode_push_bits(bits, 0, 4) // only 4 bits, need 10 for count
  let cw = dmode_pack_bits(bits)
  match decode_segments(cw, 1) {
    Some(_) => assert_true(false) // should fail
    None => assert_true(true) // expected: return None
  }
}

///|
/// Error path: unsupported mode (Kanji mode=8, 4-bit indicator 1000).
/// Decoder hits the `_ => break` arm and returns whatever was decoded so far
/// (empty, since this is the first segment).
test "decode mode: unsupported mode" {
  let bits : Array[Int32] = []
  dmode_push_bits(bits, 8, 4) // mode = 1000 (Kanji, unsupported)
  dmode_push_bits(bits, 0, 4) // padding
  let cw = dmode_pack_bits(bits)
  match decode_segments(cw, 1) {
    Some(v) => assert_true(v.length() == 0) // empty result, parsing stopped
    None => assert_true(false)
  }
}

///|
/// Error path: terminator only (mode=0000).3
/// returning an empty result.
test "decode mode: terminator only" {
  let bits : Array[Int32] = []
  dmode_push_bits(bits, 0, 4) // mode = 0 (terminator)
  dmode_push_bits(bits, 0, 4) // padding
  let cw = dmode_pack_bits(bits)
  match decode_segments(cw, 1) {
    Some(v) => assert_true(v.length() == 0)
    None => assert_true(false)
  }
}

///|
/// Error path: numeric count=100 but data has far fewer bits than needed.
/// Decoder decodes one 3-digit group from padding zeros, then runs out of
/// bits for the next group and returns None.
test "decode mode: count exceeds data" {
  let bits : Array[Int32] = []
  dmode_push_bits(bits, 1, 4) // mode = numeric
  dmode_push_bits(bits, 100, 10) // count = 100 (needs 100 digits)
  dmode_terminator(bits) // only 4 bits follow, nowhere near enough
  let cw = dmode_pack_bits(bits)
  match decode_segments(cw, 1) {
    Some(_) => assert_true(false) // should fail (count exceeds available data)
    None => assert_true(true)
  }
}
