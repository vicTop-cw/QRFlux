// Deep tests for QR code encoder core.
// Tests version invariants, finder/timing patterns, capacity functions,
// alignment patterns, and encode_segments.

///|
/// Check 7x7 finder pattern at top-left corner (ox, oy).
/// Returns true if the finder structure matches: outer ring dark, inner
/// ring light, center 3x3 dark.
fn finder_at(qr : @qr.QrCode, ox : Int32, oy : Int32) -> Bool {
  let mut ok = true
  for dy = 0; dy < 7; dy = dy + 1 {
    for dx = 0; dx < 7; dx = dx + 1 {
      let ddx = if dx - 3 < 0 { 3 - dx } else { dx - 3 }
      let ddy = if dy - 3 < 0 { 3 - dy } else { dy - 3 }
      let d = if ddx > ddy { ddx } else { ddy }
      // dark when d=0,1,3; light when d=2
      let expected = d != 2
      if qr.get_module(ox + dx, oy + dy) != expected {
        ok = false
      }
    }
  }
  ok
}

///|
test "qrcode deep: size = version*4+17 for all versions" {
  let data = FixedArray::make(1, 0x42)
  for v = 1; v <= 40; v = v + 1 {
    let qr = @qr.encode_binary(data, @qr.ecc_low(), v)
    assert_true(qr.size() == qr.version() * 4 + 17)
  }
}

///|
test "qrcode deep: version property correct" {
  let data = FixedArray::make(5, 0x42)
  for v = 1; v <= 11; v = v + 1 {
    let qr = @qr.encode_binary(data, @qr.ecc_low(), v)
    assert_true(qr.version() >= v)
  }
}

///|
test "qrcode deep: level property correct" {
  let data = FixedArray::make(10, 0x42)
  let levels = [
    @qr.ecc_low(),
    @qr.ecc_medium(),
    @qr.ecc_quartile(),
    @qr.ecc_high(),
  ]
  for l in levels {
    let qr = @qr.encode_binary(data, l, 1)
    let ql = qr.level()
    assert_true(
      ql == @qr.ecc_low() ||
      ql == @qr.ecc_medium() ||
      ql == @qr.ecc_quartile() ||
      ql == @qr.ecc_high(),
    )
  }
}

///|
test "qrcode deep: mask in range" {
  let data = FixedArray::make(10, 0x42)
  for v = 1; v <= 5; v = v + 1 {
    let qr = @qr.encode_binary(data, @qr.ecc_medium(), v)
    let m = qr.mask()
    assert_true(m >= 0 && m <= 7)
  }
}

///|
test "qrcode deep: get_module returns bool" {
  let data = FixedArray::make(5, 0x42)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let size = qr.size()
  // In-bounds: should not crash
  for y = 0; y < size; y = y + 1 {
    for x = 0; x < size; x = x + 1 {
      let _ = qr.get_module(x, y)
    }
  }
  // Out-of-bounds: should return false
  assert_true(!qr.get_module(-1, 0))
  assert_true(!qr.get_module(0, -1))
  assert_true(!qr.get_module(size, 0))
  assert_true(!qr.get_module(0, size))
}

///|
test "qrcode deep: finder pattern top-left" {
  let data = FixedArray::make(5, 0x42)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  assert_true(finder_at(qr, 0, 0))
}

///|
test "qrcode deep: finder pattern top-right" {
  let data = FixedArray::make(5, 0x42)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let size = qr.size()
  assert_true(finder_at(qr, size - 7, 0))
}

///|
test "qrcode deep: finder pattern bottom-left" {
  let data = FixedArray::make(5, 0x42)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let size = qr.size()
  assert_true(finder_at(qr, 0, size - 7))
}

///|
test "qrcode deep: timing pattern row 6" {
  let data = FixedArray::make(5, 0x42)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let size = qr.size()
  let mut all_ok = true
  for x = 8; x < size - 8; x = x + 1 {
    let expected = x % 2 == 0
    if qr.get_module(x, 6) != expected {
      all_ok = false
    }
  }
  assert_true(all_ok)
}

