// Stream protocol boundary tests.
// Focus on split_into_frames / reassemble_frames / crc16 / FrameHeader edge
// cases that complement stream_edge_test.mbt with explicit boundary naming
// and additional scenarios (1000+ frames, crc error detection, duplicate /
// partial reassembly, header corruption variants).

///|
/// Build deterministic test data of length n with a recognizable pattern.
fn sb_make_test_data(n : Int32) -> FixedArray[Int32] {
  let result = FixedArray::make(n, 0)
  for i = 0; i < n; i = i + 1 {
    result[i] = i % 256
  }
  result
}

///|
/// Element-wise equality check for two FixedArray[Int32]. Returns Bool so the
/// caller can wrap it with assert_true inside a test block.
fn sb_fixed_array_eq(a : FixedArray[Int32], b : FixedArray[Int32]) -> Bool {
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
/// Round-trip helper: split data with the given frame size, reassemble, and
/// verify the result equals the original. Aborts with a label on failure.
fn sb_roundtrip(
  data : FixedArray[Int32],
  frame_size : Int32,
  label : String,
) -> Unit {
  let frames = @qr.split_into_frames(data, frame_size)
  match @qr.reassemble_frames(frames) {
    Some(result) =>
      if !sb_fixed_array_eq(result, data) {
        abort("stream boundary \{label}: reassembled data mismatch")
      }
    None => abort("stream boundary \{label}: reassemble returned None")
  }
}

///|
test "stream boundary: frame_size 1" {
  // Smallest non-trivial frame size: one byte per frame.
  let data = sb_make_test_data(50)
  let frames = @qr.split_into_frames(data, 1)
  assert_true(frames.length() == 50)
  sb_roundtrip(data, 1, "frame_size 1")
}

///|
test "stream boundary: frame_size equals data length" {
  // frame_size == data.length() => exactly one frame.
  let data = sb_make_test_data(40)
  let frames = @qr.split_into_frames(data, 40)
  assert_true(frames.length() == 1)
  sb_roundtrip(data, 40, "frame_size equals data length")
}

///|
test "stream boundary: frame_size larger than data" {
  // frame_size > data.length() => still one frame (no over-allocation).
  let data = sb_make_test_data(20)
  let frames = @qr.split_into_frames(data, 100)
  assert_true(frames.length() == 1)
  // The single frame should be header(16) + 20 payload bytes.
  assert_true(frames[0].length() == 16 + 20)
  sb_roundtrip(data, 100, "frame_size larger than data")
}

///|
test "stream boundary: frame_size exact multiple" {
  // data.length() is an exact integer multiple of frame_size.
  let data = sb_make_test_data(90)
  let frames = @qr.split_into_frames(data, 30)
  assert_true(frames.length() == 3)
  // No remainder frame; every frame is full.
  for i = 0; i < 3; i = i + 1 {
    assert_true(frames[i].length() == 16 + 30)
  }
  sb_roundtrip(data, 30, "frame_size exact multiple")
}

///|
test "stream boundary: frame_size plus one" {
  // data.length() = frame_size * n + 1 => n+1 frames, last frame has 1 byte.
  let data = sb_make_test_data(91) // 30 * 3 + 1
  let frames = @qr.split_into_frames(data, 30)
  assert_true(frames.length() == 4)
  // Last frame carries a single payload byte.
  assert_true(frames[3].length() == 16 + 1)
  sb_roundtrip(data, 30, "frame_size plus one")
}

///|
test "stream boundary: single byte data" {
  // One byte of data: minimal non-empty payload.
  let data = FixedArray::make(1, 0x42)
  let frames = @qr.split_into_frames(data, 32)
  assert_true(frames.length() == 1)
  sb_roundtrip(data, 32, "single byte data")
}

///|
test "stream boundary: two bytes data" {
  // Two bytes of data: still fits in one frame.
  let data = FixedArray::make(2, 0)
  data[0] = 0xAB
  data[1] = 0xCD
  let frames = @qr.split_into_frames(data, 32)
  assert_true(frames.length() == 1)
  sb_roundtrip(data, 32, "two bytes data")
}

///|
test "stream boundary: empty data" {
  // Empty data: current implementation returns 0 frames and reassemble of an
  // empty frame list returns None. Document and lock this behavior.
  let data = FixedArray::make(0, 0)
  let frames = @qr.split_into_frames(data, 32)
  assert_true(frames.length() == 0)
  let result = @qr.reassemble_frames(frames)
  assert_true(result is None)
}

///|
test "stream boundary: large data 1000 frames" {
  // Stress: 1000+ frames to exercise the reassembly sort and concatenation.
  let frame_size = 1
  let data = sb_make_test_data(1000)
  let frames = @qr.split_into_frames(data, frame_size)
  assert_true(frames.length() == 1000)
  sb_roundtrip(data, frame_size, "large data 1000 frames")
}

///|
test "stream boundary: crc16 known values" {
  // crc16 of empty data is 0 (initial CRC state, no bytes processed).
  let empty = FixedArray::make(0, 0)
  assert_true(@qr.crc16(empty) == 0)
  // crc16 of a single zero byte is a fixed known value within 16-bit range.
  let one_zero = FixedArray::make(1, 0)
  let crc_one_zero = @qr.crc16(one_zero)
  assert_true(crc_one_zero >= 0 && crc_one_zero <= 0xFFFF)
  // Known pattern [0x01,0x02,0x03,0x04] must be deterministic across calls.
  let pattern = FixedArray::make(4, 0)
  pattern[0] = 0x01
  pattern[1] = 0x02
  pattern[2] = 0x03
  pattern[3] = 0x04
  let crc_a = @qr.crc16(pattern)
  let crc_b = @qr.crc16(pattern)
  assert_true(crc_a == crc_b)
  // A different pattern must (overwhelmingly likely) yield a different CRC.
  let pattern2 = FixedArray::make(4, 0)
  pattern2[0] = 0x01
  pattern2[1] = 0x02
  pattern2[2] = 0x03
  pattern2[3] = 0x05 // last byte differs
  let crc_c = @qr.crc16(pattern2)
  assert_true(crc_a != crc_c)
}

///|
test "stream boundary: crc16 detects errors" {
  // Flipping a single bit in the data must change the CRC (error detection).
  let data = sb_make_test_data(64)
  let crc_orig = @qr.crc16(data)
  // Flip bit 0 of byte 5.
  data[5] = data[5] ^ 0x01
  let crc_flip = @qr.crc16(data)
  assert_true(crc_flip != crc_orig)
  // Flip the same bit back; CRC must restore (determinism).
  data[5] = data[5] ^ 0x01
  let crc_restored = @qr.crc16(data)
  assert_true(crc_restored == crc_orig)
}

///|
test "stream boundary: frame header roundtrip" {
  // make -> to_bytes -> from_bytes preserves all fields, including large values.
  let header = @qr.FrameHeader::make(500, 250, 10000, 0xBEEF)
  let bytes = header.to_bytes()
  assert_true(bytes.length() == 16)
  match @qr.FrameHeader::from_bytes(bytes) {
    Some(h) => {
      assert_true(h.total_frames == 500)
      assert_true(h.current_frame == 250)
      assert_true(h.data_length == 10000)
      assert_true(h.checksum == 0xBEEF)
      assert_true(h.version == 1)
      // Magic bytes "QRFL" must be present.
      assert_true(h.magic[0] == 0x51)
      assert_true(h.magic[1] == 0x52)
      assert_true(h.magic[2] == 0x46)
      assert_true(h.magic[3] == 0x4C)
    }
    None => abort("stream boundary: frame header roundtrip parse failed")
  }
}

///|
test "stream boundary: frame header from invalid bytes" {
  // Too short: fewer than 16 bytes => None.
  let short_bytes = FixedArray::make(10, 0)
  assert_true(@qr.FrameHeader::from_bytes(short_bytes) is None)
  // Wrong magic: first byte is not 'Q'.
  let bad_magic = FixedArray::make(16, 0)
  bad_magic[0] = 0x58 // 'X'
  bad_magic[1] = 0x52
  bad_magic[2] = 0x46
  bad_magic[3] = 0x4C
  bad_magic[4] = 1
  assert_true(@qr.FrameHeader::from_bytes(bad_magic) is None)
  // Wrong version: magic correct but version != 1.
  let bad_ver = FixedArray::make(16, 0)
  bad_ver[0] = 0x51
  bad_ver[1] = 0x52
  bad_ver[2] = 0x46
  bad_ver[3] = 0x4C
  bad_ver[4] = 2 // wrong version
  assert_true(@qr.FrameHeader::from_bytes(bad_ver) is None)
  // All-zero bytes (wrong magic) => None.
  let all_zero = FixedArray::make(16, 0)
  assert_true(@qr.FrameHeader::from_bytes(all_zero) is None)
}

///|
test "stream boundary: reassemble partial frames" {
  // Providing fewer frames than total_frames declares must return None.
  let data = sb_make_test_data(100)
  let frames = @qr.split_into_frames(data, 32) // 4 frames
  assert_true(frames.length() == 4)
  // Keep only the first two frames.
  let partial : Array[FixedArray[Int32]] = []
  partial.push(frames[0])
  partial.push(frames[1])
  let result = @qr.reassemble_frames(partial)
  assert_true(result is None)
}

///|
test "stream boundary: reassemble duplicate frames" {
  // Two frames with the same current_frame index break the contiguous 0..n-1
  // sequence check and must return None.
  let data = sb_make_test_data(64)
  let frames = @qr.split_into_frames(data, 32) // 2 frames: indices 0 and 1
  assert_true(frames.length() == 2)
  // Duplicate frame 0 in place of frame 1.
  let dups : Array[FixedArray[Int32]] = []
  dups.push(frames[0])
  dups.push(frames[0])
  let result = @qr.reassemble_frames(dups)
  assert_true(result is None)
}
