// Strategy extra tests.
// Tests RLE compress/decompress, compress levels, compression_ratio, edge cases.

///|
/// Helper: make a FixedArray from a literal array of small ints.
fn strat_mk_bytes(xs : Array[Int32]) -> FixedArray[Int32] {
  let fa = FixedArray::make(xs.length(), 0)
  for i = 0; i < xs.length(); i = i + 1 {
    fa[i] = xs[i]
  }
  fa
}

///|
/// Helper: check two FixedArray[Int32] equal.
fn strat_bytes_eq(a : FixedArray[Int32], b : FixedArray[Int32]) -> Bool {
  if a.length() != b.length() {
    return false
  }
  for i = 0; i < a.length(); i = i + 1 {
    if a[i] != b[i] {
      return false
    }
  }
  true
}

///|
/// Helper: make pseudo-random data.
fn strat_make_random(n : Int32, seed : Int32) -> FixedArray[Int32] {
  let fa = FixedArray::make(n, 0)
  let mut s = seed
  for i = 0; i < n; i = i + 1 {
    s = (s * 1103515245 + 12345) & 0x7FFFFFFF
    fa[i] = (s >> 16) & 0xFF
  }
  fa
}

///|
test "strategy extra: rle simple roundtrip" {
  // For runs < 255, rle_compress -> rle_decompress should be lossless.
  // (rle_compress uses optimized encoding with 255 marker for runs >= 255,
  //  but rle_decompress is the simple decoder that doesn't handle markers.
  //  So we only test with runs < 255 here.)
  let datasets = [
    strat_mk_bytes([1, 2, 3, 4, 5]),
    strat_mk_bytes([0x41, 0x41, 0x41, 0x42, 0x42]),
    strat_make_random(50, 7),
  ]
  for i = 0; i < datasets.length(); i = i + 1 {
    let data = datasets[i]
    let compressed = @qr.rle_compress(data)
    let decompressed = @qr.rle_decompress(compressed)
    assert_true(strat_bytes_eq(decompressed, data))
  }
}

///|
test "strategy extra: rle simple empty" {
  let data = FixedArray::make(0, 0)
  let compressed = @qr.rle_compress(data)
  assert_true(compressed.length() == 0)
  let decompressed = @qr.rle_decompress(compressed)
  assert_true(decompressed.length() == 0)
}

///|
test "strategy extra: rle simple all same" {
  // 100 identical bytes (run < 255, so rle_decompress can handle it).
  let data = FixedArray::make(100, 0x42)
  let compressed = @qr.rle_compress(data)
  let decompressed = @qr.rle_decompress(compressed)
  assert_true(strat_bytes_eq(decompressed, data))
}

///|
test "strategy extra: rle optimized roundtrip" {
  // rle_compress_optimized -> rle_decompress_optimized should be lossless
  // for any data, including long runs (>= 255).
  let datasets = [
    strat_mk_bytes([1, 2, 3]),
    FixedArray::make(300, 0x99), // Long run >= 255
    strat_make_random(100, 11),
    FixedArray::make(1000, 0x42), // Very long run
  ]
  for i = 0; i < datasets.length(); i = i + 1 {
    let data = datasets[i]
    let compressed = @qr.rle_compress_optimized(data)
    let decompressed = @qr.rle_decompress_optimized(compressed)
    assert_true(strat_bytes_eq(decompressed, data))
  }
}

///|
test "strategy extra: rle optimized vs simple consistency" {
  // For runs < 255, rle_decompress and rle_decompress_optimized should
  // produce the same result on rle_compress output.
  let data = strat_mk_bytes([0x41, 0x41, 0x41, 0x42, 0x43, 0x43])
  let compressed = @qr.rle_compress(data)
  let decomp_simple = @qr.rle_decompress(compressed)
  let decomp_optimized = @qr.rle_decompress_optimized(compressed)
  assert_true(strat_bytes_eq(decomp_simple, decomp_optimized))
}

