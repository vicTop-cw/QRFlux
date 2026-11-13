/// PNG decoder: byte stream -> grayscale bitmap.
/// This closes the loop with image.mbt's to_png: a PNG file written by
/// QRFlux (or any non-interlaced PNG grayscale/RGB screenshot) can be
/// read back into pixels and fed to decode_from_pixels.
///
/// Chunk parsing, unfiltering and bit-depth/color expansion are
/// self-implemented; zlib decompression reuses the MoonBit standard
/// library (moonbitlang/core/compress/zlib).

///|
/// Read a big-endian u32 from a byte view at offset.
fn png_u32(data : BytesView, off : Int32) -> Int32 {
  ((data[off].to_int() & 0xFF) << 24) |
  ((data[off + 1].to_int() & 0xFF) << 16) |
  ((data[off + 2].to_int() & 0xFF) << 8) |
  (data[off + 3].to_int() & 0xFF)
}

///|
/// PNG Paeth predictor (filter type 4).
fn png_paeth(a : Int32, b : Int32, c : Int32) -> Int32 {
  let p = a + b - c
  let pa = if p > a { p - a } else { a - p }
  let pb = if p > b { p - b } else { b - p }
  let pc = if p > c { p - c } else { c - p }
  if pa <= pb && pa <= pc {
    a
  } else if pb <= pc {
    b
  } else {
    c
  }
}

///|
/// Helper: pack a FixedArray[Int32] (each 0..255) into Bytes.
pub fn bytes_of_i32(data : FixedArray[Int32]) -> Bytes {
  let buf = Buffer()
  for i = 0; i < data.length(); i = i + 1 {
    buf.write_byte((data[i] & 0xFF).to_byte())
  }
  buf.to_bytes()
}

