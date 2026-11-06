/// Extra integrate tests: calculate_frames_needed and get_stream_metadata
/// boundary coverage, plus consistency checks against split_into_frames.

///|
test "integrate extra: frames needed small data" {
  // 50 bytes, max_payload=50 -> 1 frame
  assert_true(@qr.calculate_frames_needed(50, 50, false) == 1)
  // 51 bytes, max_payload=50 -> 2 frames
  assert_true(@qr.calculate_frames_needed(51, 50, false) == 2)
  // 10 bytes, max_payload=100 -> 1 frame
  assert_true(@qr.calculate_frames_needed(10, 100, false) == 1)
}

///|
test "integrate extra: frames needed large data" {
  // 10000 bytes, max_payload=100 -> 100 frames
  assert_true(@qr.calculate_frames_needed(10000, 100, false) == 100)
  // 10001 bytes, max_payload=100 -> 101 frames
  assert_true(@qr.calculate_frames_needed(10001, 100, false) == 101)
  // 100000 bytes, max_payload=1000 -> 100 frames
  assert_true(@qr.calculate_frames_needed(100000, 1000, false) == 100)
}

///|
test "integrate extra: frames needed exact multiple" {
  // Data length is an exact multiple of max_payload.
  for n = 1; n <= 10; n = n + 1 {
    let data_size = n * 50
    assert_true(@qr.calculate_frames_needed(data_size, 50, false) == n)
  }
}

///|
test "integrate extra: frames needed plus one" {
  // Data length = max_payload * n + 1 -> n+1 frames.
  for n = 1; n <= 10; n = n + 1 {
    let data_size = n * 50 + 1
    assert_true(@qr.calculate_frames_needed(data_size, 50, false) == n + 1)
  }
}

///|
test "integrate extra: frames needed various frame sizes" {
  let data_size = 1000
  let payloads = [10, 50, 100, 500, 1000]
  let expected = [100, 20, 10, 2, 1]
  for i = 0; i < 5; i = i + 1 {
    assert_true(
      @qr.calculate_frames_needed(data_size, payloads[i], false) == expected[i],
    )
  }
}

///|
test "integrate extra: stream metadata basic" {
  let metadata = @qr.get_stream_metadata(100, 50, @qr.ecc_low(), false)
  // frames_needed = (100 + 50 - 1) / 50 = 2
  assert_true(metadata.contains("\"data_size\":100"))
  assert_true(metadata.contains("\"max_payload\":50"))
  assert_true(metadata.contains("\"frames_needed\":2"))
  assert_true(metadata.contains("\"compressed\":false"))
  assert_true(metadata.contains("\"ecl\":\"L\""))
}

///|
test "integrate extra: stream metadata large" {
  let metadata = @qr.get_stream_metadata(10000, 100, @qr.ecc_high(), true)
  // compress=true: effective_size = 10000/2 = 5000
  // frames = (5000 + 100 - 1) / 100 = 50
  assert_true(metadata.contains("\"data_size\":10000"))
  assert_true(metadata.contains("\"frames_needed\":50"))
  assert_true(metadata.contains("\"compressed\":true"))
  assert_true(metadata.contains("\"ecl\":\"H\""))
}

///|
test "integrate extra: stream metadata fields" {
  let metadata = @qr.get_stream_metadata(500, 100, @qr.ecc_medium(), false)
  // frames = (500 + 100 - 1) / 100 = 5
  assert_true(metadata.contains("\"data_size\":500"))
  assert_true(metadata.contains("\"max_payload\":100"))
  assert_true(metadata.contains("\"frames_needed\":5"))
  assert_true(metadata.contains("\"capacity_per_frame\""))
  assert_true(metadata.contains("\"compressed\":false"))
  assert_true(metadata.contains("\"ecl\":\"M\""))
}

///|
test "integrate extra: frames needed vs actual split" {
  // calculate_frames_needed (compress=false) matches split_into_frames count.
  let sizes = [1, 50, 100, 500, 1000]
  let payloads = [50, 50, 100, 200, 300]
  for i = 0; i < 5; i = i + 1 {
    let data = FixedArray::make(sizes[i], 0x42)
    let frames = @qr.split_into_frames(data, payloads[i])
    let calculated = @qr.calculate_frames_needed(sizes[i], payloads[i], false)
    assert_true(frames.length() == calculated)
  }
}

///|
test "integrate extra: metadata consistent with split" {
  // get_stream_metadata frames_needed matches split_into_frames count.
  let data_size = 250
  let max_payload = 100
  let data = FixedArray::make(data_size, 0x42)
  let frames = @qr.split_into_frames(data, max_payload)
  let metadata = @qr.get_stream_metadata(
    data_size,
    max_payload,
    @qr.ecc_low(),
    false,
  )
  // frames_needed = (250 + 100 - 1) / 100 = 3
  assert_true(frames.length() == 3)
  assert_true(metadata.contains("\"frames_needed\":3"))
}
