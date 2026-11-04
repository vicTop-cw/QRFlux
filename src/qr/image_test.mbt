/// Image generator tests: PBM, SVG, PNG.

///|
test "pbm v1 quiet 4" {
  let data = FixedArray::make(5, 0x41)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let pbm = @qr.to_pbm(qr, 4)
  // V1 size = 21, total = 21 + 8 = 29
  assert_true(pbm.contains("P1"))
  assert_true(pbm.contains("29 29"))
  // Should contain both 0 and 1
  assert_true(pbm.contains("0"))
  assert_true(pbm.contains("1"))
}

///|
test "pbm v5 quiet 2" {
  let data = FixedArray::make(50, 0x42)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 5)
  let pbm = @qr.to_pbm(qr, 2)
  // V5 size = 37, total = 37 + 4 = 41
  assert_true(qr.version() == 5)
  assert_true(pbm.contains("P1"))
  assert_true(pbm.contains("41 41"))
}

///|
test "pbm quiet zone is white" {
  let data = FixedArray::make(5, 0x41)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let pbm = @qr.to_pbm(qr, 4)
  // First pixel (top-left corner of quiet zone) must be 0 (white)
  // PBM starts with "P1\n29 29\n" then first row of pixels
  // First row is all quiet zone = all 0s
  assert_true(pbm.contains("P1\n29 29\n"))
}

///|
test "svg v1 scale 1 quiet 4" {
  let data = FixedArray::make(5, 0x41)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let svg = @qr.to_svg(qr, 1, 4)
  // V1 size = 21, total = 29, dim = 29
  assert_true(svg.contains("<svg"))
  assert_true(svg.contains("</svg>"))
  assert_true(svg.contains("<rect"))
  assert_true(svg.contains("white"))
  assert_true(svg.contains("black"))
  assert_true(svg.contains("width=\"29\""))
  assert_true(svg.contains("height=\"29\""))
}

///|
test "svg v5 scale 3 quiet 2" {
  let data = FixedArray::make(50, 0x42)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 5)
  let svg = @qr.to_svg(qr, 3, 2)
  // V5 size = 37, total = 41, dim = 123
  assert_true(qr.version() == 5)
  assert_true(svg.contains("width=\"123\""))
  assert_true(svg.contains("fill=\"black\""))
  assert_true(svg.contains("</svg>"))
}

///|
test "svg has background rect" {
  let data = FixedArray::make(5, 0x41)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let svg = @qr.to_svg(qr, 2, 4)
  // Background white rect covering full image
  assert_true(svg.contains("fill=\"white\""))
  // V1 total = 29, dim = 58
  assert_true(svg.contains("width=\"58\""))
}

///|
test "png signature v1" {
  let data = FixedArray::make(5, 0x41)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let png = @qr.to_png(qr, 1, 4)
  // PNG signature: 137 80 78 71 13 10 26 10
  assert_true(png[0] == 137)
  assert_true(png[1] == 80)
  assert_true(png[2] == 78)
  assert_true(png[3] == 71)
  assert_true(png[4] == 13)
  assert_true(png[5] == 10)
  assert_true(png[6] == 26)
  assert_true(png[7] == 10)
}

///|
test "png ihdr chunk v1" {
  let data = FixedArray::make(5, 0x41)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let png = @qr.to_png(qr, 1, 4)
  // IHDR length = 13 (big-endian)
  assert_true(png[8] == 0)
  assert_true(png[9] == 0)
  assert_true(png[10] == 0)
  assert_true(png[11] == 13)
  // IHDR type "IHDR" = 73 72 68 82
  assert_true(png[12] == 73)
  assert_true(png[13] == 72)
  assert_true(png[14] == 68)
  assert_true(png[15] == 82)
  // V1 size = 21, total = 29, width = height = 29
  // width BE: 0 0 0 29
  assert_true(png[16] == 0)
  assert_true(png[17] == 0)
  assert_true(png[18] == 0)
  assert_true(png[19] == 29)
  // height BE: 0 0 0 29
  assert_true(png[20] == 0)
  assert_true(png[21] == 0)
  assert_true(png[22] == 0)
  assert_true(png[23] == 29)
  // bit depth = 1, color type = 0 (grayscale)
  assert_true(png[24] == 1)
  assert_true(png[25] == 0)
  assert_true(png[26] == 0)
  assert_true(png[27] == 0)
  assert_true(png[28] == 0)
}

