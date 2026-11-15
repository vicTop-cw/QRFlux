/// Tests for the BMP decoder: hand-built BMPs with known pixels,
/// round-tripped through decode_bmp_gray, plus rejection cases.

///|
/// Write a little-endian 32-bit value (two's complement for negatives).
fn bmp_w32(buf : Buffer, v : Int32) -> Unit {
  buf.write_byte((v & 0xFF).to_byte())
  buf.write_byte(((v >> 8) & 0xFF).to_byte())
  buf.write_byte(((v >> 16) & 0xFF).to_byte())
  buf.write_byte(((v >> 24) & 0xFF).to_byte())
}

///|
/// Write a little-endian 16-bit value.
fn bmp_w16(buf : Buffer, v : Int32) -> Unit {
  buf.write_byte((v & 0xFF).to_byte())
  buf.write_byte(((v >> 8) & 0xFF).to_byte())
}

///|
/// Build a BMP file from image-space pixels (row-major, top-down
/// semantics). pix encodes each pixel as: 24/32 bpp -> r<<16|g<<8|b,
/// bpp<=8 -> palette index.
fn bmp_build(
  width : Int32,
  height : Int32,
  bpp : Int32,
  palette : Array[Int32],
  pix : Array[Int32],
  top_down : Bool,
) -> Bytes {
  let palette_count = if bpp <= 8 { palette.length() } else { 0 }
  let palette_size = palette_count * 4
  let row_len = (width * bpp + 7) / 8
  let stride = (row_len + 3) / 4 * 4
  let data_offset = 14 + 40 + palette_size
  let buf = Buffer()
  // BITMAPFILEHEADER
  buf.write_byte(b'B')
  buf.write_byte(b'M')
  bmp_w32(buf, data_offset + stride * height)
  bmp_w32(buf, 0)
  bmp_w32(buf, data_offset)
  // BITMAPINFOHEADER
  bmp_w32(buf, 40)
  bmp_w32(buf, width)
  bmp_w32(buf, if top_down { -height } else { height })
  bmp_w16(buf, 1)
  bmp_w16(buf, bpp)
  bmp_w32(buf, 0)
  bmp_w32(buf, 0)
  bmp_w32(buf, 0)
  bmp_w32(buf, 0)
  bmp_w32(buf, palette_count)
  bmp_w32(buf, 0)
  // palette (BGRX)
  for i = 0; i < palette_count; i = i + 1 {
    let c = palette[i]
    buf.write_byte((c & 0xFF).to_byte())
    buf.write_byte(((c >> 8) & 0xFF).to_byte())
    buf.write_byte(((c >> 16) & 0xFF).to_byte())
    buf.write_byte(b'\x00')
  }
  // pixel rows: file stores bottom-up unless top_down
  for row = 0; row < height; row = row + 1 {
    let y = if top_down { row } else { height - 1 - row }
    if bpp == 24 || bpp == 32 {
      for x = 0; x < width; x = x + 1 {
        let v = pix[y * width + x]
        buf.write_byte((v & 0xFF).to_byte())
        buf.write_byte(((v >> 8) & 0xFF).to_byte())
        buf.write_byte(((v >> 16) & 0xFF).to_byte())
        if bpp == 32 {
          buf.write_byte(b'\xFF')
        }
      }
    } else if bpp == 8 {
      for x = 0; x < width; x = x + 1 {
        buf.write_byte((pix[y * width + x] & 0xFF).to_byte())
      }
    } else {
      // bpp == 1: packed bits, MSB first
      for byte_i = 0; byte_i < row_len; byte_i = byte_i + 1 {
        let mut byte_val = 0
        for bit_i = 0; bit_i < 8; bit_i = bit_i + 1 {
          let x = byte_i * 8 + bit_i
          if x < width && pix[y * width + x] != 0 {
            byte_val = byte_val | (1 << (7 - bit_i))
          }
        }
        buf.write_byte(byte_val.to_byte())
      }
    }
    for p = row_len; p < stride; p = p + 1 {
      buf.write_byte(b'\x00')
    }
  }
  buf.to_bytes()
}

///|
/// Return a copy of `bmp` with the byte at `idx` replaced.
fn bmp_with_byte(bmp : Bytes, idx : Int32, val : Int32) -> Bytes {
  let n = bmp.length()
  let arr : FixedArray[Byte] = FixedArray::make(n, b'\x00')
  for i = 0; i < n; i = i + 1 {
    arr[i] = bmp[i]
  }
  if idx >= 0 && idx < n {
    arr[idx] = (val & 0xFF).to_byte()
  }
  Bytes::from_array(arr)
}

///|
/// Return a truncated copy of `bmp` keeping only the first `keep` bytes.
fn bmp_truncated(bmp : Bytes, keep : Int32) -> Bytes {
  let n = bmp.length()
  let k = if keep < 0 { 0 } else if keep > n { n } else { keep }
  let arr : FixedArray[Byte] = FixedArray::make(k, b'\x00')
  for i = 0; i < k; i = i + 1 {
    arr[i] = bmp[i]
  }
  Bytes::from_array(arr)
}

