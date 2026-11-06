/// Multi-segment encoding tests: encode_segments with multiple Segment entries.
/// Covers two/three segment encoding, single segment in array, empty data
/// segments, split-at-various-positions roundtrip, and all ECC levels.

///|
/// Compare two FixedArray[Int32] for element-wise equality.
fn ms_arrays_eq(a : FixedArray[Int32], b : FixedArray[Int32]) -> Bool {
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
/// Concatenate multiple FixedArray[Int32] parts into a single FixedArray.
fn ms_concat_data(parts : Array[FixedArray[Int32]]) -> FixedArray[Int32] {
  let mut total = 0
  for p in parts {
    total = total + p.length()
  }
  let result = FixedArray::make(total, 0)
  let mut k = 0
  for p in parts {
    for i = 0; i < p.length(); i = i + 1 {
      result[k] = p[i]
      k = k + 1
    }
  }
  result
}

///|
test "multi seg: two segments encode" {
  let d1 = FixedArray::make(3, 0x41)
  let d2 = FixedArray::make(3, 0x42)
  let segs : Array[@qr.Segment] = []
  segs.push(@qr.Segment::make_bytes(d1))
  segs.push(@qr.Segment::make_bytes(d2))
  let qr = @qr.encode_segments(segs, @qr.ecc_low(), 1)
  assert_true(qr.version() >= 1)
  assert_true(qr.size() == qr.version() * 4 + 17)
}

///|
test "multi seg: three segments encode" {
  let d1 = FixedArray::make(2, 0x41)
  let d2 = FixedArray::make(3, 0x42)
  let d3 = FixedArray::make(4, 0x43)
  let segs : Array[@qr.Segment] = []
  segs.push(@qr.Segment::make_bytes(d1))
  segs.push(@qr.Segment::make_bytes(d2))
  segs.push(@qr.Segment::make_bytes(d3))
  let qr = @qr.encode_segments(segs, @qr.ecc_low(), 1)
  assert_true(qr.version() >= 1)
  assert_true(qr.size() == qr.version() * 4 + 17)
}

///|
test "multi seg: multi seg version correct" {
  let segs : Array[@qr.Segment] = []
  segs.push(@qr.Segment::make_bytes(FixedArray::make(5, 0x41)))
  segs.push(@qr.Segment::make_bytes(FixedArray::make(5, 0x42)))
  let qr = @qr.encode_segments(segs, @qr.ecc_low(), 1)
  assert_true(qr.version() >= 1)
  assert_true(qr.version() <= 40)
}

///|
test "multi seg: multi seg size correct" {
  let segs : Array[@qr.Segment] = []
  segs.push(@qr.Segment::make_bytes(FixedArray::make(4, 0x41)))
  segs.push(@qr.Segment::make_bytes(FixedArray::make(6, 0x42)))
  let qr = @qr.encode_segments(segs, @qr.ecc_medium(), 1)
  assert_true(qr.size() == qr.version() * 4 + 17)
}

///|
test "multi seg: two segs vs one seg same data" {
  let d1 = FixedArray::make(4, 0x41)
  let d2 = FixedArray::make(4, 0x42)
  // Two segments
  let segs2 : Array[@qr.Segment] = []
  segs2.push(@qr.Segment::make_bytes(d1))
  segs2.push(@qr.Segment::make_bytes(d2))
  let qr2 = @qr.encode_segments(segs2, @qr.ecc_low(), 1)
  // One segment (concatenated)
  let combined = ms_concat_data([d1, d2])
  let qr1 = @qr.encode_binary(combined, @qr.ecc_low(), 1)
  // Both decode back to the same concatenated data
  match @qr.decode_from_qrcode(qr2) {
    Some(r2) => assert_true(ms_arrays_eq(r2, combined))
    None => abort("two segs decode failed")
  }
  match @qr.decode_from_qrcode(qr1) {
    Some(r1) => assert_true(ms_arrays_eq(r1, combined))
    None => abort("one seg decode failed")
  }
}

///|
test "multi seg: split at various positions" {
  let data = FixedArray::make(20, 0)
  for i = 0; i < 20; i = i + 1 {
    data[i] = i + 1
  }
  // Split at every position 1..19 and verify decode roundtrip.
  for split = 1; split < 20; split = split + 1 {
    let d1 = FixedArray::make(split, 0)
    let d2 = FixedArray::make(20 - split, 0)
    for i = 0; i < split; i = i + 1 {
      d1[i] = data[i]
    }
    for i = 0; i < 20 - split; i = i + 1 {
      d2[i] = data[split + i]
    }
    let segs : Array[@qr.Segment] = []
    segs.push(@qr.Segment::make_bytes(d1))
    segs.push(@qr.Segment::make_bytes(d2))
    let qr = @qr.encode_segments(segs, @qr.ecc_low(), 1)
    match @qr.decode_from_qrcode(qr) {
      Some(r) => assert_true(ms_arrays_eq(r, data))
      None => abort("split decode failed")
    }
  }
}

///|
test "multi seg: many small segments" {
  let segs : Array[@qr.Segment] = []
  let pieces : Array[FixedArray[Int32]] = []
  for k = 0; k < 10; k = k + 1 {
    let d = FixedArray::make(2, 0)
    d[0] = k + 1
    d[1] = (k + 1) * 2
    pieces.push(d)
    segs.push(@qr.Segment::make_bytes(d))
  }
  let qr = @qr.encode_segments(segs, @qr.ecc_low(), 1)
  let combined = ms_concat_data(pieces)
  match @qr.decode_from_qrcode(qr) {
    Some(r) => assert_true(ms_arrays_eq(r, combined))
    None => abort("many small segments decode failed")
  }
}

///|
test "multi seg: empty segments array" {
  // Empty segment array still produces a valid QR (all padding codewords).
  let segs : Array[@qr.Segment] = []
  let qr = @qr.encode_segments(segs, @qr.ecc_low(), 1)
  assert_true(qr.version() >= 1)
  assert_true(qr.size() == qr.version() * 4 + 17)
}

///|
test "multi seg: single segment in array" {
  let data = FixedArray::make(8, 0x55)
  let segs : Array[@qr.Segment] = []
  segs.push(@qr.Segment::make_bytes(data))
  let qr = @qr.encode_segments(segs, @qr.ecc_low(), 1)
  match @qr.decode_from_qrcode(qr) {
    Some(r) => assert_true(ms_arrays_eq(r, data))
    None => abort("single segment decode failed")
  }
}

///|
test "multi seg: segments with empty data" {
  // Segments containing empty data (num_chars=0) interleaved with real data.
  let empty = FixedArray::make(0, 0)
  let data = FixedArray::make(5, 0x42)
  let segs : Array[@qr.Segment] = []
  segs.push(@qr.Segment::make_bytes(empty))
  segs.push(@qr.Segment::make_bytes(data))
  segs.push(@qr.Segment::make_bytes(empty))
  let qr = @qr.encode_segments(segs, @qr.ecc_low(), 1)
  assert_true(qr.size() == qr.version() * 4 + 17)
  match @qr.decode_from_qrcode(qr) {
    Some(r) => assert_true(ms_arrays_eq(r, data))
    None => abort("segments with empty data decode failed")
  }
}

///|
test "multi seg: two segs decode roundtrip" {
  let d1 = FixedArray::make(6, 0x41)
  let d2 = FixedArray::make(6, 0x42)
  let segs : Array[@qr.Segment] = []
  segs.push(@qr.Segment::make_bytes(d1))
  segs.push(@qr.Segment::make_bytes(d2))
  let qr = @qr.encode_segments(segs, @qr.ecc_medium(), 1)
  let combined = ms_concat_data([d1, d2])
  match @qr.decode_from_qrcode(qr) {
    Some(r) => assert_true(ms_arrays_eq(r, combined))
    None => abort("two segs decode roundtrip failed")
  }
}

///|
test "multi seg: multi seg all ecc levels" {
  let d1 = FixedArray::make(4, 0x41)
  let d2 = FixedArray::make(4, 0x42)
  let combined = ms_concat_data([d1, d2])
  let levels = [
    @qr.ecc_low(),
    @qr.ecc_medium(),
    @qr.ecc_quartile(),
    @qr.ecc_high(),
  ]
  for level in levels {
    let segs : Array[@qr.Segment] = []
    segs.push(@qr.Segment::make_bytes(d1))
    segs.push(@qr.Segment::make_bytes(d2))
    let qr = @qr.encode_segments(segs, level, 1)
    match @qr.decode_from_qrcode(qr) {
      Some(r) => assert_true(ms_arrays_eq(r, combined))
      None => abort("multi seg ecc level decode failed")
    }
  }
}
