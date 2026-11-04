/// Full-version end-to-end tests for the self-implemented QR decoder.
/// Verifies encode -> decode -> restore round-trip across V1..V40
/// representative versions, all ECC levels, and varied data profiles.
/// Zero third-party dependencies: uses only the in-house encoder + decoder.

///|
/// Deterministic pseudo-random bytes (LCG, same as cmd/main and decoder_test).
fn e2e_random(n : Int32, seed : Int32) -> FixedArray[Int32] {
  let fa = FixedArray::make(n, 0)
  let mut s = seed
  for i = 0; i < n; i = i + 1 {
    s = (s * 1103515245 + 12345) & 0x7FFFFFFF
    fa[i] = (s >> 16) & 0xFF
  }
  fa
}

///|
/// Build a FixedArray from a literal array of small ints.
fn e2e_bytes(xs : Array[Int32]) -> FixedArray[Int32] {
  let fa = FixedArray::make(xs.length(), 0)
  for i = 0; i < xs.length(); i = i + 1 {
    fa[i] = xs[i]
  }
  fa
}

///|
/// Assert decoded bytes equal expected, with a label for failure diagnostics.
fn e2e_assert_eq(
  decoded : FixedArray[Int32]?,
  expected : FixedArray[Int32],
  label : String,
) -> Unit {
  match decoded {
    Some(d) =>
      if d.length() != expected.length() {
        abort(
          "e2e \{label}: length mismatch: got \{d.length()}, want \{expected.length()}",
        )
      } else {
        for i = 0; i < expected.length(); i = i + 1 {
          if d[i] != expected[i] {
            abort(
              "e2e \{label}: byte \{i} mismatch: got \{d[i]}, want \{expected[i]}",
            )
          }
        }
      }
    None => abort("e2e \{label}: decode returned None")
  }
}