///|
test "strategy extra: compress no_compress level" {
  // NoCompress level: compress is identity, decompress is identity.
  let data = strat_make_random(50, 3)
  let compressed = @qr.compress(data, @qr.no_compress())
  assert_true(strat_bytes_eq(compressed, data))
  let decompressed = @qr.decompress(compressed, @qr.no_compress())
  assert_true(strat_bytes_eq(decompressed, data))
}

///|
test "strategy extra: compress fast_compress level" {
  // Fast level: rle_compress -> rle_decompress_optimized roundtrip.
  let data = strat_make_random(50, 5)
  let compressed = @qr.compress(data, @qr.fast_compress())
  let decompressed = @qr.decompress(compressed, @qr.fast_compress())
  assert_true(strat_bytes_eq(decompressed, data))
}

///|
test "strategy extra: compress best_compress level" {
  // Best level: rle_compress -> rle_decompress_optimized roundtrip.
  let data = strat_make_random(50, 9)
  let compressed = @qr.compress(data, @qr.best_compress())
  let decompressed = @qr.decompress(compressed, @qr.best_compress())
  assert_true(strat_bytes_eq(decompressed, data))
}

///|
test "strategy extra: compress empty all levels" {
  // Empty data through all compression levels.
  let data = FixedArray::make(0, 0)
  let levels = [@qr.no_compress(), @qr.fast_compress(), @qr.best_compress()]
  for i = 0; i < levels.length(); i = i + 1 {
    let compressed = @qr.compress(data, levels[i])
    assert_true(compressed.length() == 0)
    let decompressed = @qr.decompress(compressed, levels[i])
    assert_true(decompressed.length() == 0)
  }
}

///|
test "strategy extra: compression_ratio various" {
  // compression_ratio returns compressed.length / original.length.
  // For empty original, returns 0.0.
  let empty = FixedArray::make(0, 0)
  assert_true(@qr.compression_ratio(empty, empty) == 0.0)
  // For original 100 bytes, compressed 50 bytes -> ratio 0.5.
  let orig = FixedArray::make(100, 0x42)
  let comp = FixedArray::make(50, 0x42)
  let r = @qr.compression_ratio(orig, comp)
  assert_true(r == 0.5)
  // For original 10 bytes, compressed 20 bytes -> ratio 2.0.
  let orig2 = FixedArray::make(10, 0x42)
  let comp2 = FixedArray::make(20, 0x42)
  let r2 = @qr.compression_ratio(orig2, comp2)
  assert_true(r2 == 2.0)
}

///|
test "strategy extra: single byte all functions" {
  // Single byte through all compression functions.
  let data = strat_mk_bytes([0x42])
  // rle_compress -> rle_decompress
  let c1 = @qr.rle_compress(data)
  let d1 = @qr.rle_decompress(c1)
  assert_true(strat_bytes_eq(d1, data))
  // rle_compress_optimized -> rle_decompress_optimized
  let c2 = @qr.rle_compress_optimized(data)
  let d2 = @qr.rle_decompress_optimized(c2)
  assert_true(strat_bytes_eq(d2, data))
  // compress/decompress all levels
  let levels = [@qr.no_compress(), @qr.fast_compress(), @qr.best_compress()]
  for i = 0; i < levels.length(); i = i + 1 {
    let compressed = @qr.compress(data, levels[i])
    let decompressed = @qr.decompress(compressed, levels[i])
    assert_true(strat_bytes_eq(decompressed, data))
  }
}

///|
test "strategy extra: two distinct bytes" {
  // Two different bytes through all compression functions.
  let data = strat_mk_bytes([0x41, 0x42])
  let c1 = @qr.rle_compress(data)
  let d1 = @qr.rle_decompress(c1)
  assert_true(strat_bytes_eq(d1, data))
  let c2 = @qr.rle_compress_optimized(data)
  let d2 = @qr.rle_decompress_optimized(c2)
  assert_true(strat_bytes_eq(d2, data))
  let levels = [@qr.no_compress(), @qr.fast_compress(), @qr.best_compress()]
  for i = 0; i < levels.length(); i = i + 1 {
    let compressed = @qr.compress(data, levels[i])
    let decompressed = @qr.decompress(compressed, levels[i])
    assert_true(strat_bytes_eq(decompressed, data))
  }
}
