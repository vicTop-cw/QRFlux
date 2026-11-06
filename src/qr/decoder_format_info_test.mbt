// Decoder format-info and version-info boundary tests.
// Black-box tests for decode_qr focusing on the format-info (BCH(15,5))
// and version-info (BCH(18,6)) read paths: clean reads, single-copy
// corruption (fallback to the other copy), both-copy corruption (decode
// fails), and BCH error correction of 1-3 bit flips. Covers V1 (no
// version info), V7+ (with version info), and a cross-version sweep
// V1/V7/V10/V20/V40. A successful round trip indirectly proves the
// decoder read the ECC level and mask pattern correctly: a wrong level
// would deinterleave with the wrong block layout and a wrong mask would
// scramble every data module.

///|
/// Deterministic pseudo-random bytes (LCG).
fn fi_random(n : Int32, seed : Int32) -> FixedArray[Int32] {
  let fa = FixedArray::make(n, 0)
  let mut s = seed
  for i = 0; i < n; i = i + 1 {
    s = (s * 1103515245 + 12345) & 0x7FFFFFFF
    fa[i] = (s >> 16) & 0xFF
  }
  fa
}

///|
/// Build n bytes of ascending printable data (0x30, 0x31, ...).
fn fi_asc(n : Int32) -> FixedArray[Int32] {
  let fa = FixedArray::make(n, 0)
  for i = 0; i < n; i = i + 1 {
    fa[i] = 0x30 + i % 95
  }
  fa
}

