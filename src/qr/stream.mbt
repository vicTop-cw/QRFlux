// Dynamic QR stream protocol for >1KB files.
// Frame header: 16 bytes + payload.

///|
/// Frame header structure (16 bytes):
/// +--------------------+
/// | Magic (4 bytes)    | 0x51 0x52 0x46 0x4C ("QRFL")
/// +--------------------+
/// | Version (1 byte)   | 0x01
/// +--------------------+
/// | Total frames (2B)  | big-endian
/// +--------------------+
/// | Current frame (2B) | big-endian
/// +--------------------+
/// | Data length (4B)   | big-endian
/// +--------------------+
/// | Checksum (2B)      | CRC16
/// +--------------------+
/// | Reserved (1B)      | 0x00
/// +--------------------+
pub struct FrameHeader {
  magic : FixedArray[Int32]
  version : Int32
  total_frames : Int32
  current_frame : Int32
  data_length : Int32
  checksum : Int32
}

///|
/// Magic bytes: "QRFL" = 0x51 0x52 0x46 0x4C
pub const MAGIC_Q : Int32 = 0x51

///|
pub const MAGIC_R : Int32 = 0x52

///|
pub const MAGIC_F : Int32 = 0x46

///|
pub const MAGIC_L : Int32 = 0x4C

///|
pub fn FrameHeader::make(
  total_frames : Int32,
  current_frame : Int32,
  data_length : Int32,
  checksum : Int32,
) -> FrameHeader {
  let magic = FixedArray::make(4, 0)
  magic[0] = MAGIC_Q
  magic[1] = MAGIC_R
  magic[2] = MAGIC_F
  magic[3] = MAGIC_L
  { magic, version: 1, total_frames, current_frame, data_length, checksum, }
}

///|
/// Serialize frame header to bytes (16 bytes).
pub fn FrameHeader::to_bytes(self : FrameHeader) -> FixedArray[Int32] {
  let bytes = FixedArray::make(16, 0)
  // Magic (4 bytes)
  bytes[0] = self.magic[0]
  bytes[1] = self.magic[1]
  bytes[2] = self.magic[2]
  bytes[3] = self.magic[3]
  // Version (1 byte)
  bytes[4] = self.version
  // Total frames (2 bytes, big-endian)
  bytes[5] = (self.total_frames >> 8) & 0xFF
  bytes[6] = self.total_frames & 0xFF
  // Current frame (2 bytes, big-endian)
  bytes[7] = (self.current_frame >> 8) & 0xFF
  bytes[8] = self.current_frame & 0xFF
  // Data length (4 bytes, big-endian)
  bytes[9] = (self.data_length >> 24) & 0xFF
  bytes[10] = (self.data_length >> 16) & 0xFF
  bytes[11] = (self.data_length >> 8) & 0xFF
  bytes[12] = self.data_length & 0xFF
  // Checksum (2 bytes, big-endian)
  bytes[13] = (self.checksum >> 8) & 0xFF
  bytes[14] = self.checksum & 0xFF
  // Reserved (1 byte)
  bytes[15] = 0x00
  bytes
}

