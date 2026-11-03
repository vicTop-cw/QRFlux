test "select strategy small data" {
  let data = FixedArray::make(5, 0x42)
  let strategy = @qr.select_strategy(data)
  assert_true(strategy == @qr.strategy_no_compress())
}

test "select strategy repeated data" {
  let data = FixedArray::make(100, 0xAA)
  let strategy = @qr.select_strategy(data)
  let valid = if strategy == @qr.strategy_fast_rle() { true } else { strategy == @qr.strategy_best_speed() }
  assert_true(valid)
}

test "select strategy random data" {
  let data = FixedArray::make(100, 0)
  for i = 0; i < 100; i = i + 1 {
    data[i] = i % 256
  }
  let strategy = @qr.select_strategy(data)
  let valid = if strategy == @qr.strategy_no_compress() { true } else { strategy == @qr.strategy_balanced() }
  assert_true(valid)
}

test "compress with strategy no compress" {
  let data = FixedArray::make(10, 0x42)
  let result = @qr.compress_with_strategy(data, @qr.strategy_no_compress())
  
  assert_true(result.strategy == @qr.strategy_no_compress())
  assert_true(result.original_size == 10)
  assert_true(result.compressed_size == 10)
  assert_true(result.ratio == 1.0)
}

test "compress with strategy fast rle" {
  let data = FixedArray::make(100, 0xAA)
  let result = @qr.compress_with_strategy(data, @qr.strategy_fast_rle())
  
  assert_true(result.strategy == @qr.strategy_fast_rle())
  assert_true(result.original_size == 100)
  assert_true(result.compressed_size < result.original_size)
  assert_true(result.ratio < 1.0)
}

test "decompress with strategy" {
  let original = FixedArray::make(50, 0xBB)
  let result = @qr.compress_with_strategy(original, @qr.strategy_fast_rle())
  let decompressed = @qr.decompress_with_strategy(result.compressed_data, @qr.strategy_fast_rle())
  
  assert_true(decompressed.length() == original.length())
  for i = 0; i < original.length(); i = i + 1 {
    assert_true(decompressed[i] == original[i])
  }
}

test "auto compress" {
  let data = FixedArray::make(100, 0xCC)
  let result = @qr.auto_compress(data)
  
  assert_true(result.original_size == 100)
  assert_true(result.compressed_size < result.original_size)
}

test "is compression beneficial" {
  let data = FixedArray::make(100, 0xDD)
  let result = @qr.auto_compress(data)
  let beneficial = @qr.is_compression_beneficial(result)
  assert_true(beneficial)
}

test "get savings" {
  let data = FixedArray::make(100, 0xEE)
  let result = @qr.auto_compress(data)
  let savings = @qr.get_savings(result)
  let savings_percent = @qr.get_savings_percent(result)
  
  assert_true(savings > 0)
  assert_true(savings_percent > 0.0)
}

test "strategy constructors" {
  let s1 = @qr.strategy_no_compress()
  let s2 = @qr.strategy_fast_rle()
  let s3 = @qr.strategy_best_speed()
  let s4 = @qr.strategy_balanced()
  
  assert_true(s1 == @qr.strategy_no_compress())
  assert_true(s2 == @qr.strategy_fast_rle())
  assert_true(s3 == @qr.strategy_best_speed())
  assert_true(s4 == @qr.strategy_balanced())
}