///|
/// Decode a non-interlaced PNG into a grayscale bitmap (0..255).
/// Supported color types: 0 (gray, bit depth 1/2/4/8), 2 (RGB 8-bit),
/// 4 (gray+alpha 8-bit), 6 (RGBA 8-bit). Returns None for unsupported
/// or corrupt input (interlaced, 16-bit, palette, bad signature, ...).
pub fn decode_png_gray(png : BytesView) -> FixedArray[FixedArray[Int32]]? {
  let n = png.length()
  if n < 8 + 25 {
    return None
  }
  // Signature: 89 50 4E 47 0D 0A 1A 0A
  let sig = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
  for i = 0; i < 8; i = i + 1 {
    if (png[i].to_int() & 0xFF) != sig[i] {
      return None
    }
  }
  // Walk chunks, collecting IHDR fields and concatenated IDAT payload.
  let mut width = 0
  let mut height = 0
  let mut bit_depth = 0
  let mut color_type = 0
  let mut interlace = 0
  let idat = Buffer()
  let mut seen_ihdr = false
  let mut pos = 8
  while pos + 12 <= n {
    let len = png_u32(png, pos)
    if len < 0 || pos + 12 + len > n {
      return None
    }
    let t0 = png[pos + 4].to_int() & 0xFF
    let t1 = png[pos + 5].to_int() & 0xFF
    let t2 = png[pos + 6].to_int() & 0xFF
    let t3 = png[pos + 7].to_int() & 0xFF
    let data_off = pos + 8
    if t0 == 0x49 && t1 == 0x48 && t2 == 0x44 && t3 == 0x52 {
      // IHDR
      if len != 13 {
        return None
      }
      width = png_u32(png, data_off)
      height = png_u32(png, data_off + 4)
      bit_depth = png[data_off + 8].to_int() & 0xFF
      color_type = png[data_off + 9].to_int() & 0xFF
      interlace = png[data_off + 12].to_int() & 0xFF
      seen_ihdr = true
    } else if t0 == 0x49 && t1 == 0x44 && t2 == 0x41 && t3 == 0x54 {
      // IDAT
      for i = 0; i < len; i = i + 1 {
        idat.write_byte(png[data_off + i])
      }
    } else if t0 == 0x49 && t1 == 0x45 && t2 == 0x4E && t3 == 0x44 {
      // IEND
      break
    }
    pos = pos + 12 + len
  }
  if !seen_ihdr || width <= 0 || height <= 0 || idat.length() == 0 {
    return None
  }
  if interlace != 0 {
    return None
  }
  if bit_depth == 16 {
    return None
  }
  let channels = match color_type {
    0 => 1
    2 => 3
    4 => 2
    6 => 4
    _ => return None
  }
  if color_type != 0 && bit_depth != 8 {
    return None
  }
  if color_type == 0 &&
    !(bit_depth == 1 || bit_depth == 2 || bit_depth == 4 || bit_depth == 8) {
    return None
  }
  // zlib-decompress the IDAT payload via the standard library.
  let zbytes = idat.to_bytes()
  let raw : Bytes = @zlib.decompress(zbytes) catch { _ => return None }
  // Unfilter scanlines.
  let bits_per_pixel = channels * bit_depth
  let row_len = (width * bits_per_pixel + 7) / 8
  let bpp = if bits_per_pixel / 8 < 1 { 1 } else { bits_per_pixel / 8 }
  let need = height * (1 + row_len)
  if raw.length() < need {
    return None
  }
  let prev : FixedArray[Int32] = FixedArray::make(row_len, 0)
  let cur : FixedArray[Int32] = FixedArray::make(row_len, 0)
  // Output grayscale bitmap.
  let gray : FixedArray[FixedArray[Int32]] = FixedArray::make(
    height,
    FixedArray::make(width, 255),
  )
  let mut rp = 0
  for y = 0; y < height; y = y + 1 {
    gray[y] = FixedArray::make(width, 255)
    let ft = raw[rp].to_int() & 0xFF
    rp = rp + 1
    if ft > 4 {
      return None
    }
    for i = 0; i < row_len; i = i + 1 {
      let x = raw[rp + i].to_int() & 0xFF
      let a = if i >= bpp { cur[i - bpp] } else { 0 }
      let b = if y > 0 { prev[i] } else { 0 }
      let c = if y > 0 && i >= bpp { prev[i - bpp] } else { 0 }
      let v = match ft {
        0 => x
        1 => x + a
        2 => x + b
        3 => x + (a + b) / 2
        _ => x + png_paeth(a, b, c)
      }
      cur[i] = v & 0xFF
    }
    rp = rp + row_len
    // Expand this scanline to grayscale pixels.
    if color_type == 0 {
      expand_gray_row(cur, gray[y], width, bit_depth)
    } else if color_type == 2 {
      // RGB8 -> luma
      for px = 0; px < width; px = px + 1 {
        let r = cur[px * 3]
        let g = cur[px * 3 + 1]
        let b = cur[px * 3 + 2]
        gray[y][px] = (r * 299 + g * 587 + b * 114) / 1000
      }
    } else if color_type == 4 {
      // gray + alpha: take gray channel
      for px = 0; px < width; px = px + 1 {
        gray[y][px] = cur[px * 2]
      }
    } else {
      // RGBA8 -> luma
      for px = 0; px < width; px = px + 1 {
        let r = cur[px * 4]
        let g = cur[px * 4 + 1]
        let b = cur[px * 4 + 2]
        gray[y][px] = (r * 299 + g * 587 + b * 114) / 1000
      }
    }
    // Current row becomes previous for the next iteration.
    for i = 0; i < row_len; i = i + 1 {
      prev[i] = cur[i]
    }
  }
  Some(gray)
}

///|
/// Expand a grayscale scanline of packed samples into 0..255 pixels.
fn expand_gray_row(
  cur : FixedArray[Int32],
  out : FixedArray[Int32],
  width : Int32,
  bit_depth : Int32,
) -> Unit {
  let maxv = (1 << bit_depth) - 1
  if bit_depth == 8 {
    for px = 0; px < width; px = px + 1 {
      out[px] = cur[px]
    }
    return
  }
  let per_byte = 8 / bit_depth
  for px = 0; px < width; px = px + 1 {
    let byte_idx = px / per_byte
    let shift = (per_byte - 1 - px % per_byte) * bit_depth
    let sample = (cur[byte_idx] >> shift) & maxv
    out[px] = sample * 255 / maxv
  }
}
