// Color QR mapping completeness tests (blackbox).
// Covers byte<->color<->RGB bijection, noise RGB recognition,
// 2x2 block mapping, capacity formula, matrix size parity, and
// color enum completeness. Uses only public API of color_qr.mbt.

///|
test "mapping: byte to color to rgb to color to byte roundtrip all 256" {
  // 全 256 字节 → 4 颜色 → RGB → 颜色 → 字节 往返一致性
  for byte = 0; byte < 256; byte = byte + 1 {
    let bits0 = (byte >> 6) & 0x03
    let bits1 = (byte >> 4) & 0x03
    let bits2 = (byte >> 2) & 0x03
    let bits3 = byte & 0x03
    let c0 = @qr.ColorQRColor::from_bits(bits0)
    let c1 = @qr.ColorQRColor::from_bits(bits1)
    let c2 = @qr.ColorQRColor::from_bits(bits2)
    let c3 = @qr.ColorQRColor::from_bits(bits3)
    let (r0, g0, b0) = @qr.ColorQRColor::to_rgb(c0)
    let (r1, g1, b1) = @qr.ColorQRColor::to_rgb(c1)
    let (r2, g2, b2) = @qr.ColorQRColor::to_rgb(c2)
    let (r3, g3, b3) = @qr.ColorQRColor::to_rgb(c3)
    let rc0 = @qr.ColorQRColor::from_rgb(r0, g0, b0)
    let rc1 = @qr.ColorQRColor::from_rgb(r1, g1, b1)
    let rc2 = @qr.ColorQRColor::from_rgb(r2, g2, b2)
    let rc3 = @qr.ColorQRColor::from_rgb(r3, g3, b3)
    let reconstructed = (@qr.ColorQRColor::to_bits(rc0) << 6) |
      (@qr.ColorQRColor::to_bits(rc1) << 4) |
      (@qr.ColorQRColor::to_bits(rc2) << 2) |
      @qr.ColorQRColor::to_bits(rc3)
    assert_true(reconstructed == byte)
  }
}

///|
test "mapping: each color exact rgb value" {
  // 每种颜色的 RGB 值精确校验
  let (rw, gw, bw) = @qr.ColorQRColor::to_rgb(@qr.color_white())
  assert_true(rw == 255 && gw == 255 && bw == 255)
  let (rr, gr, br) = @qr.ColorQRColor::to_rgb(@qr.color_red())
  assert_true(rr == 255 && gr == 0 && br == 0)
  let (rgc, gg, bg) = @qr.ColorQRColor::to_rgb(@qr.color_green())
  assert_true(rgc == 0 && gg == 255 && bg == 0)
  let (rb, gb, bb) = @qr.ColorQRColor::to_rgb(@qr.color_blue())
  assert_true(rb == 0 && gb == 0 && bb == 255)
}

///|
test "mapping: from rgb noise near white" {
  // 接近 White 的噪声 RGB（三分量均 > 128）应识别为 White
  let cases : Array[(Int32, Int32, Int32)] = [
    (200, 200, 200),
    (250, 240, 230),
    (180, 200, 220),
    (129, 129, 129),
    (255, 255, 255),
    (200, 150, 180),
  ]
  for i = 0; i < cases.length(); i = i + 1 {
    let (r, g, b) = cases[i]
    assert_true(@qr.ColorQRColor::from_rgb(r, g, b) == @qr.color_white())
  }
}

///|
test "mapping: from rgb noise near red" {
  // 接近 Red 的噪声 RGB（r>128, g<=128, b<=128）应识别为 Red
  let cases : Array[(Int32, Int32, Int32)] = [
    (200, 50, 50),
    (250, 0, 30),
    (180, 100, 80),
    (129, 128, 128),
    (255, 0, 0),
    (200, 128, 0),
  ]
  for i = 0; i < cases.length(); i = i + 1 {
    let (r, g, b) = cases[i]
    assert_true(@qr.ColorQRColor::from_rgb(r, g, b) == @qr.color_red())
  }
}

///|
test "mapping: from rgb noise near green" {
  // 接近 Green 的噪声 RGB（r<=128, g>128, b<=128）应识别为 Green
  let cases : Array[(Int32, Int32, Int32)] = [
    (50, 200, 50),
    (30, 250, 0),
    (100, 180, 80),
    (128, 129, 128),
    (0, 255, 0),
    (128, 200, 100),
  ]
  for i = 0; i < cases.length(); i = i + 1 {
    let (r, g, b) = cases[i]
    assert_true(@qr.ColorQRColor::from_rgb(r, g, b) == @qr.color_green())
  }
}

