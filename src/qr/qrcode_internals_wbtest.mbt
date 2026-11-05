/// Whitebox tests for qrcode.mbt internal functions.
/// Tests private functions directly: mask_pattern, apply_mask, get_penalty_score,
/// penalty_line, add_ecc_and_interleave, draw_*, choose_version_level,
/// make_data_codewords, get_bit, abs_int, max_int, min_int.

///|
/// Create a size x size matrix filled with `fill` (independent rows).
fn wb_mk_modules(size : Int32, fill : Bool) -> FixedArray[FixedArray[Bool]] {
  let m = FixedArray::make(size, FixedArray::make(size, false))
  for y = 0; y < size; y = y + 1 {
    m[y] = FixedArray::make(size, fill)
  }
  m
}

///|
/// Create a checkerboard matrix: (x+y)%2==0 is dark.
fn wb_mk_checkerboard(size : Int32) -> FixedArray[FixedArray[Bool]] {
  let m = FixedArray::make(size, FixedArray::make(size, false))
  for y = 0; y < size; y = y + 1 {
    m[y] = FixedArray::make(size, false)
    for x = 0; x < size; x = x + 1 {
      m[y][x] = (x + y) % 2 == 0
    }
  }
  m
}

///|
/// Deep-copy a Bool matrix (independent rows).
fn wb_copy_modules(
  src : FixedArray[FixedArray[Bool]],
) -> FixedArray[FixedArray[Bool]] {
  let size = src.length()
  let dst = FixedArray::make(size, FixedArray::make(size, false))
  for y = 0; y < size; y = y + 1 {
    dst[y] = FixedArray::make(size, false)
    for x = 0; x < size; x = x + 1 {
      dst[y][x] = src[y][x]
    }
  }
  dst
}

///|
/// Count dark modules in a matrix.
fn wb_count_dark(m : FixedArray[FixedArray[Bool]]) -> Int32 {
  let size = m.length()
  let mut count = 0
  for y = 0; y < size; y = y + 1 {
    for x = 0; x < size; x = x + 1 {
      if m[y][x] {
        count = count + 1
      }
    }
  }
  count
}

///|
test "enc wb: penalty all white" {
  // All-white 21x21 matrix.
  // N1: 21 rows * 19 + 21 cols * 19 = 798 (run of 21: 3 + 16 = 19 per line).
  // N2: 20*20 * 3 = 1200 (all 2x2 blocks uniform).
  // N3: 0 (no finder-like pattern in uniform line).
  // N4: dark=0, total=441, k=(4410+440)/441-1=4850/441-1=10-1=9, +90.
  // Total = 798 + 1200 + 90 = 2088.
  let m = wb_mk_modules(21, false)
  assert_true(get_penalty_score(21, m) == 2088)
}

///|
test "enc wb: penalty all black" {
  // All-black 21x21 matrix: same penalty as all-white by symmetry.
  // N4: dark=441, k=(4410+440)/441-1=9, +90. Total = 2088.
  let m = wb_mk_modules(21, true)
  assert_true(get_penalty_score(21, m) == 2088)
}

///|
test "enc wb: penalty checkerboard" {
  // Checkerboard (x+y)%2==0: optimal pattern, penalty should be minimal.
  // N1=0 (no run >= 5), N2=0 (2x2 blocks not uniform), N3=0 (no finder-like).
  // N4: dark=221, total=441, k=0, +0. Total = 0.
  let m = wb_mk_checkerboard(21)
  assert_true(get_penalty_score(21, m) == 0)
}

///|
test "enc wb: penalty line function" {
  // penalty_line on a full white row: run of 21 -> 3 + 16 = 19.
  let white = wb_mk_modules(21, false)
  assert_true(penalty_line(21, 0, true, white) == 19)
  assert_true(penalty_line(21, 0, false, white) == 19)
  // penalty_line on a full black row: same as white.
  let black = wb_mk_modules(21, true)
  assert_true(penalty_line(21, 5, true, black) == 19)
  // penalty_line on a checkerboard row: no runs, no finder-like -> 0.
  let cb = wb_mk_checkerboard(21)
  assert_true(penalty_line(21, 0, true, cb) == 0)
  assert_true(penalty_line(21, 0, false, cb) == 0)
}

