///|
test "encode small binary" {
  let data = FixedArray::make(10, 0)
  for i = 0; i < 10; i = i + 1 {
    data[i] = i
  }
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  assert_true(qr.version() >= 1)
  assert_true(qr.size() == qr.version() * 4 + 17)
  // Finder corners must be dark.
  assert_true(qr.get_module(0, 0))
  assert_true(qr.get_module(qr.size() - 1, 0))
  assert_true(qr.get_module(0, qr.size() - 1))
  // Format bit area not empty: dark module at (8, size-8).
  assert_true(qr.get_module(8, qr.size() - 8))
}

///|
test "capacity v40 L" {
  assert_true(@qr.num_data_codewords(40, @qr.ecc_low()) == 2956)
  assert_true(@qr.num_data_codewords(40, @qr.ecc_high()) == 1276)
}

///|
test "encode max binary v40 L" {
  // V40 Low max data bytes = 2953, leave room for overhead
  let n = 2900
  let data = FixedArray::make(n, 0x42)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  assert_true(qr.version() == 40)
  assert_true(qr.level() == @qr.ecc_low())
}

///|
test "align positions v2" {
  let p = @qr.alignment_pattern_positions(2)
  assert_true(p.length() == 2)
  assert_true(p[0] == 6)
  assert_true(p[1] == 18)
}
