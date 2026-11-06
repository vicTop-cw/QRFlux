// Error branch polish tests.
// Targets 12 weak error-branch points across the codebase to ensure every
// `return None`, `abort`, and error-return path is exercised or documented.
// See task spec for the weak-point list.
//
// Convention: blackbox tests calling only pub fn via @qr.*.

///|
/// Helper: make a FixedArray[Int32] from a literal Array[Int32].
fn ebp_mk_bytes(xs : Array[Int32]) -> FixedArray[Int32] {
  let fa = FixedArray::make(xs.length(), 0)
  for i = 0; i < xs.length(); i = i + 1 {
    fa[i] = xs[i]
  }
  fa
}

///|
/// Helper: convert a QrCode's Bool modules to an Int32 matrix.
fn ebp_qrcode_to_matrix(qr : @qr.QrCode) -> FixedArray[FixedArray[Int32]] {
  let size = qr.size()
  let matrix = FixedArray::make(size, FixedArray::make(0, 0))
  for y = 0; y < size; y = y + 1 {
    let row = FixedArray::make(size, 0)
    for x = 0; x < size; x = x + 1 {
      row[x] = if qr.get_module(x, y) { 1 } else { 0 }
    }
    matrix[y] = row
  }
  matrix
}

// ===== Weak point 1: PackageHeader::from_bytes version check (package.mbt:136) =====

///|
test "error branch polish 1: PackageHeader from_bytes wrong version" {
  // 构造 magic 正确但 version=2 的 32 字节，触发 version != 1 的 return None 分支。
  let bytes = FixedArray::make(32, 0)
  bytes[0] = 0x51 // 'Q'
  bytes[1] = 0x52 // 'R'
  bytes[2] = 0x46 // 'F'
  bytes[3] = 0x58 // 'X'
  bytes[4] = 2 // wrong version (should be 1)
  let result = @qr.PackageHeader::from_bytes(bytes)
  assert_true(result is None)
}

// ===== Weak point 2: read_format_info level_bits invalid (decoder.mbt:163) =====
//
// read_format_info is private; level_bits = (data >> 3) & 0x3 where data is a
// 5-bit value (0..31) from try_decode_format. Therefore level_bits is always in
// 0..3, and the `_ => return None` branch is theoretically unreachable dead
// code. We cannot trigger it through the public decode_qr API. This test
// sanity-checks that a valid QR decodes successfully (exercising the合法
// level_bits branches) and documents the unreachable branch.

///|
test "error branch polish 2: read_format_info level_bits sanity (unreachable branch documented)" {
  // 编码并解码 1 字节数据，验证合法 level_bits 路径正常工作。
  // 注：level_bits 恒在 0..3，`_ => return None` 分支不可达，此处仅做 sanity check。
  let data = FixedArray::make(1, 0x42)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let decoded = @qr.decode_from_qrcode(qr)
  match decoded {
    Some(d) => assert_true(d.length() == 1 && d[0] == 0x42)
    None => abort("error branch polish 2: valid decode returned None")
  }
}

// ===== Weak point 3: decode_segments mode=0 terminator (decoder.mbt:583) =====

///|
test "error branch polish 3: decode_segments mode=0 terminator via empty data" {
  // 编码空数据：segment 仍写 byte-mode 头 (0100) + count=0，随后 terminator (0000)
  // 触发 mode==0 break 分支，返回空 Some([])。
  // 注："首 4 位为 0" 无法通过公开 API 精确构造（编码器总写 mode 头），
  // 此处用空数据间接覆盖 mode=0 break 分支（数据末尾 terminator）。
  let data = FixedArray::make(0, 0)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let decoded = @qr.decode_from_qrcode(qr)
  match decoded {
    Some(d) => assert_true(d.length() == 0)
    None => abort("error branch polish 3: empty data decode returned None")
  }
}

// ===== Weak point 4: decode_segments unsupported mode (decoder.mbt:674) =====

///|
test "error branch polish 4: decode_segments unsupported mode via corruption" {
  // 构造合法 QR 后大量破坏数据区模块，使解码后数据码字首 4 位可能落入
  // mode=3/5/7 等非法值，触发 `_ => break` 分支。
  // 注：无法通过公开 API 精确设定 mode=3/5/7，此处用破坏性输入验证
  // decode_segments 对非法 mode 的容错（不崩溃，返回 None 或部分结果）。
  let data = FixedArray::make(10, 0x42)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let matrix = ebp_qrcode_to_matrix(qr)
  // 翻转数据区多个模块（避开 finder/format 区域），迫使 mode 字段损坏。
  matrix[10][10] = 1 - matrix[10][10]
  matrix[10][11] = 1 - matrix[10][11]
  matrix[10][12] = 1 - matrix[10][12]
  matrix[11][10] = 1 - matrix[11][10]
  matrix[11][11] = 1 - matrix[11][11]
  matrix[12][10] = 1 - matrix[12][10]
  matrix[13][13] = 1 - matrix[13][13]
  matrix[14][14] = 1 - matrix[14][14]
  let result = @qr.decode_qr(matrix)
  // 不崩溃即可（None 或 Some 都接受）。
  let _ = result
}

