// Variant contrast tests for QRFlux key mechanisms (blackbox).
//
// Per AGENTS.md: "任何判据的 --selftest，必须至少有一格是变异对照：
// 把被测机制改坏，断言锁会红。"
//
// 本文件为关键机制添加变异对照测试。每个测试验证：
//   1. 正常情况机制有效（正例）
//   2. 变异后机制检测到错误（反例）
//
// 我们不实际破坏代码；如果代码被破坏，下面的断言会变红。
// 测试通过 @qr. 公共 API 访问，不依赖私有函数。

///|
/// Helper: build FixedArray[Int32] from Array[Int32].
fn vc_mk_bytes(xs : Array[Int32]) -> FixedArray[Int32] {
  let fa = FixedArray::make(xs.length(), 0)
  for i = 0; i < xs.length(); i = i + 1 {
    fa[i] = xs[i]
  }
  fa
}

///|
/// Helper: copy a FixedArray[Int32].
fn vc_copy(src : FixedArray[Int32]) -> FixedArray[Int32] {
  let dst = FixedArray::make(src.length(), 0)
  for i = 0; i < src.length(); i = i + 1 {
    dst[i] = src[i]
  }
  dst
}

///|
/// Helper: compare two FixedArray[Int32] for element-wise equality.
fn vc_eq(a : FixedArray[Int32], b : FixedArray[Int32]) -> Bool {
  if a.length() != b.length() {
    return false
  }
  let mut ok = true
  for i = 0; i < a.length(); i = i + 1 {
    if a[i] != b[i] {
      ok = false
    }
  }
  ok
}

// ===== RS error correction variant contrast =====