///|
/// Rank of ECC level by correction strength: L=0, M=1, Q=2, H=3.
fn e2e_rank(l : @qr.EccLevel) -> Int32 {
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
/// Short name for an ECC level (for labels).
fn e2e_level_name(l : @qr.EccLevel) -> String {
  if l == @qr.ecc_low() {
    "L"
  } else if l == @qr.ecc_medium() {
    "M"
  } else if l == @qr.ecc_quartile() {
    "Q"
  } else {
    "H"
  }
}

///|
/// Pick a data length n so that encode_binary(data(n), target, v) lands on
/// exactly (v, target) after auto-boost. Returns n near capacity, or -1 if
/// no such n exists (gap skip). Byte-mode bit budget: 4 + ccbits + 8*n.
/// To pin target_level, data must fit target but NOT fit any higher level.
fn e2e_pick_n(v : Int32, target : @qr.EccLevel) -> Int32 {
  let cap = @qr.num_data_codewords(v, target)
  let ccbits = @qr.char_count_bits(@qr.mode_byte(), v)
  // n_max: largest n that fits target_level.
  let n_max = (cap * 8 - 4 - ccbits) / 8
  // n_min: smallest n that does NOT fit any higher level (rank > target).
  let mut n_min : Int32 = 0
  if target == @qr.ecc_high() {
    // H is the highest level; no boost possible. n_min stays 0.
    ()
  } else {
    let all = [
      @qr.ecc_low(),
      @qr.ecc_medium(),
      @qr.ecc_quartile(),
      @qr.ecc_high(),
    ]
    for l in all {
      if e2e_rank(l) > e2e_rank(target) {
        let hcap = @qr.num_data_codewords(v, l)
        // Need 4 + ccbits + 8*n > hcap*8  =>  n > (hcap*8 - 4 - ccbits)/8
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

///|
/// Core matrix: 11 representative versions x 4 ECC levels, near-capacity
/// payload. Pins exact (version, level) and verifies decode round-trip.
test "e2e near-capacity V1..V40 x L/M/Q/H" {
  let versions = [1, 3, 5, 7, 10, 15, 20, 25, 30, 35, 40]
  let levels = [
    @qr.ecc_low(),
    @qr.ecc_medium(),
    @qr.ecc_quartile(),
    @qr.ecc_high(),
  ]
  let mut tested = 0
  for v in versions {
    for level in levels {
      let n = e2e_pick_n(v, level)
      if n < 0 {
        continue
      }
      tested = tested + 1
      let data = e2e_random(n, 12345 + v * 4 + e2e_rank(level))
      let qr = @qr.encode_binary(data, level, v)
      let label = "V\{v}\{e2e_level_name(level)} near-cap"
      if qr.version() != v {
        abort("e2e \{label}: version \{qr.version()} != \{v}")
      }
      if qr.level() != level {
        abort("e2e \{label}: level mismatch (boosted)")
      }
      let decoded = @qr.decode_from_qrcode(qr)
      e2e_assert_eq(decoded, data, label)
    }
  }
  // Sanity guard: ensure a meaningful number of combinations were tested.
  if tested < 30 {
    abort("e2e near-capacity: only \{tested} combos tested, expected >= 30")
  }
}

///|
/// Short text "Hello" (5 bytes) across all representative versions.
/// Auto-boost may raise ECC; we verify version pin and decode round-trip.
test "e2e short text Hello all versions" {
  let versions = [1, 3, 5, 7, 10, 15, 20, 25, 30, 35, 40]
  let data = e2e_bytes([72, 101, 108, 108, 111])
  for v in versions {
    let qr = @qr.encode_binary(data, @qr.ecc_low(), v)
    if qr.version() != v {
      abort("e2e Hello V\{v}: version \{qr.version()} != \{v}")
    }
    let decoded = @qr.decode_from_qrcode(qr)
    e2e_assert_eq(decoded, data, "V\{v} Hello")
  }
}

///|
/// Medium 50-byte payload across all representative versions and levels.
/// Skips combos where 50 bytes overflow the (v, level) capacity.
test "e2e medium 50 bytes all versions x levels" {
  let versions = [1, 3, 5, 7, 10, 15, 20, 25, 30, 35, 40]
  let levels = [
    @qr.ecc_low(),
    @qr.ecc_medium(),
    @qr.ecc_quartile(),
    @qr.ecc_high(),
  ]
  let mut tested = 0
  for v in versions {
    for level in levels {
      let cap = @qr.num_data_codewords(v, level)
      let ccbits = @qr.char_count_bits(@qr.mode_byte(), v)
      if 4 + ccbits + 8 * 50 > cap * 8 {
        continue
      }
      tested = tested + 1
      let data = e2e_random(50, 999 + v * 4 + e2e_rank(level))
      let qr = @qr.encode_binary(data, level, v)
      let label = "V\{v}\{e2e_level_name(level)} 50B"
      if qr.version() != v {
        abort("e2e \{label}: version \{qr.version()} != \{v}")
      }
      let decoded = @qr.decode_from_qrcode(qr)
      e2e_assert_eq(decoded, data, label)
    }
  }
  if tested < 20 {
    abort("e2e medium 50B: only \{tested} combos tested, expected >= 20")
  }
}

///|
/// Special data patterns (zeros, 0xFF, alternating) on selected versions.
/// Exercises non-random byte distributions through the full codec path.
test "e2e special patterns zeros ff alt" {
  let versions = [1, 10, 25, 40]
  for v in versions {
    let cap = @qr.num_data_codewords(v, @qr.ecc_low())
    let ccbits = @qr.char_count_bits(@qr.mode_byte(), v)
    let n_max = (cap * 8 - 4 - ccbits) / 8
    // Use up to 200 bytes to keep test fast on large versions.
    let n = if n_max > 200 { 200 } else { n_max }
    if n < 1 {
      continue
    }
    let zeros = FixedArray::make(n, 0)
    let qr1 = @qr.encode_binary(zeros, @qr.ecc_low(), v)
    e2e_assert_eq(@qr.decode_from_qrcode(qr1), zeros, "V\{v} zeros")
    let ffs = FixedArray::make(n, 255)
    let qr2 = @qr.encode_binary(ffs, @qr.ecc_low(), v)
    e2e_assert_eq(@qr.decode_from_qrcode(qr2), ffs, "V\{v} 0xFF")
    let alt = FixedArray::make(n, 0)
    for i = 0; i < n; i = i + 1 {
      alt[i] = if i % 2 == 0 { 0x55 } else { 0xAA }
    }
    let qr3 = @qr.encode_binary(alt, @qr.ecc_low(), v)
    e2e_assert_eq(@qr.decode_from_qrcode(qr3), alt, "V\{v} alt")
  }
}

///|
/// Empty payload round-trip across selected versions.
test "e2e empty payload" {
  let versions = [1, 7, 20, 40]
  let empty = FixedArray::make(0, 0)
  for v in versions {
    let qr = @qr.encode_binary(empty, @qr.ecc_low(), v)
    if qr.version() != v {
      abort("e2e empty V\{v}: version \{qr.version()} != \{v}")
    }
    match @qr.decode_from_qrcode(qr) {
      Some(d) =>
        if d.length() != 0 {
          abort("e2e empty V\{v}: expected 0 bytes, got \{d.length()}")
        }
      None => abort("e2e empty V\{v}: decode returned None")
    }
  }
}
