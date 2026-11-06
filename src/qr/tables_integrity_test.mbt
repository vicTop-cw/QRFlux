/// QR tables integrity tests: exhaustive validation of constant tables
/// across V1~V40 × L/M/Q/H (160 combinations). Covers ecc_codewords_per_block,
/// num_ecc_blocks, ecc_tolerance, format_bits, EccLevel::from_string,
/// num_data_codewords (capacity monotonicity + ECC strength ordering), and
/// alignment_pattern_positions. Blackbox: only calls pub fn from @qr.

///|
test "tables_integrity: ecc_codewords_per_block positive all 160" {
  let levels = [
    @qr.ecc_low(),
    @qr.ecc_medium(),
    @qr.ecc_quartile(),
    @qr.ecc_high(),
  ]
  for lev in levels {
    for ver = 1; ver <= 40; ver = ver + 1 {
      let cw = @qr.ecc_codewords_per_block(lev, ver)
      assert_true(cw > 0)
    }
  }
}

///|
test "tables_integrity: ecc_codewords_per_block bounded by 30" {
  // ISO/IEC 18004: max ECC codewords per block across all versions is 30.
  let levels = [
    @qr.ecc_low(),
    @qr.ecc_medium(),
    @qr.ecc_quartile(),
    @qr.ecc_high(),
  ]
  for lev in levels {
    for ver = 1; ver <= 40; ver = ver + 1 {
      let cw = @qr.ecc_codewords_per_block(lev, ver)
      assert_true(cw <= 30)
    }
  }
}

///|
test "tables_integrity: num_ecc_blocks at least 1 all 160" {
  let levels = [
    @qr.ecc_low(),
    @qr.ecc_medium(),
    @qr.ecc_quartile(),
    @qr.ecc_high(),
  ]
  for lev in levels {
    for ver = 1; ver <= 40; ver = ver + 1 {
      let nb = @qr.num_ecc_blocks(lev, ver)
      assert_true(nb >= 1)
    }
  }
}

///|
test "tables_integrity: num_ecc_blocks bounded by 81" {
  // V40 High has 81 blocks (the max in the table).
  let levels = [
    @qr.ecc_low(),
    @qr.ecc_medium(),
    @qr.ecc_quartile(),
    @qr.ecc_high(),
  ]
  for lev in levels {
    for ver = 1; ver <= 40; ver = ver + 1 {
      let nb = @qr.num_ecc_blocks(lev, ver)
      assert_true(nb <= 81)
    }
  }
}

///|
test "tables_integrity: ecc_tolerance positive and strictly ordered" {
  let l = @qr.ecc_tolerance(@qr.ecc_low())
  let m = @qr.ecc_tolerance(@qr.ecc_medium())
  let q = @qr.ecc_tolerance(@qr.ecc_quartile())
  let h = @qr.ecc_tolerance(@qr.ecc_high())
  assert_true(l > 0)
  assert_true(m > 0)
  assert_true(q > 0)
  assert_true(h > 0)
  assert_true(l < m)
  assert_true(m < q)
  assert_true(q < h)
}

///|
test "tables_integrity: ecc_tolerance matches ISO percent" {
  // ISO/IEC 18004 tolerance: L=7%, M=15%, Q=25%, H=30%.
  assert_true(@qr.ecc_tolerance(@qr.ecc_low()) == 7)
  assert_true(@qr.ecc_tolerance(@qr.ecc_medium()) == 15)
  assert_true(@qr.ecc_tolerance(@qr.ecc_quartile()) == 25)
  assert_true(@qr.ecc_tolerance(@qr.ecc_high()) == 30)
}

///|
test "tables_integrity: capacity monotonic by version" {
  // Same ECC level: higher version => strictly larger data capacity.
  let levels = [
    @qr.ecc_low(),
    @qr.ecc_medium(),
    @qr.ecc_quartile(),
    @qr.ecc_high(),
  ]
  for lev in levels {
    for ver = 1; ver < 40; ver = ver + 1 {
      let cur = @qr.num_data_codewords(ver, lev)
      let next = @qr.num_data_codewords(ver + 1, lev)
      assert_true(next > cur)
    }
  }
}

///|
test "tables_integrity: capacity ECC strength ordering" {
  // Same version: L capacity > M > Q > H (stronger ECC => less data).
  for ver = 1; ver <= 40; ver = ver + 1 {
    let l = @qr.num_data_codewords(ver, @qr.ecc_low())
    let m = @qr.num_data_codewords(ver, @qr.ecc_medium())
    let q = @qr.num_data_codewords(ver, @qr.ecc_quartile())
    let h = @qr.num_data_codewords(ver, @qr.ecc_high())
    assert_true(l > m)
    assert_true(m > q)
    assert_true(q > h)
  }
}

///|
test "tables_integrity: format bits ISO values" {
  // ISO/IEC 18004 format info 2-bit: L=01, M=00, Q=11, H=10.
  assert_true(@qr.format_bits(@qr.ecc_low()) == 1)
  assert_true(@qr.format_bits(@qr.ecc_medium()) == 0)
  assert_true(@qr.format_bits(@qr.ecc_quartile()) == 3)
  assert_true(@qr.format_bits(@qr.ecc_high()) == 2)
}

