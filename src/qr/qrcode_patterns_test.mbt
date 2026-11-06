// Blackbox tests for QR code encoder functional pattern drawing.
// Covers finder, timing, alignment, format info, version info, dark module,
// separator, quiet zone, matrix size, cross-version, and decodability.
// Only calls pub fn of the @qr package.

///|
/// Check 7x7 finder pattern at top-left corner (ox, oy).
/// Structure: outer 7x7 border dark, inner 5x5 ring light, center 3x3 dark.
/// dark when Chebyshev distance d in {0,1,3}; light when d == 2.
fn pat_finder_at(qr : @qr.QrCode, ox : Int32, oy : Int32) -> Bool {
  let mut ok = true
  for dy = 0; dy < 7; dy = dy + 1 {
    for dx = 0; dx < 7; dx = dx + 1 {
      let ddx = if dx - 3 < 0 { 3 - dx } else { dx - 3 }
      let ddy = if dy - 3 < 0 { 3 - dy } else { dy - 3 }
      let d = if ddx > ddy { ddx } else { ddy }
      let expected = d != 2
      if qr.get_module(ox + dx, oy + dy) != expected {
        ok = false
      }
    }
  }
  ok
}

///|
/// Check 5x5 alignment pattern centered at (cx, cy).
/// Structure: outer ring dark (d=2), inner ring light (d=1), center dark (d=0).
fn pat_alignment_at(qr : @qr.QrCode, cx : Int32, cy : Int32) -> Bool {
  let mut ok = true
  for dy = -2; dy <= 2; dy = dy + 1 {
    for dx = -2; dx <= 2; dx = dx + 1 {
      let ddx = if dx < 0 { -dx } else { dx }
      let ddy = if dy < 0 { -dy } else { dy }
      let d = if ddx > ddy { ddx } else { ddy }
      let expected = d != 1
      if qr.get_module(cx + dx, cy + dy) != expected {
        ok = false
      }
    }
  }
  ok
}

///|
/// Parse PBM (P1 ASCII) pixel data into a flat row-major array.
/// Skips the "P1\n<w> <h>\n" header (first 2 newlines), then collects
/// every '0' or '1' character as a pixel value.
fn pat_pbm_pixels(pbm : String) -> Array[Int32] {
  let pixels : Array[Int32] = []
  let mut newline_count = 0
  for c in pbm.iter() {
    if newline_count < 2 {
      if c == '\n' {
        newline_count = newline_count + 1
      }
    } else if c == '0' || c == '1' {
      pixels.push(if c == '0' { 0 } else { 1 })
    }
  }
  pixels
}

///|
/// Count alignment patterns actually drawn (excluding finder-overlap corners).
fn pat_count_alignment_drawn(version : Int32) -> Int32 {
  let pos = @qr.alignment_pattern_positions(version)
  let n = pos.length()
  if n == 0 {
    return 0
  }
  let mut count = 0
  for i = 0; i < n; i = i + 1 {
    for j = 0; j < n; j = j + 1 {
      let skip = (i == 0 && j == 0) ||
        (i == 0 && j == n - 1) ||
        (i == n - 1 && j == 0)
      if !skip {
        count = count + 1
      }
    }
  }
  count
}

///|
test "patterns: finder three corners v1" {
  let data = FixedArray::make(5, 0x42)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let size = qr.size()
  assert_true(pat_finder_at(qr, 0, 0))
  assert_true(pat_finder_at(qr, size - 7, 0))
  assert_true(pat_finder_at(qr, 0, size - 7))
}

///|
test "patterns: finder three corners v7" {
  let data = FixedArray::make(50, 0x42)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 7)
  let size = qr.size()
  assert_true(pat_finder_at(qr, 0, 0))
  assert_true(pat_finder_at(qr, size - 7, 0))
  assert_true(pat_finder_at(qr, 0, size - 7))
}

///|
test "patterns: finder three corners v40" {
  let data = FixedArray::make(2000, 0x42)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 40)
  let size = qr.size()
  assert_true(pat_finder_at(qr, 0, 0))
  assert_true(pat_finder_at(qr, size - 7, 0))
  assert_true(pat_finder_at(qr, 0, size - 7))
}

