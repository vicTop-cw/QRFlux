/// Image output boundary tests (blackbox): PBM/SVG/PNG output boundary
/// conditions across V1/V10/V40, scale extremes, multi-IDAT blocks, CRC
/// correctness, and three-format round-trip consistency.

///|
/// Count non-overlapping occurrences of `sub` in `s`.
fn iob_count(s : String, sub : String) -> Int32 {
  s.split(sub.to_string_view()).count() - 1
}

///|
/// Parse PBM (P1 ASCII) pixel data into a flat row-major array.
fn iob_pbm_pixels(pbm : String) -> Array[Int32] {
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
/// Extract PNG IHDR width (big-endian, bytes 16-19).
fn iob_png_width(png : FixedArray[Int32]) -> Int32 {
  (png[16] << 24) | (png[17] << 16) | (png[18] << 8) | png[19]
}

///|
/// Extract PNG IHDR height (big-endian, bytes 20-23).
fn iob_png_height(png : FixedArray[Int32]) -> Int32 {
  (png[20] << 24) | (png[21] << 16) | (png[22] << 8) | png[23]
}

///|
/// PNG CRC32 (same algorithm as the implementation under test).
fn iob_crc32(data : FixedArray[Int32]) -> Int32 {
  let mut crc : Int32 = 0xFFFFFFFF
  for i = 0; i < data.length(); i = i + 1 {
    crc = crc ^ data[i]
    for j = 0; j < 8; j = j + 1 {
      if (crc & 1) != 0 {
        crc = ((crc >> 1) & 0x7FFFFFFF) ^ 0xEDB88320
      } else {
        crc = (crc >> 1) & 0x7FFFFFFF
      }
    }
  }
  (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF
}

///|
/// Verify CRC of a PNG chunk starting at `offset`.
/// Chunk layout: len(4 BE) + type(4) + data(len) + crc(4 BE).
fn iob_chunk_crc_ok(png : FixedArray[Int32], offset : Int32) -> Bool {
  let len = (png[offset] << 24) |
    (png[offset + 1] << 16) |
    (png[offset + 2] << 8) |
    png[offset + 3]
  let crc_input = FixedArray::make(4 + len, 0)
  for i = 0; i < 4 + len; i = i + 1 {
    crc_input[i] = png[offset + 4 + i]
  }
  let expected = iob_crc32(crc_input)
  let crc_pos = offset + 8 + len
  let actual = (png[crc_pos] << 24) |
    (png[crc_pos + 1] << 16) |
    (png[crc_pos + 2] << 8) |
    png[crc_pos + 3]
  expected == actual
}

///|
/// Count deflate stored blocks in IDAT by parsing BFINAL flags.
fn iob_count_idat_blocks(png : FixedArray[Int32]) -> Int32 {
  let idat_len = (png[33] << 24) | (png[34] << 16) | (png[35] << 8) | png[36]
  let mut pos : Int32 = 43
  let idat_data_end = 41 + idat_len - 4
  let mut blocks = 0
  let mut done = false
  while pos < idat_data_end && !done {
    let bfinal = png[pos] & 1
    blocks = blocks + 1
    let len = png[pos + 1] | (png[pos + 2] << 8)
    pos = pos + 5 + len
    if bfinal == 1 {
      done = true
    }
  }
  blocks
}

///|
/// Count dark modules in a QR code.
fn iob_qr_dark_count(qr : @qr.QrCode) -> Int32 {
  let size = qr.size()
  let mut dark = 0
  for y = 0; y < size; y = y + 1 {
    for x = 0; x < size; x = x + 1 {
      if qr.get_module(x, y) {
        dark = dark + 1
      }
    }
  }
  dark
}

///|
test "iob pbm v1 boundary" {
  let data = FixedArray::make(5, 0x41)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let pbm = @qr.to_pbm(qr, 4)
  let total = qr.size() + 8
  assert_true(qr.version() == 1)
  let header = "P1\n" + total.to_string() + " " + total.to_string() + "\n"
  assert_true(pbm.contains(header))
  let pixels = iob_pbm_pixels(pbm)
  assert_true(pixels.length() == total * total)
}

///|
test "iob pbm v10 boundary" {
  let data = FixedArray::make(5, 0x41)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 10)
  let pbm = @qr.to_pbm(qr, 4)
  let total = qr.size() + 8
  assert_true(qr.version() == 10)
  let header = "P1\n" + total.to_string() + " " + total.to_string() + "\n"
  assert_true(pbm.contains(header))
  let pixels = iob_pbm_pixels(pbm)
  assert_true(pixels.length() == total * total)
}

///|
test "iob pbm v40 boundary" {
  let data = FixedArray::make(5, 0x41)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 40)
  let pbm = @qr.to_pbm(qr, 4)
  let total = qr.size() + 8
  assert_true(qr.version() == 40)
  let header = "P1\n" + total.to_string() + " " + total.to_string() + "\n"
  assert_true(pbm.contains(header))
  let pixels = iob_pbm_pixels(pbm)
  assert_true(pixels.length() == total * total)
}

