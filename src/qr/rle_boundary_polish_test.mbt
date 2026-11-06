// RLE boundary polish tests.
// Blackbox tests for RLE compress/decompress boundary conditions:
// empty, single byte, all-same, all-distinct, run length boundaries
// (254/255/256/510/1000), mixed data, incompressible data expansion,
// all compression levels/strategies roundtrip, and select_strategy
// selection correctness across data sizes.

///|
/// Helper: make a FixedArray from a literal array of small ints.
fn rbp_mk_bytes(xs : Array[Int32]) -> FixedArray[Int32] {
  let fa = FixedArray::make(xs.length(), 0)
  for i = 0; i < xs.length(); i = i + 1 {
    fa[i] = xs[i]
  }
  fa
}

///|
/// Helper: check two FixedArray[Int32] equal.
fn rbp_bytes_eq(a : FixedArray[Int32], b : FixedArray[Int32]) -> Bool {
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
/// Helper: make pseudo-random data (LCG).
fn rbp_make_random(n : Int32, seed : Int32) -> FixedArray[Int32] {
  let fa = FixedArray::make(n, 0)
  let mut s = seed
  for i = 0; i < n; i = i + 1 {
    s = (s * 1103515245 + 12345) & 0x7FFFFFFF
    fa[i] = (s >> 16) & 0xFF
  }
  fa
}

///|
/// Helper: make n bytes of distinct values (i % 256), no adjacent repeats.
fn rbp_make_distinct(n : Int32) -> FixedArray[Int32] {
  let fa = FixedArray::make(n, 0)
  for i = 0; i < n; i = i + 1 {
    fa[i] = i % 256
  }
  fa
}

///|
test "rle boundary: empty input roundtrip" {
  let empty = FixedArray::make(0, 0)
  // rle_compress / rle_decompress
  let c1 = @qr.rle_compress(empty)
  assert_true(c1.length() == 0)
  let d1 = @qr.rle_decompress(c1)
  assert_true(d1.length() == 0)
  assert_true(rbp_bytes_eq(d1, empty))
  // optimized
  let c2 = @qr.rle_compress_optimized(empty)
  assert_true(c2.length() == 0)
  let d2 = @qr.rle_decompress_optimized(c2)
  assert_true(d2.length() == 0)
  assert_true(rbp_bytes_eq(d2, empty))
  // all levels
  let levels = [@qr.no_compress(), @qr.fast_compress(), @qr.best_compress()]
  for i = 0; i < levels.length(); i = i + 1 {
    let c = @qr.compress(empty, levels[i])
    assert_true(c.length() == 0)
    let d = @qr.decompress(c, levels[i])
    assert_true(d.length() == 0)
    assert_true(rbp_bytes_eq(d, empty))
  }
}

///|
test "rle boundary: single byte roundtrip" {
  let data = rbp_mk_bytes([0x42])
  let c1 = @qr.rle_compress(data)
  let d1 = @qr.rle_decompress(c1)
  assert_true(rbp_bytes_eq(d1, data))
  let c2 = @qr.rle_compress_optimized(data)
  let d2 = @qr.rle_decompress_optimized(c2)
  assert_true(rbp_bytes_eq(d2, data))
  // compress/decompress via levels
  let cf = @qr.compress(data, @qr.fast_compress())
  let df = @qr.decompress(cf, @qr.fast_compress())
  assert_true(rbp_bytes_eq(df, data))
  let cb = @qr.compress(data, @qr.best_compress())
  let db = @qr.decompress(cb, @qr.best_compress())
  assert_true(rbp_bytes_eq(db, data))
}

///|
test "rle boundary: all same 1000 zeros optimized roundtrip" {
  let data = FixedArray::make(1000, 0x00)
  let c = @qr.rle_compress_optimized(data)
  let d = @qr.rle_decompress_optimized(c)
  assert_true(rbp_bytes_eq(d, data))
  // One extended run = 4 bytes, much smaller than 1000.
  assert_true(c.length() == 4)
  assert_true(c.length() < data.length())
}

///|
test "rle boundary: all distinct bytes optimized roundtrip" {
  let n = 256
  let data = rbp_make_distinct(n)
  let c = @qr.rle_compress_optimized(data)
  let d = @qr.rle_decompress_optimized(c)
  assert_true(rbp_bytes_eq(d, data))
  // Each run=1 -> 2 bytes per original byte -> doubles to 512.
  assert_true(c.length() == 2 * n)
}

///|
test "rle boundary: run 254 last normal encoding" {
  // 254 < 255 -> normal 2-byte encoding [254, value].
  let data = FixedArray::make(254, 0x41)
  let c = @qr.rle_compress(data)
  assert_true(c.length() == 2)
  assert_true(c[0] == 254)
  assert_true(c[1] == 0x41)
  // Simple decompress can handle normal encoding.
  let d_simple = @qr.rle_decompress(c)
  assert_true(rbp_bytes_eq(d_simple, data))
  // Optimized decompress also handles it.
  let d_opt = @qr.rle_decompress_optimized(c)
  assert_true(rbp_bytes_eq(d_opt, data))
}

///|
test "rle boundary: run 255 first extended encoding" {
  // 255 >= 255 -> extended 4-byte encoding [255, 0, 255, value].
  let data = FixedArray::make(255, 0x42)
  let c = @qr.rle_compress(data)
  assert_true(c.length() == 4)
  assert_true(c[0] == 255)
  assert_true(c[1] == 0)
  assert_true(c[2] == 255)
  assert_true(c[3] == 0x42)
  // Must use optimized decompress for extended runs.
  let d = @qr.rle_decompress_optimized(c)
  assert_true(rbp_bytes_eq(d, data))
}

///|
test "rle boundary: run 256 extended encoding" {
  // 256 = 0x0100 -> [255, 1, 0, value].
  let data = FixedArray::make(256, 0x43)
  let c = @qr.rle_compress(data)
  assert_true(c.length() == 4)
  assert_true(c[0] == 255)
  assert_true(c[1] == 1)
  assert_true(c[2] == 0)
  assert_true(c[3] == 0x43)
  let d = @qr.rle_decompress_optimized(c)
  assert_true(rbp_bytes_eq(d, data))
}

///|
test "rle boundary: run 510 single extended block" {
  // 510 = 0x01FE -> [255, 1, 254, value]. Single block (count < 65535).
  let data = FixedArray::make(510, 0x44)
  let c = @qr.rle_compress(data)
  assert_true(c.length() == 4)
  assert_true(c[0] == 255)
  assert_true(c[1] == 1)
  assert_true(c[2] == 254)
  assert_true(c[3] == 0x44)
  let d = @qr.rle_decompress_optimized(c)
  assert_true(rbp_bytes_eq(d, data))
}

///|
test "rle boundary: run 1000 extended encoding" {
  // 1000 = 0x03E8 -> [255, 3, 232, value].
  let data = FixedArray::make(1000, 0x45)
  let c = @qr.rle_compress(data)
  assert_true(c.length() == 4)
  assert_true(c[0] == 255)
  assert_true(c[1] == 3)
  assert_true(c[2] == 232)
  assert_true(c[3] == 0x45)
  let d = @qr.rle_decompress_optimized(c)
  assert_true(rbp_bytes_eq(d, data))
}

///|
test "rle boundary: multiple extended blocks separated" {
  // 255 A + 1 B + 255 A + 1 C + 255 A forces 3 extended blocks + 2 normal.
  let total = 255 + 1 + 255 + 1 + 255
  let data = FixedArray::make(total, 0)
  let mut idx = 0
  for j = 0; j < 255; j = j + 1 {
    data[idx] = 0x41
    idx = idx + 1
  }
  data[idx] = 0x42
  idx = idx + 1
  for j = 0; j < 255; j = j + 1 {
    data[idx] = 0x41
    idx = idx + 1
  }
  data[idx] = 0x43
  idx = idx + 1
  for j = 0; j < 255; j = j + 1 {
    data[idx] = 0x41
    idx = idx + 1
  }
  let c = @qr.rle_compress(data)
  let d = @qr.rle_decompress_optimized(c)
  assert_true(rbp_bytes_eq(d, data))
  // 3 extended (4 bytes) + 2 normal (2 bytes) = 12 + 4 = 16.
  assert_true(c.length() == 16)
}

///|
test "rle boundary: mixed repeats and non-repeats" {
  // AABBBCCCCDEFFFFF - all runs < 255.
  let data = rbp_mk_bytes([
    0x41, 0x41, 0x42, 0x42, 0x42, 0x43, 0x43, 0x43, 0x43, 0x44, 0x45, 0x46, 0x46,
    0x46, 0x46, 0x46,
  ])
  let c = @qr.rle_compress(data)
  let d_opt = @qr.rle_decompress_optimized(c)
  assert_true(rbp_bytes_eq(d_opt, data))
  // All runs < 255, so simple decompress also works.
  let d_simple = @qr.rle_decompress(c)
  assert_true(rbp_bytes_eq(d_simple, data))
}

///|
test "rle boundary: incompressible data expands under rle" {
  // 100 distinct bytes -> each run=1 -> compressed 200 bytes (expands 2x).
  let n = 100
  let data = rbp_make_distinct(n)
  let c = @qr.rle_compress(data)
  assert_true(c.length() == 2 * n)
  assert_true(c.length() > data.length())
  let ratio = @qr.compression_ratio(data, c)
  assert_true(ratio == 2.0)
  // auto_compress must fall back to NoCompress (no expansion).
  let result = @qr.auto_compress(data)
  assert_true(result.compressed_size <= result.original_size)
}

///|
test "rle boundary: all compression levels roundtrip" {
  let datasets = [
    rbp_mk_bytes([0x41]),
    rbp_mk_bytes([0x41, 0x42]),
    FixedArray::make(254, 0x55),
    FixedArray::make(255, 0x55),
    FixedArray::make(1000, 0x55),
    rbp_make_random(200, 99),
  ]
  let levels = [@qr.no_compress(), @qr.fast_compress(), @qr.best_compress()]
  for di = 0; di < datasets.length(); di = di + 1 {
    let data = datasets[di]
    for li = 0; li < levels.length(); li = li + 1 {
      let c = @qr.compress(data, levels[li])
      let d = @qr.decompress(c, levels[li])
      assert_true(rbp_bytes_eq(d, data))
    }
  }
}

///|
test "rle boundary: select strategy small data returns no compress" {
  // len < 10 -> NoCompress, regardless of content.
  for n = 0; n < 10; n = n + 1 {
    let data = FixedArray::make(n, 0x42)
    let s = @qr.select_strategy(data)
    assert_true(s == @qr.strategy_no_compress())
  }
}

///|
test "rle boundary: select strategy high repeat returns fast rle" {
  // 100 identical bytes -> repeats=99, ratio=0.99 > 0.5 -> FastRLE.
  let data = FixedArray::make(100, 0xAA)
  let s = @qr.select_strategy(data)
  assert_true(s == @qr.strategy_fast_rle())
}

///|
test "rle boundary: select strategy medium repeat returns best speed" {
  // len=20, repeats=6, ratio=0.3 -> BestSpeed.
  // 7 A's (6 repeats) + 13 distinct bytes (0 repeats).
  let data = FixedArray::make(20, 0)
  for i = 0; i < 7; i = i + 1 {
    data[i] = 0x41
  }
  data[7] = 0x42
  data[8] = 0x43
  data[9] = 0x44
  data[10] = 0x45
  data[11] = 0x46
  data[12] = 0x47
  data[13] = 0x48
  data[14] = 0x49
  data[15] = 0x4A
  data[16] = 0x4B
  data[17] = 0x4C
  data[18] = 0x4D
  data[19] = 0x4E
  let s = @qr.select_strategy(data)
  assert_true(s == @qr.strategy_best_speed())
}

///|
test "rle boundary: select strategy large low repeat returns balanced" {
  // len=1001, all distinct -> repeats=0, ratio=0, len>1000 -> Balanced.
  let n = 1001
  let data = rbp_make_distinct(n)
  let s = @qr.select_strategy(data)
  assert_true(s == @qr.strategy_balanced())
}

///|
test "rle boundary: select strategy medium low repeat returns no compress" {
  // len=500, all distinct -> repeats=0, ratio=0, len<=1000 -> NoCompress.
  let n = 500
  let data = rbp_make_distinct(n)
  let s = @qr.select_strategy(data)
  assert_true(s == @qr.strategy_no_compress())
}

///|
test "rle boundary: compress with all strategies roundtrip" {
  let datasets = [
    rbp_mk_bytes([0x41, 0x41, 0x42]),
    FixedArray::make(300, 0x55),
    FixedArray::make(1000, 0x55),
    rbp_make_random(100, 42),
  ]
  let strategies = [
    @qr.strategy_no_compress(),
    @qr.strategy_fast_rle(),
    @qr.strategy_best_speed(),
    @qr.strategy_balanced(),
  ]
  for di = 0; di < datasets.length(); di = di + 1 {
    let data = datasets[di]
    for si = 0; si < strategies.length(); si = si + 1 {
      let result = @qr.compress_with_strategy(data, strategies[si])
      let d = @qr.decompress_with_strategy(
        result.compressed_data,
        strategies[si],
      )
      assert_true(rbp_bytes_eq(d, data))
    }
  }
}

///|
test "rle boundary: auto compress fallback on incompressible data" {
  // 2000 distinct bytes -> select_strategy returns Balanced (len>1000).
  // Balanced maps to Fast/RLE which expands -> auto_compress falls back.
  let n = 2000
  let data = rbp_make_distinct(n)
  let result = @qr.auto_compress(data)
  assert_true(result.compressed_size == result.original_size)
  assert_true(result.ratio == 1.0)
}

///|
test "rle boundary: auto compress repetitive data compresses" {
  let data = FixedArray::make(2000, 0xAA)
  let result = @qr.auto_compress(data)
  assert_true(result.compressed_size < result.original_size)
  assert_true(result.ratio < 1.0)
  // Verify roundtrip via the chosen strategy.
  let d = @qr.decompress_with_strategy(result.compressed_data, result.strategy)
  assert_true(rbp_bytes_eq(d, data))
}
