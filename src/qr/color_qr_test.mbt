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

///|
test "color qr from rgb" {
  assert_true(@qr.ColorQRColor::from_rgb(255, 255, 255) == @qr.color_white())
  assert_true(@qr.ColorQRColor::from_rgb(255, 0, 0) == @qr.color_red())
  assert_true(@qr.ColorQRColor::from_rgb(0, 255, 0) == @qr.color_green())
  assert_true(@qr.ColorQRColor::from_rgb(0, 0, 255) == @qr.color_blue())
  // Threshold boundary: yellow and magenta fall into "else" → Blue
  assert_true(@qr.ColorQRColor::from_rgb(200, 200, 0) == @qr.color_blue())
  assert_true(@qr.ColorQRColor::from_rgb(200, 0, 200) == @qr.color_blue())
}

///|
test "color qr rgb roundtrip" {
  let encoder = @qr.ColorQREncoder::new(2)
  let original = FixedArray::make(8, 0x5a)
  let matrix = encoder.encode(original)
  // Convert to RGB matrix
  let size = matrix.length()
  let rgb_matrix = FixedArray::make(size, FixedArray::make(size, (0, 0, 0)))
  for y = 0; y < size; y = y + 1 {
    rgb_matrix[y] = FixedArray::make(size, (0, 0, 0))
    for x = 0; x < size; x = x + 1 {
      let (r, g, b) = @qr.ColorQRColor::to_rgb(matrix[y][x])
      rgb_matrix[y][x] = (r, g, b)
    }
  }
  // Decode from RGB
  let decoded = @qr.decode_color_from_rgb(rgb_matrix, 2)
  assert_true(decoded is Some(_))
  match decoded {
    Some(d) => assert_true(d.length() > 0)
    None => assert_true(false)
  }
}

///|
test "color qr svg output" {
  let encoder = @qr.ColorQREncoder::new(1)
  let data = FixedArray::make(4, 0x42)
  let matrix = encoder.encode(data)
  let svg = @qr.color_qr_to_svg(matrix, 10, 4)
  assert_true(svg.contains("<svg"))
  assert_true(svg.contains("</svg>"))
  assert_true(svg.contains("rgb("))
}

///|
test "color qr ppm output" {
  let encoder = @qr.ColorQREncoder::new(1)
  let data = FixedArray::make(4, 0x99)
  let matrix = encoder.encode(data)
  let ppm = @qr.color_qr_to_ppm(matrix, 4)
  assert_true(ppm.contains("P3"))
  assert_true(ppm.contains("255"))
}

///|
test "color qr full roundtrip with rgb" {
  // Encode → to RGB → from RGB → decode → verify
  let encoder = @qr.ColorQREncoder::new(3)
  let original = FixedArray::make(16, 0x37)
  let matrix = encoder.encode(original)
  let size = matrix.length()
  // Convert to RGB
  let rgb_matrix = FixedArray::make(size, FixedArray::make(size, (0, 0, 0)))
  for y = 0; y < size; y = y + 1 {
    rgb_matrix[y] = FixedArray::make(size, (0, 0, 0))
    for x = 0; x < size; x = x + 1 {
      let (r, g, b) = @qr.ColorQRColor::to_rgb(matrix[y][x])
      rgb_matrix[y][x] = (r, g, b)
    }
  }
  // Decode from RGB
  match @qr.decode_color_from_rgb(rgb_matrix, 3) {
    Some(decoded) => {
      // Verify first few bytes match original
      let n = if original.length() < decoded.length() {
        original.length()
      } else {
        decoded.length()
      }
      let mut all_match = true
      for i = 0; i < n; i = i + 1 {
        if original[i] != decoded[i] {
          all_match = false
        }
      }
      assert_true(all_match)
    }
    None => assert_true(false)
  }
}
