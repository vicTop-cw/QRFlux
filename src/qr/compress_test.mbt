test "compression level from string" {
  assert_true(@qr.CompressionLevel::from_string("none") == @qr.no_compress())
  assert_true(@qr.CompressionLevel::from_string("fast") == @qr.fast_compress())
  assert_true(@qr.CompressionLevel::from_string("best") == @qr.best_compress())
  assert_true(@qr.CompressionLevel::from_string("unknown") == @qr.no_compress())
}

test "rle compress basic" {
  let data = FixedArray::make(5, 0x42)
  let compressed = @qr.rle_compress(data)
  
  // 5 bytes of 0x42 should compress to [5, 0x42]
  assert_true(compressed.length() == 2)
  assert_true(compressed[0] == 5)
  assert_true(compressed[1] == 0x42)
}

test "rle decompress basic" {
  let compressed = FixedArray::make(2, 0)
  compressed[0] = 5
  compressed[1] = 0x42
  
  let decompressed = @qr.rle_decompress(compressed)
  assert_true(decompressed.length() == 5)
  
  for i = 0; i < 5; i = i + 1 {
    assert_true(decompressed[i] == 0x42)
  }
}

test "rle compress decompress roundtrip" {
  let original = FixedArray::make(10, 0)
  for i = 0; i < 10; i = i + 1 {
    original[i] = if i < 5 { 0xAA } else { 0xBB }
  }
  
  let compressed = @qr.rle_compress(original)
  let decompressed = @qr.rle_decompress(compressed)
  
  assert_true(decompressed.length() == original.length())
  for i = 0; i < original.length(); i = i + 1 {
    assert_true(decompressed[i] == original[i])
  }
}

test "compress with level no compress" {
  let data = FixedArray::make(10, 0x42)
  let compressed = @qr.compress(data, @qr.no_compress())
  
  assert_true(compressed.length() == data.length())
  for i = 0; i < data.length(); i = i + 1 {
    assert_true(compressed[i] == data[i])
  }
}

test "compress with level fast" {
  let data = FixedArray::make(10, 0x42)
  let compressed = @qr.compress(data, @qr.fast_compress())
  
  // Should be compressed
  assert_true(compressed.length() <= data.length())
}

test "decompress roundtrip" {
  let original = FixedArray::make(10, 0x42)
  let compressed = @qr.compress(original, @qr.fast_compress())
  let decompressed = @qr.decompress(compressed, @qr.fast_compress())
  
  assert_true(decompressed.length() == original.length())
  for i = 0; i < original.length(); i = i + 1 {
    assert_true(decompressed[i] == original[i])
  }
}

test "compression ratio" {
  let original = FixedArray::make(100, 0xAA)
  let compressed = @qr.compress(original, @qr.fast_compress())
  let ratio = @qr.compression_ratio(original, compressed)
  
  // 100 bytes of same value should compress well
  assert_true(ratio < 0.1)
}

test "suggest compression level" {
  // Repeated data
  let repeated = FixedArray::make(100, 0x42)
  let level1 = @qr.suggest_compression_level(repeated)
  assert_true(level1 == @qr.fast_compress())
  
  // Random data
  let random = FixedArray::make(100, 0)
  for i = 0; i < 100; i = i + 1 {
    random[i] = i % 256
  }
  let level2 = @qr.suggest_compression_level(random)
  // Random data might or might not benefit from compression
  // Just verify it returns a valid level
  let valid = level2 == @qr.no_compress() || level2 == @qr.fast_compress()
  assert_true(valid)
}

test "empty data" {
  let empty = FixedArray::make(0, 0)
  let compressed = @qr.compress(empty, @qr.fast_compress())
  assert_true(compressed.length() == 0)
  
  let decompressed = @qr.decompress(compressed, @qr.fast_compress())
  assert_true(decompressed.length() == 0)
}
