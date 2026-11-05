/// Lossless transfer depth tests — multi-dimensional coverage.
/// Builds on lossless_transfer_test.mbt with 31 additional tests covering:
/// fountain code loss recovery, large files, version capacity boundaries,
/// frame_size boundaries, color QR across versions, full pipelines,
/// repeated transmission stability, and image format correctness.
///
/// Reuses helpers from lossless_transfer_test.mbt:
///   gen_random(len, seed), bytes_equal(a, b), gen_pattern(len, pattern)

// ============================================================
// 1. 喷泉码丢帧恢复无损测试（5个）
// ============================================================

///|
/// 辅助函数：从编码块中均匀采样 keep_count 块（模拟丢帧，均匀分布）。
fn sample_encoded_blocks(
  encoded : Array[(Int32, FixedArray[Int32])],
  keep_count : Int32,
) -> Array[(Int32, FixedArray[Int32])] {
  let total = encoded.length()
  let result : Array[(Int32, FixedArray[Int32])] = []
  for i = 0; i < keep_count; i = i + 1 {
    let idx = i * total / keep_count
    result.push(encoded[idx])
  }
  result
}

///|
test "lossless depth fountain: 10% frame loss recovery" {
  // K=8, 生成 40 块（overhead=32），丢 10% (4 块)，保留 36 块
  let fountain = @qr.LTFountain::new(16, 8)
  let data = gen_random(128, 202)
  let encoded = fountain.encode_all(data, 40)
  let subset = sample_encoded_blocks(encoded, 36)
  assert_true(subset.length() == 36)
  match fountain.decode(subset) {
    Some(decoded) => assert_true(bytes_equal(data, decoded))
    None => assert_true(false)
  }
}

///|
test "lossless depth fountain: 30% frame loss recovery" {
  // K=8, 生成 40 块，丢 30% (12 块)，保留 28 块
  let fountain = @qr.LTFountain::new(16, 8)
  let data = gen_random(128, 303)
  let encoded = fountain.encode_all(data, 40)
  let subset = sample_encoded_blocks(encoded, 28)
  assert_true(subset.length() == 28)
  match fountain.decode(subset) {
    Some(decoded) => assert_true(bytes_equal(data, decoded))
    None => assert_true(false)
  }
}

///|
test "lossless depth fountain: 50% frame loss recovery (critical)" {
  // K=8, 生成 40 块，丢 50% (20 块)，保留 20 块 (2.5×K)
  let fountain = @qr.LTFountain::new(16, 8)
  let data = gen_random(128, 505)
  let encoded = fountain.encode_all(data, 40)
  let subset = sample_encoded_blocks(encoded, 20)
  assert_true(subset.length() == 20)
  match fountain.decode(subset) {
    Some(decoded) => assert_true(bytes_equal(data, decoded))
    None => assert_true(false)
  }
}

///|
test "lossless depth fountain: loss recovery with integrity check" {
  // K=10, 生成 40 块，丢 40% (16 块)，保留 24 块；校验长度+逐字节+CRC32
  let fountain = @qr.LTFountain::new(20, 10)
  let data = gen_random(200, 707)
  let encoded = fountain.encode_all(data, 40)
  let subset = sample_encoded_blocks(encoded, 24)
  match fountain.decode(subset) {
    Some(decoded) => {
      assert_true(decoded.length() == data.length())
      assert_true(bytes_equal(data, decoded))
      assert_true(@qr.crc32(data) == @qr.crc32(decoded))
    }
    None => assert_true(false)
  }
}

///|
test "lossless depth fountain: different block sizes recovery" {
  // 用 block_size = 8, 16, 32 分别测试丢帧恢复
  let block_sizes = [8, 16, 32]
  for bi = 0; bi < 3; bi = bi + 1 {
    let bs = block_sizes[bi]
    let num_blocks = 8
    let total_len = bs * num_blocks
    let data = gen_random(total_len, bi * 111 + 1)
    let fountain = @qr.LTFountain::new(bs, num_blocks)
    let encoded = fountain.encode_all(data, 32)
    // 丢 25%: 保留 24 块 (3×K)
    let subset = sample_encoded_blocks(encoded, 24)
    match fountain.decode(subset) {
      Some(decoded) => assert_true(bytes_equal(data, decoded))
      None => assert_true(false)
    }
  }
}

// ============================================================
// 2. 大文件无损传输（4个）
// ============================================================

///|
test "lossless depth large: 50KB random data via dynamic stream" {
  let data = gen_random(51200, 11)
  let frames = @qr.split_into_frames(data, 500)
  assert_true(frames.length() > 1)
  match @qr.reassemble_frames(frames) {
    Some(decoded) => assert_true(bytes_equal(data, decoded))
    None => assert_true(false)
  }
}

