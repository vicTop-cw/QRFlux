/// QR image-pipeline decoder: grayscale pixels -> clean module matrix.
/// This is the missing "image entry" for real-world screenshots:
/// the remote machine displays a QR image, the local side captures it
/// as a screenshot (scaled, shifted, noisy) and decodes it back.
/// All steps are self-implemented from ISO/IEC 18004 geometry:
///   1. Otsu global threshold binarization
///   2. Finder localization (1:1:3:1:1 run-pattern scan, row x column)
///   3. Affine module resampling from the three finder centers
///   4. Feed the sampled N x N matrix into decode_qr (with 4-rotation retry)
/// Zero external dependencies.

///|
/// Newton-iteration square root (avoids relying on math library availability
/// across all backends).
fn dsqrt(x : Double) -> Double {
  if x <= 0.0 {
    return 0.0
  }
  let mut r = if x < 1.0 { 1.0 } else { x }
  // A few Newton rounds converge well enough for geometry use.
  for _i = 0; _i < 40; _i = _i + 1 {
    r = 0.5 * (r + x / r)
  }
  r
}

///|
fn dabs(x : Double) -> Double {
  if x < 0.0 {
    -x
  } else {
    x
  }
}

///|
/// Otsu global threshold from a 256-bin grayscale histogram.
/// Returns t such that pixel < t is dark; None when the image is
/// degenerate (all pixels share one value).
fn otsu_threshold(hist : FixedArray[Int32]) -> Int32? {
  let mut total = 0
  for i = 0; i < 256; i = i + 1 {
    total = total + hist[i]
  }
  if total == 0 {
    return None
  }
  let mut present = 0
  for i = 0; i < 256; i = i + 1 {
    if hist[i] > 0 {
      present = present + 1
    }
  }
  if present <= 1 {
    return None
  }
  let mut sum_all : Int32 = 0
  for i = 0; i < 256; i = i + 1 {
    sum_all = sum_all + hist[i] * i
  }
  let mut w_b : Int32 = 0
  let mut sum_b : Int32 = 0
  let mut best_var : Double = -1.0
  let mut best_t : Int32 = 0
  for t = 0; t < 256; t = t + 1 {
    w_b = w_b + hist[t]
    if w_b == 0 {
      continue
    }
    let w_f = total - w_b
    if w_f == 0 {
      break
    }
    sum_b = sum_b + hist[t] * t
    let mu_b = sum_b.to_double() / w_b.to_double()
    let mu_f = (sum_all - sum_b).to_double() / w_f.to_double()
    let diff = mu_b - mu_f
    let var_between = w_b.to_double() * w_f.to_double() * diff * diff
    if var_between > best_var {
      best_var = var_between
      best_t = t
    }
  }
  Some(best_t + 1)
}

///|
/// Binarize a grayscale bitmap with Otsu threshold.
/// gray values: 0 (black) .. 255 (white). Returns None for degenerate
/// images (empty, or a single gray level everywhere).
pub fn binarize_bitmap(
  gray : FixedArray[FixedArray[Int32]],
) -> FixedArray[FixedArray[Bool]]? {
  let height = gray.length()
  if height == 0 || gray[0].length() == 0 {
    return None
  }
  let width = gray[0].length()
  let hist : FixedArray[Int32] = FixedArray::make(256, 0)
  for y = 0; y < height; y = y + 1 {
    if gray[y].length() != width {
      return None
    }
    for x = 0; x < width; x = x + 1 {
      let v = gray[y][x]
      let b = if v < 0 { 0 } else if v > 255 { 255 } else { v }
      hist[b] = hist[b] + 1
    }
  }
  let t = match otsu_threshold(hist) {
    Some(v) => v
    None => return None
  }
  let bits : FixedArray[FixedArray[Bool]] = FixedArray::make(
    height,
    FixedArray::make(width, false),
  )
  for y = 0; y < height; y = y + 1 {
    bits[y] = FixedArray::make(width, false)
    for x = 0; x < width; x = x + 1 {
      bits[y][x] = gray[y][x] < t
    }
  }
  Some(bits)
}

///|
/// A 1:1:3:1:1 run-pattern hit found while scanning one line.
priv struct RunHit {
  center : Double // center coordinate along the scan axis (pixels)
  unit_px : Double // estimated pixels-per-module (dark center run / 3)
}

