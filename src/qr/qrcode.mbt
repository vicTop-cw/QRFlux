/// QR Code Model 2 encoder core.
/// Self-implemented from ISO/IEC 18004 algorithm description.

///|
/// Number of raw data modules (including remainder bits) for a version.
pub fn num_raw_data_modules(ver : Int32) -> Int32 {
  let mut result = (16 * ver + 128) * ver + 64
  if ver >= 2 {
    let numalign = ver / 7 + 2
    result = result - (25 * numalign - 10) * numalign + 55
    if ver >= 7 {
      result = result - 36
    }
  }
  result
}

///|
/// Number of data codewords (8-bit, excluding ECC) for version+level.
pub fn num_data_codewords(ver : Int32, level : EccLevel) -> Int32 {
  num_raw_data_modules(ver) / 8 -
  ecc_codewords_per_block(level, ver) * num_ecc_blocks(level, ver)
}

///|
/// Total bits needed for given segments at a version.
pub fn total_bits(segs : Array[Segment], version : Int32) -> Int32 {
  let mut result = 0
  for seg in segs {
    let ccbits = char_count_bits(seg.mode(), version)
    if seg.num_chars() >= 1 << ccbits {
      return -1 // does not fit
    }
    result = result + 4 + ccbits + seg.data().length()
  }
  result
}

///|
pub struct QrCode {
  version : Int32
  size : Int32
  level : EccLevel
  mask : Int32
  modules : FixedArray[FixedArray[Bool]]
}

///|
pub fn QrCode::version(self : QrCode) -> Int32 {
  self.version
}

///|
pub fn QrCode::size(self : QrCode) -> Int32 {
  self.size
}

///|
pub fn QrCode::level(self : QrCode) -> EccLevel {
  self.level
}

///|
pub fn QrCode::mask(self : QrCode) -> Int32 {
  self.mask
}

///|
pub fn QrCode::get_module(self : QrCode, x : Int32, y : Int32) -> Bool {
  if x < 0 || x >= self.size || y < 0 || y >= self.size {
    return false
  }
  self.modules[y][x]
}

///|
/// Encode binary data (byte mode) into a QR Code with smallest version in
/// [minversion, 40] and given ECC level; boosts ECC when possible without
/// changing version; auto-picks best mask.
pub fn encode_binary(
  data : FixedArray[Int32],
  level : EccLevel,
  minversion : Int32,
) -> QrCode {
  let segs = [Segment::make_bytes(data)]
  encode_segments(segs, level, minversion)
}

///|
pub fn encode_segments(
  segs : Array[Segment],
  ecl : EccLevel,
  minversion : Int32,
) -> QrCode {
  let (version, level) = choose_version_level(segs, ecl, minversion)
  let datacodewords = make_data_codewords(segs, version, level)
  build_qr(version, level, datacodewords)
}

///|
/// Pick smallest fitting version, then boost ECC level if capacity allows.
fn choose_version_level(
  segs : Array[Segment],
  ecl : EccLevel,
  minversion : Int32,
) -> (Int32, EccLevel) {
  let mut version = minversion
  let mut found = false
  let mut datausedbits = 0
  while version <= 40 {
    datausedbits = total_bits(segs, version)
    if datausedbits >= 0 && datausedbits <= num_data_codewords(version, ecl) * 8 {
      found = true
      break
    }
    version = version + 1
  }
  if !found {
    abort("QR data too long for any version")
  }
  let mut level = ecl
  let candidates = [EccLevel::Medium, EccLevel::Quartile, EccLevel::High]
  for newecl in candidates {
    if datausedbits <= num_data_codewords(version, newecl) * 8 {
      level = newecl
    }
  }
  (version, level)
}

