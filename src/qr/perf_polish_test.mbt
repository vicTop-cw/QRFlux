// Performance polish tests for QRFlux.
// Benchmarks encoding/decoding/compression/streaming throughput.
// Asserts operations complete successfully (no timeout, no abort);
// does not measure wall-clock time, only correctness + termination.

///|
/// Helper: make n copies of a byte value.
fn pp_make_data(n : Int32, val : Int32) -> FixedArray[Int32] {
  FixedArray::make(n, val)
}

///|
/// Helper: deterministic pseudo-random bytes (LCG).
fn pp_random(n : Int32, seed : Int32) -> FixedArray[Int32] {
  let fa = FixedArray::make(n, 0)
  let mut s = seed
  for i = 0; i < n; i = i + 1 {
    s = (s * 1103515245 + 12345) & 0x7FFFFFFF
    fa[i] = (s >> 16) & 0xFF
  }
  fa
}

///|
/// Helper: convert QrCode to Int32 matrix (0/1) for decode_qr.
fn pp_to_matrix(qr : @qr.QrCode) -> FixedArray[FixedArray[Int32]] {
  let size = qr.size()
  let matrix = FixedArray::make(size, FixedArray::make(size, 0))
  for y = 0; y < size; y = y + 1 {
    let row = FixedArray::make(size, 0)
    for x = 0; x < size; x = x + 1 {
      row[x] = if qr.get_module(x, y) { 1 } else { 0 }
    }
    matrix[y] = row
  }
  matrix
}

///|
/// Helper: check two FixedArray[Int32] equal.
fn pp_eq(a : FixedArray[Int32], b : FixedArray[Int32]) -> Bool {
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
/// Helper: the four ECC levels.
fn pp_all_levels() -> Array[@qr.EccLevel] {
  [@qr.ecc_low(), @qr.ecc_medium(), @qr.ecc_quartile(), @qr.ecc_high()]
}

///|
/// V1 × L/M/Q/H: smallest QR, all ECC levels. 5 bytes fits V1-H (7).
test "perf polish: encode V1 all ecc levels" {
  let data = pp_make_data(5, 0x42)
  for level in pp_all_levels() {
    let qr = @qr.encode_binary(data, level, 1)
    assert_true(qr.version() == 1)
    assert_true(qr.size() == 21)
  }
}

///|
/// V10 × L/M/Q/H: mid-size QR. 100 bytes fits V10-H (120).
test "perf polish: encode V10 all ecc levels" {
  let data = pp_make_data(100, 0x37)
  for level in pp_all_levels() {
    let qr = @qr.encode_binary(data, level, 10)
    assert_true(qr.version() == 10)
    assert_true(qr.size() == 57)
  }
}

///|
/// V20 × L/M/Q/H: large QR. 350 bytes fits V20-H (385 codewords).
test "perf polish: encode V20 all ecc levels" {
  let data = pp_make_data(350, 0x5A)
  for level in pp_all_levels() {
    let qr = @qr.encode_binary(data, level, 20)
    assert_true(qr.version() == 20)
    assert_true(qr.size() == 97)
  }
}

///|
/// V40 × L/M/Q/H: max QR. 1000 bytes fits V40-H (1273).
test "perf polish: encode V40 all ecc levels" {
  let data = pp_make_data(1000, 0x6B)
  for level in pp_all_levels() {
    let qr = @qr.encode_binary(data, level, 40)
    assert_true(qr.version() == 40)
    assert_true(qr.size() == 177)
  }
}

///|
/// Decode roundtrip: encode then decode_from_qrcode, verify payload matches.
/// Covers V1/V10/V20/V40 with pseudo-random data (worst-case for compression).
test "perf polish: decode roundtrip across versions" {
  let vers = [1, 10, 20, 40]
  let sizes = [5, 100, 350, 1000]
  for k = 0; k < 4; k = k + 1 {
    let ver = vers[k]
    let n = sizes[k]
    let data = pp_random(n, ver * 31 + 7)
    let qr = @qr.encode_binary(data, @qr.ecc_medium(), ver)
    assert_true(qr.version() == ver)
    match @qr.decode_from_qrcode(qr) {
      Some(dec) => assert_true(pp_eq(data, dec))
      None => abort("decode_from_qrcode failed for V\{ver}")
    }
  }
}

///|
/// Decode via decode_qr (Int32 matrix path) roundtrip for V5/V15.
test "perf polish: decode qr matrix roundtrip" {
  let vers = [5, 15]
  let sizes = [50, 300]
  for k = 0; k < 2; k = k + 1 {
    let ver = vers[k]
    let n = sizes[k]
    let data = pp_random(n, ver * 17 + 3)
    let qr = @qr.encode_binary(data, @qr.ecc_low(), ver)
    let matrix = pp_to_matrix(qr)
    match @qr.decode_qr(matrix) {
      Some(dec) => assert_true(pp_eq(data, dec))
      None => abort("decode_qr failed for V\{ver}")
    }
  }
}

///|
/// Compress/decompress roundtrip for 100/1000/5000 bytes (Fast level).
test "perf polish: compress decompress roundtrip" {
  let sizes = [100, 1000, 5000]
  for n in sizes {
    let data = pp_random(n, n * 7 + 1)
    let compressed = @qr.compress(data, @qr.fast_compress())
    let decompressed = @qr.decompress(compressed, @qr.fast_compress())
    assert_true(pp_eq(data, decompressed))
  }
}

///|
/// Large file split/reassemble roundtrip for 5000/10000 bytes.
test "perf polish: large file split reassemble" {
  let sizes = [5000, 10000]
  for n in sizes {
    let data = pp_random(n, n * 13 + 5)
    let frames = @qr.split_into_frames(data, 500)
    assert_true(frames.length() > 0)
    match @qr.reassemble_frames(frames) {
      Some(result) => assert_true(pp_eq(data, result))
      None => abort("reassemble failed for \{n} bytes")
    }
  }
}

///|
/// Batch encode 50 QRs: all should succeed without abort.
test "perf polish: batch encode 50 QRs" {
  for i = 0; i < 50; i = i + 1 {
    let data = pp_random(50, i * 17 + 3)
    let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
    assert_true(qr.version() >= 1)
    assert_true(qr.size() >= 21)
  }
}

///|
/// auto_compress + decompress_with_strategy roundtrip for repeated data.
test "perf polish: auto compress strategy roundtrip" {
  let sizes = [100, 1000, 5000]
  for n in sizes {
    let data = pp_make_data(n, 0xAA)
    let result = @qr.auto_compress(data)
    let back = @qr.decompress_with_strategy(
      result.compressed_data,
      result.strategy,
    )
    assert_true(pp_eq(data, back))
  }
}

///|
/// Batch encode+decode roundtrip for 20 QRs of varying size.
test "perf polish: batch encode decode roundtrip 20" {
  for i = 0; i < 20; i = i + 1 {
    let n = 10 + i * 30
    let data = pp_random(n, i * 101 + 11)
    let qr = @qr.encode_binary(data, @qr.ecc_medium(), 1)
    match @qr.decode_from_qrcode(qr) {
      Some(dec) => assert_true(pp_eq(data, dec))
      None => abort("roundtrip failed at i=\{i}")
    }
  }
}