///|
test "qrcode deep: timing pattern col 6" {
  let data = FixedArray::make(5, 0x42)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let size = qr.size()
  let mut all_ok = true
  for y = 8; y < size - 8; y = y + 1 {
    let expected = y % 2 == 0
    if qr.get_module(6, y) != expected {
      all_ok = false
    }
  }
  assert_true(all_ok)
}

///|
test "qrcode deep: num_raw_data_modules monotonic" {
  let mut prev = @qr.num_raw_data_modules(1)
  for v = 2; v <= 40; v = v + 1 {
    let curr = @qr.num_raw_data_modules(v)
    assert_true(curr > prev)
    prev = curr
  }
}

///|
test "qrcode deep: num_data_codewords all versions" {
  let levels = [
    @qr.ecc_low(),
    @qr.ecc_medium(),
    @qr.ecc_quartile(),
    @qr.ecc_high(),
  ]
  for l in levels {
    let mut prev = @qr.num_data_codewords(1, l)
    assert_true(prev > 0)
    for v = 2; v <= 40; v = v + 1 {
      let curr = @qr.num_data_codewords(v, l)
      assert_true(curr > 0)
      assert_true(curr > prev)
      prev = curr
    }
  }
}

///|
test "qrcode deep: num_data_codewords ecc ordering" {
  for v = 1; v <= 40; v = v + 1 {
    let l = @qr.num_data_codewords(v, @qr.ecc_low())
    let m = @qr.num_data_codewords(v, @qr.ecc_medium())
    let q = @qr.num_data_codewords(v, @qr.ecc_quartile())
    let h = @qr.num_data_codewords(v, @qr.ecc_high())
    assert_true(l > m)
    assert_true(m > q)
    assert_true(q > h)
  }
}

///|
test "qrcode deep: total_bits byte mode" {
  let data = FixedArray::make(10, 0x42)
  let seg = @qr.Segment::make_bytes(data)
  let segs = [seg]
  let tb = @qr.total_bits(segs, 1)
  // 4 (mode indicator) + 8 (char count bits for byte mode v1-9) + 80 (10 bytes * 8 bits)
  assert_true(tb == 4 + 8 + 80)
}

///|
test "qrcode deep: alignment v1 empty" {
  let p = @qr.alignment_pattern_positions(1)
  assert_true(p.length() == 0)
}

///|
test "qrcode deep: alignment v2-v6" {
  for v = 2; v <= 6; v = v + 1 {
    let p = @qr.alignment_pattern_positions(v)
    assert_true(p.length() == 2)
    assert_true(p[0] == 6)
    assert_true(p[1] > 6)
  }
}

///|
test "qrcode deep: alignment v40" {
  let p = @qr.alignment_pattern_positions(40)
  assert_true(p.length() > 2)
  assert_true(p[0] == 6)
}

///|
test "qrcode deep: encode_segments single byte segment" {
  let data = FixedArray::make(5, 0x42)
  let seg = @qr.Segment::make_bytes(data)
  let segs = [seg]
  let qr = @qr.encode_segments(segs, @qr.ecc_medium(), 1)
  assert_true(qr.size() == qr.version() * 4 + 17)
  assert_true(qr.version() >= 1)
}

///|
test "qrcode deep: encode_segments empty" {
  let segs : Array[@qr.Segment] = []
  let qr = @qr.encode_segments(segs, @qr.ecc_low(), 1)
  assert_true(qr.size() == qr.version() * 4 + 17)
  assert_true(qr.version() == 1)
}

///|
test "qrcode deep: encode_segments auto version" {
  let data = FixedArray::make(5, 0x42)
  let seg = @qr.Segment::make_bytes(data)
  let segs = [seg]
  let qr = @qr.encode_segments(segs, @qr.ecc_low(), 1)
  assert_true(qr.version() >= 1)
  let qr2 = @qr.encode_segments(segs, @qr.ecc_low(), 10)
  assert_true(qr2.version() >= 10)
}