///|
/// Convert a QrCode's Bool modules to an Int32 matrix for decode_qr.
fn fi_qr_to_matrix(qr : @qr.QrCode) -> FixedArray[FixedArray[Int32]] {
  let size = qr.size()
  let matrix = FixedArray::make(size, FixedArray::make(0, 0))
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
/// Flip a single module between 0 and 1 in place.
fn fi_flip(
  matrix : FixedArray[FixedArray[Int32]],
  x : Int32,
  y : Int32,
) -> Unit {
  matrix[y][x] = if matrix[y][x] == 1 { 0 } else { 1 }
}

///|
/// Flip every coordinate in the list.
fn fi_flip_all(
  matrix : FixedArray[FixedArray[Int32]],
  coords : Array[(Int32, Int32)],
) -> Unit {
  for c in coords {
    let (x, y) = c
    fi_flip(matrix, x, y)
  }
}

///|
/// Flip the first n coordinates in the list.
fn fi_flip_first_n(
  matrix : FixedArray[FixedArray[Int32]],
  coords : Array[(Int32, Int32)],
  n : Int32,
) -> Unit {
  let limit = if n < coords.length() { n } else { coords.length() }
  for i = 0; i < limit; i = i + 1 {
    let (x, y) = coords[i]
    fi_flip(matrix, x, y)
  }
}

///|
/// Element-wise equality check for two FixedArray[Int32].
fn fi_bytes_eq(a : FixedArray[Int32], b : FixedArray[Int32]) -> Bool {
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
/// Assert decode_qr(matrix) recovers the original payload.
fn fi_assert_ok(
  matrix : FixedArray[FixedArray[Int32]],
  data : FixedArray[Int32],
  label : String,
) -> Unit {
  match @qr.decode_qr(matrix) {
    Some(d) =>
      if !fi_bytes_eq(d, data) {
        abort("fi \{label}: decoded data mismatch")
      }
    None => abort("fi \{label}: decode returned None")
  }
}

///|
/// Assert decode_qr(matrix) returns None.
fn fi_assert_none(
  matrix : FixedArray[FixedArray[Int32]],
  label : String,
) -> Unit {
  match @qr.decode_qr(matrix) {
    Some(_) => abort("fi \{label}: expected None but got Some")
    None => ()
  }
}

///|
/// Format-info first copy coordinates (15 bits around top-left finder).
/// Order matches the decoder's read_format_info bit indexing.
fn fi_format_copy1() -> Array[(Int32, Int32)] {
  let result : Array[(Int32, Int32)] = []
  // bit 0..5: (x=8, y=0..5)
  for i = 0; i < 6; i = i + 1 {
    result.push((8, i))
  }
  // bit 6: (8, 7)
  result.push((8, 7))
  // bit 7: (8, 8)
  result.push((8, 8))
  // bit 8: (7, 8)
  result.push((7, 8))
  // bit 9..14: (x=14-i, y=8) -> (5,8),(4,8),...,(0,8)
  for i = 9; i < 15; i = i + 1 {
    result.push((14 - i, 8))
  }
  result
}

///|
/// Format-info second copy coordinates (15 bits near bottom-right).
fn fi_format_copy2(size : Int32) -> Array[(Int32, Int32)] {
  let result : Array[(Int32, Int32)] = []
  // bit 0..7: (x=size-1-i, y=8)
  for i = 0; i < 8; i = i + 1 {
    result.push((size - 1 - i, 8))
  }
  // bit 8..14: (x=8, y=size-15+i)
  for i = 8; i < 15; i = i + 1 {
    result.push((8, size - 15 + i))
  }
  result
}

///|
/// Version-info first copy coordinates (18 bits, bottom-left). V7+ only.
fn fi_version_copy1(size : Int32) -> Array[(Int32, Int32)] {
  let result : Array[(Int32, Int32)] = []
  for i = 0; i < 18; i = i + 1 {
    let x = size - 11 + i % 3
    let y = i / 3
    result.push((x, y))
  }
  result
}

///|
/// Version-info second copy coordinates (18 bits, top-right). V7+ only.
fn fi_version_copy2(size : Int32) -> Array[(Int32, Int32)] {
  let result : Array[(Int32, Int32)] = []
  for i = 0; i < 18; i = i + 1 {
    let x = i / 3
    let y = size - 11 + i % 3
    result.push((x, y))
  }
  result
}

///|
/// Rank of ECC level by correction strength: L=0, M=1, Q=2, H=3.
fn fi_rank(l : @qr.EccLevel) -> Int32 {
  if l == @qr.ecc_low() {
    0
  } else if l == @qr.ecc_medium() {
    1
  } else if l == @qr.ecc_quartile() {
    2
  } else {
    3
  }
}

///|
/// Pick a data length n so encode_binary(data(n), target, v) lands on
/// exactly (v, target) after auto-boost. Returns -1 if no such n exists.
fn fi_pick_n(v : Int32, target : @qr.EccLevel) -> Int32 {
  let cap = @qr.num_data_codewords(v, target)
  let ccbits = @qr.char_count_bits(@qr.mode_byte(), v)
  let n_max = (cap * 8 - 4 - ccbits) / 8
  let mut n_min : Int32 = 0
  if target == @qr.ecc_high() {
    ()
  } else {
    let all = [
      @qr.ecc_low(),
      @qr.ecc_medium(),
      @qr.ecc_quartile(),
      @qr.ecc_high(),
    ]
    for l in all {
      if fi_rank(l) > fi_rank(target) {
        let hcap = @qr.num_data_codewords(v, l)
        let bound = (hcap * 8 - 4 - ccbits) / 8 + 1
        if bound > n_min {
          n_min = bound
        }
      }
    }
  }
  if n_min > n_max || n_max < 1 {
    return -1
  }
  n_max
}

// ==================== Format info: clean read ====================

///|
test "format info: V1 L clean decode reads level and mask" {
  // Clean round trip. Success implies format info (level=L, mask) read
  // correctly: a wrong mask would scramble all data modules.
  let n = fi_pick_n(1, @qr.ecc_low())
  if n < 0 {
    abort("fi V1 L: no pinning size")
  }
  let data = fi_random(n, 3001)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  assert_true(qr.version() == 1)
  assert_true(qr.level() == @qr.ecc_low())
  fi_assert_ok(fi_qr_to_matrix(qr), data, "V1 L clean")
}

///|
test "format info: V3 M clean decode reads level and mask" {
  let n = fi_pick_n(3, @qr.ecc_medium())
  if n < 0 {
    abort("fi V3 M: no pinning size")
  }
  let data = fi_random(n, 3003)
  let qr = @qr.encode_binary(data, @qr.ecc_medium(), 3)
  assert_true(qr.version() == 3)
  assert_true(qr.level() == @qr.ecc_medium())
  fi_assert_ok(fi_qr_to_matrix(qr), data, "V3 M clean")
}

///|
test "format info: V5 H clean decode reads level and mask" {
  let n = fi_pick_n(5, @qr.ecc_high())
  if n < 0 {
    abort("fi V5 H: no pinning size")
  }
  let data = fi_random(n, 3005)
  let qr = @qr.encode_binary(data, @qr.ecc_high(), 5)
  assert_true(qr.version() == 5)
  assert_true(qr.level() == @qr.ecc_high())
  fi_assert_ok(fi_qr_to_matrix(qr), data, "V5 H clean")
}

// ==================== Format info: single-copy fallback ====================

///|
test "format info: copy2 fully flipped, copy1 intact -> decode succeeds" {
  // The decoder tries copy1 first; copy1 is intact so it decodes
  // correctly and copy2 is never consulted. Flipping all of copy2 has
  // no effect on the outcome -> round trip succeeds.
  let n = fi_pick_n(2, @qr.ecc_low())
  if n < 0 {
    abort("fi copy2 flip: no pinning size")
  }
  let data = fi_random(n, 3011)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 2)
  let matrix = fi_qr_to_matrix(qr)
  fi_flip_all(matrix, fi_format_copy2(qr.size()))
  fi_assert_ok(matrix, data, "copy2 flipped")
}

///|
test "format info: copy1 fully flipped, copy2 intact -> no crash" {
  // Flipping all 15 bits of copy1 may put it beyond BCH correction (None)
  // or cause a mis-correction to a different valid format word (BCH(15,5)
  // min distance 7: a 15-bit flip can land within distance 3 of another
  // codeword). If copy1 returns None the decoder falls back to copy2 and
  // succeeds; if copy1 mis-corrects, decode uses a wrong (level, mask)
  // and returns None. Either way the decoder must not crash.
  let n = fi_pick_n(2, @qr.ecc_low())
  if n < 0 {
    abort("fi copy1 flip: no pinning size")
  }
  let data = fi_random(n, 3010)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 2)
  let matrix = fi_qr_to_matrix(qr)
  fi_flip_all(matrix, fi_format_copy1())
  let result = @qr.decode_qr(matrix)
  let _ = result
}

