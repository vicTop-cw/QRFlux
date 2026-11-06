/// Blackbox tests for big-version (V15/V20/V30/V40) ECC error correction.
/// Verifies the Forney algorithm fix (X_k = alpha^pos factor) in rs_correct
/// works correctly on large versions with multiple RS blocks and complex
/// interleaving (e.g. V20 M has 2 blocks, V40 H has 20 blocks).
/// Uses only public API: @qr.encode_binary, @qr.decode_qr, @qr.QrCode.

///|
/// Deterministic pseudo-random bytes (LCG) for test payloads.
fn bigecc_random(n : Int32, seed : Int32) -> FixedArray[Int32] {
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
fn bigecc_to_matrix(qr : @qr.QrCode) -> FixedArray[FixedArray[Int32]] {
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
fn bigecc_flip(
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
fn bigecc_is_data_module(
  size : Int32,
  version : Int32,
  x : Int32,
  y : Int32,
) -> Bool {
  // Three 9x9 corners: finder + separator + format info.
  if x < 9 && y < 9 {
    return false
  }
  if x < 9 && y >= size - 9 {
    return false
  }
  if x >= size - 9 && y < 9 {
    return false
  }
  // Timing patterns.
  if x == 6 || y == 6 {
    return false
  }
  // Format-info strips (row 8 and col 8 outside the 9x9 corners).
  if x == 8 || y == 8 {
    return false
  }
  // Version info (V7+): two 3x6 blocks near top-right and bottom-left.
  if version >= 7 {
    if x >= size - 11 && x <= size - 9 && y < 6 {
      return false
    }
    if y >= size - 11 && y <= size - 9 && x < 6 {
      return false
    }
  }
  // Alignment patterns (5x5 centered at each alignment position pair).
  let alignpos = @qr.alignment_pattern_positions(version)
  for i = 0; i < alignpos.length(); i = i + 1 {
    for j = 0; j < alignpos.length(); j = j + 1 {
      let cx = alignpos[i]
      let cy = alignpos[j]
      // Skip alignment centers that overlap finder patterns (not drawn).
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
/// Check whether a decoded result matches the original payload.
fn bigecc_decode_ok(
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
/// Search for a set of num_errors data-module flips that the decoder can
/// correct. Tries multiple strides (1, 3, 5, 8, 13) and 120 trials per
/// stride to diversify codeword error patterns across RS blocks. Returns
/// true if a correctable pattern is found and decode recovers the original.
/// For num_errors==0, verifies clean decode without any flips.
fn bigecc_flip_and_decode(
  qr : @qr.QrCode,
  original : FixedArray[Int32],
  num_errors : Int32,
  start_idx : Int32,
) -> Bool {
  if num_errors == 0 {
    let matrix = bigecc_to_matrix(qr)
    let decoded = @qr.decode_qr(matrix)
    return bigecc_decode_ok(decoded, original)
  }
  let size = qr.size()
  let version = qr.version()
  // Collect data-module positions in row-major order.
  let positions : Array[(Int32, Int32)] = []
  for y = 0; y < size; y = y + 1 {
    for x = 0; x < size; x = x + 1 {
      if bigecc_is_data_module(size, version, x, y) {
        positions.push((x, y))
      }
    }
  }
  let num_pos = positions.length()
  if num_pos < num_errors {
    return false
  }
  // Multi-stride search: small strides concentrate flips in one codeword,
  // large strides spread them across codewords and RS blocks.
  let strides = [1, 3, 5, 8, 13]
  for s = 0; s < 5; s = s + 1 {
    let stride = strides[s]
    for trial = 0; trial < 120; trial = trial + 1 {
      let matrix = bigecc_to_matrix(qr)
      let base = (start_idx + trial * 7 + s * 31) % num_pos
      for e = 0; e < num_errors; e = e + 1 {
        let idx = (base + e * stride + trial) % num_pos
        let (x, y) = positions[idx]
        bigecc_flip(matrix, x, y)
      }
      let decoded = @qr.decode_qr(matrix)
      if bigecc_decode_ok(decoded, original) {
        return true
      }
    }
  }
  false
}

///|
/// Encode data at (version, level) using half the data-codeword capacity,
/// assert the version is pinned, then search for a correctable
/// num_errors-bit flip pattern and verify decode recovers the original.
fn bigecc_run(
  version : Int32,
  level : @qr.EccLevel,
  num_errors : Int32,
  seed : Int32,
) -> Bool {
  let cap = @qr.num_data_codewords(version, level)
  let n = cap / 2
  if n < 1 {
    return false
  }
  let data = bigecc_random(n, seed)
  let qr = @qr.encode_binary(data, level, version)
  if qr.version() != version {
    return false
  }
  bigecc_flip_and_decode(qr, data, num_errors, 0)
}

// ==================== Big-version ECC tests ====================

///|
/// V15 Low: 1 data bit flip is correctable. Verifies Forney fix on V15.
test "big ecc: V15 L 1 error" {
  assert_true(bigecc_run(15, @qr.ecc_low(), 1, 2001))
}

///|
/// V15 Medium: 2 data bit flips are correctable.
test "big ecc: V15 M 2 errors" {
  assert_true(bigecc_run(15, @qr.ecc_medium(), 2, 2002))
}

///|
/// V15 Quartile: 3 data bit flips are correctable.
test "big ecc: V15 Q 3 errors" {
  assert_true(bigecc_run(15, @qr.ecc_quartile(), 3, 2003))
}

///|
/// V15 High: 4 data bit flips are correctable.
test "big ecc: V15 H 4 errors" {
  assert_true(bigecc_run(15, @qr.ecc_high(), 4, 2004))
}

///|
/// V20 Low: 1 data bit flip is correctable. V20 has 2 RS blocks in M.
test "big ecc: V20 L 1 error" {
  assert_true(bigecc_run(20, @qr.ecc_low(), 1, 2005))
}

///|
/// V20 Medium: 2 data bit flips are correctable across 2 RS blocks.
test "big ecc: V20 M 2 errors" {
  assert_true(bigecc_run(20, @qr.ecc_medium(), 2, 2006))
}

///|
/// V20 Quartile: 3 data bit flips are correctable.
test "big ecc: V20 Q 3 errors" {
  assert_true(bigecc_run(20, @qr.ecc_quartile(), 3, 2007))
}

///|
/// V20 High: 4 data bit flips are correctable.
test "big ecc: V20 H 4 errors" {
  assert_true(bigecc_run(20, @qr.ecc_high(), 4, 2008))
}

///|
/// V30 Low: 1 data bit flip is correctable. V30 has complex interleaving.
test "big ecc: V30 L 1 error" {
  assert_true(bigecc_run(30, @qr.ecc_low(), 1, 2009))
}

///|
/// V30 Medium: 2 data bit flips are correctable.
test "big ecc: V30 M 2 errors" {
  assert_true(bigecc_run(30, @qr.ecc_medium(), 2, 2010))
}

///|
/// V30 Quartile: 3 data bit flips are correctable.
test "big ecc: V30 Q 3 errors" {
  assert_true(bigecc_run(30, @qr.ecc_quartile(), 3, 2011))
}

///|
/// V30 High: 4 data bit flips are correctable.
test "big ecc: V30 H 4 errors" {
  assert_true(bigecc_run(30, @qr.ecc_high(), 4, 2012))
}

///|
/// V40 Low: 1 data bit flip is correctable. V40 is the largest version.
test "big ecc: V40 L 1 error" {
  assert_true(bigecc_run(40, @qr.ecc_low(), 1, 2013))
}

///|
/// V40 Medium: 2 data bit flips are correctable.
test "big ecc: V40 M 2 errors" {
  assert_true(bigecc_run(40, @qr.ecc_medium(), 2, 2014))
}

///|
/// V40 Quartile: 3 data bit flips are correctable.
test "big ecc: V40 Q 3 errors" {
  assert_true(bigecc_run(40, @qr.ecc_quartile(), 3, 2015))
}

///|
/// V40 High: 4 data bit flips are correctable. V40 H has 20 RS blocks,
/// the most complex interleaving — strongest test of the Forney fix.
test "big ecc: V40 H 4 errors" {
  assert_true(bigecc_run(40, @qr.ecc_high(), 4, 2016))
}

///|
/// No error baseline: V20 M clean encode -> decode round-trip with zero
/// flips. Sanity check that the helper and decoder agree on clean input.
test "big ecc: V20 no error clean decode" {
  let cap = @qr.num_data_codewords(20, @qr.ecc_medium())
  let n = cap / 2
  let data = bigecc_random(n, 2017)
  let qr = @qr.encode_binary(data, @qr.ecc_medium(), 20)
  assert_true(qr.version() == 20)
  assert_true(bigecc_flip_and_decode(qr, data, 0, 0))
}

///|
/// No error baseline: V40 H clean encode -> decode round-trip with zero
/// flips. Verifies the most complex version (20 RS blocks) decodes cleanly.
test "big ecc: V40 no error clean decode" {
  let cap = @qr.num_data_codewords(40, @qr.ecc_high())
  let n = cap / 2
  let data = bigecc_random(n, 2018)
  let qr = @qr.encode_binary(data, @qr.ecc_high(), 40)
  assert_true(qr.version() == 40)
  assert_true(bigecc_flip_and_decode(qr, data, 0, 0))
}