///|
test "tables_integrity: format bits in range and distinct" {
  let l = @qr.format_bits(@qr.ecc_low())
  let m = @qr.format_bits(@qr.ecc_medium())
  let q = @qr.format_bits(@qr.ecc_quartile())
  let h = @qr.format_bits(@qr.ecc_high())
  assert_true(l >= 0 && l < 4)
  assert_true(m >= 0 && m < 4)
  assert_true(q >= 0 && q < 4)
  assert_true(h >= 0 && h < 4)
  assert_true(l != m)
  assert_true(l != q)
  assert_true(l != h)
  assert_true(m != q)
  assert_true(m != h)
  assert_true(q != h)
}

///|
test "tables_integrity: from_string full names" {
  assert_true(@qr.EccLevel::from_string("Low") == @qr.ecc_low())
  assert_true(@qr.EccLevel::from_string("Medium") == @qr.ecc_medium())
  assert_true(@qr.EccLevel::from_string("Quartile") == @qr.ecc_quartile())
  assert_true(@qr.EccLevel::from_string("High") == @qr.ecc_high())
}

///|
test "tables_integrity: from_string lowercase defaults to Low" {
  // Implementation only accepts exact "L"/"Low"/etc; lowercase falls to default Low.
  assert_true(@qr.EccLevel::from_string("l") == @qr.ecc_low())
  assert_true(@qr.EccLevel::from_string("m") == @qr.ecc_low())
  assert_true(@qr.EccLevel::from_string("q") == @qr.ecc_low())
  assert_true(@qr.EccLevel::from_string("h") == @qr.ecc_low())
}

///|
test "tables_integrity: from_string invalid defaults to Low" {
  // Unknown strings fall to default Low (defensive fallback).
  assert_true(@qr.EccLevel::from_string("") == @qr.ecc_low())
  assert_true(@qr.EccLevel::from_string("X") == @qr.ecc_low())
  assert_true(@qr.EccLevel::from_string("low") == @qr.ecc_low())
  assert_true(@qr.EccLevel::from_string("XYZ") == @qr.ecc_low())
}

///|
test "tables_integrity: V1 min and V40 max capacity boundaries" {
  // V1 High is the smallest capacity in the entire table.
  let v1_h = @qr.num_data_codewords(1, @qr.ecc_high())
  assert_true(v1_h == 9)
  // V40 Low is the largest capacity in the entire table.
  let v40_l = @qr.num_data_codewords(40, @qr.ecc_low())
  assert_true(v40_l > 2900)
  // Every other combo is within [v1_h, v40_l].
  let levels = [
    @qr.ecc_low(),
    @qr.ecc_medium(),
    @qr.ecc_quartile(),
    @qr.ecc_high(),
  ]
  for lev in levels {
    for ver = 1; ver <= 40; ver = ver + 1 {
      let c = @qr.num_data_codewords(ver, lev)
      assert_true(c >= v1_h)
      assert_true(c <= v40_l)
    }
  }
}

///|
test "tables_integrity: num_data_codewords positive all 160" {
  let levels = [
    @qr.ecc_low(),
    @qr.ecc_medium(),
    @qr.ecc_quartile(),
    @qr.ecc_high(),
  ]
  for lev in levels {
    for ver = 1; ver <= 40; ver = ver + 1 {
      let c = @qr.num_data_codewords(ver, lev)
      assert_true(c > 0)
    }
  }
}

///|
test "tables_integrity: alignment pattern V1 empty" {
  let pos = @qr.alignment_pattern_positions(1)
  assert_true(pos.length() == 0)
}

///|
test "tables_integrity: alignment pattern V2 and V6" {
  // V2: [6, 18], V6: [6, 34].
  let p2 = @qr.alignment_pattern_positions(2)
  assert_true(p2.length() == 2)
  assert_true(p2[0] == 6)
  assert_true(p2[1] == 18)
  let p6 = @qr.alignment_pattern_positions(6)
  assert_true(p6.length() == 2)
  assert_true(p6[0] == 6)
  assert_true(p6[1] == 34)
}

///|
test "tables_integrity: alignment pattern V14 V20 V32 V40" {
  // V14: [6, 26, 46, 66].
  let p14 = @qr.alignment_pattern_positions(14)
  assert_true(p14.length() == 4)
  assert_true(p14[0] == 6)
  assert_true(p14[3] == 66)
  // V20: [6, 34, 62, 90].
  let p20 = @qr.alignment_pattern_positions(20)
  assert_true(p20.length() == 4)
  assert_true(p20[0] == 6)
  assert_true(p20[3] == 90)
  // V32: 6 positions, first is 6.
  let p32 = @qr.alignment_pattern_positions(32)
  assert_true(p32.length() == 6)
  assert_true(p32[0] == 6)
  // V40: 7 positions, first is 6.
  let p40 = @qr.alignment_pattern_positions(40)
  assert_true(p40.length() == 7)
  assert_true(p40[0] == 6)
}

///|
test "tables_integrity: alignment pattern first is 6 and ascending" {
  // For all versions >= 2, first position is 6 and positions are strictly ascending,
  // and the last position equals size-7 (module grid boundary).
  for ver = 2; ver <= 40; ver = ver + 1 {
    let pos = @qr.alignment_pattern_positions(ver)
    assert_true(pos.length() >= 2)
    assert_true(pos[0] == 6)
    for i = 0; i < pos.length() - 1; i = i + 1 {
      assert_true(pos[i] < pos[i + 1])
    }
    let size = ver * 4 + 17
    assert_true(pos[pos.length() - 1] == size - 7)
  }
}
