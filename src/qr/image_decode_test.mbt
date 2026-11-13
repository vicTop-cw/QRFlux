/// Tests for the image-pipeline decoder: QR -> grayscale pixels
/// (scaled / shifted / noisy / rotated) -> decode_from_pixels round-trip.
/// These tests exercise the real-screenshot entry that decode_qr alone
/// cannot cover.

///|
/// Helper: assert decoded payload equals expected (labelled abort on diff).
fn img_assert_payload_eq(
  decoded : FixedArray[Int32]?,
  expected : FixedArray[Int32],
  label : String,
) -> Unit {
  match decoded {
    Some(d) =>
      if d.length() != expected.length() {
        abort(
          "image decode \{label}: length mismatch: got \{d.length()}, want \{expected.length()}",
        )
      } else {
        for i = 0; i < expected.length(); i = i + 1 {
          if d[i] != expected[i] {
            abort(
              "image decode \{label}: byte \{i} mismatch: got \{d[i]}, want \{expected[i]}",
            )
          }
        }
      }
    None => abort("image decode \{label}: returned None")
  }
}

///|
/// Helper: deterministic pseudo-random payload bytes.
fn img_random(n : Int32, seed : Int32) -> FixedArray[Int32] {
  let fa = FixedArray::make(n, 0)
  let mut s = seed
  for i = 0; i < n; i = i + 1 {
    s = (s * 1103515245 + 12345) & 0x7FFFFFFF
    fa[i] = (s >> 16) & 0xFF
  }
  fa
}

///|
/// Helper: literal payload bytes.
fn img_bytes(xs : Array[Int32]) -> FixedArray[Int32] {
  let fa = FixedArray::make(xs.length(), 0)
  for i = 0; i < xs.length(); i = i + 1 {
    fa[i] = xs[i]
  }
  fa
}

///|
/// Helper: QR code object -> 0/1 module matrix.
fn img_qr_to_matrix(qr : @qr.QrCode) -> FixedArray[FixedArray[Int32]] {
  let size = qr.size()
  let m = FixedArray::make(size, FixedArray::make(size, 0))
  for y = 0; y < size; y = y + 1 {
    m[y] = FixedArray::make(size, 0)
    for x = 0; x < size; x = x + 1 {
      m[y][x] = if qr.get_module(x, y) { 1 } else { 0 }
    }
  }
  m
}

///|
/// Helper: render a module matrix to a grayscale bitmap (screenshot-like).
/// Each module becomes scale x scale pixels; quiet-zone border added.
fn img_render_gray(
  m : FixedArray[FixedArray[Int32]],
  scale : Int32,
  quiet : Int32,
  dark_val : Int32,
  light_val : Int32,
) -> FixedArray[FixedArray[Int32]] {
  let size = m.length()
  let dim = (size + quiet * 2) * scale
  let g : FixedArray[FixedArray[Int32]] = FixedArray::make(
    dim,
    FixedArray::make(dim, light_val),
  )
  for y = 0; y < dim; y = y + 1 {
    g[y] = FixedArray::make(dim, light_val)
    let my = y / scale - quiet
    for x = 0; x < dim; x = x + 1 {
      let mx = x / scale - quiet
      if mx >= 0 && mx < size && my >= 0 && my < size && m[my][mx] == 1 {
        g[y][x] = dark_val
      }
    }
  }
  g
}

///|
/// Helper: shift the QR content inside a larger white canvas
/// (simulates a screenshot with the code not at the exact origin).
fn img_shift_gray(
  g : FixedArray[FixedArray[Int32]],
  dx : Int32,
  dy : Int32,
) -> FixedArray[FixedArray[Int32]] {
  let dim = g.length()
  let ndim_x = dim + dx
  let ndim_y = dim + dy
  let out : FixedArray[FixedArray[Int32]] = FixedArray::make(
    ndim_y,
    FixedArray::make(ndim_x, 255),
  )
  for y = 0; y < ndim_y; y = y + 1 {
    out[y] = FixedArray::make(ndim_x, 255)
    for x = 0; x < ndim_x; x = x + 1 {
      let sx = x - dx
      let sy = y - dy
      if sx >= 0 && sx < dim && sy >= 0 && sy < dim {
        out[y][x] = g[sy][sx]
      }
    }
  }
  out
}

