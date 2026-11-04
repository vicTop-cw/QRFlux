// End-to-end dynamic stream integration for QRFlux.
// Combines: compression -> framing -> QR encoding -> reassembly -> decompression.

///|
/// Calculate number of frames needed for data.
pub fn calculate_frames_needed(
  data_size : Int32,
  max_payload : Int32,
  compress : Bool,
) -> Int32 {
  let effective_size = if compress {
    // Estimate compression ratio (simplified)
    data_size / 2
  } else {
    data_size
  }

  (effective_size + max_payload - 1) / max_payload
}

///|
/// Get metadata for dynamic stream.
pub fn get_stream_metadata(
  data_size : Int32,
  max_payload : Int32,
  level : EccLevel,
  compress : Bool,
) -> String {
  let frames_needed = calculate_frames_needed(data_size, max_payload, compress)
  let capacity = num_data_codewords(40, level) // Assume V40 for max capacity

  let ecl_str = match level {
    Low => "L"
    Medium => "M"
    Quartile => "Q"
    High => "H"
  }

  "{" +
  "\"data_size\":" +
  data_size.to_string() +
  "," +
  "\"max_payload\":" +
  max_payload.to_string() +
  "," +
  "\"frames_needed\":" +
  frames_needed.to_string() +
  "," +
  "\"capacity_per_frame\":" +
  capacity.to_string() +
  "," +
  "\"compressed\":" +
  (if compress { "true" } else { "false" }) +
  "," +
  "\"ecl\":\"" +
  ecl_str +
  "\"" +
  "}"
}
