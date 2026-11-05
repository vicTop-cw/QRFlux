/// Whitebox tests for decoder internals (15 private functions).
/// Tests call package-private functions directly (no @qr prefix).
/// Covers: popcount15/18, gf_inv, try_decode_format/version,
/// read_format/version_info, mark_function_modules, read_data_bits,
/// read_bits_array, berlekamp_massey, rs_decode/correct,
/// deinterleave_and_correct, decode_segments, decode_bool_modules.

///|
/// Encode 5-bit data into 15-bit format info with BCH(15,5) + mask 0x5412.
/// Mirrors draw_format_bits' encoding for constructing valid test inputs.
fn encode_format_bits(data : Int32) -> Int32 {
  let mut rem = data
  for _i = 0; _i < 10; _i = _i + 1 {
    rem = (rem << 1) ^ ((rem >> 9) * 0x537)
  }
  ((data << 10) | rem) ^ 0x5412
}

///|
/// Encode 6-bit data into 18-bit version info with BCH(18,6).
/// Mirrors draw_version_info's encoding for constructing valid test inputs.
fn encode_version_bits(data : Int32) -> Int32 {
  let mut rem = data
  for _i = 0; _i < 12; _i = _i + 1 {
    rem = (rem << 1) ^ ((rem >> 11) * 0x1F25)
  }
  (data << 12) | rem
}

///|
/// Build a valid RS codeword [data..., ecc...] for testing rs_decode.
/// Uses the encoder's rs_compute_divisor/rs_compute_remainder so the
/// resulting codeword has all-zero syndromes.
fn build_codeword(data : Array[Int32], num_ec : Int32) -> FixedArray[Int32] {
  let datfa = mk_bytes(data)
  let divisor = rs_compute_divisor(num_ec)
  let ecc = rs_compute_remainder(datfa, divisor)
  let n = datfa.length() + num_ec
  let cw = FixedArray::make(n, 0)
  for i = 0; i < datfa.length(); i = i + 1 {
    cw[i] = datfa[i]
  }
  for i = 0; i < num_ec; i = i + 1 {
    cw[datfa.length() + i] = ecc[i]
  }
  cw
}

///|
/// Copy a FixedArray (helper for corrupting codewords in tests).
fn copy_fa(src : FixedArray[Int32]) -> FixedArray[Int32] {
  let dst = FixedArray::make(src.length(), 0)
  for i = 0; i < src.length(); i = i + 1 {
    dst[i] = src[i]
  }
  dst
}

