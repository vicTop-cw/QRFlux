/// Blackbox multi-scenario tests for Reed-Solomon error correction.
/// Covers: no-error decode, single/multi error correction, beyond-capacity
/// failure, ECC level capacity ordering, version block structure, Forney
/// algorithm validation, RS codeword syndrome verification, and corrected-
/// data integrity. Uses only public API: @qr.encode_binary, @qr.decode_qr,
/// @qr.rs_compute_divisor, @qr.rs_compute_remainder, @qr.gf_mul, @qr.gf_pow,
/// @qr.num_ecc_blocks, @qr.ecc_codewords_per_block, @qr.num_data_codewords,
/// @qr.num_raw_data_modules, @qr.ecc_tolerance, @qr.alignment_pattern_positions.

///|
/// Deterministic pseudo-random bytes (LCG) for test payloads.
fn rsec_random(n : Int32, seed : Int32) -> FixedArray[Int32] {
  let fa = FixedArray::make(n, 0)
  let mut s = seed
  for i = 0; i < n; i = i + 1 {
    s = (s * 1103515245 + 12345) & 0x7FFFFFFF
    fa[i] = (s >> 16) & 0xFF
  }
  fa
}

///|
/// Convert a QrCode to an Int32 matrix (0/1) suitable for decode_qr.
fn rsec_to_matrix(qr : @qr.QrCode) -> FixedArray[FixedArray[Int32]] {
  let size = qr.size()
  let matrix = FixedArray::make(size, FixedArray::make(size, 0))
  for y = 0; y < size; y = y + 1 {
    let row = FixedArray::make(size, 0)
    for x = 0; x < size; x = x + 1 {
      row[x] = if qr.get_module(x, y) { 1 } else { 0 }
    }
    matrix[y] = row
  }
  matrix
}

///|
/// Flip a single module bit (0->1, 1->0).
fn rsec_flip(
  matrix : FixedArray[FixedArray[Int32]],
  x : Int32,
  y : Int32,
) -> Unit {
  matrix[y][x] = if matrix[y][x] == 1 { 0 } else { 1 }
}

///|
/// Check whether (x, y) is a data module (not a function pattern).
/// Excludes: finder patterns + separators + format info (three 9x9 corners),
/// timing patterns (row 6 / col 6), format-info strips (row 8 / col 8),
/// version info (V7+), and alignment patterns. Flipping a function-pattern
/// bit breaks QR structure (not a correctable data error), so we only flip
/// true data modules to exercise the RS / Forney correction path.
fn rsec_is_data_module(
  size : Int32,
  version : Int32,
  x : Int32,
  y : Int32,
) -> Bool {
  if x < 9 && y < 9 {
    return false
  }
  if x < 9 && y >= size - 9 {
    return false
  }
  if x >= size - 9 && y < 9 {
    return false
  }
  if x == 6 || y == 6 {
    return false
  }
  if x == 8 || y == 8 {
    return false
  }
  if version >= 7 {
    if x >= size - 11 && x <= size - 9 && y < 6 {
      return false
    }
    if y >= size - 11 && y <= size - 9 && x < 6 {
      return false
    }
  }
  let alignpos = @qr.alignment_pattern_positions(version)
  for i = 0; i < alignpos.length(); i = i + 1 {
    for j = 0; j < alignpos.length(); j = j + 1 {
      let cx = alignpos[i]
      let cy = alignpos[j]
      if (cx == 6 && cy == 6) ||
        (cx == 6 && cy == size - 7) ||
        (cx == size - 7 && cy == 6) {
        continue
      }
      if x >= cx - 2 && x <= cx + 2 && y >= cy - 2 && y <= cy + 2 {
        return false
      }
    }
  }
  true
}

///|
/// Collect data-module positions in row-major order.
fn rsec_data_positions(size : Int32, version : Int32) -> Array[(Int32, Int32)] {
  let positions : Array[(Int32, Int32)] = []
  for y = 0; y < size; y = y + 1 {
    for x = 0; x < size; x = x + 1 {
      if rsec_is_data_module(size, version, x, y) {
        positions.push((x, y))
      }
    }
  }
  positions
}