// ==================== Format info: both copies destroyed ====================

///|
test "format info: both copies fully flipped -> decode returns None" {
  // Both copies beyond BCH correction -> read_format_info returns None ->
  // decode_qr returns None.
  let n = fi_pick_n(2, @qr.ecc_low())
  if n < 0 {
    abort("fi both flip: no pinning size")
  }
  let data = fi_random(n, 3012)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 2)
  let matrix = fi_qr_to_matrix(qr)
  fi_flip_all(matrix, fi_format_copy1())
  fi_flip_all(matrix, fi_format_copy2(qr.size()))
  fi_assert_none(matrix, "both copies flipped")
}

// ==================== Format info: BCH error correction ====================

///|
test "format info: 3 bits flipped in copy1 -> BCH corrects -> decode succeeds" {
  // BCH(15,5) has min distance 7, corrects up to 3 bit errors. Flipping 3
  // bits in copy1 still yields the original (level, mask), so decode
  // recovers the payload.
  let n = fi_pick_n(2, @qr.ecc_medium())
  if n < 0 {
    abort("fi 3-bit copy1: no pinning size")
  }
  let data = fi_random(n, 3013)
  let qr = @qr.encode_binary(data, @qr.ecc_medium(), 2)
  let matrix = fi_qr_to_matrix(qr)
  fi_flip_first_n(matrix, fi_format_copy1(), 3)
  fi_assert_ok(matrix, data, "3-bit copy1 corrected")
}