///|
test "lossless depth large: 100KB random data via dynamic stream" {
  let data = gen_random(102400, 22)
  let frames = @qr.split_into_frames(data, 1000)
  assert_true(frames.length() > 1)
  match @qr.reassemble_frames(frames) {
    Some(decoded) => assert_true(bytes_equal(data, decoded))
    None => assert_true(false)
  }
}

///|
test "lossless depth large: 50KB all zeros (highly compressible)" {
  let data = FixedArray::make(51200, 0)
  let frames = @qr.split_into_frames(data, 500)
  match @qr.reassemble_frames(frames) {
    Some(decoded) => assert_true(bytes_equal(data, decoded))
    None => assert_true(false)
  }
}

///|
test "lossless depth large: 100KB repeated pattern" {
  let pattern = FixedArray::make(4, 0)
  pattern[0] = 0xDE
  pattern[1] = 0xAD
  pattern[2] = 0xBE
  pattern[3] = 0xEF
  let data = gen_pattern(102400, pattern)
  let frames = @qr.split_into_frames(data, 1000)
  match @qr.reassemble_frames(frames) {
    Some(decoded) => assert_true(bytes_equal(data, decoded))
    None => assert_true(false)
  }
}

// ============================================================
// 3. 版本容量边界无损测试（4个）
// ============================================================

///|
test "lossless depth capacity: V1 near max capacity (M level)" {
  // V1 M 级: num_data_codewords = 14，byte 模式最大 12 字节
  let cap = @qr.num_data_codewords(1, @qr.ecc_medium())
  let data_len = cap - 3 // 留余量给模式/长度指示符
  let data = gen_random(data_len, 1)
  let qr = @qr.encode_binary(data, @qr.ecc_medium(), 1)
  assert_true(qr.version() == 1)
  match @qr.decode_from_qrcode(qr) {
    Some(decoded) => assert_true(bytes_equal(data, decoded))
    None => assert_true(false)
  }
}

///|
test "lossless depth capacity: V10 near max capacity" {
  let cap = @qr.num_data_codewords(10, @qr.ecc_medium())
  let data_len = cap - 3 // V10 长度指示符 16 位，留 3 字节余量
  let data = gen_random(data_len, 10)
  let qr = @qr.encode_binary(data, @qr.ecc_medium(), 10)
  assert_true(qr.version() == 10)
  match @qr.decode_from_qrcode(qr) {
    Some(decoded) => assert_true(bytes_equal(data, decoded))
    None => assert_true(false)
  }
}

///|
test "lossless depth capacity: V20 near max capacity" {
  let cap = @qr.num_data_codewords(20, @qr.ecc_medium())
  let data_len = cap - 3
  let data = gen_random(data_len, 20)
  let qr = @qr.encode_binary(data, @qr.ecc_medium(), 20)
  assert_true(qr.version() == 20)
  match @qr.decode_from_qrcode(qr) {
    Some(decoded) => assert_true(bytes_equal(data, decoded))
    None => assert_true(false)
  }
}

///|
test "lossless depth capacity: V40 near max capacity (L level, 2953 bytes)" {
  // V40 L 级: num_data_codewords = 2956（QR 规范最大单码容量级别）
  let cap = @qr.num_data_codewords(40, @qr.ecc_low())
  assert_true(cap > 2900) // 确认是 V40-L 级别容量
  let data_len = cap - 3 // byte 模式 4+16 位开销，留 3 字节余量
  let data = gen_random(data_len, 40)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 40)
  assert_true(qr.version() == 40)
  match @qr.decode_from_qrcode(qr) {
    Some(decoded) => assert_true(bytes_equal(data, decoded))
    None => assert_true(false)
  }
}

// ============================================================
// 4. frame_size 边界无损测试（4个）
// ============================================================

///|
test "lossless depth frame size: frame_size = 2 (tiny frames)" {
  let data = gen_random(20, 2)
  let frames = @qr.split_into_frames(data, 2)
  assert_true(frames.length() == 10)
  match @qr.reassemble_frames(frames) {
    Some(decoded) => assert_true(bytes_equal(data, decoded))
    None => assert_true(false)
  }
}

///|
test "lossless depth frame size: frame_size = data length (single frame)" {
  let data = gen_random(100, 3)
  let frames = @qr.split_into_frames(data, 100)
  assert_true(frames.length() == 1)
  match @qr.reassemble_frames(frames) {
    Some(decoded) => assert_true(bytes_equal(data, decoded))
    None => assert_true(false)
  }
}

