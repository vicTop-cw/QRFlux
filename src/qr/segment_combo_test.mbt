/// Segment combo tests: multi-mode combination coverage for segment encoding.
/// Covers single/multi byte segments, char_count_bits matrix, mode indicators,
/// version capacity boundaries, version/ECC selection, and encode-decode roundtrip.

///|
/// Compare two FixedArray[Int32] for element-wise equality.
fn combo_arrays_eq(a : FixedArray[Int32], b : FixedArray[Int32]) -> Bool {
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
/// Concatenate multiple FixedArray[Int32] parts into a single FixedArray.
fn combo_concat_data(parts : Array[FixedArray[Int32]]) -> FixedArray[Int32] {
  let mut total = 0
  for p in parts {
    total = total + p.length()
  }
  let result = FixedArray::make(total, 0)
  let mut k = 0
  for p in parts {
    for i = 0; i < p.length(); i = i + 1 {
      result[k] = p[i]
      k = k + 1
    }
  }
  result
}

///|
/// Mode equality via mode_bits bijection (Mode does not derive Eq in blackbox).
fn combo_mode_eq(a : @qr.Mode, b : @qr.Mode) -> Bool {
  @qr.mode_bits(a) == @qr.mode_bits(b)
}

///|
test "combo: single byte segment various lengths" {
  // Single byte-mode segment at lengths 0, 1, 5, 20, 100 encodes and decodes.
  let lengths = [0, 1, 5, 20, 100]
  for n in lengths {
    let data = FixedArray::make(n, 0)
    for i = 0; i < n; i = i + 1 {
      data[i] = (i * 7 + 3) & 0xFF
    }
    let seg = @qr.Segment::make_bytes(data)
    assert_true(seg.num_chars() == n)
    assert_true(combo_mode_eq(seg.mode(), @qr.mode_byte()))
    assert_true(seg.data().length() == n * 8)
    let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
    assert_true(qr.size() == qr.version() * 4 + 17)
    match @qr.decode_from_qrcode(qr) {
      Some(r) => assert_true(combo_arrays_eq(r, data))
      None => abort("single byte segment decode failed")
    }
  }
}

///|
test "combo: char_count_bits full matrix" {
  // Full matrix: 3 modes x 3 version groups, verify all 9 entries.
  let nm = @qr.mode_numeric()
  let am = @qr.mode_alphanumeric()
  let bm = @qr.mode_byte()
  // Group representatives: V1 (group 0), V10 (group 1), V27 (group 2).
  assert_true(@qr.char_count_bits(nm, 1) == 10)
  assert_true(@qr.char_count_bits(am, 1) == 9)
  assert_true(@qr.char_count_bits(bm, 1) == 8)
  assert_true(@qr.char_count_bits(nm, 10) == 12)
  assert_true(@qr.char_count_bits(am, 10) == 11)
  assert_true(@qr.char_count_bits(bm, 10) == 16)
  assert_true(@qr.char_count_bits(nm, 27) == 14)
  assert_true(@qr.char_count_bits(am, 27) == 13)
  assert_true(@qr.char_count_bits(bm, 27) == 16)
}

///|
test "combo: char_count_bits constant within version group" {
  // Within each version group, char_count_bits is constant for a given mode.
  let modes = [@qr.mode_numeric(), @qr.mode_alphanumeric(), @qr.mode_byte()]
  for m in modes {
    let g0 = @qr.char_count_bits(m, 1)
    for v = 2; v <= 9; v = v + 1 {
      assert_true(@qr.char_count_bits(m, v) == g0)
    }
    let g1 = @qr.char_count_bits(m, 10)
    for v = 11; v <= 26; v = v + 1 {
      assert_true(@qr.char_count_bits(m, v) == g1)
    }
    let g2 = @qr.char_count_bits(m, 27)
    for v = 28; v <= 40; v = v + 1 {
      assert_true(@qr.char_count_bits(m, v) == g2)
    }
  }
}

///|
test "combo: mode_bits indicator values" {
  // Mode indicator bits per ISO/IEC 18004: Numeric=001=1, Alphanumeric=010=2,
  // Byte=0100=4.
  assert_true(@qr.mode_bits(@qr.mode_numeric()) == 1)
  assert_true(@qr.mode_bits(@qr.mode_alphanumeric()) == 2)
  assert_true(@qr.mode_bits(@qr.mode_byte()) == 4)
}

///|
test "combo: mode_bits distinct across modes" {
  // The three mode indicator values are pairwise distinct (bijection).
  let n = @qr.mode_bits(@qr.mode_numeric())
  let a = @qr.mode_bits(@qr.mode_alphanumeric())
  let b = @qr.mode_bits(@qr.mode_byte())
  assert_true(n != a)
  assert_true(n != b)
  assert_true(a != b)
}

///|
test "combo: num_data_codewords monotonic in version" {
  // For each ECC level, num_data_codewords is non-decreasing in version.
  let levels = [
    @qr.ecc_low(),
    @qr.ecc_medium(),
    @qr.ecc_quartile(),
    @qr.ecc_high(),
  ]
  for level in levels {
    let mut prev = @qr.num_data_codewords(1, level)
    for v = 2; v <= 40; v = v + 1 {
      let cur = @qr.num_data_codewords(v, level)
      assert_true(cur >= prev)
      prev = cur
    }
  }
}

///|
test "combo: num_data_codewords decreases with stronger ecc" {
  // For a fixed version, stronger ECC yields fewer data codewords:
  // Low >= Medium >= Quartile >= High.
  for v = 1; v <= 40; v = v + 1 {
    let l = @qr.num_data_codewords(v, @qr.ecc_low())
    let m = @qr.num_data_codewords(v, @qr.ecc_medium())
    let q = @qr.num_data_codewords(v, @qr.ecc_quartile())
    let h = @qr.num_data_codewords(v, @qr.ecc_high())
    assert_true(l >= m)
    assert_true(m >= q)
    assert_true(q >= h)
  }
}

///|
test "combo: v40 capacity boundaries all levels" {
  // V40 data codeword counts per ISO/IEC 18004 Table 9.
  // (raw 3706 = 29648/8; subtract ECC blocks: L=2956, M=2334, Q=1666, H=1276.)
  assert_true(@qr.num_data_codewords(40, @qr.ecc_low()) == 2956)
  assert_true(@qr.num_data_codewords(40, @qr.ecc_medium()) == 2334)
  assert_true(@qr.num_data_codewords(40, @qr.ecc_quartile()) == 1666)
  assert_true(@qr.num_data_codewords(40, @qr.ecc_high()) == 1276)
}

///|
test "combo: version selection small data picks v1" {
  // Small payload (5 bytes) fits in V1, so version == 1 and size == 21.
  let data = FixedArray::make(5, 0x42)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  assert_true(qr.version() == 1)
  assert_true(qr.size() == 21)
}

///|
test "combo: version selection large data picks high version" {
  // 2000 bytes far exceeds V20 capacity, forcing a high version (>= 25).
  let data = FixedArray::make(2000, 0x42)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  assert_true(qr.version() >= 25)
  assert_true(qr.version() <= 40)
}

///|
test "combo: ecc level auto boost when capacity allows" {
  // 5 bytes at V1: total = 4 + 8 + 40 = 52 bits.
  // V1 H capacity = 9*8 = 72 >= 52, so ECC boosts all the way to High.
  let data = FixedArray::make(5, 0x42)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  assert_true(qr.version() == 1)
  assert_true(qr.level() == @qr.ecc_high())
}

///|
test "combo: ecc level boost stops at medium" {
  // 12 bytes at V1: total = 4 + 8 + 96 = 108 bits.
  // V1: H=72 < 108, Q=104 < 108, M=128 >= 108 -> boosts to Medium only.
  let data = FixedArray::make(12, 0x42)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  assert_true(qr.version() == 1)
  assert_true(qr.level() == @qr.ecc_medium())
}

///|
test "combo: encode decode roundtrip single segment" {
  // Single byte segment roundtrip across all four ECC levels.
  let data = FixedArray::make(30, 0)
  for i = 0; i < 30; i = i + 1 {
    data[i] = (i * 13 + 7) & 0xFF
  }
  let levels = [
    @qr.ecc_low(),
    @qr.ecc_medium(),
    @qr.ecc_quartile(),
    @qr.ecc_high(),
  ]
  for level in levels {
    let qr = @qr.encode_binary(data, level, 1)
    match @qr.decode_from_qrcode(qr) {
      Some(r) => assert_true(combo_arrays_eq(r, data))
      None => abort("single segment roundtrip failed for some ECC level")
    }
  }
}

///|
test "combo: encode decode roundtrip multi segment" {
  // Multiple byte segments concatenated decode to the concatenated payload.
  let d1 = FixedArray::make(8, 0x41)
  let d2 = FixedArray::make(12, 0x42)
  let d3 = FixedArray::make(5, 0x43)
  let combined = combo_concat_data([d1, d2, d3])
  let segs : Array[@qr.Segment] = []
  segs.push(@qr.Segment::make_bytes(d1))
  segs.push(@qr.Segment::make_bytes(d2))
  segs.push(@qr.Segment::make_bytes(d3))
  let qr = @qr.encode_segments(segs, @qr.ecc_medium(), 1)
  match @qr.decode_from_qrcode(qr) {
    Some(r) => assert_true(combo_arrays_eq(r, combined))
    None => abort("multi segment roundtrip failed")
  }
}

///|
test "combo: total bits matches formula" {
  // For a single byte segment of k bytes at version v:
  // total_bits = 4 (mode) + char_count_bits(byte, v) + k*8 (data).
  let bm = @qr.mode_byte()
  for k = 0; k <= 20; k = k + 1 {
    let data = FixedArray::make(k, 0x41)
    let seg = @qr.Segment::make_bytes(data)
    let segs : Array[@qr.Segment] = [seg]
    for v = 1; v <= 40; v = v + 1 {
      let expected = 4 + @qr.char_count_bits(bm, v) + k * 8
      assert_true(@qr.total_bits(segs, v) == expected)
    }
  }
}

///|
test "combo: total bits returns negative when segment too large" {
  // Byte mode at V1: char_count_bits = 8, so num_chars >= 2^8 = 256 overflows
  // and total_bits returns -1. At V10, char_count_bits = 16, so 256 < 2^16 fits.
  let data = FixedArray::make(256, 0x41)
  let seg = @qr.Segment::make_bytes(data)
  let segs : Array[@qr.Segment] = [seg]
  assert_true(@qr.total_bits(segs, 1) == -1)
  assert_true(@qr.total_bits(segs, 10) >= 0)
}

///|
test "combo: multi segment mixed lengths roundtrip" {
  // Several segments of mixed lengths (including empty) roundtrip to concat.
  let pieces : Array[FixedArray[Int32]] = []
  pieces.push(FixedArray::make(0, 0))
  pieces.push(FixedArray::make(3, 0x10))
  pieces.push(FixedArray::make(0, 0))
  pieces.push(FixedArray::make(15, 0x20))
  pieces.push(FixedArray::make(7, 0x30))
  let combined = combo_concat_data(pieces)
  let segs : Array[@qr.Segment] = []
  for p in pieces {
    segs.push(@qr.Segment::make_bytes(p))
  }
  let qr = @qr.encode_segments(segs, @qr.ecc_low(), 1)
  match @qr.decode_from_qrcode(qr) {
    Some(r) => assert_true(combo_arrays_eq(r, combined))
    None => abort("mixed lengths roundtrip failed")
  }
}

///|
test "combo: total bits additive across segments" {
  // For two byte segments at version v, total_bits is the sum of per-segment
  // totals (each contributes 4 + ccbits + data_bits).
  let bm = @qr.mode_byte()
  let d1 = FixedArray::make(4, 0x41)
  let d2 = FixedArray::make(6, 0x42)
  let s1 = @qr.Segment::make_bytes(d1)
  let s2 = @qr.Segment::make_bytes(d2)
  let segs : Array[@qr.Segment] = []
  segs.push(s1)
  segs.push(s2)
  for v = 1; v <= 40; v = v + 1 {
    let ccbits = @qr.char_count_bits(bm, v)
    let expected = 4 + ccbits + 4 * 8 + (4 + ccbits + 6 * 8)
    assert_true(@qr.total_bits(segs, v) == expected)
  }
}
