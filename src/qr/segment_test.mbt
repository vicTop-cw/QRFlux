/// Segment encoding tests: mode factories, char_count_bits, Segment::make_bytes.
/// Covers segment.mbt public API for mode indicators, character-count bits,
/// and byte-mode segment construction.

///|
/// Mode equality via mode_bits bijection (Mode does not derive Eq).
fn mode_eq(a : @qr.Mode, b : @qr.Mode) -> Bool {
  @qr.mode_bits(a) == @qr.mode_bits(b)
}

///|
test "segment: mode factory distinct" {
  // mode_bits is a bijection (Numeric=1, Alphanumeric=2, Byte=4),
  // so distinct factory functions yield distinct mode_bits values.
  let n = @qr.mode_bits(@qr.mode_numeric())
  let a = @qr.mode_bits(@qr.mode_alphanumeric())
  let b = @qr.mode_bits(@qr.mode_byte())
  assert_true(n != a)
  assert_true(n != b)
  assert_true(a != b)
}

///|
test "segment: mode factory consistent" {
  // Multiple calls to the same factory return equal mode_bits.
  assert_true(
    @qr.mode_bits(@qr.mode_numeric()) == @qr.mode_bits(@qr.mode_numeric()),
  )
  assert_true(
    @qr.mode_bits(@qr.mode_alphanumeric()) ==
    @qr.mode_bits(@qr.mode_alphanumeric()),
  )
  assert_true(@qr.mode_bits(@qr.mode_byte()) == @qr.mode_bits(@qr.mode_byte()))
}

///|
test "segment: mode_bits values" {
  // From segment.mbt: Numeric=0x1, Alphanumeric=0x2, Byte=0x4.
  assert_true(@qr.mode_bits(@qr.mode_numeric()) == 1)
  assert_true(@qr.mode_bits(@qr.mode_alphanumeric()) == 2)
  assert_true(@qr.mode_bits(@qr.mode_byte()) == 4)
}

///|
test "segment: char_count_bits byte mode" {
  // Byte mode: V1-9 -> 8, V10-26 -> 16, V27-40 -> 16.
  let m = @qr.mode_byte()
  for v = 1; v <= 9; v = v + 1 {
    assert_true(@qr.char_count_bits(m, v) == 8)
  }
  for v = 10; v <= 26; v = v + 1 {
    assert_true(@qr.char_count_bits(m, v) == 16)
  }
  for v = 27; v <= 40; v = v + 1 {
    assert_true(@qr.char_count_bits(m, v) == 16)
  }
}

///|
test "segment: char_count_bits numeric mode" {
  // Numeric mode: V1-9 -> 10, V10-26 -> 12, V27-40 -> 14.
  let m = @qr.mode_numeric()
  for v = 1; v <= 9; v = v + 1 {
    assert_true(@qr.char_count_bits(m, v) == 10)
  }
  for v = 10; v <= 26; v = v + 1 {
    assert_true(@qr.char_count_bits(m, v) == 12)
  }
  for v = 27; v <= 40; v = v + 1 {
    assert_true(@qr.char_count_bits(m, v) == 14)
  }
}

///|
test "segment: char_count_bits alphanumeric mode" {
  // Alphanumeric mode: V1-9 -> 9, V10-26 -> 11, V27-40 -> 13.
  let m = @qr.mode_alphanumeric()
  for v = 1; v <= 9; v = v + 1 {
    assert_true(@qr.char_count_bits(m, v) == 9)
  }
  for v = 10; v <= 26; v = v + 1 {
    assert_true(@qr.char_count_bits(m, v) == 11)
  }
  for v = 27; v <= 40; v = v + 1 {
    assert_true(@qr.char_count_bits(m, v) == 13)
  }
}

///|
test "segment: char_count_bits version boundaries" {
  // Boundary jumps at V9->V10 and V26->V27 for each mode.
  let nm = @qr.mode_numeric()
  assert_true(@qr.char_count_bits(nm, 9) == 10)
  assert_true(@qr.char_count_bits(nm, 10) == 12)
  assert_true(@qr.char_count_bits(nm, 26) == 12)
  assert_true(@qr.char_count_bits(nm, 27) == 14)
  let am = @qr.mode_alphanumeric()
  assert_true(@qr.char_count_bits(am, 9) == 9)
  assert_true(@qr.char_count_bits(am, 10) == 11)
  assert_true(@qr.char_count_bits(am, 26) == 11)
  assert_true(@qr.char_count_bits(am, 27) == 13)
  let bm = @qr.mode_byte()
  assert_true(@qr.char_count_bits(bm, 9) == 8)
  assert_true(@qr.char_count_bits(bm, 10) == 16)
  assert_true(@qr.char_count_bits(bm, 26) == 16)
  assert_true(@qr.char_count_bits(bm, 27) == 16)
}

///|
test "segment: make bytes basic" {
  let data = FixedArray::make(2, 0)
  data[0] = 0x48
  data[1] = 0x65
  let seg = @qr.Segment::make_bytes(data)
  assert_true(seg.num_chars() == 2)
  assert_true(mode_eq(seg.mode(), @qr.mode_byte()))
}

