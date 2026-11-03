test "package header serialize/parse" {
  let header = @qr.PackageHeader::make(100, 100, 0x12345678, true)
  let bytes = header.to_bytes()
  let parsed = @qr.PackageHeader::from_bytes(bytes)
  
  assert_true(parsed is Some(_))
  let h = parsed.unwrap()
  assert_true(h.data_length == 100)
  assert_true(h.original_size == 100)
  assert_true(h.checksum == 0x12345678)
  assert_true(h.is_compressed())
}

test "package header invalid magic" {
  let bytes = FixedArray::make(32, 0)
  bytes[0] = 0x58  // Wrong magic
  let parsed = @qr.PackageHeader::from_bytes(bytes)
  assert_true(parsed is None)
}

test "crc32 basic" {
  let data = FixedArray::make(4, 0)
  data[0] = 0x01
  data[1] = 0x02
  data[2] = 0x03
  data[3] = 0x04
  let crc = @qr.crc32(data)
  // CRC32 should be a valid 32-bit value
  assert_true(crc >= 0)
}

test "package and unpackage" {
  let data = FixedArray::make(100, 0x42)
  let pkg = @qr.package_with_header(data, false)
  
  assert_true(pkg.length() == 32 + 100)
  
  let result = @qr.unpackage_from_header(pkg)
  assert_true(result is Some(_))
  let (payload, original_size, compressed) = result.unwrap()
  
  assert_true(payload.length() == 100)
  assert_true(original_size == 100)
  assert_true(!compressed)
  
  // Verify content
  for i = 0; i < 100; i = i + 1 {
    assert_true(payload[i] == 0x42)
  }
}

test "package and unpackage compressed" {
  let data = FixedArray::make(50, 0x99)
  let pkg = @qr.package_with_header(data, true)
  
  let result = @qr.unpackage_from_header(pkg)
  assert_true(result is Some(_))
  let (payload, original_size, is_compressed) = result.unwrap()
  
  assert_true(is_compressed)
  assert_true(original_size == 50)
}

test "unpackage short data" {
  let short = FixedArray::make(10, 0)
  let result = @qr.unpackage_from_header(short)
  assert_true(result is None)
}

test "unpackage corrupted checksum" {
  let data = FixedArray::make(50, 0x99)
  let pkg = @qr.package_with_header(data, false)
  
  // Corrupt a byte
  pkg[40] = 0x00
  
  let result = @qr.unpackage_from_header(pkg)
  assert_true(result is None)
}

test "package header is compressed" {
  let header1 = @qr.PackageHeader::make(100, 100, 0x1234, false)
  assert_true(!header1.is_compressed())
  
  let header2 = @qr.PackageHeader::make(50, 100, 0x5678, true)
  assert_true(header2.is_compressed())
}
