/// Tests for the adaptive tile-wise Otsu binarization and the two-stage
/// decode strategy, using synthetic uneven-illumination QR bitmaps.

///|
/// Multiply a grayscale bitmap by a per-column light level that ramps
/// from `dark` (left) to `bright` (right) — classic side-light photo.
fn wb_gradient_light(
  src : FixedArray[FixedArray[Int32]],
  dark : Int,
  bright : Int,
) -> FixedArray[FixedArray[Int32]] {
  let h = src.length()
  let w = src[0].length()
  let out : FixedArray[FixedArray[Int32]] = FixedArray::make(
    h,
    FixedArray::make(w, 255),
  )
  for y = 0; y < h; y = y + 1 {
    out[y] = FixedArray::make(w, 255)
    for x = 0; x < w; x = x + 1 {
      let t = if w > 1 { x.to_double() / (w - 1).to_double() } else { 0.0 }
      let level = (dark.to_double() +
        (bright.to_double() - dark.to_double()) * t) /
        255.0
      let v = (src[y][x].to_double() * level)
      let iv = v.to_int()
      out[y][x] = if iv < 0 { 0 } else if iv > 255 { 255 } else { iv }
    }
  }
  out
}

///|
/// Build a V(n) QR grayscale bitmap (0=black module, 255=white/quiet).
fn wb_qr_gray(
  data : FixedArray[Int32],
  version : Int32,
  scale : Int,
  quiet : Int,
) -> FixedArray[FixedArray[Int32]] {
  let qr = @qr.encode_binary(data, @qr.ecc_low(), version)
  let size = qr.size()
  let dim = (size + quiet * 2) * scale
  let g : FixedArray[FixedArray[Int32]] = FixedArray::make(
    dim,
    FixedArray::make(dim, 255),
  )
  for y = 0; y < dim; y = y + 1 {
    g[y] = FixedArray::make(dim, 255)
    let my = y / scale - quiet
    for x = 0; x < dim; x = x + 1 {
      let mx = x / scale - quiet
      if mx >= 0 && mx < size && my >= 0 && my < size && qr.get_module(mx, my) {
        g[y][x] = 0
      }
    }
  }
  g
}

///|
fn wb_payload(n : Int) -> FixedArray[Int32] {
  let fa = FixedArray::make(n, 0)
  for i = 0; i < n; i = i + 1 {
    fa[i] = (i * 53 + 7) & 0xFF
  }
  fa
}

///|
/// Check helper: decoded payload equals expected.
fn wb_check_payload(decoded : FixedArray[Int32]?, expected : FixedArray[Int32]) -> Bool {
  match decoded {
    Some(d) =>
      if d.length() != expected.length() {
        false
      } else {
        let mut same = true
        for i = 0; i < expected.length(); i = i + 1 {
          if d[i] != expected[i] {
            same = false
          }
        }
        same
      }
    None => false
  }
}

///|
/// Sanity first: the constructed bitmap decodes without any illumination.
test "wb constructed bitmap decodes unlit" {
  let data = wb_payload(20)
  let g = wb_qr_gray(data, 2, 8, 4)
  let decoded = @qr.decode_from_pixels(g)
  assert_true(wb_check_payload(decoded, data))
}

///|
/// Uneven illumination: left side lit at 25%, right at 100%. A single
/// global Otsu threshold collapses the dark side's white modules into
/// black; the adaptive tile-wise retry must recover the code.
test "wb adaptive binarize recovers uneven illumination" {
  let data = wb_payload(20)
  let lit = wb_gradient_light(wb_qr_gray(data, 2, 8, 4), 64, 255)
  // Sanity: the dark side really is dark (left quiet zone below 100).
  assert_true(lit[10][10] < 100)
  let decoded = @qr.decode_from_pixels(lit)
  assert_true(wb_check_payload(decoded, data))
}

///|
/// Mild illumination (60%..100%) still decodes through the global path.
test "wb mild illumination decodes via global path" {
  let data = wb_payload(20)
  let lit = wb_gradient_light(wb_qr_gray(data, 2, 8, 4), 153, 255)
  let decoded = @qr.decode_from_pixels(lit)
  assert_true(wb_check_payload(decoded, data))
}

///|
/// The adaptive binarizer itself: a two-level synthetic image whose left
/// half sits at bright-bg 40 / dark-fg 200 and right half at dark-bg 240 /
/// bright-fg 150 — no single global threshold separates both halves
/// correctly, per-tile thresholds do.
test "wb adaptive binarize splits two-level tiles" {
  let w = 64
  let h = 64
  let g : FixedArray[FixedArray[Int32]] = FixedArray::make(
    h,
    FixedArray::make(w, 0),
  )
  for y = 0; y < h; y = y + 1 {
    g[y] = FixedArray::make(w, 0)
    for x = 0; x < w; x = x + 1 {
      // Left tile: bg 40 (dark), fg 200 (bright) -> local threshold ~120:
      // fg 200 >= 120 -> bright. Right tile: bg 240 (bright), fg 150
      // (dark) -> local threshold ~195: fg 150 < 195 -> dark. A global
      // threshold (~95) would call the right-half fg bright (wrong).
      g[y][x] = if x < w / 2 {
        if y % 2 == 0 { 200 } else { 40 }
      } else {
        if y % 2 == 0 { 150 } else { 240 }
      }
    }
  }
  let bits = match @qr.adaptive_binarize_bitmap(g, 32) {
    Some(b) => b
    None => abort("adaptive binarize failed")
  }
  // bits[y][x] = gray < threshold (true = dark).
  let left_even = bits[0][10] == false
  let left_odd = bits[1][10] == true
  let right_even = bits[0][40] == true
  let right_odd = bits[1][40] == false
  assert_true(left_even)
  assert_true(left_odd)
  assert_true(right_even)
  assert_true(right_odd)
}

///|
/// Mechanism check: adaptive binarization of a flat (single-level) image
/// must still fail gracefully (no QR to find).
test "wb adaptive binarize flat image still no decode" {
  let g : FixedArray[FixedArray[Int32]] = FixedArray::make(
    64,
    FixedArray::make(64, 200),
  )
  assert_true(@qr.decode_from_pixels(g) is None)
}
