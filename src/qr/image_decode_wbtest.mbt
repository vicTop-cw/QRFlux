/// Whitebox tests for the image-pipeline decoder internals:
/// Otsu threshold, run-pattern scan, matrix rotation, and the
/// affine module resampler. Whitebox tests live in the same package
/// and call internal functions directly (no package prefix).

///|
test "wb otsu bimodal threshold falls between peaks" {
  // Peaks at 30 (dark) and 220 (light): threshold must separate them.
  let hist : FixedArray[Int32] = FixedArray::make(256, 0)
  for i = 30; i < 40; i = i + 1 {
    hist[i] = 100
  }
  for i = 210; i < 230; i = i + 1 {
    hist[i] = 200
  }
  match otsu_threshold(hist) {
    // The optimal split may land on the first bin after the dark peak,
    // i.e. exactly 40: accept the inclusive range between the peaks.
    Some(v) => assert_true(v >= 40 && v <= 210)
    None => abort("otsu returned None for bimodal histogram")
  }
}

///|
test "wb otsu single-value histogram returns None" {
  let hist : FixedArray[Int32] = FixedArray::make(256, 0)
  hist[128] = 500
  assert_true(otsu_threshold(hist) is None)
}

///|
test "wb otsu empty histogram returns None" {
  let hist : FixedArray[Int32] = FixedArray::make(256, 0)
  assert_true(otsu_threshold(hist) is None)
}

///|
test "wb scan_line_hits perfect finder row" {
  // One row: dark 1, light 1, dark 3, light 1, dark 1 (unit = 1px).
  let w = 7
  let bits : FixedArray[FixedArray[Bool]] = FixedArray::make(
    1,
    FixedArray::make(w, false),
  )
  bits[0] = FixedArray::make(w, false)
  for x = 0; x < w; x = x + 1 {
    bits[0][x] = match x {
      0 => true
      1 => false
      2 | 3 | 4 => true
      5 => false
      _ => true
    }
  }
  let hits = scan_line_hits(bits, 0, 0)
  assert_true(hits.length() == 1)
  let h = hits[0]
  assert_true(dabs(h.center - 3.5) < 0.01)
  assert_true(dabs(h.unit_px - 1.0) < 0.01)
}

///|
test "wb scan_line_hits wrong ratio rejected" {
  // dark 1, light 1, dark 5, light 1, dark 1: center bar 5 units
  // instead of 3 — outside the 0.5-module tolerance.
  let w = 9
  let bits : FixedArray[FixedArray[Bool]] = FixedArray::make(
    1,
    FixedArray::make(w, false),
  )
  bits[0] = FixedArray::make(w, false)
  for x = 0; x < w; x = x + 1 {
    bits[0][x] = match x {
      0 => true
      1 => false
      2 | 3 | 4 | 5 | 6 => true
      7 => false
      _ => true
    }
  }
  let hits = scan_line_hits(bits, 0, 0)
  assert_true(hits.length() == 0)
}

///|
test "wb scan_line_hits column mode" {
  // Vertical 1:1:3:1:1 pattern scanned with axis=1.
  let h = 7
  let bits : FixedArray[FixedArray[Bool]] = FixedArray::make(
    h,
    FixedArray::make(1, false),
  )
  for y = 0; y < h; y = y + 1 {
    bits[y] = FixedArray::make(1, false)
    bits[y][0] = match y {
      0 => true
      1 => false
      2 | 3 | 4 => true
      5 => false
      _ => true
    }
  }
  let hits = scan_line_hits(bits, 0, 1)
  assert_true(hits.length() == 1)
  assert_true(dabs(hits[0].center - 3.5) < 0.01)
}

///|
test "wb rotate_matrix_cw 3x3" {
  let m : FixedArray[FixedArray[Int32]] = FixedArray::make(
    3,
    FixedArray::make(3, 0),
  )
  // FixedArray::make shares the inner array across rows: allocate each
  // row separately before filling.
  for y = 0; y < 3; y = y + 1 {
    m[y] = FixedArray::make(3, 0)
  }
  // rows: 1 2 3 / 4 5 6 / 7 8 9
  m[0][0] = 1
  m[0][1] = 2
  m[0][2] = 3
  m[1][0] = 4
  m[1][1] = 5
  m[1][2] = 6
  m[2][0] = 7
  m[2][1] = 8
  m[2][2] = 9
  let r = rotate_matrix_cw(m)
  // clockwise: 7 4 1 / 8 5 2 / 9 6 3
  assert_true(r[0][0] == 7)
  assert_true(r[0][1] == 4)
  assert_true(r[0][2] == 1)
  assert_true(r[1][0] == 8)
  assert_true(r[1][1] == 5)
  assert_true(r[1][2] == 2)
  assert_true(r[2][0] == 9)
  assert_true(r[2][1] == 6)
  assert_true(r[2][2] == 3)
}