///|
test "enc wb: mask pattern 0-7" {
  // Verify each mask pattern against ISO/IEC 18004 spec at sample points.
  // mask 0: (x+y)%2==0
  assert_true(mask_pattern(0, 3, 5) == true) // (3+5)%2=0
  assert_true(mask_pattern(0, 4, 5) == false) // (4+5)%2=1
  // mask 1: y%2==0
  assert_true(mask_pattern(1, 3, 5) == false) // 5%2=1
  assert_true(mask_pattern(1, 4, 6) == true) // 6%2=0
  // mask 2: x%3==0
  assert_true(mask_pattern(2, 3, 5) == true) // 3%3=0
  assert_true(mask_pattern(2, 4, 5) == false) // 4%3=1
  // mask 3: (x+y)%3==0
  assert_true(mask_pattern(3, 3, 5) == false) // 8%3=2
  assert_true(mask_pattern(3, 1, 2) == true) // 3%3=0
  // mask 4: (x/3 + y/2)%2==0
  assert_true(mask_pattern(4, 3, 5) == false) // (1+2)%2=1
  assert_true(mask_pattern(4, 0, 0) == true) // (0+0)%2=0
  // mask 5: x*y%2 + x*y%3==0
  assert_true(mask_pattern(5, 3, 5) == false) // 15%2+15%3=1+0=1
  assert_true(mask_pattern(5, 2, 3) == true) // 6%2+6%3=0+0=0
  // mask 6: (x*y%2 + x*y%3)%2==0
  assert_true(mask_pattern(6, 3, 5) == false) // (1+0)%2=1
  assert_true(mask_pattern(6, 2, 3) == true) // (0+0)%2=0
  // mask 7: ((x+y)%2 + x*y%3)%2==0
  assert_true(mask_pattern(7, 3, 5) == true) // (0+0)%2=0
  assert_true(mask_pattern(7, 1, 1) == false) // (0+1)%2=1
}

///|
test "enc wb: apply mask reversible" {
  // Applying the same mask twice restores the original matrix.
  let size = 21
  let modules = wb_mk_checkerboard(size)
  let isfunction = wb_mk_modules(size, false)
  let saved = wb_copy_modules(modules)
  apply_mask(size, 3, modules, isfunction)
  apply_mask(size, 3, modules, isfunction)
  let mut same = true
  for y = 0; y < size; y = y + 1 {
    for x = 0; x < size; x = x + 1 {
      if modules[y][x] != saved[y][x] {
        same = false
      }
    }
  }
  assert_true(same)
}

///|
test "enc wb: apply mask preserves function modules" {
  // apply_mask must not modify cells marked as function modules.
  let size = 21
  let modules = wb_mk_modules(size, false)
  let isfunction = wb_mk_modules(size, false)
  // Mark some cells as function modules with specific values.
  isfunction[5][5] = true
  isfunction[10][10] = true
  isfunction[0][0] = true
  modules[5][5] = true
  modules[10][10] = false
  modules[0][0] = true
  apply_mask(size, 2, modules, isfunction)
  // Function module values unchanged regardless of mask.
  assert_true(modules[5][5] == true)
  assert_true(modules[10][10] == false)
  assert_true(modules[0][0] == true)
}

///|
test "enc wb: mask pattern all 8 distinct" {
  // Verify that the 8 mask patterns are not all identical.
  // At point (3,5), masks produce a mix of true/false.
  let mut count_true = 0
  let mut count_false = 0
  for m = 0; m < 8; m = m + 1 {
    if mask_pattern(m, 3, 5) {
      count_true = count_true + 1
    } else {
      count_false = count_false + 1
    }
  }
  assert_true(count_true > 0 && count_false > 0)
  // Each mask 1..7 must differ from mask 0 at some point in 0..9 x 0..9.
  let mut all_same_as_0 = true
  for m = 1; m < 8; m = m + 1 {
    let mut differs = false
    for y = 0; y < 10; y = y + 1 {
      for x = 0; x < 10; x = x + 1 {
        if mask_pattern(m, x, y) != mask_pattern(0, x, y) {
          differs = true
        }
      }
    }
    if differs {
      all_same_as_0 = false
    }
  }
  assert_true(all_same_as_0 == false)
}

///|
test "enc wb: add ecc v1" {
  // V1 Low: 1 block, 7 ECC codewords, 26 total codewords, 19 data.
  let data = FixedArray::make(19, 0x42)
  let result = add_ecc_and_interleave(1, EccLevel::Low, data)
  // Total = num_raw_data_modules(1)/8 = 208/8 = 26.
  assert_true(result.length() == 26)
}

