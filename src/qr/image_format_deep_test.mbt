/// Image format deep correctness tests (blackbox): PBM/SVG/PNG format
/// structure, CRC32 validity, deflate stored block layout, scale/quiet_zone
/// parameter semantics, cross-version output, and three-format dark-count
/// consistency. Only calls pub fn of @qr.

///|
/// Count non-overlapping occurrences of `sub` in `s`.
fn ifd_count(s : String, sub : String) -> Int32 {
  s.split(sub.to_string_view()).count() - 1
}

///|
/// Parse PBM (P1 ASCII) pixel data into a flat row-major array.
/// Skips the "P1\n<w> <h>\n" header (first 2 newlines), then collects
/// every '0' or '1' character as a pixel value.
fn ifd_pbm_pixels(pbm : String) -> Array[Int32] {
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
fn ifd_png_width(png : FixedArray[Int32]) -> Int32 {
  (png[16] << 24) | (png[17] << 16) | (png[18] << 8) | png[19]
}

///|
/// Extract PNG IHDR height (big-endian, bytes 20-23).
fn ifd_png_height(png : FixedArray[Int32]) -> Int32 {
  (png[20] << 24) | (png[21] << 16) | (png[22] << 8) | png[23]
}

///|
/// PNG CRC32 (same algorithm as the implementation under test).
fn ifd_crc32(data : FixedArray[Int32]) -> Int32 {
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
fn ifd_chunk_crc_ok(png : FixedArray[Int32], offset : Int32) -> Bool {
  let len = (png[offset] << 24) |
    (png[offset + 1] << 16) |
    (png[offset + 2] << 8) |
    png[offset + 3]
  let crc_input = FixedArray::make(4 + len, 0)
  for i = 0; i < 4 + len; i = i + 1 {
    crc_input[i] = png[offset + 4 + i]
  }
  let expected = ifd_crc32(crc_input)
  let crc_pos = offset + 8 + len
  let actual = (png[crc_pos] << 24) |
    (png[crc_pos + 1] << 16) |
    (png[crc_pos + 2] << 8) |
    png[crc_pos + 3]
  expected == actual
}

///|
/// Count dark modules in a QR code.
fn ifd_qr_dark_count(qr : @qr.QrCode) -> Int32 {
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
test "ifd pbm header exact format" {
  // PBM 头必须精确为 "P1\n<w> <h>\n"，w == h == size + 2*quiet_zone.
  let data = FixedArray::make(5, 0x41)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let quiet = 4
  let total = qr.size() + quiet * 2
  let pbm = @qr.to_pbm(qr, quiet)
  let expected_header = "P1\n" +
    total.to_string() +
    " " +
    total.to_string() +
    "\n"
  assert_true(pbm.has_prefix(expected_header))
}

///|
test "ifd pbm pixels only 0 or 1" {
  // 头部之后的所有字符只能是 '0', '1', ' ', '\n'。
  let data = FixedArray::make(5, 0x41)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let pbm = @qr.to_pbm(qr, 4)
  let mut ok = true
  let mut newline_count = 0
  for c in pbm.iter() {
    if newline_count < 2 {
      if c == '\n' {
        newline_count = newline_count + 1
      }
    } else if c != '0' && c != '1' && c != ' ' && c != '\n' {
      ok = false
    }
  }
  assert_true(ok)
}

///|
test "ifd pbm dark count matches qr" {
  // PBM 中 '1' 像素数必须等于 QR 暗模块数。
  let data = FixedArray::make(20, 0x42)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 3)
  let pbm = @qr.to_pbm(qr, 4)
  let pixels = ifd_pbm_pixels(pbm)
  let mut pbm_dark = 0
  for i = 0; i < pixels.length(); i = i + 1 {
    if pixels[i] == 1 {
      pbm_dark = pbm_dark + 1
    }
  }
  let qr_dark = ifd_qr_dark_count(qr)
  assert_true(pbm_dark == qr_dark)
}

///|
test "ifd pbm quiet zone border all white" {
  // quiet_zone 四条边必须全白（'0'）。
  let data = FixedArray::make(5, 0x41)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let quiet = 4
  let pbm = @qr.to_pbm(qr, quiet)
  let size = qr.size()
  let total = size + quiet * 2
  let pixels = ifd_pbm_pixels(pbm)
  let mut ok = true
  for x = 0; x < total; x = x + 1 {
    if pixels[x] != 0 {
      ok = false
    }
    if pixels[(total - 1) * total + x] != 0 {
      ok = false
    }
  }
  for y = 0; y < total; y = y + 1 {
    if pixels[y * total] != 0 {
      ok = false
    }
    if pixels[y * total + total - 1] != 0 {
      ok = false
    }
  }
  assert_true(ok)
}

///|
test "ifd svg root tag with xmlns" {
  // <svg> 必须带 xmlns="http://www.w3.org/2000/svg"，并以 </svg>\n 结尾。
  let data = FixedArray::make(5, 0x41)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let svg = @qr.to_svg(qr, 1, 4)
  assert_true(svg.has_prefix("<svg xmlns=\"http://www.w3.org/2000/svg\""))
  assert_true(svg.contains("</svg>\n"))
}

///|
test "ifd svg background rect full coverage" {
  // 背景 rect 必须 fill="white" 且 width=height=dim（全覆盖）。
  let data = FixedArray::make(5, 0x41)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let scale = 3
  let quiet = 4
  let svg = @qr.to_svg(qr, scale, quiet)
  let total = qr.size() + quiet * 2
  let dim = total * scale
  let bg = "  <rect width=\"" +
    dim.to_string() +
    "\" height=\"" +
    dim.to_string() +
    "\" fill=\"white\"/>\n"
  assert_true(svg.contains(bg))
  // 背景 rect 必须在所有 black rect 之前：fill="white" 出现在 fill="black" 之前。
  let white_pos = svg.find("fill=\"white\"").unwrap()
  let black_pos = svg.find("fill=\"black\"").unwrap()
  assert_true(white_pos < black_pos)
}

///|
test "ifd svg black rect coordinates" {
  // 每个 dark module 对应一个 black rect，坐标 = (x+quiet)*scale, (y+quiet)*scale。
  let data = FixedArray::make(5, 0x41)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let scale = 2
  let quiet = 4
  let svg = @qr.to_svg(qr, scale, quiet)
  let size = qr.size()
  // 验证前若干个 dark module 的 rect 坐标正确。
  let mut checked = 0
  for y = 0; y < size && checked < 5; y = y + 1 {
    for x = 0; x < size && checked < 5; x = x + 1 {
      if qr.get_module(x, y) {
        let px = (x + quiet) * scale
        let py = (y + quiet) * scale
        let expected = "  <rect x=\"" +
          px.to_string() +
          "\" y=\"" +
          py.to_string() +
          "\" width=\"" +
          scale.to_string() +
          "\" height=\"" +
          scale.to_string() +
          "\" fill=\"black\"/>\n"
        assert_true(svg.contains(expected))
        checked = checked + 1
      }
    }
  }
  assert_true(checked == 5)
}

///|
test "ifd png signature 8 bytes" {
  // PNG 8 字节签名：137 80 78 71 13 10 26 10。
  let data = FixedArray::make(5, 0x41)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let png = @qr.to_png(qr, 1, 4)
  let expected = [137, 80, 78, 71, 13, 10, 26, 10]
  let mut ok = true
  for i = 0; i < 8; i = i + 1 {
    if png[i] != expected[i] {
      ok = false
    }
  }
  assert_true(ok)
}

///|
test "ifd png ihdr all fields" {
  // IHDR: length=13, type="IHDR", width/height, bit_depth=1, color_type=0,
  // compression=0, filter=0, interlace=0。
  let data = FixedArray::make(5, 0x41)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let png = @qr.to_png(qr, 1, 4)
  let total = qr.size() + 8
  let len = (png[8] << 24) | (png[9] << 16) | (png[10] << 8) | png[11]
  assert_true(len == 13)
  assert_true(png[12] == 73 && png[13] == 72 && png[14] == 68 && png[15] == 82)
  assert_true(ifd_png_width(png) == total)
  assert_true(ifd_png_height(png) == total)
  assert_true(png[24] == 1) // bit_depth
  assert_true(png[25] == 0) // color_type
  assert_true(png[26] == 0) // compression
  assert_true(png[27] == 0) // filter
  assert_true(png[28] == 0) // interlace
}

///|
test "ifd png chunk order ihdr idat iend" {
  // chunk 顺序必须是 IHDR -> IDAT -> IEND。
  let data = FixedArray::make(5, 0x41)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let png = @qr.to_png(qr, 1, 4)
  // IHDR at offset 8 (type at 12-15).
  assert_true(png[12] == 73 && png[13] == 72 && png[14] == 68 && png[15] == 82)
  // IDAT at offset 33 (type at 37-40).
  assert_true(png[37] == 73 && png[38] == 68 && png[39] == 65 && png[40] == 84)
  // IEND at last 12 bytes (type at n-8..n-5).
  let n = png.length()
  assert_true(
    png[n - 8] == 73 && png[n - 7] == 69 && png[n - 6] == 78 && png[n - 5] == 68,
  )
}

///|
test "ifd png crc all chunks" {
  // 遍历所有 chunk，验证每个 chunk 的 CRC32 正确，且 chunk 总数 == 3。
  let data = FixedArray::make(10, 0x42)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 2)
  let png = @qr.to_png(qr, 1, 4)
  let mut offset = 8
  let mut chunk_count = 0
  let mut all_ok = true
  while offset < png.length() {
    let len = (png[offset] << 24) |
      (png[offset + 1] << 16) |
      (png[offset + 2] << 8) |
      png[offset + 3]
    if !ifd_chunk_crc_ok(png, offset) {
      all_ok = false
    }
    chunk_count = chunk_count + 1
    offset = offset + 12 + len
  }
  assert_true(all_ok)
  assert_true(chunk_count == 3)
}

///|
test "ifd png deflate stored block structure" {
  // IDAT zlib header 0x78 0x01；deflate stored block: BFINAL=1/BTYPE=00 -> 0x01；
  // LEN/NLEN 互补：NLEN = ~LEN & 0xFFFF。
  let data = FixedArray::make(5, 0x41)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let png = @qr.to_png(qr, 1, 4)
  // zlib header at 41-42.
  assert_true(png[41] == 0x78)
  assert_true(png[42] == 0x01)
  // deflate block header at 43: BFINAL=1, BTYPE=00 -> byte = 0x01.
  assert_true(png[43] == 1)
  // LEN (LE) at 44-45, NLEN (LE) at 46-47.
  let len = png[44] | (png[45] << 8)
  let nlen = png[46] | (png[47] << 8)
  assert_true(len > 0)
  assert_true(nlen == ((len ^ 0xFFFF) & 0xFFFF))
}

///|
test "ifd scale output dimension formula" {
  // 输出尺寸 = (size + 2*quiet_zone) * scale，对 SVG 和 PNG 都成立。
  let data = FixedArray::make(5, 0x41)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let quiet = 4
  let total = qr.size() + quiet * 2
  for scale = 1; scale <= 10; scale = scale + 1 {
    let png = @qr.to_png(qr, scale, quiet)
    let svg = @qr.to_svg(qr, scale, quiet)
    let dim = total * scale
    assert_true(ifd_png_width(png) == dim)
    assert_true(ifd_png_height(png) == dim)
    assert_true(svg.contains("width=\"" + dim.to_string() + "\""))
    assert_true(svg.contains("height=\"" + dim.to_string() + "\""))
  }
}

///|
test "ifd quiet zone 0 4 10" {
  // quiet_zone = 0/4/10 时，输出尺寸 = size + 2*quiet_zone。
  let data = FixedArray::make(5, 0x41)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let size = qr.size()
  for quiet in [0, 4, 10] {
    let total = size + quiet * 2
    let pbm = @qr.to_pbm(qr, quiet)
    let header = "P1\n" + total.to_string() + " " + total.to_string() + "\n"
    assert_true(pbm.contains(header))
    let png = @qr.to_png(qr, 1, quiet)
    assert_true(ifd_png_width(png) == total)
    assert_true(ifd_png_height(png) == total)
    let svg = @qr.to_svg(qr, 1, quiet)
    assert_true(svg.contains("width=\"" + total.to_string() + "\""))
  }
}

///|
test "ifd cross version v1 v10 v20 v40" {
  // 跨版本 V1/V10/V20/V40 图片输出尺寸与格式正确。
  let data = FixedArray::make(5, 0x41)
  for v in [1, 10, 20, 40] {
    let qr = @qr.encode_binary(data, @qr.ecc_low(), v)
    assert_true(qr.version() == v)
    let quiet = 4
    let total = qr.size() + quiet * 2
    let pbm = @qr.to_pbm(qr, quiet)
    let svg = @qr.to_svg(qr, 1, quiet)
    let png = @qr.to_png(qr, 1, quiet)
    // PBM 头
    assert_true(
      pbm.contains("P1\n" + total.to_string() + " " + total.to_string() + "\n"),
    )
    // SVG 尺寸
    assert_true(svg.contains("width=\"" + total.to_string() + "\""))
    assert_true(svg.contains("height=\"" + total.to_string() + "\""))
    // PNG 签名 + 尺寸
    assert_true(png[0] == 137)
    assert_true(ifd_png_width(png) == total)
    assert_true(ifd_png_height(png) == total)
    // PNG IEND 存在
    let n = png.length()
    assert_true(png[n - 8] == 73 && png[n - 5] == 68)
  }
}

///|
test "ifd three format dark count consistency" {
  // 暗模块计数：PBM 暗像素数 == SVG black rect 数 == QR dark count。
  let data = FixedArray::make(30, 0x55)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 4)
  let quiet = 4
  let qr_dark = ifd_qr_dark_count(qr)
  // PBM 暗像素数
  let pbm = @qr.to_pbm(qr, quiet)
  let pixels = ifd_pbm_pixels(pbm)
  let mut pbm_dark = 0
  for i = 0; i < pixels.length(); i = i + 1 {
    if pixels[i] == 1 {
      pbm_dark = pbm_dark + 1
    }
  }
  // SVG black rect 数
  let svg = @qr.to_svg(qr, 1, quiet)
  let svg_dark = ifd_count(svg, "fill=\"black\"")
  assert_true(pbm_dark == qr_dark)
  assert_true(svg_dark == qr_dark)
  assert_true(pbm_dark == svg_dark)
}

