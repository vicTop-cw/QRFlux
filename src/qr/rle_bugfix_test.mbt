///|
/// RLE bug fix verification: 1000 'A' chars roundtrip.
/// This test verifies that decode_static uses rle_decompress_optimized
/// (not rle_decompress) for count>=255 extended runs.
test "rle 1000A roundtrip (bug fix verification)" {
  let data = FixedArray::make(1000, 65) // 1000 个 'A'
  let result = @qr.encode_static(data, @qr.ecc_low(), 1)
  match result {
    None => assert_true(false)
    Some(r) => {
      let decoded = @qr.decode_static(r.packaged_bytes())
      match decoded {
        None => assert_true(false)
        Some(restored) => {
          assert_true(restored.length() == 1000)
          let mut all_a = true
          for i = 0; i < 1000; i = i + 1 {
            if restored[i] != 65 {
              all_a = false
            }
          }
          assert_true(all_a)
        }
      }
    }
  }
}
