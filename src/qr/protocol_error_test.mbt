// Protocol error path tests.
// Tests FrameHeader/PackageHeader from_bytes error paths, CRC functions,
// and roundtrip correctness.

///|
/// Helper: make a FixedArray from a literal array of small ints.
fn proto_mk_bytes(xs : Array[Int32]) -> FixedArray[Int32] {
  let fa = FixedArray::make(xs.length(), 0)
  for i = 0; i < xs.length(); i = i + 1 {
    fa[i] = xs[i]
  }
  fa
}

///|
test "protocol error: frame header empty" {
  // Empty array: length < 16 -> None.
  let bytes = FixedArray::make(0, 0)
  let result = @qr.FrameHeader::from_bytes(bytes)
  assert_true(result is None)
}

///|
test "protocol error: frame header too short" {
  // Length 15 < 16 -> None.
  let bytes = FixedArray::make(15, 0)
  let result = @qr.FrameHeader::from_bytes(bytes)
  assert_true(result is None)
}

///|
test "protocol error: frame header bad magic" {
  // Valid length but wrong magic bytes.
  let bytes = FixedArray::make(16, 0)
  bytes[0] = 0x00 // Wrong magic (should be 0x51 'Q')
  bytes[4] = 1 // Valid version
  let result = @qr.FrameHeader::from_bytes(bytes)
  assert_true(result is None)
}

///|
test "protocol error: frame header crc mismatch" {
  // Construct valid frames, then corrupt payload so CRC16 mismatches.
  // reassemble_frames should return None on checksum failure.
  let data = FixedArray::make(100, 0x42)
  let frames = @qr.split_into_frames(data, 50)
  // Corrupt a payload byte in frame 0 (offset 16+ is payload).
  frames[0][20] = 0x00
  let result = @qr.reassemble_frames(frames)
  assert_true(result is None)
}

///|
test "protocol error: package header empty" {
  // Empty array: length < 32 -> None.
  let bytes = FixedArray::make(0, 0)
  let result = @qr.PackageHeader::from_bytes(bytes)
  assert_true(result is None)
}

///|
test "protocol error: package header too short" {
  // Length 31 < 32 -> None.
  let bytes = FixedArray::make(31, 0)
  let result = @qr.PackageHeader::from_bytes(bytes)
  assert_true(result is None)
}

///|
test "protocol error: package header bad magic" {
  // Valid length but wrong magic bytes.
  let bytes = FixedArray::make(32, 0)
  bytes[0] = 0x00 // Wrong magic (should be 0x51 'Q')
  bytes[4] = 1 // Valid version
  let result = @qr.PackageHeader::from_bytes(bytes)
  assert_true(result is None)
}

///|
test "protocol error: package header crc mismatch" {
  // Construct a valid package, then corrupt payload so CRC32 mismatches.
  // unpackage_from_header should return None on checksum failure.
  let data = FixedArray::make(50, 0x99)
  let pkg = @qr.package_with_header(data, 0, false)
  // Corrupt a payload byte (offset 32+ is payload).
  pkg[40] = 0x00
  let result = @qr.unpackage_from_header(pkg)
  assert_true(result is None)
}

///|
test "protocol error: crc16 known values" {
  // CRC-16/XMODEM (init=0, poly=0x1021, no reflection) of "123456789"
  // Standard check value = 0x31C3.
  let data = proto_mk_bytes([
    0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39,
  ])
  let crc = @qr.crc16(data)
  assert_true(crc == 0x31C3)
}

///|
test "protocol error: crc32 known values" {
  // Standard CRC-32 (ISO-HDLC/zlib, poly=0xEDB88320, reflected) of
  // "123456789" = 0xCBF43926. As signed Int32: -873187034.
  let data = proto_mk_bytes([
    0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39,
  ])
  let crc = @qr.crc32(data)
  assert_true(crc == -873187034)
}

///|
test "protocol error: frame header roundtrip" {
  // make -> to_bytes -> from_bytes should preserve all fields.
  let header = @qr.FrameHeader::make(10, 3, 1000, 0xABCD)
  let bytes = header.to_bytes()
  match @qr.FrameHeader::from_bytes(bytes) {
    Some(h) => {
      assert_true(h.total_frames == 10)
      assert_true(h.current_frame == 3)
      assert_true(h.data_length == 1000)
      assert_true(h.checksum == 0xABCD)
    }
    None => abort("frame header roundtrip: from_bytes returned None")
  }
}

///|
test "protocol error: package header roundtrip" {
  // make -> to_bytes -> from_bytes should preserve all fields.
  let header = @qr.PackageHeader::make(200, 200, 0x12345678, true, 1)
  let bytes = header.to_bytes()
  match @qr.PackageHeader::from_bytes(bytes) {
    Some(h) => {
      assert_true(h.data_length == 200)
      assert_true(h.original_size == 200)
      assert_true(h.checksum == 0x12345678)
      assert_true(h.is_compressed())
      assert_true(h.compression_algo() == 1)
    }
    None => abort("package header roundtrip: from_bytes returned None")
  }
}