///|
/// Run-length encode one row (axis=0, fixed y) or column (axis=1, fixed x).
/// Returns (is_dark, run_len, run_start) with one entry per run.
fn rle_line(
  bits : FixedArray[FixedArray[Bool]],
  fixed : Int32,
  axis : Int32,
) -> (Array[Bool], Array[Int32], Array[Int32]) {
  let run_dark : Array[Bool] = []
  let run_len : Array[Int32] = []
  let run_start : Array[Int32] = []
  let len = if axis == 0 { bits[0].length() } else { bits.length() }
  if len <= 0 {
    return (run_dark, run_len, run_start)
  }
  let pixel_at = fn(k : Int32) -> Bool {
    if axis == 0 {
      bits[fixed][k]
    } else {
      bits[k][fixed]
    }
  }
  let mut cur = pixel_at(0)
  let mut n = 1
  for k = 1; k < len; k = k + 1 {
    let d = pixel_at(k)
    if d == cur {
      n = n + 1
    } else {
      run_dark.push(cur)
      run_len.push(n)
      run_start.push(k - n)
      cur = d
      n = 1
    }
  }
  run_dark.push(cur)
  run_len.push(n)
  run_start.push(len - n)
  (run_dark, run_len, run_start)
}

///|
/// Scan one row (axis=0, fixed y) or one column (axis=1, fixed x) of a
/// binary bitmap for dark:light:dark:light:dark runs matching the 1:1:3:1:1
/// finder ratio (tolerance 0.5 module). Returns hits centered on the
/// middle dark run.
fn scan_line_hits(
  bits : FixedArray[FixedArray[Bool]],
  fixed : Int32,
  axis : Int32,
) -> Array[RunHit] {
  let hits : Array[RunHit] = []
  let (run_dark, run_len, run_start) = rle_line(bits, fixed, axis)
  let total_runs = run_dark.length()
  if total_runs < 5 {
    return hits
  }
  for i = 0; i + 4 < total_runs; i = i + 1 {
    if !(run_dark[i] &&
      !run_dark[i + 1] &&
      run_dark[i + 2] &&
      !run_dark[i + 3] &&
      run_dark[i + 4]) {
      continue
    }
    let r1 = run_len[i].to_double()
    let r2 = run_len[i + 1].to_double()
    let r3 = run_len[i + 2].to_double()
    let r4 = run_len[i + 3].to_double()
    let r5 = run_len[i + 4].to_double()
    if r2 <= 0.0 || r3 <= 0.0 || r4 <= 0.0 || r5 <= 0.0 {
      continue
    }
    // Estimate pixels-per-module from the full 7-module width
    // (total/7). Deriving it from r3 alone would make the r3 check
    // self-consistent and let wrong ratios (e.g. 1:1:5:1:1) pass.
    let total = r1 + r2 + r3 + r4 + r5
    let unit = total / 7.0
    if unit < 1.0 {
      continue
    }
    let tol = 0.5 * unit
    let ok = dabs(r1 - unit) <= tol &&
      dabs(r2 - unit) <= tol &&
      dabs(r3 - 3.0 * unit) <= tol &&
      dabs(r4 - unit) <= tol &&
      dabs(r5 - unit) <= tol
    if ok {
      let center = run_start[i + 2].to_double() + r3 / 2.0
      hits.push({ center, unit_px: unit, })
    }
  }
  hits
}