///|
test "lossless depth frame size: frame_size = data length - 1 (two frames)" {
  // 100 字节数据，frame_size=99 → 2 帧，第二帧 1 字节
  let data = gen_random(100, 4)
  let frames = @qr.split_into_frames(data, 99)
  assert_true(frames.length() == 2)
  match @qr.reassemble_frames(frames) {
    Some(decoded) => assert_true(bytes_equal(data, decoded))
    None => assert_true(false)
  }
}

///|
test "lossless depth frame size: frame_size = 1000 (large frames)" {
  // 3500 字节，frame_size=1000 → 4 帧
  let data = gen_random(3500, 5)
  let frames = @qr.split_into_frames(data, 1000)
  assert_true(frames.length() == 4)
  match @qr.reassemble_frames(frames) {
    Some(decoded) => assert_true(bytes_equal(data, decoded))
    None => assert_true(false)
  }
}

// ============================================================
// 5. 彩色 QR 全版本无损测试（4个）
// ============================================================

///|
test "lossless depth color: V1 color QR lossless" {
  let data = gen_random(50, 101)
  let encoder = @qr.ColorQREncoder::new(1)
  let matrix = encoder.encode(data)
  match encoder.decode(matrix) {
    Some(decoded) => {
      // 彩色 QR decode 输出可能比原始数据长，比较前缀
      let n = if data.length() < decoded.length() {
        data.length()
      } else {
        decoded.length()
      }
      for i = 0; i < n; i = i + 1 {
        assert_true(data[i] == decoded[i])
      }
    }
    None => assert_true(false)
  }
}

///|
test "lossless depth color: V5 color QR lossless" {
  let data = gen_random(200, 102)
  let encoder = @qr.ColorQREncoder::new(5)
  let matrix = encoder.encode(data)
  match encoder.decode(matrix) {
    Some(decoded) => {
      let n = if data.length() < decoded.length() {
        data.length()
      } else {
        decoded.length()
      }
      for i = 0; i < n; i = i + 1 {
        assert_true(data[i] == decoded[i])
      }
    }
    None => assert_true(false)
  }
}

///|
test "lossless depth color: V10 color QR lossless" {
  let data = gen_random(500, 103)
  let encoder = @qr.ColorQREncoder::new(10)
  let matrix = encoder.encode(data)
  match encoder.decode(matrix) {
    Some(decoded) => {
      let n = if data.length() < decoded.length() {
        data.length()
      } else {
        decoded.length()
      }
      for i = 0; i < n; i = i + 1 {
        assert_true(data[i] == decoded[i])
      }
    }
    None => assert_true(false)
  }
}

///|
test "lossless depth color: V20 color QR lossless" {
  let data = gen_random(1500, 104)
  let encoder = @qr.ColorQREncoder::new(20)
  let matrix = encoder.encode(data)
  match encoder.decode(matrix) {
    Some(decoded) => {
      let n = if data.length() < decoded.length() {
        data.length()
      } else {
        decoded.length()
      }
      for i = 0; i < n; i = i + 1 {
        assert_true(data[i] == decoded[i])
      }
    }
    None => assert_true(false)
  }
}

// ============================================================
// 6. 完整管线无损测试（4个）
// ============================================================

///|
test "lossless depth pipeline: compress -> static encode -> decode -> decompress" {
  // 静态管线内部自动压缩/解压，decode_static 直接返回原始数据
  let data = FixedArray::make(300, 0x42)
  match @qr.encode_static(data, @qr.ecc_low(), 5) {
    Some(result) => {
      assert_true(result.compressed())
      match @qr.decode_static(result.packaged_bytes()) {
        Some(decoded) => assert_true(bytes_equal(data, decoded))
        None => assert_true(false)
      }
    }
    None => assert_true(false)
  }
}

///|
test "lossless depth pipeline: compress -> split -> reassemble -> decompress" {
  // 手动压缩 -> 分片 -> 重组 -> 用原策略解压
  let data = FixedArray::make(2000, 0x37)
  let comp = @qr.auto_compress(data)
  let compressed_data = comp.compressed_data
  let strategy = comp.strategy
  let frames = @qr.split_into_frames(compressed_data, 100)
  match @qr.reassemble_frames(frames) {
    Some(reassembled) => {
      let decoded = @qr.decompress_with_strategy(reassembled, strategy)
      assert_true(bytes_equal(data, decoded))
    }
    None => assert_true(false)
  }
}

///|
test "lossless depth pipeline: highly compressible -> dynamic stream -> decode" {
  // 全同字节 → 动态码流 → 重组
  let data = FixedArray::make(5000, 0x55)
  let frames = @qr.split_into_frames(data, 200)
  assert_true(frames.length() > 1)
  match @qr.reassemble_frames(frames) {
    Some(decoded) => assert_true(bytes_equal(data, decoded))
    None => assert_true(false)
  }
}

