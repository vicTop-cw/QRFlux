/// QR Code Model 2 decoder core.
/// Self-implemented from ISO/IEC 18004 algorithm description.
/// Decodes QRFlux-generated QR codes (no geometric distortion).
/// This is the inverse of qrcode.mbt's encoder.

///|
/// Decode a QR code from a module matrix (0/1 Int32 values).
/// Returns the original byte payload, or None if decoding fails.
pub fn decode_qr(matrix : FixedArray[FixedArray[Int32]]) -> FixedArray[Int32]? {
  let size = matrix.length()
  if size < 21 || size > 177 || (size - 17) % 4 != 0 {
    return None
  }
  let version = (size - 17) / 4
  if version < 1 || version > 40 {
    return None
  }
  // Convert Int32 matrix to Bool matrix (independent rows).
  let bool_modules = FixedArray::make(size, FixedArray::make(size, false))
  for y = 0; y < size; y = y + 1 {
    bool_modules[y] = FixedArray::make(size, false)
    for x = 0; x < size; x = x + 1 {
      bool_modules[y][x] = matrix[y][x] != 0
    }
  }
  decode_bool_modules(bool_modules, version, size)
}

///|
/// Decode from a QrCode object (convenient for testing).
pub fn decode_from_qrcode(qr : QrCode) -> FixedArray[Int32]? {
  decode_bool_modules(qr.modules, qr.version(), qr.size())
}

///|
/// Core decode routine operating on Bool modules.
fn decode_bool_modules(
  modules : FixedArray[FixedArray[Bool]],
  version : Int32,
  size : Int32,
) -> FixedArray[Int32]? {
  // Step 1: Read format info to get ECC level and mask pattern.
  let (level, mask) = match read_format_info(modules, size) {
    Some(v) => v
    None => return None
  }
  // Step 2: Verify version info (V7+).
  if version >= 7 {
    match read_version_info(modules, size) {
      Some(v) => if v != version { return None }
      None => return None
    }
  }
  // Step 3: Mark function module positions (finder, alignment, timing,
  // format, version). Reuses the encoder's draw_function_patterns to
  // obtain the exact same isfunction mask.
  let isfunction = mark_function_modules(version, size)
  let raw_bits = read_data_bits(modules, size, isfunction, mask)
  // Step 5: Pack bits into codewords.
  // Note: the encoder's draw_codewords uses `if right <= 6` (not `== 6`),
  // which skips columns 0 and 3 near the end of the zigzag. This means the
  // encoder only draws 200 bits for V1 (not 208). The missing 8 bits
  // correspond to the last codeword, which the encoder leaves as 0 (initial
  // false, then unmasked). We pad with 0 bits and rely on RS correction.
  let num_codewords = num_raw_data_modules(version) / 8
  let all_codewords = FixedArray::make(num_codewords, 0)
  for i = 0; i < num_codewords; i = i + 1 {
    let mut b : Int32 = 0
    for j = 0; j < 8; j = j + 1 {
      let bit_idx = i * 8 + j
      let bit = if bit_idx < raw_bits.length() { raw_bits[bit_idx] } else { 0 }
      b = b | (bit << (7 - j))
    }
    all_codewords[i] = b
  }
  // Step 6: Deinterleave and RS-correct to get data codewords.
  let data_codewords = match
    deinterleave_and_correct(all_codewords, version, level) {
    Some(v) => v
    None => return None
  }
  // Step 7: Decode segments to raw bytes.
  decode_segments(data_codewords, version)
}

///|
/// Mark function module positions by reusing the encoder's pattern drawer.
/// We only need the isfunction mask; the temporary modules are discarded.
fn mark_function_modules(
  version : Int32,
  size : Int32,
) -> FixedArray[FixedArray[Bool]] {
  let temp_modules = FixedArray::make(size, FixedArray::make(size, false))
  let isfunction = FixedArray::make(size, FixedArray::make(size, false))
  for i = 0; i < size; i = i + 1 {
    temp_modules[i] = FixedArray::make(size, false)
    isfunction[i] = FixedArray::make(size, false)
  }
  draw_function_patterns(version, size, temp_modules, isfunction)
  isfunction
}

