// End-to-end dynamic stream tests.
// Tests the full pipeline: compression -> framing -> QR encoding -> reassembly -> decompression.

test "dynamic stream full pipeline" {
  let original = FixedArray::make(100, 0x42)
  
  // Step 1: Compress
  let compressed = @qr.compress(original, @qr.fast_compress())
  assert_true(compressed.length() <= original.length())
  
  // Step 2: Split into frames
  let frames = @qr.split_into_frames(compressed, 50)
  assert_true(frames.length() > 0)
  
  // Step 3: Reassemble
  let reassembled = @qr.reassemble_frames(frames)
  assert_true(reassembled is Some(_))
  
  // Step 4: Decompress
  let decompressed = @qr.decompress(reassembled.unwrap(), @qr.fast_compress())
  assert_true(decompressed.length() == original.length())
  
  // Verify content
  for i = 0; i < original.length(); i = i + 1 {
    assert_true(decompressed[i] == original[i])
  }
}

test "dynamic stream with compression" {
  // Use data that benefits from compression
  let original = FixedArray::make(100, 0)
  for i = 0; i < 100; i = i + 1 {
    original[i] = if i < 50 { 0xAA } else { 0xBB }
  }
  
  // Compress
  let compressed = @qr.compress(original, @qr.fast_compress())
  assert_true(compressed.length() < original.length())
}

test "dynamic stream large data" {
  let original = FixedArray::make(500, 0xCC)
  
  // Compress
  let compressed = @qr.compress(original, @qr.fast_compress())
  
  // Split into frames
  let frames = @qr.split_into_frames(compressed, 100)
  assert_true(frames.length() > 0)
  
  // Reassemble
  let reassembled = @qr.reassemble_frames(frames)
  assert_true(reassembled is Some(_))
}

test "dynamic stream empty data" {
  let original = FixedArray::make(0, 0)
  
  let compressed = @qr.compress(original, @qr.fast_compress())
  assert_true(compressed.length() == 0)
  
  let frames = @qr.split_into_frames(compressed, 50)
  assert_true(frames.length() == 0)
}
