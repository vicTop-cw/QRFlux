// Unit tests for GF(256) finite field arithmetic.
// Tests gf_mul, gf_pow, rs_compute_divisor, rs_compute_remainder.
// Primitive polynomial: x^8 + x^4 + x^3 + x^2 + 1 = 0x11D.

///|
/// Helper: make a FixedArray from a literal array of ints.
fn gf_mk(xs : Array[Int32]) -> FixedArray[Int32] {
  let fa = FixedArray::make(xs.length(), 0)
  for i = 0; i < xs.length(); i = i + 1 {
    fa[i] = xs[i]
  }
  fa
}

///|
/// Helper: check two FixedArray[Int32] equal.
fn gf_eq(a : FixedArray[Int32], b : FixedArray[Int32]) -> Bool {
  if a.length() != b.length() {
    return false
  }
  for i = 0; i < a.length(); i = i + 1 {
    if a[i] != b[i] {
      return false
    }
  }
  true
}

///|
/// Helper: check FixedArray is all zeros.
fn gf_is_zero(a : FixedArray[Int32]) -> Bool {
  for i = 0; i < a.length(); i = i + 1 {
    if a[i] != 0 {
      return false
    }
  }
  true
}

///|
test "gf256: mul by zero" {
  // 0 is the absorbing element: x*0 == 0*x == 0.
  for x = 0; x < 256; x = x + 1 {
    assert_true(@qr.gf_mul(x, 0) == 0)
    assert_true(@qr.gf_mul(0, x) == 0)
  }
}

///|
test "gf256: mul by one" {
  // 1 is the multiplicative identity: x*1 == x.
  for x = 0; x < 256; x = x + 1 {
    assert_true(@qr.gf_mul(x, 1) == x)
  }
}

///|
test "gf256: mul commutative" {
  // Specific known pairs.
  assert_true(@qr.gf_mul(2, 3) == @qr.gf_mul(3, 2))
  assert_true(@qr.gf_mul(0x53, 0xCA) == @qr.gf_mul(0xCA, 0x53))
  assert_true(@qr.gf_mul(128, 200) == @qr.gf_mul(200, 128))
  assert_true(@qr.gf_mul(255, 1) == @qr.gf_mul(1, 255))
  assert_true(@qr.gf_mul(15, 240) == @qr.gf_mul(240, 15))
  assert_true(@qr.gf_mul(0xAB, 0xCD) == @qr.gf_mul(0xCD, 0xAB))
  // Full sweep over the field.
  for a = 0; a < 256; a = a + 1 {
    for b = 0; b < 256; b = b + 1 {
      assert_true(@qr.gf_mul(a, b) == @qr.gf_mul(b, a))
    }
  }
}

///|
test "gf256: mul closed" {
  // Product of any two field elements stays in 0..255.
  let values = [0, 1, 2, 3, 15, 128, 200, 255]
  for a = 0; a < 256; a = a + 1 {
    for b in values {
      let r = @qr.gf_mul(a, b)
      assert_true(r >= 0 && r < 256)
    }
  }
}

///|
test "gf256: mul known values" {
  // 2 * 3 = 6: x * (x+1) = x^2 + x = 4 + 2 = 6
  assert_true(@qr.gf_mul(2, 3) == 6)
  // 3 * 3 = 5: (x+1)^2 = x^2 + 1 = 4 + 1 = 5 (cross terms vanish in GF(2))
  assert_true(@qr.gf_mul(3, 3) == 5)
  // 2 * 128 = 29: alpha^1 * alpha^7 = alpha^8 = 0x1D = 29 (reduction by 0x11D)
  assert_true(@qr.gf_mul(2, 128) == 29)
  // 4 * 8 = 32: alpha^2 * alpha^3 = alpha^5 = 32 (no reduction needed)
  assert_true(@qr.gf_mul(4, 8) == 32)
  // 15 * 15 = 85: (x^3+x^2+x+1)^2 = x^6+x^4+x^2+1 = 64+16+4+1 = 85
  assert_true(@qr.gf_mul(15, 15) == 85)
}