///|
/// Parse frame header from bytes (16 bytes).
pub fn FrameHeader::from_bytes(bytes : FixedArray[Int32]) -> FrameHeader? {
  if bytes.length() < 16 {
    return None
  }
  // Verify magic
  if bytes[0] != MAGIC_Q ||
    bytes[1] != MAGIC_R ||
    bytes[2] != MAGIC_F ||
    bytes[3] != MAGIC_L {
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
  let total_frames = (bytes[5] << 8) | bytes[6]
  let current_frame = (bytes[7] << 8) | bytes[8]
  let data_length = (bytes[9] << 24) |
    (bytes[10] << 16) |
    (bytes[11] << 8) |
    bytes[12]
  let checksum = (bytes[13] << 8) | bytes[14]
  Some({ magic, version, total_frames, current_frame, data_length, checksum, })
}

///|
/// Simple CRC16 checksum (for small data).
pub fn crc16(data : FixedArray[Int32]) -> Int32 {
  let mut crc = 0
  for i = 0; i < data.length(); i = i + 1 {
    crc = crc ^ (data[i] << 8)
    for j = 0; j < 8; j = j + 1 {
      if (crc & 0x8000) != 0 {
        crc = (crc << 1) ^ 0x1021
      } else {
        crc = crc << 1
      }
      crc = crc & 0xFFFF
    }
  }
  crc
}

///|
/// Split data into frames for QR encoding.
/// Each frame: header (16 bytes) + payload (max_payload bytes).
pub fn split_into_frames(
  data : FixedArray[Int32],
  max_payload : Int32,
) -> Array[FixedArray[Int32]] {
  let frames = Array::make(0, FixedArray::make(0, 0))
  let total_frames = (data.length() + max_payload - 1) / max_payload
  let checksum = crc16(data)

  for i = 0; i < total_frames; i = i + 1 {
    let start = i * max_payload
    let end = start + max_payload
    let end = if end > data.length() { data.length() } else { end }
    let payload_len = end - start

    // Build frame: header + payload
    // data_length is the total data length, not per-frame payload length
    let header = FrameHeader::make(total_frames, i, data.length(), checksum)
    let header_bytes = header.to_bytes()

    let frame = FixedArray::make(16 + payload_len, 0)
    for j = 0; j < 16; j = j + 1 {
      frame[j] = header_bytes[j]
    }
    for j = 0; j < payload_len; j = j + 1 {
      frame[16 + j] = data[start + j]
    }

    frames.push(frame)
  }

  frames
}

///|
/// Reassemble data from frames.
/// Frames may arrive in ANY order; reassembly sorts by current_frame
/// before concatenating payloads. Returns None on missing/duplicate frames,
/// bad magic/version, or checksum mismatch.
pub fn reassemble_frames(
  frames : Array[FixedArray[Int32]],
) -> FixedArray[Int32]? {
  if frames.length() == 0 {
    return None
  }

  // Parse all frame headers first.
  let headers : Array[FrameHeader] = Array::make(
    0,
    FrameHeader::make(0, 0, 0, 0),
  )
  for i = 0; i < frames.length(); i = i + 1 {
    match FrameHeader::from_bytes(frames[i]) {
      Some(h) => headers.push(h)
      None => return None
    }
  }

  // Use first header for metadata (total_frames, data_length, checksum).
  let first = headers[0]
  let total_frames = first.total_frames
  let expected_checksum = first.checksum
  let total_data_len = first.data_length

  // Verify frame count.
  if frames.length() != total_frames {
    return None
  }

  // Sort frames by current_frame (stable insertion sort by index).
  // Build index array [0, 1, ..., n-1] and sort by headers[idx].current_frame.
  let order : Array[Int32] = Array::make(frames.length(), 0)
  for i = 0; i < frames.length(); i = i + 1 {
    order[i] = i
  }
  // Insertion sort on `order` by current_frame ascending.
  for i = 1; i < order.length(); i = i + 1 {
    let key = order[i]
    let key_cf = headers[key].current_frame
    let mut j = i - 1
    while j >= 0 && headers[order[j]].current_frame > key_cf {
      order[j + 1] = order[j]
      j = j - 1
    }
    order[j + 1] = key
  }

  // Verify sorted indices form a contiguous 0..total_frames-1 sequence.
  for i = 0; i < total_frames; i = i + 1 {
    if headers[order[i]].current_frame != i {
      return None
    }
  }

  // Reassemble data in sorted order.
  let data = FixedArray::make(total_data_len, 0)
  let mut offset = 0
  for i = 0; i < total_frames; i = i + 1 {
    let frame = frames[order[i]]
    let frame_payload_len = frame.length() - 16
    for j = 0; j < frame_payload_len; j = j + 1 {
      if offset + j < total_data_len {
        data[offset + j] = frame[16 + j]
      }
    }
    offset = offset + frame_payload_len
  }

  // Verify checksum.
  let actual_checksum = crc16(data)
  if actual_checksum != expected_checksum {
    return None
  }

  Some(data)
}
