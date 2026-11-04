///|
test "static pipeline small data roundtrip" {
  // 10 bytes of sequential data
  let data = FixedArray::make(10, 0)
  for i = 0; i < 10; i = i + 1 {
    data[i] = i
  }
  let result = @qr.encode_static(data, @qr.ecc_medium(), 1)
  assert_true(result is Some(_))
  let r = result.unwrap()
  assert_true(r.original_size() == 10)
  assert_true(r.packaged_size() > 10)

  let decoded = @qr.decode_static(r.packaged_bytes())
  assert_true(decoded is Some(_))
  let d = decoded.unwrap()
  assert_true(d.length() == 10)
  for i = 0; i < 10; i = i + 1 {
    assert_true(d[i] == data[i])
  }
}

///|
test "static pipeline medium data roundtrip" {
  // 100 bytes of varying data
  let data = FixedArray::make(100, 0)
  for i = 0; i < 100; i = i + 1 {
    data[i] = (i * 7 + 3) % 256
  }
  let result = @qr.encode_static(data, @qr.ecc_medium(), 1)
  assert_true(result is Some(_))
  let r = result.unwrap()
  assert_true(r.original_size() == 100)

  let decoded = @qr.decode_static(r.packaged_bytes())
  assert_true(decoded is Some(_))
  let d = decoded.unwrap()
  assert_true(d.length() == 100)
  for i = 0; i < 100; i = i + 1 {
    assert_true(d[i] == data[i])
  }
}

///|
test "static pipeline large data roundtrip" {
  // 1000 bytes of data
  let data = FixedArray::make(1000, 0)
  for i = 0; i < 1000; i = i + 1 {
    data[i] = i % 256
  }
  let result = @qr.encode_static(data, @qr.ecc_low(), 1)
  assert_true(result is Some(_))
  let r = result.unwrap()
  assert_true(r.original_size() == 1000)

  let decoded = @qr.decode_static(r.packaged_bytes())
  assert_true(decoded is Some(_))
  let d = decoded.unwrap()
  assert_true(d.length() == 1000)
  for i = 0; i < 1000; i = i + 1 {
    assert_true(d[i] == data[i])
  }
}

///|
test "static pipeline highly repetitive triggers RLE" {
  // 200 bytes of the same value -> high repeat ratio -> FastRLE -> algo=1
  let data = FixedArray::make(200, 0xAA)
  let result = @qr.encode_static(data, @qr.ecc_medium(), 1)
  assert_true(result is Some(_))
  let r = result.unwrap()
  // Should be compressed with RLE (algo_id == 1)
  assert_true(r.compressed())
  assert_true(r.algo_id() == 1)
  assert_true(r.original_size() == 200)

  let decoded = @qr.decode_static(r.packaged_bytes())
  assert_true(decoded is Some(_))
  let d = decoded.unwrap()
  assert_true(d.length() == 200)
  for i = 0; i < 200; i = i + 1 {
    assert_true(d[i] == 0xAA)
  }
}

///|
test "static pipeline no compression algo zero" {
  // Small data (< 10 bytes) -> NoCompress strategy -> algo=0
  let data = FixedArray::make(5, 0)
  data[0] = 0x48
  data[1] = 0x65
  data[2] = 0x6C
  data[3] = 0x6C
  data[4] = 0x6F
  let result = @qr.encode_static(data, @qr.ecc_medium(), 1)
  assert_true(result is Some(_))
  let r = result.unwrap()
  assert_true(!r.compressed())
  assert_true(r.algo_id() == 0)
  assert_true(r.original_size() == 5)

  let decoded = @qr.decode_static(r.packaged_bytes())
  assert_true(decoded is Some(_))
  let d = decoded.unwrap()
  assert_true(d.length() == 5)
  for i = 0; i < 5; i = i + 1 {
    assert_true(d[i] == data[i])
  }
}

///|
test "static pipeline ecc level low" {
  let data = FixedArray::make(50, 0x42)
  let result = @qr.encode_static(data, @qr.ecc_low(), 1)
  assert_true(result is Some(_))
  let r = result.unwrap()
  let decoded = @qr.decode_static(r.packaged_bytes())
  assert_true(decoded is Some(_))
  let d = decoded.unwrap()
  assert_true(d.length() == 50)
  for i = 0; i < 50; i = i + 1 {
    assert_true(d[i] == 0x42)
  }
}