///|
test "gf256: mul distributive" {
  // a*(b^c) == (a*b) ^ (a*c)  (XOR is field addition).
  let aa = [2, 0x53, 128, 15, 255, 0xAB]
  let bb = [3, 0xCA, 200, 240, 128, 0xCD]
  let cc = [5, 0x01, 100, 15, 1, 0x12]
  for i = 0; i < aa.length(); i = i + 1 {
    let a = aa[i]
    let b = bb[i]
    let c = cc[i]
    let lhs = @qr.gf_mul(a, b ^ c)
    let rhs = @qr.gf_mul(a, b) ^ @qr.gf_mul(a, c)
    assert_true(lhs == rhs)
  }
  // Sampled sweep for broader coverage.
  for a = 1; a < 256; a = a + 17 {
    for b = 0; b < 256; b = b + 13 {
      for c = 0; c < 256; c = c + 11 {
        let lhs = @qr.gf_mul(a, b ^ c)
        let rhs = @qr.gf_mul(a, b) ^ @qr.gf_mul(a, c)
        assert_true(lhs == rhs)
      }
    }
  }
}

///|
test "gf256: mul associative" {
  // (a*b)*c == a*(b*c).
  let aa = [2, 0x53, 128, 15, 255, 0xAB]
  let bb = [3, 0xCA, 200, 240, 128, 0xCD]
  let cc = [5, 0x01, 100, 15, 1, 0x12]
  for i = 0; i < aa.length(); i = i + 1 {
    let a = aa[i]
    let b = bb[i]
    let c = cc[i]
    let lhs = @qr.gf_mul(@qr.gf_mul(a, b), c)
    let rhs = @qr.gf_mul(a, @qr.gf_mul(b, c))
    assert_true(lhs == rhs)
  }
  // Sampled sweep for broader coverage.
  for a = 1; a < 256; a = a + 23 {
    for b = 1; b < 256; b = b + 19 {
      for c = 1; c < 256; c = c + 17 {
        let lhs = @qr.gf_mul(@qr.gf_mul(a, b), c)
        let rhs = @qr.gf_mul(a, @qr.gf_mul(b, c))
        assert_true(lhs == rhs)
      }
    }
  }
}

///|
test "gf256: mul inverse exists" {
  // Every nonzero element has a multiplicative inverse in GF(256)*.
  for x = 1; x < 256; x = x + 1 {
    let mut found = false
    for y = 1; y < 256; y = y + 1 {
      if @qr.gf_mul(x, y) == 1 {
        found = true
      }
    }
    assert_true(found)
  }
}

///|
test "gf256: pow zero" {
  // x^0 == 1 for all x (including 0 by convention in this implementation).
  for x = 0; x < 256; x = x + 1 {
    assert_true(@qr.gf_pow(x, 0) == 1)
  }
}

///|
test "gf256: pow one" {
  // x^1 == x.
  for x = 0; x < 256; x = x + 1 {
    assert_true(@qr.gf_pow(x, 1) == x)
  }
}

///|
test "gf256: pow additive" {
  // x^(a+b) == x^a * x^b.
  let xs = [2, 3, 128, 5, 0x53]
  let aa = [3, 7, 100, 200, 50]
  let bb = [5, 11, 50, 55, 100]
  for i = 0; i < xs.length(); i = i + 1 {
    let x = xs[i]
    let a = aa[i]
    let b = bb[i]
    let lhs = @qr.gf_pow(x, a + b)
    let rhs = @qr.gf_mul(@qr.gf_pow(x, a), @qr.gf_pow(x, b))
    assert_true(lhs == rhs)
  }
}

///|
test "gf256: generator 2 cycles" {
  // 2 is a primitive element: 2^0..2^254 cycles through all 1..255 exactly once.
  let seen = FixedArray::make(256, false)
  for i = 0; i < 255; i = i + 1 {
    let v = @qr.gf_pow(2, i)
    assert_true(v >= 1 && v <= 255)
    assert_true(seen[v] == false)
    seen[v] = true
  }
  // Every nonzero element must have been visited.
  for v = 1; v < 256; v = v + 1 {
    assert_true(seen[v])
  }
}

