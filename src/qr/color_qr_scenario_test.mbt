// Multi-scenario blackbox tests for color QR code.
// Covers roundtrips across versions, color counts, sizes, capacities,
// byte<->RGB bijection, image dimensions, and color-vs-mono capacity ratio.

///|
test "scenario: basic roundtrip various bytes" {
  // 基本编解码往返：多种字节值
  let encoder = @qr.ColorQREncoder::new(1)
  let values : Array[Int32] = [0x00, 0x01, 0x55, 0xAA, 0xFF, 0x42, 0x99, 0x37]
  for i = 0; i < values.length(); i = i + 1 {
    let data = FixedArray::make(8, values[i])
    let matrix = encoder.encode(data)
    match encoder.decode(matrix) {
      Some(decoded) => {
        let mut all_match = true
        for j = 0; j < data.length(); j = j + 1 {
          if data[j] != decoded[j] {
            all_match = false
          }
        }
        assert_true(all_match)
      }
      None => assert_true(false)
    }
  }
}

///|
test "scenario: versions v1 v5 v10 v20 roundtrip" {
  // 不同版本彩色 QR 编解码往返
  fn check_version(version : Int32, count : Int32, value : Int32) -> Bool {
    let enc = @qr.ColorQREncoder::new(version)
    let data = FixedArray::make(count, value)
    let mat = enc.encode(data)
    match enc.decode(mat) {
      Some(decoded) => {
        let mut ok = true
        for i = 0; i < data.length(); i = i + 1 {
          if data[i] != decoded[i] {
            ok = false
          }
        }
        ok
      }
      None => false
    }
  }
  // V1 size=21, V5 size=37, V10 size=57, V20 size=97
  assert_true(check_version(1, 50, 0x5A))
  assert_true(check_version(5, 200, 0x37))
  assert_true(check_version(10, 500, 0xA3))
  assert_true(check_version(20, 1000, 0x6C))
}

///|
test "scenario: two color data roundtrip" {
  // 2 色：只用 White(00) 和 Red(01)
  // 0x00 = 00000000 (全 White), 0x55 = 01010101 (全 Red)
  let encoder = @qr.ColorQREncoder::new(3)
  let data : FixedArray[Int32] = FixedArray::make(16, 0x00)
  for i = 0; i < 16; i = i + 1 {
    if i % 2 == 0 {
      data[i] = 0x00
    } else {
      data[i] = 0x55
    }
  }
  let matrix = encoder.encode(data)
  // 验证矩阵只含 White 和 Red
  let size = matrix.length()
  let mut only_two_colors = true
  for y = 0; y < size; y = y + 1 {
    for x = 0; x < size; x = x + 1 {
      let c = matrix[y][x]
      if c != @qr.color_white() && c != @qr.color_red() {
        only_two_colors = false
      }
    }
  }
  assert_true(only_two_colors)
  // 解码往返
  match encoder.decode(matrix) {
    Some(decoded) => {
      let mut all_match = true
      for i = 0; i < data.length(); i = i + 1 {
        if data[i] != decoded[i] {
          all_match = false
        }
      }
      assert_true(all_match)
    }
    None => assert_true(false)
  }
}

///|
test "scenario: three color data roundtrip" {
  // 3 色：White(00), Red(01), Green(10)，不含 Blue(11)
  // 0x00 (全 White), 0x55 (全 Red), 0xAA (全 Green)
  let encoder = @qr.ColorQREncoder::new(3)
  let data : FixedArray[Int32] = FixedArray::make(24, 0x00)
  for i = 0; i < 24; i = i + 1 {
    let m = i % 3
    if m == 0 {
      data[i] = 0x00
    } else if m == 1 {
      data[i] = 0x55
    } else {
      data[i] = 0xAA
    }
  }
  let matrix = encoder.encode(data)
  // 验证矩阵不含 Blue
  let size = matrix.length()
  let mut no_blue = true
  for y = 0; y < size; y = y + 1 {
    for x = 0; x < size; x = x + 1 {
      if matrix[y][x] == @qr.color_blue() {
        no_blue = false
      }
    }
  }
  assert_true(no_blue)
  // 解码往返
  match encoder.decode(matrix) {
    Some(decoded) => {
      let mut all_match = true
      for i = 0; i < data.length(); i = i + 1 {
        if data[i] != decoded[i] {
          all_match = false
        }
      }
      assert_true(all_match)
    }
    None => assert_true(false)
  }
}

