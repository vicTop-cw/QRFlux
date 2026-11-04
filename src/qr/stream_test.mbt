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
/// Regression: reassemble_frames must tolerate out-of-order frames.
/// Previously it required frames in strict current_frame order and returned
/// None on any permutation. After the fix, it sorts by current_frame and
/// reassembles correctly.
test "reassemble wrong order" {
  let data = FixedArray::make(100, 0x42)
  let frames = @qr.split_into_frames(data, 32)

  // Swap frames 0 and 1.
  let temp = frames[0]
  frames[0] = frames[1]
  frames[1] = temp

  match @qr.reassemble_frames(frames) {
    Some(result) => {
      assert_true(result.length() == 100)
      for i = 0; i < 100; i = i + 1 {
        assert_true(result[i] == 0x42)
      }
    }
    None => abort("reassemble should succeed for out-of-order frames")
  }
}

///|
/// Regression: reassemble_frames handles a full permutation (reverse order).
test "reassemble reverse order" {
  let data = FixedArray::make(200, 0x77)
  let frames = @qr.split_into_frames(data, 30)
  let n = frames.length()
  // Reverse the frame array.
  let reversed : Array[FixedArray[Int32]] = Array::make(
    0,
    FixedArray::make(0, 0),
  )
  for i = n - 1; i >= 0; i = i - 1 {
    reversed.push(frames[i])
  }
  match @qr.reassemble_frames(reversed) {
    Some(result) => {
      assert_true(result.length() == 200)
      for i = 0; i < 200; i = i + 1 {
        assert_true(result[i] == 0x77)
      }
    }
    None => abort("reassemble should succeed for reversed frames")
  }
}

///|
/// Regression: reassemble_frames handles a random permutation.
test "reassemble shuffled order" {
  // Build data with distinct bytes so order matters.
  let n = 150
  let data = FixedArray::make(n, 0)
  for i = 0; i < n; i = i + 1 {
    data[i] = (i * 7 + 3) & 0xFF
  }
  let frames = @qr.split_into_frames(data, 25)
  let nf = frames.length()
  // Shuffle with a simple deterministic permutation: rotate by 1.
  let shuffled : Array[FixedArray[Int32]] = Array::make(
    0,
    FixedArray::make(0, 0),
  )
  for i = 0; i < nf; i = i + 1 {
    shuffled.push(frames[(i + 1) % nf])
  }
  match @qr.reassemble_frames(shuffled) {
    Some(result) => {
      assert_true(result.length() == n)
      for i = 0; i < n; i = i + 1 {
        assert_true(result[i] == data[i])
      }
    }
    None => abort("reassemble should succeed for shuffled frames")
  }
}

///|
/// Negative: reassemble_frames still rejects duplicate frame indices
/// (which would leave a gap in the expected 0..total-1 sequence).
test "reassemble duplicate frame rejected" {
  let data = FixedArray::make(100, 0x42)
  let frames = @qr.split_into_frames(data, 32)
  // Replace frame[1] with a copy of frame[0] (duplicate current_frame=0).
  frames[1] = frames[0]
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
