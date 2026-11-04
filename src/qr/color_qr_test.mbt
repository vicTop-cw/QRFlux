///|
test "color qr from bits" {
  let color = @qr.ColorQRColor::from_bits(0)
  assert_true(color == @qr.color_white())

  let color2 = @qr.ColorQRColor::from_bits(1)
  assert_true(color2 == @qr.color_red())

  let color3 = @qr.ColorQRColor::from_bits(2)
  assert_true(color3 == @qr.color_green())

  let color4 = @qr.ColorQRColor::from_bits(3)
  assert_true(color4 == @qr.color_blue())
}

///|
test "color qr to bits" {
  let bits = @qr.ColorQRColor::to_bits(@qr.color_white())
  assert_true(bits == 0)

  let bits2 = @qr.ColorQRColor::to_bits(@qr.color_red())
  assert_true(bits2 == 1)

  let bits3 = @qr.ColorQRColor::to_bits(@qr.color_green())
  assert_true(bits3 == 2)

  let bits4 = @qr.ColorQRColor::to_bits(@qr.color_blue())
  assert_true(bits4 == 3)
}

///|
test "color qr to rgb" {
  let (r, g, b) = @qr.ColorQRColor::to_rgb(@qr.color_white())
  assert_true(r == 255 && g == 255 && b == 255)

  let (r2, g2, b2) = @qr.ColorQRColor::to_rgb(@qr.color_red())
  assert_true(r2 == 255 && g2 == 0 && b2 == 0)

  let (r3, g3, b3) = @qr.ColorQRColor::to_rgb(@qr.color_green())
  assert_true(r3 == 0 && g3 == 255 && b3 == 0)

  let (r4, g4, b4) = @qr.ColorQRColor::to_rgb(@qr.color_blue())
  assert_true(r4 == 0 && g4 == 0 && b4 == 255)
}

///|
test "color qr encode basic" {
  let encoder = @qr.ColorQREncoder::new(1)
  let data = FixedArray::make(4, 0x42)

  let matrix = encoder.encode(data)
  assert_true(matrix.length() > 0)
}

///|
test "color qr encode decode" {
  let encoder = @qr.ColorQREncoder::new(1)
  let original = FixedArray::make(4, 0x99)

  let matrix = encoder.encode(original)
  let decoded = encoder.decode(matrix)

  assert_true(decoded is Some(_))
}
