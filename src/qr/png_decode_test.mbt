/// Tests for the PNG decoder: to_png output read back into grayscale,
/// then fed through decode_from_pixels for a full file-level round trip.

///|
test "png decode recovers pixel dimensions and polarity" {
  let data = img_bytes([1, 2, 3, 4])
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let size = qr.size()
  let scale = 8
  let quiet = 4
  let png = @qr.to_png(qr, scale, quiet)
  let gray = match @qr.decode_png_gray(@qr.bytes_of_i32(png)) {
    Some(g) => g
    None => abort("decode_png_gray returned None for valid PNG")
  }
  let expect_dim = (size + quiet * 2) * scale
  assert_true(gray.length() == expect_dim)
  assert_true(gray[0].length() == expect_dim)
  // Quiet zone is white (255), the top-left finder border is black (0).
  assert_true(gray[0][0] == 255)
  let finder_px = quiet * scale + scale / 2
  assert_true(gray[finder_px][finder_px] == 0)
}

///|
test "png roundtrip through decode_from_pixels" {
  let data = img_bytes([72, 101, 108, 108, 111])
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let png = @qr.to_png(qr, 8, 4)
  let gray = match @qr.decode_png_gray(@qr.bytes_of_i32(png)) {
    Some(g) => g
    None => abort("decode_png_gray returned None")
  }
  let decoded = @qr.decode_from_pixels(gray)
  img_assert_payload_eq(decoded, data, "png roundtrip")
}

///|
test "png roundtrip V3 smaller scale" {
  let data = img_random(50, 777)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 3)
  let png = @qr.to_png(qr, 4, 4)
  let gray = match @qr.decode_png_gray(@qr.bytes_of_i32(png)) {
    Some(g) => g
    None => abort("decode_png_gray returned None (V3)")
  }
  let decoded = @qr.decode_from_pixels(gray)
  img_assert_payload_eq(decoded, data, "png V3 scale4")
}

///|
test "png bad signature returns None" {
  let data = img_bytes([9])
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let png = @qr.to_png(qr, 4, 4)
  // Corrupt the signature first byte.
  png[0] = 0x00
  assert_true(@qr.decode_png_gray(@qr.bytes_of_i32(png)) is None)
}

///|
test "png truncated stream returns None" {
  let data = img_bytes([9])
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let png = @qr.to_png(qr, 4, 4)
  // Truncate to 20 bytes: chunk walk must fail gracefully.
  let cut : FixedArray[Int32] = FixedArray::make(20, 0)
  for i = 0; i < 20; i = i + 1 {
    cut[i] = png[i]
  }
  assert_true(@qr.decode_png_gray(@qr.bytes_of_i32(cut)) is None)
}

///|
test "png empty input returns None" {
  let empty : FixedArray[Int32] = FixedArray::make(0, 0)
  assert_true(@qr.decode_png_gray(@qr.bytes_of_i32(empty)) is None)
}
