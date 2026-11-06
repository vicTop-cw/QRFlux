/// Image parameter boundary tests: quiet_zone and scale variations for
/// to_pbm, to_svg, to_png across V1/V10/V40.

///|
/// Parse PBM (P1 ASCII) pixel data into a flat row-major array.
/// Skips the "P1\n<w> <h>\n" header (first 2 newlines), then collects
/// every '0' or '1' character as a pixel value.
fn ip_pbm_pixels(pbm : String) -> Array[Int32] {
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
/// Count non-overlapping occurrences of `sub` in `s`.
fn ip_count_substring(s : String, sub : String) -> Int32 {
  s.split(sub.to_string_view()).count() - 1
}

///|
/// Extract PNG IHDR width (big-endian, bytes 16-19).
fn ip_png_width(png : FixedArray[Int32]) -> Int32 {
  (png[16] << 24) | (png[17] << 16) | (png[18] << 8) | png[19]
}

///|
/// Extract PNG IHDR height (big-endian, bytes 20-23).
fn ip_png_height(png : FixedArray[Int32]) -> Int32 {
  (png[20] << 24) | (png[21] << 16) | (png[22] << 8) | png[23]
}

///|
test "img params: pbm quiet zone 0" {
  let data = FixedArray::make(5, 0x41)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let pbm = @qr.to_pbm(qr, 0)
  let total = qr.size()
  let header = "P1\n" + total.to_string() + " " + total.to_string() + "\n"
  assert_true(pbm.contains(header))
}

///|
test "img params: pbm quiet zone 1" {
  let data = FixedArray::make(5, 0x41)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let pbm = @qr.to_pbm(qr, 1)
  let total = qr.size() + 2
  let header = "P1\n" + total.to_string() + " " + total.to_string() + "\n"
  assert_true(pbm.contains(header))
}

///|
test "img params: pbm quiet zone 4" {
  let data = FixedArray::make(5, 0x41)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let pbm = @qr.to_pbm(qr, 4)
  let total = qr.size() + 8
  let header = "P1\n" + total.to_string() + " " + total.to_string() + "\n"
  assert_true(pbm.contains(header))
}

///|
test "img params: pbm quiet zone 10" {
  let data = FixedArray::make(5, 0x41)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let pbm = @qr.to_pbm(qr, 10)
  let total = qr.size() + 20
  let header = "P1\n" + total.to_string() + " " + total.to_string() + "\n"
  assert_true(pbm.contains(header))
}

///|
test "img params: pbm quiet zone content" {
  let data = FixedArray::make(5, 0x41)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let size = qr.size()
  // quiet_zone=0: first pixel is QR (0,0) = finder corner = black (1)
  let pbm0 = @qr.to_pbm(qr, 0)
  let pixels0 = ip_pbm_pixels(pbm0)
  assert_true(pixels0.length() == size * size)
  assert_true(pixels0[0] == 1)
  // quiet_zone=4: first pixel is quiet zone = white (0)
  let pbm4 = @qr.to_pbm(qr, 4)
  let pixels4 = ip_pbm_pixels(pbm4)
  let total4 = size + 8
  assert_true(pixels4.length() == total4 * total4)
  assert_true(pixels4[0] == 0)
}

///|
test "img params: svg scale 1" {
  let data = FixedArray::make(5, 0x41)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let quiet = 4
  let scale = 1
  let svg = @qr.to_svg(qr, scale, quiet)
  let total = qr.size() + quiet * 2
  let dim = total * scale
  assert_true(svg.contains("width=\"" + dim.to_string() + "\""))
  assert_true(svg.contains("height=\"" + dim.to_string() + "\""))
}

///|
test "img params: svg scale 5" {
  let data = FixedArray::make(5, 0x41)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let quiet = 4
  let scale = 5
  let svg = @qr.to_svg(qr, scale, quiet)
  let total = qr.size() + quiet * 2
  let dim = total * scale
  assert_true(svg.contains("width=\"" + dim.to_string() + "\""))
  assert_true(svg.contains("height=\"" + dim.to_string() + "\""))
}

///|
test "img params: svg scale 20" {
  let data = FixedArray::make(5, 0x41)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let quiet = 4
  let scale = 20
  let svg = @qr.to_svg(qr, scale, quiet)
  let total = qr.size() + quiet * 2
  let dim = total * scale
  assert_true(svg.contains("width=\"" + dim.to_string() + "\""))
  assert_true(svg.contains("height=\"" + dim.to_string() + "\""))
}

///|
test "img params: png scale various" {
  let data = FixedArray::make(5, 0x41)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let quiet = 4
  let total = qr.size() + quiet * 2
  let scales = [1, 5, 10]
  for scale in scales {
    let png = @qr.to_png(qr, scale, quiet)
    let dim = total * scale
    assert_true(ip_png_width(png) == dim)
    assert_true(ip_png_height(png) == dim)
  }
}

///|
test "img params: pbm v1 v10 v40" {
  let data = FixedArray::make(5, 0x41)
  let versions = [1, 10, 40]
  for v in versions {
    let qr = @qr.encode_binary(data, @qr.ecc_low(), v)
    let pbm = @qr.to_pbm(qr, 4)
    let total = qr.size() + 8
    let header = "P1\n" + total.to_string() + " " + total.to_string() + "\n"
    assert_true(pbm.contains(header))
    assert_true(qr.version() == v)
  }
}

///|
test "img params: svg v1 v10 v40" {
  let data = FixedArray::make(5, 0x41)
  let versions = [1, 10, 40]
  for v in versions {
    let qr = @qr.encode_binary(data, @qr.ecc_low(), v)
    let scale = 2
    let quiet = 4
    let svg = @qr.to_svg(qr, scale, quiet)
    let total = qr.size() + quiet * 2
    let dim = total * scale
    assert_true(svg.contains("width=\"" + dim.to_string() + "\""))
    assert_true(svg.contains("height=\"" + dim.to_string() + "\""))
  }
}

///|
test "img params: png v1 v10 v40" {
  let data = FixedArray::make(5, 0x41)
  let versions = [1, 10, 40]
  for v in versions {
    let qr = @qr.encode_binary(data, @qr.ecc_low(), v)
    let png = @qr.to_png(qr, 1, 4)
    let total = qr.size() + 8
    assert_true(ip_png_width(png) == total)
    assert_true(ip_png_height(png) == total)
  }
}

///|
test "img params: quiet zone all white" {
  let data = FixedArray::make(5, 0x41)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let size = qr.size()
  for quiet = 0; quiet <= 6; quiet = quiet + 1 {
    let pbm = @qr.to_pbm(qr, quiet)
    let pixels = ip_pbm_pixels(pbm)
    let total = size + quiet * 2
    let mut all_white = true
    for y = 0; y < total; y = y + 1 {
      for x = 0; x < total; x = x + 1 {
        let in_quiet = x < quiet ||
          x >= quiet + size ||
          y < quiet ||
          y >= quiet + size
        if in_quiet {
          if pixels[y * total + x] != 0 {
            all_white = false
          }
        }
      }
    }
    assert_true(all_white)
  }
}

///|
test "img params: scale does not change content" {
  let data = FixedArray::make(5, 0x41)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let svg1 = @qr.to_svg(qr, 1, 4)
  let svg5 = @qr.to_svg(qr, 5, 4)
  // Black rect count identical: scale only resizes, does not add/remove modules.
  let count1 = ip_count_substring(svg1, "fill=\"black\"")
  let count5 = ip_count_substring(svg5, "fill=\"black\"")
  assert_true(count1 == count5)
  assert_true(count1 > 0)
}

///|
test "img params: pbm quiet zone 0 no border" {
  let data = FixedArray::make(5, 0x41)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let size = qr.size()
  let pbm = @qr.to_pbm(qr, 0)
  let pixels = ip_pbm_pixels(pbm)
  // quiet_zone=0: no white border; corner pixels are QR finder modules (black).
  let mut corner_has_black = false
  if pixels[0] == 1 {
    corner_has_black = true
  }
  if pixels[size - 1] == 1 {
    corner_has_black = true
  }
  if pixels[(size - 1) * size] == 1 {
    corner_has_black = true
  }
  if pixels[size * size - 1] == 1 {
    corner_has_black = true
  }
  assert_true(corner_has_black)
}
