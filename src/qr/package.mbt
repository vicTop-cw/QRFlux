// Binary package protocol for QRFlux.
// Defines file header + payload format for transmission.

///|
/// Package header structure (32 bytes):
/// +--------------------+
/// | Magic (4 bytes)    | 0x51 0x52 0x46 0x58 ("QRFX")
/// +--------------------+
/// | Version (1 byte)   | 0x01
/// +--------------------+
/// | Flags (1 byte)     | Bit 0: compressed, Bit 1-7: reserved
/// +--------------------+
/// | Compression algo   | 0=none, 1=RLE, 2=deflate(reserved)
/// | (1 byte)           |
/// +--------------------+
/// | Data length (4B)   | big-endian, total data length
/// +--------------------+
/// | Original size (4B) | big-endian, original data size
/// +--------------------+
/// | Checksum (4B)      | big-endian, CRC32
/// +--------------------+
/// | Reserved (13B)     | 0x00
/// +--------------------+
pub struct PackageHeader {
  magic : FixedArray[Int32]
  version : Int32
  flags : Int32
  compression_algo : Int32
  data_length : Int32
  original_size : Int32
  checksum : Int32
}

///|
/// Magic bytes: "QRFX" = 0x51 0x52 0x46 0x58
pub const MAGIC_Q1 : Int32 = 0x51

///|
pub const MAGIC_R2 : Int32 = 0x52

///|
pub const MAGIC_F3 : Int32 = 0x46

///|
pub const MAGIC_X4 : Int32 = 0x58

///|
/// Flag bits
pub const FLAG_COMPRESSED : Int32 = 0x01

///|
/// Compression algorithm IDs (numeric, stored in header byte 6).
/// 0 = no compression, 1 = RLE, 2 = deflate (reserved, unimplemented).
pub const ALGO_NONE : Int32 = 0

///|
pub const ALGO_RLE : Int32 = 1

///|
pub const ALGO_DEFLATE : Int32 = 2

///|
/// Create a new package header.
pub fn PackageHeader::make(
  data_length : Int32,
  original_size : Int32,
  checksum : Int32,
  compressed : Bool,
  compression_algo : Int32,
) -> PackageHeader {
  let flags = if compressed { FLAG_COMPRESSED } else { 0 }
  let magic = FixedArray::make(4, 0)
  magic[0] = MAGIC_Q1
  magic[1] = MAGIC_R2
  magic[2] = MAGIC_F3
  magic[3] = MAGIC_X4
  {
    magic,
    version: 1,
    flags,
    compression_algo,
    data_length,
    original_size,
    checksum,
  }
}

///|
/// Serialize package header to bytes (32 bytes).
pub fn PackageHeader::to_bytes(self : PackageHeader) -> FixedArray[Int32] {
  let bytes = FixedArray::make(32, 0)
  // Magic (4 bytes)
  bytes[0] = self.magic[0]
  bytes[1] = self.magic[1]
  bytes[2] = self.magic[2]
  bytes[3] = self.magic[3]
  // Version (1 byte)
  bytes[4] = self.version
  // Flags (1 byte)
  bytes[5] = self.flags
  // Compression algorithm ID (1 byte)
  bytes[6] = self.compression_algo
  // Data length (4 bytes, big-endian)
  bytes[7] = (self.data_length >> 24) & 0xFF
  bytes[8] = (self.data_length >> 16) & 0xFF
  bytes[9] = (self.data_length >> 8) & 0xFF
  bytes[10] = self.data_length & 0xFF
  // Original size (4 bytes, big-endian)
  bytes[11] = (self.original_size >> 24) & 0xFF
  bytes[12] = (self.original_size >> 16) & 0xFF
  bytes[13] = (self.original_size >> 8) & 0xFF
  bytes[14] = self.original_size & 0xFF
  // Checksum (4 bytes, big-endian)
  bytes[15] = (self.checksum >> 24) & 0xFF
  bytes[16] = (self.checksum >> 16) & 0xFF
  bytes[17] = (self.checksum >> 8) & 0xFF
  bytes[18] = self.checksum & 0xFF
  // Reserved (13 bytes) - already 0
  bytes
}