///|
test "mapping: from rgb noise near blue" {
  // 落入 else 分支的 RGB（含接近 Blue、黄、品红、青等）应识别为 Blue
  let cases : Array[(Int32, Int32, Int32)] = [
    (50, 50, 200),
    (30, 0, 250),
    (100, 80, 180),
    (0, 0, 255),
    (200, 200, 0),
    (200, 0, 200),
    (0, 200, 200),
    (128, 128, 128),
    (0, 0, 0),
  ]
  for i = 0; i < cases.length(); i = i + 1 {
    let (r, g, b) = cases[i]
    assert_true(@qr.ColorQRColor::from_rgb(r, g, b) == @qr.color_blue())
  }
}

///|
test "mapping: to rgb from rgb bijection all colors" {
  // to_rgb/from_rgb 双射：颜色 → RGB → 颜色 一致（4 色全覆盖）
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
  // 双向唯一性：不同颜色 → 不同 RGB
  for i = 0; i < colors.length(); i = i + 1 {
    for j = i + 1; j < colors.length(); j = j + 1 {
      let (ri, gi, bi) = @qr.ColorQRColor::to_rgb(colors[i])
      let (rj, gj, bj) = @qr.ColorQRColor::to_rgb(colors[j])
      let different = ri != rj || gi != gj || bi != bj
      assert_true(different)
    }
  }
}

///|
test "mapping: 2x2 block to 4 colors to 1 byte" {
  // 2x2 块 → 4 颜色 → 1 字节 映射正确
  // 对若干代表性字节，encode 后取左上 2x2 块重组字节，应等于原字节
  let values : Array[Int32] = [0x00, 0x1B, 0x55, 0xAA, 0xFF, 0x42, 0x99, 0x37]
  for vi = 0; vi < values.length(); vi = vi + 1 {
    let encoder = @qr.ColorQREncoder::new(1)
    let data = FixedArray::make(1, values[vi])
    let matrix = encoder.encode(data)
    let c0 = matrix[0][0]
    let c1 = matrix[0][1]
    let c2 = matrix[1][0]
    let c3 = matrix[1][1]
    let byte = (@qr.ColorQRColor::to_bits(c0) << 6) |
      (@qr.ColorQRColor::to_bits(c1) << 4) |
      (@qr.ColorQRColor::to_bits(c2) << 2) |
      @qr.ColorQRColor::to_bits(c3)
    assert_true(byte == values[vi])
  }
}

///|
test "mapping: 1 byte to 4 colors to 2x2 block" {
  // 1 字节 → 4 颜色 → 2x2 块 映射正确（全 256 字节）
  for byte = 0; byte < 256; byte = byte + 1 {
    let encoder = @qr.ColorQREncoder::new(1)
    let data = FixedArray::make(1, byte)
    let matrix = encoder.encode(data)
    let expected_c0 = @qr.ColorQRColor::from_bits((byte >> 6) & 0x03)
    let expected_c1 = @qr.ColorQRColor::from_bits((byte >> 4) & 0x03)
    let expected_c2 = @qr.ColorQRColor::from_bits((byte >> 2) & 0x03)
    let expected_c3 = @qr.ColorQRColor::from_bits(byte & 0x03)
    assert_true(matrix[0][0] == expected_c0)
    assert_true(matrix[0][1] == expected_c1)
    assert_true(matrix[1][0] == expected_c2)
    assert_true(matrix[1][1] == expected_c3)
  }
}

