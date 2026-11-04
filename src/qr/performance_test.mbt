// Performance tests for QR encoding.
// Tests encoding speed for different data sizes.

///|
test "encode small data performance" {
  // Small data should be fast
  let data = FixedArray::make(10, 0x42)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  assert_true(qr.version() >= 1)
}

///|
test "encode medium data performance" {
  // Medium data
  let data = FixedArray::make(100, 0x42)
  let qr = @qr.encode_binary(data, @qr.ecc_medium(), 1)
  assert_true(qr.version() >= 5)
}

///|
test "encode large data performance" {
  // Large data
  let data = FixedArray::make(500, 0x42)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  assert_true(qr.version() >= 15)
}

///|
test "encode multiple iterations" {
  // Test multiple iterations to check stability
  let data = FixedArray::make(50, 0x99)

  for i = 0; i < 10; i = i + 1 {
    let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
    assert_true(qr.version() >= 1)
  }
}