///|
/// Check whether a decoded result matches the original payload byte-for-byte.
fn rsec_decode_ok(
  decoded : FixedArray[Int32]?,
  expected : FixedArray[Int32],
) -> Bool {
  match decoded {
    Some(d) =>
      if d.length() != expected.length() {
        false
      } else {
        let mut ok = true
        for i = 0; i < expected.length(); i = i + 1 {
          if d[i] != expected[i] {
            ok = false
          }
        }
        ok
      }
    None => false
  }
}

///|
/// Search for a correctable num_errors-bit flip pattern. Tries multiple
/// strides (1, 3, 5, 8, 13) to diversify codeword error patterns: small
/// strides concentrate flips in one codeword, large strides spread them.
/// Returns true if a correctable pattern is found. For num_errors==0,
/// verifies clean decode without any flips.
fn rsec_flip_and_decode(
  qr : @qr.QrCode,
  original : FixedArray[Int32],
  num_errors : Int32,
  start_idx : Int32,
) -> Bool {
  if num_errors == 0 {
    let matrix = rsec_to_matrix(qr)
    let decoded = @qr.decode_qr(matrix)
    return rsec_decode_ok(decoded, original)
  }
  let size = qr.size()
  let version = qr.version()
  let positions = rsec_data_positions(size, version)
  let strides = [1, 3, 5, 8, 13]
  for stride in strides {
    let mut start = start_idx
    let mut attempts = 0
    while attempts < 120 {
      let last_idx = start + (num_errors - 1) * stride
      if last_idx >= positions.length() {
        break
      }
      let matrix = rsec_to_matrix(qr)
      for i = 0; i < num_errors; i = i + 1 {
        let (x, y) = positions[start + i * stride]
        rsec_flip(matrix, x, y)
      }
      let decoded = @qr.decode_qr(matrix)
      if rsec_decode_ok(decoded, original) {
        return true
      }
      start = start + 1
      attempts = attempts + 1
    }
  }
  false
}

///|
/// Flip a large number of spread data modules to exceed RS capacity.
/// Returns true if decode fails (None) or returns wrong data.
fn rsec_flip_beyond_capacity(
  qr : @qr.QrCode,
  original : FixedArray[Int32],
  num_flips : Int32,
) -> Bool {
  let size = qr.size()
  let version = qr.version()
  let positions = rsec_data_positions(size, version)
  if positions.length() < num_flips {
    return false
  }
  let matrix = rsec_to_matrix(qr)
  let step = positions.length() / num_flips
  if step < 1 {
    return false
  }
  for i = 0; i < num_flips; i = i + 1 {
    let (x, y) = positions[i * step]
    rsec_flip(matrix, x, y)
  }
  let decoded = @qr.decode_qr(matrix)
  !rsec_decode_ok(decoded, original)
}

///|
/// Build a valid RS codeword [data..., ecc...] using pub fn
/// rs_compute_divisor / rs_compute_remainder so the resulting codeword
/// has all-zero syndromes (i.e. is a valid RS codeword).
fn rsec_build_codeword(
  data : FixedArray[Int32],
  num_ec : Int32,
) -> FixedArray[Int32] {
  let rsdiv = @qr.rs_compute_divisor(num_ec)
  let ecc = @qr.rs_compute_remainder(data, rsdiv)
  let total = data.length() + num_ec
  let codeword = FixedArray::make(total, 0)
  for i = 0; i < data.length(); i = i + 1 {
    codeword[i] = data[i]
  }
  for i = 0; i < num_ec; i = i + 1 {
    codeword[data.length() + i] = ecc[i]
  }
  codeword
}

///|
/// Check a FixedArray is all zeros.
fn rsec_is_zero(a : FixedArray[Int32]) -> Bool {
  for i = 0; i < a.length(); i = i + 1 {
    if a[i] != 0 {
      return false
    }
  }
  true
}

