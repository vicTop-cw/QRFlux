/// PNG IDAT data correctness tests (blackbox).
/// Parses PNG chunk structure and verifies zlib/deflate stored block data
/// matches QR modules exactly.
///
/// PNG layout for to_png output:
///   [0..7]   signature (8 bytes)
///   [8..32]  IHDR chunk (4 len + 4 type + 13 data + 4 crc = 25 bytes)
///   [33..]   IDAT chunk
///     [33..36] length (BE)
///     [37..40] "IDAT" = [73, 68, 65, 84]
///     [41..]  IDAT data:
///       [41..42] zlib header (0x78, 0x01)
///       [43]     deflate block header (0x01 = BFINAL=1, BTYPE=00 stored)
///       [44..45] LEN (LE)
///       [46..47] NLEN (LE, = ~LEN & 0xFFFF)
///       [48..48+LEN-1] raw image data
///       [48+LEN..48+LEN+3] Adler-32 (BE)
///   [...]   IEND chunk

///|
/// Compute Adler-32 checksum of a byte array (zlib convention).
fn png_adler32(data : FixedArray[Int32]) -> Int32 {
  let mut a : Int32 = 1
  let mut b : Int32 = 0
  for i = 0; i < data.length(); i = i + 1 {
    a = (a + data[i]) % 65521
    b = (b + a) % 65521
  }
  (b << 16) | a
}

///|
test "png data: idat zlib header" {
  // IDAT data begins with zlib header 0x78 0x01
  // (CM=8 deflate, CINFO=7; FCHECK=1 makes CMF*256+FLG divisible by 31).
  let data = FixedArray::make(5, 0x41)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let png = @qr.to_png(qr, 1, 4)
  // IDAT data starts at offset 41 (8 sig + 25 IHDR + 4 len + 4 type).
  assert_true(png[41] == 0x78)
  assert_true(png[42] == 0x01)
}

///|
test "png data: idat adler32 correct" {
  // The last 4 bytes of IDAT data are the Adler-32 checksum (BE)
  // of the raw (uncompressed) image data.
  let data = FixedArray::make(5, 0x41)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let png = @qr.to_png(qr, 1, 4)
  // IDAT length (BE at offset 33).
  let idat_len = (png[33] << 24) | (png[34] << 16) | (png[35] << 8) | png[36]
  // Stored block: LEN at 44-45 (LE).
  let len = png[44] | (png[45] << 8)
  // Raw data is at 48..48+len-1.
  let raw = FixedArray::make(len, 0)
  for i = 0; i < len; i = i + 1 {
    raw[i] = png[48 + i]
  }
  let expected = png_adler32(raw)
  // Adler-32 is the last 4 bytes of IDAT data (BE).
  let adler_start = 41 + idat_len - 4
  let actual = (png[adler_start] << 24) |
    (png[adler_start + 1] << 16) |
    (png[adler_start + 2] << 8) |
    png[adler_start + 3]
  assert_true(actual == expected)
}

///|
test "png data: idat stored block" {
  // The deflate data uses a single stored block:
  // BFINAL=1, BTYPE=00 -> header byte = 0x01.
  // LEN and NLEN are complementary: NLEN = ~LEN & 0xFFFF.
  let data = FixedArray::make(5, 0x41)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let png = @qr.to_png(qr, 1, 4)
  // Block header at offset 43.
  assert_true(png[43] == 1) // BFINAL=1, BTYPE=00
  let len = png[44] | (png[45] << 8)
  let nlen = png[46] | (png[47] << 8)
  // NLEN must be the one's complement of LEN (mod 16 bits).
  assert_true(nlen == ((len ^ 0xFFFF) & 0xFFFF))
}

///|
test "png data: idat data length matches" {
  // The stored block data length == height * (1 + ceil(width/8))
  // where width = height = size + 2*quiet_zone (scale=1, bit_depth=1).
  let data = FixedArray::make(5, 0x41)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let png = @qr.to_png(qr, 1, 4)
  let size = qr.size()
  let quiet = 4
  let total = size + quiet * 2
  let width = total
  let height = total
  let row_bytes = (width + 7) / 8 // ceil(width/8) for bit_depth=1
  let expected_raw_len = height * (1 + row_bytes) // 1 filter byte per row
  let len = png[44] | (png[45] << 8)
  assert_true(len == expected_raw_len)
}

///|
test "png data: idat filter byte zero" {
  // Every row's first byte (filter type) must be 0 (None).
  let data = FixedArray::make(5, 0x41)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let png = @qr.to_png(qr, 1, 4)
  let size = qr.size()
  let quiet = 4
  let total = size + quiet * 2
  let width = total
  let row_bytes = (width + 7) / 8
  let row_len = 1 + row_bytes
  let height = total
  // Raw data starts at offset 48.
  let mut all_zero = true
  for y = 0; y < height; y = y + 1 {
    let filter_byte = png[48 + y * row_len]
    if filter_byte != 0 {
      all_zero = false
    }
  }
  assert_true(all_zero)
}

///|
test "png data: idat pixels match qr modules" {
  // Decompress IDAT (stored block) and verify each pixel bit matches the
  // corresponding QR module. PNG grayscale bit_depth=1: 0=black, 1=white.
  // QR module: true=black, false=white. So PNG bit = qr.get_module ? 0 : 1.
  // Bits are packed MSB first: pixel x -> byte[x/8] bit (7 - x%8).
  let data = FixedArray::make(5, 0x41)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let png = @qr.to_png(qr, 1, 4)
  let size = qr.size()
  let quiet = 4
  let total = size + quiet * 2
  let row_bytes = (total + 7) / 8
  let row_len = 1 + row_bytes
  // Raw data starts at offset 48.
  let mut all_match = true
  for y = 0; y < total; y = y + 1 {
    for x = 0; x < total; x = x + 1 {
      let byte_idx = x / 8
      let bit_pos = 7 - x % 8
      let byte = png[48 + y * row_len + 1 + byte_idx]
      let bit = (byte >> bit_pos) & 1
      // Determine expected darkness from QR module (with quiet zone offset).
      let dark = if x < quiet ||
        x >= quiet + size ||
        y < quiet ||
        y >= quiet + size {
        false
      } else {
        qr.get_module(x - quiet, y - quiet)
      }
      // PNG: 0=black (dark), 1=white (light).
      let expected_bit = if dark { 0 } else { 1 }
      if bit != expected_bit {
        all_match = false
      }
    }
  }
  assert_true(all_match)
}
