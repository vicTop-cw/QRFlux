// LT 喷泉码鲁棒性黑盒测试。
//
// 覆盖方向：
//   - 高丢包率恢复（编码 2N 块仅用后 N 块）
//   - 50% 丢包恢复
//   - 重复块处理
//   - 恰好 N 块解码（无冗余）
//   - 不足 N 块返回 None
//   - 不同 num_blocks (1/2/5/10/20/50)
//   - 不同 block_size (1/10/100/500)
//   - 种子可重复性 / 编码块独立性
//   - 解码后数据与原始一致
//   - 极端丢包 / 大 K 高丢包率
//
// 仅调用 src/qr/fountain.mbt 中的 pub fn。

///|
/// 辅助：构造带可识别模式的数据。
fn frob_make_data(total_len : Int32) -> FixedArray[Int32] {
  let data = FixedArray::make(total_len, 0)
  for i = 0; i < total_len; i = i + 1 {
    data[i] = (i * 7 + 13) & 0xFF
  }
  data
}

///|
/// 辅助：比较两个 FixedArray[Int32] 是否完全相等。
fn frob_eq(a : FixedArray[Int32], b : FixedArray[Int32]) -> Bool {
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
fn frob_roundtrip(
  block_size : Int32,
  num_blocks : Int32,
  num_encoded : Int32,
) -> Bool {
  let fountain = @qr.LTFountain::new(block_size, num_blocks)
  let data = frob_make_data(block_size * num_blocks)
  let encoded = fountain.encode_all(data, num_encoded)
  match fountain.decode(encoded) {
    None => false
    Some(d) => frob_eq(d, data)
  }
}

///|
/// 辅助：从 encoded 取后半部分（模拟高丢包率，丢前一半）。
fn frob_take_last_half(
  encoded : Array[(Int32, FixedArray[Int32])],
) -> Array[(Int32, FixedArray[Int32])] {
  let total = encoded.length()
  let half = total / 2
  let out = Array::make(0, (0, FixedArray::make(0, 0)))
  for i = half; i < total; i = i + 1 {
    out.push(encoded[i])
  }
  out
}

// ===== 高丢包率恢复 =====

///|
test "robust: high loss rate use last N of 2N blocks" {
  // K=10，编码 2N=20 块，仅用后 N=10 块（seed 11-20）解码。
  let fountain = @qr.LTFountain::new(10, 10)
  let data = frob_make_data(100)
  let encoded = fountain.encode_all(data, 20)
  assert_true(encoded.length() == 20)
  let tail = frob_take_last_half(encoded)
  assert_true(tail.length() == 10)
  let decoded = fountain.decode(tail)
  match decoded {
    Some(result) => assert_true(frob_eq(result, data))
    None => assert_true(false)
  }
}

///|
test "robust: high loss rate K=8 use last 12 of 24" {
  // K=8，编码 24 块（3K），仅用后 12 块（seed 13-24，K+4 overhead）解码。
  let fountain = @qr.LTFountain::new(10, 8)
  let data = frob_make_data(80)
  let encoded = fountain.encode_all(data, 24)
  let tail = frob_take_last_half(encoded)
  assert_true(tail.length() == 12)
  let decoded = fountain.decode(tail)
  match decoded {
    Some(result) => assert_true(frob_eq(result, data))
    None => assert_true(false)
  }
}

// ===== 50% 丢包恢复 =====

///|
test "robust: 50 percent loss drop every other block" {
  // K=10，编码 30 块，丢弃一半（取偶数索引 15 块），仍能解码。
  let fountain = @qr.LTFountain::new(10, 10)
  let data = frob_make_data(100)
  let encoded = fountain.encode_all(data, 30)
  let subset = Array::make(0, (0, FixedArray::make(0, 0)))
  for i = 0; i < 30; i = i + 1 {
    if i % 2 == 0 {
      subset.push(encoded[i])
    }
  }
  assert_true(subset.length() == 15)
  let decoded = fountain.decode(subset)
  match decoded {
    Some(result) => assert_true(frob_eq(result, data))
    None => assert_true(false)
  }
}

///|
test "robust: 50 percent loss keep second half" {
  // K=8，编码 24 块，保留后 12 块（50% 丢包），仍能解码。
  let fountain = @qr.LTFountain::new(10, 8)
  let data = frob_make_data(80)
  let encoded = fountain.encode_all(data, 24)
  let subset = Array::make(0, (0, FixedArray::make(0, 0)))
  for i = 12; i < 24; i = i + 1 {
    subset.push(encoded[i])
  }
  assert_true(subset.length() == 12)
  let decoded = fountain.decode(subset)
  match decoded {
    Some(result) => assert_true(frob_eq(result, data))
    None => assert_true(false)
  }
}

// ===== 重复块处理 =====

///|
test "robust: duplicate blocks appended still decode" {
  // K=4，编码 8 块（已知可解码），追加第 0 块重复 4 次，仍能解码。
  let fountain = @qr.LTFountain::new(10, 4)
  let data = frob_make_data(40)
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
    Some(result) => assert_true(frob_eq(result, data))
    None => assert_true(false)
  }
}