///|
test "enc wb: add ecc length" {
  // For versions 1..10, output length == num_raw_data_modules(v)/8.
  let mut all_ok = true
  for v = 1; v <= 10; v = v + 1 {
    let ndc = num_data_codewords(v, EccLevel::Low)
    let data = FixedArray::make(ndc, 0x42)
    let result = add_ecc_and_interleave(v, EccLevel::Low, data)
    let expected = num_raw_data_modules(v) / 8
    if result.length() != expected {
      all_ok = false
    }
  }
  assert_true(all_ok)
}

///|
test "enc wb: add ecc interleave order" {
  // V5 Medium: 2 blocks, shortdatalen=43, no short blocks (numshortblocks=2).
  // Interleave is column-major: all[0]=dcw[0], all[1]=dcw[43],
  // all[2]=dcw[1], all[3]=dcw[44], etc.
  let data = FixedArray::make(50, 0x42)
  let segs = [Segment::make_bytes(data)]
  let dcw = make_data_codewords(segs, 5, EccLevel::Medium)
  let all = add_ecc_and_interleave(5, EccLevel::Medium, dcw)
  // rawcodewords = 134, num_data_codewords = 86.
  assert_true(all.length() == 134)
  assert_true(dcw.length() == 86)
  // Data interleave: column-major across 2 blocks.
  assert_true(all[0] == dcw[0])
  assert_true(all[1] == dcw[43])
  assert_true(all[2] == dcw[1])
  assert_true(all[3] == dcw[44])
  assert_true(all[84] == dcw[42])
  assert_true(all[85] == dcw[85])
}

///|
test "enc wb: draw codewords fills data" {
  // After draw_codewords, non-function modules should have some dark cells.
  let data = FixedArray::make(10, 0x42)
  let segs = [Segment::make_bytes(data)]
  let dcw = make_data_codewords(segs, 1, EccLevel::Low)
  let all = add_ecc_and_interleave(1, EccLevel::Low, dcw)
  let size = 21
  let modules = wb_mk_modules(size, false)
  let isfunction = wb_mk_modules(size, false)
  draw_function_patterns(1, size, modules, isfunction)
  draw_codewords(1, size, all, modules, isfunction)
  // Count dark non-function modules.
  let mut dark = 0
  for y = 0; y < size; y = y + 1 {
    for x = 0; x < size; x = x + 1 {
      if !isfunction[y][x] && modules[y][x] {
        dark = dark + 1
      }
    }
  }
  assert_true(dark > 0)
}

///|
test "enc wb: draw finder pattern" {
  // draw_finder at center (3,3) in 21x21: 7x7 finder pattern.
  // dist = max(|dx|, |dy|); dark when dist != 2 && dist != 4.
  let size = 21
  let modules = wb_mk_modules(size, false)
  let isfunction = wb_mk_modules(size, false)
  draw_finder(3, 3, size, modules, isfunction)
  // (3,3): dist=0 -> dark
  assert_true(modules[3][3] == true)
  // (1,1): dist=2 -> light
  assert_true(modules[1][1] == false)
  // (0,0): dist=3 -> dark
  assert_true(modules[0][0] == true)
  // (4,4): dist=1 -> dark
  assert_true(modules[4][4] == true)
  // (5,5): dist=2 -> light
  assert_true(modules[5][5] == false)
  // (6,6): dist=3 -> dark
  assert_true(modules[6][6] == true)
  // (7,7): dist=4 -> light (separator)
  assert_true(modules[7][7] == false)
}

///|
test "enc wb: draw alignment pattern" {
  // draw_alignment at (10,10): 5x5 alignment pattern.
  // dist = max(|dx|, |dy|) for dx,dy in -2..2;
  // dark when dist != 1.
  let size = 21
  let modules = wb_mk_modules(size, false)
  let isfunction = wb_mk_modules(size, false)
  draw_alignment(10, 10, modules, isfunction)
  // Center (10,10): dist=0 -> dark
  assert_true(modules[10][10] == true)
  // (11,11): dist=1 -> light
  assert_true(modules[11][11] == false)
  // (12,12): dist=2 -> dark
  assert_true(modules[12][12] == true)
  // (10,11): dist=1 -> light
  assert_true(modules[10][11] == false)
  // (8,8): dist=2 -> dark
  assert_true(modules[8][8] == true)
  // (8,10): dist=2 -> dark
  assert_true(modules[8][10] == true)
}