///|
test "iob svg v1 boundary" {
  let data = FixedArray::make(5, 0x41)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let scale = 2
  let quiet = 4
  let svg = @qr.to_svg(qr, scale, quiet)
  let total = qr.size() + quiet * 2
  let dim = total * scale
  assert_true(svg.contains("<svg"))
  assert_true(svg.contains("</svg>"))
  assert_true(svg.contains("width=\"" + dim.to_string() + "\""))
  assert_true(svg.contains("height=\"" + dim.to_string() + "\""))
  let dark = iob_qr_dark_count(qr)
  let black_rects = iob_count(svg, "fill=\"black\"")
  assert_true(black_rects == dark)
  let total_rects = iob_count(svg, "<rect")
  assert_true(total_rects == dark + 1)
}

///|
test "iob svg v10 boundary" {
  let data = FixedArray::make(5, 0x41)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 10)
  let scale = 2
  let quiet = 4
  let svg = @qr.to_svg(qr, scale, quiet)
  let total = qr.size() + quiet * 2
  let dim = total * scale
  assert_true(qr.version() == 10)
  assert_true(svg.contains("<svg"))
  assert_true(svg.contains("</svg>"))
  assert_true(svg.contains("width=\"" + dim.to_string() + "\""))
  assert_true(svg.contains("height=\"" + dim.to_string() + "\""))
  let dark = iob_qr_dark_count(qr)
  let black_rects = iob_count(svg, "fill=\"black\"")
  assert_true(black_rects == dark)
  let total_rects = iob_count(svg, "<rect")
  assert_true(total_rects == dark + 1)
}

///|
test "iob svg v40 boundary" {
  let data = FixedArray::make(5, 0x41)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 40)
  let scale = 2
  let quiet = 4
  let svg = @qr.to_svg(qr, scale, quiet)
  let total = qr.size() + quiet * 2
  let dim = total * scale
  assert_true(qr.version() == 40)
  assert_true(svg.contains("<svg"))
  assert_true(svg.contains("</svg>"))
  assert_true(svg.contains("width=\"" + dim.to_string() + "\""))
  assert_true(svg.contains("height=\"" + dim.to_string() + "\""))
  let dark = iob_qr_dark_count(qr)
  let black_rects = iob_count(svg, "fill=\"black\"")
  assert_true(black_rects == dark)
  let total_rects = iob_count(svg, "<rect")
  assert_true(total_rects == dark + 1)
}

///|
test "iob png v1 boundary" {
  let data = FixedArray::make(5, 0x41)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let png = @qr.to_png(qr, 1, 4)
  let total = qr.size() + 8
  assert_true(png[0] == 137)
  assert_true(png[1] == 80)
  assert_true(png[2] == 78)
  assert_true(png[3] == 71)
  assert_true(png[4] == 13)
  assert_true(png[5] == 10)
  assert_true(png[6] == 26)
  assert_true(png[7] == 10)
  assert_true(png[12] == 73)
  assert_true(png[13] == 72)
  assert_true(png[14] == 68)
  assert_true(png[15] == 82)
  assert_true(iob_png_width(png) == total)
  assert_true(iob_png_height(png) == total)
  let n = png.length()
  assert_true(png[n - 8] == 73)
  assert_true(png[n - 7] == 69)
  assert_true(png[n - 6] == 78)
  assert_true(png[n - 5] == 68)
}

