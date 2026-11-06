// Static pipeline end-to-end combination tests.
// Exercises the full encode_static -> decode_static roundtrip across
// compression strategies × QR versions × ECC levels × data types.
// Header is 32 bytes (see package.mbt): magic(4) + version(1) + flags(1)
// + algo(1) + data_length(4) + original_size(4) + checksum(4) + reserved(13).

///|
/// Helper: pseudo-random data with fixed seed (deterministic LCG).
fn e2e_make_random(n : Int32, seed : Int32) -> FixedArray[Int32] {
  let data = FixedArray::make(n, 0)
  let mut s = seed
  for i = 0; i < n; i = i + 1 {
    s = (s * 1103515245 + 12345) & 0x7FFFFFFF
    data[i] = (s >> 16) & 0xFF
  }
  data
}

///|
/// Helper: sequential data (i % 256).
fn e2e_make_sequential(n : Int32) -> FixedArray[Int32] {
  let data = FixedArray::make(n, 0)
  for i = 0; i < n; i = i + 1 {
    data[i] = i % 256
  }
  data
}

///|
/// Helper: repetitive pattern (0xAA 0xBB 0xCC 0xDD cycling).
fn e2e_make_repetitive(n : Int32) -> FixedArray[Int32] {
  let pattern = [0xAA, 0xBB, 0xCC, 0xDD]
  let data = FixedArray::make(n, 0)
  for i = 0; i < n; i = i + 1 {
    data[i] = pattern[i % 4]
  }
  data
}

///|
/// Helper: text-like data (printable ASCII 0x20..0x7E cycling, 95 chars).
fn e2e_make_text(n : Int32) -> FixedArray[Int32] {
  let data = FixedArray::make(n, 0)
  for i = 0; i < n; i = i + 1 {
    data[i] = 0x20 + i % 95
  }
  data
}

///|
/// Helper: binary full-spectrum data (all 256 byte values cycling).
fn e2e_make_binary(n : Int32) -> FixedArray[Int32] {
  let data = FixedArray::make(n, 0)
  for i = 0; i < n; i = i + 1 {
    data[i] = i % 256
  }
  data
}

///|
/// Helper: check two FixedArray[Int32] equal.
fn e2e_arrays_equal(a : FixedArray[Int32], b : FixedArray[Int32]) -> Bool {
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
fn e2e_roundtrip_ok(
  data : FixedArray[Int32],
  level : @qr.EccLevel,
  min_version : Int32,
) -> Bool {
  match @qr.encode_static(data, level, min_version) {
    None => false
    Some(r) =>
      match @qr.decode_static(r.packaged_bytes()) {
        None => false
        Some(d) => e2e_arrays_equal(d, data)
      }
  }
}

///|
/// Helper: roundtrip ok AND qr.version() >= min_version.
fn e2e_version_roundtrip_ok(
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
        Some(d) => e2e_arrays_equal(d, data)
      }
    }
  }
}

///|
/// Helper: predict algo_id mirroring encode_static's internal logic.
/// encode_static: strategy != NoCompress && compressed < original -> ALGO_RLE
/// else -> ALGO_NONE. auto_compress already falls back to NoCompress when
/// compression expands, so we replicate that decision here.
fn e2e_predict_algo_id(data : FixedArray[Int32]) -> Int32 {
  let comp = @qr.auto_compress(data)
  let strategy = comp.strategy
  let use_compression = strategy != @qr.strategy_no_compress() &&
    comp.compressed_size < comp.original_size
  if use_compression {
    @qr.ALGO_RLE
  } else {
    @qr.ALGO_NONE
  }
}

///|
/// Helper: all four ECC levels.
fn e2e_all_levels() -> Array[@qr.EccLevel] {
  [@qr.ecc_low(), @qr.ecc_medium(), @qr.ecc_quartile(), @qr.ecc_high()]
}

// ===== Data type × ECC roundtrip =====

///|
test "e2e: empty data roundtrip all ecc" {
  let data = FixedArray::make(0, 0)
  let levels = e2e_all_levels()
  for i = 0; i < levels.length(); i = i + 1 {
    assert_true(e2e_roundtrip_ok(data, levels[i], 1))
  }
}

