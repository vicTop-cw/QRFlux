/// Appendable bit buffer for QR data segments.

pub struct BitBuffer {
  bits : Array[Int]
}

pub fn BitBuffer::new() -> BitBuffer {
  { bits: [] }
}

pub fn BitBuffer::length(self : BitBuffer) -> Int {
  self.bits.length()
}

/// Append the low n bits of val (0 <= val < 2^n), most significant first.
pub fn BitBuffer::append_bits(self : BitBuffer, val : Int, n : Int) -> Unit {
  for i = n - 1; i >= 0; i = i - 1 {
    self.bits.push((val >> i) & 1)
  }
}

/// Append the low n bits of val from a byte array, MSB first per byte.
pub fn BitBuffer::append_bytes(self : BitBuffer, data : FixedArray[Int]) -> Unit {
  for b in data {
    self.append_bits(b, 8)
  }
}

pub fn BitBuffer::bit_at(self : BitBuffer, i : Int) -> Int {
  self.bits[i]
}

pub fn BitBuffer::to_bytes(self : BitBuffer) -> FixedArray[Int] {
  let n = self.bits.length()
  let result = FixedArray::make((n + 7) / 8, 0)
  for i = 0; i < n; i = i + 1 {
    result[i >> 3] = result[i >> 3] | (self.bits[i] << (7 - (i & 7)))
  }
  result
}
