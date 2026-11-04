// Error handling tests for QR encoding.
// Tests boundary conditions and error scenarios.

///|
test "encode empty data" {
  let data = FixedArray::make(0, 0)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  // Empty data should still produce a valid QR code
  assert_true(qr.version() >= 1)
}

///|
test "encode maximum v40 data" {
  // Test maximum capacity for V40-L
  let n = 2953 // V40-L capacity
  let data = FixedArray::make(n, 0x42)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 40)
  assert_true(qr.version() == 40)
}

///|
test "invalid version handling" {
  let data = FixedArray::make(10, 0x42)
  // Version 0 should auto-select
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 0)
  assert_true(qr.version() >= 1)
}

///|
test "stream empty data" {
  let data = FixedArray::make(0, 0)
  let frames = @qr.split_into_frames(data, 50)
  assert_true(frames.length() == 0)

  let reassembled = @qr.reassemble_frames(frames)
  assert_true(reassembled is None)
}

///|
test "reassemble corrupted frames" {
  let data = FixedArray::make(100, 0x42)
  let frames = @qr.split_into_frames(data, 50)

  // Corrupt a frame
  if frames.length() > 0 {
    frames[0][20] = 0x00
  }

  let reassembled = @qr.reassemble_frames(frames)
  // Should fail due to checksum
  assert_true(reassembled is None)
}

///|
test "reassemble missing frame" {
  let data = FixedArray::make(100, 0x42)
  let frames = @qr.split_into_frames(data, 50)

  // Remove a frame
  let frames_copy = Array::make(0, FixedArray::make(0, 0))
  for i = 0; i < frames.length(); i = i + 1 {
    if i != 1 {
      frames_copy.push(frames[i])
    }
  }

  let reassembled = @qr.reassemble_frames(frames_copy)
  // Should fail due to missing frame
  assert_true(reassembled is None)
}

///|
test "compress empty data" {
  let data = FixedArray::make(0, 0)
  let compressed = @qr.compress(data, @qr.fast_compress())
  assert_true(compressed.length() == 0)

  let decompressed = @qr.decompress(compressed, @qr.fast_compress())
  assert_true(decompressed.length() == 0)
}

///|
test "package empty data" {
  let data = FixedArray::make(0, 0)
  let pkg = @qr.package_with_header(data, 0, false)
  assert_true(pkg.length() > 0)

  let result = @qr.unpackage_from_header(pkg)
  assert_true(result is Some(_))
}

///|
test "package corrupted header" {
  let data = FixedArray::make(50, 0x99)
  let pkg = @qr.package_with_header(data, 0, false)

  // Corrupt magic bytes
  pkg[0] = 0x00

  let result = @qr.unpackage_from_header(pkg)
  // Should fail due to invalid magic
  assert_true(result is None)
}

///|
test "crc32 empty data" {
  let data = FixedArray::make(0, 0)
  let crc = @qr.crc32(data)
  // Standard CRC32 of empty input = 0.
  // Variant contrast: any shift bug still yields 0 here (no iterations),
  // so this guards the init/final XOR path rather than the shift.
  assert_true(crc == 0)
}
