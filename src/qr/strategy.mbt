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
pub extend CompressionStrategy with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// Convenience constructors.
pub fn strategy_no_compress() -> CompressionStrategy {
  NoCompress
}

///|
pub fn strategy_fast_rle() -> CompressionStrategy {
  FastRLE
}

///|
pub fn strategy_best_speed() -> CompressionStrategy {
  BestSpeed
}

///|
pub fn strategy_balanced() -> CompressionStrategy {
  Balanced
}

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
pub extend CompressionLevel with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub fn no_compress() -> CompressionLevel {
  NoCompress
}

///|
pub fn fast_compress() -> CompressionLevel {
  Fast
}

///|
pub fn best_compress() -> CompressionLevel {
  Best
}

///|
/// Compression result.
pub struct CompressionResult {
  strategy : CompressionStrategy
  compressed_data : FixedArray[Int32]
  original_size : Int32
  compressed_size : Int32
  ratio : Float
}

///|
/// Improved RLE compression with variable-length encoding.
/// Uses single byte for short runs, multiple bytes for long runs.
pub fn rle_compress_optimized(data : FixedArray[Int32]) -> FixedArray[Int32] {
  if data.length() == 0 {
    return FixedArray::make(0, 0)
  }

  let result = Array::make(0, 0)
  let mut i = 0

  while i < data.length() {
    let value = data[i]
    let mut count = 1

    while i + count < data.length() && data[i + count] == value && count < 65535 {
      count = count + 1
    }

    // Optimized encoding:
    // - count < 255: 2 bytes [count, value]
    // - count >= 255: 4 bytes [255, high_byte, low_byte, value]

    if count < 255 {
      result.push(count)
      result.push(value)
    } else {
      result.push(255) // Marker for extended run
      result.push((count >> 8) & 0xFF)
      result.push(count & 0xFF)
      result.push(value)
    }

    i = i + count
  }

  let output = FixedArray::make(result.length(), 0)
  for i = 0; i < result.length(); i = i + 1 {
    output[i] = result[i]
  }
  output
}

///|
/// Optimized RLE decompression.
pub fn rle_decompress_optimized(data : FixedArray[Int32]) -> FixedArray[Int32] {
  if data.length() == 0 {
    return FixedArray::make(0, 0)
  }

  let result = Array::make(0, 0)
  let mut i = 0

  while i < data.length() {
    if data[i] == 255 {
      // Extended run
      if i + 3 >= data.length() {
        break
      }
      let count = (data[i + 1] << 8) | data[i + 2]
      let value = data[i + 3]

      for j = 0; j < count; j = j + 1 {
        result.push(value)
      }

      i = i + 4
    } else {
      // Normal run
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
  }

  let output = FixedArray::make(result.length(), 0)
  for i = 0; i < result.length(); i = i + 1 {
    output[i] = result[i]
  }
  output
}

///|
/// RLE compression.
pub fn rle_compress(data : FixedArray[Int32]) -> FixedArray[Int32] {
  rle_compress_optimized(data)
}

///|
/// RLE decompression.
pub fn rle_decompress(data : FixedArray[Int32]) -> FixedArray[Int32] {
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
pub fn compress(
  data : FixedArray[Int32],
  level : CompressionLevel,
) -> FixedArray[Int32] {
  match level {
    NoCompress => data
    Fast => rle_compress(data)
    Best => rle_compress(data)
  }
}

///|
/// Decompress data using the specified compression level.
pub fn decompress(
  data : FixedArray[Int32],
  level : CompressionLevel,
) -> FixedArray[Int32] {
  match level {
    NoCompress => data
    Fast => rle_decompress_optimized(data)
    Best => rle_decompress_optimized(data)
  }
}

///|
/// Calculate compression ratio.
pub fn compression_ratio(
  original : FixedArray[Int32],
  compressed : FixedArray[Int32],
) -> Float {
  if original.length() == 0 {
    return 0.0
  }
  Float::from_int(compressed.length()) / Float::from_int(original.length())
}

///|
/// Select compression strategy based on data characteristics.
pub fn select_strategy(data : FixedArray[Int32]) -> CompressionStrategy {
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
pub fn compress_with_strategy(
  data : FixedArray[Int32],
  strategy : CompressionStrategy,
) -> CompressionResult {
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
pub fn decompress_with_strategy(
  compressed : FixedArray[Int32],
  strategy : CompressionStrategy,
) -> FixedArray[Int32] {
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
/// If the chosen strategy makes the data larger (or equal), fall back to
/// NoCompress to avoid expansion. This guards against cases like random
/// data with len > 1000 where select_strategy returns Balanced (mapped to
/// Fast/RLE), and RLE expands random data ~2x.
pub fn auto_compress(data : FixedArray[Int32]) -> CompressionResult {
  let strategy = select_strategy(data)
  let result = compress_with_strategy(data, strategy)
  if result.compressed_size >= result.original_size {
    compress_with_strategy(data, CompressionStrategy::NoCompress)
  } else {
    result
  }
}

///|
/// Check if compression is beneficial.
pub fn is_compression_beneficial(result : CompressionResult) -> Bool {
  result.ratio < 0.9
}

///|
/// Get compression savings in bytes.
pub fn get_savings(result : CompressionResult) -> Int32 {
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