///|
test "iob png v10 boundary" {
  let data = FixedArray::make(5, 0x41)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 10)
  let png = @qr.to_png(qr, 1, 4)
  let total = qr.size() + 8
  assert_true(qr.version() == 10)
  assert_true(png[0] == 137)
  assert_true(png[12] == 73)
  assert_true(png[13] == 72)
  assert_true(png[14] == 68)
  assert_true(png[15] == 82)
  assert_true(iob_png_width(png) == total)
  assert_true(iob_png_height(png) == total)
  let n = png.length()
  assert_true(png[n - 8] == 73)
  assert_true(png[n - 7] == 69)
  assert_true(png[n - 6] == 78)
  assert_true(png[n - 5] == 68)
}

///|
test "iob png v40 boundary" {
  let data = FixedArray::make(5, 0x41)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 40)
  let png = @qr.to_png(qr, 1, 4)
  let total = qr.size() + 8
  assert_true(qr.version() == 40)
  assert_true(png[0] == 137)
  assert_true(png[12] == 73)
  assert_true(png[13] == 72)
  assert_true(png[14] == 68)
  assert_true(png[15] == 82)
  assert_true(iob_png_width(png) == total)
  assert_true(iob_png_height(png) == total)
  let n = png.length()
  assert_true(png[n - 8] == 73)
  assert_true(png[n - 7] == 69)
  assert_true(png[n - 6] == 78)
  assert_true(png[n - 5] == 68)
}

///|
test "iob png scale boundary" {
  let data = FixedArray::make(5, 0x41)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let quiet = 4
  let total = qr.size() + quiet * 2
  let scales = [1, 5, 20]
  for scale in scales {
    let png = @qr.to_png(qr, scale, quiet)
    let dim = total * scale
    assert_true(iob_png_width(png) == dim)
    assert_true(iob_png_height(png) == dim)
    assert_true(png[0] == 137)
    let n = png.length()
    assert_true(png[n - 8] == 73)
    assert_true(png[n - 5] == 68)
  }
}

///|
test "iob png multi idat blocks" {
  // V40 + scale=20 produces raw_len > 65535, forcing multiple stored blocks.
  let data = FixedArray::make(5, 0x41)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 40)
  let png = @qr.to_png(qr, 20, 4)
  let blocks = iob_count_idat_blocks(png)
  assert_true(blocks > 1)
}

///|
test "iob png crc ihdr correct" {
  let data = FixedArray::make(5, 0x41)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let png = @qr.to_png(qr, 1, 4)
  assert_true(iob_chunk_crc_ok(png, 8))
}

///|
test "iob png crc idat correct" {
  let data = FixedArray::make(5, 0x41)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let png = @qr.to_png(qr, 1, 4)
  assert_true(iob_chunk_crc_ok(png, 33))
}

///|
test "iob png crc iend correct" {
  let data = FixedArray::make(5, 0x41)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let png = @qr.to_png(qr, 1, 4)
  let n = png.length()
  assert_true(iob_chunk_crc_ok(png, n - 12))
}

///|
test "iob three format consistency" {
  let data = FixedArray::make(10, 0x42)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let quiet = 4
  let total = qr.size() + quiet * 2
  let dark = iob_qr_dark_count(qr)
  let pbm = @qr.to_pbm(qr, quiet)
  let pixels = iob_pbm_pixels(pbm)
  assert_true(pixels.length() == total * total)
  let mut pbm_dark = 0
  for i = 0; i < pixels.length(); i = i + 1 {
    if pixels[i] == 1 {
      pbm_dark = pbm_dark + 1
    }
  }
  assert_true(pbm_dark == dark)
  let svg = @qr.to_svg(qr, 1, quiet)
  let svg_dark = iob_count(svg, "fill=\"black\"")
  assert_true(svg_dark == dark)
  let png = @qr.to_png(qr, 1, quiet)
  assert_true(iob_png_width(png) == total)
  assert_true(iob_png_height(png) == total)
  assert_true(png[0] == 137)
}

///|
test "iob minimal matrix boundary" {
  let data = FixedArray::make(1, 0x41)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let size = qr.size()
  assert_true(qr.version() == 1)
  assert_true(size == 21)
  let pbm = @qr.to_pbm(qr, 0)
  let pixels = iob_pbm_pixels(pbm)
  assert_true(pixels.length() == size * size)
  assert_true(pixels[0] == 1)
  let svg = @qr.to_svg(qr, 1, 0)
  assert_true(svg.contains("width=\"" + size.to_string() + "\""))
  let png = @qr.to_png(qr, 1, 0)
  assert_true(iob_png_width(png) == size)
  assert_true(iob_png_height(png) == size)
}
