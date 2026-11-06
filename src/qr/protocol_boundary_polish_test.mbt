// Protocol boundary polish tests.
// Systematic boundary coverage for PackageHeader / FrameHeader fields,
// magic byte corruption, version rejection, min/max field values,
// extra-bytes tolerance, and multi-frame reassembly ordering.

///|
/// Build a valid 32-byte package header buffer with the given fields.
fn pb_pkg_bytes(
  data_length : Int32,
  original_size : Int32,
  checksum : Int32,
  compressed : Bool,
  algo : Int32,
) -> FixedArray[Int32] {
  let h = @qr.PackageHeader::make(
    data_length, original_size, checksum, compressed, algo,
  )
  h.to_bytes()
}

///|
/// Build a valid 16-byte frame header buffer with the given fields.
fn pb_frame_bytes(
  total : Int32,
  current : Int32,
  data_len : Int32,
  checksum : Int32,
) -> FixedArray[Int32] {
  let h = @qr.FrameHeader::make(total, current, data_len, checksum)
  h.to_bytes()
}

///|
/// Element-wise equality check for two FixedArray[Int32].
fn pb_eq(a : FixedArray[Int32], b : FixedArray[Int32]) -> Bool {
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
test "protocol boundary: package magic each byte corruption" {
  // Corrupting any single magic byte must cause from_bytes to return None.
  for k = 0; k < 4; k = k + 1 {
    let bytes = pb_pkg_bytes(100, 100, 0x1234, false, 0)
    bytes[k] = bytes[k] ^ 0x01
    assert_true(@qr.PackageHeader::from_bytes(bytes) is None)
  }
}

///|
test "protocol boundary: package version 0 2 255 rejected" {
  // from_bytes requires version == 1; any other value is rejected.
  let versions : Array[Int32] = [0, 2, 255]
  for i = 0; i < versions.length(); i = i + 1 {
    let bytes = pb_pkg_bytes(100, 100, 0x1234, false, 0)
    bytes[4] = versions[i]
    assert_true(@qr.PackageHeader::from_bytes(bytes) is None)
  }
}

///|
test "protocol boundary: package zero fields roundtrip" {
  // All numeric fields at minimum (zero) must roundtrip.
  let h = @qr.PackageHeader::make(0, 0, 0, false, 0)
  let bytes = h.to_bytes()
  match @qr.PackageHeader::from_bytes(bytes) {
    Some(p) => {
      assert_true(p.data_length == 0)
      assert_true(p.original_size == 0)
      assert_true(p.checksum == 0)
      assert_true(!p.is_compressed())
      assert_true(p.compression_algo() == 0)
    }
    None => abort("protocol boundary: package zero fields roundtrip failed")
  }
}

///|
test "protocol boundary: package max positive fields roundtrip" {
  // Max positive Int32 fields must roundtrip without overflow.
  let max_pos : Int32 = 0x7FFFFFFF
  let h = @qr.PackageHeader::make(max_pos, max_pos, max_pos, true, 2)
  let bytes = h.to_bytes()
  match @qr.PackageHeader::from_bytes(bytes) {
    Some(p) => {
      assert_true(p.data_length == max_pos)
      assert_true(p.original_size == max_pos)
      assert_true(p.checksum == max_pos)
      assert_true(p.is_compressed())
      assert_true(p.compression_algo() == 2)
    }
    None =>
      abort("protocol boundary: package max positive fields roundtrip failed")
  }
}

///|
test "protocol boundary: package negative checksum roundtrip" {
  // Checksum with high bit set (negative Int32) must roundtrip correctly.
  let neg_checksum : Int32 = -1 // 0xFFFFFFFF in two's complement
  let h = @qr.PackageHeader::make(1000, 2000, neg_checksum, true, 1)
  let bytes = h.to_bytes()
  // Verify all 4 checksum bytes are 0xFF.
  assert_true(bytes[15] == 0xFF)
  assert_true(bytes[16] == 0xFF)
  assert_true(bytes[17] == 0xFF)
  assert_true(bytes[18] == 0xFF)
  match @qr.PackageHeader::from_bytes(bytes) {
    Some(p) => assert_true(p.checksum == neg_checksum)
    None =>
      abort("protocol boundary: package negative checksum roundtrip failed")
  }
}

///|
test "protocol boundary: package length boundary 31 vs 32" {
  // 31 bytes => None; 32 bytes with valid header => Some.
  let too_short = FixedArray::make(31, 0)
  assert_true(@qr.PackageHeader::from_bytes(too_short) is None)
  let valid = pb_pkg_bytes(10, 10, 0, false, 0)
  assert_true(valid.length() == 32)
  assert_true(@qr.PackageHeader::from_bytes(valid) is Some(_))
}

///|
test "protocol boundary: package extra bytes ignored" {
  // from_bytes should accept >32 bytes and use only the first 32.
  let header_bytes = pb_pkg_bytes(50, 50, 0xABCDEF, false, 0)
  let extended = FixedArray::make(40, 0xFF)
  for i = 0; i < 32; i = i + 1 {
    extended[i] = header_bytes[i]
  }
  match @qr.PackageHeader::from_bytes(extended) {
    Some(p) => assert_true(p.data_length == 50)
    None => abort("protocol boundary: package extra bytes ignored failed")
  }
}

///|
test "protocol boundary: frame magic each byte corruption" {
  // Corrupting any single frame magic byte must cause from_bytes to return None.
  for k = 0; k < 4; k = k + 1 {
    let bytes = pb_frame_bytes(10, 5, 100, 0xBEEF)
    bytes[k] = bytes[k] ^ 0x01
    assert_true(@qr.FrameHeader::from_bytes(bytes) is None)
  }
}

///|
test "protocol boundary: frame version 0 2 255 rejected" {
  // from_bytes requires version == 1; any other value is rejected.
  let versions : Array[Int32] = [0, 2, 255]
  for i = 0; i < versions.length(); i = i + 1 {
    let bytes = pb_frame_bytes(10, 5, 100, 0xBEEF)
    bytes[4] = versions[i]
    assert_true(@qr.FrameHeader::from_bytes(bytes) is None)
  }
}

///|
test "protocol boundary: frame total_frames zero roundtrip" {
  // total_frames=0 is semantically unusual but from_bytes does not reject it.
  let h = @qr.FrameHeader::make(0, 0, 0, 0)
  let bytes = h.to_bytes()
  match @qr.FrameHeader::from_bytes(bytes) {
    Some(p) => assert_true(p.total_frames == 0)
    None => abort("protocol boundary: frame total_frames zero roundtrip failed")
  }
}

///|
test "protocol boundary: frame total_frames 65535 roundtrip" {
  // 65535 is the max value storable in 2 big-endian bytes.
  let h = @qr.FrameHeader::make(65535, 65534, 100000, 0xFFFF)
  let bytes = h.to_bytes()
  // Verify 2-byte big-endian encoding of total_frames.
  assert_true(bytes[5] == 0xFF)
  assert_true(bytes[6] == 0xFF)
  match @qr.FrameHeader::from_bytes(bytes) {
    Some(p) => {
      assert_true(p.total_frames == 65535)
      assert_true(p.current_frame == 65534)
      assert_true(p.checksum == 0xFFFF)
    }
    None =>
      abort("protocol boundary: frame total_frames 65535 roundtrip failed")
  }
}

///|
test "protocol boundary: frame current exceeds total roundtrip" {
  // current_frame > total_frames is semantically invalid but from_bytes
  // does not enforce the relationship; it must still roundtrip.
  let h = @qr.FrameHeader::make(3, 10, 500, 0x1234)
  let bytes = h.to_bytes()
  match @qr.FrameHeader::from_bytes(bytes) {
    Some(p) => {
      assert_true(p.total_frames == 3)
      assert_true(p.current_frame == 10)
    }
    None =>
      abort("protocol boundary: frame current exceeds total roundtrip failed")
  }
}

///|
test "protocol boundary: frame length boundary 15 vs 16" {
  // 15 bytes => None; 16 bytes with valid header => Some.
  let too_short = FixedArray::make(15, 0)
  assert_true(@qr.FrameHeader::from_bytes(too_short) is None)
  let valid = pb_frame_bytes(5, 0, 50, 0)
  assert_true(valid.length() == 16)
  assert_true(@qr.FrameHeader::from_bytes(valid) is Some(_))
}

///|
test "protocol boundary: frame extra bytes ignored" {
  // from_bytes should accept >16 bytes and use only the first 16.
  let header_bytes = pb_frame_bytes(8, 3, 64, 0xABCD)
  let extended = FixedArray::make(20, 0xEE)
  for i = 0; i < 16; i = i + 1 {
    extended[i] = header_bytes[i]
  }
  match @qr.FrameHeader::from_bytes(extended) {
    Some(p) => assert_true(p.total_frames == 8)
    None => abort("protocol boundary: frame extra bytes ignored failed")
  }
}

///|
test "protocol boundary: package full roundtrip various sizes" {
  // End-to-end: data -> package_with_header -> unpackage_from_header -> equality.
  let sizes : Array[Int32] = [0, 1, 31, 32, 33, 255, 1024]
  for i = 0; i < sizes.length(); i = i + 1 {
    let n = sizes[i]
    let data = FixedArray::make(n, 0)
    for j = 0; j < n; j = j + 1 {
      data[j] = j % 256
    }
    let pkg = @qr.package_with_header(data, 0, false)
    match @qr.unpackage_from_header(pkg) {
      Some((payload, orig, comp, algo)) => {
        assert_true(pb_eq(payload, data))
        assert_true(orig == n)
        assert_true(!comp)
        assert_true(algo == 0)
      }
      None =>
        abort("protocol boundary: package full roundtrip size \{n} failed")
    }
  }
}

///|
test "protocol boundary: multi frame reassemble out of order" {
  // Split data into frames, shuffle the frame order, and verify reassemble
  // still reconstructs the original data (sorts by current_frame).
  let data = FixedArray::make(100, 0)
  for i = 0; i < 100; i = i + 1 {
    data[i] = i % 256
  }
  let frames = @qr.split_into_frames(data, 30) // 4 frames: 30+30+30+10
  assert_true(frames.length() == 4)
  // Non-trivial permutation: [3, 1, 2, 0].
  let shuffled : Array[FixedArray[Int32]] = []
  shuffled.push(frames[3])
  shuffled.push(frames[1])
  shuffled.push(frames[2])
  shuffled.push(frames[0])
  match @qr.reassemble_frames(shuffled) {
    Some(result) => assert_true(pb_eq(result, data))
    None =>
      abort("protocol boundary: multi frame reassemble out of order failed")
  }
}