///|
test "segment: make bytes empty" {
  let data = FixedArray::make(0, 0)
  let seg = @qr.Segment::make_bytes(data)
  assert_true(seg.num_chars() == 0)
}

///|
test "segment: make bytes single" {
  let data = FixedArray::make(1, 0x00)
  let seg = @qr.Segment::make_bytes(data)
  assert_true(seg.num_chars() == 1)
}

///|
test "segment: make bytes data access" {
  // make_bytes appends 8 bits per byte, MSB first.
  // 0x48 = 01001000, 0x65 = 01100101.
  let data = FixedArray::make(2, 0)
  data[0] = 0x48
  data[1] = 0x65
  let seg = @qr.Segment::make_bytes(data)
  let bb = seg.data()
  // 2 bytes = 16 bits.
  assert_true(bb.length() == 16)
  // First byte 0x48 = 0 1 0 0 1 0 0 0.
  assert_true(bb.bit_at(0) == 0)
  assert_true(bb.bit_at(1) == 1)
  assert_true(bb.bit_at(2) == 0)
  assert_true(bb.bit_at(3) == 0)
  assert_true(bb.bit_at(4) == 1)
  assert_true(bb.bit_at(5) == 0)
  assert_true(bb.bit_at(6) == 0)
  assert_true(bb.bit_at(7) == 0)
  // Second byte 0x65 = 0 1 1 0 0 1 0 1.
  assert_true(bb.bit_at(8) == 0)
  assert_true(bb.bit_at(9) == 1)
  assert_true(bb.bit_at(10) == 1)
  assert_true(bb.bit_at(11) == 0)
  assert_true(bb.bit_at(12) == 0)
  assert_true(bb.bit_at(13) == 1)
  assert_true(bb.bit_at(14) == 0)
  assert_true(bb.bit_at(15) == 1)
}

///|
test "segment: segment mode correct" {
  // make_bytes always creates a byte-mode segment.
  let data = FixedArray::make(3, 0x41)
  let seg = @qr.Segment::make_bytes(data)
  assert_true(mode_eq(seg.mode(), @qr.mode_byte()))
}

///|
test "segment: segment num_chars matches data length" {
  // num_chars() == data.length() for make_bytes across sizes 0..10.
  for n = 0; n <= 10; n = n + 1 {
    let data = FixedArray::make(n, 0x42)
    let seg = @qr.Segment::make_bytes(data)
    assert_true(seg.num_chars() == data.length())
  }
}

///|
test "segment: total bits calculation" {
  // For a byte segment of k bytes at version v:
  // total = 4 (mode bits) + char_count_bits(byte, v) + k*8 (data bits).
  let data = FixedArray::make(5, 0x41)
  let seg = @qr.Segment::make_bytes(data)
  // V1 byte: 4 + 8 + 40 = 52.
  let v1 = 1
  let expected_v1 = 4 + @qr.char_count_bits(@qr.mode_byte(), v1) + 5 * 8
  assert_true(expected_v1 == 52)
  // Verify via seg properties.
  let seg_total = 4 + @qr.char_count_bits(seg.mode(), v1) + seg.data().length()
  assert_true(seg_total == expected_v1)
  // V10 byte: 4 + 16 + 40 = 60.
  let v10 = 10
  let expected_v10 = 4 + @qr.char_count_bits(@qr.mode_byte(), v10) + 5 * 8
  assert_true(expected_v10 == 60)
  // V27 byte: 4 + 16 + 40 = 60.
  let v27 = 27
  let expected_v27 = 4 + @qr.char_count_bits(@qr.mode_byte(), v27) + 5 * 8
  assert_true(expected_v27 == 60)
}

///|
test "segment: numeric mode more efficient than byte" {
  // For pure numeric data, numeric mode packs 3 digits into 10 bits,
  // while byte mode packs 3 bytes into 24 bits. The data-bit savings
  // dominate, making numeric total bits smaller.
  // Numeric total (V1): 4 + 10 + 10 = 24.
  // Byte total (V1):    4 + 8  + 24 = 36.
  let v = 1
  let numeric_total = 4 + @qr.char_count_bits(@qr.mode_numeric(), v) + 10
  let byte_total = 4 + @qr.char_count_bits(@qr.mode_byte(), v) + 24
  assert_true(numeric_total < byte_total)
  // char_count_bits relationship varies by version group:
  // V1-9: numeric(10) > byte(8); V10-40: numeric(12/14) < byte(16).
  for ver = 1; ver <= 9; ver = ver + 1 {
    let n = @qr.char_count_bits(@qr.mode_numeric(), ver)
    let b = @qr.char_count_bits(@qr.mode_byte(), ver)
    assert_true(n > b)
  }
  for ver = 10; ver <= 40; ver = ver + 1 {
    let n = @qr.char_count_bits(@qr.mode_numeric(), ver)
    let b = @qr.char_count_bits(@qr.mode_byte(), ver)
    assert_true(n < b)
  }
}