///|
/// Concatenate segments, append terminator/padding, return data codewords.
fn make_data_codewords(
  segs : Array[Segment],
  version : Int32,
  level : EccLevel,
) -> FixedArray[Int32] {
  let bb = BitBuffer::new()
  for seg in segs {
    bb.append_bits(mode_bits(seg.mode()), 4)
    bb.append_bits(seg.num_chars(), char_count_bits(seg.mode(), version))
    for i = 0; i < seg.data().length(); i = i + 1 {
      bb.append_bits(seg.data().bit_at(i), 1)
    }
  }
  let capacity = num_data_codewords(version, level) * 8
  let term = min_int(4, capacity - bb.length())
  if term > 0 {
    bb.append_bits(0, term)
  }
  bb.append_bits(0, (8 - bb.length() % 8) % 8)
  let mut padbyte = 0xEC
  while bb.length() < capacity {
    bb.append_bits(padbyte, 8)
    padbyte = if padbyte == 0xEC { 0x11 } else { 0xEC }
  }
  bb.to_bytes()
}

///|
/// Debug helper: expose raw data codewords and interleaved ECC codewords.
pub fn debug_codewords(
  data : FixedArray[Int32],
  ecl : EccLevel,
  minversion : Int32,
) -> (FixedArray[Int32], FixedArray[Int32]) {
  let segs = [Segment::make_bytes(data)]
  let (version, level) = choose_version_level(segs, ecl, minversion)
  let datacodewords = make_data_codewords(segs, version, level)
  let all = add_ecc_and_interleave(version, level, datacodewords)
  (datacodewords, all)
}

///|
/// Add ECC, interleave blocks, draw modules, choose best mask.
fn build_qr(
  version : Int32,
  level : EccLevel,
  datacodewords : FixedArray[Int32],
) -> QrCode {
  let size = version * 4 + 17
  let modules = FixedArray::make(size, FixedArray::make(size, false))
  let isfunction = FixedArray::make(size, FixedArray::make(size, false))
  for i = 0; i < size; i = i + 1 {
    modules[i] = FixedArray::make(size, false)
    isfunction[i] = FixedArray::make(size, false)
  }

  draw_function_patterns(version, size, modules, isfunction)

  let allcodewords = add_ecc_and_interleave(version, level, datacodewords)
  draw_codewords(version, size, allcodewords, modules, isfunction)

  // Choose best mask (0..7), draw format bits after masking.
  let mut bestmask = 0
  let mut bestpenalty = 1 << 31
  for mask = 0; mask < 8; mask = mask + 1 {
    apply_mask(size, mask, modules, isfunction)
    draw_format_bits(size, level, mask, modules, isfunction)
    let penalty = get_penalty_score(size, modules)
    if penalty < bestpenalty {
      bestpenalty = penalty
      bestmask = mask
    }
    apply_mask(size, mask, modules, isfunction) // undo
  }
  apply_mask(size, bestmask, modules, isfunction)
  draw_format_bits(size, level, bestmask, modules, isfunction)

  { version, size, level, mask: bestmask, modules, }
}

///|
/// Split data into blocks, append RS ECC per block, interleave.
fn add_ecc_and_interleave(
  version : Int32,
  level : EccLevel,
  data : FixedArray[Int32],
) -> FixedArray[Int32] {
  let numblocks = num_ecc_blocks(level, version)
  let blockecclen = ecc_codewords_per_block(level, version)
  let rawcodewords = num_raw_data_modules(version) / 8
  let numshortblocks = numblocks - rawcodewords % numblocks
  let shortblocklen = rawcodewords / numblocks
  // Short block data length (long blocks have one extra data codeword).
  let shortdatalen = shortblocklen - blockecclen

  let rsdiv = rs_compute_divisor(blockecclen)

  // Split data into blocks and compute ECC for each block separately.
  let datblocks : Array[FixedArray[Int32]] = []
  let eccblocks : Array[FixedArray[Int32]] = []
  let mut k = 0
  for i = 0; i < numblocks; i = i + 1 {
    let dlen = shortdatalen + (if i < numshortblocks { 0 } else { 1 })
    let dat = FixedArray::make(dlen, 0)
    for j = 0; j < dlen; j = j + 1 {
      dat[j] = data[k + j]
    }
    k = k + dlen
    let ecc = rs_compute_remainder(dat, rsdiv)
    datblocks.push(dat)
    eccblocks.push(ecc)
  }

  // Interleave per ISO/IEC 18004 8.5.3: data codewords first (column-major,
  // skipping short blocks at the extra column), then ECC codewords (column-major
  // across all blocks). The previous implementation concatenated data+ecc per
  // block and interleaved the concatenation, which dropped the long blocks'
  // extra data codeword and mis-ordered ECC when numshortblocks < numblocks.
  let result = FixedArray::make(rawcodewords, 0)
  let mut idx = 0
  // Data: columns 0..shortdatalen-1, all blocks.
  for i = 0; i < shortdatalen; i = i + 1 {
    for j = 0; j < numblocks; j = j + 1 {
      result[idx] = datblocks[j][i]
      idx = idx + 1
    }
  }
  // Data: column shortdatalen, only long blocks (short blocks have no extra).
  for j = numshortblocks; j < numblocks; j = j + 1 {
    result[idx] = datblocks[j][shortdatalen]
    idx = idx + 1
  }
  // ECC: all columns, all blocks (every block has blockecclen ECC codewords).
  for i = 0; i < blockecclen; i = i + 1 {
    for j = 0; j < numblocks; j = j + 1 {
      result[idx] = eccblocks[j][i]
      idx = idx + 1
    }
  }
  result
}