///|
test "robust: all blocks duplicated still decode" {
  // K=5，编码 15 块，每块重复一次得到 30 块，仍能解码。
  let fountain = @qr.LTFountain::new(10, 5)
  let data = frob_make_data(50)
  let encoded = fountain.encode_all(data, 15)
  let dup = Array::make(0, (0, FixedArray::make(0, 0)))
  for i = 0; i < 15; i = i + 1 {
    dup.push(encoded[i])
    dup.push(encoded[i])
  }
  assert_true(dup.length() == 30)
  let decoded = fountain.decode(dup)
  match decoded {
    Some(result) => assert_true(frob_eq(result, data))
    None => assert_true(false)
  }
}

// ===== 恰好 N 块 / 不足 N 块 =====

///|
test "robust: exactly N blocks no redundancy K=2" {
  // K=2，恰好 2 块解码（无冗余）。
  let fountain = @qr.LTFountain::new(10, 2)
  let data = frob_make_data(20)
  let encoded = fountain.encode_all(data, 2)
  assert_true(encoded.length() == 2)
  let decoded = fountain.decode(encoded)
  match decoded {
    Some(result) => assert_true(frob_eq(result, data))
    None => assert_true(false)
  }
}

///|
test "robust: exactly N blocks K=1 trivial" {
  // K=1，恰好 1 块（trivial fountain）。
  let fountain = @qr.LTFountain::new(10, 1)
  let data = frob_make_data(10)
  let encoded = fountain.encode_all(data, 1)
  let decoded = fountain.decode(encoded)
  match decoded {
    Some(result) => assert_true(frob_eq(result, data))
    None => assert_true(false)
  }
}

///|
test "robust: N minus 1 blocks returns None" {
  // K=10，给 9 块（< K），decode 返回 None。
  let fountain = @qr.LTFountain::new(10, 10)
  let data = frob_make_data(100)
  let encoded = fountain.encode_all(data, 9)
  let result = fountain.decode(encoded)
  assert_true(result is None)
}

///|
test "robust: N minus 1 blocks K=5 returns None" {
  // K=5，给 4 块（< K），decode 返回 None。
  let fountain = @qr.LTFountain::new(10, 5)
  let data = frob_make_data(50)
  let encoded = fountain.encode_all(data, 4)
  let result = fountain.decode(encoded)
  assert_true(result is None)
}

// ===== 不同 num_blocks =====

///|
test "robust: various num blocks 1 2 5 10 20 50" {
  // num_blocks = 1/2/5/10/20/50，均用充足 overhead 保证解码成功。
  let nbs = [1, 2, 5, 10, 20, 50]
  for i = 0; i < nbs.length(); i = i + 1 {
    let nb = nbs[i]
    let overhead = if nb >= 20 { nb } else { 20 }
    assert_true(frob_roundtrip(8, nb, nb + overhead))
  }
}

// ===== 不同 block_size =====

///|
test "robust: various block sizes 1 10 100 500" {
  // block_size = 1/10/100/500，K=4，充足 overhead，均能解码。
  let bss = [1, 10, 100, 500]
  for i = 0; i < bss.length(); i = i + 1 {
    let bs = bss[i]
    assert_true(frob_roundtrip(bs, 4, 16))
  }
}

// ===== 种子可重复性 =====