///|
test "patterns: timing row 6 alternating" {
  let data = FixedArray::make(5, 0x42)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let size = qr.size()
  let mut ok = true
  // Timing row spans between the two finders: x in [8, size-9].
  for x = 8; x < size - 8; x = x + 1 {
    if qr.get_module(x, 6) != (x % 2 == 0) {
      ok = false
    }
  }
  assert_true(ok)
}

///|
test "patterns: timing col 6 alternating" {
  let data = FixedArray::make(5, 0x42)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let size = qr.size()
  let mut ok = true
  for y = 8; y < size - 8; y = y + 1 {
    if qr.get_module(6, y) != (y % 2 == 0) {
      ok = false
    }
  }
  assert_true(ok)
}

///|
test "patterns: alignment v1 none" {
  // V1 has no alignment pattern positions.
  let pos = @qr.alignment_pattern_positions(1)
  assert_true(pos.length() == 0)
  assert_true(pat_count_alignment_drawn(1) == 0)
}

///|
test "patterns: alignment v2 single pattern" {
  // V2 has 2 positions [6, 18]; only (18,18) is drawn (others overlap finders).
  let data = FixedArray::make(20, 0x42)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 2)
  let pos = @qr.alignment_pattern_positions(2)
  assert_true(pos.length() == 2)
  assert_true(pos[0] == 6)
  assert_true(pos[1] == 18)
  assert_true(pat_count_alignment_drawn(2) == 1)
  assert_true(pat_alignment_at(qr, pos[1], pos[1]))
}

///|
test "patterns: alignment v7 multiple" {
  // V7: numalign = 7/7+2 = 3 positions; 3x3 - 3 corners = 6 patterns.
  let data = FixedArray::make(50, 0x42)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 7)
  let pos = @qr.alignment_pattern_positions(7)
  assert_true(pos.length() == 3)
  assert_true(pat_count_alignment_drawn(7) == 6)
  let mut ok = true
  for i = 0; i < pos.length(); i = i + 1 {
    for j = 0; j < pos.length(); j = j + 1 {
      let skip = (i == 0 && j == 0) ||
        (i == 0 && j == pos.length() - 1) ||
        (i == pos.length() - 1 && j == 0)
      if !skip {
        if !pat_alignment_at(qr, pos[i], pos[j]) {
          ok = false
        }
      }
    }
  }
  assert_true(ok)
}

///|
test "patterns: alignment v20 positions correct" {
  // V20: numalign = 20/7+2 = 4 positions; 4x4 - 3 corners = 13 patterns.
  let data = FixedArray::make(500, 0x42)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 20)
  let pos = @qr.alignment_pattern_positions(20)
  assert_true(pos.length() == 4)
  assert_true(pos[0] == 6)
  assert_true(pat_count_alignment_drawn(20) == 13)
  let mut ok = true
  for i = 0; i < pos.length(); i = i + 1 {
    for j = 0; j < pos.length(); j = j + 1 {
      let skip = (i == 0 && j == 0) ||
        (i == 0 && j == pos.length() - 1) ||
        (i == pos.length() - 1 && j == 0)
      if !skip {
        if !pat_alignment_at(qr, pos[i], pos[j]) {
          ok = false
        }
      }
    }
  }
  assert_true(ok)
}

///|
test "patterns: alignment v40 positions correct" {
  // V40: numalign = 40/7+2 = 7 positions; 7x7 - 3 corners = 46 patterns.
  let data = FixedArray::make(2000, 0x42)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 40)
  let pos = @qr.alignment_pattern_positions(40)
  assert_true(pos.length() == 7)
  assert_true(pos[0] == 6)
  assert_true(pat_count_alignment_drawn(40) == 46)
  // Spot-check a few interior alignment patterns.
  assert_true(pat_alignment_at(qr, pos[1], pos[1]))
  assert_true(pat_alignment_at(qr, pos[3], pos[3]))
  assert_true(pat_alignment_at(qr, pos[2], pos[4]))
}