///|
test "gf256: pow 255 fermat" {
  // Fermat little theorem in GF(256): x^255 == 1 for all nonzero x,
  // since the multiplicative group GF(256)* has order 255.
  for x = 1; x < 256; x = x + 1 {
    assert_true(@qr.gf_pow(x, 255) == 1)
  }
}

///|
test "gf256: rs divisor degree" {
  // rs_compute_divisor(d) returns array of length d (leading 1 is implicit).
  for d = 1; d < 11; d = d + 1 {
    let div = @qr.rs_compute_divisor(d)
    assert_true(div.length() == d)
  }
}

///|
test "gf256: rs divisor monic" {
  // Known divisor values. The leading coefficient 1 is implicit (excluded).
  // g1(x) = x + 1 = (x - alpha^0), so divisor = [1]
  let div1 = @qr.rs_compute_divisor(1)
  assert_true(gf_eq(div1, gf_mk([1])))
  // g2(x) = x^2 + 3x + 2 = (x - 1)(x - 2), so divisor = [3, 2]
  let div2 = @qr.rs_compute_divisor(2)
  assert_true(gf_eq(div2, gf_mk([3, 2])))
  // Constant term of g1 is alpha^0 = 1 (product of roots), confirming monic.
  assert_true(div1[div1.length() - 1] == 1)
}

///|
test "gf256: rs remainder length" {
  // rs_compute_remainder returns array of length == divisor.length().
  let data = gf_mk([1, 2, 3, 4, 5])
  for d = 1; d < 6; d = d + 1 {
    let div = @qr.rs_compute_divisor(d)
    let rem = @qr.rs_compute_remainder(data, div)
    assert_true(rem.length() == div.length())
  }
}

///|
test "gf256: rs remainder zero for codeword" {
  // For degree 2, g(x) = x^2 + 3x + 2, divisor = [3, 2].
  // m(x) = 1 -> c(x) = g(x) -> data = [1, 3, 2]
  let div = @qr.rs_compute_divisor(2)
  let cw1 = gf_mk([1, 3, 2])
  let rem1 = @qr.rs_compute_remainder(cw1, div)
  assert_true(gf_is_zero(rem1))
  // m(x) = x + 1 -> c(x) = (x+1)*g(x) = x^3 + 2x^2 + x + 2 -> data = [1, 2, 1, 2]
  let cw2 = gf_mk([1, 2, 1, 2])
  let rem2 = @qr.rs_compute_remainder(cw2, div)
  assert_true(gf_is_zero(rem2))
  // Degree 5: m(x) = 1 -> c(x) = g(x) coefficients = [1, div5[0..4]]
  let div5 = @qr.rs_compute_divisor(5)
  let cw5 = FixedArray::make(6, 0)
  cw5[0] = 1
  for i = 0; i < 5; i = i + 1 {
    cw5[i + 1] = div5[i]
  }
  let rem5 = @qr.rs_compute_remainder(cw5, div5)
  assert_true(gf_is_zero(rem5))
}

///|
test "gf256: rs remainder nonzero for error" {
  // Corrupt a valid codeword; remainder must be nonzero (error detected).
  let div = @qr.rs_compute_divisor(2)
  // Valid codeword is [1, 3, 2]; corrupt last byte -> [1, 3, 3]
  let corrupted = gf_mk([1, 3, 3])
  let rem = @qr.rs_compute_remainder(corrupted, div)
  assert_true(gf_is_zero(rem) == false)
  // Corrupt middle byte -> [1, 2, 2]
  let corrupted2 = gf_mk([1, 2, 2])
  let rem2 = @qr.rs_compute_remainder(corrupted2, div)
  assert_true(gf_is_zero(rem2) == false)
  // Corrupt first byte -> [0, 3, 2]
  let corrupted3 = gf_mk([0, 3, 2])
  let rem3 = @qr.rs_compute_remainder(corrupted3, div)
  assert_true(gf_is_zero(rem3) == false)
}
