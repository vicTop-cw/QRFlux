/// QR Code image generators: PBM, SVG, PNG.
/// Zero external dependencies, fully self-implemented.
/// PNG uses deflate "stored" blocks to avoid implementing full zlib.

///|
/// Generate PBM (Portable Bitmap, P1 ASCII) format image string.
/// 1 = black (module), 0 = white. Quiet zone is white border.
/// qr: QR code object, quiet_zone: quiet zone size (typically 4)
pub fn to_pbm(qr : QrCode, quiet_zone : Int32) -> String {
  let size = qr.size()
  let total = size + quiet_zone * 2
  let mut sb = "P1\n"
  sb = sb + total.to_string() + " " + total.to_string() + "\n"
  for y = 0; y < total; y = y + 1 {
    for x = 0; x < total; x = x + 1 {
      let dark = if x < quiet_zone ||
        x >= quiet_zone + size ||
        y < quiet_zone ||
        y >= quiet_zone + size {
        false
      } else {
        qr.get_module(x - quiet_zone, y - quiet_zone)
      }
      if dark {
        sb = sb + "1"
      } else {
        sb = sb + "0"
      }
      if x < total - 1 {
        sb = sb + " "
      }
    }
    sb = sb + "\n"
  }
  sb
}

///|
/// Generate SVG format image string.
/// Each black module is a <rect>. scale = pixels per module.
/// qr: QR code object, scale: pixels per module, quiet_zone: quiet zone size
pub fn to_svg(qr : QrCode, scale : Int32, quiet_zone : Int32) -> String {
  let size = qr.size()
  let total = size + quiet_zone * 2
  let dim = total * scale
  let dim_str = dim.to_string()
  let scale_str = scale.to_string()
  let mut sb = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"" +
    dim_str +
    "\" height=\"" +
    dim_str +
    "\">\n"
  sb = sb +
    "  <rect width=\"" +
    dim_str +
    "\" height=\"" +
    dim_str +
    "\" fill=\"white\"/>\n"
  for y = 0; y < total; y = y + 1 {
    for x = 0; x < total; x = x + 1 {
      let dark = if x < quiet_zone ||
        x >= quiet_zone + size ||
        y < quiet_zone ||
        y >= quiet_zone + size {
        false
      } else {
        qr.get_module(x - quiet_zone, y - quiet_zone)
      }
      if dark {
        let px = x * scale
        let py = y * scale
        sb = sb +
          "  <rect x=\"" +
          px.to_string() +
          "\" y=\"" +
          py.to_string() +
          "\" width=\"" +
          scale_str +
          "\" height=\"" +
          scale_str +
          "\" fill=\"black\"/>\n"
      }
    }
  }
  sb = sb + "</svg>\n"
  sb
}

///|
/// Adler-32 checksum (for zlib stream in PNG).
fn adler32(data : FixedArray[Int32]) -> Int32 {
  let mut a : Int32 = 1
  let mut b : Int32 = 0
  let n = data.length()
  for i = 0; i < n; i = i + 1 {
    a = (a + data[i]) % 65521
    b = (b + a) % 65521
  }
  (b << 16) | a
}