///|
test "robust: same seed produces same encoded block" {
  // 同 seed 产生完全相同的编码块（确定性）。
  let fountain = @qr.LTFountain::new(10, 8)
  let data = frob_make_data(80)
  let blocks = fountain.split(data)
  let enc1 = fountain.encode_block(blocks, 42)
  let enc2 = fountain.encode_block(blocks, 42)
  assert_true(frob_eq(enc1, enc2))
}

///|
test "robust: same seed produces same select_blocks sequence" {
  // 同 seed + 同 degree 产生完全相同的索引序列。
  let fountain = @qr.LTFountain::new(10, 10)
  let s1 = fountain.select_blocks(99, 5)
  let s2 = fountain.select_blocks(99, 5)
  assert_true(s1.length() == s2.length())
  for i = 0; i < s1.length(); i = i + 1 {
    assert_true(s1[i] == s2[i])
  }
}

// ===== 编码块独立性 =====

///|
test "robust: different seeds produce different encoded blocks" {
  // 不同 seed 产生不同编码块（独立性）。
  // seed=1 → degree=2，seed=2 → degree=1，编码块必然不同。
  let fountain = @qr.LTFountain::new(10, 10)
  let data = frob_make_data(100)
  let blocks = fountain.split(data)
  let enc1 = fountain.encode_block(blocks, 1)
  let enc2 = fountain.encode_block(blocks, 2)
  assert_true(!frob_eq(enc1, enc2))
}

///|
test "robust: different seeds produce different select_blocks" {
  // 不同 seed 产生不同的 select_blocks 索引序列。
  let fountain = @qr.LTFountain::new(10, 10)
  let s1 = fountain.select_blocks(1, 5)
  let s2 = fountain.select_blocks(2, 5)
  let mut diff = false
  if s1.length() != s2.length() {
    diff = true
  } else {
    for i = 0; i < s1.length(); i = i + 1 {
      if s1[i] != s2[i] {
        diff = true
        break
      }
    }
  }
  assert_true(diff)
}

// ===== 解码后数据与原始一致 =====

///|
test "robust: decoded data equals original multiple scenarios" {
  // 多个场景验证解码后数据与原始完全一致。
  let cases = [(10, 4, 12), (10, 8, 20), (8, 10, 24), (100, 5, 15), (50, 4, 12)]
  for i = 0; i < cases.length(); i = i + 1 {
    let (bs, nb, ne) = cases[i]
    assert_true(frob_roundtrip(bs, nb, ne))
  }
}

///|
test "robust: decoded data equals original with patterned data" {
  // 用强模式数据（0xAA/0x55 交替）验证解码一致性。
  let fountain = @qr.LTFountain::new(10, 6)
  let data = FixedArray::make(60, 0)
  for i = 0; i < 60; i = i + 1 {
    data[i] = if i % 2 == 0 { 0xAA } else { 0x55 }
  }
  let encoded = fountain.encode_all(data, 18)
  let decoded = fountain.decode(encoded)
  match decoded {
    Some(result) => assert_true(frob_eq(result, data))
    None => assert_true(false)
  }
}

// ===== 极端丢包 / 大 K 高丢包率 =====

///|
test "robust: extreme loss only K blocks from 4K encoded" {
  // K=5，编码 20 块（4K），只用后 10 块（seed 11-20，K+5 overhead）解码。
  let fountain = @qr.LTFountain::new(10, 5)
  let data = frob_make_data(50)
  let encoded = fountain.encode_all(data, 20)
  let subset = Array::make(0, (0, FixedArray::make(0, 0)))
  for i = 10; i < 20; i = i + 1 {
    subset.push(encoded[i])
  }
  assert_true(subset.length() == 10)
  let decoded = fountain.decode(subset)
  match decoded {
    Some(result) => assert_true(frob_eq(result, data))
    None => assert_true(false)
  }
}

///|
test "robust: large K high loss rate K=20 use last 30 of 60" {
  // K=20，编码 60 块（3K），仅用后 30 块（seed 31-60，K+10 overhead）解码。
  let fountain = @qr.LTFountain::new(8, 20)
  let data = frob_make_data(160)
  let encoded = fountain.encode_all(data, 60)
  let tail = frob_take_last_half(encoded)
  assert_true(tail.length() == 30)
  let decoded = fountain.decode(tail)
  match decoded {
    Some(result) => assert_true(frob_eq(result, data))
    None => assert_true(false)
  }
}
