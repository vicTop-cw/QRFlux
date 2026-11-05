// Unit tests for BitBuffer bit-stream operations.
// Tests BitBuffer::new, length, append_bits, append_bytes, bit_at, to_bytes.

///|
/// Helper: make a FixedArray from a literal array of ints.
fn bits_mk(xs : Array[Int32]) -> FixedArray[Int32] {
  let fa = FixedArray::make(xs.length(), 0)
  for i = 0; i < xs.length(); i = i + 1 {
    fa[i] = xs[i]
  }
  fa
}

///|
/// Helper: check two FixedArray[Int32] equal.
fn bits_eq(a : FixedArray[Int32], b : FixedArray[Int32]) -> Bool {
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
test "bits: new empty" {
  let buf = @qr.BitBuffer::new()
  assert_true(buf.length() == 0)
}

///|
test "bits: new to_bytes empty" {
  let buf = @qr.BitBuffer::new()
  let bytes = buf.to_bytes()
  assert_true(bytes.length() == 0)
}

///|
test "bits: append single bit" {
  let buf = @qr.BitBuffer::new()
  buf.append_bits(1, 1)
  assert_true(buf.length() == 1)
  assert_true(buf.bit_at(0) == 1)
}

///|
test "bits: append zero bit" {
  let buf = @qr.BitBuffer::new()
  buf.append_bits(0, 1)
  assert_true(buf.length() == 1)
  assert_true(buf.bit_at(0) == 0)
}

///|
test "bits: append multiple bits" {
  let buf = @qr.BitBuffer::new()
  buf.append_bits(0b1010, 4)
  assert_true(buf.length() == 4)
  assert_true(buf.bit_at(0) == 1)
  assert_true(buf.bit_at(1) == 0)
  assert_true(buf.bit_at(2) == 1)
  assert_true(buf.bit_at(3) == 0)
}

///|
test "bits: append bits cumulative" {
  // Consecutive append_bits calls accumulate length correctly.
  let buf = @qr.BitBuffer::new()
  buf.append_bits(0, 1)
  assert_true(buf.length() == 1)
  buf.append_bits(1, 1)
  assert_true(buf.length() == 2)
  buf.append_bits(0b11, 2)
  assert_true(buf.length() == 4)
  buf.append_bits(0b1010, 4)
  assert_true(buf.length() == 8)
  buf.append_bits(0xFF, 8)
  assert_true(buf.length() == 16)
}

///|
test "bits: append bits 8" {
  let buf = @qr.BitBuffer::new()
  buf.append_bits(0xFF, 8)
  assert_true(buf.length() == 8)
  let bytes = buf.to_bytes()
  assert_true(bytes.length() == 1)
  assert_true(bytes[0] == 0xFF)
}

///|
test "bits: append single byte" {
  let buf = @qr.BitBuffer::new()
  buf.append_bytes(bits_mk([0x42]))
  assert_true(buf.length() == 8)
  let bytes = buf.to_bytes()
  assert_true(bytes.length() == 1)
  assert_true(bytes[0] == 0x42)
}

///|
test "bits: append multiple bytes" {
  let buf = @qr.BitBuffer::new()
  buf.append_bytes(bits_mk([0x01, 0x02, 0x03]))
  assert_true(buf.length() == 24)
  let bytes = buf.to_bytes()
  assert_true(bits_eq(bytes, bits_mk([0x01, 0x02, 0x03])))
}

///|
test "bits: bit at bounds" {
  let buf = @qr.BitBuffer::new()
  buf.append_bits(0b1100, 4)
  assert_true(buf.bit_at(0) == 1)
  assert_true(buf.bit_at(1) == 1)
  assert_true(buf.bit_at(2) == 0)
  assert_true(buf.bit_at(3) == 0)
}

///|
test "bits: bit at after multiple appends" {
  let buf = @qr.BitBuffer::new()
  buf.append_bits(0b101, 3) // bits 0..2: 1,0,1
  buf.append_bits(0b00, 2) // bits 3..4: 0,0
  buf.append_bits(0b1111, 4) // bits 5..8: 1,1,1,1
  assert_true(buf.length() == 9)
  assert_true(buf.bit_at(0) == 1)
  assert_true(buf.bit_at(1) == 0)
  assert_true(buf.bit_at(2) == 1)
  assert_true(buf.bit_at(3) == 0)
  assert_true(buf.bit_at(4) == 0)
  assert_true(buf.bit_at(5) == 1)
  assert_true(buf.bit_at(6) == 1)
  assert_true(buf.bit_at(7) == 1)
  assert_true(buf.bit_at(8) == 1)
}

///|
test "bits: to bytes roundtrip" {
  let data = bits_mk([0x00, 0x01, 0x7F, 0x80, 0xFF, 0x42, 0xAA, 0x55])
  let buf = @qr.BitBuffer::new()
  buf.append_bytes(data)
  let bytes = buf.to_bytes()
  assert_true(bits_eq(bytes, data))
}

///|
test "bits: to bytes partial byte" {
  // append_bits(0b101, 3) -> bits [1,0,1] -> to_bytes packs MSB first.
  // result[0] = 1<<7 | 0<<6 | 1<<5 = 128 + 32 = 160 = 0xA0 (low 5 bits zero-padded)
  let buf = @qr.BitBuffer::new()
  buf.append_bits(0b101, 3)
  assert_true(buf.length() == 3)
  let bytes = buf.to_bytes()
  assert_true(bytes.length() == 1)
  assert_true(bytes[0] == 0xA0)
}

///|
test "bits: mixed appends" {
  let buf = @qr.BitBuffer::new()
  buf.append_bits(0b1100, 4) // bits 0..3: 1,1,0,0
  buf.append_bytes(bits_mk([0xF0])) // bits 4..11: 1,1,1,1,0,0,0,0
  assert_true(buf.length() == 12)
  assert_true(buf.bit_at(0) == 1)
  assert_true(buf.bit_at(1) == 1)
  assert_true(buf.bit_at(2) == 0)
  assert_true(buf.bit_at(3) == 0)
  assert_true(buf.bit_at(4) == 1)
  assert_true(buf.bit_at(5) == 1)
  assert_true(buf.bit_at(6) == 1)
  assert_true(buf.bit_at(7) == 1)
  assert_true(buf.bit_at(8) == 0)
  assert_true(buf.bit_at(9) == 0)
  assert_true(buf.bit_at(10) == 0)
  assert_true(buf.bit_at(11) == 0)
  // to_bytes: byte0 = 0b11001111 = 0xCF, byte1 = 0b00000000 = 0x00
  let bytes = buf.to_bytes()
  assert_true(bytes.length() == 2)
  assert_true(bytes[0] == 0xCF)
  assert_true(bytes[1] == 0x00)
}

///|
test "bits: large bitstream" {
  let buf = @qr.BitBuffer::new()
  let data = FixedArray::make(100, 0)
  for i = 0; i < 100; i = i + 1 {
    data[i] = (i * 7 + 13) & 0xFF
  }
  buf.append_bytes(data)
  assert_true(buf.length() == 800)
  let bytes = buf.to_bytes()
  assert_true(bytes.length() == 100)
  assert_true(bits_eq(bytes, data))
}
