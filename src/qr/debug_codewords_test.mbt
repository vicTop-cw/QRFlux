// Tests for the public debug_codewords helper.
// debug_codewords(data, ecl, minversion) returns (datacodewords, allcodewords)
// where datacodewords is the raw data codewords and allcodewords is the
// ECC-appended interleaved block output. These tests verify non-emptiness,
// version-dependent sizing, ECC-level coverage, and call determinism.

///|
/// Build a FixedArray[Int32] from a literal array of small ints.
fn dc_bytes(xs : Array[Int32]) -> FixedArray[Int32] {
  let fa = FixedArray::make(xs.length(), 0)
  for i = 0; i < xs.length(); i = i + 1 {
    fa[i] = xs[i]
  }
  fa
}

///|
/// Build n bytes of deterministic test data with a non-trivial pattern.
fn dc_make_data(n : Int32) -> FixedArray[Int32] {
  let fa = FixedArray::make(n, 0)
  for i = 0; i < n; i = i + 1 {
    fa[i] = (i * 31 + 17) & 0xFF
  }
  fa
}

///|
/// Element-wise equality check for two FixedArray[Int32].
fn dc_fa_eq(a : FixedArray[Int32], b : FixedArray[Int32]) -> Bool {
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
test "debug codewords: V1 returns non empty" {
  let data = dc_bytes([72, 101, 108, 108, 111]) // "Hello"
  let (datacw, allcw) = @qr.debug_codewords(data, @qr.ecc_low(), 1)
  assert_true(datacw.length() > 0)
  assert_true(allcw.length() > 0)
  // allcw includes data + ECC codewords, so it is at least as long as datacw.
  assert_true(allcw.length() >= datacw.length())
}

///|
test "debug codewords: V5 returns non empty" {
  let data = dc_make_data(20)
  let (datacw, allcw) = @qr.debug_codewords(data, @qr.ecc_low(), 5)
  assert_true(datacw.length() > 0)
  assert_true(allcw.length() > 0)
  assert_true(allcw.length() >= datacw.length())
}

///|
test "debug codewords: V10 returns non empty" {
  let data = dc_make_data(50)
  let (datacw, allcw) = @qr.debug_codewords(data, @qr.ecc_medium(), 10)
  assert_true(datacw.length() > 0)
  assert_true(allcw.length() > 0)
  assert_true(allcw.length() >= datacw.length())
}

///|
test "debug codewords: different versions different length" {
  // Same payload encoded at V1 vs V10 must produce different data-codeword
  // counts because larger versions have more data capacity.
  let data = dc_bytes([72, 101, 108, 108, 111])
  let (datacw1, allcw1) = @qr.debug_codewords(data, @qr.ecc_low(), 1)
  let (datacw10, allcw10) = @qr.debug_codewords(data, @qr.ecc_low(), 10)
  // V10 has strictly more data codewords than V1.
  assert_true(datacw10.length() > datacw1.length())
  // V10 also has more total (data + ECC) codewords.
  assert_true(allcw10.length() > allcw1.length())
}

///|
test "debug codewords: all ecc levels" {
  // V1 across all four ECC levels. Data sizes are chosen to pin each level
  // (avoid auto-boost) so every level produces a distinct, non-empty output.
  // V1 byte-mode capacity: L=17, M=14, Q=11, H=7 bytes max.
  let levels = [
    @qr.ecc_low(),
    @qr.ecc_medium(),
    @qr.ecc_quartile(),
    @qr.ecc_high(),
  ]
  // 15 bytes pins L (fits L=17, not M=14); 12 pins M; 9 pins Q; 7 pins H.
  let sizes = [15, 12, 9, 7]
  for i = 0; i < 4; i = i + 1 {
    let data = dc_make_data(sizes[i])
    let (datacw, allcw) = @qr.debug_codewords(data, levels[i], 1)
    assert_true(datacw.length() > 0)
    assert_true(allcw.length() > 0)
    assert_true(allcw.length() >= datacw.length())
  }
}

///|
test "debug codewords: consistent across calls" {
  // The function must be deterministic: the same inputs yield identical
  // codeword arrays across repeated calls.
  let data = dc_make_data(30)
  let (datacw1, allcw1) = @qr.debug_codewords(data, @qr.ecc_medium(), 5)
  let (datacw2, allcw2) = @qr.debug_codewords(data, @qr.ecc_medium(), 5)
  let (datacw3, allcw3) = @qr.debug_codewords(data, @qr.ecc_medium(), 5)
  assert_true(dc_fa_eq(datacw1, datacw2))
  assert_true(dc_fa_eq(datacw2, datacw3))
  assert_true(dc_fa_eq(allcw1, allcw2))
  assert_true(dc_fa_eq(allcw2, allcw3))
}
