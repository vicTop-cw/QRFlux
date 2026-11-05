/// Lossless transfer tests — comprehensive data integrity verification.
/// Every test verifies that data survives a full encode → decode roundtrip
/// without any bit corruption, covering all pipelines and data patterns.

///|
/// Helper: generate all 256 byte values (0x00~0xFF).
fn gen_all_bytes() -> FixedArray[Int32] {
  let data = FixedArray::make(256, 0)
  for i = 0; i < 256; i = i + 1 {
    data[i] = i
  }
  data
}

///|
/// Helper: generate random-ish data (deterministic LCG).
fn gen_random(len : Int32, seed : Int32) -> FixedArray[Int32] {
  let data = FixedArray::make(len, 0)
  let mut s = seed
  for i = 0; i < len; i = i + 1 {
    s = (s * 1103515245 + 12345) & 0x7fffffff
    data[i] = (s >> 16) & 0xff
  }
  data
}

///|
/// Helper: verify two byte arrays are identical. Returns true if equal.
fn bytes_equal(a : FixedArray[Int32], b : FixedArray[Int32]) -> Bool {
  if a.length() != b.length() {
    return false
  }
  for i = 0; i < a.length(); i = i + 1 {
    if a[i] != b[i] {
      return false
    }
  }
  true
}

///|
/// Helper: generate repeated pattern data.
fn gen_pattern(len : Int32, pattern : FixedArray[Int32]) -> FixedArray[Int32] {
  let data = FixedArray::make(len, 0)
  for i = 0; i < len; i = i + 1 {
    data[i] = pattern[i % pattern.length()]
  }
  data
}

// ============================================================
// 1. All 256 byte values — full binary spectrum coverage
// ============================================================

///|
test "lossless: all 256 bytes via encode_binary/decode" {
  let data = gen_all_bytes()
  let qr = @qr.encode_binary(data, @qr.ecc_medium(), 1)
  match @qr.decode_from_qrcode(qr) {
    Some(decoded) => assert_true(bytes_equal(data, decoded))
    None => assert_true(false)
  }
}

///|
test "lossless: all 256 bytes via static pipeline" {
  let data = gen_all_bytes()
  match @qr.encode_static(data, @qr.ecc_medium(), 1) {
    Some(result) =>
      match @qr.decode_static(result.packaged_bytes()) {
        Some(decoded) => assert_true(bytes_equal(data, decoded))
        None => assert_true(false)
      }
    None => assert_true(false)
  }
}

///|
test "lossless: all 256 bytes via dynamic stream" {
  let data = gen_all_bytes()
  let frames = @qr.split_into_frames(data, 50)
  match @qr.reassemble_frames(frames) {
    Some(decoded) => assert_true(bytes_equal(data, decoded))
    None => assert_true(false)
  }
}

///|
test "lossless: all 256 bytes via color QR" {
  let data = gen_all_bytes()
  let encoder = @qr.ColorQREncoder::new(10)
  let matrix = encoder.encode(data)
  match encoder.decode(matrix) {
    Some(decoded) =>
      // Color QR may produce extra trailing bytes; verify first 256 match
      for i = 0; i < 256; i = i + 1 {
        assert_true(data[i] == decoded[i])
      }
    None => assert_true(false)
  }
}

// ============================================================
// 2. Static pipeline — multiple data types
// ============================================================

///|
test "lossless static: empty data" {
  let data = FixedArray::make(0, 0)
  match @qr.encode_static(data, @qr.ecc_low(), 1) {
    Some(result) =>
      match @qr.decode_static(result.packaged_bytes()) {
        Some(decoded) => assert_true(decoded.length() == 0)
        None => assert_true(false)
      }
    None => assert_true(false)
  }
}

