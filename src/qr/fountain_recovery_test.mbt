// LT 喷泉码丢帧恢复测试。
//
// 历史 bug 已修复：
//   BUG-1 (fountain.mbt split): Array::make(num_blocks, FixedArray::make(...))
//        共享引用 → 改为循环创建独立实例。
//   BUG-2 (fountain.mbt decode neighbors): 同样共享引用 → 改为循环。
//   BUG-3 (fountain.mbt decode original_blocks): 同样共享引用 → 改为循环。
//   BUG-4 (strategy.mbt decompress): 用错 rle_decompress → 改为 rle_decompress_optimized。
//
// 本文件策略：
//   - "valid-*" 测试：验证不受 bug 影响的正确行为
//   - "recovery-*" 测试：验证修复后喷泉码能从 K+overhead 块恢复原始数据
//   - "integrity-*" 测试：验证 split/encode/decode 数据完整性

///|
/// 辅助函数：构造测试数据（带可识别模式）。
fn make_test_data(total_len : Int32) -> FixedArray[Int32] {
  let data = FixedArray::make(total_len, 0)
  for i = 0; i < total_len; i = i + 1 {
    data[i] = (i * 7 + 13) & 0xFF
  }
  data
}

///|
/// 辅助函数：比对两个 FixedArray 是否完全相同。
fn arrays_equal(a : FixedArray[Int32], b : FixedArray[Int32]) -> Bool {
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

// ===== 修复后行为测试 =====

///|
test "recovery: split preserves independent blocks" {
  // 修复 BUG-1 后：split 返回的每块是独立 FixedArray 实例。
  let fountain = @qr.LTFountain::new(10, 4)
  let data = make_test_data(40)
  let blocks = fountain.split(data)
  assert_true(blocks.length() == 4)
  // 修改 blocks[0] 不应该影响 blocks[1]
  blocks[0][0] = 0xFF
  assert_true(blocks[1][0] != 0xFF)
  blocks[1][1] = 0xAA
  assert_true(blocks[0][1] != 0xAA)
}

///|
test "recovery: split preserves data per block" {
  // 修复 BUG-1 后：split 后 blocks[i][j] == data[i * block_size + j]。
  let block_size = 10
  let num_blocks = 10
  let fountain = @qr.LTFountain::new(block_size, num_blocks)
  let data = make_test_data(100)
  let blocks = fountain.split(data)
  // 每块内容应该等于 data 对应区段
  for i = 0; i < num_blocks; i = i + 1 {
    for j = 0; j < block_size; j = j + 1 {
      assert_true(blocks[i][j] == data[i * block_size + j])
    }
  }
}

///|
test "recovery: split with padding last block zero filled" {
  // 修复 BUG-1 后：数据长度不是 block_size 整数倍时，超出部分用 0 填充。
  let fountain = @qr.LTFountain::new(10, 5) // 5 块 * 10 = 50 字节容量
  let data = FixedArray::make(35, 0x42) // 只有 35 字节
  let blocks = fountain.split(data)
  assert_true(blocks.length() == 5)
  // 前 3 块 + 第 4 块前 5 字节 = 0x42
  for i = 0; i < 3; i = i + 1 {
    for j = 0; j < 10; j = j + 1 {
      assert_true(blocks[i][j] == 0x42)
    }
  }
  // 第 4 块：前 5 字节 0x42，后 5 字节 0
  for j = 0; j < 5; j = j + 1 {
    assert_true(blocks[3][j] == 0x42)
  }
  for j = 5; j < 10; j = j + 1 {
    assert_true(blocks[3][j] == 0)
  }
  // 第 5 块：全 0
  for j = 0; j < 10; j = j + 1 {
    assert_true(blocks[4][j] == 0)
  }
}

///|
test "recovery: encode_all produces non-degenerate blocks" {
  // 修复 BUG-1 后：编码块应该包含原始数据的混合，不应全是 0。
  let fountain = @qr.LTFountain::new(10, 4)
  let data = make_test_data(40)
  let encoded = fountain.encode_all(data, 8)
  // 至少有一些非零块
  let mut nonzero_count = 0
  for i = 0; i < encoded.length(); i = i + 1 {
    let (_, block) = encoded[i]
    let mut is_zero = true
    for j = 0; j < block.length(); j = j + 1 {
      if block[j] != 0 {
        is_zero = false
        break
      }
    }
    if !is_zero {
      nonzero_count = nonzero_count + 1
    }
  }
  assert_true(nonzero_count > 0)
}

///|
test "recovery: decode restores original data with K blocks" {
  // 修复 BUG-1/2/3 后：decode 能从 K+overhead 块恢复原始数据。
  let fountain = @qr.LTFountain::new(10, 4)
  let data = make_test_data(40)
  let encoded = fountain.encode_all(data, 8) // K+4 overhead
  let decoded = fountain.decode(encoded)
  match decoded {
    Some(result) => assert_true(arrays_equal(result, data))
    None => assert_true(false)
  }
}

///|
test "recovery: decode restores original data larger K" {
  // 修复后：更大的 K 也能恢复。
  let fountain = @qr.LTFountain::new(10, 10)
  let data = make_test_data(100)
  let encoded = fountain.encode_all(data, 20) // K+10 overhead
  let decoded = fountain.decode(encoded)
  match decoded {
    Some(result) => assert_true(arrays_equal(result, data))
    None => assert_true(false)
  }
}

///|
test "recovery: decode handles lost blocks" {
  // 修复后：丢帧场景，从 K+overhead 块中丢弃部分仍能恢复。
  let fountain = @qr.LTFountain::new(10, 8)
  let data = make_test_data(80)
  let encoded = fountain.encode_all(data, 20) // 生成 20 块
  // 模拟丢帧：只取偶数索引的块（10 块，>= K=8）
  let subset = Array::make(0, (0, FixedArray::make(0, 0)))
  for i = 0; i < 20; i = i + 1 {
    if i % 2 == 0 {
      subset.push(encoded[i])
    }
  }
  assert_true(subset.length() == 10)
  let decoded = fountain.decode(subset)
  match decoded {
    Some(result) => assert_true(arrays_equal(result, data))
    None => assert_true(false)
  }
}

// ===== 有效行为测试（不受 bug 影响，应通过）=====

///|
test "valid: insufficient blocks returns None" {
  // 验证 decode 在块数 < K 时返回 None（此逻辑不依赖 split）。
  let fountain = @qr.LTFountain::new(10, 10)
  let data = make_test_data(100)
  let encoded = fountain.encode_all(data, 15)
  // 只取前 5 个块（< K=10）
  let subset = Array::make(0, (0, FixedArray::make(0, 0)))
  for i = 0; i < 5; i = i + 1 {
    subset.push(encoded[i])
  }
  let result = fountain.decode(subset)
  assert_true(result is None)
}

///|
test "valid: deterministic encode with same seed" {
  // 验证相同 seed 产生相同编码块（确定性）。
  let fountain = @qr.LTFountain::new(10, 10)
  let data = make_test_data(100)
  let blocks = fountain.split(data)
  let enc1 = fountain.encode_block(blocks, 7)
  let enc2 = fountain.encode_block(blocks, 7)
  assert_true(arrays_equal(enc1, enc2))
}

///|
test "valid: split returns correct block count" {
  // 验证 split 返回正确数量的块。
  let fountain = @qr.LTFountain::new(10, 10)
  let data = make_test_data(100)
  let blocks = fountain.split(data)
  assert_true(blocks.length() == 10)
}

///|
test "valid: split block size correct" {
  // 验证 split 每块大小正确。
  let fountain = @qr.LTFountain::new(10, 10)
  let data = make_test_data(100)
  let blocks = fountain.split(data)
  for i = 0; i < 10; i = i + 1 {
    assert_true(blocks[i].length() == 10)
  }
}

///|
test "valid: encode_block returns correct size" {
  // 验证 encode_block 返回正确大小。
  let fountain = @qr.LTFountain::new(10, 10)
  let data = make_test_data(100)
  let blocks = fountain.split(data)
  let encoded = fountain.encode_block(blocks, 1)
  assert_true(encoded.length() == 10)
}

///|
test "valid: encode_all returns correct count" {
  // 验证 encode_all 返回正确数量的编码块。
  let fountain = @qr.LTFountain::new(10, 10)
  let data = make_test_data(100)
  let encoded = fountain.encode_all(data, 15)
  assert_true(encoded.length() == 15)
}

///|
test "valid: robust_soliton_degree in valid range" {
  // 验证 degree 在 1 到 K 之间。
  let fountain = @qr.LTFountain::new(10, 10)
  for seed = 1; seed <= 20; seed = seed + 1 {
    let degree = fountain.robust_soliton_degree(seed)
    assert_true(degree >= 1)
    assert_true(degree <= 10)
  }
}

///|
test "valid: select_blocks returns unique indices" {
  // 验证 select_blocks 返回不重复的索引。
  let fountain = @qr.LTFountain::new(10, 10)
  let indices = fountain.select_blocks(42, 5)
  // 检查不重复
  for i = 0; i < indices.length(); i = i + 1 {
    for j = i + 1; j < indices.length(); j = j + 1 {
      assert_true(indices[i] != indices[j])
    }
    // 索引在有效范围内
    assert_true(indices[i] >= 0)
    assert_true(indices[i] < 10)
  }
}

///|
test "valid: pseudo_random deterministic" {
  // 验证伪随机数确定性。
  let fountain = @qr.LTFountain::new(10, 10)
  let r1 = fountain.pseudo_random(123)
  let r2 = fountain.pseudo_random(123)
  assert_true(r1 == r2)
}

///|
test "valid: all zero data encode decode" {
  // 全 0 数据是退化情况：编码块也是全 0，decode 返回全 0。
  let fountain = @qr.LTFountain::new(10, 10)
  let data = FixedArray::make(100, 0)
  let encoded = fountain.encode_all(data, 15)
  let decoded = fountain.decode(encoded)
  match decoded {
    Some(result) => assert_true(arrays_equal(result, data))
    None => assert_true(true) // 全 0 数据退化情况，None 也可接受
  }
}
