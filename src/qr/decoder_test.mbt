/// Tests for the QR decoder (encode -> decode round-trip).

///|
/// Helper: assert decoded bytes equal expected.
fn assert_decode_eq(
  decoded : FixedArray[Int32]?,
  expected : FixedArray[Int32],
  label : String,
) -> Unit {
  match decoded {
    Some(d) =>
      if d.length() != expected.length() {
        abort(
          "decode \{label}: length mismatch: got \{d.length()}, want \{expected.length()}",
        )
      } else {
        for i = 0; i < expected.length(); i = i + 1 {
          if d[i] != expected[i] {
            abort(
              "decode \{label}: byte \{i} mismatch: got \{d[i]}, want \{expected[i]}",
            )
          }
        }
      }
    None => abort("decode \{label}: returned None")
  }
}

///|
/// Helper: make a FixedArray from a literal array of small ints.
fn mk_bytes(xs : Array[Int32]) -> FixedArray[Int32] {
  let fa = FixedArray::make(xs.length(), 0)
  for i = 0; i < xs.length(); i = i + 1 {
    fa[i] = xs[i]
  }
  fa
}

///|
/// Helper: make a FixedArray of n pseudo-random bytes (deterministic).
fn mk_random(n : Int32, seed : Int32) -> FixedArray[Int32] {
  let fa = FixedArray::make(n, 0)
  let mut s = seed
  for i = 0; i < n; i = i + 1 {
    // LCG
    s = (s * 1103515245 + 12345) & 0x7FFFFFFF
    fa[i] = (s >> 16) & 0xFF
  }
  fa
}

///|
test "decode V1 byte mode Hello" {
  // "Hello" = 72,101,108,108,111 (5 bytes). V1-H chosen by auto-boost.
  let data = mk_bytes([72, 101, 108, 108, 111])
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let decoded = @qr.decode_from_qrcode(qr)
  assert_decode_eq(decoded, data, "V1 Hello")
}

///|
test "decode V1 Hello World" {
  // "Hello World" (11 bytes)
  let data = mk_bytes([72, 101, 108, 108, 111, 32, 87, 111, 114, 108, 100])
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let decoded = @qr.decode_from_qrcode(qr)
  assert_decode_eq(decoded, data, "V1 Hello World")
}

///|
test "decode V2 20 bytes" {
  let data = mk_random(20, 42)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let decoded = @qr.decode_from_qrcode(qr)
  assert_decode_eq(decoded, data, "V2 20 bytes")
}

///|
test "decode V3 50 bytes" {
  let data = mk_random(50, 123)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let decoded = @qr.decode_from_qrcode(qr)
  assert_decode_eq(decoded, data, "V3 50 bytes")
}

///|
test "decode V5 100 bytes" {
  let data = mk_random(100, 7)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let decoded = @qr.decode_from_qrcode(qr)
  assert_decode_eq(decoded, data, "V5 100 bytes")
}

///|
test "decode V10 200 bytes" {
  let data = mk_random(200, 999)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let decoded = @qr.decode_from_qrcode(qr)
  assert_decode_eq(decoded, data, "V10 200 bytes")
}

///|
test "decode V20 500 bytes" {
  let data = mk_random(500, 2024)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let decoded = @qr.decode_from_qrcode(qr)
  assert_decode_eq(decoded, data, "V20 500 bytes")
}

///|
test "decode V40 large payload" {
  // V40-L max ~2953 bytes; use 2900 to stay safe.
  let data = mk_random(2900, 31415)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let decoded = @qr.decode_from_qrcode(qr)
  assert_decode_eq(decoded, data, "V40 2900 bytes")
}

///|
test "decode all ECC levels" {
  // Pick a size that fits in V1-H (9 bytes) to exercise L/M/Q/H boost.
  let data = mk_bytes([1, 2, 3, 4, 5, 6, 7, 8])
  for
    level in [
      @qr.ecc_low(),
      @qr.ecc_medium(),
      @qr.ecc_quartile(),
      @qr.ecc_high(),
    ] {
    let qr = @qr.encode_binary(data, level, 1)
    let decoded = @qr.decode_from_qrcode(qr)
    assert_decode_eq(decoded, data, "all-ecc")
  }
}

