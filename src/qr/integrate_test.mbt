test "calculate frames needed" {
  let frames = calculate_frames_needed(100, 50, false)
  assert_true(frames == 2)
  
  let frames2 = calculate_frames_needed(100, 30, false)
  assert_true(frames2 == 4)
}

test "get stream metadata" {
  let metadata = get_stream_metadata(100, 50, ecc_low(), false)
  
  // Should contain data_size
  assert_true(metadata.contains("data_size"))
  assert_true(metadata.contains("100"))
}

test "calculate frames needed compressed" {
  let frames = calculate_frames_needed(100, 50, true)
  // With compression, effective size is ~50, so 1 frame
  assert_true(frames == 1)
}

test "calculate frames needed large" {
  let frames = calculate_frames_needed(1000, 100, false)
  assert_true(frames == 10)
  
  let frames2 = calculate_frames_needed(2000, 100, false)
  assert_true(frames2 == 20)
}

test "metadata contains all fields" {
  let metadata = get_stream_metadata(500, 50, ecc_medium(), true)
  
  assert_true(metadata.contains("data_size"))
  assert_true(metadata.contains("max_payload"))
  assert_true(metadata.contains("frames_needed"))
  assert_true(metadata.contains("capacity_per_frame"))
  assert_true(metadata.contains("compressed"))
  assert_true(metadata.contains("ecl"))
}