///|
/// Helper: add deterministic gray noise (±amp) to every pixel.
/// Handles non-square bitmaps (e.g. after a shift).
fn img_add_noise(
  g : FixedArray[FixedArray[Int32]],
  amp : Int32,
  seed : Int32,
) -> FixedArray[FixedArray[Int32]] {
  let rows = g.length()
  let out : FixedArray[FixedArray[Int32]] = FixedArray::make(
    rows,
    FixedArray::make(0, 0),
  )
  let mut s = seed
  for y = 0; y < rows; y = y + 1 {
    let cols = g[y].length()
    out[y] = FixedArray::make(cols, 0)
    for x = 0; x < cols; x = x + 1 {
      s = (s * 1103515245 + 12345) & 0x7FFFFFFF
      let n = ((s >> 16) & 0xFFFF) % (amp * 2 + 1) - amp
      let v = g[y][x] + n
      out[y][x] = if v < 0 { 0 } else if v > 255 { 255 } else { v }
    }
  }
  out
}

///|
/// Helper: rotate a square grayscale bitmap 90 degrees clockwise.
fn img_rotate_gray_cw(
  g : FixedArray[FixedArray[Int32]],
) -> FixedArray[FixedArray[Int32]] {
  let dim = g.length()
  let out : FixedArray[FixedArray[Int32]] = FixedArray::make(
    dim,
    FixedArray::make(dim, 0),
  )
  for y = 0; y < dim; y = y + 1 {
    out[y] = FixedArray::make(dim, 0)
    for x = 0; x < dim; x = x + 1 {
      out[y][x] = g[dim - 1 - x][y]
    }
  }
  out
}

///|
test "image pipeline V1 Hello scale 8" {
  let data = img_bytes([72, 101, 108, 108, 111])
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let gray = img_render_gray(img_qr_to_matrix(qr), 8, 4, 0, 255)
  let decoded = @qr.decode_from_pixels(gray)
  img_assert_payload_eq(decoded, data, "V1 scale8")
}

///|
test "image pipeline V2 random 20B scale 6" {
  let data = img_random(20, 42)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 2)
  let gray = img_render_gray(img_qr_to_matrix(qr), 6, 4, 0, 255)
  let decoded = @qr.decode_from_pixels(gray)
  img_assert_payload_eq(decoded, data, "V2 scale6")
}

///|
test "image pipeline V3 random 50B scale 4" {
  let data = img_random(50, 123)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 3)
  let gray = img_render_gray(img_qr_to_matrix(qr), 4, 4, 0, 255)
  let decoded = @qr.decode_from_pixels(gray)
  img_assert_payload_eq(decoded, data, "V3 scale4")
}

///|
test "image pipeline V5 random 100B scale 8" {
  let data = img_random(100, 7)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 5)
  let gray = img_render_gray(img_qr_to_matrix(qr), 8, 4, 0, 255)
  let decoded = @qr.decode_from_pixels(gray)
  img_assert_payload_eq(decoded, data, "V5 scale8")
}

///|
test "image pipeline shifted screenshot" {
  // QR not at image origin: remote screen, screenshot includes margins.
  let data = img_bytes([1, 2, 3, 4, 5, 6, 7, 8])
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let base = img_render_gray(img_qr_to_matrix(qr), 8, 4, 0, 255)
  let gray = img_shift_gray(base, 17, 9)
  let decoded = @qr.decode_from_pixels(gray)
  img_assert_payload_eq(decoded, data, "shifted")
}

///|
test "image pipeline with gray noise amp 60" {
  let data = img_random(20, 99)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 2)
  let base = img_render_gray(img_qr_to_matrix(qr), 8, 4, 0, 255)
  let gray = img_add_noise(base, 60, 777)
  let decoded = @qr.decode_from_pixels(gray)
  img_assert_payload_eq(decoded, data, "noise60")
}

