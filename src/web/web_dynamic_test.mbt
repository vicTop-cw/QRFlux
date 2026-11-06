// Web dynamic stream tests.
// Covers web_encode_dynamic and wasm_calculate_frames public functions,
// which are not covered by web_test.mbt.

///|
/// Helper: check if a JSON string contains a key/value fragment.
fn json_contains(json : String, key : String) -> Bool {
  json.contains(key)
}

///|
/// Helper: build a string by repeating a single-char string n times.
fn repeat_char(ch : String, n : Int32) -> String {
  let mut s = ""
  for i = 0; i < n; i = i + 1 {
    s = s + ch
  }
  s
}

///|
test "web dynamic: returns json with total_frames" {
  // "Hello World" = 11 bytes, max_payload=5 -> ceil(11/5) = 3 frames.
  let result = @web.web_encode_dynamic("Hello World", 5, "L")
  assert_true(result.length() > 0)
  assert_true(json_contains(result, "\"total_frames\""))
  assert_true(json_contains(result, "\"frames\""))
}

///|
test "web dynamic: small data single frame" {
  // "Hi" = 2 bytes, max_payload=100 -> 1 frame.
  let result = @web.web_encode_dynamic("Hi", 100, "L")
  assert_true(json_contains(result, "\"total_frames\":1"))
}

///|
test "web dynamic: large data multiple frames" {
  // 100 bytes / 10 = 10 frames.
  let data = repeat_char("A", 100)
  let result = @web.web_encode_dynamic(data, 10, "L")
  assert_true(json_contains(result, "\"total_frames\":10"))
}

///|
test "web dynamic: all ecc levels" {
  // All four ECC levels should return valid JSON with total_frames field.
  let levels = ["L", "M", "Q", "H"]
  for i = 0; i < levels.length(); i = i + 1 {
    let result = @web.web_encode_dynamic("Test", 50, levels[i])
    assert_true(result.length() > 0)
    assert_true(json_contains(result, "\"total_frames\""))
  }
}

///|
test "web dynamic: frame structure" {
  // Each frame should contain frame_id, version, size, matrix fields.
  let result = @web.web_encode_dynamic("Hello", 50, "L")
  assert_true(json_contains(result, "\"frame_id\""))
  assert_true(json_contains(result, "\"version\""))
  assert_true(json_contains(result, "\"size\""))
  assert_true(json_contains(result, "\"matrix\""))
}

///|
test "web dynamic: empty data" {
  // Empty string -> 0 frames, should not crash and return valid JSON.
  let result = @web.web_encode_dynamic("", 100, "L")
  assert_true(result.length() > 0)
  assert_true(json_contains(result, "\"total_frames\""))
}

///|
test "web dynamic: unicode data" {
  // Chinese characters -> multi-byte UTF-8, should encode successfully.
  let result = @web.web_encode_dynamic("你好世界", 50, "L")
  assert_true(result.length() > 0)
  assert_true(json_contains(result, "\"total_frames\""))
}

///|
test "web dynamic: max_payload 1" {
  // 3 bytes / 1 = 3 frames; verify tiny frame size is handled.
  let result = @web.web_encode_dynamic("ABC", 1, "L")
  assert_true(json_contains(result, "\"total_frames\":3"))
}

///|
test "wasm calc frames: basic" {
  // (100 + 50 - 1) / 50 = 2 frames, no compression.
  let result = @web.wasm_calculate_frames(100, 50, false)
  assert_true(json_contains(result, "\"frames_needed\""))
  assert_true(json_contains(result, "\"data_size\":100"))
  assert_true(json_contains(result, "\"max_payload\":50"))
  assert_true(json_contains(result, "\"compressed\":false"))
}

///|
test "wasm calc frames: with compress" {
  // compress=true: effective_size = 100/2 = 50, frames = (50+50-1)/50 = 1.
  let result = @web.wasm_calculate_frames(100, 50, true)
  assert_true(json_contains(result, "\"compressed\":true"))
  assert_true(json_contains(result, "\"frames_needed\":1"))
}

///|
test "wasm calc frames: exact multiple" {
  // data_size=100, max_payload=50 -> (100+50-1)/50 = 2 (exact multiple).
  let result = @web.wasm_calculate_frames(100, 50, false)
  assert_true(json_contains(result, "\"frames_needed\":2"))
}

///|
test "wasm calc frames: plus one" {
  // data_size=101, max_payload=50 -> (101+50-1)/50 = 3 (needs extra frame).
  let result = @web.wasm_calculate_frames(101, 50, false)
  assert_true(json_contains(result, "\"frames_needed\":3"))
}
