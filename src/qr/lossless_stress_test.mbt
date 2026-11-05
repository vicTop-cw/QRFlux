/// Lossless transfer stress tests — four-dimensional coverage.
/// Builds on lossless_transfer_test.mbt and lossless_depth_test.mbt with 44
/// additional stress tests covering: performance baselines, fuzz testing,
/// V27~V39 middle version coverage, and multi-frame disorder/loss scenarios.
///
/// Reuses helpers from lossless_transfer_test.mbt:
///   gen_random(len, seed), bytes_equal(a, b), gen_pattern(len, pattern)
/// Reuses helpers from lossless_depth_test.mbt:
///   sample_encoded_blocks(encoded, keep_count)

// ============================================================
// 辅助函数
// ============================================================

///|
/// 辅助函数：将编码块数组完全反序（用于模拟乱序传输）。
fn reverse_encoded_blocks(
  encoded : Array[(Int32, FixedArray[Int32])],
) -> Array[(Int32, FixedArray[Int32])] {
  let n = encoded.length()
  let result : Array[(Int32, FixedArray[Int32])] = []
  for i = 0; i < n; i = i + 1 {
    result.push(encoded[n - 1 - i])
  }
  result
}

///|
/// 辅助函数：测试指定版本和 ECC 级的近容量无损传输。
/// 从 num_data_codewords - 2 开始递减数据长度，直到 encode_binary 生成的
/// QR 版本与目标版本匹配，然后验证编解码无损。返回 true 表示成功。
fn test_version_near_capacity(
  version : Int32,
  level : @qr.EccLevel,
  seed : Int32,
) -> Bool {
  let cap = @qr.num_data_codewords(version, level)
  let mut data_len = cap - 2
  while data_len > 0 {
    let data = gen_random(data_len, seed)
    let qr = @qr.encode_binary(data, level, version)
    if qr.version() == version {
      match @qr.decode_from_qrcode(qr) {
        Some(decoded) => return bytes_equal(data, decoded)
        None => return false
      }
    }
    data_len = data_len - 1
  }
  false
}

///|
/// 辅助函数：生成前半正序后半倒序的编码块数组（部分乱序）。
fn partial_shuffle_encoded_blocks(
  encoded : Array[(Int32, FixedArray[Int32])],
) -> Array[(Int32, FixedArray[Int32])] {
  let n = encoded.length()
  let half = n / 2
  let result : Array[(Int32, FixedArray[Int32])] = []
  // 前半正序
  for i = 0; i < half; i = i + 1 {
    result.push(encoded[i])
  }
  // 后半倒序
  for i = 0; i < n - half; i = i + 1 {
    result.push(encoded[n - 1 - i])
  }
  result
}

// ============================================================
// 1. 性能基准测试（8个）
// ============================================================

///|
test "stress perf: V40 L level encode/decode 10x consistent" {
  let cap = @qr.num_data_codewords(40, @qr.ecc_low())
  let data = gen_random(cap - 3, 40)
  // 基准结果
  let qr0 = @qr.encode_binary(data, @qr.ecc_low(), 40)
  let baseline = match @qr.decode_from_qrcode(qr0) {
    Some(d) => d
    None => FixedArray::make(0, 0)
  }
  assert_true(bytes_equal(data, baseline))
  // 重复 10 次，每次结果应与基准一致且正确
  for iter = 0; iter < 10; iter = iter + 1 {
    let qr = @qr.encode_binary(data, @qr.ecc_low(), 40)
    match @qr.decode_from_qrcode(qr) {
      Some(decoded) => assert_true(bytes_equal(baseline, decoded))
      None => assert_true(false)
    }
  }
}

///|
test "stress perf: V40 H level encode/decode 10x consistent" {
  let cap = @qr.num_data_codewords(40, @qr.ecc_high())
  let data = gen_random(cap - 3, 41)
  let qr0 = @qr.encode_binary(data, @qr.ecc_high(), 40)
  let baseline = match @qr.decode_from_qrcode(qr0) {
    Some(d) => d
    None => FixedArray::make(0, 0)
  }
  assert_true(bytes_equal(data, baseline))
  for iter = 0; iter < 10; iter = iter + 1 {
    let qr = @qr.encode_binary(data, @qr.ecc_high(), 40)
    match @qr.decode_from_qrcode(qr) {
      Some(decoded) => assert_true(bytes_equal(baseline, decoded))
      None => assert_true(false)
    }
  }
}

