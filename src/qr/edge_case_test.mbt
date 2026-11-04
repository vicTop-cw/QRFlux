// Edge case tests for QR encoding.
// Tests boundary conditions and error handling.

///|
test "encode at version boundary" {
  // Test data that fits exactly at version boundary
  let data = FixedArray::make(17, 0x42) // V1-L capacity
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  assert_true(qr.version() == 1)
}

///|
test "encode with different masks" {
  let data = FixedArray::make(50, 0x42)
  let qr = @qr.encode_binary(data, @qr.ecc_medium(), 8) // mask 8
  assert_true(qr.mask() >= 0 && qr.mask() <= 7)
}

///|
test "alignment pattern positions" {
  // Test alignment pattern positions for different versions
  let p1 = @qr.alignment_pattern_positions(1)
  assert_true(p1.length() == 0) // V1 has no alignment patterns

  let p2 = @qr.alignment_pattern_positions(2)
  assert_true(p2.length() == 2) // V2 has 2 positions

  let p7 = @qr.alignment_pattern_positions(7)
  assert_true(p7.length() > 0) // V7+ has alignment patterns
}

///|
test "format bits validation" {
  // Test format bits for different ECC levels
  let bits_L = @qr.format_bits(@qr.ecc_low())
  assert_true(bits_L == 1)

  let bits_M = @qr.format_bits(@qr.ecc_medium())
  assert_true(bits_M == 0)

  let bits_Q = @qr.format_bits(@qr.ecc_quartile())
  assert_true(bits_Q == 3)

  let bits_H = @qr.format_bits(@qr.ecc_high())
  assert_true(bits_H == 2)
}

///|
test "ecc tolerance values" {
  // Test ECC tolerance percentages
  assert_true(@qr.ecc_tolerance(@qr.ecc_low()) == 7)
  assert_true(@qr.ecc_tolerance(@qr.ecc_medium()) == 15)
  assert_true(@qr.ecc_tolerance(@qr.ecc_quartile()) == 25)
  assert_true(@qr.ecc_tolerance(@qr.ecc_high()) == 30)
}

///|
test "frame header edge cases" {
  // Test frame header with edge case values
  let header = @qr.FrameHeader::make(0, 0, 0, 0)
  let bytes = header.to_bytes()
  assert_true(bytes.length() == 16)

  let parsed = @qr.FrameHeader::from_bytes(bytes)
  assert_true(parsed is Some(_))
}