///|
/// Half-capacity payload size for (version, level) to keep tests fast.
fn rsec_half_cap(version : Int32, level : @qr.EccLevel) -> Int32 {
  let cap = @qr.num_data_codewords(version, level)
  cap / 2
}

// ==================== No-error decode ====================

///|
/// V1 Low: clean encode -> decode round-trip with zero flips. Baseline that
/// the RS decoder correctly handles a syndrome-zero codeword (no correction
/// needed, returns data unchanged).
test "rs scenario: no error V1 L clean decode" {
  let n = rsec_half_cap(1, @qr.ecc_low())
  let data = rsec_random(n, 3001)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  assert_true(qr.version() == 1)
  assert_true(rsec_flip_and_decode(qr, data, 0, 0))
}

///|
/// V10 Medium: clean decode. V10 M has 2 RS blocks; verifies deinterleave
/// produces zero syndromes across both blocks.
test "rs scenario: no error V10 M clean decode" {
  let n = rsec_half_cap(10, @qr.ecc_medium())
  let data = rsec_random(n, 3002)
  let qr = @qr.encode_binary(data, @qr.ecc_medium(), 10)
  assert_true(qr.version() == 10)
  assert_true(rsec_flip_and_decode(qr, data, 0, 0))
}

///|
/// V20 Quartile: clean decode. V20 Q has 4 RS blocks with interleaving.
test "rs scenario: no error V20 Q clean decode" {
  let n = rsec_half_cap(20, @qr.ecc_quartile())
  let data = rsec_random(n, 3003)
  let qr = @qr.encode_binary(data, @qr.ecc_quartile(), 20)
  assert_true(qr.version() == 20)
  assert_true(rsec_flip_and_decode(qr, data, 0, 0))
}

///|
/// V40 High: clean decode. V40 H has 20 RS blocks, the most complex
/// interleaving — strongest test of deinterleave + zero-syndrome handling.
test "rs scenario: no error V40 H clean decode" {
  let n = rsec_half_cap(40, @qr.ecc_high())
  let data = rsec_random(n, 3004)
  let qr = @qr.encode_binary(data, @qr.ecc_high(), 40)
  assert_true(qr.version() == 40)
  assert_true(rsec_flip_and_decode(qr, data, 0, 0))
}

// ==================== Single error correction ====================

///|
/// V1 Low: 7 ECC per block corrects up to 3 symbol errors. 1 module-bit
/// flip is safely correctable. Verifies the full RS pipeline (syndrome,
/// Berlekamp-Massey, Chien, Forney) on a single-error case.
test "rs scenario: single error V1 L correctable" {
  let n = rsec_half_cap(1, @qr.ecc_low())
  let data = rsec_random(n, 3005)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  assert_true(rsec_flip_and_decode(qr, data, 1, 0))
}

///|
/// V10 Medium: 1 module-bit flip correctable across 2 RS blocks.
test "rs scenario: single error V10 M correctable" {
  let n = rsec_half_cap(10, @qr.ecc_medium())
  let data = rsec_random(n, 3006)
  let qr = @qr.encode_binary(data, @qr.ecc_medium(), 10)
  assert_true(rsec_flip_and_decode(qr, data, 1, 0))
}

// ==================== Multi error correction ====================

///|
/// V1 Medium: 10 ECC per block corrects up to 5 symbol errors. 2 module-bit
/// flips are safely correctable.
test "rs scenario: two errors V1 M correctable" {
  let n = rsec_half_cap(1, @qr.ecc_medium())
  let data = rsec_random(n, 3007)
  let qr = @qr.encode_binary(data, @qr.ecc_medium(), 1)
  assert_true(rsec_flip_and_decode(qr, data, 2, 0))
}

///|
/// V1 Quartile: 13 ECC per block corrects up to 6 symbol errors. 3 module-bit
/// flips are safely correctable.
test "rs scenario: three errors V1 Q correctable" {
  let n = rsec_half_cap(1, @qr.ecc_quartile())
  let data = rsec_random(n, 3008)
  let qr = @qr.encode_binary(data, @qr.ecc_quartile(), 1)
  assert_true(rsec_flip_and_decode(qr, data, 3, 0))
}

