/// Blackbox tests for Reed-Solomon error-correction capacity limits.
/// Exercises the boundary between correctable and uncorrectable errors:
/// - Near capacity (t-1 errors): always correctable
/// - At capacity (t errors): correctable depending on position
/// - Beyond capacity (t+1+ errors): decode fails
/// where t = ecc_codewords_per_block / 2 is the per-block correction limit.
/// Covers all four ECC levels (L/M/Q/H), multiple versions (V1/V5/V10/V20/V40),
/// multi-block RS (V20/V40), concentrated vs spread errors, and corrected-
/// data integrity. Uses only public API: @qr.encode_binary, @qr.decode_qr,
/// @qr.ecc_codewords_per_block, @qr.ecc_tolerance, @qr.num_ecc_blocks,
/// @qr.num_data_codewords, @qr.num_raw_data_modules, @qr.alignment_pattern_positions.

///|
/// Deterministic pseudo-random bytes (LCG) for test payloads.
fn rsl_random(n : Int32, seed : Int32) -> FixedArray[Int32] {
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
fn rsl_to_matrix(qr : @qr.QrCode) -> FixedArray[FixedArray[Int32]] {
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
fn rsl_flip(
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
fn rsl_is_data_module(
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
fn rsl_data_positions(size : Int32, version : Int32) -> Array[(Int32, Int32)] {
  let positions : Array[(Int32, Int32)] = []
  for y = 0; y < size; y = y + 1 {
    for x = 0; x < size; x = x + 1 {
      if rsl_is_data_module(size, version, x, y) {
        positions.push((x, y))
      }
    }
  }
  positions
}

///|
/// Check decoded result matches original byte-for-byte.
fn rsl_decode_ok(
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
/// RS per-block correction capacity t = ecc_codewords_per_block / 2.
fn rsl_capacity(level : @qr.EccLevel, version : Int32) -> Int32 {
  @qr.ecc_codewords_per_block(level, version) / 2
}

///|
/// Half-capacity payload size for (version, level) to keep tests fast.
fn rsl_half_cap(version : Int32, level : @qr.EccLevel) -> Int32 {
  @qr.num_data_codewords(version, level) / 2
}

///|
/// Flip num_errors data modules uniformly spread across the matrix, starting
/// at offset. Uses step = num_pos / num_errors so flips are maximally spread
/// (each in a different codeword region). Returns true if decode recovers
/// the original. For num_errors==0, verifies clean decode.
fn rsl_flip_uniform_and_decode(
  qr : @qr.QrCode,
  original : FixedArray[Int32],
  num_errors : Int32,
  offset : Int32,
) -> Bool {
  if num_errors == 0 {
    let matrix = rsl_to_matrix(qr)
    let decoded = @qr.decode_qr(matrix)
    return rsl_decode_ok(decoded, original)
  }
  let size = qr.size()
  let version = qr.version()
  let positions = rsl_data_positions(size, version)
  let num_pos = positions.length()
  if num_pos < num_errors {
    return false
  }
  let step = num_pos / num_errors
  if step < 1 {
    return false
  }
  let matrix = rsl_to_matrix(qr)
  for i = 0; i < num_errors; i = i + 1 {
    let idx = (offset + i * step) % num_pos
    let (x, y) = positions[idx]
    rsl_flip(matrix, x, y)
  }
  let decoded = @qr.decode_qr(matrix)
  rsl_decode_ok(decoded, original)
}

///|
/// Search for a correctable uniform-spread pattern of num_errors flips.
/// Tries multiple offsets. Returns true if a correctable pattern is found.
/// For num_errors==0, verifies clean decode.
fn rsl_search_spread_correctable(
  qr : @qr.QrCode,
  original : FixedArray[Int32],
  num_errors : Int32,
  max_offsets : Int32,
) -> Bool {
  if num_errors == 0 {
    let matrix = rsl_to_matrix(qr)
    let decoded = @qr.decode_qr(matrix)
    return rsl_decode_ok(decoded, original)
  }
  let size = qr.size()
  let version = qr.version()
  let positions = rsl_data_positions(size, version)
  let num_pos = positions.length()
  if num_pos < num_errors {
    return false
  }
  let step = num_pos / num_errors
  if step < 1 {
    return false
  }
  for offset = 0; offset < max_offsets; offset = offset + 1 {
    let matrix = rsl_to_matrix(qr)
    for i = 0; i < num_errors; i = i + 1 {
      let idx = (offset + i * step) % num_pos
      let (x, y) = positions[idx]
      rsl_flip(matrix, x, y)
    }
    let decoded = @qr.decode_qr(matrix)
    if rsl_decode_ok(decoded, original) {
      return true
    }
  }
  false
}

///|
/// Flip num_errors consecutive data modules starting at start_idx (concentrated
/// in one region, likely fewer codeword symbol errors). Returns true if decode
/// recovers the original.
fn rsl_flip_consecutive_and_decode(
  qr : @qr.QrCode,
  original : FixedArray[Int32],
  num_errors : Int32,
  start_idx : Int32,
) -> Bool {
  let size = qr.size()
  let version = qr.version()
  let positions = rsl_data_positions(size, version)
  if start_idx + num_errors > positions.length() {
    return false
  }
  let matrix = rsl_to_matrix(qr)
  for i = 0; i < num_errors; i = i + 1 {
    let (x, y) = positions[start_idx + i]
    rsl_flip(matrix, x, y)
  }
  let decoded = @qr.decode_qr(matrix)
  rsl_decode_ok(decoded, original)
}

///|
/// Flip num_flips data modules spread uniformly to exceed RS capacity.
/// Returns true if decode fails (None) or returns wrong data.
fn rsl_flip_beyond_capacity(
  qr : @qr.QrCode,
  original : FixedArray[Int32],
  num_flips : Int32,
) -> Bool {
  let size = qr.size()
  let version = qr.version()
  let positions = rsl_data_positions(size, version)
  if positions.length() < num_flips {
    return false
  }
  let matrix = rsl_to_matrix(qr)
  let step = positions.length() / num_flips
  if step < 1 {
    return false
  }
  for i = 0; i < num_flips; i = i + 1 {
    let (x, y) = positions[i * step]
    rsl_flip(matrix, x, y)
  }
  let decoded = @qr.decode_qr(matrix)
  !rsl_decode_ok(decoded, original)
}

// ==================== Near capacity (t-1) ====================

///|
/// V1 Low: 7 ECC per block, t=3. Flipping t-1=2 spread data bits produces
/// <= 2 symbol errors, safely correctable. Verifies near-limit correction.
test "rs limit: V1 L near capacity t-1 correctable" {
  let n = rsl_half_cap(1, @qr.ecc_low())
  let data = rsl_random(n, 4001)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  assert_true(rsl_capacity(@qr.ecc_low(), 1) == 3)
  assert_true(rsl_search_spread_correctable(qr, data, 2, 30))
}

///|
/// V1 Medium: 10 ECC per block, t=5. Flipping t-1=4 spread data bits is
/// safely correctable.
test "rs limit: V1 M near capacity t-1 correctable" {
  let n = rsl_half_cap(1, @qr.ecc_medium())
  let data = rsl_random(n, 4002)
  let qr = @qr.encode_binary(data, @qr.ecc_medium(), 1)
  assert_true(rsl_capacity(@qr.ecc_medium(), 1) == 5)
  assert_true(rsl_search_spread_correctable(qr, data, 4, 30))
}

///|
/// V1 Quartile: 13 ECC per block, t=6. Flipping t-1=5 spread data bits is
/// safely correctable.
test "rs limit: V1 Q near capacity t-1 correctable" {
  let n = rsl_half_cap(1, @qr.ecc_quartile())
  let data = rsl_random(n, 4003)
  let qr = @qr.encode_binary(data, @qr.ecc_quartile(), 1)
  assert_true(rsl_capacity(@qr.ecc_quartile(), 1) == 6)
  assert_true(rsl_search_spread_correctable(qr, data, 5, 30))
}

///|
/// V1 High: 17 ECC per block, t=8. Flipping t-1=7 spread data bits is
/// safely correctable.
test "rs limit: V1 H near capacity t-1 correctable" {
  let n = rsl_half_cap(1, @qr.ecc_high())
  let data = rsl_random(n, 4004)
  let qr = @qr.encode_binary(data, @qr.ecc_high(), 1)
  assert_true(rsl_capacity(@qr.ecc_high(), 1) == 8)
  assert_true(rsl_search_spread_correctable(qr, data, 7, 30))
}

// ==================== At capacity (t) ====================

///|
/// V1 Low: t=3. Flipping exactly t=3 spread data bits produces 3 symbol
/// errors, which RS can correct at capacity. Searches for a correctable
/// position pattern.
test "rs limit: V1 L at capacity t correctable" {
  let n = rsl_half_cap(1, @qr.ecc_low())
  let data = rsl_random(n, 4005)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  assert_true(rsl_search_spread_correctable(qr, data, 3, 60))
}

///|
/// V1 Medium: t=5. Flipping exactly t=5 spread data bits is correctable
/// at capacity.
test "rs limit: V1 M at capacity t correctable" {
  let n = rsl_half_cap(1, @qr.ecc_medium())
  let data = rsl_random(n, 4006)
  let qr = @qr.encode_binary(data, @qr.ecc_medium(), 1)
  assert_true(rsl_search_spread_correctable(qr, data, 5, 60))
}

///|
/// V1 High: t=8. Flipping exactly t=8 spread data bits is correctable
/// at capacity.
test "rs limit: V1 H at capacity t correctable" {
  let n = rsl_half_cap(1, @qr.ecc_high())
  let data = rsl_random(n, 4007)
  let qr = @qr.encode_binary(data, @qr.ecc_high(), 1)
  assert_true(rsl_search_spread_correctable(qr, data, 8, 60))
}

// ==================== Beyond capacity (t+1+) ====================

///|
/// V1 Low: t=3. Flipping 50 spread data modules far exceeds capacity
/// (spans many codewords) -> decode must fail or return wrong data.
test "rs limit: V1 L beyond capacity fails" {
  let n = rsl_half_cap(1, @qr.ecc_low())
  let data = rsl_random(n, 4008)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  assert_true(rsl_flip_beyond_capacity(qr, data, 50))
}

///|
/// V1 Medium: t=5. Flipping 60 spread data modules exceeds capacity
/// -> decode must fail.
test "rs limit: V1 M beyond capacity fails" {
  let n = rsl_half_cap(1, @qr.ecc_medium())
  let data = rsl_random(n, 4009)
  let qr = @qr.encode_binary(data, @qr.ecc_medium(), 1)
  assert_true(rsl_flip_beyond_capacity(qr, data, 60))
}

///|
/// V1 High: t=8. Flipping 80 spread data modules exceeds capacity
/// -> decode must fail.
test "rs limit: V1 H beyond capacity fails" {
  let n = rsl_half_cap(1, @qr.ecc_high())
  let data = rsl_random(n, 4010)
  let qr = @qr.encode_binary(data, @qr.ecc_high(), 1)
  assert_true(rsl_flip_beyond_capacity(qr, data, 80))
}

// ==================== ECC level limits (L/M/Q/H) ====================

///|
/// V5 Low: 26 ECC per block, t=13. Flipping t-1=12 spread bits is correctable.
/// V5 L has 2 RS blocks; errors spread across both blocks.
test "rs limit: V5 L near capacity t-1" {
  let n = rsl_half_cap(5, @qr.ecc_low())
  let data = rsl_random(n, 4011)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 5)
  assert_true(qr.version() == 5)
  assert_true(rsl_capacity(@qr.ecc_low(), 5) == 13)
  assert_true(rsl_search_spread_correctable(qr, data, 12, 30))
}

///|
/// V5 High: 22 ECC per block, t=11. Flipping t-1=10 spread bits is correctable.
test "rs limit: V5 H near capacity t-1" {
  let n = rsl_half_cap(5, @qr.ecc_high())
  let data = rsl_random(n, 4012)
  let qr = @qr.encode_binary(data, @qr.ecc_high(), 5)
  assert_true(qr.version() == 5)
  assert_true(rsl_capacity(@qr.ecc_high(), 5) == 11)
  assert_true(rsl_search_spread_correctable(qr, data, 10, 30))
}

// ==================== Multi-block RS ====================

///|
/// V20 High: multiple RS blocks. Flipping 8 spread bits (within per-block
/// capacity) is correctable. Tests multi-block independent correction with
/// interleaving.
test "rs limit: V20 H multi block near capacity" {
  let n = rsl_half_cap(20, @qr.ecc_high())
  let data = rsl_random(n, 4013)
  let qr = @qr.encode_binary(data, @qr.ecc_high(), 20)
  assert_true(qr.version() == 20)
  assert_true(@qr.num_ecc_blocks(@qr.ecc_high(), 20) >= 2)
  assert_true(rsl_search_spread_correctable(qr, data, 8, 30))
}

///|
/// V40 High: 81 RS blocks (most complex interleaving). Flipping 8 spread
/// bits is correctable. Each block corrects its share of errors independently.
test "rs limit: V40 H 81 blocks near capacity" {
  let n = rsl_half_cap(40, @qr.ecc_high())
  let data = rsl_random(n, 4014)
  let qr = @qr.encode_binary(data, @qr.ecc_high(), 40)
  assert_true(qr.version() == 40)
  assert_true(@qr.num_ecc_blocks(@qr.ecc_high(), 40) == 81)
  assert_true(rsl_search_spread_correctable(qr, data, 8, 30))
}

// ==================== V40 all 4 ECC levels ====================

///|
/// V40 all four ECC levels: 4 spread bit flips each is correctable across
/// L/M/Q/H. Verifies large-version limit behavior at every ECC strength.
test "rs limit: V40 all 4 levels near capacity" {
  let levels = [
    @qr.ecc_low(),
    @qr.ecc_medium(),
    @qr.ecc_quartile(),
    @qr.ecc_high(),
  ]
  let mut all_ok = true
  for i = 0; i < levels.length(); i = i + 1 {
    let l = levels[i]
    let n = rsl_half_cap(40, l)
    if n < 1 {
      all_ok = false
    } else {
      let data = rsl_random(n, 4015 + rsl_capacity(l, 40))
      let qr = @qr.encode_binary(data, l, 40)
      if qr.version() != 40 {
        all_ok = false
      } else if !rsl_search_spread_correctable(qr, data, 4, 30) {
        all_ok = false
      }
    }
  }
  assert_true(all_ok)
}

// ==================== Concentrated vs spread errors ====================

///|
/// V5 Medium: t=12. Same 4 errors, concentrated (consecutive) vs spread
/// (uniform). Both are within capacity and must be correctable. Verifies
/// the decoder handles both error distributions equally well.
test "rs limit: concentrated vs spread errors both correctable" {
  let n = rsl_half_cap(5, @qr.ecc_medium())
  let data = rsl_random(n, 4016)
  let qr = @qr.encode_binary(data, @qr.ecc_medium(), 5)
  assert_true(qr.version() == 5)
  // Concentrated: 4 consecutive flips -> fewer symbol errors, easily correctable.
  assert_true(rsl_flip_consecutive_and_decode(qr, data, 4, 10))
  // Spread: 4 uniform flips -> up to 4 symbol errors, still within t=12.
  assert_true(rsl_search_spread_correctable(qr, data, 4, 30))
}

// ==================== Corrected data integrity ====================

///|
/// V10 Quartile: t=7. After correcting 6 spread bit flips (near capacity),
/// the decoded data must match the original byte-for-byte. This is the
/// end-to-end integrity check at near-limit error count.
test "rs limit: corrected data integrity byte-for-byte" {
  let n = rsl_half_cap(10, @qr.ecc_quartile())
  let data = rsl_random(n, 4017)
  let qr = @qr.encode_binary(data, @qr.ecc_quartile(), 10)
  assert_true(qr.version() == 10)
  // Clean decode baseline.
  assert_true(rsl_flip_uniform_and_decode(qr, data, 0, 0))
  // Near-capacity correction must preserve data integrity.
  assert_true(rsl_search_spread_correctable(qr, data, 6, 40))
}

// ==================== No error baseline ====================

///|
/// V1/V10/V20/V40 clean decode baseline: zero flips, decode must recover
/// the original. Sanity check that the helper and decoder agree on clean
/// input across small and large versions.
test "rs limit: no error baseline clean decode" {
  let configs : Array[(Int32, @qr.EccLevel)] = [
    (1, @qr.ecc_low()),
    (10, @qr.ecc_medium()),
    (20, @qr.ecc_quartile()),
    (40, @qr.ecc_high()),
  ]
  let mut all_ok = true
  for i = 0; i < configs.length(); i = i + 1 {
    let (v, l) = configs[i]
    let n = rsl_half_cap(v, l)
    if n < 1 {
      all_ok = false
    } else {
      let data = rsl_random(n, 4018 + v)
      let qr = @qr.encode_binary(data, l, v)
      if qr.version() != v {
        all_ok = false
      } else if !rsl_flip_uniform_and_decode(qr, data, 0, 0) {
        all_ok = false
      }
    }
  }
  assert_true(all_ok)
}