///|
test "stress perf: 100KB random data dynamic stream lossless" {
  let data = gen_random(102400, 100)
  let frames = @qr.split_into_frames(data, 1000)
  assert_true(frames.length() > 1)
  match @qr.reassemble_frames(frames) {
    Some(decoded) => assert_true(bytes_equal(data, decoded))
    None => assert_true(false)
  }
}

///|
test "stress perf: 50KB all zeros static pipeline lossless" {
  // 50KB 全零，RLE 压缩后极小（4 字节），可放入单个 QR
  let data = FixedArray::make(51200, 0)
  match @qr.encode_static(data, @qr.ecc_low(), 1) {
    Some(result) =>
      match @qr.decode_static(result.packaged_bytes()) {
        Some(decoded) => assert_true(bytes_equal(data, decoded))
        None => assert_true(false)
      }
    None => assert_true(false)
  }
}

///|
test "stress perf: V1~V40 each version encode once" {
  // 用小数据确保每个版本都能编码
  let data = gen_random(10, 2024)
  for v = 1; v <= 40; v = v + 1 {
    let qr = @qr.encode_binary(data, @qr.ecc_medium(), v)
    assert_true(qr.version() >= v)
    match @qr.decode_from_qrcode(qr) {
      Some(decoded) => assert_true(bytes_equal(data, decoded))
      None => assert_true(false)
    }
  }
}

///|
test "stress perf: 1000x V5 encode consistent" {
  let data = gen_random(50, 5)
  let qr0 = @qr.encode_binary(data, @qr.ecc_medium(), 5)
  let baseline = match @qr.decode_from_qrcode(qr0) {
    Some(d) => d
    None => FixedArray::make(0, 0)
  }
  assert_true(bytes_equal(data, baseline))
  for iter = 0; iter < 1000; iter = iter + 1 {
    let qr = @qr.encode_binary(data, @qr.ecc_medium(), 5)
    match @qr.decode_from_qrcode(qr) {
      Some(decoded) => assert_true(bytes_equal(baseline, decoded))
      None => assert_true(false)
    }
  }
}

///|
test "stress perf: 100 small random data static encode/decode" {
  for i = 0; i < 100; i = i + 1 {
    let data = gen_random(10, i * 31 + 7)
    match @qr.encode_static(data, @qr.ecc_medium(), 1) {
      Some(result) =>
        match @qr.decode_static(result.packaged_bytes()) {
          Some(decoded) => assert_true(bytes_equal(data, decoded))
          None => assert_true(false)
        }
      None => assert_true(false)
    }
  }
}

///|
test "stress perf: compress -> encode -> decode -> decompress 100x" {
  // 用高度可压缩数据，静态管线内部自动压缩/解压
  let data = FixedArray::make(200, 0x42)
  for iter = 0; iter < 100; iter = iter + 1 {
    match @qr.encode_static(data, @qr.ecc_low(), 1) {
      Some(result) =>
        match @qr.decode_static(result.packaged_bytes()) {
          Some(decoded) => assert_true(bytes_equal(data, decoded))
          None => assert_true(false)
        }
      None => assert_true(false)
    }
  }
}

// ============================================================
// 2. 模糊测试（15个）
// ============================================================

///|
test "stress fuzz: 50 random length/content via static pipeline" {
  let mut seed = 12345
  for i = 0; i < 50; i = i + 1 {
    seed = (seed * 1103515245 + 12345) & 0x7fffffff
    let len = seed % 100 + 1
    seed = (seed * 1103515245 + 12345) & 0x7fffffff
    let data = gen_random(len, seed)
    match @qr.encode_static(data, @qr.ecc_medium(), 1) {
      Some(result) =>
        match @qr.decode_static(result.packaged_bytes()) {
          Some(decoded) => assert_true(bytes_equal(data, decoded))
          None => assert_true(false)
        }
      None => assert_true(false)
    }
  }
}

