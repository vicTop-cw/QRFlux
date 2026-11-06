// Fountain code extra tests.
// Supplements fountain_test.mbt and fountain_recovery_test.mbt with
// broader coverage of LTFountain new / split / encode_block / encode_all / decode.

///|
/// Helper: make test data with recognizable pattern.
fn fextra_make_data(total_len : Int32) -> FixedArray[Int32] {
  let data = FixedArray::make(total_len, 0)
  for i = 0; i < total_len; i = i + 1 {
    data[i] = (i * 7 + 13) & 0xFF
  }
  data
}

///|
/// Helper: check two FixedArray[Int32] equal.
fn fextra_arrays_equal(a : FixedArray[Int32], b : FixedArray[Int32]) -> Bool {
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
/// Helper: encode_all -> decode roundtrip ok?
fn fextra_roundtrip_ok(
  block_size : Int32,
  num_blocks : Int32,
  num_encoded : Int32,
) -> Bool {
  let fountain = @qr.LTFountain::new(block_size, num_blocks)
  let data = fextra_make_data(block_size * num_blocks)
  let encoded = fountain.encode_all(data, num_encoded)
  match fountain.decode(encoded) {
    None => false
    Some(d) => fextra_arrays_equal(d, data)
  }
}

// ===== LTFountain::new / split =====

///|
test "fountain extra: new and split basic" {
  let fountain = @qr.LTFountain::new(10, 4)
  let data = fextra_make_data(40)
  let blocks = fountain.split(data)
  assert_true(blocks.length() == 4)
  for i = 0; i < 4; i = i + 1 {
    assert_true(blocks[i].length() == 10)
  }
}

///|
test "fountain extra: split preserves data" {
  // split 后的块拼接还原原数据。
  let block_size = 10
  let num_blocks = 4
  let fountain = @qr.LTFountain::new(block_size, num_blocks)
  let data = fextra_make_data(40)
  let blocks = fountain.split(data)
  let reassembled = FixedArray::make(40, 0)
  for i = 0; i < num_blocks; i = i + 1 {
    for j = 0; j < block_size; j = j + 1 {
      reassembled[i * block_size + j] = blocks[i][j]
    }
  }
  assert_true(fextra_arrays_equal(reassembled, data))
}

///|
test "fountain extra: split various block sizes" {
  let sizes = [5, 10, 20]
  for i = 0; i < sizes.length(); i = i + 1 {
    let bs = sizes[i]
    let fountain = @qr.LTFountain::new(bs, 4)
    let data = fextra_make_data(bs * 4)
    let blocks = fountain.split(data)
    assert_true(blocks.length() == 4)
    for k = 0; k < 4; k = k + 1 {
      assert_true(blocks[k].length() == bs)
    }
  }
}

// ===== encode_block / encode_all =====

///|
test "fountain extra: encode block produces valid output" {
  let fountain = @qr.LTFountain::new(10, 4)
  let data = fextra_make_data(40)
  let blocks = fountain.split(data)
  let encoded = fountain.encode_block(blocks, 1)
  // Encoded block has correct size (== block_size).
  assert_true(encoded.length() == 10)
  assert_true(encoded.length() > 0)
}

///|
test "fountain extra: encode all produces requested count" {
  let fountain = @qr.LTFountain::new(10, 4)
  let data = fextra_make_data(40)
  let counts = [5, 8, 12]
  for i = 0; i < counts.length(); i = i + 1 {
    let encoded = fountain.encode_all(data, counts[i])
    assert_true(encoded.length() == counts[i])
  }
}

///|
test "fountain extra: encode all various counts" {
  let fountain = @qr.LTFountain::new(10, 10)
  let data = fextra_make_data(100)
  let counts = [10, 15, 20, 30]
  for i = 0; i < counts.length(); i = i + 1 {
    let encoded = fountain.encode_all(data, counts[i])
    assert_true(encoded.length() == counts[i])
    // Each encoded block has correct size (== block_size).
    for k = 0; k < counts[i]; k = k + 1 {
      let (_, block) = encoded[k]
      assert_true(block.length() == 10)
    }
  }
}

///|
test "fountain extra: encode block different seeds" {
  // 不同 seed 产生不同编码块（degree 或 block 选择不同）。
  let fountain = @qr.LTFountain::new(10, 4)
  let data = fextra_make_data(40)
  let blocks = fountain.split(data)
  let enc1 = fountain.encode_block(blocks, 1)
  let enc2 = fountain.encode_block(blocks, 2)
  let enc3 = fountain.encode_block(blocks, 3)
  // At least two encoded blocks should differ.
  let mut all_same = true
  if !fextra_arrays_equal(enc1, enc2) {
    all_same = false
  }
  if !fextra_arrays_equal(enc1, enc3) {
    all_same = false
  }
  if !fextra_arrays_equal(enc2, enc3) {
    all_same = false
  }
  assert_true(!all_same)
}

// ===== decode recovery =====

///|
test "fountain extra: decode with exact blocks" {
  // K=2, exactly 2 encoded blocks. seed=2 has degree=1 (resolves one block),
  // seed=1 then resolves the other. Deterministic success.
  let fountain = @qr.LTFountain::new(10, 2)
  let data = fextra_make_data(20)
  let encoded = fountain.encode_all(data, 2)
  let decoded = fountain.decode(encoded)
  match decoded {
    Some(result) => assert_true(fextra_arrays_equal(result, data))
    None => assert_true(false)
  }
}

///|
test "fountain extra: decode with extra blocks" {
  // K=4, K+4 overhead blocks.
  let fountain = @qr.LTFountain::new(10, 4)
  let data = fextra_make_data(40)
  let encoded = fountain.encode_all(data, 8)
  let decoded = fountain.decode(encoded)
  match decoded {
    Some(result) => assert_true(fextra_arrays_equal(result, data))
    None => assert_true(false)
  }
}

///|
test "fountain extra: decode various block sizes" {
  // K=4, K+4 overhead. Different block sizes.
  let sizes = [5, 10, 20]
  for i = 0; i < sizes.length(); i = i + 1 {
    let bs = sizes[i]
    assert_true(fextra_roundtrip_ok(bs, 4, 8))
  }
}

///|
test "fountain extra: decode various num blocks" {
  // K+12 overhead ensures robust decoding across K values.
  let nbs = [2, 4, 8]
  for i = 0; i < nbs.length(); i = i + 1 {
    let nb = nbs[i]
    assert_true(fextra_roundtrip_ok(10, nb, nb + 12))
  }
}

// ===== Edge cases =====

///|
test "fountain extra: single block" {
  // num_blocks=1: trivial fountain, every encoded block equals the original.
  let fountain = @qr.LTFountain::new(10, 1)
  let data = fextra_make_data(10)
  let encoded = fountain.encode_all(data, 3)
  let decoded = fountain.decode(encoded)
  match decoded {
    Some(result) => assert_true(fextra_arrays_equal(result, data))
    None => assert_true(false)
  }
}

///|
test "fountain extra: small block size" {
  // block_size=1: each block is a single byte.
  let fountain = @qr.LTFountain::new(1, 10)
  let data = fextra_make_data(10)
  let encoded = fountain.encode_all(data, 20)
  let decoded = fountain.decode(encoded)
  match decoded {
    Some(result) => assert_true(fextra_arrays_equal(result, data))
    None => assert_true(false)
  }
}

///|
test "fountain extra: large num blocks" {
  // num_blocks=100: larger fountain, K+50 overhead.
  let fountain = @qr.LTFountain::new(4, 100)
  let data = fextra_make_data(400)
  let encoded = fountain.encode_all(data, 150)
  let decoded = fountain.decode(encoded)
  match decoded {
    Some(result) => assert_true(fextra_arrays_equal(result, data))
    None => assert_true(false)
  }
}

///|
test "fountain extra: block size equals data size" {
  // block_size == data length, num_blocks=1.
  let fountain = @qr.LTFountain::new(40, 1)
  let data = fextra_make_data(40)
  let encoded = fountain.encode_all(data, 3)
  let decoded = fountain.decode(encoded)
  match decoded {
    Some(result) => assert_true(fextra_arrays_equal(result, data))
    None => assert_true(false)
  }
}