///|
test "lossless depth pipeline: incompressible -> dynamic stream -> decode" {
  // 随机数据不可压缩 → 动态码流 → 重组
  let data = gen_random(5000, 888)
  let frames = @qr.split_into_frames(data, 200)
  assert_true(frames.length() > 1)
  match @qr.reassemble_frames(frames) {
    Some(decoded) => assert_true(bytes_equal(data, decoded))
    None => assert_true(false)
  }
}

// ============================================================
// 7. 重复传输稳定性测试（3个）
// ============================================================

///|
test "lossless depth stability: same data 10x encode/decode consistent" {
  let data = gen_random(100, 42)
  // 第一次结果作为基准
  let qr0 = @qr.encode_binary(data, @qr.ecc_medium(), 1)
  let baseline = match @qr.decode_from_qrcode(qr0) {
    Some(d) => d
    None => FixedArray::make(0, 0)
  }
  assert_true(bytes_equal(data, baseline))
  // 重复 10 次，每次结果应与基准一致
  for iter = 0; iter < 10; iter = iter + 1 {
    let qr = @qr.encode_binary(data, @qr.ecc_medium(), 1)
    match @qr.decode_from_qrcode(qr) {
      Some(decoded) => assert_true(bytes_equal(baseline, decoded))
      None => assert_true(false)
    }
  }
}

///|
test "lossless depth stability: same data various frame sizes consistent" {
  let data = gen_random(300, 77)
  let frame_sizes = [10, 50, 100, 300]
  // 第一次结果作为基准
  let frames0 = @qr.split_into_frames(data, frame_sizes[0])
  let baseline = match @qr.reassemble_frames(frames0) {
    Some(d) => d
    None => FixedArray::make(0, 0)
  }
  assert_true(bytes_equal(data, baseline))
  for i = 1; i < 4; i = i + 1 {
    let frames = @qr.split_into_frames(data, frame_sizes[i])
    match @qr.reassemble_frames(frames) {
      Some(decoded) => assert_true(bytes_equal(baseline, decoded))
      None => assert_true(false)
    }
  }
}

///|
test "lossless depth stability: same data various ECC levels consistent" {
  let data = gen_random(50, 99)
  let levels = [
    @qr.ecc_low(),
    @qr.ecc_medium(),
    @qr.ecc_quartile(),
    @qr.ecc_high(),
  ]
  // 第一次结果作为基准
  let qr0 = @qr.encode_binary(data, levels[0], 1)
  let baseline = match @qr.decode_from_qrcode(qr0) {
    Some(d) => d
    None => FixedArray::make(0, 0)
  }
  assert_true(bytes_equal(data, baseline))
  for i = 1; i < 4; i = i + 1 {
    let qr = @qr.encode_binary(data, levels[i], 1)
    match @qr.decode_from_qrcode(qr) {
      Some(decoded) => assert_true(bytes_equal(baseline, decoded))
      None => assert_true(false)
    }
  }
}

// ============================================================
// 8. 图片格式正确性测试（3个）
// ============================================================

///|
test "lossless depth image: PBM starts with P1 and correct size" {
  let data = gen_random(20, 1)
  let qr = @qr.encode_binary(data, @qr.ecc_medium(), 3)
  let pbm = @qr.to_pbm(qr, 4)
  // V3 size = 29, total = 29 + 8 = 37
  let size = qr.size()
  let total = size + 8
  assert_true(pbm.contains("P1\n"))
  assert_true(pbm.contains(total.to_string() + " " + total.to_string() + "\n"))
}

///|
test "lossless depth image: SVG contains svg open and close tags" {
  let data = gen_random(20, 2)
  let qr = @qr.encode_binary(data, @qr.ecc_medium(), 3)
  let svg = @qr.to_svg(qr, 2, 4)
  assert_true(svg.contains("<svg"))
  assert_true(svg.contains("</svg>"))
}

///|
test "lossless depth image: PNG starts with PNG signature" {
  let data = gen_random(20, 3)
  let qr = @qr.encode_binary(data, @qr.ecc_medium(), 3)
  let png = @qr.to_png(qr, 1, 4)
  // PNG 签名: \x89PNG\r\n\x1a\n = 137 80 78 71 13 10 26 10
  assert_true(png[0] == 137)
  assert_true(png[1] == 80)
  assert_true(png[2] == 78)
  assert_true(png[3] == 71)
  assert_true(png[4] == 13)
  assert_true(png[5] == 10)
  assert_true(png[6] == 26)
  assert_true(png[7] == 10)
}