///|
/// Expected luma for an RGB triple, matching the decoder's formula.
fn bmp_luma(r : Int32, g : Int32, b : Int32) -> Int32 {
  (r * 299 + g * 587 + b * 114) / 1000
}

///|
test "bmp 24bit bottom-up roundtrip" {
  // 3x2 image, top-down semantics: row0 = R,G,B; row1 = white,black,white
  let pix : Array[Int32] = [
    0xFF0000, 0x00FF00, 0x0000FF, 0xFFFFFF, 0x000000, 0xFFFFFF,
  ]
  let bmp = bmp_build(3, 2, 24, [], pix, false)
  let gray = match @qr.decode_bmp_gray(bmp) {
    Some(g) => g
    None => abort("24-bit BMP decode failed")
  }
  assert_true(gray.length() == 2)
  assert_true(gray[0][0] == bmp_luma(255, 0, 0))
  assert_true(gray[0][1] == bmp_luma(0, 255, 0))
  assert_true(gray[0][2] == bmp_luma(0, 0, 255))
  assert_true(gray[1][0] == bmp_luma(255, 255, 255))
  assert_true(gray[1][1] == 0)
  assert_true(gray[1][2] == bmp_luma(255, 255, 255))
}

///|
test "bmp 32bit bgra roundtrip" {
  let pix : Array[Int32] = [0x0000FF, 0xFFFFFF]
  let bmp = bmp_build(2, 1, 32, [], pix, false)
  let gray = match @qr.decode_bmp_gray(bmp) {
    Some(g) => g
    None => abort("32-bit BMP decode failed")
  }
  assert_true(gray.length() == 1)
  assert_true(gray[0][0] == bmp_luma(0, 0, 255))
  assert_true(gray[0][1] == bmp_luma(255, 255, 255))
}

///|
test "bmp 8bit palette roundtrip" {
  // palette: 0=black 1=white 2=mid-gray
  let palette : Array[Int32] = [0x000000, 0xFFFFFF, 0x808080]
  // 4x1 image: black white gray white
  let pix : Array[Int32] = [0, 1, 2, 1]
  let bmp = bmp_build(4, 1, 8, palette, pix, false)
  let gray = match @qr.decode_bmp_gray(bmp) {
    Some(g) => g
    None => abort("8-bit BMP decode failed")
  }
  assert_true(gray.length() == 1)
  assert_true(gray[0][0] == 0)
  assert_true(gray[0][1] == 255)
  assert_true(gray[0][2] == bmp_luma(128, 128, 128))
  assert_true(gray[0][3] == 255)
}

///|
test "bmp 1bit mono stripes" {
  // palette: 0=white 1=black; alternating 8x8 stripe pattern
  let palette : Array[Int32] = [0xFFFFFF, 0x000000]
  let pix : Array[Int32] = []
  for y = 0; y < 8; y = y + 1 {
    for x = 0; x < 8; x = x + 1 {
      pix.push(if y % 2 == 0 { 1 } else { 0 })
    }
  }
  let bmp = bmp_build(8, 8, 1, palette, pix, false)
  let gray = match @qr.decode_bmp_gray(bmp) {
    Some(g) => g
    None => abort("1-bit BMP decode failed")
  }
  assert_true(gray.length() == 8)
  assert_true(gray[0][0] == 0)
  assert_true(gray[1][0] == 255)
  assert_true(gray[7][7] == 255)
}

///|
test "bmp top-down negative height" {
  let pix : Array[Int32] = [0xFF0000, 0x00FF00]
  // top_down: file rows appear in image order
  let bmp = bmp_build(2, 1, 24, [], pix, true)
  let gray = match @qr.decode_bmp_gray(bmp) {
    Some(g) => g
    None => abort("top-down BMP decode failed")
  }
  assert_true(gray[0][0] == bmp_luma(255, 0, 0))
  assert_true(gray[0][1] == bmp_luma(0, 255, 0))
}

///|
test "bmp bad signature returns None" {
  let pix : Array[Int32] = [0xFFFFFF]
  let bmp = bmp_build(1, 1, 24, [], pix, false)
  let corrupt = bmp_with_byte(bmp, 0, 0x00)
  assert_true(@qr.decode_bmp_gray(corrupt) is None)
}

///|
/// Mechanism check: flipping compression to BI_RLE8 must be rejected
/// (RLE decoding is out of scope and must not be silently mis-decoded).
test "bmp RLE compression rejected" {
  let pix : Array[Int32] = [0xFFFFFF]
  let bmp = bmp_build(1, 1, 24, [], pix, false)
  let corrupt = bmp_with_byte(bmp, 30, 1)
  assert_true(@qr.decode_bmp_gray(corrupt) is None)
}

///|
test "bmp 16bpp rejected" {
  let pix : Array[Int32] = [0xFFFF]
  let bmp = bmp_build(1, 1, 16, [], pix, false)
  assert_true(@qr.decode_bmp_gray(bmp) is None)
}

///|
test "bmp truncated returns None" {
  let pix : Array[Int32] = [0xFFFFFF, 0x000000, 0xFF0000, 0x00FF00]
  let bmp = bmp_build(2, 2, 24, [], pix, false)
  assert_true(@qr.decode_bmp_gray(bmp_truncated(bmp, 20)) is None)
}
