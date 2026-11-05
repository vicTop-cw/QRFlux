/// Image content correctness tests: parse PBM/SVG/PNG output and verify
/// that pixel values match QR modules (not just format signatures).
/// Covers to_pbm, to_svg, to_png, color_qr_to_svg, color_qr_to_ppm.

///|
/// Count non-overlapping occurrences of `sub` in `s`.
fn count_substring(s : String, sub : String) -> Int32 {
  s.split(sub.to_string_view()).count() - 1
}

///|
/// Parse PBM (P1 ASCII) pixel data into a flat row-major array.
/// Skips the "P1\n<w> <h>\n" header (first 2 newlines), then collects
/// every '0' or '1' character as a pixel value.
fn pbm_pixels(pbm : String) -> Array[Int32] {
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
/// Verify PBM content matches QR modules with quiet-zone offset.
/// PBM: 1 = black (dark module), 0 = white (light/quiet zone).
fn pbm_matches_qr(qr : @qr.QrCode, pbm : String, quiet : Int32) -> Bool {
  let size = qr.size()
  let total = size + quiet * 2
  let pixels = pbm_pixels(pbm)
  if pixels.length() != total * total {
    return false
  }
  for y = 0; y < total; y = y + 1 {
    for x = 0; x < total; x = x + 1 {
      let idx = y * total + x
      let dark = if x < quiet ||
        x >= quiet + size ||
        y < quiet ||
        y >= quiet + size {
        false
      } else {
        qr.get_module(x - quiet, y - quiet)
      }
      let expected = if dark { 1 } else { 0 }
      if pixels[idx] != expected {
        return false
      }
    }
  }
  true
}

///|
test "image content: pbm content matches qr modules" {
  // V1: parse PBM and verify every pixel matches qr.get_module (with offset).
  let data = FixedArray::make(5, 0x41)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let pbm = @qr.to_pbm(qr, 4)
  assert_true(pbm_matches_qr(qr, pbm, 4))
}

///|
test "image content: pbm content v5" {
  // V5: parse PBM and verify every pixel matches qr.get_module (with offset).
  let data = FixedArray::make(50, 0x42)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 5)
  let pbm = @qr.to_pbm(qr, 2)
  assert_true(pbm_matches_qr(qr, pbm, 2))
}

///|
test "image content: pbm content size correct" {
  // PBM header declares (size + 2*quiet) x (size + 2*quiet); pixel count matches.
  let data = FixedArray::make(5, 0x41)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let quiet = 4
  let pbm = @qr.to_pbm(qr, quiet)
  let total = qr.size() + quiet * 2
  let expected_header = "P1\n" +
    total.to_string() +
    " " +
    total.to_string() +
    "\n"
  assert_true(pbm.contains(expected_header))
  let pixels = pbm_pixels(pbm)
  assert_true(pixels.length() == total * total)
}

///|
test "image content: pbm content quiet zone white" {
  // All quiet-zone pixels (border) must be 0 (white).
  let data = FixedArray::make(5, 0x41)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let quiet = 4
  let pbm = @qr.to_pbm(qr, quiet)
  let size = qr.size()
  let total = size + quiet * 2
  let pixels = pbm_pixels(pbm)
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
test "image content: svg content rect count" {
  // to_svg emits 1 background white rect + 1 black rect per dark module.
  let data = FixedArray::make(5, 0x41)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let svg = @qr.to_svg(qr, 1, 4)
  let size = qr.size()
  let mut dark_count = 0
  for y = 0; y < size; y = y + 1 {
    for x = 0; x < size; x = x + 1 {
      if qr.get_module(x, y) {
        dark_count = dark_count + 1
      }
    }
  }
  let rect_count = count_substring(svg, "<rect")
  assert_true(rect_count == dark_count + 1)
}

///|
test "image content: svg content v1 module colors" {
  // SVG contains both black (dark modules) and white (background) fills.
  let data = FixedArray::make(5, 0x41)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let svg = @qr.to_svg(qr, 1, 4)
  assert_true(svg.contains("fill=\"black\""))
  assert_true(svg.contains("fill=\"white\""))
}

///|
test "image content: svg content dimensions" {
  // SVG width/height == (size + 2*quiet) * scale.
  let data = FixedArray::make(5, 0x41)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let quiet = 4
  let scale = 3
  let svg = @qr.to_svg(qr, scale, quiet)
  let total = qr.size() + quiet * 2
  let dim = total * scale
  assert_true(svg.contains("width=\"" + dim.to_string() + "\""))
  assert_true(svg.contains("height=\"" + dim.to_string() + "\""))
}

///|
test "image content: png content ihdr dimensions" {
  // IHDR width (bytes 16-19 BE) and height (bytes 20-23 BE) == total.
  let data = FixedArray::make(5, 0x41)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let quiet = 4
  let png = @qr.to_png(qr, 1, quiet)
  let total = qr.size() + quiet * 2
  let width = (png[16] << 24) | (png[17] << 16) | (png[18] << 8) | png[19]
  let height = (png[20] << 24) | (png[21] << 16) | (png[22] << 8) | png[23]
  assert_true(width == total)
  assert_true(height == total)
}

///|
test "image content: png content bit depth 1" {
  // IHDR bit depth (byte 24) == 1 (bit-packed grayscale).
  let data = FixedArray::make(5, 0x41)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let png = @qr.to_png(qr, 1, 4)
  assert_true(png[24] == 1)
}

///|
test "image content: png content color type 0" {
  // IHDR color type (byte 25) == 0 (grayscale).
  let data = FixedArray::make(5, 0x41)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let png = @qr.to_png(qr, 1, 4)
  assert_true(png[25] == 0)
}

///|
test "image content: color svg content has rects" {
  // color_qr_to_svg output contains at least one <rect>.
  let encoder = @qr.ColorQREncoder::new(1)
  let data = FixedArray::make(4, 0x42)
  let matrix = encoder.encode(data)
  let svg = @qr.color_qr_to_svg(matrix, 1, 4)
  let rect_count = count_substring(svg, "<rect")
  assert_true(rect_count > 0)
}

///|
test "image content: color ppm content header" {
  // color_qr_to_ppm uses P3 (ASCII PPM) format.
  let encoder = @qr.ColorQREncoder::new(1)
  let data = FixedArray::make(4, 0x42)
  let matrix = encoder.encode(data)
  let ppm = @qr.color_qr_to_ppm(matrix, 4)
  assert_true(ppm.has_prefix("P3"))
}