///|
test "e2e: single byte roundtrip all ecc" {
  let data = FixedArray::make(1, 0x42)
  let levels = e2e_all_levels()
  for i = 0; i < levels.length(); i = i + 1 {
    assert_true(e2e_roundtrip_ok(data, levels[i], 1))
  }
}

///|
test "e2e: all zeros compressible roundtrip all ecc" {
  let data = FixedArray::make(200, 0)
  let levels = e2e_all_levels()
  for i = 0; i < levels.length(); i = i + 1 {
    assert_true(e2e_roundtrip_ok(data, levels[i], 1))
  }
}

///|
test "e2e: all FF compressible roundtrip all ecc" {
  let data = FixedArray::make(200, 0xFF)
  let levels = e2e_all_levels()
  for i = 0; i < levels.length(); i = i + 1 {
    assert_true(e2e_roundtrip_ok(data, levels[i], 1))
  }
}

///|
test "e2e: random incompressible roundtrip all ecc" {
  let data = e2e_make_random(100, 7)
  let levels = e2e_all_levels()
  for i = 0; i < levels.length(); i = i + 1 {
    assert_true(e2e_roundtrip_ok(data, levels[i], 1))
  }
}

///|
test "e2e: repetitive pattern roundtrip all ecc" {
  let data = e2e_make_repetitive(200)
  let levels = e2e_all_levels()
  for i = 0; i < levels.length(); i = i + 1 {
    assert_true(e2e_roundtrip_ok(data, levels[i], 1))
  }
}

///|
test "e2e: text-like data roundtrip all ecc" {
  let data = e2e_make_text(150)
  let levels = e2e_all_levels()
  for i = 0; i < levels.length(); i = i + 1 {
    assert_true(e2e_roundtrip_ok(data, levels[i], 1))
  }
}

///|
test "e2e: binary full spectrum roundtrip all ecc" {
  let data = e2e_make_binary(256)
  let levels = e2e_all_levels()
  for i = 0; i < levels.length(); i = i + 1 {
    assert_true(e2e_roundtrip_ok(data, levels[i], 1))
  }
}

// ===== Version × ECC roundtrip =====

///|
test "e2e: min version v1 v10 v20 v40 roundtrip" {
  // v1: 5 bytes (encoder auto-upgrades version, verify >= 1 and lossless)
  let d1 = e2e_make_sequential(5)
  assert_true(e2e_version_roundtrip_ok(d1, @qr.ecc_medium(), 1))
  // v10: 50 bytes
  let d10 = e2e_make_sequential(50)
  assert_true(e2e_version_roundtrip_ok(d10, @qr.ecc_medium(), 10))
  // v20: 150 bytes
  let d20 = e2e_make_sequential(150)
  assert_true(e2e_version_roundtrip_ok(d20, @qr.ecc_medium(), 20))
  // v40: 600 bytes
  let d40 = e2e_make_sequential(600)
  assert_true(e2e_version_roundtrip_ok(d40, @qr.ecc_medium(), 40))
}

// ===== algo_id consistency =====

///|
test "e2e: algo id consistent with auto compress prediction" {
  // Multiple data shapes: verify encode_static algo_id matches prediction
  // from select_strategy + auto_compress, across all ECC levels.
  let shapes = [
    e2e_make_sequential(5), // NoCompress (too small)
    e2e_make_sequential(50), // NoCompress (low repeat)
    FixedArray::make(200, 0xAA), // FastRLE effective
    FixedArray::make(200, 0), // FastRLE effective
    e2e_make_random(100, 7), // incompressible -> fallback NoCompress
    e2e_make_repetitive(200), // FastRLE effective
    e2e_make_text(150), // text-like
    e2e_make_binary(256), // full spectrum
  ]
  let levels = e2e_all_levels()
  for s = 0; s < shapes.length(); s = s + 1 {
    let predicted = e2e_predict_algo_id(shapes[s])
    for l = 0; l < levels.length(); l = l + 1 {
      match @qr.encode_static(shapes[s], levels[l], 1) {
        None => () // too large to fit, skip
        Some(r) => assert_true(r.algo_id() == predicted)
      }
    }
  }
}