// ===== Weak point 5: rle_decompress_optimized truncated input break (strategy.mbt:135,148) =====

///|
test "error branch polish 5a: rle_decompress_optimized [255] truncated" {
  // 单字节 [255]：data[0]==255，i+3=3 >= length=1 → break。返回空。
  let data = ebp_mk_bytes([255])
  let result = @qr.rle_decompress_optimized(data)
  assert_true(result.length() == 0)
}

///|
test "error branch polish 5b: rle_decompress_optimized [255, high] truncated" {
  // 两字节 [255, 1]：data[0]==255，i+3=3 >= length=2 → break。返回空。
  let data = ebp_mk_bytes([255, 1])
  let result = @qr.rle_decompress_optimized(data)
  assert_true(result.length() == 0)
}

///|
test "error branch polish 5c: rle_decompress_optimized [255, h, l] truncated" {
  // 三字节 [255, 0, 1]：data[0]==255，i+3=3 >= length=3 → break。返回空。
  let data = ebp_mk_bytes([255, 0, 1])
  let result = @qr.rle_decompress_optimized(data)
  assert_true(result.length() == 0)
}

///|
test "error branch polish 5d: rle_decompress_optimized [5] single non-255 truncated" {
  // 单字节 [5]（非 255）：data[0]=5!=255，i+1=1 >= length=1 → break。返回空。
  let data = ebp_mk_bytes([5])
  let result = @qr.rle_decompress_optimized(data)
  assert_true(result.length() == 0)
}

// ===== Weak point 6: fountain decode insufficient blocks (fountain.mbt:147) =====

///|
test "error branch polish 6: fountain decode insufficient blocks returns None" {
  // num_blocks=4 但只传 3 个编码块，触发 encoded_blocks.length() < num_blocks 的 return None。
  let fountain = @qr.LTFountain::new(10, 4)
  let blocks : Array[(Int32, FixedArray[Int32])] = []
  blocks.push((1, FixedArray::make(10, 0)))
  blocks.push((2, FixedArray::make(10, 0)))
  blocks.push((3, FixedArray::make(10, 0)))
  let result = fountain.decode(blocks)
  assert_true(result is None)
}

// ===== Weak point 7: fountain decode resolution failure (fountain.mbt:230) =====

///|
test "error branch polish 7: fountain decode unresolved blocks returns None" {
  // num_blocks=4，传 4 个相同 seed 的全 0 块。所有块解析到相同的 block(s)，
  // 剩余 block 无法 resolve，resolved_count < num_blocks → return None。
  let fountain = @qr.LTFountain::new(10, 4)
  let blocks : Array[(Int32, FixedArray[Int32])] = []
  for i = 0; i < 4; i = i + 1 {
    blocks.push((1, FixedArray::make(10, 0)))
  }
  let result = fountain.decode(blocks)
  assert_true(result is None)
}

// ===== Weak point 8: rs_correct lambda_deriv_val==0 (decoder.mbt:483) =====
//
// rs_correct is private; triggering lambda_deriv_val==0 requires precise GF(256)
// construction of a codeword whose Forney denominator vanishes. This cannot be
// reliably constructed through the public decode_qr API. We exercise the
// surrounding RS error-correction path with heavy corruption and assert no
// crash; the specific lambda_deriv_val==0 branch is documented as unreachable
// via public API.

///|
test "error branch polish 8: rs_correct heavy corruption no crash (lambda_deriv branch documented)" {
  // 大量破坏数据模块，迫使 RS 纠错进入异常路径（可能触发 lambda_deriv_val==0
  // 或 error_positions mismatch）。验证不崩溃。
  // 注：lambda_deriv_val==0 无法通过公开 API 精确构造，此处验证 RS 异常路径容错。
  let data = FixedArray::make(5, 0x37)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let matrix = ebp_qrcode_to_matrix(qr)
  // 翻转 12 个数据区模块，超过 V1-Low 的纠错能力（3 码字）。
  matrix[9][9] = 1 - matrix[9][9]
  matrix[9][10] = 1 - matrix[9][10]
  matrix[9][11] = 1 - matrix[9][11]
  matrix[10][9] = 1 - matrix[10][9]
  matrix[10][10] = 1 - matrix[10][10]
  matrix[10][11] = 1 - matrix[10][11]
  matrix[11][9] = 1 - matrix[11][9]
  matrix[11][10] = 1 - matrix[11][10]
  matrix[11][11] = 1 - matrix[11][11]
  matrix[12][12] = 1 - matrix[12][12]
  matrix[13][13] = 1 - matrix[13][13]
  matrix[14][14] = 1 - matrix[14][14]
  let result = @qr.decode_qr(matrix)
  let _ = result
}