///|
test "scenario: four color data roundtrip" {
  // 4 色：White, Red, Green, Blue 全用
  // 0x1B = 00011011 → c0=White, c1=Red, c2=Green, c3=Blue
  let encoder = @qr.ColorQREncoder::new(3)
  let data = FixedArray::make(16, 0x1B)
  let matrix = encoder.encode(data)
  // 验证矩阵包含全部 4 色
  let size = matrix.length()
  let mut has_w = false
  let mut has_r = false
  let mut has_g = false
  let mut has_b = false
  for y = 0; y < size; y = y + 1 {
    for x = 0; x < size; x = x + 1 {
      let c = matrix[y][x]
      if c == @qr.color_white() {
        has_w = true
      }
      if c == @qr.color_red() {
        has_r = true
      }
      if c == @qr.color_green() {
        has_g = true
      }
      if c == @qr.color_blue() {
        has_b = true
      }
    }
  }
  assert_true(has_w && has_r && has_g && has_b)
  // 解码往返
  match encoder.decode(matrix) {
    Some(decoded) => {
      let mut all_match = true
      for i = 0; i < data.length(); i = i + 1 {
        if data[i] != decoded[i] {
          all_match = false
        }
      }
      assert_true(all_match)
    }
    None => assert_true(false)
  }
}

///|
test "scenario: all versions odd size" {
  // size = 4*v + 17 永远是奇数；最后一行/列因 size/2 向下取整保持 White
  fn check_odd(version : Int32) -> Bool {
    let enc = @qr.ColorQREncoder::new(version)
    let data = FixedArray::make(1, 0xFF)
    let mat = enc.encode(data)
    let size = mat.length()
    // size 应为奇数
    if size % 2 == 0 {
      return false
    }
    // 最后一行和最后一列应为 White（未被 2x2 块覆盖）
    let mut last_row_white = true
    for x = 0; x < size; x = x + 1 {
      if mat[size - 1][x] != @qr.color_white() {
        last_row_white = false
      }
    }
    let mut last_col_white = true
    for y = 0; y < size; y = y + 1 {
      if mat[y][size - 1] != @qr.color_white() {
        last_col_white = false
      }
    }
    last_row_white && last_col_white
  }
  assert_true(check_odd(1))
  assert_true(check_odd(2))
  assert_true(check_odd(5))
  assert_true(check_odd(10))
  assert_true(check_odd(20))
}

///|
test "scenario: empty data roundtrip" {
  // 空数据：矩阵全 White，解码不崩溃
  let encoder = @qr.ColorQREncoder::new(2)
  let data = FixedArray::make(0, 0)
  let matrix = encoder.encode(data)
  let size = matrix.length()
  let mut all_white = true
  for y = 0; y < size; y = y + 1 {
    for x = 0; x < size; x = x + 1 {
      if matrix[y][x] != @qr.color_white() {
        all_white = false
      }
    }
  }
  assert_true(all_white)
  // 解码输出长度 = (size/2)^2
  match encoder.decode(matrix) {
    Some(d) => assert_true(d.length() == size / 2 * (size / 2))
    None => assert_true(false)
  }
}

///|
test "scenario: single byte roundtrip" {
  // 单字节多种值
  let values : Array[Int32] = [0x00, 0x01, 0x5A, 0x7F, 0x80, 0xAA, 0xFF]
  for i = 0; i < values.length(); i = i + 1 {
    let encoder = @qr.ColorQREncoder::new(1)
    let data = FixedArray::make(1, values[i])
    let matrix = encoder.encode(data)
    match encoder.decode(matrix) {
      Some(decoded) => assert_true(decoded[0] == values[i])
      None => assert_true(false)
    }
  }
}

