/// Whitebox tests for decoder internals.

///|
fn mk_bytes(xs : Array[Int32]) -> FixedArray[Int32] {
  let fa = FixedArray::make(xs.length(), 0)
  for i = 0; i < xs.length(); i = i + 1 {
    fa[i] = xs[i]
  }
  fa
}

///|
/// Verify that read_data_bits produces consistent results with the encoder's
/// draw_codewords scan. After the RS position-mapping fix, raw_bits should
/// match the encoder's written bits exactly.
test "wb compare bits V1 Hello" {
  let data = mk_bytes([72, 101, 108, 108, 111])
  let qr = encode_binary(data, ecc_low(), 1)
  let size = qr.size()
  let version = qr.version()
  let mask = qr.mask
  let isfunction = mark_function_modules(version, size)
  let raw_bits = read_data_bits(qr.modules, size, isfunction, mask)
  // Simulate the encoder's draw_codewords scan to verify bit consistency
  let modules = qr.modules
  let mut idx = 0
  let mut right = size - 1
  let mut mismatches = 0
  while right >= 1 {
    if right <= 6 {
      right = right - 1
    }
    for vert = 0; vert < size; vert = vert + 1 {
      for j = 0; j < 2; j = j + 1 {
        let x = right - j
        let upward = ((right + 1) & 2) == 0
        let y = if upward { size - 1 - vert } else { vert }
        if !isfunction[y][x] {
          let mut bit = modules[y][x]
          if mask_pattern(mask, x, y) {
            bit = !bit
          }
          let expected = if bit { 1 } else { 0 }
          if idx < raw_bits.length() {
            if raw_bits[idx] != expected {
              mismatches = mismatches + 1
            }
          }
          idx = idx + 1
        }
      }
    }
    right = right - 2
  }
  // After RS position-mapping fix, there should be no mismatches
  assert_true(mismatches == 0)
  assert_true(idx == raw_bits.length())
}