///|
test "format info: 2 bits flipped in both copies -> BCH corrects -> decode succeeds" {
  // Each copy has 2 bit errors (within BCH capacity), so copy1 decodes
  // correctly and the round trip succeeds.
  let n = fi_pick_n(3, @qr.ecc_low())
  if n < 0 {
    abort("fi 2-bit both: no pinning size")
  }
  let data = fi_random(n, 3014)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 3)
  let matrix = fi_qr_to_matrix(qr)
  fi_flip_first_n(matrix, fi_format_copy1(), 2)
  fi_flip_first_n(matrix, fi_format_copy2(qr.size()), 2)
  fi_assert_ok(matrix, data, "2-bit both corrected")
}

///|
test "format info: 1 bit flipped in copy2 -> BCH corrects -> decode succeeds" {
  let n = fi_pick_n(1, @qr.ecc_low())
  if n < 0 {
    abort("fi 1-bit copy2: no pinning size")
  }
  let data = fi_random(n, 3015)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let matrix = fi_qr_to_matrix(qr)
  fi_flip_first_n(matrix, fi_format_copy2(qr.size()), 1)
  fi_assert_ok(matrix, data, "1-bit copy2 corrected")
}

///|
test "format info: 3 bits in each copy -> both BCH correct -> decode succeeds" {
  // Each copy has 3 bit errors, within BCH(15,5) capacity. copy1 decodes
  // correctly (best_dist=3 <= 3) and the round trip succeeds. This
  // deterministically exercises BCH correction on both redundant copies.
  let n = fi_pick_n(2, @qr.ecc_medium())
  if n < 0 {
    abort("fi 3-bit each: no pinning size")
  }
  let data = fi_random(n, 3016)
  let qr = @qr.encode_binary(data, @qr.ecc_medium(), 2)
  let matrix = fi_qr_to_matrix(qr)
  fi_flip_first_n(matrix, fi_format_copy1(), 3)
  fi_flip_first_n(matrix, fi_format_copy2(qr.size()), 3)
  fi_assert_ok(matrix, data, "3-bit each copy corrected")
}

// ==================== Version info: clean read (V7+) ====================

///|
test "version info: V7 M clean decode reads version" {
  // V7+ carries version info; a clean round trip implies read_version_info
  // returned 7 (matching the size-derived version).
  let n = fi_pick_n(7, @qr.ecc_medium())
  if n < 0 {
    abort("vi V7 M: no pinning size")
  }
  let data = fi_random(n, 3107)
  let qr = @qr.encode_binary(data, @qr.ecc_medium(), 7)
  assert_true(qr.version() == 7)
  fi_assert_ok(fi_qr_to_matrix(qr), data, "V7 M clean")
}

// ==================== Version info: single-copy fallback ====================

///|
test "version info: copy2 fully flipped, copy1 intact -> decode succeeds" {
  // Decoder tries copy1 first; copy1 intact -> version read correctly,
  // copy2 never consulted. Round trip succeeds.
  let n = fi_pick_n(7, @qr.ecc_low())
  if n < 0 {
    abort("vi copy2 flip: no pinning size")
  }
  let data = fi_random(n, 3111)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 7)
  let matrix = fi_qr_to_matrix(qr)
  fi_flip_all(matrix, fi_version_copy2(qr.size()))
  fi_assert_ok(matrix, data, "version copy2 flipped")
}

///|
test "version info: copy1 fully flipped, copy2 intact -> no crash" {
  // Same rationale as the format-info copy1 test: a full 18-bit flip may
  // be beyond BCH correction (None -> fallback to copy2 -> success) or may
  // mis-correct to a different version. If it mis-corrects to a value in
  // 1..40 but != 7, decode returns None; if to a value outside 1..40,
  // try_decode_version returns None and the decoder falls back to copy2.
  // The decoder must not crash in any case.
  let n = fi_pick_n(7, @qr.ecc_low())
  if n < 0 {
    abort("vi copy1 flip: no pinning size")
  }
  let data = fi_random(n, 3110)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 7)
  let matrix = fi_qr_to_matrix(qr)
  fi_flip_all(matrix, fi_version_copy1(qr.size()))
  let result = @qr.decode_qr(matrix)
  let _ = result
}

// ==================== Version info: both copies destroyed ====================

