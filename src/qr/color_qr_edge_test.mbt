// Edge case tests for color QR code.
// Tests boundary conditions, bijections, and error handling for color_qr.mbt.

///|
test "color edge: four colors distinct" {
  let w = @qr.color_white()
  let r = @qr.color_red()
  let g = @qr.color_green()
  let b = @qr.color_blue()
  assert_true(w != r)
  assert_true(w != g)
  assert_true(w != b)
  assert_true(r != g)
  assert_true(r != b)
  assert_true(g != b)
}

///|
test "color edge: four colors consistent" {
  assert_true(@qr.color_white() == @qr.color_white())
  assert_true(@qr.color_red() == @qr.color_red())
  assert_true(@qr.color_green() == @qr.color_green())
  assert_true(@qr.color_blue() == @qr.color_blue())
}

///|
test "color edge: four colors cover all bits" {
  let bits_w = @qr.ColorQRColor::to_bits(@qr.color_white())
  let bits_r = @qr.ColorQRColor::to_bits(@qr.color_red())
  let bits_g = @qr.ColorQRColor::to_bits(@qr.color_green())
  let bits_b = @qr.ColorQRColor::to_bits(@qr.color_blue())
  assert_true(bits_w == 0)
  assert_true(bits_r == 1)
  assert_true(bits_g == 2)
  assert_true(bits_b == 3)
  let seen = [bits_w, bits_r, bits_g, bits_b]
  let mut all_distinct = true
  for i = 0; i < 4; i = i + 1 {
    for j = i + 1; j < 4; j = j + 1 {
      if seen[i] == seen[j] {
        all_distinct = false
      }
    }
  }
  assert_true(all_distinct)
}

///|
test "color edge: from to bits bijection" {
  let c0 = @qr.ColorQRColor::from_bits(0)
  let c1 = @qr.ColorQRColor::from_bits(1)
  let c2 = @qr.ColorQRColor::from_bits(2)
  let c3 = @qr.ColorQRColor::from_bits(3)
  assert_true(c0 != c1)
  assert_true(c0 != c2)
  assert_true(c0 != c3)
  assert_true(c1 != c2)
  assert_true(c1 != c3)
  assert_true(c2 != c3)
  assert_true(@qr.ColorQRColor::to_bits(c0) == 0)
  assert_true(@qr.ColorQRColor::to_bits(c1) == 1)
  assert_true(@qr.ColorQRColor::to_bits(c2) == 2)
  assert_true(@qr.ColorQRColor::to_bits(c3) == 3)
}

///|
test "color edge: to from bits bijection" {
  let w = @qr.color_white()
  let r = @qr.color_red()
  let g = @qr.color_green()
  let b = @qr.color_blue()
  let bw = @qr.ColorQRColor::to_bits(w)
  let br = @qr.ColorQRColor::to_bits(r)
  let bg = @qr.ColorQRColor::to_bits(g)
  let bb = @qr.ColorQRColor::to_bits(b)
  assert_true(bw >= 0 && bw <= 3)
  assert_true(br >= 0 && br <= 3)
  assert_true(bg >= 0 && bg <= 3)
  assert_true(bb >= 0 && bb <= 3)
  assert_true(@qr.ColorQRColor::from_bits(bw) == w)
  assert_true(@qr.ColorQRColor::from_bits(br) == r)
  assert_true(@qr.ColorQRColor::from_bits(bg) == g)
  assert_true(@qr.ColorQRColor::from_bits(bb) == b)
}

///|
test "color edge: from bits out of range" {
  // from_bits 的 _ 分支捕获所有非 0/1/2 的值，映射到 Blue
  assert_true(@qr.ColorQRColor::from_bits(4) == @qr.color_blue())
  assert_true(@qr.ColorQRColor::from_bits(5) == @qr.color_blue())
  assert_true(@qr.ColorQRColor::from_bits(-1) == @qr.color_blue())
  assert_true(@qr.ColorQRColor::from_bits(100) == @qr.color_blue())
  assert_true(@qr.ColorQRColor::from_bits(1000) == @qr.color_blue())
}

