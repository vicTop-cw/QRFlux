///|
test "package header serialize/parse" {
  let header = @qr.PackageHeader::make(100, 100, 0x12345678, true, 1)
  let bytes = header.to_bytes()
  let parsed = @qr.PackageHeader::from_bytes(bytes)

  assert_true(parsed is Some(_))
  let h = parsed.unwrap()
  assert_true(h.data_length == 100)
  assert_true(h.original_size == 100)
  assert_true(h.checksum == 0x12345678)
  assert_true(h.is_compressed())
  assert_true(h.compression_algo() == 1)
}

///|
test "package header invalid magic" {
  let bytes = FixedArray::make(32, 0)
  bytes[0] = 0x58 // Wrong magic
  let parsed = @qr.PackageHeader::from_bytes(bytes)
  assert_true(parsed is None)
}

///|
test "crc32 basic" {
  let data = FixedArray::make(4, 0)
  data[0] = 0x01
  data[1] = 0x02
  data[2] = 0x03
  data[3] = 0x04
  let crc = @qr.crc32(data)
  // Standard CRC32([0x01,0x02,0x03,0x04]) = 0xB63CFBCD = 3057449933.
  // As signed Int32 this is -1237517363 (high bit set).
  // Variant contrast: if crc32 reverts to arithmetic >> without & 0x7FFFFFFF,
  // this assertion fails — the buggy shift produces a different value.
  assert_true(crc == -1237517363)
}

///|
test "crc32 variant: 100 bytes of 0x42" {
  let data = FixedArray::make(100, 0x42)
  let crc = @qr.crc32(data)
  // Standard CRC32(100 * 0x42) = 535209010 (positive, fits in Int31).
  // Variant contrast: arithmetic >> bug would give a different value.
  assert_true(crc == 535209010)
}

///|
test "package and unpackage" {
  let data = FixedArray::make(100, 0x42)
  let pkg = @qr.package_with_header(data, 0, false)

  assert_true(pkg.length() == 32 + 100)

  let result = @qr.unpackage_from_header(pkg)
  assert_true(result is Some(_))
  let (payload, original_size, compressed, algo) = result.unwrap()

  assert_true(payload.length() == 100)
  assert_true(original_size == 100)
  assert_true(!compressed)
  assert_true(algo == 0)

  // Verify content
  for i = 0; i < 100; i = i + 1 {
    assert_true(payload[i] == 0x42)
  }
}

///|
test "package and unpackage compressed" {
  let data = FixedArray::make(50, 0x99)
  let pkg = @qr.package_with_header(data, 1, true)

  let result = @qr.unpackage_from_header(pkg)
  assert_true(result is Some(_))
  let (_, original_size, is_compressed, algo) = result.unwrap()

  assert_true(is_compressed)
  assert_true(original_size == 50)
  assert_true(algo == 1)
}

///|
test "unpackage short data" {
  let short = FixedArray::make(10, 0)
  let result = @qr.unpackage_from_header(short)
  assert_true(result is None)
}

///|
test "unpackage corrupted checksum" {
  let data = FixedArray::make(50, 0x99)
  let pkg = @qr.package_with_header(data, 0, false)

  // Corrupt a byte
  pkg[40] = 0x00

  let result = @qr.unpackage_from_header(pkg)
  assert_true(result is None)
}

///|
test "package header is compressed" {
  let header1 = @qr.PackageHeader::make(100, 100, 0x1234, false, 0)
  assert_true(!header1.is_compressed())
  assert_true(header1.compression_algo() == 0)

  let header2 = @qr.PackageHeader::make(50, 100, 0x5678, true, 1)
  assert_true(header2.is_compressed())
  assert_true(header2.compression_algo() == 1)
}

///|
test "compression algo field serialize roundtrip" {
  // Test algo=0 (no compression)
  let h0 = @qr.PackageHeader::make(10, 10, 0xABCDEF01, false, 0)
  let b0 = h0.to_bytes()
  // compression_algo is at byte offset 6
  assert_true(b0[6] == 0)
  let p0 = @qr.PackageHeader::from_bytes(b0).unwrap()
  assert_true(p0.compression_algo() == 0)

  // Test algo=1 (RLE)
  let h1 = @qr.PackageHeader::make(10, 20, 0xABCDEF02, true, 1)
  let b1 = h1.to_bytes()
  assert_true(b1[6] == 1)
  let p1 = @qr.PackageHeader::from_bytes(b1).unwrap()
  assert_true(p1.compression_algo() == 1)

  // Test algo=2 (deflate reserved)
  let h2 = @qr.PackageHeader::make(10, 30, 0xABCDEF03, true, 2)
  let b2 = h2.to_bytes()
  assert_true(b2[6] == 2)
  let p2 = @qr.PackageHeader::from_bytes(b2).unwrap()
  assert_true(p2.compression_algo() == 2)
}

///|
test "package algo id passthrough" {
  let data = FixedArray::make(30, 0x77)
  // algo=1 (RLE), compressed=true
  let pkg = @qr.package_with_header(data, 1, true)
  let result = @qr.unpackage_from_header(pkg)
  assert_true(result is Some(_))
  let (_, _, compressed, algo) = result.unwrap()
  assert_true(compressed)
  assert_true(algo == 1)

  // algo=0, compressed=false
  let pkg2 = @qr.package_with_header(data, 0, false)
  let result2 = @qr.unpackage_from_header(pkg2)
  assert_true(result2 is Some(_))
  let (_, _, compressed2, algo2) = result2.unwrap()
  assert_true(!compressed2)
  assert_true(algo2 == 0)
}

///|
test "package header 32 bytes layout" {
  // Verify header is still 32 bytes after adding compression_algo field
  let header = @qr.PackageHeader::make(100, 100, 0x12345678, true, 1)
  let bytes = header.to_bytes()
  assert_true(bytes.length() == 32)
  // Verify field offsets: magic[0..4], version[4], flags[5], algo[6]
  assert_true(bytes[0] == 0x51)
  assert_true(bytes[1] == 0x52)
  assert_true(bytes[2] == 0x46)
  assert_true(bytes[3] == 0x58)
  assert_true(bytes[4] == 1) // version
  assert_true(bytes[5] == 0x01) // flags (compressed)
  assert_true(bytes[6] == 1) // compression_algo
}