///|
test "static pipeline ecc level medium" {
  let data = FixedArray::make(50, 0x33)
  let result = @qr.encode_static(data, @qr.ecc_medium(), 1)
  assert_true(result is Some(_))
  let r = result.unwrap()
  let decoded = @qr.decode_static(r.packaged_bytes())
  assert_true(decoded is Some(_))
  let d = decoded.unwrap()
  assert_true(d.length() == 50)
}

///|
test "static pipeline ecc level quartile" {
  let data = FixedArray::make(50, 0x55)
  let result = @qr.encode_static(data, @qr.ecc_quartile(), 1)
  assert_true(result is Some(_))
  let r = result.unwrap()
  let decoded = @qr.decode_static(r.packaged_bytes())
  assert_true(decoded is Some(_))
  let d = decoded.unwrap()
  assert_true(d.length() == 50)
  for i = 0; i < 50; i = i + 1 {
    assert_true(d[i] == 0x55)
  }
}

///|
test "static pipeline ecc level high" {
  let data = FixedArray::make(50, 0x77)
  let result = @qr.encode_static(data, @qr.ecc_high(), 1)
  assert_true(result is Some(_))
  let r = result.unwrap()
  let decoded = @qr.decode_static(r.packaged_bytes())
  assert_true(decoded is Some(_))
  let d = decoded.unwrap()
  assert_true(d.length() == 50)
  for i = 0; i < 50; i = i + 1 {
    assert_true(d[i] == 0x77)
  }
}

///|
test "static pipeline too large returns none" {
  // 5000 bytes of random-ish data: cannot fit in a single QR at high ECC.
  // RLE will expand random data, so encoder falls back to no compression,
  // yielding a 5032-byte package that exceeds V40-H capacity (~1273 bytes).
  let data = FixedArray::make(5000, 0)
  for i = 0; i < 5000; i = i + 1 {
    data[i] = (i * 31 + 17) % 256
  }
  let result = @qr.encode_static(data, @qr.ecc_high(), 1)
  assert_true(result is None)
}

///|
test "static pipeline encode result fields" {
  // Verify all StaticEncodeResult fields are populated correctly.
  let data = FixedArray::make(150, 0xCC)
  let result = @qr.encode_static(data, @qr.ecc_medium(), 1)
  assert_true(result is Some(_))
  let r = result.unwrap()
  // QR code object should be valid
  assert_true(r.qr().version() >= 1)
  assert_true(r.qr().version() <= 40)
  assert_true(r.qr().size() >= 21)
  // Metadata
  assert_true(r.original_size() == 150)
  assert_true(r.packaged_size() == r.packaged_bytes().length())
  // 150 identical bytes -> high repeat -> RLE compression
  assert_true(r.compressed())
  assert_true(r.algo_id() == 1)
}

///|
test "static pipeline decode invalid input returns none" {
  // Too short to contain a header
  let short = FixedArray::make(10, 0)
  assert_true(@qr.decode_static(short) is None)

  // Invalid magic
  let bad = FixedArray::make(40, 0)
  bad[0] = 0x00
  assert_true(@qr.decode_static(bad) is None)
}

///|
test "static pipeline algo id embedded in packaged bytes" {
  // Verify the algo_id is actually stored at byte offset 6 of the packaged bytes.
  let data = FixedArray::make(200, 0xBB)
  let result = @qr.encode_static(data, @qr.ecc_medium(), 1)
  assert_true(result is Some(_))
  let r = result.unwrap()
  let pkg = r.packaged_bytes()
  // Byte 6 is the compression_algo field
  assert_true(pkg[6] == r.algo_id())
  // For repetitive data, algo should be 1 (RLE)
  assert_true(pkg[6] == 1)
  // Magic still intact
  assert_true(pkg[0] == 0x51)
  assert_true(pkg[1] == 0x52)
  assert_true(pkg[2] == 0x46)
  assert_true(pkg[3] == 0x58)
}
