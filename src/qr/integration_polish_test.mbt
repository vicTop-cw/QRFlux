// Integration polish tests for three weak cross-module integration points.
// 1. decoder reuses qrcode.draw_function_patterns (V7+ version info path)
// 2. static_pipeline strategy+package+qrcode algo_id consistency
// 3. integrate.calculate_frames_needed vs stream.split_into_frames

///|
/// Helper: deterministic pseudo-random bytes (LCG).
fn ip_random(n : Int32, seed : Int32) -> FixedArray[Int32] {
  let fa = FixedArray::make(n, 0)
  let mut s = seed
  for i = 0; i < n; i = i + 1 {
    s = (s * 1103515245 + 12345) & 0x7FFFFFFF
    fa[i] = (s >> 16) & 0xFF
  }
  fa
}

///|
/// Helper: make n copies of a byte value.
fn ip_repeating(n : Int32, val : Int32) -> FixedArray[Int32] {
  FixedArray::make(n, val)
}

///|
/// Helper: convert QrCode to Int32 matrix (0/1) for decode_qr.
fn ip_to_matrix(qr : @qr.QrCode) -> FixedArray[FixedArray[Int32]] {
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
fn ip_arrays_equal(a : FixedArray[Int32], b : FixedArray[Int32]) -> Bool {
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
/// Helper: encode -> matrix -> decode_qr round-trip ok and version pinned.
/// Exercises the V7+ path where decoder reads version-info areas and reuses
/// the encoder's draw_function_patterns to build the isfunction mask.
fn ip_decode_qr_roundtrip(
  data : FixedArray[Int32],
  level : @qr.EccLevel,
  min_version : Int32,
) -> Bool {
  let qr = @qr.encode_binary(data, level, min_version)
  if qr.version() != min_version {
    return false
  }
  let matrix = ip_to_matrix(qr)
  match @qr.decode_qr(matrix) {
    None => false
    Some(d) => ip_arrays_equal(d, data)
  }
}

// ===== Weakness 1: decoder reuses qrcode.draw_function_patterns =====
// decoder.mbt:99 calls draw_function_patterns to build the isfunction mask.
// For V7+ the decoder also reads version info (decoder.mbt:48-53). Verify
// that encode_binary -> decode_qr round-trips and the version is pinned,
// meaning the encoder's and decoder's function-pattern masks agree.

///|
test "integration polish: decoder reuse draw_function_patterns V7 L/M" {
  // V7 is the smallest version with version-info areas. 40 bytes fits V7-M.
  let data = ip_random(40, 7777)
  assert_true(ip_decode_qr_roundtrip(data, @qr.ecc_low(), 7))
  assert_true(ip_decode_qr_roundtrip(data, @qr.ecc_medium(), 7))
}

///|
test "integration polish: decoder reuse draw_function_patterns V10 L/M" {
  // V10 has 3 alignment patterns; exercises alignment-pattern mask reuse.
  let data = ip_random(40, 10101)
  assert_true(ip_decode_qr_roundtrip(data, @qr.ecc_low(), 10))
  assert_true(ip_decode_qr_roundtrip(data, @qr.ecc_medium(), 10))
}

///|
test "integration polish: decoder reuse draw_function_patterns V15 L/M" {
  // V15 has 6 alignment patterns and 2 RS blocks in M.
  let data = ip_random(40, 15151)
  assert_true(ip_decode_qr_roundtrip(data, @qr.ecc_low(), 15))
  assert_true(ip_decode_qr_roundtrip(data, @qr.ecc_medium(), 15))
}

// ===== Weakness 2: static_pipeline strategy+package+qrcode consistency =====
// static_pipeline.mbt:90-115: encode_static calls auto_compress (which calls
// select_strategy) then maps strategy -> algo_id. Verify the algo_id in the
// StaticEncodeResult matches what select_strategy + auto_compress predict.

///|
/// Helper: predict algo_id from select_strategy + auto_compress.
/// Returns 0 (ALGO_NONE) or 1 (ALGO_RLE), mirroring encode_static's logic.
fn ip_predict_algo_id(data : FixedArray[Int32]) -> Int32 {
  let strategy = @qr.select_strategy(data)
  if strategy == @qr.strategy_no_compress() {
    return 0
  }
  let comp = @qr.auto_compress(data)
  if comp.compressed_size < comp.original_size {
    1
  } else {
    0
  }
}

///|
/// Helper: verify encode_static algo_id matches prediction, for one level.
/// Returns true if encode_static returns None (too large) or algo_id matches.
fn ip_algo_id_consistent(
  data : FixedArray[Int32],
  level : @qr.EccLevel,
) -> Bool {
  let predicted = ip_predict_algo_id(data)
  match @qr.encode_static(data, level, 1) {
    None => true
    Some(r) => r.algo_id() == predicted
  }
}

///|
test "integration polish: static pipeline algo_id consistency 10 bytes" {
  // 10 identical bytes -> FastRLE -> RLE compresses -> algo_id=1.
  let rep = ip_repeating(10, 0x42)
  // 10 distinct bytes -> NoCompress -> algo_id=0.
  let rnd = ip_random(10, 31)
  assert_true(ip_algo_id_consistent(rep, @qr.ecc_low()))
  assert_true(ip_algo_id_consistent(rep, @qr.ecc_medium()))
  assert_true(ip_algo_id_consistent(rnd, @qr.ecc_low()))
  assert_true(ip_algo_id_consistent(rnd, @qr.ecc_medium()))
}

///|
test "integration polish: static pipeline algo_id consistency 100 bytes" {
  let rep = ip_repeating(100, 0xAA)
  let rnd = ip_random(100, 53)
  assert_true(ip_algo_id_consistent(rep, @qr.ecc_low()))
  assert_true(ip_algo_id_consistent(rep, @qr.ecc_medium()))
  assert_true(ip_algo_id_consistent(rnd, @qr.ecc_low()))
  assert_true(ip_algo_id_consistent(rnd, @qr.ecc_medium()))
}

///|
test "integration polish: static pipeline algo_id consistency 1000 bytes" {
  let rep = ip_repeating(1000, 0x55)
  let rnd = ip_random(1000, 71)
  assert_true(ip_algo_id_consistent(rep, @qr.ecc_low()))
  assert_true(ip_algo_id_consistent(rep, @qr.ecc_medium()))
  assert_true(ip_algo_id_consistent(rnd, @qr.ecc_low()))
  assert_true(ip_algo_id_consistent(rnd, @qr.ecc_medium()))
}

///|
test "integration polish: static pipeline algo_id consistency 5000 bytes" {
  // 5000 repeating bytes -> RLE compresses to tiny payload -> fits single QR.
  let rep = ip_repeating(5000, 0x55)
  // 5000 random bytes -> NoCompress -> packaged 5032 > V40-L 2953 -> None.
  let rnd = ip_random(5000, 91)
  let predicted_rep = ip_predict_algo_id(rep)
  // Repetitive: encode_static succeeds, algo_id must match prediction.
  match @qr.encode_static(rep, @qr.ecc_low(), 1) {
    Some(r) => assert_true(r.algo_id() == predicted_rep)
    None => abort("5000 rep L: expected Some, got None")
  }
  match @qr.encode_static(rep, @qr.ecc_medium(), 1) {
    Some(r) => assert_true(r.algo_id() == predicted_rep)
    None => abort("5000 rep M: expected Some, got None")
  }
  // Random: encode_static returns None (too large), not abort.
  assert_true(@qr.encode_static(rnd, @qr.ecc_low(), 1) is None)
  assert_true(@qr.encode_static(rnd, @qr.ecc_medium(), 1) is None)
}

// ===== Weakness 3: integrate.calculate_frames_needed vs split_into_frames =====
// integrate.mbt:29 calculate_frames_needed estimates frame count.
// stream.mbt:142 split_into_frames actually splits data. Verify consistency:
// compress=false -> frames_needed == frames.length; compress=true -> formula.

///|
test "integration polish: frames needed vs split compress=false all ecc" {
  // compress=false: calculate_frames_needed matches split_into_frames count.
  // Cover 4 ECC levels via get_stream_metadata (which calls calculate_frames_needed).
  let sizes = [100, 500, 2000]
  let max_payload : Int32 = 100
  let levels = [
    @qr.ecc_low(),
    @qr.ecc_medium(),
    @qr.ecc_quartile(),
    @qr.ecc_high(),
  ]
  for s in sizes {
    let data = ip_repeating(s, 0x42)
    let frames = @qr.split_into_frames(data, max_payload)
    for level in levels {
      let metadata = @qr.get_stream_metadata(s, max_payload, level, false)
      // frames_needed in metadata must equal actual split count.
      let expected = "\"frames_needed\":\{frames.length()}"
      assert_true(metadata.contains(expected))
    }
  }
}

///|
test "integration polish: frames needed compress=true estimation" {
  // compress=true: calculate_frames_needed uses data_size/2 estimation.
  // (split_into_frames does not compress, so we verify the estimation formula
  //  frames = (data_size/2 + max_payload - 1) / max_payload instead.)
  let sizes = [100, 500, 2000]
  let max_payload : Int32 = 100
  for s in sizes {
    let effective = s / 2
    let expected = (effective + max_payload - 1) / max_payload
    assert_true(@qr.calculate_frames_needed(s, max_payload, true) == expected)
  }
}

///|
test "integration polish: frames needed direct calc vs split all ecc" {
  // Direct calculate_frames_needed vs split_into_frames.length, compress=false.
  // calculate_frames_needed does not take ECC, but we loop 4 levels to confirm
  // get_stream_metadata propagates frames_needed consistently regardless of ECC.
  let sizes = [100, 500, 2000]
  let max_payload : Int32 = 100
  let levels = [
    @qr.ecc_low(),
    @qr.ecc_medium(),
    @qr.ecc_quartile(),
    @qr.ecc_high(),
  ]
  for s in sizes {
    let data = ip_repeating(s, 0x42)
    let frames = @qr.split_into_frames(data, max_payload)
    let calc = @qr.calculate_frames_needed(s, max_payload, false)
    assert_true(calc == frames.length())
    for level in levels {
      let metadata = @qr.get_stream_metadata(s, max_payload, level, false)
      let expected = "\"frames_needed\":\{calc}"
      assert_true(metadata.contains(expected))
    }
  }
}
