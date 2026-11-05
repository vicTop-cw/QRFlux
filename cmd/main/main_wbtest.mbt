// CLI helper function tests for cmd/main (whitebox).
// Tests parse_int, hex_digit, hex2, ecl_from_name, hex_val, hex_to_bytes,
// byte_capacity, gen_zero, gen_ff, utf8_to_bytes, base64_encode, and
// integration with @qr.encode_binary.
//
// NOTE: Uses _wbtest.mbt (whitebox) suffix because cmd/main is an executable
// package where _test.mbt (blackbox) cannot access package-private helpers
// like parse_int, hex2, hex_digit, ecl_from_name.

///|
test "cli: parse_int normal" {
  assert_true(parse_int("123") == Some(123))
  assert_true(parse_int("0") == Some(0))
  assert_true(parse_int("99999") == Some(99999))
}

///|
test "cli: parse_int empty" {
  assert_true(parse_int("") == None)
}

///|
test "cli: parse_int non-digit" {
  assert_true(parse_int("12a") == None)
  assert_true(parse_int("abc") == None)
  assert_true(parse_int(" 12") == None)
}

///|
test "cli: parse_int boundary" {
  assert_true(parse_int("1") == Some(1))
  assert_true(parse_int("1000000") == Some(1000000))
}

///|
test "cli: parse_int with leading zeros" {
  assert_true(parse_int("007") == Some(7))
  assert_true(parse_int("000") == Some(0))
}

///|
test "cli: hex_digit 0-9" {
  assert_true(hex_digit(0) == "0")
  assert_true(hex_digit(9) == "9")
}

///|
test "cli: hex_digit 10-15" {
  assert_true(hex_digit(10) == "a")
  assert_true(hex_digit(15) == "f")
}

///|
test "cli: hex2 various" {
  assert_true(hex2(0) == "00")
  assert_true(hex2(255) == "ff")
  assert_true(hex2(16) == "10")
  assert_true(hex2(171) == "ab")
}

///|
test "cli: hex2 all nibbles" {
  let mut all_ok = true
  for b = 0; b < 256; b = b + 1 {
    let s = hex2(b)
    if s.length() != 2 {
      all_ok = false
    }
  }
  assert_true(all_ok)
}

///|
test "cli: ecl_from_name valid" {
  assert_true(ecl_from_name("L") == @qr.ecc_low())
  assert_true(ecl_from_name("M") == @qr.ecc_medium())
  assert_true(ecl_from_name("Q") == @qr.ecc_quartile())
  assert_true(ecl_from_name("H") == @qr.ecc_high())
}

///|
test "cli: ecl_from_name invalid defaults to H" {
  assert_true(ecl_from_name("X") == @qr.ecc_high())
  assert_true(ecl_from_name("") == @qr.ecc_high())
  assert_true(ecl_from_name("l") == @qr.ecc_high())
}

///|
test "cli: ecl_from_name all four" {
  let names = ["L", "M", "Q", "H"]
  let levels = [
    @qr.ecc_low(),
    @qr.ecc_medium(),
    @qr.ecc_quartile(),
    @qr.ecc_high(),
  ]
  let mut all_ok = true
  for i = 0; i < 4; i = i + 1 {
    if ecl_from_name(names[i]) != levels[i] {
      all_ok = false
    }
  }
  assert_true(all_ok)
}

///|
test "cli: hex_val digits" {
  assert_true(hex_val(0x30) == 0)
  assert_true(hex_val(0x39) == 9)
  assert_true(hex_val(0x41) == 10)
  assert_true(hex_val(0x46) == 15)
  assert_true(hex_val(0x61) == 10)
  assert_true(hex_val(0x66) == 15)
  assert_true(hex_val(0x67) == -1)
}

///|
test "cli: hex_to_bytes roundtrip" {
  let r = hex_to_bytes("000102")
  assert_true(r is Some(_))
  match r {
    Some(bytes) => {
      assert_true(bytes.length() == 3)
      assert_true(bytes[0] == 0)
      assert_true(bytes[1] == 1)
      assert_true(bytes[2] == 2)
    }
    None => ()
  }
  assert_true(hex_to_bytes("abc") is None)
  assert_true(hex_to_bytes("") is None)
}

///|
test "cli: hex2 roundtrip" {
  let mut all_ok = true
  for b = 0; b < 256; b = b + 1 {
    let hex = hex2(b)
    match hex_to_bytes(hex) {
      Some(bytes) => if bytes.length() != 1 || bytes[0] != b { all_ok = false }
      None => all_ok = false
    }
  }
  assert_true(all_ok)
}

///|
test "cli: byte_capacity positive" {
  let cap = byte_capacity(1, @qr.ecc_low())
  assert_true(cap > 0)
  let cap40 = byte_capacity(40, @qr.ecc_low())
  assert_true(cap40 > cap)
}

///|
test "cli: gen_zero all zeros" {
  let data = gen_zero(10)
  assert_true(data.length() == 10)
  let mut all_ok = true
  for i = 0; i < 10; i = i + 1 {
    if data[i] != 0 {
      all_ok = false
    }
  }
  assert_true(all_ok)
}

///|
test "cli: gen_ff all ff" {
  let data = gen_ff(10)
  assert_true(data.length() == 10)
  let mut all_ok = true
  for i = 0; i < 10; i = i + 1 {
    if data[i] != 0xFF {
      all_ok = false
    }
  }
  assert_true(all_ok)
}

///|
test "cli: utf8_to_bytes ascii" {
  let bytes = utf8_to_bytes("AB")
  assert_true(bytes.length() == 2)
  assert_true(bytes[0] == 0x41)
  assert_true(bytes[1] == 0x42)
}

///|
test "cli: base64_encode known" {
  let data = FixedArray::make(2, 0)
  data[0] = 0x41
  data[1] = 0x42
  let encoded = base64_encode(data)
  assert_true(encoded == "QUI=")
}

///|
test "cli: encode and capacity consistent" {
  let data = gen_zero(10)
  let level = ecl_from_name("M")
  let qr = @qr.encode_binary(data, level, 1)
  assert_true(qr.size() == qr.version() * 4 + 17)
  assert_true(qr.mask() >= 0 && qr.mask() <= 7)
}
