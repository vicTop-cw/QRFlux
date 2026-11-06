// 动态码流帧大小边界测试。
// 专门针对 split_into_frames / reassemble_frames 在各种 frame_size 边界下的行为，
// 覆盖极端分片、单帧、两帧、常规帧、超大数据帧、空数据、单字节、往返、
// 乱序重组、CRC16 校验以及跨 ECC level 容量的分片场景。

///|
/// 构造长度为 n 的可识别模式数据（与已有辅助函数名隔离，前缀 fsf_）。
fn fsf_make_data(n : Int32) -> FixedArray[Int32] {
  let data = FixedArray::make(n, 0)
  for i = 0; i < n; i = i + 1 {
    data[i] = (i * 11 + 7) & 0xFF
  }
  data
}

///|
/// 逐字节比较两个 FixedArray[Int32] 是否完全相同。
fn fsf_eq(a : FixedArray[Int32], b : FixedArray[Int32]) -> Bool {
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
/// 往返校验：用给定 frame_size 分片再重组，结果必须与原始数据一致。
fn fsf_roundtrip(
  data : FixedArray[Int32],
  frame_size : Int32,
  label : String,
) -> Unit {
  let frames = @qr.split_into_frames(data, frame_size)
  match @qr.reassemble_frames(frames) {
    Some(result) =>
      if !fsf_eq(result, data) {
        abort("framesize \{label}: 重组数据不匹配")
      }
    None => abort("framesize \{label}: 重组返回 None")
  }
}

///|
test "framesize boundary: frame_size 1 极端分片" {
  // frame_size=1：每个字节一帧，最极端的分片情形。
  let data = fsf_make_data(30)
  let frames = @qr.split_into_frames(data, 1)
  assert_true(frames.length() == 30)
  // 每帧应为 header(16) + 1 字节 payload = 17 字节。
  for i = 0; i < 30; i = i + 1 {
    assert_true(frames[i].length() == 17)
  }
  fsf_roundtrip(data, 1, "frame_size 1")
}

///|
test "framesize boundary: frame_size 等于数据长度单帧" {
  // frame_size == data.length() => 恰好一帧。
  let n = 64
  let data = fsf_make_data(n)
  let frames = @qr.split_into_frames(data, n)
  assert_true(frames.length() == 1)
  assert_true(frames[0].length() == 16 + n)
  fsf_roundtrip(data, n, "frame_size 等于数据长度")
}

///|
test "framesize boundary: frame_size 数据长度减 1 两帧" {
  // frame_size = data.length() - 1 => 两帧，第二帧仅 1 字节。
  let n = 50
  let data = fsf_make_data(n)
  let frames = @qr.split_into_frames(data, n - 1)
  assert_true(frames.length() == 2)
  // 第一帧满载：16 + (n-1)；第二帧仅 1 字节 payload：16 + 1。
  assert_true(frames[0].length() == 16 + (n - 1))
  assert_true(frames[1].length() == 16 + 1)
  fsf_roundtrip(data, n - 1, "frame_size 数据长度减 1")
}

///|
test "framesize boundary: frame_size 2 小帧" {
  // frame_size=2：小型帧，验证偶数与奇数数据长度两种情形。
  let even_data = fsf_make_data(40)
  let frames_even = @qr.split_into_frames(even_data, 2)
  assert_true(frames_even.length() == 20)
  fsf_roundtrip(even_data, 2, "frame_size 2 偶数")
  let odd_data = fsf_make_data(41)
  let frames_odd = @qr.split_into_frames(odd_data, 2)
  assert_true(frames_odd.length() == 21)
  // 最后一帧仅 1 字节 payload。
  assert_true(frames_odd[20].length() == 16 + 1)
  fsf_roundtrip(odd_data, 2, "frame_size 2 奇数")
}

///|
test "framesize boundary: frame_size 100 常规帧" {
  // frame_size=100：常规帧大小，覆盖整除与非整除两种情况。
  let data_exact = fsf_make_data(300)
  let frames_exact = @qr.split_into_frames(data_exact, 100)
  assert_true(frames_exact.length() == 3)
  fsf_roundtrip(data_exact, 100, "frame_size 100 整除")
  let data_partial = fsf_make_data(250)
  let frames_partial = @qr.split_into_frames(data_partial, 100)
  assert_true(frames_partial.length() == 3)
  // 最后一帧 50 字节 payload。
  assert_true(frames_partial[2].length() == 16 + 50)
  fsf_roundtrip(data_partial, 100, "frame_size 100 非整除")
}

///|
test "framesize boundary: frame_size 500 常规帧" {
  // frame_size=500：中等偏大帧，验证跨帧边界的数据完整性。
  let data = fsf_make_data(1200)
  let frames = @qr.split_into_frames(data, 500)
  assert_true(frames.length() == 3)
  // 前两帧满载 500，最后一帧 200。
  assert_true(frames[0].length() == 16 + 500)
  assert_true(frames[1].length() == 16 + 500)
  assert_true(frames[2].length() == 16 + 200)
  fsf_roundtrip(data, 500, "frame_size 500")
}

///|
test "framesize boundary: frame_size 1000 常规帧" {
  // frame_size=1000：大帧，少量分片。
  let data = fsf_make_data(2500)
  let frames = @qr.split_into_frames(data, 1000)
  assert_true(frames.length() == 3)
  assert_true(frames[2].length() == 16 + 500)
  fsf_roundtrip(data, 1000, "frame_size 1000")
}

///|
test "framesize boundary: frame_size 超过数据长度单帧" {
  // frame_size > data.length() => 仍为单帧，不越界分配。
  let data = fsf_make_data(30)
  let frames = @qr.split_into_frames(data, 5000)
  assert_true(frames.length() == 1)
  // 单帧 = header(16) + 30 payload。
  assert_true(frames[0].length() == 16 + 30)
  fsf_roundtrip(data, 5000, "frame_size 超过数据长度")
}

///|
test "framesize boundary: 空数据分片" {
  // 空数据：当前实现返回 0 帧，重组空帧列表返回 None。锁定该行为。
  let data = FixedArray::make(0, 0)
  let frames = @qr.split_into_frames(data, 32)
  assert_true(frames.length() == 0)
  let result = @qr.reassemble_frames(frames)
  assert_true(result is None)
}

///|
test "framesize boundary: 单字节数据分片" {
  // 单字节数据：最小非空 payload，任意 frame_size >= 1 均为单帧。
  let data = FixedArray::make(1, 0x5A)
  for fs in [1, 2, 16, 32, 100, 1000] {
    let frames = @qr.split_into_frames(data, fs)
    assert_true(frames.length() == 1)
    assert_true(frames[0].length() == 17)
    match @qr.reassemble_frames(frames) {
      Some(result) => {
        assert_true(result.length() == 1)
        assert_true(result[0] == 0x5A)
      }
      None => abort("单字节 frame_size=\{fs} 重组失败")
    }
  }
}

///|
test "framesize boundary: split reassemble 往返多种帧大小" {
  // 对同一数据用多种 frame_size 往返，验证重组一致性。
  let data = fsf_make_data(200)
  for fs in [1, 2, 3, 7, 16, 25, 32, 50, 100, 199, 200, 201, 500] {
    let frames = @qr.split_into_frames(data, fs)
    let expected = (200 + fs - 1) / fs
    assert_true(frames.length() == expected)
    match @qr.reassemble_frames(frames) {
      Some(result) => assert_true(fsf_eq(result, data))
      None => abort("往返 frame_size=\{fs} 重组失败")
    }
  }
}

///|
test "framesize boundary: 乱序重组仍能还原" {
  // 帧顺序打乱后重组，结果必须与原始数据一致。
  let data = fsf_make_data(150)
  let frames = @qr.split_into_frames(data, 20) // 8 帧
  assert_true(frames.length() == 8)
  // 用奇偶交换构造打乱顺序：[1,0,3,2,5,4,7,6]
  let shuffled : Array[FixedArray[Int32]] = Array::make(
    0,
    FixedArray::make(0, 0),
  )
  for i = 0; i < 8; i = i + 1 {
    let idx = if i % 2 == 0 { i + 1 } else { i - 1 }
    shuffled.push(frames[idx])
  }
  match @qr.reassemble_frames(shuffled) {
    Some(result) => assert_true(fsf_eq(result, data))
    None => abort("乱序重组失败")
  }
}

///|
test "framesize boundary: CRC16 帧头校验正确" {
  // 每帧 header 中的 checksum 字段必须等于整段数据的 crc16。
  let data = fsf_make_data(80)
  let frames = @qr.split_into_frames(data, 25) // 4 帧
  assert_true(frames.length() == 4)
  let expected_crc = @qr.crc16(data)
  for i = 0; i < 4; i = i + 1 {
    match @qr.FrameHeader::from_bytes(frames[i]) {
      Some(h) => assert_true(h.checksum == expected_crc)
      None => abort("帧 \{i} header 解析失败")
    }
  }
  // 重组必须成功（CRC 一致）。
  fsf_roundtrip(data, 25, "CRC16 帧头正确")
}

///|
test "framesize boundary: CRC16 检测 payload 损坏" {
  // 翻转 payload 中一字节，CRC16 必须失配，重组返回 None。
  let data = fsf_make_data(60)
  let frames = @qr.split_into_frames(data, 20) // 3 帧
  assert_true(frames.length() == 3)
  // 翻转第 1 帧 payload 区（offset 16 之后）的 bit 0。
  frames[1][20] = frames[1][20] ^ 0x01
  let result = @qr.reassemble_frames(frames)
  assert_true(result is None)
}

///|
test "framesize boundary: CRC16 检测 header checksum 篡改" {
  // 直接篡改 header 中的 checksum 字段，重组必须返回 None。
  let data = fsf_make_data(50)
  let frames = @qr.split_into_frames(data, 25) // 2 帧
  assert_true(frames.length() == 2)
  // checksum 高字节在 offset 13。改成与原值不同的值。
  let orig = frames[0][13]
  frames[0][13] = (orig + 1) & 0xFF
  let result = @qr.reassemble_frames(frames)
  assert_true(result is None)
}

///|
test "framesize boundary: 跨 ECC level 容量分片往返" {
  // 不同 ECC level (L/M/Q/H) 对应不同单张 QR 容量。用代表性容量作为
  // 数据长度，验证分片-重组往返在每种 ECC level 容量边界下均正确。
  // V20 近似容量：L~537 / M~384 / Q~279 / H~78（字节）。
  let ecc_capacities = [78, 279, 384, 537]
  for cap in ecc_capacities {
    // 数据长度刚好等于该 ECC level 容量。
    let data = fsf_make_data(cap)
    // 用一个典型帧大小（如 64）分片。
    let frames = @qr.split_into_frames(data, 64)
    let expected = (cap + 64 - 1) / 64
    assert_true(frames.length() == expected)
    match @qr.reassemble_frames(frames) {
      Some(result) => assert_true(fsf_eq(result, data))
      None => abort("ECC 容量=\{cap} 重组失败")
    }
    // 同时验证 frame_size=1 的极端分片在每种容量下也可往返。
    let frames_one = @qr.split_into_frames(data, 1)
    assert_true(frames_one.length() == cap)
    match @qr.reassemble_frames(frames_one) {
      Some(result) => assert_true(fsf_eq(result, data))
      None => abort("ECC 容量=\{cap} frame_size=1 重组失败")
    }
  }
}

///|
test "framesize boundary: 帧大小 1 与帧大小 N 重组结果一致" {
  // 同一数据用 frame_size=1 和 frame_size=N 分片，重组结果必须相同。
  let data = fsf_make_data(45)
  let frames_one = @qr.split_into_frames(data, 1)
  let frames_n = @qr.split_into_frames(data, 15)
  let r1 = @qr.reassemble_frames(frames_one)
  let r2 = @qr.reassemble_frames(frames_n)
  match (r1, r2) {
    (Some(a), Some(b)) => assert_true(fsf_eq(a, b))
    (None, _) => abort("frame_size=1 重组失败")
    (_, None) => abort("frame_size=15 重组失败")
  }
}