///|
/// Read format info (15 bits, two copies, BCH(15,5) error correction).
/// Returns (EccLevel, mask) on success.
fn read_format_info(
  modules : FixedArray[FixedArray[Bool]],
  size : Int32,
) -> (EccLevel, Int32)? {
  // First copy around top-left finder.
  // bit 0..5: (x=8, y=0..5); bit 6: (8,7); bit 7: (8,8); bit 8: (7,8);
  // bit 9..14: (x=14-i, y=8) i.e. (5..0, 8).
  let mut bits1 : Int32 = 0
  for i = 0; i < 6; i = i + 1 {
    if modules[i][8] {
      bits1 = bits1 | (1 << i)
    }
  }
  if modules[7][8] {
    bits1 = bits1 | (1 << 6)
  }
  if modules[8][8] {
    bits1 = bits1 | (1 << 7)
  }
  if modules[8][7] {
    bits1 = bits1 | (1 << 8)
  }
  for i = 9; i < 15; i = i + 1 {
    if modules[8][14 - i] {
      bits1 = bits1 | (1 << i)
    }
  }
  // Second copy near bottom-right.
  // bit 0..7: (x=size-1-i, y=8); bit 8..14: (x=8, y=size-15+i).
  let mut bits2 : Int32 = 0
  for i = 0; i < 8; i = i + 1 {
    if modules[8][size - 1 - i] {
      bits2 = bits2 | (1 << i)
    }
  }
  for i = 8; i < 15; i = i + 1 {
    if modules[size - 15 + i][8] {
      bits2 = bits2 | (1 << i)
    }
  }
  // Decode with BCH error correction (try each copy, pick the valid one).
  let data = match try_decode_format(bits1) {
    Some(v) => v
    None =>
      match try_decode_format(bits2) {
        Some(v) => v
        None => return None
      }
  }
  let mask = data & 0x7
  let level_bits = (data >> 3) & 0x3
  // format_bits: Low=1, Medium=0, Quartile=3, High=2 (see tables.mbt).
  let level = match level_bits {
    1 => EccLevel::Low
    0 => EccLevel::Medium
    3 => EccLevel::Quartile
    2 => EccLevel::High
    _ => return None
  }
  Some((level, mask))
}

///|
/// Try to decode a 15-bit format info value with BCH(15,5) error correction.
/// Generator polynomial 0x537, mask 0x5412. Corrects up to 3 bit errors.
/// Returns the 5-bit data part, or None if too many errors.
fn try_decode_format(raw : Int32) -> Int32? {
  let mut best_data : Int32 = -1
  let mut best_dist : Int32 = 100
  for data = 0; data < 32; data = data + 1 {
    let mut rem = data
    for _i = 0; _i < 10; _i = _i + 1 {
      rem = (rem << 1) ^ ((rem >> 9) * 0x537)
    }
    let bits = ((data << 10) | rem) ^ 0x5412
    let dist = popcount15(raw ^ bits)
    if dist < best_dist {
      best_dist = dist
      best_data = data
    }
  }
  if best_dist <= 3 {
    Some(best_data)
  } else {
    None
  }
}

///|
/// Read version info (18 bits, two copies, BCH(18,6) error correction).
/// V7+ only. Returns the decoded version number.
fn read_version_info(
  modules : FixedArray[FixedArray[Bool]],
  size : Int32,
) -> Int32? {
  // First copy (bottom-left): bit i at (x=size-11+i%3, y=i/3).
  let mut bits1 : Int32 = 0
  for i = 0; i < 18; i = i + 1 {
    let x = size - 11 + i % 3
    let y = i / 3
    if modules[y][x] {
      bits1 = bits1 | (1 << i)
    }
  }
  // Second copy (top-right): bit i at (x=i/3, y=size-11+i%3).
  let mut bits2 : Int32 = 0
  for i = 0; i < 18; i = i + 1 {
    let x = i / 3
    let y = size - 11 + i % 3
    if modules[y][x] {
      bits2 = bits2 | (1 << i)
    }
  }
  match try_decode_version(bits1) {
    Some(v) => return Some(v)
    None => ()
  }
  match try_decode_version(bits2) {
    Some(v) => return Some(v)
    None => ()
  }
  None
}