///|
test "image pipeline shifted + noisy combined" {
  let data = img_bytes([200, 100, 50, 25, 12])
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let base = img_render_gray(img_qr_to_matrix(qr), 10, 4, 0, 255)
  let shifted = img_shift_gray(base, 23, 31)
  let gray = img_add_noise(shifted, 50, 2024)
  let decoded = @qr.decode_from_pixels(gray)
  img_assert_payload_eq(decoded, data, "shift+noise")
}

///|
test "image pipeline rotate 90" {
  let data = img_bytes([10, 20, 30, 40])
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let base = img_render_gray(img_qr_to_matrix(qr), 8, 4, 0, 255)
  let gray = img_rotate_gray_cw(base)
  let decoded = @qr.decode_from_pixels(gray)
  img_assert_payload_eq(decoded, data, "rot90")
}

///|
test "image pipeline rotate 180" {
  let data = img_bytes([11, 22, 33, 44])
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let base = img_render_gray(img_qr_to_matrix(qr), 8, 4, 0, 255)
  let gray = img_rotate_gray_cw(img_rotate_gray_cw(base))
  let decoded = @qr.decode_from_pixels(gray)
  img_assert_payload_eq(decoded, data, "rot180")
}

///|
test "image pipeline rotate 270" {
  let data = img_bytes([13, 23, 33, 43])
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let base = img_render_gray(img_qr_to_matrix(qr), 8, 4, 0, 255)
  let gray = img_rotate_gray_cw(img_rotate_gray_cw(img_rotate_gray_cw(base)))
  let decoded = @qr.decode_from_pixels(gray)
  img_assert_payload_eq(decoded, data, "rot270")
}

///|
test "image pipeline non-black-white grays (screenshot dim screen)" {
  // Real screenshots are never pure 0/255; use dark=45, light=210.
  let data = img_bytes([90, 80, 70])
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let gray = img_render_gray(img_qr_to_matrix(qr), 8, 4, 45, 210)
  let decoded = @qr.decode_from_pixels(gray)
  img_assert_payload_eq(decoded, data, "gray tones")
}

///|
test "binarize all-white image returns None" {
  let g = FixedArray::make(8, FixedArray::make(8, 255))
  assert_true(@qr.binarize_bitmap(g) is None)
}

///|
test "binarize all-black image returns None" {
  let g = FixedArray::make(8, FixedArray::make(8, 0))
  assert_true(@qr.binarize_bitmap(g) is None)
}

///|
test "binarize empty image returns None" {
  let g : FixedArray[FixedArray[Int32]] = FixedArray::make(
    0,
    FixedArray::make(0, 0),
  )
  assert_true(@qr.binarize_bitmap(g) is None)
}

///|
test "decode_from_pixels pure noise returns None" {
  let g = img_add_noise(
    FixedArray::make(64, FixedArray::make(64, 255)),
    120,
    555,
  )
  assert_true(@qr.decode_from_pixels(g) is None)
}

///|
/// Mechanism check: fill each finder pattern into a solid 7x7 black
/// block. No scan line through it can exhibit the 1:1:3:1:1 profile,
/// so localization must yield fewer than three finders and the decode
/// must fail. Locks the finder-shape gate: break the mechanism, red.
test "solid-block finder rejected" {
  let data = img_bytes([7, 7, 7])
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let m = img_qr_to_matrix(qr)
  let size = m.length()
  let corners = [(0, 0), (size - 7, 0), (0, size - 7)]
  for (ox, oy) in corners {
    for dy = 0; dy < 7; dy = dy + 1 {
      for dx = 0; dx < 7; dx = dx + 1 {
        m[oy + dy][ox + dx] = 1
      }
    }
  }
  let gray = img_render_gray(m, 8, 4, 0, 255)
  let decoded = @qr.decode_from_pixels(gray)
  assert_true(decoded is None)
}