///|
/// Scan one line for the alignment-pattern profile 1:1:1:1:1
/// (five equal runs). Returns hits centered on the middle dark run.
/// Finder rows are 1:1:3:1:1 so they never match this profile.
fn scan_alignment_hits(
  bits : FixedArray[FixedArray[Bool]],
  fixed : Int32,
  axis : Int32,
) -> Array[RunHit] {
  let hits : Array[RunHit] = []
  let (run_dark, run_len, run_start) = rle_line(bits, fixed, axis)
  let total_runs = run_dark.length()
  if total_runs < 5 {
    return hits
  }
  for i = 0; i + 4 < total_runs; i = i + 1 {
    if !(run_dark[i] &&
      !run_dark[i + 1] &&
      run_dark[i + 2] &&
      !run_dark[i + 3] &&
      run_dark[i + 4]) {
      continue
    }
    let r1 = run_len[i].to_double()
    let r2 = run_len[i + 1].to_double()
    let r3 = run_len[i + 2].to_double()
    let r4 = run_len[i + 3].to_double()
    let r5 = run_len[i + 4].to_double()
    if r2 <= 0.0 || r3 <= 0.0 || r4 <= 0.0 || r5 <= 0.0 {
      continue
    }
    let total = r1 + r2 + r3 + r4 + r5
    let unit = total / 5.0
    if unit < 1.0 {
      continue
    }
    let tol = 0.4 * unit
    let ok = dabs(r1 - unit) <= tol &&
      dabs(r2 - unit) <= tol &&
      dabs(r3 - unit) <= tol &&
      dabs(r4 - unit) <= tol &&
      dabs(r5 - unit) <= tol
    if ok {
      let center = run_start[i + 2].to_double() + r3 / 2.0
      hits.push({ center, unit_px: unit, })
    }
  }
  hits
}

///|
/// A localized finder-pattern candidate (image coordinates).
priv struct FinderPoint {
  cx : Double
  cy : Double
  unit_px : Double
}

///|
/// Find finder-pattern candidates by scanning rows and columns for
/// 1:1:3:1:1 patterns and cross-matching row hits with column hits.
/// Candidates closer than half a module to each other are merged.
fn find_finder_candidates(
  bits : FixedArray[FixedArray[Bool]],
) -> Array[FinderPoint] {
  let height = bits.length()
  let width = bits[0].length()
  let row_hits : Array[(Int32, RunHit)] = []
  for y = 0; y < height; y = y + 1 {
    for h in scan_line_hits(bits, y, 0) {
      row_hits.push((y, h))
    }
  }
  let col_hits : Array[(Int32, RunHit)] = []
  for x = 0; x < width; x = x + 1 {
    for h in scan_line_hits(bits, x, 1) {
      col_hits.push((x, h))
    }
  }
  // Cross-match: row hit at (center_x, y) vs column hit at (x, center_y)
  // pair up when they agree on both coordinates.
  let raw : Array[FinderPoint] = []
  for (y, rh) in row_hits {
    for (x, ch) in col_hits {
      let tol = 2.0 * rh.unit_px
      if dabs(rh.center - x.to_double()) <= tol &&
        dabs(ch.center - y.to_double()) <= tol {
        raw.push({
          cx: rh.center,
          cy: ch.center,
          unit_px: (rh.unit_px + ch.unit_px) / 2.0,
        })
      }
    }
  }
  // Merge near-duplicate candidates.
  let merged : Array[FinderPoint] = []
  for p in raw {
    let mut dup = false
    for q in merged {
      let d = dsqrt(
        (p.cx - q.cx) * (p.cx - q.cx) + (p.cy - q.cy) * (p.cy - q.cy),
      )
      if d < p.unit_px * 1.5 {
        dup = true
        break
      }
    }
    if !dup {
      merged.push(p)
    }
  }
  merged
}

///|
/// Distance between two finder points.
fn fdist(a : FinderPoint, b : FinderPoint) -> Double {
  dsqrt((a.cx - b.cx) * (a.cx - b.cx) + (a.cy - b.cy) * (a.cy - b.cy))
}

///|
/// Estimate the QR module-array size from three finder centers.
/// Returns None when the geometry is inconsistent or the derived size
/// is not a legal QR side length (4k+17).
fn estimate_size(
  tl : FinderPoint,
  tr : FinderPoint,
  bl : FinderPoint,
) -> Int32? {
  let d_tr = fdist(tl, tr)
  let d_bl = fdist(tl, bl)
  if d_tr <= 0.0 || d_bl <= 0.0 {
    return None
  }
  // Reject badly skewed triangles: the two legs must be near-equal.
  if dabs(d_tr - d_bl) / d_tr > 0.25 {
    return None
  }
  let unit_est = (tl.unit_px + tr.unit_px + bl.unit_px) / 3.0
  if unit_est <= 0.0 {
    return None
  }
  let size = ((d_tr + d_bl) / 2.0 / unit_est + 7.0 + 0.5).to_int()
  if size < 21 || size > 177 || (size - 17) % 4 != 0 {
    return None
  }
  Some(size)
}