///|
/// Try to decode an 18-bit version info value with BCH(18,6) error correction.
/// Generator polynomial 0x1F25, no mask. Corrects up to 3 bit errors.
fn try_decode_version(raw : Int32) -> Int32? {
  let mut best_data : Int32 = -1
  let mut best_dist : Int32 = 100
  for data = 0; data < 64; data = data + 1 {
    let mut rem = data
    for _i = 0; _i < 12; _i = _i + 1 {
      rem = (rem << 1) ^ ((rem >> 11) * 0x1F25)
    }
    let bits = (data << 12) | rem
    let dist = popcount18(raw ^ bits)
    if dist < best_dist {
      best_dist = dist
      best_data = data
    }
  }
  if best_dist <= 3 && best_data >= 1 && best_data <= 40 {
    Some(best_data)
  } else {
    None
  }
}

///|
/// Count set bits in a 15-bit value.
fn popcount15(x : Int32) -> Int32 {
  let mut count = 0
  let mut v = x
  for _i = 0; _i < 15; _i = _i + 1 {
    count = count + (v & 1)
    v = v >> 1
  }
  count
}

///|
/// Count set bits in an 18-bit value.
fn popcount18(x : Int32) -> Int32 {
  let mut count = 0
  let mut v = x
  for _i = 0; _i < 18; _i = _i + 1 {
    count = count + (v & 1)
    v = v >> 1
  }
  count
}

///|
/// Read data bits in zigzag order (mirror of encoder's draw_codewords),
/// unmasking data modules on the fly. Function modules are skipped.
fn read_data_bits(
  modules : FixedArray[FixedArray[Bool]],
  size : Int32,
  isfunction : FixedArray[FixedArray[Bool]],
  mask : Int32,
) -> Array[Int32] {
  let bits : Array[Int32] = []
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
        if !isfunction[y][x] {
          let mut bit = modules[y][x]
          if mask_pattern(mask, x, y) {
            bit = !bit
          }
          bits.push(if bit { 1 } else { 0 })
        }
      }
    }
    right = right - 2
  }
  bits
}