///|
test "mapping: full 256 bytes encode decode roundtrip" {
  // 彩色 QR 编解码全 256 字节往返
  // V5 size=37, 容量 = (37/2)^2 = 324 >= 256
  let encoder = @qr.ColorQREncoder::new(5)
  let data = FixedArray::make(256, 0)
  for i = 0; i < 256; i = i + 1 {
    data[i] = i
  }
  let matrix = encoder.encode(data)
  match encoder.decode(matrix) {
    Some(decoded) => {
      assert_true(decoded.length() >= 256)
      let mut all_match = true
      for i = 0; i < 256; i = i + 1 {
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
test "mapping: capacity formula across versions" {
  // 不同版本彩色 QR 容量：(size/2)^2 字节
  fn check_capacity(version : Int32) -> Bool {
    let enc = @qr.ColorQREncoder::new(version)
    let size = version * 4 + 17
    let capacity = size / 2 * (size / 2)
    let data = FixedArray::make(capacity, 0)
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
  // V1: (21/2)^2 = 100, V2: (25/2)^2 = 144, V5: (37/2)^2 = 324,
  // V10: (57/2)^2 = 784, V20: (97/2)^2 = 2304
  assert_true(check_capacity(1))
  assert_true(check_capacity(2))
  assert_true(check_capacity(5))
  assert_true(check_capacity(10))
  assert_true(check_capacity(20))
  // 精确容量值校验
  assert_true(21 / 2 * (21 / 2) == 100)
  assert_true(25 / 2 * (25 / 2) == 144)
  assert_true(37 / 2 * (37 / 2) == 324)
  assert_true(57 / 2 * (57 / 2) == 784)
  assert_true(97 / 2 * (97 / 2) == 2304)
}

///|
test "mapping: color qr matrix size equals mono qr size" {
  // 彩色 QR 矩阵尺寸 = 黑白 QR 矩阵尺寸 = version*4+17
  for version = 1; version <= 10; version = version + 1 {
    let expected_size = version * 4 + 17
    // 彩色 QR 矩阵尺寸
    let color_enc = @qr.ColorQREncoder::new(version)
    let color_data = FixedArray::make(1, 0x42)
    let color_mat = color_enc.encode(color_data)
    assert_true(color_mat.length() == expected_size)
    // 每行长度也等于 expected_size
    for y = 0; y < expected_size; y = y + 1 {
      assert_true(color_mat[y].length() == expected_size)
    }
    // 黑白 QR 矩阵尺寸（1 字节数据不会触发版本升级）
    let mono_data = FixedArray::make(1, 0x42)
    let qr = @qr.encode_binary(mono_data, @qr.ecc_low(), version)
    assert_true(qr.version() == version)
    assert_true(qr.size() == expected_size)
    // 两者尺寸一致
    assert_true(color_mat.length() == qr.size())
  }
}

///|
test "mapping: color enum completeness" {
  // 颜色枚举完备性：遍历所有颜色值，to_bits 覆盖 0..3，from_bits(to_bits(c)) == c
  let colors = [
    @qr.color_white(),
    @qr.color_red(),
    @qr.color_green(),
    @qr.color_blue(),
  ]
  // 每个颜色的 bits 在 0..3 范围内
  for i = 0; i < colors.length(); i = i + 1 {
    let bits = @qr.ColorQRColor::to_bits(colors[i])
    assert_true(bits >= 0 && bits < 4)
  }
  // to_bits 的值两两不同（枚举完备）
  for i = 0; i < colors.length(); i = i + 1 {
    for j = i + 1; j < colors.length(); j = j + 1 {
      assert_true(
        @qr.ColorQRColor::to_bits(colors[i]) !=
        @qr.ColorQRColor::to_bits(colors[j]),
      )
    }
  }
  // from_bits(to_bits(c)) == c（往返一致）
  for i = 0; i < colors.length(); i = i + 1 {
    let c = colors[i]
    let bits = @qr.ColorQRColor::to_bits(c)
    assert_true(@qr.ColorQRColor::from_bits(bits) == c)
  }
  // from_bits(0..3) 恰好覆盖全部 4 种颜色
  let w = @qr.ColorQRColor::from_bits(0)
  let r = @qr.ColorQRColor::from_bits(1)
  let g = @qr.ColorQRColor::from_bits(2)
  let b = @qr.ColorQRColor::from_bits(3)
  assert_true(w == @qr.color_white())
  assert_true(r == @qr.color_red())
  assert_true(g == @qr.color_green())
  assert_true(b == @qr.color_blue())
}

///|
test "mapping: from bits to bits inverse all 4 values" {
  // from_bits/to_bits 互逆：0..3 → color → 0..3 一致
  for bits = 0; bits < 4; bits = bits + 1 {
    let c = @qr.ColorQRColor::from_bits(bits)
    assert_true(@qr.ColorQRColor::to_bits(c) == bits)
  }
  // to_bits/from_bits 互逆：4 色 → bits → 4 色一致
  let colors = [
    @qr.color_white(),
    @qr.color_red(),
    @qr.color_green(),
    @qr.color_blue(),
  ]
  for i = 0; i < colors.length(); i = i + 1 {
    let bits = @qr.ColorQRColor::to_bits(colors[i])
    assert_true(@qr.ColorQRColor::from_bits(bits) == colors[i])
  }
}

///|
test "mapping: rgb roundtrip via decode color from rgb all 256 bytes" {
  // 全 256 字节经 encode → to_rgb 矩阵 → decode_color_from_rgb → 原字节
  // V5 size=37, 容量 = (37/2)^2 = 324 >= 256
  let encoder = @qr.ColorQREncoder::new(5)
  let data = FixedArray::make(256, 0)
  for i = 0; i < 256; i = i + 1 {
    data[i] = i
  }
  let matrix = encoder.encode(data)
  let size = matrix.length()
  // 转 RGB 矩阵（独立行避免共享引用）
  let rgb_matrix = FixedArray::make(size, FixedArray::make(size, (0, 0, 0)))
  for y = 0; y < size; y = y + 1 {
    rgb_matrix[y] = FixedArray::make(size, (0, 0, 0))
    for x = 0; x < size; x = x + 1 {
      let (r, g, b) = @qr.ColorQRColor::to_rgb(matrix[y][x])
      rgb_matrix[y][x] = (r, g, b)
    }
  }
  // 从 RGB 矩阵解码
  match @qr.decode_color_from_rgb(rgb_matrix, 5) {
    Some(decoded) => {
      assert_true(decoded.length() >= 256)
      let mut all_match = true
      for i = 0; i < 256; i = i + 1 {
        if data[i] != decoded[i] {
          all_match = false
        }
      }
      assert_true(all_match)
    }
    None => assert_true(false)
  }
}
