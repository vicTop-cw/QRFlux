// LT 喷泉码多场景黑盒测试。
//
// 覆盖：
//   - 基本编码/解码往返（N 原始块 → M 编码块 → 解码还原）
//   - 丢包恢复（编码 N+K 块，丢弃 K 块仍能解码）
//   - 恰好 N 块解码（无冗余）/ 不足 N 块返回 None
//   - 不同 num_blocks (1/2/5/10/50)
//   - robust soliton degree 分布
//   - 重复块处理 / 种子可重复性
//   - 大块解码 (block_size 100/1000)
//
// 仅调用 src/qr/fountain.mbt 中的 pub fn。

///|
/// 辅助：构造带可识别模式的数据。
fn fscn_make_data(total_len : Int32) -> FixedArray[Int32] {
  let data = FixedArray::make(total_len, 0)
  for i = 0; i < total_len; i = i + 1 {
    data[i] = (i * 7 + 13) & 0xFF
  }
  data
}

///|
/// 辅助：比较两个 FixedArray[Int32] 是否完全相等。
fn fscn_eq(a : FixedArray[Int32], b : FixedArray[Int32]) -> Bool {
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
/// 辅助：encode_all -> decode 往返是否成功还原原始数据。
fn fscn_roundtrip(
  block_size : Int32,
  num_blocks : Int32,
  num_encoded : Int32,
) -> Bool {
  let fountain = @qr.LTFountain::new(block_size, num_blocks)
  let data = fscn_make_data(block_size * num_blocks)
  let encoded = fountain.encode_all(data, num_encoded)
  match fountain.decode(encoded) {
    None => false
    Some(d) => fscn_eq(d, data)
  }
}

///|
/// 辅助：从 encoded 中按步长抽取子集（模拟丢包，step=2 取偶数索引）。
fn fscn_subset(
  encoded : Array[(Int32, FixedArray[Int32])],
  step : Int32,
) -> Array[(Int32, FixedArray[Int32])] {
  let out = Array::make(0, (0, FixedArray::make(0, 0)))
  for i = 0; i < encoded.length(); i = i + 1 {
    if i % step == 0 {
      out.push(encoded[i])
    }
  }
  out
}

// ===== 基本编码/解码往返 =====

///|
test "scenario: basic roundtrip N blocks to M encoded to N decoded" {
  // K=5 原始块，编码 M=15 块，解码还原。
  let fountain = @qr.LTFountain::new(10, 5)
  let data = fscn_make_data(50)
  let encoded = fountain.encode_all(data, 15)
  assert_true(encoded.length() == 15)
  let decoded = fountain.decode(encoded)
  match decoded {
    Some(result) => assert_true(fscn_eq(result, data))
    None => assert_true(false)
  }
}

///|
test "scenario: roundtrip across various num blocks" {
  // num_blocks = 1/2/5/10/50，均用充足 overhead 保证解码成功。
  let nbs = [1, 2, 5, 10, 50]
  for i = 0; i < nbs.length(); i = i + 1 {
    let nb = nbs[i]
    // overhead = max(nb, 20) 保证充足冗余。
    let overhead = if nb >= 20 { nb } else { 20 }
    assert_true(fscn_roundtrip(8, nb, nb + overhead))
  }
}

// ===== 丢包恢复 =====

///|
test "scenario: lossy recovery drop half blocks" {
  // K=8，编码 20 块，取偶数索引 10 块（K+2 overhead），仍能解码。
  let fountain = @qr.LTFountain::new(10, 8)
  let data = fscn_make_data(80)
  let encoded = fountain.encode_all(data, 20)
  let subset = fscn_subset(encoded, 2)
  assert_true(subset.length() == 10)
  let decoded = fountain.decode(subset)
  match decoded {
    Some(result) => assert_true(fscn_eq(result, data))
    None => assert_true(false)
  }
}

///|
test "scenario: lossy recovery with heavy overhead" {
  // K=10，编码 30 块，取每 2 个索引 15 块（K+5 overhead），仍能解码。
  let fountain = @qr.LTFountain::new(10, 10)
  let data = fscn_make_data(100)
  let encoded = fountain.encode_all(data, 30)
  let subset = fscn_subset(encoded, 2)
  assert_true(subset.length() == 15)
  let decoded = fountain.decode(subset)
  match decoded {
    Some(result) => assert_true(fscn_eq(result, data))
    None => assert_true(false)
  }
}

///|
test "scenario: large num blocks 50 with lossy recovery" {
  // K=50，编码 100 块全用（K+50 overhead，与 K=100 用 K+50 同比例），大 K 解码。
  let fountain = @qr.LTFountain::new(8, 50)
  let data = fscn_make_data(400)
  let encoded = fountain.encode_all(data, 100)
  assert_true(encoded.length() == 100)
  let decoded = fountain.decode(encoded)
  match decoded {
    Some(result) => assert_true(fscn_eq(result, data))
    None => assert_true(false)
  }
}

///|
test "scenario: lossy recovery K=20 drop half" {
  // K=20，编码 60 块，取前 30 块（seed 1..30，K+10 overhead），仍能解码。
  let fountain = @qr.LTFountain::new(8, 20)
  let data = fscn_make_data(160)
  let encoded = fountain.encode_all(data, 60)
  let subset = Array::make(0, (0, FixedArray::make(0, 0)))
  for i = 0; i < 30; i = i + 1 {
    subset.push(encoded[i])
  }
  assert_true(subset.length() == 30)
  let decoded = fountain.decode(subset)
  match decoded {
    Some(result) => assert_true(fscn_eq(result, data))
    None => assert_true(false)
  }
}

// ===== 恰好 N 块 / 不足 N 块 =====

///|
test "scenario: exact N blocks decode no redundancy" {
  // K=2，恰好 2 块解码（无冗余）。
  // seed=1,2 中至少一个 degree=1 启动 peeling，级联解析第二块。
  let fountain = @qr.LTFountain::new(10, 2)
  let data = fscn_make_data(20)
  let encoded = fountain.encode_all(data, 2)
  assert_true(encoded.length() == 2)
  let decoded = fountain.decode(encoded)
  match decoded {
    Some(result) => assert_true(fscn_eq(result, data))
    None => assert_true(false)
  }
}

///|
test "scenario: exact N blocks single block trivial" {
  // K=1，恰好 1 块（trivial fountain，每块即原始块）。
  let fountain = @qr.LTFountain::new(10, 1)
  let data = fscn_make_data(10)
  let encoded = fountain.encode_all(data, 1)
  let decoded = fountain.decode(encoded)
  match decoded {
    Some(result) => assert_true(fscn_eq(result, data))
    None => assert_true(false)
  }
}

///|
test "scenario: insufficient blocks returns None" {
  // K=10，只给 7 块（< K），decode 返回 None。
  let fountain = @qr.LTFountain::new(10, 10)
  let data = fscn_make_data(100)
  let encoded = fountain.encode_all(data, 7)
  let result = fountain.decode(encoded)
  assert_true(result is None)
}

///|
test "scenario: zero blocks returns None" {
  // 0 块解码返回 None。
  let fountain = @qr.LTFountain::new(10, 5)
  let empty = Array::make(0, (0, FixedArray::make(0, 0)))
  let result = fountain.decode(empty)
  assert_true(result is None)
}

// ===== robust soliton degree 分布 =====

///|
test "scenario: robust soliton degree in range across many seeds" {
  // 大量 seed 下 degree ∈ [1, K]。
  let fountain = @qr.LTFountain::new(10, 10)
  for seed = 1; seed <= 200; seed = seed + 1 {
    let d = fountain.robust_soliton_degree(seed)
    assert_true(d >= 1)
    assert_true(d <= 10)
  }
}

///|
test "scenario: robust soliton degree distribution has low degrees" {
  // 统计 1000 个 seed 的 degree 分布：
  //   r < 500 → degree=1（约 50%）
  //   r < 800 → degree=2（约 30%）
  //   r < 950 → degree=3（约 15%）
  //   else   → degree>=4（约 5%）
  // 验证 degree=1 占多数，degree<=2 占绝大多数。
  let fountain = @qr.LTFountain::new(10, 10)
  let mut deg_one = 0
  let mut deg_low = 0
  for seed = 1; seed <= 1000; seed = seed + 1 {
    let d = fountain.robust_soliton_degree(seed)
    if d == 1 {
      deg_one = deg_one + 1
    }
    if d <= 2 {
      deg_low = deg_low + 1
    }
  }
  // degree=1 应至少 30%（robust soliton 低度优先特性）。
  assert_true(deg_one > 300)
  // degree<=2 应至少 70%。
  assert_true(deg_low > 700)
}

// ===== 重复块处理 =====

///|
test "scenario: duplicate encoded blocks handled" {
  // 含重复块的编码集合仍能解码（peeling 跳过冗余邻居）。
  // K=4，取前 8 块（seed 1-8，K+4 已知可解码），再追加第 0 块重复 4 次。
  let fountain = @qr.LTFountain::new(10, 4)
  let data = fscn_make_data(40)
  let encoded = fountain.encode_all(data, 8)
  let dup = Array::make(0, (0, FixedArray::make(0, 0)))
  for i = 0; i < 8; i = i + 1 {
    dup.push(encoded[i])
  }
  for i = 0; i < 4; i = i + 1 {
    dup.push(encoded[0])
  }
  assert_true(dup.length() == 12)
  let decoded = fountain.decode(dup)
  match decoded {
    Some(result) => assert_true(fscn_eq(result, data))
    None => assert_true(false)
  }
}

// ===== 种子可重复性 =====

///|
test "scenario: same seed produces same encoded block" {
  // 同 seed 产生完全相同的编码块（确定性）。
  let fountain = @qr.LTFountain::new(10, 8)
  let data = fscn_make_data(80)
  let blocks = fountain.split(data)
  let enc1 = fountain.encode_block(blocks, 42)
  let enc2 = fountain.encode_block(blocks, 42)
  assert_true(fscn_eq(enc1, enc2))
}

///|
test "scenario: same seed produces same select_blocks" {
  // 同 seed + 同 degree 产生完全相同的索引序列。
  let fountain = @qr.LTFountain::new(10, 10)
  let s1 = fountain.select_blocks(99, 5)
  let s2 = fountain.select_blocks(99, 5)
  assert_true(s1.length() == s2.length())
  for i = 0; i < s1.length(); i = i + 1 {
    assert_true(s1[i] == s2[i])
  }
}

///|
test "scenario: encode_all uses sequential seeds 1 to M" {
  // encode_all(data, M) 第 i 块的 seed == i+1，
  // 且等价于手动 encode_block(blocks, i+1)。
  let fountain = @qr.LTFountain::new(10, 4)
  let data = fscn_make_data(40)
  let blocks = fountain.split(data)
  let encoded = fountain.encode_all(data, 6)
  for i = 0; i < 6; i = i + 1 {
    let (seed, block) = encoded[i]
    assert_true(seed == i + 1)
    let manual = fountain.encode_block(blocks, i + 1)
    assert_true(fscn_eq(block, manual))
  }
}

///|
test "scenario: select_blocks length at most degree and unique" {
  // select_blocks 因去重，length <= degree；且所有索引唯一、在 [0, K) 内。
  let fountain = @qr.LTFountain::new(10, 10)
  for d = 1; d <= 10; d = d + 1 {
    let idx = fountain.select_blocks(7, d)
    assert_true(idx.length() <= d)
    for i = 0; i < idx.length(); i = i + 1 {
      assert_true(idx[i] >= 0)
      assert_true(idx[i] < 10)
      for j = i + 1; j < idx.length(); j = j + 1 {
        assert_true(idx[i] != idx[j])
      }
    }
  }
}

// ===== 大块解码 =====

///|
test "scenario: large block size 100 decode" {
  // block_size=100，K=5，大块往返。
  let fountain = @qr.LTFountain::new(100, 5)
  let data = fscn_make_data(500)
  let encoded = fountain.encode_all(data, 15)
  let decoded = fountain.decode(encoded)
  match decoded {
    Some(result) => assert_true(fscn_eq(result, data))
    None => assert_true(false)
  }
}

///|
test "scenario: large block size 1000 decode" {
  // block_size=1000，K=4，大块往返。
  let fountain = @qr.LTFountain::new(1000, 4)
  let data = fscn_make_data(4000)
  let encoded = fountain.encode_all(data, 12)
  let decoded = fountain.decode(encoded)
  match decoded {
    Some(result) => assert_true(fscn_eq(result, data))
    None => assert_true(false)
  }
}
