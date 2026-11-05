/// QR tables tests: EccLevel::from_string, ecc_codewords_per_block,
/// num_ecc_blocks, format_bits, ecc_tolerance, and ECC factory functions.
/// Covers tables.mbt public API against ISO/IEC 18004 values.

///|
test "tables: from_string L" {
  assert_true(@qr.EccLevel::from_string("L") == @qr.ecc_low())
}

///|
test "tables: from_string M" {
  assert_true(@qr.EccLevel::from_string("M") == @qr.ecc_medium())
}

///|
test "tables: from_string Q" {
  assert_true(@qr.EccLevel::from_string("Q") == @qr.ecc_quartile())
}

///|
test "tables: from_string H" {
  assert_true(@qr.EccLevel::from_string("H") == @qr.ecc_high())
}

///|
test "tables: ecc codewords v1" {
  // From tables.mbt: V1 L=7, M=10, Q=13, H=17.
  assert_true(@qr.ecc_codewords_per_block(@qr.ecc_low(), 1) == 7)
  assert_true(@qr.ecc_codewords_per_block(@qr.ecc_medium(), 1) == 10)
  assert_true(@qr.ecc_codewords_per_block(@qr.ecc_quartile(), 1) == 13)
  assert_true(@qr.ecc_codewords_per_block(@qr.ecc_high(), 1) == 17)
}

///|
test "tables: ecc codewords v40" {
  // V40: all ECC levels have ecc_codewords_per_block > 0.
  assert_true(@qr.ecc_codewords_per_block(@qr.ecc_low(), 40) > 0)
  assert_true(@qr.ecc_codewords_per_block(@qr.ecc_medium(), 40) > 0)
  assert_true(@qr.ecc_codewords_per_block(@qr.ecc_quartile(), 40) > 0)
  assert_true(@qr.ecc_codewords_per_block(@qr.ecc_high(), 40) > 0)
}

///|
test "tables: ecc codewords monotonic" {
  // At V1, ecc_codewords_per_block is monotonic: L < M < Q < H.
  // (This is NOT true for all versions — QR tables vary by block structure,
  // e.g. V3 has M=26 > Q=18. So we only assert V1 monotonicity here.)
  let v = 1
  let l = @qr.ecc_codewords_per_block(@qr.ecc_low(), v)
  let m = @qr.ecc_codewords_per_block(@qr.ecc_medium(), v)
  let q = @qr.ecc_codewords_per_block(@qr.ecc_quartile(), v)
  let h = @qr.ecc_codewords_per_block(@qr.ecc_high(), v)
  assert_true(l < m)
  assert_true(m < q)
  assert_true(q < h)
  // All versions 1..40 have positive ecc_codewords_per_block.
  for ver = 1; ver <= 40; ver = ver + 1 {
    assert_true(@qr.ecc_codewords_per_block(@qr.ecc_low(), ver) > 0)
    assert_true(@qr.ecc_codewords_per_block(@qr.ecc_medium(), ver) > 0)
    assert_true(@qr.ecc_codewords_per_block(@qr.ecc_quartile(), ver) > 0)
    assert_true(@qr.ecc_codewords_per_block(@qr.ecc_high(), ver) > 0)
  }
}

///|
test "tables: num ecc blocks v1" {
  // V1: all ECC levels have exactly 1 block.
  assert_true(@qr.num_ecc_blocks(@qr.ecc_low(), 1) == 1)
  assert_true(@qr.num_ecc_blocks(@qr.ecc_medium(), 1) == 1)
  assert_true(@qr.num_ecc_blocks(@qr.ecc_quartile(), 1) == 1)
  assert_true(@qr.num_ecc_blocks(@qr.ecc_high(), 1) == 1)
}

///|
test "tables: num ecc blocks v40" {
  // V40: all ECC levels have >= 1 block.
  assert_true(@qr.num_ecc_blocks(@qr.ecc_low(), 40) >= 1)
  assert_true(@qr.num_ecc_blocks(@qr.ecc_medium(), 40) >= 1)
  assert_true(@qr.num_ecc_blocks(@qr.ecc_quartile(), 40) >= 1)
  assert_true(@qr.num_ecc_blocks(@qr.ecc_high(), 40) >= 1)
}

///|
test "tables: format bits distinct" {
  // From tables.mbt: Low=1, Medium=0, Quartile=3, High=2.
  let l = @qr.format_bits(@qr.ecc_low())
  let m = @qr.format_bits(@qr.ecc_medium())
  let q = @qr.format_bits(@qr.ecc_quartile())
  let h = @qr.format_bits(@qr.ecc_high())
  assert_true(l != m)
  assert_true(l != q)
  assert_true(l != h)
  assert_true(m != q)
  assert_true(m != h)
  assert_true(q != h)
}

///|
test "tables: ecc tolerance values" {
  // From tables.mbt: L=7, M=15, Q=25, H=30.
  assert_true(@qr.ecc_tolerance(@qr.ecc_low()) == 7)
  assert_true(@qr.ecc_tolerance(@qr.ecc_medium()) == 15)
  assert_true(@qr.ecc_tolerance(@qr.ecc_quartile()) == 25)
  assert_true(@qr.ecc_tolerance(@qr.ecc_high()) == 30)
}

///|
test "tables: ecc tolerance monotonic" {
  // ecc_tolerance is monotonic: L < M < Q < H.
  let l = @qr.ecc_tolerance(@qr.ecc_low())
  let m = @qr.ecc_tolerance(@qr.ecc_medium())
  let q = @qr.ecc_tolerance(@qr.ecc_quartile())
  let h = @qr.ecc_tolerance(@qr.ecc_high())
  assert_true(l < m)
  assert_true(m < q)
  assert_true(q < h)
}

///|
test "tables: ecc factory distinct" {
  // Four ECC factory functions return mutually distinct values.
  let l = @qr.ecc_low()
  let m = @qr.ecc_medium()
  let q = @qr.ecc_quartile()
  let h = @qr.ecc_high()
  assert_true(l != m)
  assert_true(l != q)
  assert_true(l != h)
  assert_true(m != q)
  assert_true(m != h)
  assert_true(q != h)
}

///|
test "tables: ecc factory consistent" {
  // Multiple calls to the same factory return equal values.
  assert_true(@qr.ecc_low() == @qr.ecc_low())
  assert_true(@qr.ecc_medium() == @qr.ecc_medium())
  assert_true(@qr.ecc_quartile() == @qr.ecc_quartile())
  assert_true(@qr.ecc_high() == @qr.ecc_high())
}