///|
/// Deinterleave codewords (inverse of add_ecc_and_interleave) and RS-correct
/// each block. Returns the concatenated data codewords.
fn deinterleave_and_correct(
  all_codewords : FixedArray[Int32],
  version : Int32,
  level : EccLevel,
) -> FixedArray[Int32]? {
  let numblocks = num_ecc_blocks(level, version)
  let blockecclen = ecc_codewords_per_block(level, version)
  let rawcodewords = num_raw_data_modules(version) / 8
  let numshortblocks = numblocks - rawcodewords % numblocks
  let shortblocklen = rawcodewords / numblocks
  let shortdatalen = shortblocklen - blockecclen
  // Allocate per-block data and ECC arrays.
  let datblocks : Array[FixedArray[Int32]] = []
  for i = 0; i < numblocks; i = i + 1 {
    let dlen = shortdatalen + (if i < numshortblocks { 0 } else { 1 })
    datblocks.push(FixedArray::make(dlen, 0))
  }
  let eccblocks : Array[FixedArray[Int32]] = []
  for i = 0; i < numblocks; i = i + 1 {
    eccblocks.push(FixedArray::make(blockecclen, 0))
  }
  // Inverse interleave: read columns back into blocks.
  let mut idx = 0
  // Data: columns 0..shortdatalen-1, all blocks.
  for i = 0; i < shortdatalen; i = i + 1 {
    for j = 0; j < numblocks; j = j + 1 {
      datblocks[j][i] = all_codewords[idx]
      idx = idx + 1
    }
  }
  // Data: column shortdatalen, only long blocks.
  for j = numshortblocks; j < numblocks; j = j + 1 {
    datblocks[j][shortdatalen] = all_codewords[idx]
    idx = idx + 1
  }
  // ECC: all columns, all blocks.
  for i = 0; i < blockecclen; i = i + 1 {
    for j = 0; j < numblocks; j = j + 1 {
      eccblocks[j][i] = all_codewords[idx]
      idx = idx + 1
    }
  }
  // RS-correct each block and concatenate data codewords.
  let result : Array[Int32] = []
  for i = 0; i < numblocks; i = i + 1 {
    let datlen = datblocks[i].length()
    let codeword = FixedArray::make(datlen + blockecclen, 0)
    for j = 0; j < datlen; j = j + 1 {
      codeword[j] = datblocks[i][j]
    }
    for j = 0; j < blockecclen; j = j + 1 {
      codeword[datlen + j] = eccblocks[i][j]
    }
    let corrected = match rs_decode(codeword, blockecclen) {
      Some(v) => v
      None => return None
    }
    for j = 0; j < datlen; j = j + 1 {
      result.push(corrected[j])
    }
  }
  // Convert Array to FixedArray.
  let fa = FixedArray::make(result.length(), 0)
  for i = 0; i < result.length(); i = i + 1 {
    fa[i] = result[i]
  }
  Some(fa)
}

///|
/// RS decode: compute syndromes, correct errors via Berlekamp-Massey.
/// Codeword layout: [data[0..dlen-1], ecc[0..num_ec-1]] (high-order first).
/// Generator roots: alpha^0, alpha^1, ..., alpha^(num_ec-1) with alpha=2.
fn rs_decode(
  codeword : FixedArray[Int32],
  num_ec : Int32,
) -> FixedArray[Int32]? {
  let n = codeword.length()
  // Compute syndromes S_i = c(alpha^i) via Horner's method.
  let syndromes = FixedArray::make(num_ec, 0)
  let mut all_zero = true
  for i = 0; i < num_ec; i = i + 1 {
    let alpha_i = gf_pow(2, i)
    let mut s = 0
    for j = 0; j < n; j = j + 1 {
      s = gf_mul(s, alpha_i) ^ codeword[j]
    }
    syndromes[i] = s
    if s != 0 {
      all_zero = false
    }
  }
  if all_zero {
    return Some(codeword)
  }
  // Attempt error correction.
  rs_correct(codeword, syndromes, num_ec)
}