///|
/// Parse package header from bytes (32 bytes).
pub fn PackageHeader::from_bytes(bytes : FixedArray[Int32]) -> PackageHeader? {
  if bytes.length() < 32 {
    return None
  }
  // Verify magic
  if bytes[0] != MAGIC_Q1 ||
    bytes[1] != MAGIC_R2 ||
    bytes[2] != MAGIC_F3 ||
    bytes[3] != MAGIC_X4 {
    return None
  }
  // Verify version
  if bytes[4] != 1 {
    return None
  }
  let magic = FixedArray::make(4, 0)
  magic[0] = bytes[0]
  magic[1] = bytes[1]
  magic[2] = bytes[2]
  magic[3] = bytes[3]
  let version = bytes[4]
  let flags = bytes[5]
  let compression_algo = bytes[6]
  let data_length = (bytes[7] << 24) |
    (bytes[8] << 16) |
    (bytes[9] << 8) |
    bytes[10]
  let original_size = (bytes[11] << 24) |
    (bytes[12] << 16) |
    (bytes[13] << 8) |
    bytes[14]
  let checksum = (bytes[15] << 24) |
    (bytes[16] << 16) |
    (bytes[17] << 8) |
    bytes[18]
  Some({
    magic,
    version,
    flags,
    compression_algo,
    data_length,
    original_size,
    checksum,
  })
}

///|
/// Check if package is compressed.
pub fn PackageHeader::is_compressed(self : PackageHeader) -> Bool {
  (self.flags & FLAG_COMPRESSED) != 0
}

///|
/// Get compression algorithm ID.
pub fn PackageHeader::compression_algo(self : PackageHeader) -> Int32 {
  self.compression_algo
}

///|
/// Simple CRC32 checksum.
/// Uses logical right shift emulated via (x >> 1) & 0x7FFFFFFF to produce
/// standard CRC32 values (poly 0xEDB88320) for both positive and negative
/// Int32 intermediates. Arithmetic >> alone would give non-standard values
/// when crc becomes negative (high bit set).
pub fn crc32(data : FixedArray[Int32]) -> Int32 {
  let mut crc : Int32 = 0xFFFFFFFF
  for i = 0; i < data.length(); i = i + 1 {
    crc = crc ^ data[i]
    for j = 0; j < 8; j = j + 1 {
      if (crc & 1) != 0 {
        crc = ((crc >> 1) & 0x7FFFFFFF) ^ 0xEDB88320
      } else {
        crc = (crc >> 1) & 0x7FFFFFFF
      }
    }
  }
  (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF
}

///|
/// Package data with header.
/// Returns: header (32 bytes) + payload
/// compression_algo: 0=none, 1=RLE, 2=deflate(reserved)
pub fn package_with_header(
  data : FixedArray[Int32],
  compression_algo : Int32,
  compressed : Bool,
) -> FixedArray[Int32] {
  let checksum = crc32(data)
  let header = PackageHeader::make(
    data.length(),
    data.length(),
    checksum,
    compressed,
    compression_algo,
  )
  let header_bytes = header.to_bytes()

  let pkg = FixedArray::make(32 + data.length(), 0)
  for i = 0; i < 32; i = i + 1 {
    pkg[i] = header_bytes[i]
  }
  for i = 0; i < data.length(); i = i + 1 {
    pkg[32 + i] = data[i]
  }

  pkg
}

///|
/// Unpackage data from header + payload.
/// Returns: (payload, original_size, compressed, compression_algo)
pub fn unpackage_from_header(
  pkg : FixedArray[Int32],
) -> (FixedArray[Int32], Int32, Bool, Int32)? {
  if pkg.length() < 32 {
    return None
  }

  let header_bytes = FixedArray::make(32, 0)
  for i = 0; i < 32; i = i + 1 {
    header_bytes[i] = pkg[i]
  }

  let header = PackageHeader::from_bytes(header_bytes)
  match header {
    Some(h) => {
      // Verify data length
      if pkg.length() < 32 + h.data_length {
        return None
      }

      // Extract payload
      let payload = FixedArray::make(h.data_length, 0)
      for i = 0; i < h.data_length; i = i + 1 {
        payload[i] = pkg[32 + i]
      }

      // Verify checksum
      let actual_checksum = crc32(payload)
      if actual_checksum != h.checksum {
        return None
      }

      Some((payload, h.original_size, h.is_compressed(), h.compression_algo))
    }
    None => None
  }
}