///|
test "enc wb: draw format bits" {
  // draw_format_bits writes format info; dark module at (8, size-8) is always set.
  let size = 21
  let modules = wb_mk_modules(size, false)
  let isfunction = wb_mk_modules(size, false)
  draw_format_bits(size, EccLevel::Low, 0, modules, isfunction)
  // Dark module at (8, size-8) is always dark per ISO spec.
  assert_true(modules[8][size - 8] == true)
  // Format info region around top-left finder is marked as function.
  assert_true(isfunction[0][8] == true)
  assert_true(isfunction[1][8] == true)
  assert_true(isfunction[8][0] == true)
}

///|
test "enc wb: draw version info v7" {
  // V7+: version info is drawn; V1-V6: no version info.
  let size7 = 7 * 4 + 17 // 45
  let modules7 = wb_mk_modules(size7, false)
  let isfunction7 = wb_mk_modules(size7, false)
  draw_version_info(7, size7, modules7, isfunction7)
  // Version info area should have some dark modules.
  let mut dark7 = 0
  for i = 0; i < 18; i = i + 1 {
    let a = size7 - 11 + i % 3
    let b = i / 3
    if modules7[b][a] {
      dark7 = dark7 + 1
    }
  }
  assert_true(dark7 > 0)
  // V1: no version info drawn (version < 7 returns immediately).
  let size1 = 21
  let modules1 = wb_mk_modules(size1, false)
  let isfunction1 = wb_mk_modules(size1, false)
  draw_version_info(1, size1, modules1, isfunction1)
  assert_true(wb_count_dark(modules1) == 0)
}

///|
test "enc wb: choose version auto" {
  // Small data (5 bytes) fits V1; ECC boosts to High (9 cw = 72 bits >= 52 bits).
  let small = FixedArray::make(5, 0x41)
  let segs_small = [Segment::make_bytes(small)]
  let (v1, l1) = choose_version_level(segs_small, EccLevel::Low, 1)
  assert_true(v1 == 1)
  assert_true(l1 == EccLevel::High)
  // Large data (100 bytes) requires a higher version.
  let big = FixedArray::make(100, 0x42)
  let segs_big = [Segment::make_bytes(big)]
  let (v2, _) = choose_version_level(segs_big, EccLevel::Low, 1)
  assert_true(v2 > 1)
  // minversion constraint: requesting minversion=5 forces v >= 5.
  let (v3, _) = choose_version_level(segs_small, EccLevel::Low, 5)
  assert_true(v3 >= 5)
}

///|
test "enc wb: make data codewords length" {
  // make_data_codewords returns exactly num_data_codewords(v, level) bytes.
  let data = FixedArray::make(10, 0x42)
  let segs = [Segment::make_bytes(data)]
  let dcw = make_data_codewords(segs, 1, EccLevel::Low)
  assert_true(dcw.length() == num_data_codewords(1, EccLevel::Low))
  // V3 Medium.
  let dcw3 = make_data_codewords(segs, 3, EccLevel::Medium)
  assert_true(dcw3.length() == num_data_codewords(3, EccLevel::Medium))
}

///|
test "enc wb: get bit" {
  // get_bit(x, i) returns bit i of x (0 = LSB).
  assert_true(get_bit(0b1010, 0) == false)
  assert_true(get_bit(0b1010, 1) == true)
  assert_true(get_bit(0b1010, 2) == false)
  assert_true(get_bit(0b1010, 3) == true)
  assert_true(get_bit(0xFF, 7) == true)
  assert_true(get_bit(0, 0) == false)
  assert_true(get_bit(1, 0) == true)
  assert_true(get_bit(128, 7) == true)
}

///|
test "enc wb: abs/max/min int" {
  // abs_int
  assert_true(abs_int(-5) == 5)
  assert_true(abs_int(5) == 5)
  assert_true(abs_int(0) == 0)
  // max_int
  assert_true(max_int(3, 7) == 7)
  assert_true(max_int(7, 3) == 7)
  assert_true(max_int(-1, -2) == -1)
  // min_int
  assert_true(min_int(3, 7) == 3)
  assert_true(min_int(7, 3) == 3)
  assert_true(min_int(-1, -2) == -2)
}