///|
/// Helper (wb-local): render module matrix to grayscale bitmap.
fn wb_render(
  m : FixedArray[FixedArray[Int32]],
  scale : Int32,
  quiet : Int32,
) -> FixedArray[FixedArray[Int32]] {
  let size = m.length()
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
      if mx >= 0 && mx < size && my >= 0 && my < size && m[my][mx] == 1 {
        g[y][x] = 0
      }
    }
  }
  g
}

///|
/// Resampler precision: render a V1 QR at scale 6, derive finder centers
/// from the known geometry, sample back — the matrix must match exactly.
test "wb sample_matrix recovers module matrix at scale 6" {
  let data : FixedArray[Int32] = FixedArray::make(6, 0)
  for i = 0; i < 6; i = i + 1 {
    data[i] = (i * 37 + 11) & 0xFF
  }
  let qr = encode_binary(data, ecc_low(), 1)
  let scale = 6
  let quiet = 4
  let size = qr.size()
  let m : FixedArray[FixedArray[Int32]] = FixedArray::make(
    size,
    FixedArray::make(size, 0),
  )
  for y = 0; y < size; y = y + 1 {
    m[y] = FixedArray::make(size, 0)
    for x = 0; x < size; x = x + 1 {
      m[y][x] = if qr.get_module(x, y) { 1 } else { 0 }
    }
  }
  let gray = wb_render(m, scale, quiet)
  let bits = match binarize_bitmap(gray) {
    Some(b) => b
    None => abort("binarize failed on rendered QR")
  }
  // Finder centers sit at module (3.5, 3.5) / (size-3.5, 3.5) / (3.5, size-3.5).
  let c_tl = (quiet.to_double() + 3.5) * scale.to_double()
  let c_br = (quiet.to_double() + size.to_double() - 3.5) * scale.to_double()
  let tl : FinderPoint = { cx: c_tl, cy: c_tl, unit_px: scale.to_double(), }
  let tr : FinderPoint = { cx: c_br, cy: c_tl, unit_px: scale.to_double(), }
  let bl : FinderPoint = { cx: c_tl, cy: c_br, unit_px: scale.to_double(), }
  let sampled = match sample_matrix(bits, tl, tr, bl) {
    Some(s) => s
    None => abort("sample_matrix returned None for clean geometry")
  }
  assert_true(sampled.length() == size)
  for y = 0; y < size; y = y + 1 {
    for x = 0; x < size; x = x + 1 {
      if sampled[y][x] != m[y][x] {
        abort(
          "sample mismatch at (\{x},\{y}): got \{sampled[y][x]}, want \{m[y][x]}",
        )
      }
    }
  }
}

///|
/// sample_matrix rejects a skewed triangle (badly unequal legs).
test "wb sample_matrix rejects skewed triangle" {
  let bits : FixedArray[FixedArray[Bool]] = FixedArray::make(
    40,
    FixedArray::make(40, false),
  )
  for y = 0; y < 40; y = y + 1 {
    bits[y] = FixedArray::make(40, false)
  }
  let tl : FinderPoint = { cx: 10.0, cy: 10.0, unit_px: 3.0, }
  // d_tr = 34, d_bl = 8: relative diff 76% > 25% gate -> rejected.
  let tr : FinderPoint = { cx: 44.0, cy: 10.0, unit_px: 3.0, }
  let bl : FinderPoint = { cx: 10.0, cy: 18.0, unit_px: 3.0, }
  assert_true(sample_matrix(bits, tl, tr, bl) is None)
}

///|
/// sample_matrix rejects an invalid derived size (not 4k+17).
test "wb sample_matrix rejects invalid size" {
  // Three collinear-ish points whose spacing implies a non-4k+17 size.
  let bits : FixedArray[FixedArray[Bool]] = FixedArray::make(
    60,
    FixedArray::make(60, false),
  )
  for y = 0; y < 60; y = y + 1 {
    bits[y] = FixedArray::make(60, false)
  }
  // unit_px=2, leg distance 25 -> size = 25/2 + 7 = 19.5 -> round 20:
  // 20 is not 4k+17 -> rejected.
  let tl : FinderPoint = { cx: 10.0, cy: 10.0, unit_px: 2.0, }
  let tr : FinderPoint = { cx: 35.0, cy: 10.0, unit_px: 2.0, }
  let bl : FinderPoint = { cx: 10.0, cy: 35.0, unit_px: 2.0, }
  assert_true(sample_matrix(bits, tl, tr, bl) is None)
}