///|
/// Draw timing, finder, alignment, format, version function modules.
fn draw_function_patterns(
  version : Int32,
  size : Int32,
  modules : FixedArray[FixedArray[Bool]],
  isfunction : FixedArray[FixedArray[Bool]],
) -> Unit {
  // Timing patterns.
  for i = 0; i < size; i = i + 1 {
    set_function(6, i, i % 2 == 0, modules, isfunction)
    set_function(i, 6, i % 2 == 0, modules, isfunction)
  }
  // Finder patterns + separators (9x9 each).
  draw_finder(3, 3, size, modules, isfunction)
  draw_finder(size - 4, 3, size, modules, isfunction)
  draw_finder(3, size - 4, size, modules, isfunction)
  // Alignment patterns.
  let alignpos = alignment_pattern_positions(version)
  let numalign = alignpos.length()
  for i = 0; i < numalign; i = i + 1 {
    for j = 0; j < numalign; j = j + 1 {
      // Skip the three corners covered by finders.
      let skip = (i == 0 && j == 0) ||
        (i == 0 && j == numalign - 1) ||
        (i == numalign - 1 && j == 0)
      if !skip {
        draw_alignment(alignpos[i], alignpos[j], modules, isfunction)
      }
    }
  }
  // Format bits dummy (overwritten later).
  draw_format_bits(size, EccLevel::Low, 0, modules, isfunction)
  // Version info for version >= 7.
  draw_version_info(version, size, modules, isfunction)
}

///|
fn set_function(
  x : Int32,
  y : Int32,
  isdark : Bool,
  modules : FixedArray[FixedArray[Bool]],
  isfunction : FixedArray[FixedArray[Bool]],
) -> Unit {
  modules[y][x] = isdark
  isfunction[y][x] = true
}

///|
fn draw_finder(
  cx : Int32,
  cy : Int32,
  size : Int32,
  modules : FixedArray[FixedArray[Bool]],
  isfunction : FixedArray[FixedArray[Bool]],
) -> Unit {
  for dy = -4; dy <= 4; dy = dy + 1 {
    for dx = -4; dx <= 4; dx = dx + 1 {
      let xx = cx + dx
      let yy = cy + dy
      if xx >= 0 && xx < size && yy >= 0 && yy < size {
        let dist = max_int(abs_int(dx), abs_int(dy))
        set_function(xx, yy, dist != 2 && dist != 4, modules, isfunction)
      }
    }
  }
}

///|
fn draw_alignment(
  cx : Int32,
  cy : Int32,
  modules : FixedArray[FixedArray[Bool]],
  isfunction : FixedArray[FixedArray[Bool]],
) -> Unit {
  for dy = -2; dy <= 2; dy = dy + 1 {
    for dx = -2; dx <= 2; dx = dx + 1 {
      let dist = max_int(abs_int(dx), abs_int(dy))
      set_function(cx + dx, cy + dy, dist != 1, modules, isfunction)
    }
  }
}