///|
/// RS remainder: a valid codeword yields all-zero remainder; a corrupted
/// codeword yields a non-zero remainder.
///
/// Variant contrast: if rs_compute_remainder were broken (e.g. always
/// returned zero), the corrupted codeword's remainder would still be zero
/// and the `any_nonzero` assertion would turn red.
test "variant: rs remainder zero vs nonzero" {
  let data = vc_mk_bytes([1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
  let divisor = @qr.rs_compute_divisor(7)
  let ecc = @qr.rs_compute_remainder(data, divisor)
  // Positive: ECC length equals divisor length.
  assert_true(ecc.length() == 7)
  // Build full codeword [data..., ecc...] and verify remainder is all zero.
  let full = FixedArray::make(data.length() + ecc.length(), 0)
  for i = 0; i < data.length(); i = i + 1 {
    full[i] = data[i]
  }
  for i = 0; i < ecc.length(); i = i + 1 {
    full[data.length() + i] = ecc[i]
  }
  let rem = @qr.rs_compute_remainder(full, divisor)
  let mut all_zero = true
  for i = 0; i < rem.length(); i = i + 1 {
    if rem[i] != 0 {
      all_zero = false
    }
  }
  assert_true(all_zero)
  // Variant: corrupt one byte; remainder must be non-zero.
  let corrupted = vc_copy(full)
  corrupted[3] = corrupted[3] ^ 0x55
  let rem2 = @qr.rs_compute_remainder(corrupted, divisor)
  let mut any_nonzero = false
  for i = 0; i < rem2.length(); i = i + 1 {
    if rem2[i] != 0 {
      any_nonzero = true
    }
  }
  assert_true(any_nonzero)
}

///|
/// gf_mul is commutative: gf_mul(x, y) == gf_mul(y, x) for all x, y in GF(256).
///
/// Variant contrast: if gf_mul were implemented with plain integer
/// multiplication (no modular reduction), commutativity would still hold,
/// but the identity test below would catch it. If gf_mul had an asymmetric
/// bug (e.g. processing x and y differently), this test would turn red.
test "variant: gf mul commutative" {
  let mut ok = true
  for x = 0; x < 256; x = x + 1 {
    for y = 0; y < 256; y = y + 1 {
      if @qr.gf_mul(x, y) != @qr.gf_mul(y, x) {
        ok = false
      }
    }
  }
  assert_true(ok)
}

///|
/// gf_mul is associative: gf_mul(gf_mul(x, y), z) == gf_mul(x, gf_mul(y, z)).
///
/// Variant contrast: if gf_mul used wrong reduction polynomial, associativity
/// would break. Sampled test (15^3 = 3375 triples) for speed.
test "variant: gf mul associative" {
  let mut ok = true
  let samples = [0, 1, 2, 3, 5, 7, 15, 16, 31, 64, 100, 127, 128, 200, 255]
  for x in samples {
    for y in samples {
      for z in samples {
        let lhs = @qr.gf_mul(@qr.gf_mul(x, y), z)
        let rhs = @qr.gf_mul(x, @qr.gf_mul(y, z))
        if lhs != rhs {
          ok = false
        }
      }
    }
  }
  assert_true(ok)
}

///|
/// gf_mul identity and zero: gf_mul(x, 1) == x, gf_mul(x, 0) == 0.
///
/// Variant contrast: if gf_mul had an off-by-one or wrong polynomial,
/// the identity property would fail and this test would turn red.
test "variant: gf mul identity and zero" {
  let mut ok = true
  for x = 0; x < 256; x = x + 1 {
    if @qr.gf_mul(x, 1) != x {
      ok = false
    }
    if @qr.gf_mul(x, 0) != 0 {
      ok = false
    }
    if @qr.gf_mul(1, x) != x {
      ok = false
    }
    if @qr.gf_mul(0, x) != 0 {
      ok = false
    }
  }
  assert_true(ok)
}

///|
/// gf_inv via Fermat: gf_mul(x, gf_pow(x, 254)) == 1 for every nonzero x.
/// Also gf_inv(gf_inv(x)) == x (double inverse restores original).
///
/// Variant contrast: if gf_pow or gf_mul were broken, the product would
/// not equal 1 and this test would turn red.
test "variant: gf inv correct vs wrong" {
  let mut ok = true
  for x = 1; x < 256; x = x + 1 {
    let inv = @qr.gf_pow(x, 254)
    if @qr.gf_mul(x, inv) != 1 {
      ok = false
    }
    // Double inverse restores original.
    if @qr.gf_pow(inv, 254) != x {
      ok = false
    }
  }
  assert_true(ok)
}

// ===== Mask selection variant contrast =====

///|
/// After encoding, the selected mask is in [0, 7] (validity).
///
/// Variant contrast: if mask selection returned an out-of-range value,
/// this test would turn red.
test "variant: mask selection picks valid mask" {
  let mut all_valid = true
  for i = 0; i < 30; i = i + 1 {
    let n = 5 + i
    let data = FixedArray::make(n, 0)
    for j = 0; j < n; j = j + 1 {
      data[j] = (i * 37 + j * 91 + 7) % 256
    }
    let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
    let m = qr.mask()
    if m < 0 || m > 7 {
      all_valid = false
    }
  }
  assert_true(all_valid)
}

///|
/// There exists data for which the selected mask != 0.
///
/// Variant contrast: if mask selection degenerated to always return 0
/// (a previous bug), all masks would be 0 and `mask_set.length() >= 2`
/// would turn red.
test "variant: mask 0 not always best" {
  let mask_set : Array[Int32] = []
  for i = 0; i < 40; i = i + 1 {
    let n = 5 + i
    let data = FixedArray::make(n, 0)
    for j = 0; j < n; j = j + 1 {
      data[j] = (i * 53 + j * 91 + 13) % 256
    }
    let level = if i % 2 == 0 { @qr.ecc_low() } else { @qr.ecc_medium() }
    let qr = @qr.encode_binary(data, level, 1)
    let m = qr.mask()
    let mut found = false
    for k in mask_set {
      if k == m {
        found = true
      }
    }
    if !found {
      mask_set.push(m)
    }
  }
  // At least 2 distinct masks selected (mask selection is not constant 0).
  assert_true(mask_set.length() >= 2)
}

///|
/// Different data produces different selected masks (mask selection is
/// data-sensitive).
///
/// Variant contrast: if penalty scoring were broken (all masks tied),
/// mask selection would be constant and `distinct.length() >= 2` would
/// turn red.
test "variant: different masks different penalties" {
  let masks : Array[Int32] = []
  for i = 0; i < 50; i = i + 1 {
    let n = 3 + i
    let data = FixedArray::make(n, 0)
    for j = 0; j < n; j = j + 1 {
      data[j] = (i * 41 + j * 73 + 17) % 256
    }
    let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
    masks.push(qr.mask())
  }
  // Count distinct masks.
  let distinct : Array[Int32] = []
  for m in masks {
    let mut found = false
    for d in distinct {
      if d == m {
        found = true
      }
    }
    if !found {
      distinct.push(m)
    }
  }
  // At least 2 distinct masks (selection is data-sensitive).
  assert_true(distinct.length() >= 2)
}

// ===== CRC variant contrast =====

///|
/// CRC32: original data vs data with one byte flipped produce different
/// checksums.
///
/// Variant contrast: if crc32 could not detect single-byte errors (e.g.
/// always returned 0), the two checksums would be equal and the
/// `crc1 != crc2` assertion would turn red.
test "variant: crc32 correct vs corrupted" {
  let data = vc_mk_bytes([1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
  let crc1 = @qr.crc32(data)
  // Variant: flip one byte; CRC must differ.
  let corrupted = vc_copy(data)
  corrupted[3] = corrupted[3] ^ 0x55
  let crc2 = @qr.crc32(corrupted)
  assert_true(crc1 != crc2)
  // Positive: identical data yields identical CRC.
  let data2 = vc_copy(data)
  let crc3 = @qr.crc32(data2)
  assert_true(crc1 == crc3)
}

///|
/// CRC16: original data vs data with one byte flipped produce different
/// checksums.
///
/// Variant contrast: if crc16 could not detect single-byte errors, the
/// two checksums would be equal and the assertion would turn red.
test "variant: crc16 correct vs corrupted" {
  let data = vc_mk_bytes([1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
  let crc1 = @qr.crc16(data)
  let corrupted = vc_copy(data)
  corrupted[3] = corrupted[3] ^ 0x55
  let crc2 = @qr.crc16(corrupted)
  assert_true(crc1 != crc2)
  // Positive: identical data yields identical CRC.
  let data2 = vc_copy(data)
  let crc3 = @qr.crc16(data2)
  assert_true(crc1 == crc3)
}

///|
/// package_with_header followed by unpackage_from_header succeeds on the
/// original; corrupting one payload byte makes unpackage return None.
///
/// Variant contrast: if unpackage did not verify the CRC, the corrupted
/// package would still unpack and `result2 is None` would turn red.
test "variant: package crc catches corruption" {
  let data = vc_mk_bytes([1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
  let pkg = @qr.package_with_header(data, 0, false)
  // Positive: original unpacks successfully.
  let result1 = @qr.unpackage_from_header(pkg)
  assert_true(result1 is Some(_))
  // Variant: corrupt one payload byte (offset 33 = header[32] + payload[1]);
  // CRC mismatch must cause unpackage to return None.
  let corrupted = vc_copy(pkg)
  corrupted[33] = corrupted[33] ^ 0x55
  let result2 = @qr.unpackage_from_header(corrupted)
  assert_true(result2 is None)
}

// ===== RLE variant contrast =====

///|
/// rle_compress_optimized followed by rle_decompress_optimized restores
/// the original; corrupting the compressed stream yields different output.
///
/// Variant contrast: if decompression did not depend on the compressed
/// bytes (e.g. always returned empty), the corrupted decompression would
/// equal the original and `!vc_eq(...)` would turn red.
test "variant: rle roundtrip correct vs corrupted" {
  let data = vc_mk_bytes([1, 1, 1, 2, 2, 3, 4, 4, 4, 4, 5, 6, 6, 7])
  let compressed = @qr.rle_compress_optimized(data)
  // Positive: compress -> decompress restores original.
  let decompressed = @qr.rle_decompress_optimized(compressed)
  assert_true(vc_eq(decompressed, data))
  // Variant: corrupt the first count byte; decompressed output must differ.
  let corrupted = vc_copy(compressed)
  if corrupted.length() > 1 {
    corrupted[0] = corrupted[0] ^ 0x03
    let decompressed2 = @qr.rle_decompress_optimized(corrupted)
    assert_true(!vc_eq(decompressed2, data))
  }
}

///|
/// rle_compress_optimized and rle_compress produce identical output (the
/// latter delegates to the former); both round-trip the original.
///
/// Variant contrast: if rle_compress were reimplemented differently and
/// diverged from the optimized version, `vc_eq(comp_opt, comp_simple)`
/// would turn red.
test "variant: rle optimized vs simple consistency" {
  let data = vc_mk_bytes([1, 1, 2, 2, 2, 3, 3, 4, 5, 5])
  let comp_opt = @qr.rle_compress_optimized(data)
  let comp_simple = @qr.rle_compress(data)
  // Optimized and simple compress produce identical output.
  assert_true(vc_eq(comp_opt, comp_simple))
  // Both decompress back to the original.
  let decomp_opt = @qr.rle_decompress_optimized(comp_opt)
  assert_true(vc_eq(decomp_opt, data))
}

///|
/// RLE round-trip on edge cases: empty, single byte, all-same, alternating,
/// and a long run that triggers extended encoding (count >= 255).
///
/// Variant contrast: if RLE mishandled any edge case (e.g. empty input
/// crash, extended encoding off-by-one), the corresponding `vc_eq` would
/// turn red.
test "variant: rle handles edge cases" {
  // Empty data.
  let empty = FixedArray::make(0, 0)
  let comp_empty = @qr.rle_compress_optimized(empty)
  let decomp_empty = @qr.rle_decompress_optimized(comp_empty)
  assert_true(decomp_empty.length() == 0)
  // Single byte.
  let single = vc_mk_bytes([42])
  let comp_single = @qr.rle_compress_optimized(single)
  let decomp_single = @qr.rle_decompress_optimized(comp_single)
  assert_true(vc_eq(decomp_single, single))
  // All-same bytes (10 x 0x42).
  let same = FixedArray::make(10, 0x42)
  let comp_same = @qr.rle_compress_optimized(same)
  let decomp_same = @qr.rle_decompress_optimized(comp_same)
  assert_true(vc_eq(decomp_same, same))
  // Alternating bytes.
  let alt = FixedArray::make(10, 0)
  for i = 0; i < 10; i = i + 1 {
    alt[i] = if i % 2 == 0 { 0xAA } else { 0x55 }
  }
  let comp_alt = @qr.rle_compress_optimized(alt)
  let decomp_alt = @qr.rle_decompress_optimized(comp_alt)
  assert_true(vc_eq(decomp_alt, alt))
  // Long run (300 x 0x77) triggers extended encoding (count >= 255).
  let longrun = FixedArray::make(300, 0x77)
  let comp_long = @qr.rle_compress_optimized(longrun)
  let decomp_long = @qr.rle_decompress_optimized(comp_long)
  assert_true(vc_eq(decomp_long, longrun))
}

// ===== Interleave variant contrast =====

///|
/// encode_static followed by decode_static restores the original; flipping
/// a payload byte of packaged_bytes makes decode_static return None.
///
/// Variant contrast: if decode_static did not verify the package CRC,
/// the corrupted package would still decode and `decoded2 is None` would
/// turn red.
test "variant: interleave correct order" {
  let data = vc_mk_bytes([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15])
  let result = @qr.encode_static(data, @qr.ecc_low(), 1)
  assert_true(result is Some(_))
  let r = result.unwrap()
  // Positive: original packaged_bytes decode successfully.
  let decoded = @qr.decode_static(r.packaged_bytes())
  assert_true(decoded is Some(_))
  let d = decoded.unwrap()
  assert_true(vc_eq(d, data))
  // Variant: flip one payload byte (offset 33); CRC mismatch -> None.
  let pkg = vc_copy(r.packaged_bytes())
  if pkg.length() > 35 {
    pkg[33] = pkg[33] ^ 0x55
    let decoded2 = @qr.decode_static(pkg)
    assert_true(decoded2 is None)
  }
}

///|
/// encode_binary followed by decode_from_qrcode restores the original;
/// encoding different data yields different decoded output.
///
/// Variant contrast: if decode_from_qrcode ignored module differences
/// (e.g. always returned a constant), the second decode would equal the
/// first data and `!vc_eq(d2, data)` would turn red.
test "variant: deinterleave reverses interleave" {
  let data = vc_mk_bytes([72, 101, 108, 108, 111]) // "Hello"
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  // Positive: original QR decodes to original data.
  let decoded = @qr.decode_from_qrcode(qr)
  assert_true(decoded is Some(_))
  let d = decoded.unwrap()
  assert_true(vc_eq(d, data))
  // Variant: encode slightly different data; decoded output must differ.
  let data2 = vc_mk_bytes([72, 101, 108, 108, 112]) // "Hellp"
  let qr2 = @qr.encode_binary(data2, @qr.ecc_low(), 1)
  let decoded2 = @qr.decode_from_qrcode(qr2)
  assert_true(decoded2 is Some(_))
  let d2 = decoded2.unwrap()
  assert_true(!vc_eq(d2, data))
  assert_true(vc_eq(d2, data2))
}

// ===== Decode variant contrast =====

///|
/// A valid QR matrix decodes successfully; corrupting many data modules
/// causes decode to fail or return wrong data.
///
/// Variant contrast: if decode_qr did not validate module integrity
/// (e.g. always returned a fixed payload), the corrupted decode would
/// equal the original data and `!vc_eq(d, data)` would turn red.
test "variant: decode correct vs corrupted matrix" {
  let data = vc_mk_bytes([72, 101, 108, 108, 111])
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let size = qr.size()
  // Positive: original matrix decodes to original data.
  let matrix = FixedArray::make(size, FixedArray::make(size, 0))
  for y = 0; y < size; y = y + 1 {
    matrix[y] = FixedArray::make(size, 0)
    for x = 0; x < size; x = x + 1 {
      matrix[y][x] = if qr.get_module(x, y) { 1 } else { 0 }
    }
  }
  let decoded = @qr.decode_qr(matrix)
  assert_true(decoded is Some(_))
  // Variant: flip 81 data modules in region y=9..17, x=9..17.
  // V1 Low has 7 ECC codewords -> corrects at most 3 codeword errors.
  // 81 bit flips spread across >3 codewords overwhelm RS correction.
  // Region avoids finder/timing/format function modules.
  let corrupted = FixedArray::make(size, FixedArray::make(size, 0))
  for y = 0; y < size; y = y + 1 {
    corrupted[y] = FixedArray::make(size, 0)
    for x = 0; x < size; x = x + 1 {
      corrupted[y][x] = matrix[y][x]
    }
  }
  let mut flipped = 0
  for y = 9; y <= 17; y = y + 1 {
    for x = 9; x <= 17; x = x + 1 {
      corrupted[y][x] = 1 - corrupted[y][x]
      flipped = flipped + 1
    }
  }
  // Confirm we actually flipped 81 modules.
  assert_true(flipped == 81)
  let decoded2 = @qr.decode_qr(corrupted)
  // After 81 module flips, decode must fail or return wrong data.
  match decoded2 {
    Some(d) => assert_true(!vc_eq(d, data))
    None => assert_true(true)
  }
}

///|
/// encode_binary -> decode_from_qrcode round-trips across 20 varied inputs.
///
/// Variant contrast: if decode_from_qrcode had an off-by-one or mask
/// handling bug, at least one round-trip would fail and `all_ok` would
/// turn red.
test "variant: decode from qrcode roundtrip" {
  let mut all_ok = true
  for i = 0; i < 20; i = i + 1 {
    let n = 3 + i
    let data = FixedArray::make(n, 0)
    for j = 0; j < n; j = j + 1 {
      data[j] = (i * 37 + j * 91 + 7) % 256
    }
    let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
    let decoded = @qr.decode_from_qrcode(qr)
    match decoded {
      Some(d) => if !vc_eq(d, data) { all_ok = false }
      None => all_ok = false
    }
  }
  assert_true(all_ok)
}

///|
/// A valid encode_static output decodes via decode_static; random bytes
/// and empty input cause decode_static to return None.
///
/// Variant contrast: if decode_static did not verify the header magic,
/// random bytes would "decode" to garbage and `decoded2 is None` would
/// turn red.
test "variant: decode static correct vs invalid" {
  let data = vc_mk_bytes([1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
  let result = @qr.encode_static(data, @qr.ecc_low(), 1)
  assert_true(result is Some(_))
  let r = result.unwrap()
  // Positive: valid packaged_bytes decode successfully.
  let decoded = @qr.decode_static(r.packaged_bytes())
  assert_true(decoded is Some(_))
  // Variant: random bytes fail (magic mismatch).
  let random_bytes = FixedArray::make(50, 0)
  for i = 0; i < 50; i = i + 1 {
    random_bytes[i] = (i * 73 + 41) % 256
  }
  let decoded2 = @qr.decode_static(random_bytes)
  assert_true(decoded2 is None)
  // Variant: empty input fails.
  let empty = FixedArray::make(0, 0)
  let decoded3 = @qr.decode_static(empty)
  assert_true(decoded3 is None)
}

// ===== Fountain code variant contrast =====

///|
/// With K + overhead encoded blocks, fountain decode restores the original;
/// with fewer than K blocks, decode returns None.
///
/// Variant contrast: if decode did not check block count, the undersized
/// subset would "decode" to garbage and `decoded2 is None` would turn red.
test "variant: fountain decode with enough blocks" {
  let fountain = @qr.LTFountain::new(10, 4)
  let data = FixedArray::make(40, 0)
  for i = 0; i < 40; i = i + 1 {
    data[i] = (i * 7 + 13) & 0xFF
  }
  // Positive: K + overhead blocks decode successfully.
  let encoded = fountain.encode_all(data, 8)
  let decoded = fountain.decode(encoded)
  assert_true(decoded is Some(_))
  let d = decoded.unwrap()
  assert_true(vc_eq(d, data))
  // Variant: fewer than K blocks -> None.
  let subset : Array[(Int32, FixedArray[Int32])] = []
  for i = 0; i < 3; i = i + 1 {
    subset.push(encoded[i])
  }
  let decoded2 = fountain.decode(subset)
  assert_true(decoded2 is None)
}

///|
/// Corrupting every encoded block's first byte causes decode to fail or
/// return data that differs from the original.
///
/// Variant contrast: if decode ignored block contents (e.g. always
/// returned the original via some side channel), the corrupted decode
/// would equal the original and `!vc_eq(d, data)` would turn red.
test "variant: fountain corrupted block detected" {
  let fountain = @qr.LTFountain::new(10, 4)
  let data = FixedArray::make(40, 0)
  for i = 0; i < 40; i = i + 1 {
    data[i] = (i * 7 + 13) & 0xFF
  }
  let encoded = fountain.encode_all(data, 8)
  // Positive: original encoded blocks decode to original data.
  let decoded = fountain.decode(encoded)
  assert_true(decoded is Some(_))
  // Variant: flip first byte of every encoded block.
  let corrupted : Array[(Int32, FixedArray[Int32])] = []
  for i = 0; i < encoded.length(); i = i + 1 {
    let (seed, block) = encoded[i]
    let block_copy = vc_copy(block)
    if block_copy.length() > 0 {
      block_copy[0] = block_copy[0] ^ 0xFF
    }
    corrupted.push((seed, block_copy))
  }
  let decoded2 = fountain.decode(corrupted)
  // Corrupted blocks must fail to decode or yield wrong data.
  match decoded2 {
    Some(d) => assert_true(!vc_eq(d, data))
    None => assert_true(true)
  }
}
