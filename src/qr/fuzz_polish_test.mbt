/// Fuzz polish tests — deterministic LCG-driven fuzzing of encode→decode
/// roundtrip across lengths, ECC levels, and pipelines (binary / static /
/// dynamic). Self-contained: defines its own LCG generator and equality
/// helper so this file does not depend on helpers in other test files.
///
/// LCG recurrence: seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
/// Lengths covered: 1, 10, 50, 100, 500, 1000 bytes.
/// ECC levels covered: L, M, Q, H.
/// Pipelines covered: encode_binary/decode_from_qrcode, encode_static/
/// decode_static (internal compression), split_into_frames/reassemble_frames.

// ============================================================
// 辅助函数：自包含 LCG 伪随机生成器与比较
// ============================================================

///|
/// Deterministic LCG byte generator. Same recurrence as the project's other
/// fuzz suites but defined locally for file independence. Each byte is taken
/// from bits 16~23 of the state (high-quality bits of LCG).
fn fuzz_gen(len : Int32, seed : Int32) -> FixedArray[Int32] {
  let data = FixedArray::make(len, 0)
  let mut s = seed
  for i = 0; i < len; i = i + 1 {
    s = (s * 1103515245 + 12345) & 0x7fffffff
    data[i] = (s >> 16) & 0xff
  }
  data
}