///|
/// Alignment pattern positions for version.
pub fn alignment_pattern_positions(version : Int32) -> FixedArray[Int32] {
  if version == 1 {
    return FixedArray::make(0, 0)
  }
  let numalign = version / 7 + 2
  let step = if numalign == 1 {
    0
  } else {
    (version * 8 + numalign * 3 + 5) / (numalign * 4 - 4) * 2
  }
  let size = version * 4 + 17
  let result = FixedArray::make(numalign, 0)
  for i = 0; i < numalign - 1; i = i + 1 {
    result[numalign - 1 - i] = size - 7 - i * step
  }
  result[0] = 6
  result
}

///|
fn draw_format_bits(
  size : Int32,
  level : EccLevel,
  mask : Int32,
  modules : FixedArray[FixedArray[Bool]],
  isfunction : FixedArray[FixedArray[Bool]],
) -> Unit {
  let data = (format_bits(level) << 3) | mask
  let mut rem = data
  for _i = 0; _i < 10; _i = _i + 1 {
    rem = (rem << 1) ^ ((rem >> 9) * 0x537)
  }
  let bits = ((data << 10) | rem) ^ 0x5412
  // First copy.
  for i = 0; i < 6; i = i + 1 {
    set_function(8, i, get_bit(bits, i), modules, isfunction)
  }
  set_function(8, 7, get_bit(bits, 6), modules, isfunction)
  set_function(8, 8, get_bit(bits, 7), modules, isfunction)
  set_function(7, 8, get_bit(bits, 8), modules, isfunction)
  for i = 9; i < 15; i = i + 1 {
    set_function(14 - i, 8, get_bit(bits, i), modules, isfunction)
  }
  // Second copy.
  for i = 0; i < 8; i = i + 1 {
    set_function(size - 1 - i, 8, get_bit(bits, i), modules, isfunction)
  }
  for i = 8; i < 15; i = i + 1 {
    set_function(8, size - 15 + i, get_bit(bits, i), modules, isfunction)
  }
  set_function(8, size - 8, true, modules, isfunction)
}

///|
fn draw_version_info(
  version : Int32,
  size : Int32,
  modules : FixedArray[FixedArray[Bool]],
  isfunction : FixedArray[FixedArray[Bool]],
) -> Unit {
  if version < 7 {
    return
  }
  let mut rem = version
  for _i = 0; _i < 12; _i = _i + 1 {
    rem = (rem << 1) ^ ((rem >> 11) * 0x1F25)
  }
  let bits = (version << 12) | rem
  for i = 0; i < 18; i = i + 1 {
    let bit = get_bit(bits, i)
    let a = size - 11 + i % 3
    let b = i / 3
    set_function(a, b, bit, modules, isfunction)
    set_function(b, a, bit, modules, isfunction)
  }
}

///|
fn get_bit(x : Int32, i : Int32) -> Bool {
  ((x >> i) & 1) == 1
}

///|
/// Draw codeword bits in zigzag scan, skipping function modules.
fn draw_codewords(
  version : Int32,
  size : Int32,
  data : FixedArray[Int32],
  modules : FixedArray[FixedArray[Bool]],
  isfunction : FixedArray[FixedArray[Bool]],
) -> Unit {
  let mut i = 0
  let mut right = size - 1
  while right >= 1 {
    if right <= 6 {
      right = right - 1
    }
    for vert = 0; vert < size; vert = vert + 1 {
      for j = 0; j < 2; j = j + 1 {
        let x = right - j
        let upward = ((right + 1) & 2) == 0
        let y = if upward { size - 1 - vert } else { vert }
        if !isfunction[y][x] && i < data.length() * 8 {
          modules[y][x] = get_bit(data[i >> 3], 7 - (i & 7))
          i = i + 1
        }
      }
    }
    right = right - 2
  }
}