///|
test "stress fuzz: 30 random length/content via dynamic stream" {
  let mut seed = 54321
  for i = 0; i < 30; i = i + 1 {
    seed = (seed * 1103515245 + 12345) & 0x7fffffff
    let len = seed % 2000 + 1
    seed = (seed * 1103515245 + 12345) & 0x7fffffff
    let data = gen_random(len, seed)
    let frames = @qr.split_into_frames(data, 100)
    match @qr.reassemble_frames(frames) {
      Some(decoded) => assert_true(bytes_equal(data, decoded))
      None => assert_true(false)
    }
  }
}

///|
test "stress fuzz: 20 random length/content via color QR" {
  let mut seed = 98765
  for i = 0; i < 20; i = i + 1 {
    seed = (seed * 1103515245 + 12345) & 0x7fffffff
    let len = seed % 500 + 1
    seed = (seed * 1103515245 + 12345) & 0x7fffffff
    let data = gen_random(len, seed)
    let encoder = @qr.ColorQREncoder::new(10)
    let matrix = encoder.encode(data)
    match encoder.decode(matrix) {
      Some(decoded) => {
        // 彩色 QR decode 输出可能比原始数据长或短，用 min 比较前缀
        let n = if data.length() < decoded.length() {
          data.length()
        } else {
          decoded.length()
        }
        for j = 0; j < n; j = j + 1 {
          assert_true(data[j] == decoded[j])
        }
      }
      None => assert_true(false)
    }
  }
}

///|
test "stress fuzz: random ECC level x random data static" {
  let levels = [
    @qr.ecc_low(),
    @qr.ecc_medium(),
    @qr.ecc_quartile(),
    @qr.ecc_high(),
  ]
  let mut seed = 11111
  for i = 0; i < 20; i = i + 1 {
    seed = (seed * 1103515245 + 12345) & 0x7fffffff
    let level_idx = seed % 4
    seed = (seed * 1103515245 + 12345) & 0x7fffffff
    let data = gen_random(50, seed)
    match @qr.encode_static(data, levels[level_idx], 1) {
      Some(result) =>
        match @qr.decode_static(result.packaged_bytes()) {
          Some(decoded) => assert_true(bytes_equal(data, decoded))
          None => assert_true(false)
        }
      None => assert_true(false)
    }
  }
}

///|
test "stress fuzz: random frame_size x random data dynamic" {
  let mut seed = 22222
  for i = 0; i < 20; i = i + 1 {
    seed = (seed * 1103515245 + 12345) & 0x7fffffff
    let frame_size = seed % 200 + 1
    seed = (seed * 1103515245 + 12345) & 0x7fffffff
    let data = gen_random(500, seed)
    let frames = @qr.split_into_frames(data, frame_size)
    match @qr.reassemble_frames(frames) {
      Some(decoded) => assert_true(bytes_equal(data, decoded))
      None => assert_true(false)
    }
  }
}

///|
test "stress fuzz: all 0x00 various lengths static" {
  let lengths = [1, 10, 100, 1000, 10000]
  for i = 0; i < 5; i = i + 1 {
    let data = FixedArray::make(lengths[i], 0)
    match @qr.encode_static(data, @qr.ecc_low(), 1) {
      Some(result) =>
        match @qr.decode_static(result.packaged_bytes()) {
          Some(decoded) => assert_true(bytes_equal(data, decoded))
          None => assert_true(false)
        }
      None => assert_true(false)
    }
  }
}

///|
test "stress fuzz: all 0xFF various lengths static" {
  let lengths = [1, 10, 100, 1000, 10000]
  for i = 0; i < 5; i = i + 1 {
    let data = FixedArray::make(lengths[i], 0xff)
    match @qr.encode_static(data, @qr.ecc_low(), 1) {
      Some(result) =>
        match @qr.decode_static(result.packaged_bytes()) {
          Some(decoded) => assert_true(bytes_equal(data, decoded))
          None => assert_true(false)
        }
      None => assert_true(false)
    }
  }
}

///|
test "stress fuzz: single bit flip per position static" {
  // 8 字节数据，每个 bit 位置（0~63）单独置 1，静态管线无损
  for bit_pos = 0; bit_pos < 64; bit_pos = bit_pos + 1 {
    let data = FixedArray::make(8, 0)
    let byte_idx = bit_pos / 8
    let bit_idx = bit_pos % 8
    data[byte_idx] = 1 << (7 - bit_idx)
    match @qr.encode_static(data, @qr.ecc_medium(), 1) {
      Some(result) =>
        match @qr.decode_static(result.packaged_bytes()) {
          Some(decoded) => assert_true(bytes_equal(data, decoded))
          None => assert_true(false)
        }
      None => assert_true(false)
    }
  }
}