///|
test "scenario: full capacity roundtrip" {
  // 满容量：容量 = (size/2)^2 字节
  fn check_full(version : Int32) -> Bool {
    let enc = @qr.ColorQREncoder::new(version)
    let size = version * 4 + 17
    let capacity = size / 2 * (size / 2)
    let data = FixedArray::make(capacity, 0)
    // 填入不同字节值以增强覆盖
    for i = 0; i < capacity; i = i + 1 {
      data[i] = i % 256
    }
    let mat = enc.encode(data)
    match enc.decode(mat) {
      Some(decoded) => {
        if decoded.length() != capacity {
          return false
        }
        let mut ok = true
        for i = 0; i < capacity; i = i + 1 {
          if data[i] != decoded[i] {
            ok = false
          }
        }
        ok
      }
      None => false
    }
  }
  assert_true(check_full(1)) // capacity = 100
  assert_true(check_full(5)) // capacity = 324
  assert_true(check_full(10)) // capacity = 784
}

///|
test "scenario: byte rgb byte bijection" {
  // 颜色 → RGB → 颜色 一致性（4 色全覆盖）
  let colors = [
    @qr.color_white(),
    @qr.color_red(),
    @qr.color_green(),
    @qr.color_blue(),
  ]
  for i = 0; i < colors.length(); i = i + 1 {
    let c = colors[i]
    let (r, g, b) = @qr.ColorQRColor::to_rgb(c)
    let rc = @qr.ColorQRColor::from_rgb(r, g, b)
    assert_true(rc == c)
  }
  // byte → 4 colors → RGB → colors → byte 一致性（遍历全部 256 字节）
  let encoder = @qr.ColorQREncoder::new(2)
  for byte = 0; byte < 256; byte = byte + 1 {
    let data = FixedArray::make(1, byte)
    let matrix = encoder.encode(data)
    let c0 = matrix[0][0]
    let c1 = matrix[0][1]
    let c2 = matrix[1][0]
    let c3 = matrix[1][1]
    let (r0, g0, b0) = @qr.ColorQRColor::to_rgb(c0)
    let (r1, g1, b1) = @qr.ColorQRColor::to_rgb(c1)
    let (r2, g2, b2) = @qr.ColorQRColor::to_rgb(c2)
    let (r3, g3, b3) = @qr.ColorQRColor::to_rgb(c3)
    let rc0 = @qr.ColorQRColor::from_rgb(r0, g0, b0)
    let rc1 = @qr.ColorQRColor::from_rgb(r1, g1, b1)
    let rc2 = @qr.ColorQRColor::from_rgb(r2, g2, b2)
    let rc3 = @qr.ColorQRColor::from_rgb(r3, g3, b3)
    assert_true(rc0 == c0)
    assert_true(rc1 == c1)
    assert_true(rc2 == c2)
    assert_true(rc3 == c3)
    let reconstructed = (@qr.ColorQRColor::to_bits(rc0) << 6) |
      (@qr.ColorQRColor::to_bits(rc1) << 4) |
      (@qr.ColorQRColor::to_bits(rc2) << 2) |
      @qr.ColorQRColor::to_bits(rc3)
    assert_true(reconstructed == byte)
  }
}

///|
test "scenario: image size correct svg" {
  // SVG 尺寸：total = size + quiet_zone*2, width/height = total * scale
  fn check_svg_size(version : Int32, scale : Int32, quiet : Int32) -> Bool {
    let enc = @qr.ColorQREncoder::new(version)
    let data = FixedArray::make(4, 0x42)
    let mat = enc.encode(data)
    let svg = @qr.color_qr_to_svg(mat, scale, quiet)
    let size = version * 4 + 17
    let total = size + quiet * 2
    let expected = (total * scale).to_string()
    svg.contains("width=\"" + expected + "\"") &&
    svg.contains("height=\"" + expected + "\"")
  }
  assert_true(check_svg_size(1, 10, 4)) // total=29, dim=290
  assert_true(check_svg_size(5, 5, 2)) // total=41, dim=205
  assert_true(check_svg_size(10, 1, 0)) // total=57, dim=57
}

