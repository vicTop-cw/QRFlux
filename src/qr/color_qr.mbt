// Color QR code prototype for QRFlux.
// Implements 4-color QR (2 bits/module) using color overlay.

///|
/// Color mapping for 4-color QR.
/// Each color represents 2 bits of data.
pub enum ColorQRColor {
  White // 00 - 0xFFFFFF
  Red // 01 - 0xFF0000
  Green // 10 - 0x00FF00
  Blue // 11 - 0x0000FF
} derive(Eq, Debug)

///|
pub extend ColorQRColor with Eq::{not_equal, equal}

///|
pub extend ColorQRColor with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// Convenience constructors.
pub fn color_white() -> ColorQRColor {
  White
}

///|
pub fn color_red() -> ColorQRColor {
  Red
}

///|
pub fn color_green() -> ColorQRColor {
  Green
}

///|
pub fn color_blue() -> ColorQRColor {
  Blue
}

///|
/// Encode 2 bits of data into a color.
pub fn ColorQRColor::from_bits(bits : Int32) -> ColorQRColor {
  match bits {
    0 => White
    1 => Red
    2 => Green
    _ => Blue
  }
}

///|
/// Decode color back to 2 bits.
pub fn ColorQRColor::to_bits(color : ColorQRColor) -> Int32 {
  match color {
    White => 0
    Red => 1
    Green => 2
    Blue => 3
  }
}

///|
/// Get RGB value for a color.
pub fn ColorQRColor::to_rgb(color : ColorQRColor) -> (Int32, Int32, Int32) {
  match color {
    White => (255, 255, 255)
    Red => (255, 0, 0)
    Green => (0, 255, 0)
    Blue => (0, 0, 255)
  }
}

///|
/// Color QR encoder.
/// Encodes data into a 2x module grid with colors.
pub struct ColorQREncoder {
  version : Int32
  size : Int32
}

///|
/// Create a new Color QR encoder.
pub fn ColorQREncoder::new(version : Int32) -> ColorQREncoder {
  let size = version * 4 + 17
  { version, size, }
}

///|
/// Encode data into Color QR matrix.
/// Returns: 2D array of colors.
pub fn ColorQREncoder::encode(
  self : ColorQREncoder,
  data : FixedArray[Int32],
) -> FixedArray[FixedArray[ColorQRColor]] {
  // Initialize with white
  let matrix = FixedArray::make(self.size, FixedArray::make(self.size, White))

  // Encode data into 2x2 blocks (each block stores 4 bits = 2 colors)
  let mut data_idx = 0
  for block_y = 0; block_y < self.size / 2; block_y = block_y + 1 {
    for block_x = 0; block_x < self.size / 2; block_x = block_x + 1 {
      if data_idx < data.length() {
        let byte = data[data_idx]

        // Encode 4 bits into 2 colors
        let color1 = ColorQRColor::from_bits((byte >> 4) & 0x03)
        let color2 = ColorQRColor::from_bits(byte & 0x03)

        // Set 2x2 block
        let x = block_x * 2
        let y = block_y * 2

        if x < self.size && y < self.size {
          matrix[y][x] = color1
        }
        if x + 1 < self.size && y < self.size {
          matrix[y][x + 1] = color2
        }
        if x < self.size && y + 1 < self.size {
          matrix[y + 1][x] = color1
        }
        if x + 1 < self.size && y + 1 < self.size {
          matrix[y + 1][x + 1] = color2
        }

        data_idx = data_idx + 1
      }
    }
  }

  matrix
}

///|
/// Decode Color QR matrix back to data.
pub fn ColorQREncoder::decode(
  self : ColorQREncoder,
  matrix : FixedArray[FixedArray[ColorQRColor]],
) -> FixedArray[Int32]? {
  let result = Array::make(0, 0)

  // Decode from 2x2 blocks
  for block_y = 0; block_y < self.size / 2; block_y = block_y + 1 {
    for block_x = 0; block_x < self.size / 2; block_x = block_x + 1 {
      let x = block_x * 2
      let y = block_y * 2

      if x < self.size && y < self.size {
        let color1 = matrix[y][x]
        let bits1 = ColorQRColor::to_bits(color1)

        let mut bits2 = 0
        if x + 1 < self.size && y < self.size {
          bits2 = ColorQRColor::to_bits(matrix[y][x + 1])
        }

        let byte = (bits1 << 4) | bits2
        result.push(byte)
      }
    }
  }

  let output = FixedArray::make(result.length(), 0)
  for i = 0; i < result.length(); i = i + 1 {
    output[i] = result[i]
  }
  Some(output)
}