///|
test "stress fuzz: incrementing sequence various lengths" {
  let lengths = [10, 50, 100, 500, 1000]
  for i = 0; i < 5; i = i + 1 {
    let len = lengths[i]
    let data = FixedArray::make(len, 0)
    for j = 0; j < len; j = j + 1 {
      data[j] = j % 256
    }
    match @qr.encode_static(data, @qr.ecc_medium(), 1) {
      Some(result) =>
        match @qr.decode_static(result.packaged_bytes()) {
          Some(decoded) => assert_true(bytes_equal(data, decoded))
          None => assert_true(false)
        }
      None => assert_true(false)
    }
  }
}

///|
test "stress fuzz: decrementing sequence various lengths" {
  let lengths = [10, 50, 100, 500, 1000]
  for i = 0; i < 5; i = i + 1 {
    let len = lengths[i]
    let data = FixedArray::make(len, 0)
    for j = 0; j < len; j = j + 1 {
      data[j] = (255 - j) % 256
    }
    match @qr.encode_static(data, @qr.ecc_medium(), 1) {
      Some(result) =>
        match @qr.decode_static(result.packaged_bytes()) {
          Some(decoded) => assert_true(bytes_equal(data, decoded))
          None => assert_true(false)
        }
      None => assert_true(false)
    }
  }
}

///|
test "stress fuzz: prime lengths data lossless" {
  let primes = [2, 3, 5, 7, 11, 13, 17, 19, 23, 29]
  for i = 0; i < 10; i = i + 1 {
    let data = gen_random(primes[i], i * 37 + 1)
    match @qr.encode_static(data, @qr.ecc_medium(), 1) {
      Some(result) =>
        match @qr.decode_static(result.packaged_bytes()) {
          Some(decoded) => assert_true(bytes_equal(data, decoded))
          None => assert_true(false)
        }
      None => assert_true(false)
    }
  }
}

///|
test "stress fuzz: power of 2 lengths data lossless" {
  let powers = [1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024]
  for i = 0; i < 11; i = i + 1 {
    let data = gen_random(powers[i], i * 53 + 3)
    match @qr.encode_static(data, @qr.ecc_medium(), 1) {
      Some(result) =>
        match @qr.decode_static(result.packaged_bytes()) {
          Some(decoded) => assert_true(bytes_equal(data, decoded))
          None => assert_true(false)
        }
      None => assert_true(false)
    }
  }
}

///|
test "stress fuzz: fibonacci lengths data lossless" {
  let fibs = [1, 2, 3, 5, 8, 13, 21, 34, 55, 89]
  for i = 0; i < 10; i = i + 1 {
    let data = gen_random(fibs[i], i * 71 + 5)
    match @qr.encode_static(data, @qr.ecc_medium(), 1) {
      Some(result) =>
        match @qr.decode_static(result.packaged_bytes()) {
          Some(decoded) => assert_true(bytes_equal(data, decoded))
          None => assert_true(false)
        }
      None => assert_true(false)
    }
  }
}

///|
test "stress fuzz: random byte value repeated 100x" {
  let mut seed = 33333
  for i = 0; i < 20; i = i + 1 {
    seed = (seed * 1103515245 + 12345) & 0x7fffffff
    let byte_val = seed % 256
    let data = FixedArray::make(100, byte_val)
    match @qr.encode_static(data, @qr.ecc_low(), 1) {
      Some(result) =>
        match @qr.decode_static(result.packaged_bytes()) {
          Some(decoded) => assert_true(bytes_equal(data, decoded))
          None => assert_true(false)
        }
      None => assert_true(false)
    }
  }
}

///|
test "stress fuzz: mixed mode (half 0 half FF) various lengths" {
  let lengths = [10, 50, 100, 500, 1000]
  for i = 0; i < 5; i = i + 1 {
    let len = lengths[i]
    let data = FixedArray::make(len, 0)
    for j = 0; j < len / 2; j = j + 1 {
      data[j] = 0
    }
    for j = len / 2; j < len; j = j + 1 {
      data[j] = 0xff
    }
    match @qr.encode_static(data, @qr.ecc_medium(), 1) {
      Some(result) =>
        match @qr.decode_static(result.packaged_bytes()) {
          Some(decoded) => assert_true(bytes_equal(data, decoded))
          None => assert_true(false)
        }
      None => assert_true(false)
    }
  }
}

