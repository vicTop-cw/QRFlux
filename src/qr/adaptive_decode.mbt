/// Adaptive (tile-wise Otsu) binarization and the two-stage decode
/// strategy: global Otsu first, adaptive retry on failure.

///|
/// Binarize a grayscale bitmap tile-wise: each tile×tile block gets its
/// own Otsu threshold, so uneven illumination (shadows, side light,
/// vignetting) does not push one side's white modules below a single
/// global threshold. Blocks with a degenerate histogram (flat tile) fall
/// back to the global threshold.
pub fn adaptive_binarize_bitmap(
  gray : FixedArray[FixedArray[Int32]],
  tile : Int,
) -> FixedArray[FixedArray[Bool]]? {
  let height = gray.length()
  if height == 0 || gray[0].length() == 0 {
    return None
  }
  let width = gray[0].length()
  for y = 0; y < height; y = y + 1 {
    if gray[y].length() != width {
      return None
    }
  }
  if tile < 8 {
    return None
  }
  // Global threshold as the degenerate-tile fallback.
  let global_hist : FixedArray[Int] = FixedArray::make(256, 0)
  for y = 0; y < height; y = y + 1 {
    for x = 0; x < width; x = x + 1 {
      let v = gray[y][x]
      let b = if v < 0 { 0 } else if v > 255 { 255 } else { v }
      global_hist[b] = global_hist[b] + 1
    }
  }
  let global_t = match otsu_threshold(global_hist) {
    Some(v) => v
    None => return None
  }
  let bits : FixedArray[FixedArray[Bool]] = FixedArray::make(
    height,
    FixedArray::make(width, false),
  )
  // Allocate each row separately: `FixedArray::make(height, inner)` shares
  // one inner array across all rows, and tile-wise writes would overwrite
  // each other.
  for i = 0; i < height; i = i + 1 {
    bits[i] = FixedArray::make(width, false)
  }
  let mut ty = 0
  while ty < height {
    let th = if ty + tile < height { tile } else { height - ty }
    let mut tx = 0
    while tx < width {
      let tw = if tx + tile < width { tile } else { width - tx }
      // Per-tile histogram.
      let hist : FixedArray[Int] = FixedArray::make(256, 0)
      for y = ty; y < ty + th; y = y + 1 {
        for x = tx; x < tx + tw; x = x + 1 {
          let v = gray[y][x]
          let b = if v < 0 { 0 } else if v > 255 { 255 } else { v }
          hist[b] = hist[b] + 1
        }
      }
      // Degenerate tile (flat) -> global threshold; otherwise local Otsu.
      let t = match otsu_threshold(hist) {
        Some(v) => v
        None => global_t
      }
      for y = ty; y < ty + th; y = y + 1 {
        for x = tx; x < tx + tw; x = x + 1 {
          bits[y][x] = gray[y][x] < t
        }
      }
      tx = tx + tw
    }
    ty = ty + th
  }
  Some(bits)
}

///|
/// Full decode attempt on an already-binarized bitmap: finder
/// localization -> candidate enumeration -> affine/perspective sampling
/// -> decode_qr with 4-rotation retry.
fn try_decode_bits(
  bits : FixedArray[FixedArray[Bool]]
) -> FixedArray[Int32]? {
  let cands = find_finder_candidates(bits)
  if cands.length() < 3 {
    return None
  }
  // Enumerate candidate triples and try to decode each sampled matrix.
  // Alignment patterns also match 1:1:3:1:1, so there may be more than
  // three candidates; geometric + size validation inside sample_matrix
  // filters bad triples, and decode_qr is the final judge.
  let n = cands.length()
  // Cap combinatorics on pathological inputs.
  let max_c = if n > 12 { 12 } else { n }
  for a = 0; a < max_c; a = a + 1 {
    for b = a + 1; b < max_c; b = b + 1 {
      for c = b + 1; c < max_c; c = c + 1 {
        let p1 = cands[a]
        let p2 = cands[b]
        let p3 = cands[c]
        // Try all assignments of (tl, tr, bl).
        let combos = [
          (p1, p2, p3),
          (p1, p3, p2),
          (p2, p1, p3),
          (p2, p3, p1),
          (p3, p1, p2),
          (p3, p2, p1),
        ]
        for combo in combos {
          let (tl, tr, bl) = combo
          let mat = match sample_matrix(bits, tl, tr, bl) {
            Some(m) => m
            None => continue
          }
          // Orientation unknown: try 4 rotations.
          let mut m = mat
          for _r = 0; _r < 4; _r = _r + 1 {
            match decode_qr(m) {
              Some(payload) => return Some(payload)
              None => m = rotate_matrix_cw(m)
            }
          }
          // Affine failed: retry with perspective correction.
          match try_decode_perspective(bits, tl, tr, bl) {
            Some(payload) => return Some(payload)
            None => ()
          }
        }
      }
    }
  }
  None
}

///|
/// Decode a QR code directly from grayscale pixels (screenshot-like input).
/// Two-stage binarization strategy:
///   1. global Otsu (fast, correct for uniform illumination)
///   2. adaptive tile-wise Otsu retry (for uneven illumination)
/// followed by finder localization -> affine/perspective resampling ->
/// decode_qr with 4-rotation retry. Returns the original byte payload,
/// or None if the image does not contain a decodable QR code.
pub fn decode_from_pixels(
  gray : FixedArray[FixedArray[Int32]],
) -> FixedArray[Int32]? {
  // Stage 1: global Otsu.
  let bits = match binarize_bitmap(gray) {
    Some(b) => b
    None => return None
  }
  match try_decode_bits(bits) {
    Some(payload) => return Some(payload)
    None => ()
  }
  // Stage 2: adaptive tile-wise Otsu retry. Tile 64 keeps finder
  // patterns (7 modules each) well inside a tile at typical resolutions.
  let abits = match adaptive_binarize_bitmap(gray, 64) {
    Some(b) => b
    None => return None
  }
  try_decode_bits(abits)
}