///|
test "version info: both copies fully flipped -> decode returns None" {
  // Both version-info copies beyond BCH correction -> read_version_info
  // returns None -> decode_qr returns None (format info is still valid,
  // but the version check fails).
  let n = fi_pick_n(7, @qr.ecc_low())
  if n < 0 {
    abort("vi both flip: no pinning size")
  }
  let data = fi_random(n, 3112)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 7)
  let matrix = fi_qr_to_matrix(qr)
  fi_flip_all(matrix, fi_version_copy1(qr.size()))
  fi_flip_all(matrix, fi_version_copy2(qr.size()))
  fi_assert_none(matrix, "both version copies flipped")
}

// ==================== Version info: BCH error correction ====================

///|
test "version info: 3 bits flipped in copy1 -> BCH corrects -> decode succeeds" {
  // BCH(18,6) corrects up to 3 bit errors; copy1 recovers version 7.
  let n = fi_pick_n(7, @qr.ecc_medium())
  if n < 0 {
    abort("vi 3-bit copy1: no pinning size")
  }
  let data = fi_random(n, 3113)
  let qr = @qr.encode_binary(data, @qr.ecc_medium(), 7)
  let matrix = fi_qr_to_matrix(qr)
  fi_flip_first_n(matrix, fi_version_copy1(qr.size()), 3)
  fi_assert_ok(matrix, data, "version 3-bit corrected")
}

///|
test "version info: 3 bits in each copy -> both BCH correct -> decode succeeds" {
  // Both version-info copies have 3 bit errors, within BCH(18,6) capacity.
  // copy1 recovers version 7 and the round trip succeeds.
  let n = fi_pick_n(7, @qr.ecc_medium())
  if n < 0 {
    abort("vi 3-bit each: no pinning size")
  }
  let data = fi_random(n, 3114)
  let qr = @qr.encode_binary(data, @qr.ecc_medium(), 7)
  let matrix = fi_qr_to_matrix(qr)
  fi_flip_first_n(matrix, fi_version_copy1(qr.size()), 3)
  fi_flip_first_n(matrix, fi_version_copy2(qr.size()), 3)
  fi_assert_ok(matrix, data, "version 3-bit each corrected")
}

// ==================== Cross-version sweep ====================

///|
test "cross version: V1/V7/V10/V20/V40 clean decode all succeed" {
  // Sweep representative versions spanning no-version-info (V1) and
  // version-info (V7+). Each must round trip cleanly.
  let versions = [1, 7, 10, 20, 40]
  for v in versions {
    let data = fi_asc(16)
    let qr = @qr.encode_binary(data, @qr.ecc_low(), v)
    assert_true(qr.version() == v)
    fi_assert_ok(fi_qr_to_matrix(qr), data, "cross V\{v}")
  }
}

// ==================== Robustness: no crash on heavy corruption ====================

///|
test "format info: heavy corruption does not crash decoder" {
  // Flip all format-info bits in both copies plus some data modules.
  // The decoder must not crash regardless of the outcome.
  let data = fi_asc(16)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let matrix = fi_qr_to_matrix(qr)
  fi_flip_all(matrix, fi_format_copy1())
  fi_flip_all(matrix, fi_format_copy2(qr.size()))
  for y = 0; y < 5; y = y + 1 {
    for x = 0; x < 5; x = x + 1 {
      fi_flip(matrix, 10 + x, 10 + y)
    }
  }
  let result = @qr.decode_qr(matrix)
  let _ = result
}

///|
test "version info: heavy corruption does not crash decoder (V10)" {
  // V10 with both version-info copies and some data modules corrupted.
  let data = fi_asc(32)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 10)
  let matrix = fi_qr_to_matrix(qr)
  fi_flip_all(matrix, fi_version_copy1(qr.size()))
  fi_flip_all(matrix, fi_version_copy2(qr.size()))
  fi_flip_all(matrix, fi_format_copy1())
  for y = 0; y < 4; y = y + 1 {
    for x = 0; x < 4; x = x + 1 {
      fi_flip(matrix, 12 + x, 12 + y)
    }
  }
  let result = @qr.decode_qr(matrix)
  let _ = result
}