// ============================================================
// 3. V27~V39 中间版本补全（13个）
// ============================================================

///|
test "stress versions: V27 L near capacity lossless" {
  assert_true(test_version_near_capacity(27, @qr.ecc_low(), 27))
}

///|
test "stress versions: V27 M near capacity lossless" {
  assert_true(test_version_near_capacity(27, @qr.ecc_medium(), 28))
}

///|
test "stress versions: V27 Q near capacity lossless" {
  assert_true(test_version_near_capacity(27, @qr.ecc_quartile(), 29))
}

///|
test "stress versions: V27 H near capacity lossless" {
  assert_true(test_version_near_capacity(27, @qr.ecc_high(), 30))
}

///|
test "stress versions: V30 L near capacity lossless" {
  assert_true(test_version_near_capacity(30, @qr.ecc_low(), 31))
}

///|
test "stress versions: V30 M near capacity lossless" {
  assert_true(test_version_near_capacity(30, @qr.ecc_medium(), 32))
}

///|
test "stress versions: V30 Q near capacity lossless" {
  assert_true(test_version_near_capacity(30, @qr.ecc_quartile(), 33))
}

///|
test "stress versions: V30 H near capacity lossless" {
  assert_true(test_version_near_capacity(30, @qr.ecc_high(), 34))
}

///|
test "stress versions: V33 L near capacity lossless" {
  assert_true(test_version_near_capacity(33, @qr.ecc_low(), 35))
}

///|
test "stress versions: V33 M near capacity lossless" {
  assert_true(test_version_near_capacity(33, @qr.ecc_medium(), 36))
}

///|
test "stress versions: V33 Q near capacity lossless" {
  assert_true(test_version_near_capacity(33, @qr.ecc_quartile(), 37))
}

///|
test "stress versions: V33 H near capacity lossless" {
  assert_true(test_version_near_capacity(33, @qr.ecc_high(), 38))
}

///|
test "stress versions: V36~V39 L near capacity lossless" {
  for v = 36; v <= 39; v = v + 1 {
    assert_true(test_version_near_capacity(v, @qr.ecc_low(), v * 7 + 1))
  }
}

// ============================================================
// 4. 多帧乱序+丢帧组合场景（8个）
// ============================================================

///|
test "stress disorder: 10 frames all shuffled + lose 1 frame fountain recovery" {
  // K=10，生成 30 块（overhead=20），全乱序后丢 1 块保留 29 块 (2.9×K)
  let fountain = @qr.LTFountain::new(16, 10)
  let data = gen_random(160, 101)
  let encoded = fountain.encode_all(data, 30)
  // 全乱序（反序）
  let shuffled = reverse_encoded_blocks(encoded)
  // 丢 1 块，保留 29 块
  let subset = sample_encoded_blocks(shuffled, 29)
  match fountain.decode(subset) {
    Some(decoded) => assert_true(bytes_equal(data, decoded))
    None => assert_true(false)
  }
}

///|
test "stress disorder: 20 frames all shuffled + lose 20% fountain recovery" {
  // K=20，生成 60 块，全乱序后丢 20% (12 块) 保留 48 块 (2.4×K)
  let fountain = @qr.LTFountain::new(16, 20)
  let data = gen_random(320, 202)
  let encoded = fountain.encode_all(data, 60)
  let shuffled = reverse_encoded_blocks(encoded)
  // 丢 20% (12 块)，保留 48 块
  let subset = sample_encoded_blocks(shuffled, 48)
  match fountain.decode(subset) {
    Some(decoded) => assert_true(bytes_equal(data, decoded))
    None => assert_true(false)
  }
}

///|
test "stress disorder: 50 frames partial shuffled + lose 30% fountain recovery" {
  // K=50，生成 200 块，部分乱序后丢 30% (60 块) 保留 140 块 (2.8×K)
  let fountain = @qr.LTFountain::new(16, 50)
  let data = gen_random(800, 303)
  let encoded = fountain.encode_all(data, 200)
  // 部分乱序：前半正序后半倒序
  let shuffled = partial_shuffle_encoded_blocks(encoded)
  // 丢 30% (60 块)，保留 140 块
  let subset = sample_encoded_blocks(shuffled, 140)
  match fountain.decode(subset) {
    Some(decoded) => assert_true(bytes_equal(data, decoded))
    None => assert_true(false)
  }
}

