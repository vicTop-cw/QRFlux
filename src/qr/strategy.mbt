// Compression strategy selection for QRFlux.
// Automatically selects optimal compression strategy based on data characteristics.

///|
/// Compression strategy.
pub enum CompressionStrategy {
  NoCompress
  FastRLE
  BestSpeed
  Balanced
} derive(Eq, Debug)

///|
pub extend CompressionStrategy with Eq::{not_equal, equal}

///|
/// Convenience constructors.
pub fn strategy_no_compress() -> CompressionStrategy { NoCompress }
pub fn strategy_fast_rle() -> CompressionStrategy { FastRLE }
pub fn strategy_best_speed() -> CompressionStrategy { BestSpeed }
pub fn strategy_balanced() -> CompressionStrategy { Balanced }

///|
/// Compression level.
pub enum CompressionLevel {
  NoCompress
  Fast
  Best
} derive(Eq, Debug)

///|
pub extend CompressionLevel with Eq::{not_equal, equal}

///|
pub fn no_compress() -> CompressionLevel { NoCompress }
pub fn fast_compress() -> CompressionLevel { Fast }
pub fn best_compress() -> CompressionLevel { Best }

///|
/// Compression result.
pub struct CompressionResult {
  strategy : CompressionStrategy;
  compressed_data : FixedArray[Int];
  original_size : Int;
  compressed_size : Int;
  ratio : Float;
}

///|
/// Run-Length Encoding (RLE) compression.
pub fn rle_compress(data : FixedArray[Int]) -> FixedArray[Int] {
  if data.length() == 0 {
    return FixedArray::make(0, 0)
  }
  
  let result = Array::make(0, 0)
  let mut i = 0
  
  while i < data.length() {
    let value = data[i]
    let mut count = 1
    
    while i + count < data.length() && 
          data[i + count] == value && 
          count < 255 {
      count = count + 1
    }
    
    result.push(count)
    result.push(value)
    
    i = i + count
  }
  
  let output = FixedArray::make(result.length(), 0)
  for i = 0; i < result.length(); i = i + 1 {
    output[i] = result[i]
  }
  output
}

///|
/// RLE decompression.
pub fn rle_decompress(data : FixedArray[Int]) -> FixedArray[Int] {
  if data.length() == 0 {
    return FixedArray::make(0, 0)
  }
  
  let result = Array::make(0, 0)
  let mut i = 0
  
  while i < data.length() {
    if i + 1 >= data.length() {
      break
    }
    
    let count = data[i]
    let value = data[i + 1]
    
    for j = 0; j < count; j = j + 1 {
      result.push(value)
    }
    
    i = i + 2
  }
  
  let output = FixedArray::make(result.length(), 0)
  for i = 0; i < result.length(); i = i + 1 {
    output[i] = result[i]
  }
  output
}

///|
/// Compress data using the specified compression level.
pub fn compress(data : FixedArray[Int], level : CompressionLevel) -> FixedArray[Int] {
  match level {
    NoCompress => data
    Fast => rle_compress(data)
    Best => rle_compress(data)
  }
}

///|
/// Decompress data using the specified compression level.
pub fn decompress(data : FixedArray[Int], level : CompressionLevel) -> FixedArray[Int] {
  match level {
    NoCompress => data
    Fast => rle_decompress(data)
    Best => rle_decompress(data)
  }
}

///|
/// Calculate compression ratio.
pub fn compression_ratio(original : FixedArray[Int], compressed : FixedArray[Int]) -> Float {
  if original.length() == 0 {
    return 0.0
  }
  Float::from_int(compressed.length()) / Float::from_int(original.length())
}

///|
/// Select compression strategy based on data characteristics.
pub fn select_strategy(data : FixedArray[Int]) -> CompressionStrategy {
  if data.length() < 10 {
    return NoCompress
  }
  
  let mut repeats = 0
  for i = 1; i < data.length(); i = i + 1 {
    if data[i] == data[i - 1] {
      repeats = repeats + 1
    }
  }
  
  let repeat_ratio = Float::from_int(repeats) / Float::from_int(data.length())
  
  if repeat_ratio > 0.5 {
    FastRLE
  } else if repeat_ratio > 0.2 {
    BestSpeed
  } else if data.length() > 1000 {
    Balanced
  } else {
    NoCompress
  }
}

///|
/// Compress data using the selected strategy.
pub fn compress_with_strategy(data : FixedArray[Int], strategy : CompressionStrategy) -> CompressionResult {
  let level = match strategy {
    CompressionStrategy::NoCompress => CompressionLevel::NoCompress
    CompressionStrategy::FastRLE => CompressionLevel::Fast
    CompressionStrategy::BestSpeed => CompressionLevel::Fast
    CompressionStrategy::Balanced => CompressionLevel::Fast
  }
  
  let compressed = compress(data, level)
  let ratio = compression_ratio(data, compressed)
  
  {
    strategy,
    compressed_data: compressed,
    original_size: data.length(),
    compressed_size: compressed.length(),
    ratio,
  }
}

///|
/// Decompress data using the selected strategy.
pub fn decompress_with_strategy(compressed : FixedArray[Int], strategy : CompressionStrategy) -> FixedArray[Int] {
  let level = match strategy {
    CompressionStrategy::NoCompress => CompressionLevel::NoCompress
    CompressionStrategy::FastRLE => CompressionLevel::Fast
    CompressionStrategy::BestSpeed => CompressionLevel::Fast
    CompressionStrategy::Balanced => CompressionLevel::Fast
  }
  
  decompress(compressed, level)
}

///|
/// Auto-compress data: select strategy and compress.
pub fn auto_compress(data : FixedArray[Int]) -> CompressionResult {
  let strategy = select_strategy(data)
  compress_with_strategy(data, strategy)
}

///|
/// Check if compression is beneficial.
pub fn is_compression_beneficial(result : CompressionResult) -> Bool {
  result.ratio < 0.9
}

///|
/// Get compression savings in bytes.
pub fn get_savings(result : CompressionResult) -> Int {
  result.original_size - result.compressed_size
}

///|
/// Get savings percentage.
pub fn get_savings_percent(result : CompressionResult) -> Float {
  if result.original_size == 0 {
    return 0.0
  }
  (1.0 - result.ratio) * 100.0
}