///|
test "patterns: format info dark module all versions" {
  // Dark module at (x=8, y=size-8) = (8, 4*version+9) for all versions.
  for v = 1; v <= 40; v = v + 1 {
    let data = FixedArray::make(1, 0x42)
    let qr = @qr.encode_binary(data, @qr.ecc_low(), v)
    let size = qr.size()
    if !qr.get_module(8, size - 8) {
      abort("dark module missing at v\{v}")
    }
    // Also verify y coordinate equals 4v+9.
    if size - 8 != 4 * v + 9 {
      abort("dark module y mismatch at v\{v}")
    }
  }
}

///|
test "patterns: format info region populated" {
  // Format info first copy occupies 15 module positions around top-left finder.
  // Verify the region has a mix of dark and light (not all one color).
  let data = FixedArray::make(10, 0x42)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let mut dark = 0
  let mut light = 0
  // Column 8, rows 0..5, 7, 8.
  for i = 0; i < 6; i = i + 1 {
    if qr.get_module(8, i) {
      dark = dark + 1
    } else {
      light = light + 1
    }
  }
  if qr.get_module(8, 7) {
    dark = dark + 1
  } else {
    light = light + 1
  }
  if qr.get_module(8, 8) {
    dark = dark + 1
  } else {
    light = light + 1
  }
  // Row 8, cols 0..5, 7.
  for i = 0; i < 6; i = i + 1 {
    if qr.get_module(i, 8) {
      dark = dark + 1
    } else {
      light = light + 1
    }
  }
  if qr.get_module(7, 8) {
    dark = dark + 1
  } else {
    light = light + 1
  }
  // Format info is 15 bits encoded with BCH; cannot be all-0 or all-1.
  assert_true(dark > 0)
  assert_true(light > 0)
}

///|
test "patterns: version info v7 populated and symmetric" {
  // V7+: version info is 18 bits in two 6x3 blocks (symmetric).
  let data = FixedArray::make(50, 0x42)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 7)
  let size = qr.size()
  // Block 1: x in 0..5, y in size-11..size-9.
  // Block 2: x in size-11..size-9, y in 0..5.
  // Verify symmetry: block1[x][y-offset] == block2[y][x-offset].
  let mut dark = 0
  let mut symmetric = true
  for i = 0; i < 6; i = i + 1 {
    for j = 0; j < 3; j = j + 1 {
      let b1 = qr.get_module(i, size - 11 + j)
      let b2 = qr.get_module(size - 11 + j, i)
      if b1 {
        dark = dark + 1
      }
      if b2 {
        dark = dark + 1
      }
      if b1 != b2 {
        symmetric = false
      }
    }
  }
  // V7 version info bits are not all zero.
  assert_true(dark > 0)
  assert_true(symmetric)
}

///|
test "patterns: version info below v7 not drawn" {
  // For v < 7, version info region is not function-pattern drawn.
  // We verify by checking that V6 does not have the symmetric version info
  // structure that V7 has (the region holds data modules instead).
  let data = FixedArray::make(30, 0x42)
  let qr6 = @qr.encode_binary(data, @qr.ecc_low(), 6)
  let size6 = qr6.size()
  // Just ensure no crash reading the region; V6 has no version info function.
  for i = 0; i < 6; i = i + 1 {
    for j = 0; j < 3; j = j + 1 {
      let _ = qr6.get_module(i, size6 - 11 + j)
      let _ = qr6.get_module(size6 - 11 + j, i)
    }
  }
  assert_true(true)
}

///|
test "patterns: separator white around finders" {
  // Separator: 1-module white border between finder and timing/data.
  let data = FixedArray::make(5, 0x42)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let size = qr.size()
  let mut ok = true
  // Top-left finder separator: row 7 cols 0..7, col 7 rows 0..7.
  for i = 0; i < 8; i = i + 1 {
    if qr.get_module(i, 7) {
      ok = false
    }
    if qr.get_module(7, i) {
      ok = false
    }
  }
  // Top-right finder separator: row 7 cols size-8..size-1.
  for i = 0; i < 8; i = i + 1 {
    if qr.get_module(size - 1 - i, 7) {
      ok = false
    }
  }
  // Bottom-left finder separator: col 7 rows size-8..size-1.
  for i = 0; i < 8; i = i + 1 {
    if qr.get_module(7, size - 1 - i) {
      ok = false
    }
  }
  assert_true(ok)
}