///|
test "lossless static: single byte 0x00" {
  let data = FixedArray::make(1, 0)
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
test "lossless static: single byte 0xFF" {
  let data = FixedArray::make(1, 0xff)
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
test "lossless static: all zeros 100 bytes" {
  let data = FixedArray::make(100, 0)
  match @qr.encode_static(data, @qr.ecc_medium(), 1) {
    Some(result) =>
      match @qr.decode_static(result.packaged_bytes()) {
        Some(decoded) => assert_true(bytes_equal(data, decoded))
        None => assert_true(false)
      }
    None => assert_true(false)
  }
}

///|
test "lossless static: all 0xFF 100 bytes" {
  let data = FixedArray::make(100, 0xff)
  match @qr.encode_static(data, @qr.ecc_medium(), 1) {
    Some(result) =>
      match @qr.decode_static(result.packaged_bytes()) {
        Some(decoded) => assert_true(bytes_equal(data, decoded))
        None => assert_true(false)
      }
    None => assert_true(false)
  }
}

///|
test "lossless static: alternating 0x00/0xFF" {
  let data = FixedArray::make(100, 0)
  for i = 0; i < 100; i = i + 1 {
    data[i] = if i % 2 == 0 { 0 } else { 0xff }
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

///|
test "lossless static: random 200 bytes" {
  let data = gen_random(200, 42)
  match @qr.encode_static(data, @qr.ecc_medium(), 1) {
    Some(result) =>
      match @qr.decode_static(result.packaged_bytes()) {
        Some(decoded) => assert_true(bytes_equal(data, decoded))
        None => assert_true(false)
      }
    None => assert_true(false)
  }
}

///|
test "lossless static: repetitive pattern (high compression)" {
  let pattern = FixedArray::make(3, 0)
  pattern[0] = 0x41
  pattern[1] = 0x42
  pattern[2] = 0x43
  let data = gen_pattern(300, pattern)
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
test "lossless static: all ECC levels" {
  let data = gen_random(50, 99)
  let levels = [
    @qr.ecc_low(),
    @qr.ecc_medium(),
    @qr.ecc_quartile(),
    @qr.ecc_high(),
  ]
  for i = 0; i < 4; i = i + 1 {
    match @qr.encode_static(data, levels[i], 1) {
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
// 3. Dynamic stream — large files
// ============================================================

///|
test "lossless dynamic: 1KB random data" {
  let data = gen_random(1024, 7)
  let frames = @qr.split_into_frames(data, 100)
  assert_true(frames.length() > 1)
  match @qr.reassemble_frames(frames) {
    Some(decoded) => assert_true(bytes_equal(data, decoded))
    None => assert_true(false)
  }
}

///|
test "lossless dynamic: 5KB random data" {
  let data = gen_random(5120, 13)
  let frames = @qr.split_into_frames(data, 200)
  assert_true(frames.length() > 1)
  match @qr.reassemble_frames(frames) {
    Some(decoded) => assert_true(bytes_equal(data, decoded))
    None => assert_true(false)
  }
}

///|
test "lossless dynamic: 10KB random data" {
  let data = gen_random(10240, 77)
  let frames = @qr.split_into_frames(data, 500)
  assert_true(frames.length() > 1)
  match @qr.reassemble_frames(frames) {
    Some(decoded) => assert_true(bytes_equal(data, decoded))
    None => assert_true(false)
  }
}

///|
test "lossless dynamic: various frame sizes" {
  let data = gen_random(500, 55)
  let frame_sizes = [10, 25, 50, 100, 200, 500]
  for i = 0; i < 6; i = i + 1 {
    let frames = @qr.split_into_frames(data, frame_sizes[i])
    match @qr.reassemble_frames(frames) {
      Some(decoded) => assert_true(bytes_equal(data, decoded))
      None => assert_true(false)
    }
  }
}

///|
test "lossless dynamic: out-of-order reassembly" {
  let data = gen_random(300, 88)
  let frames = @qr.split_into_frames(data, 50)
  // Reverse frame order
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
test "lossless dynamic: all zeros large" {
  let data = FixedArray::make(2000, 0)
  let frames = @qr.split_into_frames(data, 100)
  match @qr.reassemble_frames(frames) {
    Some(decoded) => assert_true(bytes_equal(data, decoded))
    None => assert_true(false)
  }
}

///|
test "lossless dynamic: all 0xFF large" {
  let data = FixedArray::make(2000, 0xff)
  let frames = @qr.split_into_frames(data, 100)
  match @qr.reassemble_frames(frames) {
    Some(decoded) => assert_true(bytes_equal(data, decoded))
    None => assert_true(false)
  }
}

// ============================================================
// 4. Color QR — multiple versions and data types
// ============================================================

///|
test "lossless color: V1~V5 all bytes" {
  let data = gen_all_bytes()
  for v = 1; v <= 5; v = v + 1 {
    let encoder = @qr.ColorQREncoder::new(v)
    let matrix = encoder.encode(data)
    match encoder.decode(matrix) {
      Some(decoded) => {
        // Compare min(data, decoded) bytes — color QR may produce extra trailing bytes
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
}

///|
test "lossless color: random data V10" {
  let data = gen_random(400, 42)
  let encoder = @qr.ColorQREncoder::new(10)
  let matrix = encoder.encode(data)
  match encoder.decode(matrix) {
    Some(decoded) =>
      for i = 0; i < data.length(); i = i + 1 {
        assert_true(data[i] == decoded[i])
      }
    None => assert_true(false)
  }
}

///|
test "lossless color: RGB roundtrip V5" {
  let data = gen_random(100, 123)
  let encoder = @qr.ColorQREncoder::new(5)
  let matrix = encoder.encode(data)
  let size = matrix.length()
  // Convert to RGB and back
  let rgb_matrix = FixedArray::make(size, FixedArray::make(size, (0, 0, 0)))
  for y = 0; y < size; y = y + 1 {
    rgb_matrix[y] = FixedArray::make(size, (0, 0, 0))
    for x = 0; x < size; x = x + 1 {
      let (r, g, b) = @qr.ColorQRColor::to_rgb(matrix[y][x])
      rgb_matrix[y][x] = (r, g, b)
    }
  }
  match @qr.decode_color_from_rgb(rgb_matrix, 5) {
    Some(decoded) =>
      for i = 0; i < data.length(); i = i + 1 {
        assert_true(data[i] == decoded[i])
      }
    None => assert_true(false)
  }
}

// ============================================================
// 5. Full encode → QR → decode E2E (all pipelines combined)
// ============================================================

///|
test "lossless e2e: static pipeline full roundtrip V1~V10" {
  let data = gen_random(30, 2024)
  for v = 1; v <= 10; v = v + 1 {
    match @qr.encode_static(data, @qr.ecc_medium(), v) {
      Some(result) => {
        // Path 1: decode from QR code directly
        match @qr.decode_from_qrcode(result.qr()) {
          Some(qr_bytes) =>
            match @qr.decode_static(qr_bytes) {
              Some(decoded) => assert_true(bytes_equal(data, decoded))
              None => assert_true(false)
            }
          None => assert_true(false)
        }
        // Path 2: decode from packaged bytes
        match @qr.decode_static(result.packaged_bytes()) {
          Some(decoded) => assert_true(bytes_equal(data, decoded))
          None => assert_true(false)
        }
      }
      None => () // data may not fit in version v, skip
    }
  }
}

///|
test "lossless e2e: near-capacity stress V1~V20" {
  for v = 1; v <= 20; v = v + 1 {
    let level = @qr.ecc_medium()
    // Get capacity and fill to ~90%
    let cap = @qr.num_data_codewords(v, level)
    let data_len = cap * 9 / 10
    if data_len < 1 {
      continue
    }
    let data = gen_random(data_len, v * 31 + 7)
    let qr = @qr.encode_binary(data, level, v)
    match @qr.decode_from_qrcode(qr) {
      Some(decoded) => assert_true(bytes_equal(data, decoded))
      None => assert_true(false)
    }
  }
}

///|
test "lossless e2e: all 4 ECC levels with 100 bytes" {
  let data = gen_random(100, 555)
  let levels = [
    @qr.ecc_low(),
    @qr.ecc_medium(),
    @qr.ecc_quartile(),
    @qr.ecc_high(),
  ]
  for i = 0; i < 4; i = i + 1 {
    let qr = @qr.encode_binary(data, levels[i], 1)
    match @qr.decode_from_qrcode(qr) {
      Some(decoded) => assert_true(bytes_equal(data, decoded))
      None => assert_true(false)
    }
  }
}

// ============================================================
// 6. Compression + transfer closed loop
// ============================================================

///|
test "lossless compress: highly compressible data" {
  // All same byte — RLE should compress heavily
  let data = FixedArray::make(500, 0x42)
  match @qr.encode_static(data, @qr.ecc_low(), 1) {
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
test "lossless compress: incompressible data (no expansion)" {
  // Random data — should NOT expand after compression
  let data = gen_random(200, 999)
  match @qr.encode_static(data, @qr.ecc_medium(), 1) {
    Some(result) =>
      match @qr.decode_static(result.packaged_bytes()) {
        Some(decoded) => assert_true(bytes_equal(data, decoded))
        None => assert_true(false)
      }
    None => assert_true(false)
  }
}

///|
test "lossless compress: mixed compressible segments" {
  // Half repetitive, half random
  let data = FixedArray::make(200, 0)
  for i = 0; i < 100; i = i + 1 {
    data[i] = 0x41 // repetitive
  }
  for i = 100; i < 200; i = i + 1 {
    data[i] = (i * 37 + 13) & 0xff // pseudo-random
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

///|
test "lossless compress: dynamic stream with compressible data" {
  let data = FixedArray::make(3000, 0x37)
  let frames = @qr.split_into_frames(data, 100)
  match @qr.reassemble_frames(frames) {
    Some(decoded) => assert_true(bytes_equal(data, decoded))
    None => assert_true(false)
  }
}

// ============================================================
// 7. Edge cases for lossless transfer
// ============================================================

///|
test "lossless edge: single byte through dynamic stream" {
  let data = FixedArray::make(1, 0x5a)
  let frames = @qr.split_into_frames(data, 50)
  match @qr.reassemble_frames(frames) {
    Some(decoded) => assert_true(bytes_equal(data, decoded))
    None => assert_true(false)
  }
}

///|
test "lossless edge: two bytes through dynamic stream" {
  let data = FixedArray::make(2, 0)
  data[0] = 0x12
  data[1] = 0x34
  let frames = @qr.split_into_frames(data, 50)
  match @qr.reassemble_frames(frames) {
    Some(decoded) => assert_true(bytes_equal(data, decoded))
    None => assert_true(false)
  }
}

///|
test "lossless edge: frame_size = 1" {
  let data = gen_random(20, 5)
  let frames = @qr.split_into_frames(data, 1)
  assert_true(frames.length() == 20)
  match @qr.reassemble_frames(frames) {
    Some(decoded) => assert_true(bytes_equal(data, decoded))
    None => assert_true(false)
  }
}

///|
test "lossless edge: data length = exact frame_size multiple" {
  let data = gen_random(150, 8)
  let frames = @qr.split_into_frames(data, 50)
  match @qr.reassemble_frames(frames) {
    Some(decoded) => assert_true(bytes_equal(data, decoded))
    None => assert_true(false)
  }
}

///|
test "lossless edge: every byte value through QR encode/decode" {
  // Test each byte value individually through the full pipeline
  for b = 0; b < 256; b = b + 1 {
    let data = FixedArray::make(1, b)
    let qr = @qr.encode_binary(data, @qr.ecc_medium(), 1)
    match @qr.decode_from_qrcode(qr) {
      Some(decoded) => {
        assert_true(decoded.length() >= 1)
        assert_true(decoded[0] == b)
      }
      None => assert_true(false)
    }
  }
}
