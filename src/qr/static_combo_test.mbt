// Static pipeline combination tests.
// Tests compression strategy × version × ECC level combinations
// for encode_static / decode_static roundtrip losslessness.
// Header is 32 bytes (see package.mbt), so packaged_size = 32 + payload.length().

///|
/// Helper: make sequential data (i % 256).
fn combo_make_sequential(n : Int32) -> FixedArray[Int32] {
  let data = FixedArray::make(n, 0)
  for i = 0; i < n; i = i + 1 {
    data[i] = i % 256
  }
  data
}

///|
/// Helper: make pseudo-random data with fixed seed (deterministic).
fn combo_make_random(n : Int32, seed : Int32) -> FixedArray[Int32] {
  let data = FixedArray::make(n, 0)
  let mut s = seed
  for i = 0; i < n; i = i + 1 {
    s = (s * 1103515245 + 12345) & 0x7FFFFFFF
    data[i] = (s >> 16) & 0xFF
  }
  data
}

///|
/// Helper: make all-0xFF data.
fn combo_make_ffs(n : Int32) -> FixedArray[Int32] {
  FixedArray::make(n, 0xFF)
}

///|
/// Helper: make repetitive pattern data (0xAA 0xBB 0xCC 0xDD cycling).
fn combo_make_repetitive(n : Int32) -> FixedArray[Int32] {
  let pattern = [0xAA, 0xBB, 0xCC, 0xDD]
  let data = FixedArray::make(n, 0)
  for i = 0; i < n; i = i + 1 {
    data[i] = pattern[i % 4]
  }
  data
}