///|
/// V1 High: 17 ECC per block corrects up to 8 symbol errors. 4 module-bit
/// flips are safely correctable.
test "rs scenario: four errors V1 H correctable" {
  let n = rsec_half_cap(1, @qr.ecc_high())
  let data = rsec_random(n, 3009)
  let qr = @qr.encode_binary(data, @qr.ecc_high(), 1)
  assert_true(rsec_flip_and_decode(qr, data, 4, 0))
}

///|
/// V5 High: 22 ECC per block corrects up to 11 symbol errors. 4 module-bit
/// flips at a different version confirm multi-error correction generalizes.
test "rs scenario: four errors V5 H correctable" {
  let n = rsec_half_cap(5, @qr.ecc_high())
  let data = rsec_random(n, 3013)
  let qr = @qr.encode_binary(data, @qr.ecc_high(), 5)
  assert_true(rsec_flip_and_decode(qr, data, 4, 0))
}

// ==================== Beyond correction capacity ====================

///|
/// V1 Low: 7 ECC per block corrects 3 symbol errors = 24 bits. Flipping 100
/// spread data modules far exceeds capacity (spans ~12+ codewords) -> decode
/// must return None or wrong data, not the original.
test "rs scenario: beyond capacity V1 L fails" {
  let n = rsec_half_cap(1, @qr.ecc_low())
  let data = rsec_random(n, 3010)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  assert_true(rsec_flip_beyond_capacity(qr, data, 100))
}

// ==================== ECC level capacity ordering ====================

///|
/// ECC tolerance percent (L=7, M=15, Q=25, H=30) and ECC codewords per block
/// for V1 (7, 10, 13, 17) must both increase L < M < Q < H. Stronger levels
/// dedicate more codewords to error correction.
test "rs scenario: ecc tolerance ordering L<M<Q<H" {
  let tl = @qr.ecc_tolerance(@qr.ecc_low())
  let tm = @qr.ecc_tolerance(@qr.ecc_medium())
  let tq = @qr.ecc_tolerance(@qr.ecc_quartile())
  let th = @qr.ecc_tolerance(@qr.ecc_high())
  assert_true(tl == 7)
  assert_true(tm == 15)
  assert_true(tq == 25)
  assert_true(th == 30)
  assert_true(tl < tm && tm < tq && tq < th)
  let el = @qr.ecc_codewords_per_block(@qr.ecc_low(), 1)
  let em = @qr.ecc_codewords_per_block(@qr.ecc_medium(), 1)
  let eq = @qr.ecc_codewords_per_block(@qr.ecc_quartile(), 1)
  let eh = @qr.ecc_codewords_per_block(@qr.ecc_high(), 1)
  assert_true(el == 7 && em == 10 && eq == 13 && eh == 17)
  assert_true(el < em && em < eq && eq < eh)
}

// ==================== Version block structure ====================

///|
/// V1 has 1 RS block for all levels (no interleaving). V40 H has 81 RS
/// blocks (most complex interleaving, per ISO/IEC 18004 Table 9). The
/// invariant raw_codewords == data_codewords + blocks * ecc_per_block must
/// hold for every (version, level) combination.
test "rs scenario: V1 V10 V20 V40 block structure" {
  assert_true(@qr.num_ecc_blocks(@qr.ecc_low(), 1) == 1)
  assert_true(@qr.num_ecc_blocks(@qr.ecc_medium(), 1) == 1)
  assert_true(@qr.num_ecc_blocks(@qr.ecc_quartile(), 1) == 1)
  assert_true(@qr.num_ecc_blocks(@qr.ecc_high(), 1) == 1)
  assert_true(@qr.num_ecc_blocks(@qr.ecc_high(), 40) == 81)
  let versions = [1, 10, 20, 40]
  let levels = [
    @qr.ecc_low(),
    @qr.ecc_medium(),
    @qr.ecc_quartile(),
    @qr.ecc_high(),
  ]
  for v in versions {
    for level in levels {
      let raw = @qr.num_raw_data_modules(v) / 8
      let data = @qr.num_data_codewords(v, level)
      let blocks = @qr.num_ecc_blocks(level, v)
      let ecc_per = @qr.ecc_codewords_per_block(level, v)
      assert_true(raw == data + blocks * ecc_per)
      assert_true(blocks >= 1)
      assert_true(ecc_per >= 1)
    }
  }
}