// ===== Compression effect =====

///|
test "e2e: compressible data packaged smaller than original" {
  // 500 identical bytes -> RLE -> 4-byte payload -> packaged 36 < 500.
  let data = FixedArray::make(500, 0x55)
  let result = @qr.encode_static(data, @qr.ecc_medium(), 1)
  assert_true(result is Some(_))
  let r = result.unwrap()
  assert_true(r.compressed())
  assert_true(r.algo_id() == @qr.ALGO_RLE)
  assert_true(r.packaged_size() < r.original_size())
}

///|
test "e2e: incompressible data no expansion beyond header" {
  // 100 random bytes -> NoCompress -> packaged = 32 + 100 = 132.
  // Assert packaged_size <= original_size + 32 (header overhead, no expansion).
  let data = e2e_make_random(100, 7)
  let result = @qr.encode_static(data, @qr.ecc_medium(), 1)
  assert_true(result is Some(_))
  let r = result.unwrap()
  assert_true(!r.compressed())
  assert_true(r.algo_id() == @qr.ALGO_NONE)
  assert_true(r.packaged_size() <= r.original_size() + 32)
}

// ===== Large data roundtrip =====

///|
test "e2e: large 1000 bytes roundtrip all ecc" {
  // 1000 random bytes -> NoCompress -> packaged 1032 <= V40-H (1273).
  let data = e2e_make_random(1000, 42)
  let levels = e2e_all_levels()
  for i = 0; i < levels.length(); i = i + 1 {
    assert_true(e2e_roundtrip_ok(data, levels[i], 1))
  }
}

///|
test "e2e: large 5000 bytes compressible roundtrip" {
  // 5000 identical bytes -> RLE -> 4-byte payload -> packaged 36 bytes.
  // Fits in small QR version at all ECC levels.
  let data = FixedArray::make(5000, 0x77)
  let levels = e2e_all_levels()
  for i = 0; i < levels.length(); i = i + 1 {
    assert_true(e2e_roundtrip_ok(data, levels[i], 1))
  }
}

///|
test "e2e: large 5000 bytes incompressible returns none all ecc" {
  // 5000 random bytes -> RLE expands -> fallback NoCompress -> packaged 5032.
  // Exceeds V40-L (2953) capacity, so encode_static returns None at all levels.
  let data = e2e_make_random(5000, 99)
  let levels = e2e_all_levels()
  for i = 0; i < levels.length(); i = i + 1 {
    let result = @qr.encode_static(data, levels[i], 1)
    assert_true(result is None)
  }
}

// ===== Cross ECC level capacity =====

///|
test "e2e: cross ecc level version monotonic" {
  // 800 sequential bytes -> NoCompress (repeat_ratio ~ 0) -> packaged 832.
  // Higher ECC level has less capacity -> needs >= version.
  // Assert version(ecc_high) >= version(ecc_quartile) >= version(ecc_medium)
  // >= version(ecc_low).
  let data = e2e_make_sequential(800)
  let r_low = @qr.encode_static(data, @qr.ecc_low(), 1).unwrap()
  let r_med = @qr.encode_static(data, @qr.ecc_medium(), 1).unwrap()
  let r_q = @qr.encode_static(data, @qr.ecc_quartile(), 1).unwrap()
  let r_high = @qr.encode_static(data, @qr.ecc_high(), 1).unwrap()
  assert_true(r_high.qr().version() >= r_q.qr().version())
  assert_true(r_q.qr().version() >= r_med.qr().version())
  assert_true(r_med.qr().version() >= r_low.qr().version())
}

// ===== Header format correctness =====