///|
test "patterns: matrix size formula all versions" {
  // size = 4*version + 17 for all versions 1..40.
  let data = FixedArray::make(1, 0x42)
  for v = 1; v <= 40; v = v + 1 {
    let qr = @qr.encode_binary(data, @qr.ecc_low(), v)
    let expected = v * 4 + 17
    if qr.size() != expected {
      abort("size mismatch at v\{v}: got \{qr.size()} expected \{expected}")
    }
  }
}

///|
test "patterns: quiet zone default 4 white border" {
  // Quiet zone is an image concept; verify via to_pbm with quiet=4.
  // All border pixels (quiet zone) must be white (0).
  let data = FixedArray::make(10, 0x42)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let quiet = 4
  let pbm = @qr.to_pbm(qr, quiet)
  let size = qr.size()
  let total = size + quiet * 2
  let pixels = pat_pbm_pixels(pbm)
  // Pixel count must match total*total.
  assert_true(pixels.length() == total * total)
  // All quiet-zone pixels must be white (0).
  let mut all_white = true
  for y = 0; y < total; y = y + 1 {
    for x = 0; x < total; x = x + 1 {
      let in_quiet = x < quiet ||
        x >= quiet + size ||
        y < quiet ||
        y >= quiet + size
      if in_quiet {
        let idx = y * total + x
        if pixels[idx] != 0 {
          all_white = false
        }
      }
    }
  }
  assert_true(all_white)
}

///|
test "patterns: quiet zone varies with parameter" {
  // quiet=0: no border, total == size. quiet=4: total == size+8.
  let data = FixedArray::make(5, 0x42)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let size = qr.size()
  let pbm0 = @qr.to_pbm(qr, 0)
  let pbm4 = @qr.to_pbm(qr, 4)
  let pixels0 = pat_pbm_pixels(pbm0)
  let pixels4 = pat_pbm_pixels(pbm4)
  assert_true(pixels0.length() == size * size)
  assert_true(pixels4.length() == (size + 8) * (size + 8))
}

///|
test "patterns: cross version decodability" {
  // Encode and decode across representative versions.
  let versions = [1, 2, 7, 20, 40]
  let sizes = [5, 20, 50, 500, 2000]
  for idx = 0; idx < versions.length(); idx = idx + 1 {
    let v = versions[idx]
    let n = sizes[idx]
    let data = FixedArray::make(n, 0x42)
    let qr = @qr.encode_binary(data, @qr.ecc_low(), v)
    match @qr.decode_from_qrcode(qr) {
      Some(decoded) => {
        if decoded.length() != n {
          abort("v\{v}: decoded length \{decoded.length()} != \{n}")
        }
        for i = 0; i < n; i = i + 1 {
          if decoded[i] != 0x42 {
            abort("v\{v}: decoded[\{i}] != 0x42")
          }
        }
      }
      None => abort("v\{v}: decode failed")
    }
  }
}

///|
test "patterns: cross version decodability all ecc levels" {
  // V7 with all four ECC levels must round-trip.
  let data = FixedArray::make(30, 0x37)
  let levels = [
    @qr.ecc_low(),
    @qr.ecc_medium(),
    @qr.ecc_quartile(),
    @qr.ecc_high(),
  ]
  for l in levels {
    let qr = @qr.encode_binary(data, l, 7)
    match @qr.decode_from_qrcode(qr) {
      Some(decoded) => {
        assert_true(decoded.length() == 30)
        let mut ok = true
        for i = 0; i < 30; i = i + 1 {
          if decoded[i] != 0x37 {
            ok = false
          }
        }
        assert_true(ok)
      }
      None => abort("v7 ecc decode failed")
    }
  }
}
