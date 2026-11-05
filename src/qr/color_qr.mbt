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
/// Each 2x2 block stores 4 colors = 8 bits = 1 byte (lossless).
pub fn ColorQREncoder::encode(
  self : ColorQREncoder,
  data : FixedArray[Int32],
) -> FixedArray[FixedArray[ColorQRColor]] {
  // Initialize with white (independent rows to avoid shared reference)
  let matrix = FixedArray::make(self.size, FixedArray::make(self.size, White))
  for y = 0; y < self.size; y = y + 1 {
    matrix[y] = FixedArray::make(self.size, White)
  }

  // Encode data into 2x2 blocks (each block stores 4 colors = 1 byte)
  let mut data_idx = 0
  for block_y = 0; block_y < self.size / 2; block_y = block_y + 1 {
    for block_x = 0; block_x < self.size / 2; block_x = block_x + 1 {
      if data_idx < data.length() {
        let byte = data[data_idx]

        // Encode 8 bits into 4 colors (2 bits each)
        let c0 = ColorQRColor::from_bits((byte >> 6) & 0x03)
        let c1 = ColorQRColor::from_bits((byte >> 4) & 0x03)
        let c2 = ColorQRColor::from_bits((byte >> 2) & 0x03)
        let c3 = ColorQRColor::from_bits(byte & 0x03)

        // Set 2x2 block
        let x = block_x * 2
        let y = block_y * 2

        if x < self.size && y < self.size {
          matrix[y][x] = c0
        }
        if x + 1 < self.size && y < self.size {
          matrix[y][x + 1] = c1
        }
        if x < self.size && y + 1 < self.size {
          matrix[y + 1][x] = c2
        }
        if x + 1 < self.size && y + 1 < self.size {
          matrix[y + 1][x + 1] = c3
        }

        data_idx = data_idx + 1
      }
    }
  }

  matrix
}

///|
/// Decode Color QR matrix back to data.
/// Each 2x2 block stores 4 colors = 8 bits = 1 byte (lossless).
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
        let b0 = ColorQRColor::to_bits(matrix[y][x])
        let mut b1 = 0
        let mut b2 = 0
        let mut b3 = 0
        if x + 1 < self.size && y < self.size {
          b1 = ColorQRColor::to_bits(matrix[y][x + 1])
        }
        if x < self.size && y + 1 < self.size {
          b2 = ColorQRColor::to_bits(matrix[y + 1][x])
        }
        if x + 1 < self.size && y + 1 < self.size {
          b3 = ColorQRColor::to_bits(matrix[y + 1][x + 1])
        }
        let byte = (b0 << 6) | (b1 << 4) | (b2 << 2) | b3
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

///|
/// Identify color from RGB values (with threshold 128).
/// White: r>128 && g>128 && b>128
/// Red:   r>128 && g<=128 && b<=128
/// Green: r<=128 && g>128 && b<=128
/// Blue:  otherwise
pub fn ColorQRColor::from_rgb(r : Int32, g : Int32, b : Int32) -> ColorQRColor {
  if r > 128 && g > 128 && b > 128 {
    White
  } else if r > 128 && g <= 128 && b <= 128 {
    Red
  } else if r <= 128 && g > 128 && b <= 128 {
    Green
  } else {
    Blue
  }
}

///|
/// Decode color QR from an RGB matrix.
/// Each cell is an (r, g, b) tuple. Converts to colors then decodes.
pub fn decode_color_from_rgb(
  rgb_matrix : FixedArray[FixedArray[(Int32, Int32, Int32)]],
  version : Int32,
) -> FixedArray[Int32]? {
  let size = version * 4 + 17
  if rgb_matrix.length() != size {
    return None
  }
  let color_matrix = FixedArray::make(size, FixedArray::make(size, White))
  for y = 0; y < size; y = y + 1 {
    color_matrix[y] = FixedArray::make(size, White)
    for x = 0; x < size; x = x + 1 {
      let (r, g, b) = rgb_matrix[y][x]
      color_matrix[y][x] = ColorQRColor::from_rgb(r, g, b)
    }
  }
  let encoder = ColorQREncoder::new(version)
  encoder.decode(color_matrix)
}

///|
/// Generate SVG image from color QR matrix.
pub fn color_qr_to_svg(
  matrix : FixedArray[FixedArray[ColorQRColor]],
  scale : Int32,
  quiet_zone : Int32,
) -> String {
  let size = matrix.length()
  let total = size + quiet_zone * 2
  let mut svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"" +
    (total * scale).to_string() +
    "\" height=\"" +
    (total * scale).to_string() +
    "\">"
  svg = svg + "<rect width=\"100%\" height=\"100%\" fill=\"white\"/>"
  for y = 0; y < size; y = y + 1 {
    for x = 0; x < size; x = x + 1 {
      let color = matrix[y][x]
      if color != White {
        let (r, g, b) = ColorQRColor::to_rgb(color)
        svg = svg +
          "<rect x=\"" +
          ((x + quiet_zone) * scale).to_string() +
          "\" y=\"" +
          ((y + quiet_zone) * scale).to_string() +
          "\" width=\"" +
          scale.to_string() +
          "\" height=\"" +
          scale.to_string() +
          "\" fill=\"rgb(" +
          r.to_string() +
          "," +
          g.to_string() +
          "," +
          b.to_string() +
          ")\"/>"
      }
    }
  }
  svg = svg + "</svg>"
  svg
}

///|
/// Generate PPM (P3, color) image from color QR matrix.
pub fn color_qr_to_ppm(
  matrix : FixedArray[FixedArray[ColorQRColor]],
  quiet_zone : Int32,
) -> String {
  let size = matrix.length()
  let total = size + quiet_zone * 2
  let mut ppm = "P3\n" + total.to_string() + " " + total.to_string() + "\n255\n"
  // Top quiet zone
  for y = 0; y < quiet_zone; y = y + 1 {
    for x = 0; x < total; x = x + 1 {
      ppm = ppm + "255 255 255 "
    }
    ppm = ppm + "\n"
  }
  // Matrix rows with side quiet zones
  for y = 0; y < size; y = y + 1 {
    for x = 0; x < quiet_zone; x = x + 1 {
      ppm = ppm + "255 255 255 "
    }
    for x = 0; x < size; x = x + 1 {
      let (r, g, b) = ColorQRColor::to_rgb(matrix[y][x])
      ppm = ppm +
        r.to_string() +
        " " +
        g.to_string() +
        " " +
        b.to_string() +
        " "
    }
    for x = 0; x < quiet_zone; x = x + 1 {
      ppm = ppm + "255 255 255 "
    }
    ppm = ppm + "\n"
  }
  // Bottom quiet zone
  for y = 0; y < quiet_zone; y = y + 1 {
    for x = 0; x < total; x = x + 1 {
      ppm = ppm + "255 255 255 "
    }
    ppm = ppm + "\n"
  }
  ppm
}