///|
/// Majority vote over a 3x3 pixel neighborhood centered on (px, py):
/// returns 1 when more than half the sampled pixels are dark.
fn sample_vote(
  bits : FixedArray[FixedArray[Bool]],
  px : Double,
  py : Double,
  width : Int32,
  height : Int32,
) -> Int32 {
  let mut dark_cnt = 0
  let mut tot = 0
  let xi = px.to_int()
  let yi = py.to_int()
  for dy = -1; dy <= 1; dy = dy + 1 {
    let yy = yi + dy
    if yy < 0 || yy >= height {
      continue
    }
    for dx = -1; dx <= 1; dx = dx + 1 {
      let xx = xi + dx
      if xx < 0 || xx >= width {
        continue
      }
      tot = tot + 1
      if bits[yy][xx] {
        dark_cnt = dark_cnt + 1
      }
    }
  }
  if tot > 0 && dark_cnt * 2 > tot {
    1
  } else {
    0
  }
}

///|
/// Map module coordinates (u, v) to pixel coordinates via the affine
/// basis defined by the three finder centers.
fn affine_map(
  tl : FinderPoint,
  tr : FinderPoint,
  bl : FinderPoint,
  size : Int32,
  u : Double,
  v : Double,
) -> (Double, Double) {
  let span = size.to_double() - 7.0
  let fi = (u - 3.5) / span
  let fj = (v - 3.5) / span
  (
    tl.cx + (tr.cx - tl.cx) * fi + (bl.cx - tl.cx) * fj,
    tl.cy + (tr.cy - tl.cy) * fi + (bl.cy - tl.cy) * fj,
  )
}

///|
/// Sample the module matrix from a binary bitmap using three finder
/// centers (top-left, top-right, bottom-left). The module size and QR
/// size are derived from the geometry; each module is sampled with a
/// majority vote over a small pixel neighborhood.
fn sample_matrix(
  bits : FixedArray[FixedArray[Bool]],
  tl : FinderPoint,
  tr : FinderPoint,
  bl : FinderPoint,
) -> FixedArray[FixedArray[Int32]]? {
  let height = bits.length()
  let width = bits[0].length()
  let size = match estimate_size(tl, tr, bl) {
    Some(s) => s
    None => return None
  }
  // Sample each module center via affine mapping from finder centers.
  // Module index i occupies [i, i+1); its center is at module coord
  // i+0.5, which is exactly what affine_map expects.
  let mat : FixedArray[FixedArray[Int32]] = FixedArray::make(
    size,
    FixedArray::make(size, 0),
  )
  for j = 0; j < size; j = j + 1 {
    mat[j] = FixedArray::make(size, 0)
    for i = 0; i < size; i = i + 1 {
      let (px, py) = affine_map(
        tl,
        tr,
        bl,
        size,
        i.to_double() + 0.5,
        j.to_double() + 0.5,
      )
      mat[j][i] = sample_vote(bits, px, py, width, height)
    }
  }
  Some(mat)
}

///|
/// Solve an 8x8 linear system by Gaussian elimination with partial
/// pivoting. Returns None when the matrix is singular.
fn solve_linear_8(
  a : FixedArray[FixedArray[Double]],
  b : FixedArray[Double],
) -> FixedArray[Double]? {
  let n = 8
  for col = 0; col < n; col = col + 1 {
    let mut piv = col
    let mut best = dabs(a[col][col])
    for r = col + 1; r < n; r = r + 1 {
      let v = dabs(a[r][col])
      if v > best {
        best = v
        piv = r
      }
    }
    if best < 1.0e-12 {
      return None
    }
    if piv != col {
      let tmp = a[col]
      a[col] = a[piv]
      a[piv] = tmp
      let tb = b[col]
      b[col] = b[piv]
      b[piv] = tb
    }
    let d = a[col][col]
    for r = col + 1; r < n; r = r + 1 {
      let f = a[r][col] / d
      if f != 0.0 {
        for c = col; c < n; c = c + 1 {
          a[r][c] = a[r][c] - f * a[col][c]
        }
        b[r] = b[r] - f * b[col]
      }
    }
  }
  let x = FixedArray::make(n, 0.0)
  for i = n - 1; i >= 0; i = i - 1 {
    let mut s = b[i]
    for j = i + 1; j < n; j = j + 1 {
      s = s - a[i][j] * x[j]
    }
    if dabs(a[i][i]) < 1.0e-12 {
      return None
    }
    x[i] = s / a[i][i]
  }
  Some(x)
}