// ===== Weak point 9: rs_correct error position count mismatch (decoder.mbt:445) =====

///|
test "error branch polish 9: rs_correct error count mismatch returns None" {
  // 破坏超过 V1-Low 纠错能力（3 码字）的模块，使 Chien 搜索找到的错误位置数
  // 与 num_errors 不匹配，触发 error_positions.length() != num_errors 的 return None。
  let data = FixedArray::make(5, 0x42)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let matrix = ebp_qrcode_to_matrix(qr)
  // 翻转 15 个分散的数据区模块，远超纠错能力。
  matrix[9][9] = 1 - matrix[9][9]
  matrix[9][11] = 1 - matrix[9][11]
  matrix[9][13] = 1 - matrix[9][13]
  matrix[11][9] = 1 - matrix[11][9]
  matrix[11][11] = 1 - matrix[11][11]
  matrix[11][13] = 1 - matrix[11][13]
  matrix[13][9] = 1 - matrix[13][9]
  matrix[13][11] = 1 - matrix[13][11]
  matrix[13][13] = 1 - matrix[13][13]
  matrix[10][12] = 1 - matrix[10][12]
  matrix[12][10] = 1 - matrix[12][10]
  matrix[14][14] = 1 - matrix[14][14]
  matrix[15][15] = 1 - matrix[15][15]
  matrix[16][16] = 1 - matrix[16][16]
  matrix[17][17] = 1 - matrix[17][17]
  let result = @qr.decode_qr(matrix)
  assert_true(result is None)
}

// ===== Weak point 10: choose_version_level abort (qrcode.mbt:119) =====
//
// choose_version_level is private and calls abort("QR data too long") when no
// version in [minversion, 40] fits the data. MoonBit abort terminates the
// process and fails the test, so we cannot directly trigger it. We instead
// verify the abort precondition boundary: num_data_codewords(40, High) gives
// the V40-H capacity (1273 bytes), confirming the upper limit that, when
// exceeded, would cause abort.

///|
test "error branch polish 10: choose_version_level abort boundary documented" {
  // 验证 V40-H 容量上限（abort 的前置条件边界）。
  // 注：abort 分支无法在不导致测试失败的情况下触发，此处验证容量边界。
  // V40-H: num_raw_data_modules(40)/8 = 3706, ECC = 30*81 = 2430, data = 1276。
  let capacity = @qr.num_data_codewords(40, @qr.ecc_high())
  assert_true(capacity == 1276)
}

// ===== Weak point 11: reassemble_frames frame count mismatch (stream.mbt:206) =====

///|
test "error branch polish 11: reassemble_frames frame count mismatch returns None" {
  // 构造 total_frames=3 但只传 2 帧，触发 frames.length() != total_frames 的 return None。
  let data = FixedArray::make(96, 0)
  for i = 0; i < 96; i = i + 1 {
    data[i] = i % 256
  }
  let frames = @qr.split_into_frames(data, 32) // 3 frames
  assert_true(frames.length() == 3)
  let partial : Array[FixedArray[Int32]] = []
  partial.push(frames[0])
  partial.push(frames[1])
  let result = @qr.reassemble_frames(partial)
  assert_true(result is None)
}

// ===== Weak point 12: reassemble_frames duplicate/non-contiguous frame index (stream.mbt:230) =====

///|
test "error branch polish 12: reassemble_frames duplicate frame index returns None" {
  // 构造 current_frame=[0,0,2] 重复索引，触发 headers[order[i]].current_frame != i 的 return None。
  let data = FixedArray::make(96, 0)
  for i = 0; i < 96; i = i + 1 {
    data[i] = i % 256
  }
  let frames = @qr.split_into_frames(data, 32) // 3 frames: indices 0,1,2
  assert_true(frames.length() == 3)
  // 用 frame[0] 的副本替换 frame[1]，使 current_frame 序列变为 [0,0,2]。
  let dup : Array[FixedArray[Int32]] = []
  dup.push(frames[0])
  let frame0_copy = FixedArray::make(frames[0].length(), 0)
  for i = 0; i < frames[0].length(); i = i + 1 {
    frame0_copy[i] = frames[0][i]
  }
  dup.push(frame0_copy)
  dup.push(frames[2])
  let result = @qr.reassemble_frames(dup)
  assert_true(result is None)
}
