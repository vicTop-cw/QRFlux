///|
test "frame header serialize/parse" {
  let header = @qr.FrameHeader::make(10, 3, 100, 0x1234)
  let bytes = header.to_bytes()
  let parsed = @qr.FrameHeader::from_bytes(bytes)
  match parsed {
    Some(h) => {
      assert_true(h.total_frames == 10)
      assert_true(h.current_frame == 3)
      assert_true(h.data_length == 100)
      assert_true(h.checksum == 0x1234)
    }
    None => abort("parse failed")
  }
}

///|
test "frame header invalid magic" {
  let bytes = FixedArray::make(16, 0)
  bytes[0] = 0x58 // Wrong magic (0x58 = 'X')
  let parsed = @qr.FrameHeader::from_bytes(bytes)
  assert_true(parsed is None)
}

///|
test "crc16 basic" {
  let data = FixedArray::make(4, 0)
  data[0] = 0x01
  data[1] = 0x02
  data[2] = 0x03
  data[3] = 0x04
  let crc = @qr.crc16(data)
  assert_true(crc >= 0 && crc <= 0xFFFF)
}

///|
test "split and reassemble" {
  let data = FixedArray::make(100, 0x42)
  let frames = @qr.split_into_frames(data, 32)
  assert_true(frames.length() > 0)

  match @qr.reassemble_frames(frames) {
    Some(result) => {
      assert_true(result.length() == 100)
      // Verify content
      for i = 0; i < 100; i = i + 1 {
        assert_true(result[i] == 0x42)
      }
    }
    None => abort("reassemble failed")
  }
}

///|
test "split and reassemble large" {
  let data = FixedArray::make(500, 0x99)
  let frames = @qr.split_into_frames(data, 32)
  assert_true(frames.length() > 0)

  match @qr.reassemble_frames(frames) {
    Some(result) => {
      assert_true(result.length() == 500)
      // Verify content
      for i = 0; i < 500; i = i + 1 {
        assert_true(result[i] == 0x99)
      }
    }
    None => abort("reassemble failed")
  }
}

///|
test "reassemble missing frame" {
  let data = FixedArray::make(100, 0x42)
  let frames = @qr.split_into_frames(data, 32)

  // Remove a frame
  let frames_copy = Array(capacity=frames.length())
  for i = 0; i < frames.length(); i = i + 1 {
    if i != 2 {
      frames_copy.push(frames[i])
    }
  }

  let reassembled = @qr.reassemble_frames(frames_copy)
  assert_true(reassembled is None)
}

///|
test "reassemble wrong order" {
  let data = FixedArray::make(100, 0x42)
  let frames = @qr.split_into_frames(data, 32)

  // Swap frames
  let temp = frames[0]
  frames[0] = frames[1]
  frames[1] = temp

  let reassembled = @qr.reassemble_frames(frames)
  assert_true(reassembled is None)
}

///|
test "reassemble corrupted checksum" {
  let data = FixedArray::make(100, 0x42)
  let frames = @qr.split_into_frames(data, 32)

  // Corrupt a payload byte
  frames[0][20] = 0x00

  let reassembled = @qr.reassemble_frames(frames)
  assert_true(reassembled is None)
}