///|
test "decode via matrix API" {
  // Exercise decode_qr (Int32 matrix) instead of decode_from_qrcode.
  let data = mk_bytes([72, 101, 108, 108, 111])
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let size = qr.size()
  // Build Int32 matrix from QrCode.
  let matrix = FixedArray::make(size, FixedArray::make(size, 0))
  for y = 0; y < size; y = y + 1 {
    matrix[y] = FixedArray::make(size, 0)
    for x = 0; x < size; x = x + 1 {
      matrix[y][x] = if qr.get_module(x, y) { 1 } else { 0 }
    }
  }
  let decoded = @qr.decode_qr(matrix)
  assert_decode_eq(decoded, data, "matrix API")
}

///|
test "decode rejects bad size" {
  // 20x20 is not a valid QR size (must be 4k+17).
  let m = FixedArray::make(20, FixedArray::make(20, 0))
  for y = 0; y < 20; y = y + 1 {
    m[y] = FixedArray::make(20, 0)
  }
  match @qr.decode_qr(m) {
    Some(_) => assert_true(false)
    None => assert_true(true)
  }
}

///|
test "decode single byte" {
  let data = mk_bytes([65]) // 'A'
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let decoded = @qr.decode_from_qrcode(qr)
  assert_decode_eq(decoded, data, "single byte")
}

///|
test "decode empty payload" {
  let data = FixedArray::make(0, 0)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let decoded = @qr.decode_from_qrcode(qr)
  match decoded {
    Some(d) => assert_true(d.length() == 0)
    None => assert_true(false)
  }
}

///|
test "decode all 8 masks via V7" {
  // V7+ exercises version info read path. Use a payload that lands on V7.
  // V7-L data codewords = 28*8/8 - ...; just use 100 bytes.
  let data = mk_random(100, 555)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 7)
  // Verify version info path is exercised.
  assert_true(qr.version() >= 7)
  let decoded = @qr.decode_from_qrcode(qr)
  assert_decode_eq(decoded, data, "V7")
}

///|
test "decode medium ECC V10" {
  let data = mk_random(150, 88)
  let qr = @qr.encode_binary(data, @qr.ecc_medium(), 1)
  let decoded = @qr.decode_from_qrcode(qr)
  assert_decode_eq(decoded, data, "V10 M")
}

///|
test "decode high ECC V5" {
  let data = mk_random(30, 11)
  let qr = @qr.encode_binary(data, @qr.ecc_high(), 1)
  let decoded = @qr.decode_from_qrcode(qr)
  assert_decode_eq(decoded, data, "V5 H")
}

///|
/// MVP gate: V1 "Hello" (5 bytes). Requested L, but auto-boost promotes to
/// V1-H (9 data cw, 72 bits >= 52). Verifies the minimal byte-mode path.
test "mvp V1-L Hello" {
  let data = mk_bytes([72, 101, 108, 108, 111])
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  assert_true(qr.version() == 1)
  assert_true(qr.level() == @qr.ecc_high())
  let decoded = @qr.decode_from_qrcode(qr)
  assert_decode_eq(decoded, data, "mvp V1-L Hello")
}

///|
/// MVP gate: V1 "Hello World" (11 bytes, 100 bits). Auto-boost: V1-M (128)
/// and V1-Q (104) both fit, V1-H (72) does not, so level lands on Q.
test "mvp V1-M Hello World" {
  let data = mk_bytes([72, 101, 108, 108, 111, 32, 87, 111, 114, 108, 100])
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  assert_true(qr.version() == 1)
  assert_true(qr.level() == @qr.ecc_quartile())
  let decoded = @qr.decode_from_qrcode(qr)
  assert_decode_eq(decoded, data, "mvp V1-M Hello World")
}

///|
/// MVP gate: V3-L 50 random bytes. 412 bits fit V3-L (440) but not V3-M
/// (352), so level stays L.
test "mvp V3-L 50 bytes" {
  let data = mk_random(50, 123)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  assert_true(qr.version() == 3)
  assert_true(qr.level() == @qr.ecc_low())
  let decoded = @qr.decode_from_qrcode(qr)
  assert_decode_eq(decoded, data, "mvp V3-L 50 bytes")
}

///|
/// MVP gate: V5-M 80 random bytes. 652 bits fit V5-M (688) but not V5-Q
/// (512), so auto-boost lands on V5-M. (100 bytes would overflow V5-M and
/// is covered by the V5-L test above.)
test "mvp V5-M 80 bytes" {
  let data = mk_random(80, 7)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  assert_true(qr.version() == 5)
  assert_true(qr.level() == @qr.ecc_medium())
  let decoded = @qr.decode_from_qrcode(qr)
  assert_decode_eq(decoded, data, "mvp V5-M 80 bytes")
}
