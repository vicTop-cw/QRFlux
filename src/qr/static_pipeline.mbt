// Static encoding pipeline for QRFlux.
// data -> auto_compress -> package(with algo id) -> encode_qr
// qr_bytes -> unpackage -> decompress(by algo id) -> data

///|
/// Compression algorithm ID constants (mirrored from package.mbt for clarity).
/// 0 = no compression, 1 = RLE, 2 = deflate (reserved, unimplemented).

///|
/// Static encoding result.
pub struct StaticEncodeResult {
  qr : QrCode
  algo_id : Int32
  original_size : Int32
  packaged_size : Int32
  compressed : Bool
  packaged_bytes : FixedArray[Int32]
}

///|
/// Get the QR code object.
pub fn StaticEncodeResult::qr(self : StaticEncodeResult) -> QrCode {
  self.qr
}

///|
/// Get the compression algorithm ID used.
pub fn StaticEncodeResult::algo_id(self : StaticEncodeResult) -> Int32 {
  self.algo_id
}

///|
/// Get the original data size.
pub fn StaticEncodeResult::original_size(self : StaticEncodeResult) -> Int32 {
  self.original_size
}

///|
/// Get the packaged size (header + payload).
pub fn StaticEncodeResult::packaged_size(self : StaticEncodeResult) -> Int32 {
  self.packaged_size
}

///|
/// Check if data was compressed.
pub fn StaticEncodeResult::compressed(self : StaticEncodeResult) -> Bool {
  self.compressed
}

///|
/// Get the packaged bytes (header + payload), used as input to decode_static.
pub fn StaticEncodeResult::packaged_bytes(
  self : StaticEncodeResult,
) -> FixedArray[Int32] {
  self.packaged_bytes
}

///|
/// Check whether data fits in a single QR code at the given ECC level.
/// Uses the same bit-counting logic as encode_binary to avoid abort.
fn fits_in_single_qr(
  data : FixedArray[Int32],
  level : EccLevel,
  min_version : Int32,
) -> Bool {
  let segs = [Segment::make_bytes(data)]
  let mut version = min_version
  while version <= 40 {
    let bits = total_bits(segs, version)
    if bits >= 0 && bits <= num_data_codewords(version, level) * 8 {
      return true
    }
    version = version + 1
  }
  false
}

///|
/// Static encode: data -> auto_compress -> package(with algo id) -> encode_qr.
/// Automatically selects compression strategy, packages data with the
/// compression algorithm ID embedded in the header, then encodes into a QR code.
/// Returns None if the data is too large to fit in a single QR code
/// (static pipeline does not support fragmentation; use dynamic stream instead).
pub fn encode_static(
  data : FixedArray[Int32],
  level : EccLevel,
  min_version : Int32,
) -> StaticEncodeResult? {
  // 1. Auto-compress: select strategy and compress.
  let comp_result = auto_compress(data)
  let strategy = comp_result.strategy
  let compressed_data = comp_result.compressed_data

  // 2. Decide whether to use compression.
  //    - strategy == NoCompress -> algo 0
  //    - strategy != NoCompress but compressed >= original -> fall back to algo 0
  //    - otherwise -> RLE (algo 1)
  let use_compression = strategy != CompressionStrategy::NoCompress &&
    compressed_data.length() < data.length()
  let (payload, algo_id, compressed_flag) = if use_compression {
    (compressed_data, ALGO_RLE, true)
  } else {
    (data, ALGO_NONE, false)
  }

  // 3. Package with header (embeds algo_id at byte offset 6).
  let packaged = package_with_header(payload, algo_id, compressed_flag)

  // 4. Capacity check: abort prevention for single-QR static pipeline.
  if !fits_in_single_qr(packaged, level, min_version) {
    return None
  }

  // 5. Encode into QR code.
  let qr = encode_binary(packaged, level, min_version)

  // 6. Return result.
  Some({
    qr,
    algo_id,
    original_size: data.length(),
    packaged_size: packaged.length(),
    compressed: compressed_flag,
    packaged_bytes: packaged,
  })
}

///|
/// Static decode: qr_bytes -> unpackage -> decompress(by algo id) -> data.
/// Unpackages the scanned QR bytes, reads the compression algorithm ID from
/// the header, and decompresses the payload accordingly to restore the
/// original data.
/// Returns None if the package is invalid or the algorithm ID is unknown.
pub fn decode_static(qr_bytes : FixedArray[Int32]) -> FixedArray[Int32]? {
  let result = unpackage_from_header(qr_bytes)
  match result {
    None => None
    Some((payload, _original_size, _compressed, algo_id)) =>
      // Decompress by algorithm ID.
      match algo_id {
        0 => Some(payload)
        1 => Some(rle_decompress_optimized(payload))
        _ => None // unknown/unimplemented algorithm (e.g. algo=2 deflate)
      }
  }
}