///|
fn apply_mask(
  size : Int32,
  mask : Int32,
  modules : FixedArray[FixedArray[Bool]],
  isfunction : FixedArray[FixedArray[Bool]],
) -> Unit {
  for y = 0; y < size; y = y + 1 {
    for x = 0; x < size; x = x + 1 {
      if mask_pattern(mask, x, y) && !isfunction[y][x] {
        modules[y][x] = !modules[y][x]
      }
    }
  }
}

///|
fn mask_pattern(mask : Int32, x : Int32, y : Int32) -> Bool {
  match mask {
    0 => (x + y) % 2 == 0
    1 => y % 2 == 0
    2 => x % 3 == 0
    3 => (x + y) % 3 == 0
    4 => (x / 3 + y / 2) % 2 == 0
    5 => x * y % 2 + x * y % 3 == 0
    6 => (x * y % 2 + x * y % 3) % 2 == 0
    _ => ((x + y) % 2 + x * y % 3) % 2 == 0
  }
}

///|
/// Penalty score for mask selection (ISO/IEC 18004 rules N1-N4).
fn get_penalty_score(
  size : Int32,
  modules : FixedArray[FixedArray[Bool]],
) -> Int32 {
  let mut result = 0
  // N1 + N3: rows.
  for y = 0; y < size; y = y + 1 {
    result = result + penalty_line(size, y, true, modules)
  }
  // N1 + N3: columns.
  for x = 0; x < size; x = x + 1 {
    result = result + penalty_line(size, x, false, modules)
  }
  // N2: 2x2 blocks.
  for y = 0; y < size - 1; y = y + 1 {
    for x = 0; x < size - 1; x = x + 1 {
      let c = modules[y][x]
      if c == modules[y][x + 1] &&
        c == modules[y + 1][x] &&
        c == modules[y + 1][x + 1] {
        result = result + 3
      }
    }
  }
  // N4: dark balance.
  let mut dark = 0
  for y = 0; y < size; y = y + 1 {
    for x = 0; x < size; x = x + 1 {
      if modules[y][x] {
        dark = dark + 1
      }
    }
  }
  let total = size * size
  let k = (abs_int(dark * 20 - total * 10) + total - 1) / total - 1
  result = result + k * 10
  result
}

///|
/// Penalty for one row (is_row=true) or one column: N1 runs + N3 finder-like.
fn penalty_line(
  size : Int32,
  fixed : Int32,
  is_row : Bool,
  modules : FixedArray[FixedArray[Bool]],
) -> Int32 {
  let mut result = 0
  let mut runcolor = false
  let mut runlen = 0
  // N3 finder-like pattern: dark:light:dark:light:dark = 1:1:3:1:1.
  // Direct 11-module sliding window detection of 10111010000 / 00001011101.
  let mut window = 0 // bit mask, 11 bits, bit 10 = oldest
  let mut wbits = 0
  for pos = 0; pos < size; pos = pos + 1 {
    let c = if is_row { modules[fixed][pos] } else { modules[pos][fixed] }
    window = ((window << 1) | (if c { 1 } else { 0 })) & 0x7FF
    if wbits < 11 {
      wbits = wbits + 1
    }
    if wbits == 11 {
      if window == 0b10111010000 || window == 0b00001011101 {
        result = result + 40
      }
    }
    // N1: runs of 5+ same color.
    if pos == 0 {
      runcolor = c
      runlen = 1
    } else if c == runcolor {
      runlen = runlen + 1
      if runlen == 5 {
        result = result + 3
      } else if runlen > 5 {
        result = result + 1
      }
    } else {
      runcolor = c
      runlen = 1
    }
  }
  result
}

///|
fn abs_int(x : Int32) -> Int32 {
  if x < 0 {
    -x
  } else {
    x
  }
}

///|
fn max_int(a : Int32, b : Int32) -> Int32 {
  if a > b {
    a
  } else {
    b
  }
}

///|
fn min_int(a : Int32, b : Int32) -> Int32 {
  if a < b {
    a
  } else {
    b
  }
}