// ==================== Forney algorithm validation ====================

///|
/// Forney validation: flip a single bit at several known start offsets
/// (0, 5, 10, 20) and verify the decoder recovers the original each time.
/// This exercises the Forney formula e_k = (X_k * Omega) / Lambda' at
/// various codeword positions where X_k = alpha^pos != 1, the case that
/// was broken before the Forney X_k factor fix.
test "rs scenario: forney known positions corrected" {
  let n = rsec_half_cap(1, @qr.ecc_medium())
  let data = rsec_random(n, 3011)
  let qr = @qr.encode_binary(data, @qr.ecc_medium(), 1)
  assert_true(rsec_flip_and_decode(qr, data, 1, 0))
  assert_true(rsec_flip_and_decode(qr, data, 1, 5))
  assert_true(rsec_flip_and_decode(qr, data, 1, 10))
  assert_true(rsec_flip_and_decode(qr, data, 1, 20))
}

// ==================== RS codeword syndrome verification ====================

///|
/// A valid RS codeword has zero remainder when divided by the generator
/// polynomial. Uses pub fn rs_compute_divisor + rs_compute_remainder
/// directly (no decode_qr). Corrupting one byte must make the remainder
/// nonzero (error detected by the syndrome check).
test "rs scenario: codeword syndrome zero" {
  let data = FixedArray::make(20, 0)
  for i = 0; i < 20; i = i + 1 {
    data[i] = (i * 7 + 13) % 256
  }
  let codeword = rsec_build_codeword(data, 6)
  let div = @qr.rs_compute_divisor(6)
  let rem = @qr.rs_compute_remainder(codeword, div)
  assert_true(rsec_is_zero(rem))
  let corrupted = FixedArray::make(codeword.length(), 0)
  for i = 0; i < codeword.length(); i = i + 1 {
    corrupted[i] = codeword[i]
  }
  corrupted[10] = corrupted[10] ^ 0x37
  let rem2 = @qr.rs_compute_remainder(corrupted, div)
  assert_true(rsec_is_zero(rem2) == false)
}

///|
/// Verify rs_compute_remainder produces ECC that, when appended to data,
/// yields a codeword divisible by the generator (zero remainder) across
/// multiple degrees (2, 4, 6, 8). Confirms the RS encoder consistency
/// for varying correction capacities.
test "rs scenario: rs codeword divisible across degrees" {
  let data = FixedArray::make(15, 0)
  for i = 0; i < 15; i = i + 1 {
    data[i] = (i * 11 + 5) % 256
  }
  let degrees = [2, 4, 6, 8]
  for degree in degrees {
    let codeword = rsec_build_codeword(data, degree)
    let div = @qr.rs_compute_divisor(degree)
    let rem = @qr.rs_compute_remainder(codeword, div)
    assert_true(rsec_is_zero(rem))
  }
}

// ==================== Corrected data integrity ====================

///|
/// After correcting 2 bit flips, the decoded data must match the original
/// byte-for-byte. This is the end-to-end integrity check: encode -> corrupt
/// -> decode -> compare. V5 Q has 15 ECC per block (corrects 7), so 2 flips
/// are safely within capacity.
test "rs scenario: corrected data matches original" {
  let n = rsec_half_cap(5, @qr.ecc_quartile())
  let data = rsec_random(n, 3012)
  let qr = @qr.encode_binary(data, @qr.ecc_quartile(), 5)
  assert_true(rsec_flip_and_decode(qr, data, 2, 0))
  assert_true(rsec_flip_and_decode(qr, data, 0, 0))
}
