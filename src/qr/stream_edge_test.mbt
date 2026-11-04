// 分片协议边界测试。
// 验证 split_into_frames / reassemble_frames 在各种边界条件下的正确性。

///|
/// 辅助函数：构造测试数据（带可识别模式）。
fn make_pattern_data(total_len : Int32) -> FixedArray[Int32] {
  let data = FixedArray::make(total_len, 0)
  for i = 0; i < total_len; i = i + 1 {
    data[i] = (i * 7 + 13) & 0xFF
  }
  data
}

///|
/// 辅助函数：比对两个 FixedArray 是否完全相同。
fn arrays_eq(a : FixedArray[Int32], b : FixedArray[Int32]) -> Bool {
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
test "stream edge: single frame exact fit" {
  // 数据刚好放入一帧（不需要分片）
  let max_payload = 32
  let data = make_pattern_data(32) // 刚好 32 字节
  let frames = @qr.split_into_frames(data, max_payload)
  assert_true(frames.length() == 1)
  match @qr.reassemble_frames(frames) {
    Some(result) => assert_true(arrays_eq(result, data))
    None => abort("reassemble failed")
  }
}

///|
test "stream edge: two frames boundary" {
  // 数据刚好超过一帧容量，需要两帧
  let max_payload = 32
  let data = make_pattern_data(33) // 32 + 1
  let frames = @qr.split_into_frames(data, max_payload)
  assert_true(frames.length() == 2)
  match @qr.reassemble_frames(frames) {
    Some(result) => assert_true(arrays_eq(result, data))
    None => abort("reassemble failed")
  }
}

///|
test "stream edge: exact multiple of frame capacity" {
  // 数据长度刚好是帧容量的整数倍
  let max_payload = 32
  let data = make_pattern_data(96) // 32 * 3
  let frames = @qr.split_into_frames(data, max_payload)
  assert_true(frames.length() == 3)
  match @qr.reassemble_frames(frames) {
    Some(result) => assert_true(arrays_eq(result, data))
    None => abort("reassemble failed")
  }
}

///|
test "stream edge: multiple plus one byte" {
  // 数据长度 = 帧容量 × N + 1
  let max_payload = 32
  let data = make_pattern_data(97) // 32 * 3 + 1
  let frames = @qr.split_into_frames(data, max_payload)
  assert_true(frames.length() == 4)
  match @qr.reassemble_frames(frames) {
    Some(result) => assert_true(arrays_eq(result, data))
    None => abort("reassemble failed")
  }
}

///|
test "stream edge: empty data" {
  // 0 字节数据
  // 注意：split_into_frames 对空数据返回空数组（潜在 bug）
  let max_payload = 32
  let data = FixedArray::make(0, 0)
  let frames = @qr.split_into_frames(data, max_payload)
  // 当前实现：total_frames = (0 + 32 - 1) / 32 = 0，返回空数组
  assert_true(frames.length() == 0)
  // reassemble_frames 对空数组返回 None
  let result = @qr.reassemble_frames(frames)
  assert_true(result is None)
}

///|
test "stream edge: one byte data" {
  // 1 字节数据（最小非空数据）
  let max_payload = 32
  let data = FixedArray::make(1, 0x42)
  let frames = @qr.split_into_frames(data, max_payload)
  assert_true(frames.length() == 1)
  match @qr.reassemble_frames(frames) {
    Some(result) => {
      assert_true(result.length() == 1)
      assert_true(result[0] == 0x42)
    }
    None => abort("reassemble failed for 1 byte")
  }
}

///|
test "stream edge: max payload equals data length" {
  // max_payload 刚好等于数据长度
  let data = make_pattern_data(50)
  let frames = @qr.split_into_frames(data, 50)
  assert_true(frames.length() == 1)
  match @qr.reassemble_frames(frames) {
    Some(result) => assert_true(arrays_eq(result, data))
    None => abort("reassemble failed")
  }
}

///|
test "stream edge: max payload larger than data" {
  // max_payload 大于数据长度
  let data = make_pattern_data(20)
  let frames = @qr.split_into_frames(data, 100)
  assert_true(frames.length() == 1)
  match @qr.reassemble_frames(frames) {
    Some(result) => assert_true(arrays_eq(result, data))
    None => abort("reassemble failed")
  }
}

///|
test "stream edge: many frames" {
  // 大量数据，很多帧
  let max_payload = 16
  let data = make_pattern_data(1000) // 1000 / 16 = 62.5 → 63 帧
  let frames = @qr.split_into_frames(data, max_payload)
  assert_true(frames.length() == 63)
  match @qr.reassemble_frames(frames) {
    Some(result) => assert_true(arrays_eq(result, data))
    None => abort("reassemble failed")
  }
}

///|
test "stream edge: frame header correctness" {
  // 验证 FrameHeader 的序列化/反序列化
  let header = @qr.FrameHeader::make(100, 50, 4000, 0xABCD)
  let bytes = header.to_bytes()
  assert_true(bytes.length() == 16)
  match @qr.FrameHeader::from_bytes(bytes) {
    Some(h) => {
      assert_true(h.total_frames == 100)
      assert_true(h.current_frame == 50)
      assert_true(h.data_length == 4000)
      assert_true(h.checksum == 0xABCD)
      assert_true(h.version == 1)
    }
    None => abort("parse failed")
  }
}

///|
test "stream edge: frame header max values" {
  // FrameHeader 边界值（2 字节字段最大值 65535）
  let header = @qr.FrameHeader::make(65535, 65534, 100000, 0xFFFF)
  let bytes = header.to_bytes()
  match @qr.FrameHeader::from_bytes(bytes) {
    Some(h) => {
      assert_true(h.total_frames == 65535)
      assert_true(h.current_frame == 65534)
      assert_true(h.checksum == 0xFFFF)
    }
    None => abort("parse failed for max values")
  }
}

///|
test "stream edge: frame header zero values" {
  // FrameHeader 零值
  let header = @qr.FrameHeader::make(1, 0, 0, 0)
  let bytes = header.to_bytes()
  match @qr.FrameHeader::from_bytes(bytes) {
    Some(h) => {
      assert_true(h.total_frames == 1)
      assert_true(h.current_frame == 0)
      assert_true(h.data_length == 0)
      assert_true(h.checksum == 0)
    }
    None => abort("parse failed for zero values")
  }
}

///|
test "stream edge: frame header short input" {
  // from_bytes 输入不足 16 字节
  let bytes = FixedArray::make(10, 0)
  let result = @qr.FrameHeader::from_bytes(bytes)
  assert_true(result is None)
}

///|
test "stream edge: cross frame reassembly" {
  // 跨帧重组：分片后重组，验证还原
  let max_payload = 20
  let data = make_pattern_data(105) // 105 / 20 = 5.25 → 6 帧
  let frames = @qr.split_into_frames(data, max_payload)
  assert_true(frames.length() == 6)
  match @qr.reassemble_frames(frames) {
    Some(result) => {
      assert_true(result.length() == 105)
      assert_true(arrays_eq(result, data))
    }
    None => abort("reassemble failed")
  }
}

///|
test "stream edge: each frame has correct header" {
  // 验证每帧的 header 字段正确
  let max_payload = 32
  let data = make_pattern_data(100) // 4 帧
  let frames = @qr.split_into_frames(data, max_payload)
  assert_true(frames.length() == 4)
  let expected_checksum = @qr.crc16(data)
  for i = 0; i < 4; i = i + 1 {
    let frame = frames[i]
    match @qr.FrameHeader::from_bytes(frame) {
      Some(h) => {
        assert_true(h.total_frames == 4)
        assert_true(h.current_frame == i)
        assert_true(h.data_length == 100)
        assert_true(h.checksum == expected_checksum)
        assert_true(h.version == 1)
      }
      None => abort("frame " + i.to_string() + " header parse failed")
    }
  }
}

///|
test "stream edge: frame payload sizes" {
  // 验证每帧的 payload 大小正确
  let max_payload = 32
  let data = make_pattern_data(80) // 80 / 32 = 2.5 → 3 帧
  let frames = @qr.split_into_frames(data, max_payload)
  assert_true(frames.length() == 3)
  // 前 2 帧应该是 16 + 32 = 48 字节
  assert_true(frames[0].length() == 48)
  assert_true(frames[1].length() == 48)
  // 第 3 帧应该是 16 + 16 = 32 字节（80 - 64 = 16）
  assert_true(frames[2].length() == 32)
}

///|
test "stream edge: reassemble empty frames array" {
  // reassemble_frames 对空数组返回 None
  let frames = Array::make(0, FixedArray::make(0, 0))
  let result = @qr.reassemble_frames(frames)
  assert_true(result is None)
}

///|
test "stream edge: reassemble with corrupted magic" {
  // 损坏 magic 字节
  let data = make_pattern_data(50)
  let frames = @qr.split_into_frames(data, 32)
  frames[0][0] = 0x00 // 损坏 magic
  let result = @qr.reassemble_frames(frames)
  assert_true(result is None)
}

///|
test "stream edge: reassemble with wrong frame count" {
  // 帧数不匹配
  let data = make_pattern_data(100)
  let frames = @qr.split_into_frames(data, 32)
  // 修改 header 中的 total_frames
  let frame = frames[0]
  frame[5] = 0 // total_frames 高字节
  frame[6] = 99 // total_frames 低字节 = 99（实际 4）
  let result = @qr.reassemble_frames(frames)
  assert_true(result is None)
}

///|
test "stream edge: crc16 empty data" {
  // CRC16 对空数据
  let data = FixedArray::make(0, 0)
  let crc = @qr.crc16(data)
  assert_true(crc == 0)
}

///|
test "stream edge: crc16 single byte" {
  // CRC16 单字节
  let data = FixedArray::make(1, 0)
  data[0] = 0x00
  let crc = @qr.crc16(data)
  assert_true(crc >= 0 && crc <= 0xFFFF)
}

///|
test "stream edge: crc16 deterministic" {
  // CRC16 确定性：相同数据相同 CRC
  let data1 = make_pattern_data(50)
  let data2 = make_pattern_data(50)
  let crc1 = @qr.crc16(data1)
  let crc2 = @qr.crc16(data2)
  assert_true(crc1 == crc2)
}

///|
test "stream edge: round trip various sizes" {
  // 多种大小的往返测试
  let max_payload = 25
  let sizes = [1, 2, 24, 25, 26, 50, 75, 100, 250]
  for size in sizes {
    let data = make_pattern_data(size)
    let frames = @qr.split_into_frames(data, max_payload)
    let expected_frames = (size + max_payload - 1) / max_payload
    assert_true(frames.length() == expected_frames)
    match @qr.reassemble_frames(frames) {
      Some(result) => assert_true(arrays_eq(result, data))
      None => abort("reassemble failed for size=" + size.to_string())
    }
  }
}

///|
test "stream edge: payload max payload 1" {
  // max_payload = 1，每个字节一帧
  let data = make_pattern_data(10)
  let frames = @qr.split_into_frames(data, 1)
  assert_true(frames.length() == 10)
  match @qr.reassemble_frames(frames) {
    Some(result) => assert_true(arrays_eq(result, data))
    None => abort("reassemble failed for max_payload=1")
  }
}
