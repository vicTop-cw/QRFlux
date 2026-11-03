// Compression module for QRFlux.
// Supports multiple compression levels: none/fast/best.

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
/// Convenience constructors (cross-package enum ctor usage helper).
pub fn no_compress() -> CompressionLevel { NoCompress }
pub fn fast_compress() -> CompressionLevel { Fast }
pub fn best_compress() -> CompressionLevel { Best }

///|
/// Get compression level from string.
pub fn CompressionLevel::from_string(s : String) -> CompressionLevel {
  match s {
    "none" => NoCompress
    "fast" => Fast
    "best" => Best
    _ => NoCompress
  }
}

///|
/// Compress data using the specified compression level.
/// Returns compressed data.
pub fn compress(data : FixedArray[Int], level : CompressionLevel) -> FixedArray[Int] {
  match level {
    NoCompress => data
    Fast => rle_compress(data)
    Best => rle_compress(data)  // For now, RLE is our best option
  }
}

///|
/// Decompress data using the specified compression level.
/// Returns decompressed data.
pub fn decompress(data : FixedArray[Int], level : CompressionLevel) -> FixedArray[Int] {
  match level {
    NoCompress => data
    Fast => rle_decompress(data)
    Best => rle_decompress(data)
  }
}

///|
/// Run-Length Encoding (RLE) compression.
/// Simple compression: [count, value, count, value, ...]
/// For repeated bytes, this reduces size significantly.
pub fn rle_compress(data : FixedArray[Int]) -> FixedArray[Int] {
  if data.length() == 0 {
    return FixedArray::make(0, 0)
  }
  
  let result = Array::make(0, 0)
  let mut i = 0
  
  while i < data.length() {
    let value = data[i]
    let mut count = 1
    
    // Count consecutive identical bytes
    while i + count < data.length() && 
          data[i + count] == value && 
          count < 255 {
      count = count + 1
    }
    
    // Encode: [count, value]
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
    
    // Decode: repeat value count times
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
/// Calculate compression ratio.
/// Returns ratio of compressed size to original size (0.0 to 1.0+).
pub fn compression_ratio(original : FixedArray[Int], compressed : FixedArray[Int]) -> Float {
  if original.length() == 0 {
    return 0.0
  }
  Float::from_int(compressed.length()) / Float::from_int(original.length())
}

///|
/// Estimate best compression level based on data characteristics.
/// Simple heuristic: if data has many repeats, use RLE.
pub fn suggest_compression_level(data : FixedArray[Int]) -> CompressionLevel {
  if data.length() < 10 {
    return NoCompress  // Too small to benefit from compression
  }
  
  // Calculate repeat ratio
  let mut repeats = 0
  for i = 1; i < data.length(); i = i + 1 {
    if data[i] == data[i - 1] {
      repeats = repeats + 1
    }
  }
  
  let repeat_ratio = Float::from_int(repeats) / Float::from_int(data.length())
  
  if repeat_ratio > 0.3 {
    Fast  // High repeat ratio benefits from RLE
  } else {
    NoCompress  // Low repeat ratio, don't compress
  }
}