///|
/// PNG CRC32 using logical right shift.
/// Now identical to the package-level crc32 (which was fixed to use logical
/// right shift via (x >> 1) & 0x7FFFFFFF). Kept as a separate function to
/// preserve the png module boundary and allow independent verification.
fn png_crc32(data : FixedArray[Int32]) -> Int32 {
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
/// Build a PNG chunk: length(4 BE) + type(4) + data + CRC32(4 BE).
/// CRC is computed over type + data.
fn png_chunk(
  type_bytes : FixedArray[Int32],
  data : FixedArray[Int32],
) -> FixedArray[Int32] {
  let len : Int32 = data.length()
  let crc_input = FixedArray::make(4 + len, 0)
  crc_input[0] = type_bytes[0]
  crc_input[1] = type_bytes[1]
  crc_input[2] = type_bytes[2]
  crc_input[3] = type_bytes[3]
  for i = 0; i < len; i = i + 1 {
    crc_input[4 + i] = data[i]
  }
  let crc = png_crc32(crc_input)
  let out = FixedArray::make(12 + len, 0)
  out[0] = (len >> 24) & 0xFF
  out[1] = (len >> 16) & 0xFF
  out[2] = (len >> 8) & 0xFF
  out[3] = len & 0xFF
  out[4] = type_bytes[0]
  out[5] = type_bytes[1]
  out[6] = type_bytes[2]
  out[7] = type_bytes[3]
  for i = 0; i < len; i = i + 1 {
    out[8 + i] = data[i]
  }
  out[8 + len] = (crc >> 24) & 0xFF
  out[9 + len] = (crc >> 16) & 0xFF
  out[10 + len] = (crc >> 8) & 0xFF
  out[11 + len] = crc & 0xFF
  out
}

///|
/// Generate PNG format image (grayscale, bit_depth=1) as byte array.
/// Uses deflate "stored" blocks (no compression) to avoid full zlib.
/// bit_depth=1 packs 8 pixels per byte (MSB first), ~8x smaller than bit_depth=8.
/// PNG grayscale bit_depth=1: 0=black, 1=white.
/// QR module: 1=black, 0=white, so PNG bit = 1 - QR module.
/// qr: QR code object, scale: pixels per module, quiet_zone: quiet zone size
/// Returns: PNG binary data (FixedArray[Int32], each 0~255)
pub fn to_png(
  qr : QrCode,
  scale : Int32,
  quiet_zone : Int32,
) -> FixedArray[Int32] {
  let size = qr.size()
  let total = size + quiet_zone * 2
  let width = total * scale
  let height = total * scale
  // bit_depth=1: each row = 1 filter byte (0) + ceil(width/8) packed bytes
  // MSB first: pixel 0 -> bit 7, pixel 1 -> bit 6, ...
  let row_bytes = (width + 7) / 8
  let row_len = 1 + row_bytes
  let raw_len = height * row_len
  let raw = FixedArray::make(raw_len, 0)
  for y = 0; y < total; y = y + 1 {
    for x = 0; x < total; x = x + 1 {
      let dark = if x < quiet_zone ||
        x >= quiet_zone + size ||
        y < quiet_zone ||
        y >= quiet_zone + size {
        false
      } else {
        qr.get_module(x - quiet_zone, y - quiet_zone)
      }
      // PNG bit: 0=black (QR dark), 1=white (QR light)
      let bit : Int32 = if dark { 0 } else { 1 }
      for dy = 0; dy < scale; dy = dy + 1 {
        let row = (y * scale + dy) * row_len
        raw[row] = 0 // filter type = None
        for dx = 0; dx < scale; dx = dx + 1 {
          let px = x * scale + dx
          let byte_idx = px / 8
          let bit_pos = 7 - px % 8
          raw[row + 1 + byte_idx] = raw[row + 1 + byte_idx] | (bit << bit_pos)
        }
      }
    }
  }
  // IHDR data (13 bytes)
  let ihdr = FixedArray::make(13, 0)
  ihdr[0] = (width >> 24) & 0xFF
  ihdr[1] = (width >> 16) & 0xFF
  ihdr[2] = (width >> 8) & 0xFF
  ihdr[3] = width & 0xFF
  ihdr[4] = (height >> 24) & 0xFF
  ihdr[5] = (height >> 16) & 0xFF
  ihdr[6] = (height >> 8) & 0xFF
  ihdr[7] = height & 0xFF
  ihdr[8] = 1 // bit depth = 1 (bit-packed grayscale)
  ihdr[9] = 0 // color type (grayscale)
  ihdr[10] = 0 // compression method
  ihdr[11] = 0 // filter method
  ihdr[12] = 0 // interlace method
  // IDAT data: zlib stream
  // zlib header (2) + deflate stored blocks (5 header each + data) + adler32 (4)
  let num_blocks = (raw_len + 65534) / 65535
  let idat_len = 2 + num_blocks * 5 + raw_len + 4
  let idat = FixedArray::make(idat_len, 0)
  idat[0] = 0x78 // CMF: CM=8 (deflate), CINFO=7
  idat[1] = 0x01 // FLG: FCHECK=1 (makes CMF*256+FLG divisible by 31)
  let mut pos : Int32 = 2
  let mut offset : Int32 = 0
  while offset < raw_len {
    let remaining = raw_len - offset
    let block_len = if remaining > 65535 { 65535 } else { remaining }
    let bfinal = if offset + block_len >= raw_len { 1 } else { 0 }
    idat[pos] = bfinal
    idat[pos + 1] = block_len & 0xFF
    idat[pos + 2] = (block_len >> 8) & 0xFF
    idat[pos + 3] = (block_len ^ 0xFFFF) & 0xFF
    idat[pos + 4] = ((block_len ^ 0xFFFF) >> 8) & 0xFF
    pos = pos + 5
    for i = 0; i < block_len; i = i + 1 {
      idat[pos + i] = raw[offset + i]
    }
    pos = pos + block_len
    offset = offset + block_len
  }
  let adler = adler32(raw)
  idat[pos] = (adler >> 24) & 0xFF
  idat[pos + 1] = (adler >> 16) & 0xFF
  idat[pos + 2] = (adler >> 8) & 0xFF
  idat[pos + 3] = adler & 0xFF
  // Chunk type bytes
  let ihdr_type = FixedArray::make(4, 0)
  ihdr_type[0] = 0x49 // I
  ihdr_type[1] = 0x48 // H
  ihdr_type[2] = 0x44 // D
  ihdr_type[3] = 0x52 // R
  let idat_type = FixedArray::make(4, 0)
  idat_type[0] = 0x49 // I
  idat_type[1] = 0x44 // D
  idat_type[2] = 0x41 // A
  idat_type[3] = 0x54 // T
  let iend_type = FixedArray::make(4, 0)
  iend_type[0] = 0x49 // I
  iend_type[1] = 0x45 // E
  iend_type[2] = 0x4E // N
  iend_type[3] = 0x44 // D
  let empty = FixedArray::make(0, 0)
  let ihdr_chunk = png_chunk(ihdr_type, ihdr)
  let idat_chunk = png_chunk(idat_type, idat)
  let iend_chunk = png_chunk(iend_type, empty)
  // Assemble: signature + IHDR + IDAT + IEND
  let total_len = 8 +
    ihdr_chunk.length() +
    idat_chunk.length() +
    iend_chunk.length()
  let out = FixedArray::make(total_len, 0)
  out[0] = 137
  out[1] = 80
  out[2] = 78
  out[3] = 71
  out[4] = 13
  out[5] = 10
  out[6] = 26
  out[7] = 10
  let mut p : Int32 = 8
  for i = 0; i < ihdr_chunk.length(); i = i + 1 {
    out[p + i] = ihdr_chunk[i]
  }
  p = p + ihdr_chunk.length()
  for i = 0; i < idat_chunk.length(); i = i + 1 {
    out[p + i] = idat_chunk[i]
  }
  p = p + idat_chunk.length()
  for i = 0; i < iend_chunk.length(); i = i + 1 {
    out[p + i] = iend_chunk[i]
  }
  out
}