///|
/// RS error correction using Berlekamp-Massey + Chien search + Forney.
fn rs_correct(
  codeword : FixedArray[Int32],
  syndromes : FixedArray[Int32],
  num_ec : Int32,
) -> FixedArray[Int32]? {
  let bm = match berlekamp_massey(syndromes, num_ec) {
    Some(v) => v
    None => return None
  }
  let lambda = bm.0
  let num_errors = bm.1
  if num_errors == 0 {
    return Some(codeword)
  }
  // Chien search: find positions i where Lambda(alpha^(-i)) == 0.
  let n = codeword.length()
  let error_positions : Array[Int32] = []
  for i = 0; i < n; i = i + 1 {
    // alpha^(-i) = alpha^(255-i) in GF(256).
    let alpha_inv_i = gf_pow(2, 255 - i)
    let mut val = 1 // lambda[0] = 1
    for j = 1; j <= num_errors; j = j + 1 {
      val = val ^ gf_mul(lambda[j], gf_pow(alpha_inv_i, j))
    }
    if val == 0 {
      error_positions.push(i)
    }
  }
  if error_positions.length() != num_errors {
    return None
  }
  // Compute error evaluator Omega(x) = (S(x) * Lambda(x)) mod x^num_ec.
  let omega = FixedArray::make(num_ec, 0)
  for i = 0; i < num_ec; i = i + 1 {
    let mut s = 0
    for j = 0; j <= i; j = j + 1 {
      if j <= num_errors && i - j < num_ec {
        s = s ^ gf_mul(lambda[j], syndromes[i - j])
      }
    }
    omega[i] = s
  }
  // Apply Forney algorithm to compute and apply error values.
  let result = FixedArray::make(n, 0)
  for i = 0; i < n; i = i + 1 {
    result[i] = codeword[i]
  }
  for pos in error_positions {
    let alpha_inv_pos = gf_pow(2, 255 - pos)
    // Evaluate Omega at alpha^(-pos).
    let mut omega_val = 0
    for i = 0; i < num_ec; i = i + 1 {
      omega_val = omega_val ^ gf_mul(omega[i], gf_pow(alpha_inv_pos, i))
    }
    // Evaluate Lambda'(alpha^(-pos)) (formal derivative; even terms vanish).
    let mut lambda_deriv_val = 0
    for j = 1; j <= num_errors; j = j + 1 {
      if j % 2 == 1 {
        lambda_deriv_val = lambda_deriv_val ^
          gf_mul(lambda[j], gf_pow(alpha_inv_pos, j - 1))
      }
    }
    if lambda_deriv_val == 0 {
      return None
    }
    let error_val = gf_mul(omega_val, gf_inv(lambda_deriv_val))
    // Chien search finds i where Lambda(alpha^(-i)) == 0; with the encoder's
    // descending-power codeword layout c(x)=c[0]*x^(n-1)+...+c[n-1], this
    // root corresponds to error at codeword[n-1-i], not codeword[i].
    result[n - 1 - pos] = result[n - 1 - pos] ^ error_val
  }
  Some(result)
}

///|
/// Berlekamp-Massey algorithm: find error locator polynomial Lambda(x).
/// Returns (lambda coefficients, number of errors).
fn berlekamp_massey(
  syndromes : FixedArray[Int32],
  num_ec : Int32,
) -> (FixedArray[Int32], Int32)? {
  // Lambda(x) = lambda[0] + lambda[1]*x + ... + lambda[L]*x^L
  let lambda = FixedArray::make(num_ec + 1, 0)
  lambda[0] = 1
  let b = FixedArray::make(num_ec + 1, 0)
  b[0] = 1
  let mut l = 0
  let mut m = 1
  let mut bb = 1
  for i = 0; i < num_ec; i = i + 1 {
    // Compute discrepancy.
    let mut delta = syndromes[i]
    for j = 1; j <= l; j = j + 1 {
      delta = delta ^ gf_mul(lambda[j], syndromes[i - j])
    }
    if delta == 0 {
      m = m + 1
    } else if 2 * l <= i {
      // Save lambda, update, then set b = old lambda.
      let t = FixedArray::make(num_ec + 1, 0)
      for j = 0; j <= num_ec; j = j + 1 {
        t[j] = lambda[j]
      }
      let delta_over_b = gf_mul(delta, gf_inv(bb))
      for j = 0; j <= num_ec - m; j = j + 1 {
        lambda[j + m] = lambda[j + m] ^ gf_mul(delta_over_b, b[j])
      }
      l = i + 1 - l
      for j = 0; j <= num_ec; j = j + 1 {
        b[j] = t[j]
      }
      bb = delta
      m = 1
    } else {
      let delta_over_b = gf_mul(delta, gf_inv(bb))
      for j = 0; j <= num_ec - m; j = j + 1 {
        lambda[j + m] = lambda[j + m] ^ gf_mul(delta_over_b, b[j])
      }
      m = m + 1
    }
  }
  Some((lambda, l))
}

///|
/// Multiplicative inverse in GF(256) via Fermat's little theorem: x^254.
fn gf_inv(x : Int32) -> Int32 {
  if x == 0 {
    return 0
  }
  gf_pow(x, 254)
}