///|
test "ifd png idat length matches raw size" {
  // IDAT 数据长度 = 2 (zlib header) + 5 (stored block header) + raw_len + 4 (adler32).
  // raw_len = height * (1 + ceil(width/8))，bit_depth=1。
  let data = FixedArray::make(5, 0x41)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let quiet = 4
  let scale = 1
  let png = @qr.to_png(qr, scale, quiet)
  let total = qr.size() + quiet * 2
  let width = total * scale
  let height = total * scale
  let row_bytes = (width + 7) / 8
  let raw_len = height * (1 + row_bytes)
  let expected_idat_len = 2 + 5 + raw_len + 4
  let idat_len = (png[33] << 24) | (png[34] << 16) | (png[35] << 8) | png[36]
  assert_true(idat_len == expected_idat_len)
}

///|
test "ifd svg rect count equals dark plus one" {
  // SVG <rect> 总数 = dark_count + 1（背景 white rect）。
  let data = FixedArray::make(15, 0x33)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 2)
  let svg = @qr.to_svg(qr, 2, 4)
  let dark = ifd_qr_dark_count(qr)
  let total_rects = ifd_count(svg, "<rect")
  let black_rects = ifd_count(svg, "fill=\"black\"")
  let white_rects = ifd_count(svg, "fill=\"white\"")
  assert_true(black_rects == dark)
  assert_true(white_rects == 1)
  assert_true(total_rects == dark + 1)
}