///|
/// Byte array equality. Returns true iff same length and all bytes match.
fn fuzz_eq(a : FixedArray[Int32], b : FixedArray[Int32]) -> Bool {
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
/// One-shot encode_binary → decode_from_qrcode roundtrip check. Returns true
/// iff the decoded bytes exactly match the original generated data.
fn fuzz_roundtrip_binary(
  len : Int32,
  seed : Int32,
  level : @qr.EccLevel,
) -> Bool {
  let data = fuzz_gen(len, seed)
  let qr = @qr.encode_binary(data, level, 1)
  match @qr.decode_from_qrcode(qr) {
    Some(decoded) => fuzz_eq(data, decoded)
    None => false
  }
}

// ============================================================
// 1. encode_binary / decode_from_qrcode 往返模糊测试（12 个）
//    覆盖 6 种长度 × 4 种 ECC，每个块独立 seed。
// ============================================================

///|
test "fuzz polish binary: len=1 seed=101 ECC=L" {
  assert_true(fuzz_roundtrip_binary(1, 101, @qr.ecc_low()))
}

///|
test "fuzz polish binary: len=10 seed=202 ECC=M" {
  assert_true(fuzz_roundtrip_binary(10, 202, @qr.ecc_medium()))
}

///|
test "fuzz polish binary: len=50 seed=303 ECC=Q" {
  assert_true(fuzz_roundtrip_binary(50, 303, @qr.ecc_quartile()))
}

///|
test "fuzz polish binary: len=100 seed=404 ECC=H" {
  assert_true(fuzz_roundtrip_binary(100, 404, @qr.ecc_high()))
}

///|
test "fuzz polish binary: len=500 seed=505 ECC=L" {
  assert_true(fuzz_roundtrip_binary(500, 505, @qr.ecc_low()))
}

///|
test "fuzz polish binary: len=1000 seed=606 ECC=M" {
  assert_true(fuzz_roundtrip_binary(1000, 606, @qr.ecc_medium()))
}

///|
test "fuzz polish binary: len=1 seed=707 ECC=H" {
  assert_true(fuzz_roundtrip_binary(1, 707, @qr.ecc_high()))
}

///|
test "fuzz polish binary: len=10 seed=808 ECC=L" {
  assert_true(fuzz_roundtrip_binary(10, 808, @qr.ecc_low()))
}

///|
test "fuzz polish binary: len=50 seed=909 ECC=H" {
  assert_true(fuzz_roundtrip_binary(50, 909, @qr.ecc_high()))
}

///|
test "fuzz polish binary: len=100 seed=111 ECC=Q" {
  assert_true(fuzz_roundtrip_binary(100, 111, @qr.ecc_quartile()))
}

///|
test "fuzz polish binary: len=500 seed=222 ECC=H" {
  assert_true(fuzz_roundtrip_binary(500, 222, @qr.ecc_high()))
}

///|
test "fuzz polish binary: len=1000 seed=333 ECC=L" {
  assert_true(fuzz_roundtrip_binary(1000, 333, @qr.ecc_low()))
}

// ============================================================
// 2. 静态管线（含内部压缩）往返模糊测试（4 个）
//    覆盖 4 种 ECC，验证压缩 → 编码 → 解码 → 解压无损。
// ============================================================

///|
test "fuzz polish static: len=100 seed=444 ECC=M compress on" {
  let data = fuzz_gen(100, 444)
  match @qr.encode_static(data, @qr.ecc_medium(), 1) {
    Some(result) =>
      match @qr.decode_static(result.packaged_bytes()) {
        Some(decoded) => assert_true(fuzz_eq(data, decoded))
        None => assert_true(false)
      }
    None => assert_true(false)
  }
}

///|
test "fuzz polish static: len=500 seed=555 ECC=L compress on" {
  let data = fuzz_gen(500, 555)
  match @qr.encode_static(data, @qr.ecc_low(), 1) {
    Some(result) =>
      match @qr.decode_static(result.packaged_bytes()) {
        Some(decoded) => assert_true(fuzz_eq(data, decoded))
        None => assert_true(false)
      }
    None => assert_true(false)
  }
}

///|
test "fuzz polish static: len=1000 seed=666 ECC=H compress on" {
  let data = fuzz_gen(1000, 666)
  match @qr.encode_static(data, @qr.ecc_high(), 1) {
    Some(result) =>
      match @qr.decode_static(result.packaged_bytes()) {
        Some(decoded) => assert_true(fuzz_eq(data, decoded))
        None => assert_true(false)
      }
    None => assert_true(false)
  }
}

///|
test "fuzz polish static: len=50 seed=777 ECC=Q compress on" {
  let data = fuzz_gen(50, 777)
  match @qr.encode_static(data, @qr.ecc_quartile(), 1) {
    Some(result) =>
      match @qr.decode_static(result.packaged_bytes()) {
        Some(decoded) => assert_true(fuzz_eq(data, decoded))
        None => assert_true(false)
      }
    None => assert_true(false)
  }
}

// ============================================================
// 3. 动态码流分片/重组往返模糊测试（2 个）
//    覆盖较大数据量，验证 split → reassemble 无损。
// ============================================================

///|
test "fuzz polish dynamic: len=500 seed=888 frame=100" {
  let data = fuzz_gen(500, 888)
  let frames = @qr.split_into_frames(data, 100)
  assert_true(frames.length() >= 1)
  match @qr.reassemble_frames(frames) {
    Some(decoded) => assert_true(fuzz_eq(data, decoded))
    None => assert_true(false)
  }
}

///|
test "fuzz polish dynamic: len=1000 seed=999 frame=200" {
  let data = fuzz_gen(1000, 999)
  let frames = @qr.split_into_frames(data, 200)
  assert_true(frames.length() >= 1)
  match @qr.reassemble_frames(frames) {
    Some(decoded) => assert_true(fuzz_eq(data, decoded))
    None => assert_true(false)
  }
}

// ============================================================
// 4. 大数据单帧 binary 往返（3 个）—— 缺口1：>1000 字节接近 V40 上限
//    V40 L=2953B, V40 H=1273B。验证大 payload 编解码无损。
// ============================================================

///|
test "fuzz polish binary: len=2000 seed=1001 ECC=L large" {
  assert_true(fuzz_roundtrip_binary(2000, 1001, @qr.ecc_low()))
}

///|
test "fuzz polish binary: len=1200 seed=1002 ECC=H near V40 cap" {
  assert_true(fuzz_roundtrip_binary(1200, 1002, @qr.ecc_high()))
}

///|
test "fuzz polish binary: len=2500 seed=1003 ECC=L near V40 cap" {
  assert_true(fuzz_roundtrip_binary(2500, 1003, @qr.ecc_low()))
}

// ============================================================
// 5. minversion 强制版本提升（3 个）—— 缺口2：minversion>1 路径
//    小数据 + 高 minversion，验证版本被强制提升且往返无损。
// ============================================================

///|
test "fuzz polish minver: minversion=10 len=5 seed=1004 ECC=L forced" {
  let data = fuzz_gen(5, 1004)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 10)
  assert_true(qr.version() >= 10)
  match @qr.decode_from_qrcode(qr) {
    Some(decoded) => assert_true(fuzz_eq(data, decoded))
    None => assert_true(false)
  }
}

///|
test "fuzz polish minver: minversion=20 len=5 seed=1005 ECC=M forced" {
  let data = fuzz_gen(5, 1005)
  let qr = @qr.encode_binary(data, @qr.ecc_medium(), 20)
  assert_true(qr.version() >= 20)
  match @qr.decode_from_qrcode(qr) {
    Some(decoded) => assert_true(fuzz_eq(data, decoded))
    None => assert_true(false)
  }
}

///|
test "fuzz polish minver: minversion=15 len=100 seed=1006 ECC=Q forced" {
  let data = fuzz_gen(100, 1006)
  let qr = @qr.encode_binary(data, @qr.ecc_quartile(), 15)
  assert_true(qr.version() >= 15)
  match @qr.decode_from_qrcode(qr) {
    Some(decoded) => assert_true(fuzz_eq(data, decoded))
    None => assert_true(false)
  }
}

// ============================================================
// 6. 极端 frame_size 动态码流（2 个）—— 缺口3：极端 frame_size
//    frame=1（每帧 1 字节，帧数最多）与 frame=500（大帧，帧数最少）。
// ============================================================

