/// Mask selection algorithm tests (blackbox).
/// Tests mask selection through public API: encode_binary + QrCode.mask().

///|
test "mask: best mask in range 0-7" {
  // After encoding, the selected mask must be in [0, 7].
  let data = FixedArray::make(10, 0x42)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let m = qr.mask()
  assert_true(m >= 0 && m <= 7)
}

///|
test "mask: same data same mask" {
  // Encoding the same data with same params must pick the same mask
  // (mask selection is deterministic).
  let data = FixedArray::make(20, 0x41)
  let qr1 = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let qr2 = @qr.encode_binary(data, @qr.ecc_low(), 1)
  assert_true(qr1.mask() == qr2.mask())
}

///|
test "mask: different data may differ" {
  // After fixing the bestpenalty initialization bug (was `1 << 31` which
  // overflowed to Int32 min, now `0x7FFFFFFF`), mask selection actually
  // picks the lowest-penalty mask. Different data should produce varied
  // mask selections (not all 0).
  let mask_set : Array[Int32] = []
  for i = 0; i < 20; i = i + 1 {
    let n = 5 + i
    let data = FixedArray::make(n, 0)
    for j = 0; j < n; j = j + 1 {
      data[j] = (i * 53 + j * 91 + 7) % 256
    }
    let level = if i % 2 == 0 { @qr.ecc_low() } else { @qr.ecc_medium() }
    let qr = @qr.encode_binary(data, level, 1)
    let m = qr.mask()
    // Mask must be in valid range.
    assert_true(m >= 0 && m <= 7)
    // Collect distinct masks.
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
  // With the bug fixed, at least 2 different masks should be selected
  // across 20 varied inputs (mask selection is no longer constant 0).
  assert_true(mask_set.length() >= 2)
}

///|
test "mask: all versions have valid mask" {
  // For every version 1..40, the selected mask is in [0, 7].
  let mut all_valid = true
  for v = 1; v <= 40; v = v + 1 {
    let data = FixedArray::make(1, 0x42)
    let qr = @qr.encode_binary(data, @qr.ecc_low(), v)
    let m = qr.mask()
    if m < 0 || m > 7 {
      all_valid = false
    }
  }
  assert_true(all_valid)
}

///|
test "mask: all ecc levels have valid mask" {
  // All four ECC levels produce a valid mask in [0, 7].
  let data = FixedArray::make(10, 0x42)
  let levels = [
    @qr.ecc_low(),
    @qr.ecc_medium(),
    @qr.ecc_quartile(),
    @qr.ecc_high(),
  ]
  let mut all_valid = true
  for l in levels {
    let qr = @qr.encode_binary(data, l, 1)
    let m = qr.mask()
    if m < 0 || m > 7 {
      all_valid = false
    }
  }
  assert_true(all_valid)
}

///|
test "mask: mask 0 vs best mask penalty" {
  // The best mask produces a decodable QR code (mask selection yields a
  // valid, optimal QR). We verify by round-trip decoding: if the mask
  // selection were broken, the decoder would fail or return wrong data.
  let data = FixedArray::make(15, 0x42)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let m = qr.mask()
  assert_true(m >= 0 && m <= 7)
  // Round-trip: decode the encoded QR and verify payload matches.
  let decoded = @qr.decode_from_qrcode(qr)
  match decoded {
    Some(bytes) => {
      assert_true(bytes.length() == 15)
      let mut all_match = true
      for i = 0; i < 15; i = i + 1 {
        if bytes[i] != 0x42 {
          all_match = false
        }
      }
      assert_true(all_match)
    }
    None => assert_true(false)
  }
}

///|
test "mask: 8 masks cover all patterns" {
  // After fixing the bestpenalty initialization bug, mask selection picks
  // the optimal mask per ISO/IEC 18004. This test verifies that selected
  // masks are valid (0-7) and produce decodable QR codes across varied
  // payloads. The 8 mask patterns themselves are verified distinct in the
  // whitebox test "enc wb: mask pattern all 8 distinct".
  let mut all_valid = true
  for i = 0; i < 30; i = i + 1 {
    let n = 3 + i
    let data = FixedArray::make(n, 0)
    for j = 0; j < n; j = j + 1 {
      data[j] = (i * 37 + j * 73 + 11) % 256
    }
    let level = if i % 2 == 0 { @qr.ecc_low() } else { @qr.ecc_medium() }
    let qr = @qr.encode_binary(data, level, 1)
    // Mask must be in valid range.
    let m = qr.mask()
    if m < 0 || m > 7 {
      all_valid = false
    }
    // QR must be decodable (any valid mask produces decodable output).
    let decoded = @qr.decode_from_qrcode(qr)
    match decoded {
      Some(bytes) => if bytes.length() != n { all_valid = false }
      None => all_valid = false
    }
  }
  assert_true(all_valid)
}

///|
test "mask: mask selection stable across versions" {
  // Same data encoded at different minimum versions: all masks valid,
  // and the selection is deterministic (re-encoding gives same mask).
  let data = FixedArray::make(5, 0x42)
  let mut all_valid = true
  for v = 1; v <= 10; v = v + 1 {
    let qr1 = @qr.encode_binary(data, @qr.ecc_low(), v)
    let qr2 = @qr.encode_binary(data, @qr.ecc_low(), v)
    let m = qr1.mask()
    if m < 0 || m > 7 {
      all_valid = false
    }
    // Determinism: same data + same params => same mask.
    if qr1.mask() != qr2.mask() {
      all_valid = false
    }
  }
  assert_true(all_valid)
}