///|
/// Solve the perspective homography (module coords -> image coords) from
/// four point correspondences. Returns [a,b,c,d,e,f,g,h] such that
///   x = (a*u + b*v + c) / (g*u + h*v + 1)
///   y = (d*u + e*v + f) / (g*u + h*v + 1)
fn solve_homography(
  us : FixedArray[Double],
  vs : FixedArray[Double],
  xs : FixedArray[Double],
  ys : FixedArray[Double],
) -> FixedArray[Double]? {
  let a : FixedArray[FixedArray[Double]] = FixedArray::make(
    8,
    FixedArray::make(8, 0.0),
  )
  for i = 0; i < 8; i = i + 1 {
    a[i] = FixedArray::make(8, 0.0)
  }
  let b = FixedArray::make(8, 0.0)
  for i = 0; i < 4; i = i + 1 {
    let u = us[i]
    let v = vs[i]
    let x = xs[i]
    let y = ys[i]
    a[i * 2][0] = u
    a[i * 2][1] = v
    a[i * 2][2] = 1.0
    a[i * 2][6] = -u * x
    a[i * 2][7] = -v * x
    b[i * 2] = x
    a[i * 2 + 1][3] = u
    a[i * 2 + 1][4] = v
    a[i * 2 + 1][5] = 1.0
    a[i * 2 + 1][6] = -u * y
    a[i * 2 + 1][7] = -v * y
    b[i * 2 + 1] = y
  }
  solve_linear_8(a, b)
}

///|
/// Sample the module matrix through a perspective homography.
fn sample_matrix_homography(
  bits : FixedArray[FixedArray[Bool]],
  h : FixedArray[Double],
  size : Int32,
) -> FixedArray[FixedArray[Int32]] {
  let height = bits.length()
  let width = bits[0].length()
  let mat : FixedArray[FixedArray[Int32]] = FixedArray::make(
    size,
    FixedArray::make(size, 0),
  )
  for j = 0; j < size; j = j + 1 {
    mat[j] = FixedArray::make(size, 0)
    let v = j.to_double() + 0.5
    for i = 0; i < size; i = i + 1 {
      let u = i.to_double() + 0.5
      let den = h[6] * u + h[7] * v + 1.0
      let px = if dabs(den) < 1.0e-9 {
        -1.0
      } else {
        (h[0] * u + h[1] * v + h[2]) / den
      }
      let py = if dabs(den) < 1.0e-9 {
        -1.0
      } else {
        (h[3] * u + h[4] * v + h[5]) / den
      }
      mat[j][i] = sample_vote(bits, px, py, width, height)
    }
  }
  mat
}

///|
/// Find an alignment-pattern center near an affine-predicted image
/// position. Scans a local window for 1:1:1:1:1 profiles and cross-matches
/// rows against columns, returning the closest hit.
fn find_alignment_point(
  bits : FixedArray[FixedArray[Bool]],
  expected_x : Double,
  expected_y : Double,
  radius : Double,
) -> (Double, Double)? {
  let height = bits.length()
  let width = bits[0].length()
  let r = radius.to_int()
  if r < 1 {
    return None
  }
  let ey = expected_y.to_int()
  let ex = expected_x.to_int()
  let y0 = if ey - r < 0 { 0 } else { ey - r }
  let y1 = if ey + r >= height { height - 1 } else { ey + r }
  let x0 = if ex - r < 0 { 0 } else { ex - r }
  let x1 = if ex + r >= width { width - 1 } else { ex + r }
  let rows : Array[(Int32, RunHit)] = []
  for y = y0; y <= y1; y = y + 1 {
    for h in scan_alignment_hits(bits, y, 0) {
      if dabs(h.center - expected_x) <= radius {
        rows.push((y, h))
      }
    }
  }
  let cols : Array[(Int32, RunHit)] = []
  for x = x0; x <= x1; x = x + 1 {
    for h in scan_alignment_hits(bits, x, 1) {
      if dabs(h.center - expected_y) <= radius {
        cols.push((x, h))
      }
    }
  }
  let mut best : (Double, Double)? = None
  let mut best_d = 1.0e18
  for (ry, rh) in rows {
    for (cx, ch) in cols {
      let tol = 2.0 * rh.unit_px
      if dabs(rh.center - cx.to_double()) <= tol &&
        dabs(ch.center - ry.to_double()) <= tol {
        let dx = rh.center - expected_x
        let dy = ch.center - expected_y
        let d = dx * dx + dy * dy
        if d < best_d {
          best_d = d
          best = Some((rh.center, ch.center))
        }
      }
    }
  }
  best
}