///|
test "stress disorder: split then shuffle reassemble lossless" {
  // 动态码流分片后乱序重组（reassemble_frames 支持乱序）
  let data = gen_random(500, 404)
  let frames = @qr.split_into_frames(data, 50)
  // 乱序：反序
  let n = frames.length()
  let shuffled : Array[FixedArray[Int32]] = []
  for i = 0; i < n; i = i + 1 {
    shuffled.push(frames[n - 1 - i])
  }
  match @qr.reassemble_frames(shuffled) {
    Some(decoded) => assert_true(bytes_equal(data, decoded))
    None => assert_true(false)
  }
}

///|
test "stress disorder: fountain shuffled + duplicate frames recovery" {
  // 喷泉码天然支持重复块：乱序 + 重复块后 decode 恢复无损
  let fountain = @qr.LTFountain::new(16, 10)
  let data = gen_random(160, 505)
  let encoded = fountain.encode_all(data, 30)
  // 乱序 + 重复：取前 20 块乱序 + 重复前 5 块
  let shuffled : Array[(Int32, FixedArray[Int32])] = []
  for i = 0; i < 20; i = i + 1 {
    shuffled.push(encoded[19 - i])
  }
  // 重复前 5 块
  for i = 0; i < 5; i = i + 1 {
    shuffled.push(encoded[i])
  }
  match fountain.decode(shuffled) {
    Some(decoded) => assert_true(bytes_equal(data, decoded))
    None => assert_true(false)
  }
}

///|
test "stress disorder: fountain encode_all shuffled + lose frames decode recovery" {
  // K=10，生成 40 块，乱序后丢 25% (10 块) 保留 30 块 (3×K)
  let fountain = @qr.LTFountain::new(20, 10)
  let data = gen_random(200, 606)
  let encoded = fountain.encode_all(data, 40)
  let shuffled = reverse_encoded_blocks(encoded)
  // 丢 25% (10 块)，保留 30 块 (3×K)
  let subset = sample_encoded_blocks(shuffled, 30)
  match fountain.decode(subset) {
    Some(decoded) => assert_true(bytes_equal(data, decoded))
    None => assert_true(false)
  }
}

///|
test "stress disorder: dynamic stream full pipeline shuffled + loss recovery" {
  // 完整管线：数据 -> 喷泉码编码 -> 乱序 -> 丢帧 -> 喷泉码解码 -> 数据
  // K=20，生成 80 块，乱序后丢 30% (24 块) 保留 56 块 (2.8×K)
  let fountain = @qr.LTFountain::new(50, 20)
  let data = gen_random(1000, 707)
  let encoded = fountain.encode_all(data, 80)
  let shuffled = reverse_encoded_blocks(encoded)
  // 丢 30% (24 块)，保留 56 块 (2.8×K)
  let subset = sample_encoded_blocks(shuffled, 56)
  match fountain.decode(subset) {
    Some(decoded) => assert_true(bytes_equal(data, decoded))
    None => assert_true(false)
  }
}

///|
test "stress disorder: different block_sizes shuffled + loss recovery" {
  // 不同 block_size 的乱序+丢帧组合恢复
  let block_sizes = [8, 16, 32, 64]
  for bi = 0; bi < 4; bi = bi + 1 {
    let bs = block_sizes[bi]
    let num_blocks = 10
    let total_len = bs * num_blocks
    let data = gen_random(total_len, bi * 111 + 1)
    let fountain = @qr.LTFountain::new(bs, num_blocks)
    // K=10，生成 30 块，乱序后丢 20% (6 块) 保留 24 块 (2.4×K)
    let encoded = fountain.encode_all(data, 30)
    let shuffled = reverse_encoded_blocks(encoded)
    let subset = sample_encoded_blocks(shuffled, 24)
    match fountain.decode(subset) {
      Some(decoded) => assert_true(bytes_equal(data, decoded))
      None => assert_true(false)
    }
  }
}
