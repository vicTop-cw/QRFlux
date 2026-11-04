///|
test "lt fountain split and encode" {
  let fountain = @qr.LTFountain::new(10, 4)
  let data = FixedArray::make(40, 0x42)

  let blocks = fountain.split(data)
  assert_true(blocks.length() == 4)

  // Encode a block
  let encoded = fountain.encode_block(blocks, 1)
  assert_true(encoded.length() == 10)
}

///|
test "lt fountain basic" {
  let fountain = @qr.LTFountain::new(10, 4)
  let data = FixedArray::make(40, 0x42)

  // Split data
  let blocks = fountain.split(data)
  assert_true(blocks.length() == 4)

  // Verify first block content
  assert_true(blocks[0][0] == 0x42)
  assert_true(blocks[0][9] == 0x42)
}