///|
test "color edge: to rgb white" {
  let (r, g, b) = @qr.ColorQRColor::to_rgb(@qr.color_white())
  assert_true(r == 255 && g == 255 && b == 255)
}

///|
test "color edge: to rgb red" {
  let (r, g, b) = @qr.ColorQRColor::to_rgb(@qr.color_red())
  assert_true(r == 255 && g == 0 && b == 0)
}

///|
test "color edge: to rgb green" {
  let (r, g, b) = @qr.ColorQRColor::to_rgb(@qr.color_green())
  assert_true(r == 0 && g == 255 && b == 0)
}

///|
test "color edge: to rgb blue" {
  let (r, g, b) = @qr.ColorQRColor::to_rgb(@qr.color_blue())
  assert_true(r == 0 && g == 0 && b == 255)
}

///|
test "color edge: from rgb white" {
  assert_true(@qr.ColorQRColor::from_rgb(255, 255, 255) == @qr.color_white())
}

///|
test "color edge: from rgb red" {
  assert_true(@qr.ColorQRColor::from_rgb(255, 0, 0) == @qr.color_red())
}

///|
test "color edge: from rgb boundary" {
  // 128 不 > 128，所以 (128,128,128) 落到 else → Blue
  assert_true(@qr.ColorQRColor::from_rgb(128, 128, 128) == @qr.color_blue())
  // 129 才 > 128
  assert_true(@qr.ColorQRColor::from_rgb(129, 129, 129) == @qr.color_white())
  assert_true(@qr.ColorQRColor::from_rgb(129, 0, 0) == @qr.color_red())
  assert_true(@qr.ColorQRColor::from_rgb(0, 129, 0) == @qr.color_green())
  // (0, 0, 129): r<=128, g<=128 → else → Blue
  assert_true(@qr.ColorQRColor::from_rgb(0, 0, 129) == @qr.color_blue())
}

///|
test "color edge: encode empty data" {
  let encoder = @qr.ColorQREncoder::new(1)
  let data = FixedArray::make(0, 0)
  let matrix = encoder.encode(data)
  assert_true(matrix.length() == 21)
  for y = 0; y < 21; y = y + 1 {
    assert_true(matrix[y].length() == 21)
  }
  // 空数据，所有块应为 White
  let mut all_white = true
  for y = 0; y < 21; y = y + 1 {
    for x = 0; x < 21; x = x + 1 {
      if matrix[y][x] != @qr.color_white() {
        all_white = false
      }
    }
  }
  assert_true(all_white)
  // 解码不崩溃，输出长度 = (21/2)^2 = 100
  match encoder.decode(matrix) {
    Some(d) => assert_true(d.length() == 100)
    None => assert_true(false)
  }
}

///|
test "color edge: encode single byte" {
  let encoder = @qr.ColorQREncoder::new(1)
  let data = FixedArray::make(1, 0x5A)
  let matrix = encoder.encode(data)
  match encoder.decode(matrix) {
    Some(decoded) => {
      let n = if data.length() < decoded.length() {
        data.length()
      } else {
        decoded.length()
      }
      assert_true(n == 1)
      assert_true(decoded[0] == 0x5A)
    }
    None => assert_true(false)
  }
}

///|
test "color edge: encode v1 capacity" {
  let encoder = @qr.ColorQREncoder::new(1)
  // V1 size=21, 容量 = (21/2)^2 = 100 字节
  let capacity = 100
  let data = FixedArray::make(capacity, 0x42)
  let matrix = encoder.encode(data)
  match encoder.decode(matrix) {
    Some(decoded) => {
      let n = if data.length() < decoded.length() {
        data.length()
      } else {
        decoded.length()
      }
      let mut all_match = true
      for i = 0; i < n; i = i + 1 {
        if data[i] != decoded[i] {
          all_match = false
        }
      }
      assert_true(all_match)
      assert_true(n == capacity)
    }
    None => assert_true(false)
  }
}