///|
/// Alphanumeric mode character table (45 chars): 0-9, A-Z, and 9 symbols.
let alphanumeric_table : FixedArray[Int32] = [
  48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74,
  75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 32, 36, 37, 42,
  43, 45, 46, 47, 58,
]

///|
/// Decode segments from data codewords. Supports byte, numeric, alphanumeric.
fn decode_segments(
  data : FixedArray[Int32],
  version : Int32,
) -> FixedArray[Int32]? {
  // Unpack codewords into a flat bit array (MSB first per byte).
  let bits : Array[Int32] = []
  for i = 0; i < data.length(); i = i + 1 {
    for j = 7; j >= 0; j = j - 1 {
      bits.push((data[i] >> j) & 1)
    }
  }
  let result : Array[Int32] = []
  let mut pos = 0
  let total_bits = bits.length()
  while pos + 4 <= total_bits {
    let mode = read_bits_array(bits, pos, 4)
    pos = pos + 4
    if mode == 0 {
      break // Terminator
    }
    match mode {
      4 => {
        // Byte mode
        let ccbits = char_count_bits(mode_byte(), version)
        if pos + ccbits > total_bits {
          return None
        }
        let count = read_bits_array(bits, pos, ccbits)
        pos = pos + ccbits
        if count < 0 || pos + count * 8 > total_bits {
          return None
        }
        for _i = 0; _i < count; _i = _i + 1 {
          let byte = read_bits_array(bits, pos, 8)
          pos = pos + 8
          result.push(byte)
        }
      }
      1 => {
        // Numeric mode
        let ccbits = char_count_bits(mode_numeric(), version)
        if pos + ccbits > total_bits {
          return None
        }
        let count = read_bits_array(bits, pos, ccbits)
        pos = pos + ccbits
        let mut remaining = count
        while remaining > 0 {
          if remaining >= 3 {
            if pos + 10 > total_bits {
              return None
            }
            let n = read_bits_array(bits, pos, 10)
            pos = pos + 10
            result.push(48 + n / 100)
            result.push(48 + n / 10 % 10)
            result.push(48 + n % 10)
            remaining = remaining - 3
          } else if remaining == 2 {
            if pos + 7 > total_bits {
              return None
            }
            let n = read_bits_array(bits, pos, 7)
            pos = pos + 7
            result.push(48 + n / 10)
            result.push(48 + n % 10)
            remaining = 0
          } else {
            if pos + 4 > total_bits {
              return None
            }
            let n = read_bits_array(bits, pos, 4)
            pos = pos + 4
            result.push(48 + n)
            remaining = 0
          }
        }
      }
      2 => {
        // Alphanumeric mode
        let ccbits = char_count_bits(mode_alphanumeric(), version)
        if pos + ccbits > total_bits {
          return None
        }
        let count = read_bits_array(bits, pos, ccbits)
        pos = pos + ccbits
        let mut remaining = count
        while remaining > 0 {
          if remaining >= 2 {
            if pos + 11 > total_bits {
              return None
            }
            let n = read_bits_array(bits, pos, 11)
            pos = pos + 11
            result.push(alphanumeric_table[n / 45])
            result.push(alphanumeric_table[n % 45])
            remaining = remaining - 2
          } else {
            if pos + 6 > total_bits {
              return None
            }
            let n = read_bits_array(bits, pos, 6)
            pos = pos + 6
            result.push(alphanumeric_table[n])
            remaining = 0
          }
        }
      }
      _ => break // Unsupported mode (Kanji/ECI/etc.) — stop parsing.
    }
  }
  // Convert Array to FixedArray.
  let fa = FixedArray::make(result.length(), 0)
  for i = 0; i < result.length(); i = i + 1 {
    fa[i] = result[i]
  }
  Some(fa)
}

///|
/// Read n bits from bit array starting at pos (MSB first).
fn read_bits_array(bits : Array[Int32], pos : Int32, n : Int32) -> Int32 {
  let mut result = 0
  for i = 0; i < n; i = i + 1 {
    result = (result << 1) | bits[pos + i]
  }
  result
}