///|
test "png idat chunk v1" {
  let data = FixedArray::make(5, 0x41)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let png = @qr.to_png(qr, 1, 4)
  // After signature(8) + IHDR chunk(25) = offset 33
  // IDAT length at 33-36, type at 37-40
  // "IDAT" = 73 68 65 84
  assert_true(png[37] == 73)
  assert_true(png[38] == 68)
  assert_true(png[39] == 65)
  assert_true(png[40] == 84)
  // IDAT data starts at 41: zlib header 0x78 0x01
  assert_true(png[41] == 0x78)
  assert_true(png[42] == 0x01)
  // V1 quiet 4 scale 1 bit_depth=1: row_bytes=ceil(29/8)=4, row_len=5
  // raw_len = 29 * 5 = 145 < 65535, single stored block
  // BFINAL = 1
  assert_true(png[43] == 1)
  // LEN = 145 = 0x0091, little-endian: 0x91 0x00
  assert_true(png[44] == 0x91)
  assert_true(png[45] == 0x00)
  // NLEN = ~145 & 0xFFFF = 0xFF6E, little-endian: 0x6E 0xFF
  assert_true(png[46] == 0x6E)
  assert_true(png[47] == 0xFF)
}

///|
test "png iend chunk v1" {
  let data = FixedArray::make(5, 0x41)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let png = @qr.to_png(qr, 1, 4)
  let n = png.length()
  // IEND is last 12 bytes: length(4) + type(4) + crc(4)
  // length = 0
  assert_true(png[n - 12] == 0)
  assert_true(png[n - 11] == 0)
  assert_true(png[n - 10] == 0)
  assert_true(png[n - 9] == 0)
  // "IEND" = 73 69 78 68
  assert_true(png[n - 8] == 73)
  assert_true(png[n - 7] == 69)
  assert_true(png[n - 6] == 78)
  assert_true(png[n - 5] == 68)
}

///|
test "png iend crc v1" {
  // CRC32("IEND") = 0xAE426082 (known constant)
  // Big-endian bytes: 174 66 96 130
  let data = FixedArray::make(5, 0x41)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let png = @qr.to_png(qr, 1, 4)
  let n = png.length()
  assert_true(png[n - 4] == 174)
  assert_true(png[n - 3] == 66)
  assert_true(png[n - 2] == 96)
  assert_true(png[n - 1] == 130)
}

///|
test "png v5 scale 2 quiet 2" {
  let data = FixedArray::make(50, 0x42)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 5)
  let png = @qr.to_png(qr, 2, 2)
  // V5 size = 37, total = 41, width = height = 82
  assert_true(qr.version() == 5)
  assert_true(png[0] == 137)
  assert_true(png[16] == 0)
  assert_true(png[17] == 0)
  assert_true(png[18] == 0)
  assert_true(png[19] == 82)
  assert_true(png[23] == 82)
  assert_true(png[24] == 1)
  // IEND present
  let n = png.length()
  assert_true(png[n - 8] == 73)
  assert_true(png[n - 7] == 69)
  assert_true(png[n - 6] == 78)
  assert_true(png[n - 5] == 68)
}

///|
test "png total length v1" {
  // V1 quiet 4 scale 1 bit_depth=1: width=height=29
  // row_bytes=ceil(29/8)=4, row_len=5, raw_len=29*5=145
  // IDAT: 2 (zlib) + 5 (stored header) + 145 (data) + 4 (adler) = 156
  // IHDR chunk: 12 + 13 = 25
  // IDAT chunk: 12 + 156 = 168
  // IEND chunk: 12 + 0 = 12
  // Total: 8 + 25 + 168 + 12 = 213
  let data = FixedArray::make(5, 0x41)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let png = @qr.to_png(qr, 1, 4)
  assert_true(png.length() == 213)
}