///|
test "color edge: encode decode various versions" {
  fn check(version : Int32, value : Int32, count : Int32) -> Bool {
    let enc = @qr.ColorQREncoder::new(version)
    let data = FixedArray::make(count, value)
    let mat = enc.encode(data)
    match enc.decode(mat) {
      Some(decoded) => {
        let n = if data.length() < decoded.length() {
          data.length()
        } else {
          decoded.length()
        }
        let mut ok = true
        for i = 0; i < n; i = i + 1 {
          if data[i] != decoded[i] {
            ok = false
          }
        }
        ok
      }
      None => false
    }
  }
  assert_true(check(1, 0x5A, 10))
  assert_true(check(3, 0x37, 20))
  assert_true(check(5, 0x6C, 30))
  assert_true(check(10, 0xA3, 50))
}

///|
test "color edge: svg contains colored rects" {
  let encoder = @qr.ColorQREncoder::new(1)
  // 0x1B = 00011011 → c0=White, c1=Red, c2=Green, c3=Blue
  let data = FixedArray::make(1, 0x1B)
  let matrix = encoder.encode(data)
  let svg = @qr.color_qr_to_svg(matrix, 10, 4)
  assert_true(svg.contains("<rect"))
  assert_true(svg.contains("fill=\"rgb(255,0,0)\""))
  assert_true(svg.contains("fill=\"rgb(0,255,0)\""))
  assert_true(svg.contains("fill=\"rgb(0,0,255)\""))
}

///|
test "color edge: ppm header correct" {
  let encoder = @qr.ColorQREncoder::new(1)
  let data = FixedArray::make(4, 0x42)
  let matrix = encoder.encode(data)
  let ppm = @qr.color_qr_to_ppm(matrix, 4)
  // P3 格式，total = 21 + 4*2 = 29
  assert_true(ppm.contains("P3\n"))
  assert_true(ppm.contains("29 29\n"))
  assert_true(ppm.contains("255\n"))
}

///|
test "color edge: ppm contains color data" {
  let encoder = @qr.ColorQREncoder::new(1)
  // 0x1B 编码出 White, Red, Green, Blue 四色
  let data = FixedArray::make(1, 0x1B)
  let matrix = encoder.encode(data)
  let ppm = @qr.color_qr_to_ppm(matrix, 0)
  assert_true(ppm.contains("255 0 0"))
  assert_true(ppm.contains("0 255 0"))
  assert_true(ppm.contains("0 0 255"))
  assert_true(ppm.contains("255 255 255"))
}

///|
test "color edge: decode color from rgb size mismatch" {
  // 构造错误尺寸的 RGB 矩阵 (10x10，V1 需要 21x21)
  let wrong_matrix = FixedArray::make(10, FixedArray::make(10, (255, 255, 255)))
  for y = 0; y < 10; y = y + 1 {
    wrong_matrix[y] = FixedArray::make(10, (255, 255, 255))
  }
  let result = @qr.decode_color_from_rgb(wrong_matrix, 1)
  assert_true(result is None)
}

///|
test "color edge: encode decode rgb roundtrip" {
  let encoder = @qr.ColorQREncoder::new(2)
  let original = FixedArray::make(8, 0x5A)
  let matrix = encoder.encode(original)
  let size = matrix.length()
  // 转换为 RGB 矩阵（用循环避免共享引用）
  let rgb_matrix = FixedArray::make(size, FixedArray::make(size, (0, 0, 0)))
  for y = 0; y < size; y = y + 1 {
    rgb_matrix[y] = FixedArray::make(size, (0, 0, 0))
    for x = 0; x < size; x = x + 1 {
      let (r, g, b) = @qr.ColorQRColor::to_rgb(matrix[y][x])
      rgb_matrix[y][x] = (r, g, b)
    }
  }
  match @qr.decode_color_from_rgb(rgb_matrix, 2) {
    Some(decoded) => {
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

///|
test "color edge: encoder size formula" {
  fn check_size(version : Int32, expected : Int32) -> Bool {
    let enc = @qr.ColorQREncoder::new(version)
    let data = FixedArray::make(1, 0x42)
    let mat = enc.encode(data)
    mat.length() == expected
  }
  // size = version * 4 + 17
  assert_true(check_size(1, 21))
  assert_true(check_size(2, 25))
  assert_true(check_size(5, 37))
  assert_true(check_size(10, 57))
}