///|
test "scenario: image size correct ppm" {
  // PPM 尺寸：header "P3\n total total\n255\n", total = size + quiet_zone*2
  fn check_ppm_size(version : Int32, quiet : Int32) -> Bool {
    let enc = @qr.ColorQREncoder::new(version)
    let data = FixedArray::make(4, 0x42)
    let mat = enc.encode(data)
    let ppm = @qr.color_qr_to_ppm(mat, quiet)
    let size = version * 4 + 17
    let total = size + quiet * 2
    let header = "P3\n" +
      total.to_string() +
      " " +
      total.to_string() +
      "\n255\n"
    ppm.contains(header)
  }
  assert_true(check_ppm_size(1, 4)) // total=29
  assert_true(check_ppm_size(5, 2)) // total=41
  assert_true(check_ppm_size(10, 0)) // total=57
}

///|
test "scenario: color vs mono capacity ratio" {
  // 彩色 QR: 每 2x2 块存 1 字节，容量 = (size/2)^2 字节
  // 黑白 QR: 每模块 1 位，容量 = size^2 / 8 字节
  // 彩色容量约为黑白的 2 倍（size 奇数时略小）
  fn color_cap(version : Int32) -> Int32 {
    let size = version * 4 + 17
    size / 2 * (size / 2)
  }
  fn mono_cap(version : Int32) -> Int32 {
    let size = version * 4 + 17
    size * size / 8
  }
  // 彩色容量严格大于黑白容量
  assert_true(color_cap(1) > mono_cap(1)) // 100 > 55
  assert_true(color_cap(5) > mono_cap(5)) // 324 > 171
  assert_true(color_cap(10) > mono_cap(10)) // 784 > 406
  assert_true(color_cap(20) > mono_cap(20)) // 2304 > 1176
  // 比例约为 2 倍：1.5*mono < color < 2.5*mono（整数运算：3*mono < 2*color < 5*mono）
  assert_true(3 * mono_cap(1) < 2 * color_cap(1))
  assert_true(2 * color_cap(1) < 5 * mono_cap(1))
  assert_true(3 * mono_cap(10) < 2 * color_cap(10))
  assert_true(2 * color_cap(10) < 5 * mono_cap(10))
  // 精确值校验
  assert_true(color_cap(1) == 100)
  assert_true(mono_cap(1) == 55)
  assert_true(color_cap(10) == 784)
  assert_true(mono_cap(10) == 406)
}

///|
test "scenario: rgb matrix full roundtrip" {
  // 数据 → encode → to RGB matrix → decode_color_from_rgb → 验证
  fn check_rgb_roundtrip(
    version : Int32,
    count : Int32,
    value : Int32,
  ) -> Bool {
    let enc = @qr.ColorQREncoder::new(version)
    let data = FixedArray::make(count, value)
    let mat = enc.encode(data)
    let size = mat.length()
    // 转 RGB 矩阵（独立行避免共享引用）
    let rgb_matrix = FixedArray::make(size, FixedArray::make(size, (0, 0, 0)))
    for y = 0; y < size; y = y + 1 {
      rgb_matrix[y] = FixedArray::make(size, (0, 0, 0))
      for x = 0; x < size; x = x + 1 {
        let (r, g, b) = @qr.ColorQRColor::to_rgb(mat[y][x])
        rgb_matrix[y][x] = (r, g, b)
      }
    }
    // 从 RGB 解码
    match @qr.decode_color_from_rgb(rgb_matrix, version) {
      Some(decoded) => {
        let mut ok = true
        for i = 0; i < data.length(); i = i + 1 {
          if data[i] != decoded[i] {
            ok = false
          }
        }
        ok
      }
      None => false
    }
  }
  assert_true(check_rgb_roundtrip(1, 50, 0x5A))
  assert_true(check_rgb_roundtrip(5, 200, 0x37))
  assert_true(check_rgb_roundtrip(10, 500, 0xA3))
}