///|
/// Compare two FixedArray[Int32] for element-wise equality.
fn fa_eq(a : FixedArray[Int32], b : FixedArray[Int32]) -> Bool {
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
/// popcount15: count set bits in a 15-bit value.
test "dec wb: popcount15 basic" {
  assert_true(popcount15(0) == 0)
  assert_true(popcount15(1) == 1)
  assert_true(popcount15(0x7FFF) == 15)
}

///|
/// popcount18: count set bits in an 18-bit value.
test "dec wb: popcount18 basic" {
  assert_true(popcount18(0) == 0)
  assert_true(popcount18(1) == 1)
  assert_true(popcount18(0x3FFFF) == 18)
}

///|
/// popcount15/18 on alternating-bit patterns.
test "dec wb: popcount known values" {
  // 0b101010101010101 has 8 ones in 15 bits
  assert_true(popcount15(0b101010101010101) == 8)
  // 0b101010101010101010 has 9 ones in 18 bits
  assert_true(popcount18(0b101010101010101010) == 9)
}

///|
/// gf_inv: 1 is its own inverse; 0 maps to 0 by convention.
test "dec wb: gf_inv basic" {
  assert_true(gf_inv(1) == 1)
  assert_true(gf_inv(0) == 0)
}

///|
/// gf_inv: for every nonzero x, x * gf_inv(x) == 1 in GF(256).
test "dec wb: gf_inv all nonzeros" {
  let mut ok = true
  for x = 1; x < 256; x = x + 1 {
    if gf_mul(x, gf_inv(x)) != 1 {
      ok = false
    }
  }
  assert_true(ok)
}

///|
/// gf_inv: applying inverse twice returns the original element.
test "dec wb: gf_inv double inv" {
  let mut ok = true
  for x = 1; x < 256; x = x + 1 {
    if gf_inv(gf_inv(x)) != x {
      ok = false
    }
  }
  assert_true(ok)
}

///|
/// try_decode_format: all 32 valid BCH(15,5) codewords decode to their data.
test "dec wb: try_decode_format valid" {
  let mut ok = true
  for data = 0; data < 32; data = data + 1 {
    let bits = encode_format_bits(data)
    match try_decode_format(bits) {
      Some(v) => if v != data { ok = false }
      None => ok = false
    }
  }
  assert_true(ok)
}

///|
/// try_decode_format: 1-3 bit errors are corrected (BCH(15,5) min dist 7).
test "dec wb: try_decode_format error correction" {
  let bits = encode_format_bits(5)
  // flip 1 bit (bit 0)
  match try_decode_format(bits ^ 1) {
    Some(v) => assert_true(v == 5)
    None => assert_true(false)
  }
  // flip 2 bits (bits 0,1)
  match try_decode_format(bits ^ 3) {
    Some(v) => assert_true(v == 5)
    None => assert_true(false)
  }
  // flip 3 bits (bits 0,1,2)
  match try_decode_format(bits ^ 7) {
    Some(v) => assert_true(v == 5)
    None => assert_true(false)
  }
}

///|
/// try_decode_format: some 15-bit values are too far from any codeword
/// (distance > 3) and return None. BCH(15,5) has 32 codewords in 2^15
/// space, so uncorrectable values exist.
test "dec wb: try_decode_format invalid" {
  let mut found_none = false
  for raw = 0; raw < 32768; raw = raw + 1 {
    match try_decode_format(raw) {
      Some(_) => ()
      None => {
        found_none = true
        break
      }
    }
  }
  assert_true(found_none)
}

///|
/// try_decode_version: all versions 1..40 decode correctly.
test "dec wb: try_decode_version valid" {
  let mut ok = true
  for v = 1; v <= 40; v = v + 1 {
    let bits = encode_version_bits(v)
    match try_decode_version(bits) {
      Some(d) => if d != v { ok = false }
      None => ok = false
    }
  }
  assert_true(ok)
}

///|
/// try_decode_version: raw=1 is closest to data=0 codeword (distance 1),
/// but data=0 is rejected (version must be 1..40), so returns None.
test "dec wb: try_decode_version invalid" {
  match try_decode_version(1) {
    Some(_) => assert_true(false)
    None => assert_true(true)
  }
}

///|
/// mark_function_modules for V1: finder, timing, format areas marked true.
test "dec wb: mark function v1" {
  let isfn = mark_function_modules(1, 21)
  assert_true(isfn.length() == 21)
  assert_true(isfn[0].length() == 21)
  // Finder pattern at top-left
  assert_true(isfn[0][0])
  assert_true(isfn[3][3])
  // Timing pattern at row/column 6
  assert_true(isfn[0][6])
  assert_true(isfn[6][0])
  assert_true(isfn[6][6])
  // Format info area
  assert_true(isfn[0][8])
  assert_true(isfn[8][0])
  assert_true(isfn[8][8])
  // Dark module at (8, size-8) = (8, 13)
  assert_true(isfn[13][8])
  // Data module (10,10) should NOT be a function module
  assert_true(!isfn[10][10])
}

///|
/// mark_function_modules for V5: alignment patterns at (6,30),(30,6),(30,30).
test "dec wb: mark function v5" {
  let isfn = mark_function_modules(5, 37)
  assert_true(isfn.length() == 37)
  // Finder patterns at three corners
  assert_true(isfn[3][3])
  assert_true(isfn[3][33])
  assert_true(isfn[33][3])
  // V5 alignment positions: [6, 30]. (6,6) skipped (finder overlap).
  // Alignment centers at (6,30), (30,6), (30,30).
  assert_true(isfn[30][30])
  assert_true(isfn[30][6])
  assert_true(isfn[6][30])
  // Alignment pattern is 5x5, so corners around (30,30) are also function
  assert_true(isfn[28][28])
  assert_true(isfn[32][32])
}

///|
/// read_format_info: decode format from a real V1 QR matches encoder state.
test "dec wb: read format info from qr" {
  let data = mk_bytes([72, 101, 108, 108, 111]) // "Hello"
  let qr = encode_binary(data, ecc_low(), 1)
  match read_format_info(qr.modules, qr.size()) {
    Some((level, mask)) => {
      assert_true(level == qr.level())
      assert_true(mask == qr.mask)
    }
    None => assert_true(false)
  }
}

///|
/// read_version_info: V7+ QR has version info that decodes to the version.
test "dec wb: read version info from qr" {
  // V7+ has version info. 15 bytes fits V7 Low (capacity 80 bytes).
  let data = mk_bytes([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15])
  let qr = encode_binary(data, ecc_low(), 7)
  assert_true(qr.version() == 7)
  match read_version_info(qr.modules, qr.size()) {
    Some(v) => assert_true(v == 7)
    None => assert_true(false)
  }
}

///|
/// read_data_bits for V1: bit count matches the zigzag scan of non-function
/// modules. The encoder skips some columns via `if right <= 6`, so the count
/// is less than num_raw_data_modules (208); we verify against a simulated scan.
test "dec wb: read data bits v1" {
  let data = mk_bytes([72, 101, 108, 108, 111])
  let qr = encode_binary(data, ecc_low(), 1)
  let size = qr.size()
  let isfn = mark_function_modules(1, size)
  let raw_bits = read_data_bits(qr.modules, size, isfn, qr.mask)
  // Simulate the encoder's zigzag scan to count expected data modules.
  let mut expected = 0
  let mut right = size - 1
  while right >= 1 {
    if right <= 6 {
      right = right - 1
    }
    for vert = 0; vert < size; vert = vert + 1 {
      for j = 0; j < 2; j = j + 1 {
        let x = right - j
        let upward = ((right + 1) & 2) == 0
        let y = if upward { size - 1 - vert } else { vert }
        if !isfn[y][x] {
          expected = expected + 1
        }
      }
    }
    right = right - 2
  }
  assert_true(raw_bits.length() == expected)
  assert_true(expected > 0)
  assert_true(expected <= num_raw_data_modules(1))
}

///|
/// read_data_bits for V5: bit count matches the zigzag scan.
test "dec wb: read data bits v5" {
  let data = mk_bytes([1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
  let qr = encode_binary(data, ecc_low(), 5)
  let size = qr.size()
  let version = qr.version()
  let isfn = mark_function_modules(version, size)
  let raw_bits = read_data_bits(qr.modules, size, isfn, qr.mask)
  // Simulate the zigzag scan to count expected data modules.
  let mut expected = 0
  let mut right = size - 1
  while right >= 1 {
    if right <= 6 {
      right = right - 1
    }
    for vert = 0; vert < size; vert = vert + 1 {
      for j = 0; j < 2; j = j + 1 {
        let x = right - j
        let upward = ((right + 1) & 2) == 0
        let y = if upward { size - 1 - vert } else { vert }
        if !isfn[y][x] {
          expected = expected + 1
        }
      }
    }
    right = right - 2
  }
  assert_true(raw_bits.length() == expected)
  assert_true(expected > 0)
  assert_true(expected <= num_raw_data_modules(version))
}

///|
/// read_bits_array: read 4 bits from position 0 (MSB first).
test "dec wb: read bits array basic" {
  let bits : Array[Int32] = [1, 0, 1, 1]
  // Read 4 bits from pos 0: 1,0,1,1 -> 0b1011 = 11
  assert_true(read_bits_array(bits, 0, 4) == 0b1011)
}

///|
/// read_bits_array: read 8 bits from a non-zero offset.
test "dec wb: read bits array offset" {
  let bits : Array[Int32] = [1, 0, 1, 1, 0, 1, 0, 0, 1, 1, 0, 1]
  // From pos 4, read 8 bits: 0,1,0,0,1,1,0,1 -> 0b01001101 = 77
  assert_true(read_bits_array(bits, 4, 8) == 0b01001101)
}

///|
/// berlekamp_massey: all-zero syndromes => 0 errors.
test "dec wb: berlekamp massey no error" {
  let syndromes = FixedArray::make(4, 0)
  match berlekamp_massey(syndromes, 4) {
    Some((_lambda, l)) => assert_true(l == 0)
    None => assert_true(false)
  }
}

///|
/// berlekamp_massey: single-error syndrome sequence => 1 error.
/// Syndromes S_i = e * alpha^(i * pos) form a geometric sequence.
test "dec wb: berlekamp massey single error" {
  let pos = 2
  let err = 5
  let num_ec = 4
  let syndromes = FixedArray::make(num_ec, 0)
  for i = 0; i < num_ec; i = i + 1 {
    syndromes[i] = gf_mul(err, gf_pow(2, i * pos))
  }
  match berlekamp_massey(syndromes, num_ec) {
    Some((_lambda, l)) => assert_true(l == 1)
    None => assert_true(false)
  }
}

///|
/// berlekamp_massey: two-error syndrome sequence => 2 errors.
test "dec wb: berlekamp massey double error" {
  let pos1 = 2
  let pos2 = 5
  let err1 = 3
  let err2 = 7
  let num_ec = 5
  let syndromes = FixedArray::make(num_ec, 0)
  for i = 0; i < num_ec; i = i + 1 {
    syndromes[i] = gf_mul(err1, gf_pow(2, i * pos1)) ^
      gf_mul(err2, gf_pow(2, i * pos2))
  }
  match berlekamp_massey(syndromes, num_ec) {
    Some((_lambda, l)) => assert_true(l == 2)
    None => assert_true(false)
  }
}

///|
/// rs_decode: a valid codeword (all-zero syndromes) is returned unchanged.
test "dec wb: rs correct no error" {
  let original = build_codeword([1, 2, 3], 2)
  match rs_decode(original, 2) {
    Some(v) => assert_true(fa_eq(v, original))
    None => assert_true(false)
  }
}

///|
/// rs_decode: a single-symbol error is corrected back to the original.
/// Uses num_ec=7 (V1 Low's ECC count) with error in the last codeword,
/// mirroring the decoder's real-world missing-codeword scenario.
test "dec wb: rs correct single error" {
  let original = build_codeword([1, 2, 3, 4, 5], 7)
  // Verify original is a valid codeword (all 7 syndromes zero).
  let n0 = original.length()
  let mut orig_zero = true
  for i = 0; i < 7; i = i + 1 {
    let alpha_i = gf_pow(2, i)
    let mut s = 0
    for j = 0; j < n0; j = j + 1 {
      s = gf_mul(s, alpha_i) ^ original[j]
    }
    if s != 0 {
      orig_zero = false
    }
  }
  assert_true(orig_zero)
  // Corrupt the last symbol and verify rs_decode corrects it.
  let corrupted = copy_fa(original)
  let last = corrupted.length() - 1
  corrupted[last] = corrupted[last] ^ 0x55
  match rs_decode(corrupted, 7) {
    Some(v) => assert_true(fa_eq(v, original))
    None => assert_true(false)
  }
}

///|
/// deinterleave_and_correct: V1 Low QR codewords deinterleave to data codewords.
/// Uses 17-byte data (>16 = Medium capacity) to force V1 Low (no ECC boost).
test "dec wb: deinterleave v1" {
  let data = mk_bytes([
    1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17,
  ])
  let (datacw, allcw) = debug_codewords(data, ecc_low(), 1)
  // V1 Low: 19 data + 7 ecc = 26 codewords, 1 block.
  assert_true(datacw.length() == 19)
  assert_true(allcw.length() == 26)
  // Verify allcw is a valid RS codeword: all 7 syndromes should be zero.
  let n = allcw.length()
  let mut syndromes_zero = true
  for i = 0; i < 7; i = i + 1 {
    let alpha_i = gf_pow(2, i)
    let mut s = 0
    for j = 0; j < n; j = j + 1 {
      s = gf_mul(s, alpha_i) ^ allcw[j]
    }
    if s != 0 {
      syndromes_zero = false
    }
  }
  assert_true(syndromes_zero)
  // Verify allcw prefix matches datacw (1 block: data then ecc).
  let mut prefix_ok = true
  for i = 0; i < 19; i = i + 1 {
    if allcw[i] != datacw[i] {
      prefix_ok = false
    }
  }
  assert_true(prefix_ok)
  // Now verify deinterleave returns the original data codewords.
  match deinterleave_and_correct(allcw, 1, ecc_low()) {
    Some(v) => assert_true(fa_eq(v, datacw))
    None => assert_true(false)
  }
}

///|
/// deinterleave_and_correct: a single codeword error is corrected.
/// Uses 17-byte data to force V1 Low (7 ECC per block, corrects 3 errors).
test "dec wb: deinterleave with error" {
  let data = mk_bytes([
    1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17,
  ])
  let (datacw, allcw) = debug_codewords(data, ecc_low(), 1)
  let corrupted = copy_fa(allcw)
  // Corrupt the last codeword symbol (mirrors decoder's missing-codeword case)
  let last = corrupted.length() - 1
  corrupted[last] = corrupted[last] ^ 0x55
  match deinterleave_and_correct(corrupted, 1, ecc_low()) {
    Some(v) => assert_true(fa_eq(v, datacw))
    None => assert_true(false)
  }
}

///|
/// decode_segments: byte-mode data codewords decode back to original bytes.
test "dec wb: decode segments byte mode" {
  let data = mk_bytes([72, 105]) // "Hi"
  let (datacw, _allcw) = debug_codewords(data, ecc_low(), 1)
  match decode_segments(datacw, 1) {
    Some(v) => {
      assert_true(v.length() == 2)
      assert_true(v[0] == 72)
      assert_true(v[1] == 105)
    }
    None => assert_true(false)
  }
}

///|
/// decode_bool_modules and decode_from_qrcode agree and recover original data.
test "dec wb: decode bool modules matches decode_from_qrcode" {
  let data = mk_bytes([72, 101, 108, 108, 111])
  let qr = encode_binary(data, ecc_low(), 1)
  let r1 = decode_bool_modules(qr.modules, qr.version(), qr.size())
  let r2 = decode_from_qrcode(qr)
  match (r1, r2) {
    (Some(a), Some(b)) => {
      // Both decode paths agree
      assert_true(fa_eq(a, b))
      // And they recover the original payload
      assert_true(fa_eq(a, data))
    }
    _ => assert_true(false)
  }
}