///|
test "e2e: packaged header format correct" {
  // Compressed case: 200 identical bytes -> RLE.
  let comp_data = FixedArray::make(200, 0xAA)
  let comp_r = @qr.encode_static(comp_data, @qr.ecc_medium(), 1).unwrap()
  let cpkg = comp_r.packaged_bytes()
  // Magic bytes (ASCII "QRFX")
  assert_true(cpkg[0] == 0x51)
  assert_true(cpkg[1] == 0x52)
  assert_true(cpkg[2] == 0x46)
  assert_true(cpkg[3] == 0x58)
  // Version
  assert_true(cpkg[4] == 1)
  // Flags: compressed -> FLAG_COMPRESSED (0x01)
  assert_true(cpkg[5] == 0x01)
  // Algo id at byte offset 6
  assert_true(cpkg[6] == comp_r.algo_id())
  assert_true(cpkg[6] == @qr.ALGO_RLE)
  // Data length (big-endian) = packaged_size - 32
  let comp_dlen = (cpkg[7] << 24) | (cpkg[8] << 16) | (cpkg[9] << 8) | cpkg[10]
  assert_true(comp_dlen == comp_r.packaged_size() - 32)
  // Original size field (big-endian): package_with_header stores payload
  // length here (compressed payload length, not the pre-compression 200).
  let comp_osize = (cpkg[11] << 24) |
    (cpkg[12] << 16) |
    (cpkg[13] << 8) |
    cpkg[14]
  assert_true(comp_osize == comp_r.packaged_size() - 32)
  // Reserved bytes (19..31) all zero
  for i = 19; i < 32; i = i + 1 {
    assert_true(cpkg[i] == 0)
  }

  // Uncompressed case: 100 random bytes -> NoCompress.
  let raw_data = e2e_make_random(100, 7)
  let raw_r = @qr.encode_static(raw_data, @qr.ecc_medium(), 1).unwrap()
  let rpkg = raw_r.packaged_bytes()
  // Magic
  assert_true(rpkg[0] == 0x51)
  assert_true(rpkg[1] == 0x52)
  assert_true(rpkg[2] == 0x46)
  assert_true(rpkg[3] == 0x58)
  // Version
  assert_true(rpkg[4] == 1)
  // Flags: not compressed -> 0x00
  assert_true(rpkg[5] == 0x00)
  // Algo id
  assert_true(rpkg[6] == @qr.ALGO_NONE)
  // Data length = 100 (payload == original since no compression)
  let raw_dlen = (rpkg[7] << 24) | (rpkg[8] << 16) | (rpkg[9] << 8) | rpkg[10]
  assert_true(raw_dlen == 100)
  // Original size = 100
  let raw_osize = (rpkg[11] << 24) |
    (rpkg[12] << 16) |
    (rpkg[13] << 8) |
    rpkg[14]
  assert_true(raw_osize == 100)
  // Reserved bytes all zero
  for i = 19; i < 32; i = i + 1 {
    assert_true(rpkg[i] == 0)
  }
}

// ===== Decode robustness =====

///|
test "e2e: decode rejects corrupted header" {
  // Baseline: valid packaged bytes decode successfully.
  let data = e2e_make_sequential(50)
  let r = @qr.encode_static(data, @qr.ecc_medium(), 1).unwrap()
  let pkg = r.packaged_bytes()
  assert_true(@qr.decode_static(pkg) is Some(_))

  // 1. Too short (< 32 bytes) -> None
  let short = FixedArray::make(10, 0)
  assert_true(@qr.decode_static(short) is None)

  // 2. Corrupted magic -> None
  let bad_magic = FixedArray::make(pkg.length(), 0)
  for i = 0; i < pkg.length(); i = i + 1 {
    bad_magic[i] = pkg[i]
  }
  bad_magic[0] = 0x00
  assert_true(@qr.decode_static(bad_magic) is None)

  // 3. Corrupted payload (checksum mismatch) -> None
  let bad_payload = FixedArray::make(pkg.length(), 0)
  for i = 0; i < pkg.length(); i = i + 1 {
    bad_payload[i] = pkg[i]
  }
  // Flip last payload byte (index >= 32, in payload region)
  let last = bad_payload.length() - 1
  bad_payload[last] = (bad_payload[last] + 1) % 256
  assert_true(@qr.decode_static(bad_payload) is None)

  // 4. Unknown algorithm id (algo=2 deflate reserved) -> None
  let bad_algo = FixedArray::make(pkg.length(), 0)
  for i = 0; i < pkg.length(); i = i + 1 {
    bad_algo[i] = pkg[i]
  }
  bad_algo[6] = 2
  assert_true(@qr.decode_static(bad_algo) is None)
}