///|
/// Helper: check two FixedArray[Int32] equal.
fn combo_arrays_equal(a : FixedArray[Int32], b : FixedArray[Int32]) -> Bool {
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
/// Helper: encode_static -> decode_static roundtrip lossless?
fn combo_roundtrip_ok(
  data : FixedArray[Int32],
  level : @qr.EccLevel,
  min_version : Int32,
) -> Bool {
  match @qr.encode_static(data, level, min_version) {
    None => false
    Some(r) =>
      match @qr.decode_static(r.packaged_bytes()) {
        None => false
        Some(d) => combo_arrays_equal(d, data)
      }
  }
}

///|
/// Helper: roundtrip ok AND qr.version() >= min_version.
fn combo_version_roundtrip_ok(
  data : FixedArray[Int32],
  level : @qr.EccLevel,
  min_version : Int32,
) -> Bool {
  match @qr.encode_static(data, level, min_version) {
    None => false
    Some(r) => {
      if r.qr().version() < min_version {
        return false
      }
      match @qr.decode_static(r.packaged_bytes()) {
        None => false
        Some(d) => combo_arrays_equal(d, data)
      }
    }
  }
}

// ===== Compression × ECC combinations =====

///|
test "static combo: compressible data all ecc" {
  // 200 identical bytes -> RLE compression -> small packaged.
  let data = FixedArray::make(200, 0xAA)
  assert_true(combo_roundtrip_ok(data, @qr.ecc_low(), 1))
  assert_true(combo_roundtrip_ok(data, @qr.ecc_medium(), 1))
  assert_true(combo_roundtrip_ok(data, @qr.ecc_quartile(), 1))
  assert_true(combo_roundtrip_ok(data, @qr.ecc_high(), 1))
}

///|
test "static combo: incompressible data all ecc" {
  // 100 pseudo-random bytes -> NoCompress -> packaged = data + header.
  let data = combo_make_random(100, 7)
  assert_true(combo_roundtrip_ok(data, @qr.ecc_low(), 1))
  assert_true(combo_roundtrip_ok(data, @qr.ecc_medium(), 1))
  assert_true(combo_roundtrip_ok(data, @qr.ecc_quartile(), 1))
  assert_true(combo_roundtrip_ok(data, @qr.ecc_high(), 1))
}

///|
test "static combo: empty data all ecc" {
  let data = FixedArray::make(0, 0)
  assert_true(combo_roundtrip_ok(data, @qr.ecc_low(), 1))
  assert_true(combo_roundtrip_ok(data, @qr.ecc_medium(), 1))
  assert_true(combo_roundtrip_ok(data, @qr.ecc_quartile(), 1))
  assert_true(combo_roundtrip_ok(data, @qr.ecc_high(), 1))
}

///|
test "static combo: single byte all ecc" {
  let data = FixedArray::make(1, 0x42)
  assert_true(combo_roundtrip_ok(data, @qr.ecc_low(), 1))
  assert_true(combo_roundtrip_ok(data, @qr.ecc_medium(), 1))
  assert_true(combo_roundtrip_ok(data, @qr.ecc_quartile(), 1))
  assert_true(combo_roundtrip_ok(data, @qr.ecc_high(), 1))
}

// ===== Version × ECC combinations =====

///|
test "static combo: v1 all ecc" {
  // 5 bytes: V1 capacity too small for 32-byte header + payload,
  // encoder auto-upgrades version. Verify version >= 1 and lossless.
  let data = combo_make_sequential(5)
  assert_true(combo_version_roundtrip_ok(data, @qr.ecc_low(), 1))
  assert_true(combo_version_roundtrip_ok(data, @qr.ecc_medium(), 1))
  assert_true(combo_version_roundtrip_ok(data, @qr.ecc_quartile(), 1))
  assert_true(combo_version_roundtrip_ok(data, @qr.ecc_high(), 1))
}

///|
test "static combo: v10 all ecc" {
  // 50 bytes: fits in V10 at all ECC levels (V10-H=134 > 82 packaged).
  let data = combo_make_sequential(50)
  assert_true(combo_version_roundtrip_ok(data, @qr.ecc_low(), 10))
  assert_true(combo_version_roundtrip_ok(data, @qr.ecc_medium(), 10))
  assert_true(combo_version_roundtrip_ok(data, @qr.ecc_quartile(), 10))
  assert_true(combo_version_roundtrip_ok(data, @qr.ecc_high(), 10))
}

///|
test "static combo: v20 all ecc" {
  // 150 bytes: fits in V20 at all ECC levels (V20-H=318 > 182 packaged).
  let data = combo_make_sequential(150)
  assert_true(combo_version_roundtrip_ok(data, @qr.ecc_low(), 20))
  assert_true(combo_version_roundtrip_ok(data, @qr.ecc_medium(), 20))
  assert_true(combo_version_roundtrip_ok(data, @qr.ecc_quartile(), 20))
  assert_true(combo_version_roundtrip_ok(data, @qr.ecc_high(), 20))
}

///|
test "static combo: v40 all ecc" {
  // 600 bytes: fits in V40 at all ECC levels (V40-H=1273 > 632 packaged).
  let data = combo_make_sequential(600)
  assert_true(combo_version_roundtrip_ok(data, @qr.ecc_low(), 40))
  assert_true(combo_version_roundtrip_ok(data, @qr.ecc_medium(), 40))
  assert_true(combo_version_roundtrip_ok(data, @qr.ecc_quartile(), 40))
  assert_true(combo_version_roundtrip_ok(data, @qr.ecc_high(), 40))
}

// ===== Data type × version combinations =====

///|
test "static combo: all zeros v1 v10 v40" {
  // 100 zeros -> RLE -> 2-byte payload -> small packaged (34 bytes).
  let data = FixedArray::make(100, 0)
  assert_true(combo_version_roundtrip_ok(data, @qr.ecc_medium(), 1))
  assert_true(combo_version_roundtrip_ok(data, @qr.ecc_medium(), 10))
  assert_true(combo_version_roundtrip_ok(data, @qr.ecc_medium(), 40))
}

///|
test "static combo: all ff v1 v10 v40" {
  let data = combo_make_ffs(100)
  assert_true(combo_version_roundtrip_ok(data, @qr.ecc_medium(), 1))
  assert_true(combo_version_roundtrip_ok(data, @qr.ecc_medium(), 10))
  assert_true(combo_version_roundtrip_ok(data, @qr.ecc_medium(), 40))
}

///|
test "static combo: random v1 v10 v40" {
  let data = combo_make_random(100, 13)
  assert_true(combo_version_roundtrip_ok(data, @qr.ecc_medium(), 1))
  assert_true(combo_version_roundtrip_ok(data, @qr.ecc_medium(), 10))
  assert_true(combo_version_roundtrip_ok(data, @qr.ecc_medium(), 40))
}

///|
test "static combo: repetitive v1 v10 v40" {
  let data = combo_make_repetitive(100)
  assert_true(combo_version_roundtrip_ok(data, @qr.ecc_medium(), 1))
  assert_true(combo_version_roundtrip_ok(data, @qr.ecc_medium(), 10))
  assert_true(combo_version_roundtrip_ok(data, @qr.ecc_medium(), 40))
}

///|
test "static combo: mixed data types" {
  // First half zeros, second half pseudo-random.
  let data = FixedArray::make(100, 0)
  let rand_part = combo_make_random(50, 99)
  for i = 0; i < 50; i = i + 1 {
    data[50 + i] = rand_part[i]
  }
  assert_true(combo_roundtrip_ok(data, @qr.ecc_low(), 1))
  assert_true(combo_roundtrip_ok(data, @qr.ecc_medium(), 1))
  assert_true(combo_roundtrip_ok(data, @qr.ecc_quartile(), 1))
  assert_true(combo_roundtrip_ok(data, @qr.ecc_high(), 1))
}

// ===== StaticEncodeResult property tests =====

///|
test "static combo: result original size correct" {
  let sizes = [0, 1, 10, 50, 100, 200]
  for i = 0; i < sizes.length(); i = i + 1 {
    let data = combo_make_sequential(sizes[i])
    let result = @qr.encode_static(data, @qr.ecc_medium(), 1)
    assert_true(result is Some(_))
    let r = result.unwrap()
    assert_true(r.original_size() == data.length())
  }
}

///|
test "static combo: result qr valid" {
  let data = combo_make_sequential(100)
  let levels = [
    @qr.ecc_low(),
    @qr.ecc_medium(),
    @qr.ecc_quartile(),
    @qr.ecc_high(),
  ]
  for i = 0; i < levels.length(); i = i + 1 {
    let result = @qr.encode_static(data, levels[i], 1)
    assert_true(result is Some(_))
    let r = result.unwrap()
    assert_true(r.qr().version() >= 1)
    assert_true(r.qr().version() <= 40)
    assert_true(r.qr().size() >= 21)
  }
}

///|
test "static combo: result packaged bytes non empty" {
  let data = combo_make_sequential(50)
  let result = @qr.encode_static(data, @qr.ecc_medium(), 1)
  assert_true(result is Some(_))
  let r = result.unwrap()
  // Header is 32 bytes, so packaged_bytes always >= 32.
  assert_true(r.packaged_bytes().length() >= 32)
  assert_true(r.packaged_size() == r.packaged_bytes().length())
}

// ===== Compression effect verification =====

///|
test "static combo: compressible data smaller packaged" {
  // 200 identical bytes -> RLE -> 2-byte payload -> packaged 34 < original 200.
  let data = FixedArray::make(200, 0xAA)
  let result = @qr.encode_static(data, @qr.ecc_medium(), 1)
  assert_true(result is Some(_))
  let r = result.unwrap()
  assert_true(r.compressed())
  assert_true(r.packaged_size() < r.original_size())
}

///|
test "static combo: incompressible data no expansion" {
  // 100 random bytes -> NoCompress -> packaged = 32 + 100 = 132.
  // Assert packaged_size <= original_size + 32 (header overhead, no expansion).
  let data = combo_make_random(100, 7)
  let result = @qr.encode_static(data, @qr.ecc_medium(), 1)
  assert_true(result is Some(_))
  let r = result.unwrap()
  assert_true(!r.compressed())
  assert_true(r.packaged_size() <= r.original_size() + 32)
}
