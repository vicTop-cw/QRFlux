/// Round-trip combination tests: version × ECC × mode/content matrix.
/// Verifies encode -> decode -> restore losslessness across
/// V1/V5/V10/V15/V20/V25/V30/V40 × L/M/Q/H × {byte, numeric content,
/// alphanumeric content}.
///
/// Mode coverage note: the public API exposes only Segment::make_bytes
/// (byte-mode segment construction). There is no Segment::make_numeric or
/// Segment::make_alphanumeric, and Segment struct fields are package-private,
/// so blackbox tests cannot trigger the numeric/alphanumeric *encoding* path.
/// The decoder fully supports numeric/alphanumeric modes (decoder.mbt:604-669),
/// but exercising those encoding paths requires whitebox segment construction.
/// To still cover the "mode" dimension at the blackbox level, the numeric and
/// alphanumeric groups encode ASCII digit/alphanumeric content via byte mode
/// and verify round-trip; this exercises the full byte codec on representative
/// content. Mode-metadata combinations (mode_bits, char_count_bits) for all
/// three modes are covered in a dedicated test block.

///|
/// Deterministic LCG pseudo-random bytes (same family as decoder_e2e_test).
fn rtc_random(n : Int32, seed : Int32) -> FixedArray[Int32] {
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
fn rtc_bytes(xs : Array[Int32]) -> FixedArray[Int32] {
  let fa = FixedArray::make(xs.length(), 0)
  for i = 0; i < xs.length(); i = i + 1 {
    fa[i] = xs[i]
  }
  fa
}

///|
/// Build n bytes of numeric content: ASCII '0'..'9' cycling with a seed offset.
/// Produces deterministic digit-character payloads for numeric-content groups.
fn rtc_digits(n : Int32, seed : Int32) -> FixedArray[Int32] {
  let fa = FixedArray::make(n, 0)
  for i = 0; i < n; i = i + 1 {
    fa[i] = 48 + (i + seed) % 10
  }
  fa
}

///|
/// Build n bytes of alphanumeric content: cycles through the 45-char
/// alphanumeric alphabet (0-9, A-Z, space $ % * + - . / :) as ASCII codes.
fn rtc_alnum(n : Int32, seed : Int32) -> FixedArray[Int32] {
  let table = [
    48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74,
    75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 32, 36, 37, 42,
    43, 45, 46, 47, 58,
  ]
  let fa = FixedArray::make(n, 0)
  for i = 0; i < n; i = i + 1 {
    fa[i] = table[(i + seed) % table.length()]
  }
  fa
}

///|
/// Build n bytes of mixed content: first third digits, middle third alnum,
/// last third pseudo-random bytes. Exercises heterogeneous byte payloads.
fn rtc_mixed(n : Int32, seed : Int32) -> FixedArray[Int32] {
  let fa = FixedArray::make(n, 0)
  let third = n / 3
  for i = 0; i < n; i = i + 1 {
    if i < third {
      fa[i] = 48 + (i + seed) % 10
    } else if i < 2 * third {
      fa[i] = 65 + (i + seed) % 26
    } else {
      let mut s = seed + i
      s = (s * 1103515245 + 12345) & 0x7FFFFFFF
      fa[i] = (s >> 16) & 0xFF
    }
  }
  fa
}

///|
/// Assert decoded bytes equal expected, with a label for failure diagnostics.
fn rtc_assert_eq(
  decoded : FixedArray[Int32]?,
  expected : FixedArray[Int32],
  label : String,
) -> Unit {
  match decoded {
    Some(d) =>
      if d.length() != expected.length() {
        abort(
          "rtc \{label}: length mismatch: got \{d.length()}, want \{expected.length()}",
        )
      } else {
        for i = 0; i < expected.length(); i = i + 1 {
          if d[i] != expected[i] {
            abort(
              "rtc \{label}: byte \{i} mismatch: got \{d[i]}, want \{expected[i]}",
            )
          }
        }
      }
    None => abort("rtc \{label}: decode returned None")
  }
}

///|
/// Short name for an ECC level (for labels).
fn rtc_level_name(l : @qr.EccLevel) -> String {
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
/// All four ECC levels in rank order L, M, Q, H.
fn rtc_all_levels() -> Array[@qr.EccLevel] {
  [@qr.ecc_low(), @qr.ecc_medium(), @qr.ecc_quartile(), @qr.ecc_high()]
}

///|
/// Pick a moderate byte payload length for (v, level): ~50% of byte-mode
/// capacity, capped at 200 to keep large-version tests fast. Returns -1 if
/// no positive length fits.
fn rtc_pick_len(v : Int32, level : @qr.EccLevel) -> Int32 {
  let cap = @qr.num_data_codewords(v, level)
  let ccbits = @qr.char_count_bits(@qr.mode_byte(), v)
  let n_max = (cap * 8 - 4 - ccbits) / 8
  if n_max < 1 {
    return -1
  }
  let half = n_max / 2
  if half < 1 {
    1
  } else if half > 200 {
    200
  } else {
    half
  }
}

// ===== Byte mode round-trip: one block per representative version × all ECC =====

///|
/// V1 × L/M/Q/H byte-mode round-trip with moderate pseudo-random payload.
test "rtc byte V1 all ecc" {
  let v = 1
  for level in rtc_all_levels() {
    let n = rtc_pick_len(v, level)
    if n < 0 {
      continue
    }
    let data = rtc_random(n, 1000 + v * 4 + rtc_level_name(level).length())
    let qr = @qr.encode_binary(data, level, v)
    if qr.version() != v {
      abort(
        "rtc byte V\{v}\{rtc_level_name(level)}: version \{qr.version()} != \{v}",
      )
    }
    rtc_assert_eq(
      @qr.decode_from_qrcode(qr),
      data,
      "byte V\{v}\{rtc_level_name(level)}",
    )
  }
}

///|
/// V5 × L/M/Q/H byte-mode round-trip.
test "rtc byte V5 all ecc" {
  let v = 5
  for level in rtc_all_levels() {
    let n = rtc_pick_len(v, level)
    if n < 0 {
      continue
    }
    let data = rtc_random(n, 2000 + v * 4 + rtc_level_name(level).length())
    let qr = @qr.encode_binary(data, level, v)
    if qr.version() != v {
      abort(
        "rtc byte V\{v}\{rtc_level_name(level)}: version \{qr.version()} != \{v}",
      )
    }
    rtc_assert_eq(
      @qr.decode_from_qrcode(qr),
      data,
      "byte V\{v}\{rtc_level_name(level)}",
    )
  }
}

///|
/// V10 × L/M/Q/H byte-mode round-trip.
test "rtc byte V10 all ecc" {
  let v = 10
  for level in rtc_all_levels() {
    let n = rtc_pick_len(v, level)
    if n < 0 {
      continue
    }
    let data = rtc_random(n, 3000 + v * 4 + rtc_level_name(level).length())
    let qr = @qr.encode_binary(data, level, v)
    if qr.version() != v {
      abort(
        "rtc byte V\{v}\{rtc_level_name(level)}: version \{qr.version()} != \{v}",
      )
    }
    rtc_assert_eq(
      @qr.decode_from_qrcode(qr),
      data,
      "byte V\{v}\{rtc_level_name(level)}",
    )
  }
}

///|
/// V15 × L/M/Q/H byte-mode round-trip.
test "rtc byte V15 all ecc" {
  let v = 15
  for level in rtc_all_levels() {
    let n = rtc_pick_len(v, level)
    if n < 0 {
      continue
    }
    let data = rtc_random(n, 4000 + v * 4 + rtc_level_name(level).length())
    let qr = @qr.encode_binary(data, level, v)
    if qr.version() != v {
      abort(
        "rtc byte V\{v}\{rtc_level_name(level)}: version \{qr.version()} != \{v}",
      )
    }
    rtc_assert_eq(
      @qr.decode_from_qrcode(qr),
      data,
      "byte V\{v}\{rtc_level_name(level)}",
    )
  }
}

///|
/// V20 × L/M/Q/H byte-mode round-trip.
test "rtc byte V20 all ecc" {
  let v = 20
  for level in rtc_all_levels() {
    let n = rtc_pick_len(v, level)
    if n < 0 {
      continue
    }
    let data = rtc_random(n, 5000 + v * 4 + rtc_level_name(level).length())
    let qr = @qr.encode_binary(data, level, v)
    if qr.version() != v {
      abort(
        "rtc byte V\{v}\{rtc_level_name(level)}: version \{qr.version()} != \{v}",
      )
    }
    rtc_assert_eq(
      @qr.decode_from_qrcode(qr),
      data,
      "byte V\{v}\{rtc_level_name(level)}",
    )
  }
}

///|
/// V25 × L/M/Q/H byte-mode round-trip.
test "rtc byte V25 all ecc" {
  let v = 25
  for level in rtc_all_levels() {
    let n = rtc_pick_len(v, level)
    if n < 0 {
      continue
    }
    let data = rtc_random(n, 6000 + v * 4 + rtc_level_name(level).length())
    let qr = @qr.encode_binary(data, level, v)
    if qr.version() != v {
      abort(
        "rtc byte V\{v}\{rtc_level_name(level)}: version \{qr.version()} != \{v}",
      )
    }
    rtc_assert_eq(
      @qr.decode_from_qrcode(qr),
      data,
      "byte V\{v}\{rtc_level_name(level)}",
    )
  }
}

///|
/// V30 × L/M/Q/H byte-mode round-trip.
test "rtc byte V30 all ecc" {
  let v = 30
  for level in rtc_all_levels() {
    let n = rtc_pick_len(v, level)
    if n < 0 {
      continue
    }
    let data = rtc_random(n, 7000 + v * 4 + rtc_level_name(level).length())
    let qr = @qr.encode_binary(data, level, v)
    if qr.version() != v {
      abort(
        "rtc byte V\{v}\{rtc_level_name(level)}: version \{qr.version()} != \{v}",
      )
    }
    rtc_assert_eq(
      @qr.decode_from_qrcode(qr),
      data,
      "byte V\{v}\{rtc_level_name(level)}",
    )
  }
}

///|
/// V40 × L/M/Q/H byte-mode round-trip.
test "rtc byte V40 all ecc" {
  let v = 40
  for level in rtc_all_levels() {
    let n = rtc_pick_len(v, level)
    if n < 0 {
      continue
    }
    let data = rtc_random(n, 8000 + v * 4 + rtc_level_name(level).length())
    let qr = @qr.encode_binary(data, level, v)
    if qr.version() != v {
      abort(
        "rtc byte V\{v}\{rtc_level_name(level)}: version \{qr.version()} != \{v}",
      )
    }
    rtc_assert_eq(
      @qr.decode_from_qrcode(qr),
      data,
      "byte V\{v}\{rtc_level_name(level)}",
    )
  }
}

// ===== Numeric content round-trip (byte-mode encoding of digit chars) =====

///|
/// Numeric content (ASCII '0'..'9') across V1/V10/V20/V40 × L/M/Q/H.
/// Byte-mode encoding of digit payloads; verifies decode restores exact bytes.
test "rtc numeric content V1 V10 V20 V40 all ecc" {
  let versions = [1, 10, 20, 40]
  let mut tested = 0
  for v in versions {
    for level in rtc_all_levels() {
      let n = rtc_pick_len(v, level)
      if n < 0 {
        continue
      }
      tested = tested + 1
      let data = rtc_digits(n, v * 7 + rtc_level_name(level).length())
      let qr = @qr.encode_binary(data, level, v)
      let label = "num V\{v}\{rtc_level_name(level)}"
      if qr.version() != v {
        abort("rtc \{label}: version \{qr.version()} != \{v}")
      }
      rtc_assert_eq(@qr.decode_from_qrcode(qr), data, label)
    }
  }
  if tested < 12 {
    abort("rtc numeric content: only \{tested} combos tested, expected >= 12")
  }
}

///|
/// Numeric content across V5/V15/V25/V30 × L/M/Q/H (complement of above).
test "rtc numeric content V5 V15 V25 V30 all ecc" {
  let versions = [5, 15, 25, 30]
  let mut tested = 0
  for v in versions {
    for level in rtc_all_levels() {
      let n = rtc_pick_len(v, level)
      if n < 0 {
        continue
      }
      tested = tested + 1
      let data = rtc_digits(n, 500 + v * 7 + rtc_level_name(level).length())
      let qr = @qr.encode_binary(data, level, v)
      let label = "num2 V\{v}\{rtc_level_name(level)}"
      rtc_assert_eq(@qr.decode_from_qrcode(qr), data, label)
    }
  }
  if tested < 12 {
    abort(
      "rtc numeric content v2: only \{tested} combos tested, expected >= 12",
    )
  }
}

// ===== Alphanumeric content round-trip (byte-mode encoding of alnum chars) =====

///|
/// Alphanumeric content (0-9 A-Z space $%*+-./:) across V1/V10/V20/V40 × L/M/Q/H.
test "rtc alnum content V1 V10 V20 V40 all ecc" {
  let versions = [1, 10, 20, 40]
  let mut tested = 0
  for v in versions {
    for level in rtc_all_levels() {
      let n = rtc_pick_len(v, level)
      if n < 0 {
        continue
      }
      tested = tested + 1
      let data = rtc_alnum(n, v * 9 + rtc_level_name(level).length())
      let qr = @qr.encode_binary(data, level, v)
      let label = "alnum V\{v}\{rtc_level_name(level)}"
      if qr.version() != v {
        abort("rtc \{label}: version \{qr.version()} != \{v}")
      }
      rtc_assert_eq(@qr.decode_from_qrcode(qr), data, label)
    }
  }
  if tested < 12 {
    abort("rtc alnum content: only \{tested} combos tested, expected >= 12")
  }
}

///|
/// Alphanumeric content across V5/V15/V25/V30 × L/M/Q/H (complement of above).
test "rtc alnum content V5 V15 V25 V30 all ecc" {
  let versions = [5, 15, 25, 30]
  let mut tested = 0
  for v in versions {
    for level in rtc_all_levels() {
      let n = rtc_pick_len(v, level)
      if n < 0 {
        continue
      }
      tested = tested + 1
      let data = rtc_alnum(n, 300 + v * 9 + rtc_level_name(level).length())
      let qr = @qr.encode_binary(data, level, v)
      let label = "alnum2 V\{v}\{rtc_level_name(level)}"
      rtc_assert_eq(@qr.decode_from_qrcode(qr), data, label)
    }
  }
  if tested < 12 {
    abort("rtc alnum content v2: only \{tested} combos tested, expected >= 12")
  }
}

// ===== Mixed content round-trip =====

///|
/// Mixed content (digits + letters + random bytes) across all 8 versions × L/M/Q/H.
test "rtc mixed content all versions all ecc" {
  let versions = [1, 5, 10, 15, 20, 25, 30, 40]
  let mut tested = 0
  for v in versions {
    for level in rtc_all_levels() {
      let n = rtc_pick_len(v, level)
      if n < 0 {
        continue
      }
      tested = tested + 1
      let data = rtc_mixed(n, 700 + v * 5 + rtc_level_name(level).length())
      let qr = @qr.encode_binary(data, level, v)
      let label = "mix V\{v}\{rtc_level_name(level)}"
      rtc_assert_eq(@qr.decode_from_qrcode(qr), data, label)
    }
  }
  if tested < 24 {
    abort("rtc mixed content: only \{tested} combos tested, expected >= 24")
  }
}

// ===== Mode metadata combinations: version × all three modes =====

///|
/// Mode metadata (mode_bits, char_count_bits) for numeric/alphanumeric/byte
/// across all 8 representative versions. Covers the "mode" dimension of the
/// matrix at the metadata level (encoding path requires whitebox segment
/// construction; see file header note).
test "rtc mode metadata all versions all modes" {
  let versions = [1, 5, 10, 15, 20, 25, 30, 40]
  let modes = [@qr.mode_numeric(), @qr.mode_alphanumeric(), @qr.mode_byte()]
  // Expected mode indicator bits: numeric=1, alnum=2, byte=4.
  let expected_bits = [
    @qr.mode_bits(@qr.mode_numeric()),
    @qr.mode_bits(@qr.mode_alphanumeric()),
    @qr.mode_bits(@qr.mode_byte()),
  ]
  assert_true(expected_bits[0] == 1)
  assert_true(expected_bits[1] == 2)
  assert_true(expected_bits[2] == 4)
  for v in versions {
    for k = 0; k < modes.length(); k = k + 1 {
      let m = modes[k]
      let ccbits = @qr.char_count_bits(m, v)
      // char_count_bits must be positive and within documented bounds.
      if ccbits < 8 || ccbits > 16 {
        abort(
          "rtc meta V\{v} mode\{k}: char_count_bits \{ccbits} out of [8,16]",
        )
      }
      // mode_bits must be the canonical indicator.
      if @qr.mode_bits(m) != expected_bits[k] {
        abort("rtc meta V\{v} mode\{k}: mode_bits mismatch")
      }
      // Version-group boundaries for char_count_bits.
      let group = (v + 7) / 17
      let want : Int32 = match m {
        _ =>
          if k == 0 {
            [10, 12, 14][group]
          } else if k == 1 {
            [9, 11, 13][group]
          } else {
            [8, 16, 16][group]
          }
      }
      if ccbits != want {
        abort("rtc meta V\{v} mode\{k}: char_count_bits \{ccbits} != \{want}")
      }
    }
  }
}

// ===== Near-capacity byte stress: pin version and fill close to capacity =====

///|
/// Near-capacity byte payload on V1/V10/V20/V40 × L/H to stress the codec at
/// the upper end of the per-(version,level) data envelope.
test "rtc near-capacity byte V1 V10 V20 V40 L H" {
  let versions = [1, 10, 20, 40]
  let levels = [@qr.ecc_low(), @qr.ecc_high()]
  let mut tested = 0
  for v in versions {
    for level in levels {
      let cap = @qr.num_data_codewords(v, level)
      let ccbits = @qr.char_count_bits(@qr.mode_byte(), v)
      let n_max = (cap * 8 - 4 - ccbits) / 8
      if n_max < 1 {
        continue
      }
      // Use ~90% of capacity, capped at 250 to keep test fast.
      let n = if n_max * 9 / 10 > 250 {
        250
      } else if n_max * 9 / 10 < 1 {
        1
      } else {
        n_max * 9 / 10
      }
      tested = tested + 1
      let data = rtc_random(n, 9000 + v * 3 + rtc_level_name(level).length())
      let qr = @qr.encode_binary(data, level, v)
      let label = "nearcap V\{v}\{rtc_level_name(level)}"
      if qr.version() != v {
        abort("rtc \{label}: version \{qr.version()} != \{v}")
      }
      // encode_binary auto-boosts ECC to the highest level that still fits the
      // data, so qr.level() may exceed the requested level. We do not pin
      // level here; the round-trip itself is the property under test.
      rtc_assert_eq(@qr.decode_from_qrcode(qr), data, label)
    }
  }
  if tested < 6 {
    abort("rtc near-capacity: only \{tested} combos tested, expected >= 6")
  }
}

// ===== Tiny payload + empty payload across the version span =====

///|
/// Tiny (3-byte) and empty payloads across all 8 versions × L/M/Q/H to cover
/// the lower end of the payload-size dimension.
test "rtc tiny and empty payload all versions all ecc" {
  let versions = [1, 5, 10, 15, 20, 25, 30, 40]
  let tiny = rtc_bytes([0x41, 0x42, 0x43])
  let empty = FixedArray::make(0, 0)
  let mut tested = 0
  for v in versions {
    for level in rtc_all_levels() {
      // Tiny payload.
      tested = tested + 1
      let qr1 = @qr.encode_binary(tiny, level, v)
      if qr1.version() != v {
        abort(
          "rtc tiny V\{v}\{rtc_level_name(level)}: version \{qr1.version()} != \{v}",
        )
      }
      rtc_assert_eq(
        @qr.decode_from_qrcode(qr1),
        tiny,
        "tiny V\{v}\{rtc_level_name(level)}",
      )
      // Empty payload.
      tested = tested + 1
      let qr2 = @qr.encode_binary(empty, level, v)
      if qr2.version() != v {
        abort(
          "rtc empty V\{v}\{rtc_level_name(level)}: version \{qr2.version()} != \{v}",
        )
      }
      match @qr.decode_from_qrcode(qr2) {
        Some(d) =>
          if d.length() != 0 {
            abort(
              "rtc empty V\{v}\{rtc_level_name(level)}: expected 0 bytes, got \{d.length()}",
            )
          }
        None =>
          abort("rtc empty V\{v}\{rtc_level_name(level)}: decode returned None")
      }
    }
  }
  if tested < 48 {
    abort("rtc tiny/empty: only \{tested} combos tested, expected >= 48")
  }
}
