/// GF(256) finite field arithmetic over GF(2^8) with polynomial 0x11D.
/// Reed-Solomon error correction for QR uses this field.
/// Implemented from the ISO/IEC 18004 algorithm description.

/// Multiply two field elements modulo GF(2^8/0x11D) using Russian peasant multiplication.
pub fn gf_mul(x : Int, y : Int) -> Int {
  let mut z = 0
  let yy = y
  for i = 7; i >= 0; i = i - 1 {
    z = (z << 1) ^ ((z >> 7) * 0x11D)
    if ((yy >> i) & 1) == 1 {
      z = z ^ x
    }
  }
  z & 0xFF
}

/// Raise a field element to the given non-negative power.
pub fn gf_pow(x : Int, power : Int) -> Int {
  let mut result = 1
  let mut base = x
  let mut p = power
  while p > 0 {
    if (p & 1) == 1 {
      result = gf_mul(result, base)
    }
    base = gf_mul(base, base)
    p = p >> 1
  }
  result
}

/// Compute the Reed-Solomon generator polynomial for the given degree.
/// Returns coefficients from highest power down, excluding the leading 1.
pub fn rs_compute_divisor(degree : Int) -> FixedArray[Int] {
  let result = FixedArray::make(degree, 0)
  result[degree - 1] = 1
  let mut root = 1
  for _i = 0; _i < degree; _i = _i + 1 {
    for j = 0; j < degree; j = j + 1 {
      result[j] = gf_mul(result[j], root)
      if (j + 1) < degree {
        result[j] = result[j] ^ result[j + 1]
      }
    }
    root = gf_mul(root, 0x02)
  }
  result
}

/// Compute the Reed-Solomon remainder (error correction codewords) of data
/// divided by the generator polynomial.
pub fn rs_compute_remainder(data : FixedArray[Int], divisor : FixedArray[Int]) -> FixedArray[Int] {
  let dlen = data.length()
  let divlen = divisor.length()
  let result = FixedArray::make(divlen, 0)
  for i = 0; i < dlen; i = i + 1 {
    let factor = data[i] ^ result[0]
    for j = 0; j < divlen - 1; j = j + 1 {
      result[j] = result[j + 1]
    }
    result[divlen - 1] = 0
    if factor != 0 {
      for j = 0; j < divlen; j = j + 1 {
        result[j] = result[j] ^ gf_mul(divisor[j], factor)
      }
    }
  }
  result
}
