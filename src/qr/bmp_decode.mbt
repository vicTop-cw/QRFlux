/// BMP decoder: byte stream -> grayscale bitmap.
/// Covers the formats that actually appear on Windows desktops and
/// clipboard pipelines: BI_RGB (uncompressed) at 24/32 bpp (BGR/BGRA)
/// and 8/1 bpp with a palette, bottom-up or top-down (negative height).
/// Everything else (RLE, 16 bpp, PNG-inside-BMP, ...) is rejected with
/// None rather than mis-decoded.

///|
/// Read a little-endian u32 from a byte view at offset.
fn bmp_u32(data : BytesView, off : Int32) -> Int32 {
  data[off].to_int() |
  (data[off + 1].to_int() << 8) |
  (data[off + 2].to_int() << 16) |
  (data[off + 3].to_int() << 24)
}

///|
/// Read a little-endian u16 from a byte view at offset.
fn bmp_u16(data : BytesView, off : Int32) -> Int32 {
  data[off].to_int() | (data[off + 1].to_int() << 8)
}

///|
/// Read a little-endian i32 (signed) from a byte view at offset.
/// MoonBit Int is 32-bit and `<<` wraps to two's complement on both
/// backends, so the bit pattern from bmp_u32 already carries the sign.
fn bmp_i32(data : BytesView, off : Int32) -> Int32 {
  bmp_u32(data, off)
}

///|
/// Decode an uncompressed (BI_RGB) BMP into a grayscale bitmap (0..255).
/// Supported: 24 bpp (BGR), 32 bpp (BGRA/BGRX), 8 bpp palette,
/// 1 bpp monochrome palette; bottom-up (positive height) and top-down
/// (negative height) scan order. Returns None for unsupported or
/// corrupt input (RLE, 16 bpp, truncated file, bad signature).
pub fn decode_bmp_gray(bmp : BytesView) -> FixedArray[FixedArray[Int32]]? {
  let n = bmp.length()
  // BITMAPFILEHEADER is 14 bytes, BITMAPINFOHEADER at least 40.
  if n < 14 + 40 {
    return None
  }
  // Signature 'BM'
  if bmp[0].to_int() != 0x42 || bmp[1].to_int() != 0x4D {
    return None
  }
  let data_offset = bmp_u32(bmp, 10)
  let header_size = bmp_u32(bmp, 14)
  if header_size < 40 {
    return None
  }
  let width = bmp_i32(bmp, 18)
  let height_signed = bmp_i32(bmp, 22)
  let bpp = bmp_u16(bmp, 28)
  let compression = bmp_u32(bmp, 30)
  if width <= 0 ||
    width > 32767 ||
    height_signed == 0 ||
    height_signed.abs() > 32767 {
    return None
  }
  if compression != 0 {
    // BI_RGB only; RLE and BI_BITFIELDS are out of scope.
    return None
  }
  let bottom_up = height_signed > 0
  let height = height_signed.abs()
  let palette_offset = 14 + header_size
  // Palette: 4 bytes per entry (BGRX) for bpp <= 8.
  if bpp > 8 && bpp != 24 && bpp != 32 {
    return None
  }
  let palette_count = if bpp <= 8 {
    // ColorsUsed field at offset 46; 0 means the full 2^bpp table.
    let used = bmp_u32(bmp, 46)
    if used == 0 {
      1 << bpp
    } else if used > 1 << bpp {
      1 << bpp
    } else {
      used
    }
  } else {
    0
  }
  if palette_offset + palette_count * 4 > n {
    return None
  }
  // Read the palette into gray values (luma of BGRX).
  let pal : FixedArray[Int32] = FixedArray::make(palette_count, 0)
  for i = 0; i < palette_count; i = i + 1 {
    let b = bmp[palette_offset + i * 4].to_int() & 0xFF
    let g = bmp[palette_offset + i * 4 + 1].to_int() & 0xFF
    let r = bmp[palette_offset + i * 4 + 2].to_int() & 0xFF
    pal[i] = (r * 299 + g * 587 + b * 114) / 1000
  }
  // Row layout: bytes per row padded to a 4-byte boundary.
  let bits_per_row = width * bpp
  let row_len = (bits_per_row + 7) / 8
  let stride = (row_len + 3) / 4 * 4
  if data_offset + stride * height > n {
    return None
  }
  let gray : FixedArray[FixedArray[Int32]] = FixedArray::make(
    height,
    FixedArray::make(width, 255),
  )
  // Allocate each row up front: the write index below is the *transposed*
  // row y (bottom-up files), so allocating inside the row loop would
  // reset a row that was already written.
  for i = 0; i < height; i = i + 1 {
    gray[i] = FixedArray::make(width, 255)
  }
  let pixels_at = data_offset
  for row = 0; row < height; row = row + 1 {
    // Bottom-up bitmaps store the bottom row first.
    let y = if bottom_up { height - 1 - row } else { row }
    let base = pixels_at + row * stride
    if bpp == 24 {
      for x = 0; x < width; x = x + 1 {
        let o = base + x * 3
        let b = bmp[o].to_int() & 0xFF
        let g = bmp[o + 1].to_int() & 0xFF
        let r = bmp[o + 2].to_int() & 0xFF
        gray[y][x] = (r * 299 + g * 587 + b * 114) / 1000
      }
    } else if bpp == 32 {
      for x = 0; x < width; x = x + 1 {
        let o = base + x * 4
        let b = bmp[o].to_int() & 0xFF
        let g = bmp[o + 1].to_int() & 0xFF
        let r = bmp[o + 2].to_int() & 0xFF
        gray[y][x] = (r * 299 + g * 587 + b * 114) / 1000
      }
    } else if bpp == 8 {
      for x = 0; x < width; x = x + 1 {
        let idx = bmp[base + x].to_int() & 0xFF
        gray[y][x] = if idx < palette_count { pal[idx] } else { 255 }
      }
    } else {
      // bpp == 1: packed monochrome, MSB first.
      for x = 0; x < width; x = x + 1 {
        let byte = bmp[base + x / 8].to_int() & 0xFF
        let bit = (byte >> (7 - x % 8)) & 1
        gray[y][x] = if bit < palette_count { pal[bit] } else { 255 }
      }
    }
  }
  Some(gray)
}