///|
test "fuzz polish dynamic: len=50 seed=1007 frame=1 extreme small" {
  let data = fuzz_gen(50, 1007)
  let frames = @qr.split_into_frames(data, 1)
  assert_true(frames.length() >= 1)
  match @qr.reassemble_frames(frames) {
    Some(decoded) => assert_true(fuzz_eq(data, decoded))
    None => assert_true(false)
  }
}

///|
test "fuzz polish dynamic: len=1000 seed=1008 frame=500 large" {
  let data = fuzz_gen(1000, 1008)
  let frames = @qr.split_into_frames(data, 500)
  assert_true(frames.length() >= 1)
  match @qr.reassemble_frames(frames) {
    Some(decoded) => assert_true(fuzz_eq(data, decoded))
    None => assert_true(false)
  }
}

// ============================================================
// 7. 压缩/边界/确定性/单调性（4 个）—— 缺口4
// ============================================================

///|
test "fuzz polish static: all-0x42 x1000 ECC=L highly compressible" {
  // 全相同字节，高度可压缩；静态管线内部压缩后 payload 极小。
  let data = FixedArray::make(1000, 0x42)
  match @qr.encode_static(data, @qr.ecc_low(), 1) {
    Some(result) =>
      match @qr.decode_static(result.packaged_bytes()) {
        Some(decoded) => assert_true(fuzz_eq(data, decoded))
        None => assert_true(false)
      }
    None => assert_true(false)
  }
}

///|
test "fuzz polish boundary: V1-L exact cap and overflow" {
  // V1-L data codewords = 19；byte mode 开销 4(mode)+8(count)=12 bits；
  // 最大字节数 = (19*8 - 12)/8 = 17。17 字节正好 V1-L，18 字节溢出到 V2。
  let cap_cw = @qr.num_data_codewords(1, @qr.ecc_low())
  let max_bytes = (cap_cw * 8 - 12) / 8
  assert_true(max_bytes == 17)
  let d_cap = fuzz_gen(max_bytes, 1010)
  let qr_cap = @qr.encode_binary(d_cap, @qr.ecc_low(), 1)
  assert_true(qr_cap.version() == 1)
  match @qr.decode_from_qrcode(qr_cap) {
    Some(decoded) => assert_true(fuzz_eq(d_cap, decoded))
    None => assert_true(false)
  }
  let d_over = fuzz_gen(max_bytes + 1, 1011)
  let qr_over = @qr.encode_binary(d_over, @qr.ecc_low(), 1)
  assert_true(qr_over.version() >= 2)
  match @qr.decode_from_qrcode(qr_over) {
    Some(decoded) => assert_true(fuzz_eq(d_over, decoded))
    None => assert_true(false)
  }
}

///|
/// Helper: compare two QrCode modules pixel-by-pixel for determinism check.
fn fuzz_qr_eq(a : @qr.QrCode, b : @qr.QrCode) -> Bool {
  if a.version() != b.version() {
    return false
  }
  if a.size() != b.size() {
    return false
  }
  if a.mask() != b.mask() {
    return false
  }
  for y = 0; y < a.size(); y = y + 1 {
    for x = 0; x < a.size(); x = x + 1 {
      if a.get_module(x, y) != b.get_module(x, y) {
        return false
      }
    }
  }
  true
}

///|
test "fuzz polish deterministic: same data 5x identical QR modules" {
  // 同输入同参数，encode_binary 必须完全确定：5 次编码的版本/掩码/模块全同。
  let data = fuzz_gen(80, 1012)
  let qr1 = @qr.encode_binary(data, @qr.ecc_medium(), 1)
  let qr2 = @qr.encode_binary(data, @qr.ecc_medium(), 1)
  let qr3 = @qr.encode_binary(data, @qr.ecc_medium(), 1)
  let qr4 = @qr.encode_binary(data, @qr.ecc_medium(), 1)
  let qr5 = @qr.encode_binary(data, @qr.ecc_medium(), 1)
  assert_true(fuzz_qr_eq(qr1, qr2))
  assert_true(fuzz_qr_eq(qr1, qr3))
  assert_true(fuzz_qr_eq(qr1, qr4))
  assert_true(fuzz_qr_eq(qr1, qr5))
}

///|
test "fuzz polish monotone: 4 ECC levels version monotonicity" {
  // 同数据下 ECC 越高容量越小，所需版本号单调不降：vH >= vQ >= vM >= vL。
  let data = fuzz_gen(100, 1013)
  let vL = @qr.encode_binary(data, @qr.ecc_low(), 1).version()
  let vM = @qr.encode_binary(data, @qr.ecc_medium(), 1).version()
  let vQ = @qr.encode_binary(data, @qr.ecc_quartile(), 1).version()
  let vH = @qr.encode_binary(data, @qr.ecc_high(), 1).version()
  assert_true(vH >= vQ)
  assert_true(vQ >= vM)
  assert_true(vM >= vL)
}