///|
/// Rotate a square matrix 90 degrees clockwise.
fn rotate_matrix_cw(
  m : FixedArray[FixedArray[Int32]],
) -> FixedArray[FixedArray[Int32]] {
  let size = m.length()
  let out : FixedArray[FixedArray[Int32]] = FixedArray::make(
    size,
    FixedArray::make(size, 0),
  )
  for y = 0; y < size; y = y + 1 {
    out[y] = FixedArray::make(size, 0)
    for x = 0; x < size; x = x + 1 {
      out[y][x] = m[size - 1 - x][y]
    }
  }
  out
}

///|
/// Perspective fallback: use the bottom-right alignment pattern as a
/// fourth reference point and re-sample through a homography. Returns
/// the decoded payload, or None when no alignment pattern is found or
/// the matrix still does not decode.
fn try_decode_perspective(
  bits : FixedArray[FixedArray[Bool]],
  tl : FinderPoint,
  tr : FinderPoint,
  bl : FinderPoint,
) -> FixedArray[Int32]? {
  let size = match estimate_size(tl, tr, bl) {
    Some(s) => s
    None => return None
  }
  let version = (size - 17) / 4
  if version < 2 {
    // V1 has no alignment pattern: affine is the only model available.
    return None
  }
  let apos = alignment_pattern_positions(version)
  if apos.length() == 0 {
    return None
  }
  let last = apos[apos.length() - 1]
  // Alignment center sits at module coord (index + 0.5).
  let au = last.to_double() + 0.5
  let av = last.to_double() + 0.5
  let (ex, ey) = affine_map(tl, tr, bl, size, au, av)
  let unit = (tl.unit_px + tr.unit_px + bl.unit_px) / 3.0
  if unit <= 0.0 {
    return None
  }
  // Search a generous window: under perspective the affine prediction
  // can be off by several modules.
  let radius = 6.0 * unit
  let (ax, ay) = match find_alignment_point(bits, ex, ey, radius) {
    Some(p) => p
    None => return None
  }
  let us = FixedArray::make(4, 0.0)
  let vs = FixedArray::make(4, 0.0)
  let xs = FixedArray::make(4, 0.0)
  let ys = FixedArray::make(4, 0.0)
  let sz = size.to_double()
  us[0] = 3.5
  vs[0] = 3.5
  xs[0] = tl.cx
  ys[0] = tl.cy
  us[1] = sz - 3.5
  vs[1] = 3.5
  xs[1] = tr.cx
  ys[1] = tr.cy
  us[2] = 3.5
  vs[2] = sz - 3.5
  xs[2] = bl.cx
  ys[2] = bl.cy
  us[3] = au
  vs[3] = av
  xs[3] = ax
  ys[3] = ay
  let h = match solve_homography(us, vs, xs, ys) {
    Some(v) => v
    None => return None
  }
  let mat = sample_matrix_homography(bits, h, size)
  let mut m = mat
  for _r = 0; _r < 4; _r = _r + 1 {
    match decode_qr(m) {
      Some(payload) => return Some(payload)
      None => m = rotate_matrix_cw(m)
    }
  }
  None
}

///|
/// Decode a QR code directly from grayscale pixels (screenshot-like input).
/// Pipeline: Otsu binarization -> finder localization -> affine module
/// resampling -> decode_qr with 4-rotation retry; if the affine model
/// fails, retry through a perspective homography anchored on the
/// bottom-right alignment pattern. Returns the original byte payload,
/// or None if the image does not contain a decodable QR code.
pub fn decode_from_pixels(
  gray : FixedArray[FixedArray[Int32]],
) -> FixedArray[Int32]? {
  let bits = match binarize_bitmap(gray) {
    Some(b) => b
    None => return None
  }
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
