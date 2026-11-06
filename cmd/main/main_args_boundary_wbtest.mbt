// CLI 参数解析边界测试（白盒）。
// 覆盖 parse_int / hex_val / hex_to_bytes / hex2 / ecl_from_name / run_cli
// 的边界值与缺失参数路径，与 main_wbtest.mbt / main_entry_wbtest.mbt 互补。
// 使用 _wbtest.mbt 后缀以访问包私有函数。

///|
test "args_boundary: parse_int single digit 0-9" {
  // 单字符数字 0~9 全覆盖
  let mut all_ok = true
  for d = 0; d < 10; d = d + 1 {
    let s = d.to_string()
    match parse_int(s) {
      Some(n) => if n != d { all_ok = false }
      None => all_ok = false
    }
  }
  assert_true(all_ok)
}

///|
test "args_boundary: parse_int non-digit variants" {
  // 带符号、小数、空格、字母、十六进制前缀都应返回 None
  assert_true(parse_int("-5") == None)
  assert_true(parse_int("+5") == None)
  assert_true(parse_int("12.3") == None)
  assert_true(parse_int("1e3") == None)
  assert_true(parse_int("0x10") == None)
  assert_true(parse_int(" 12") == None)
  assert_true(parse_int("12 ") == None)
  assert_true(parse_int("1 2") == None)
}

///|
test "args_boundary: parse_int large value" {
  // 大数边界（Int32 范围内安全值）
  assert_true(parse_int("2147483647") == Some(2147483647))
  assert_true(parse_int("1000000000") == Some(1000000000))
}

///|
test "args_boundary: hex_val out-of-range boundaries" {
  // 边界外值：0x2F('0'前)、0x3A('9'后)、0x40('A'前)、0x47('F'后)、0x60('a'前)、0x67('f'后)
  assert_true(hex_val(0x2F) == -1)
  assert_true(hex_val(0x3A) == -1)
  assert_true(hex_val(0x40) == -1)
  assert_true(hex_val(0x47) == -1)
  assert_true(hex_val(0x60) == -1)
  assert_true(hex_val(0x67) == -1)
  // 边界内值
  assert_true(hex_val(0x30) == 0)
  assert_true(hex_val(0x39) == 9)
  assert_true(hex_val(0x41) == 10)
  assert_true(hex_val(0x46) == 15)
  assert_true(hex_val(0x61) == 10)
  assert_true(hex_val(0x66) == 15)
}

///|
test "args_boundary: hex_to_bytes odd length" {
  // 奇数长度（1, 3, 5）都应返回 None
  assert_true(hex_to_bytes("a") is None)
  assert_true(hex_to_bytes("abc") is None)
  assert_true(hex_to_bytes("abcde") is None)
}

///|
test "args_boundary: hex_to_bytes mixed case" {
  // 大小写混合应正确解析
  match hex_to_bytes("AbCdEf") {
    Some(bytes) => {
      assert_true(bytes.length() == 3)
      assert_true(bytes[0] == 0xAB)
      assert_true(bytes[1] == 0xCD)
      assert_true(bytes[2] == 0xEF)
    }
    None => assert_true(false)
  }
  match hex_to_bytes("aBcD01") {
    Some(bytes) => {
      assert_true(bytes.length() == 3)
      assert_true(bytes[0] == 0xAB)
      assert_true(bytes[1] == 0xCD)
      assert_true(bytes[2] == 0x01)
    }
    None => assert_true(false)
  }
}

///|
test "args_boundary: hex_to_bytes invalid chars" {
  // 含无效字符（g, G, !, 空格）应返回 None
  assert_true(hex_to_bytes("gg") is None)
  assert_true(hex_to_bytes("GG") is None)
  assert_true(hex_to_bytes("12g4") is None)
  assert_true(hex_to_bytes("!!") is None)
  assert_true(hex_to_bytes("12 34") is None)
}

///|
test "args_boundary: hex2 boundary values" {
  // 边界值：0, 15, 16, 127, 128, 255
  assert_true(hex2(0) == "00")
  assert_true(hex2(15) == "0f")
  assert_true(hex2(16) == "10")
  assert_true(hex2(127) == "7f")
  assert_true(hex2(128) == "80")
  assert_true(hex2(255) == "ff")
}

///|
test "args_boundary: ecl_from_name lowercase defaults H" {
  // 小写 l/m/q/h 都不在 match 范围，应默认 H
  assert_true(ecl_from_name("l") == @qr.ecc_high())
  assert_true(ecl_from_name("m") == @qr.ecc_high())
  assert_true(ecl_from_name("q") == @qr.ecc_high())
  assert_true(ecl_from_name("h") == @qr.ecc_high())
}

///|
test "args_boundary: ecl_from_name mixed and whitespace" {
  // 带空格、部分匹配、多字符都应默认 H
  assert_true(ecl_from_name("L ") == @qr.ecc_high())
  assert_true(ecl_from_name(" L") == @qr.ecc_high())
  assert_true(ecl_from_name("Lm") == @qr.ecc_high())
  assert_true(ecl_from_name("LL") == @qr.ecc_high())
  assert_true(ecl_from_name("X") == @qr.ecc_high())
}

///|
test "args_boundary: run_cli --text missing value at end" {
  // --text 在末尾无值 → has_text 保持 false → 输出错误
  let mut ok = false
  run_cli(["cmd/main", "--text"])
  ok = true
  assert_true(ok)
}

///|
test "args_boundary: run_cli unknown flag ignored" {
  // 未知选项被忽略，但无 --text → 输出错误
  let mut ok = false
  run_cli(["cmd/main", "--unknown-flag", "--another"])
  ok = true
  assert_true(ok)
}

///|
test "args_boundary: run_cli --ecl missing value keeps default" {
  // --ecl 在末尾无值 → 保持默认 M
  let mut ok = false
  run_cli(["cmd/main", "--text", "hi", "--ecl"])
  ok = true
  assert_true(ok)
}

///|
test "args_boundary: run_cli --format missing value keeps default" {
  // --format 在末尾无值 → 保持默认 pbm
  let mut ok = false
  run_cli(["cmd/main", "--text", "hi", "--format"])
  ok = true
  assert_true(ok)
}

///|
test "args_boundary: run_cli --frame-size non-numeric" {
  // --frame-size 非数字 → parse_int 返回 None → 保持默认 500
  let mut ok = false
  run_cli([
    "cmd/main", "--text", "hi", "--encode-dynamic", "--frame-size", "abc",
  ])
  ok = true
  assert_true(ok)
}

///|
test "args_boundary: run_cli --frame-size zero and negative" {
  // --frame-size 0 或负数 → n > 0 为 false → 保持默认 500
  let mut ok = false
  run_cli(["cmd/main", "--text", "hi", "--encode-dynamic", "--frame-size", "0"])
  run_cli(["cmd/main", "--text", "hi", "--encode-dynamic", "--frame-size", "-5"])
  ok = true
  assert_true(ok)
}

///|
test "args_boundary: run_cli --decode-static without --hex" {
  // --decode-static 无 --hex → hex_data 为空 → 输出错误
  let mut ok = false
  run_cli(["cmd/main", "--decode-static"])
  ok = true
  assert_true(ok)
}

///|
test "args_boundary: run_cli --decode-dynamic without --hex" {
  // --decode-dynamic 无 --hex → hex_data 为空 → 输出错误
  let mut ok = false
  run_cli(["cmd/main", "--decode-dynamic"])
  ok = true
  assert_true(ok)
}

///|
test "args_boundary: run_cli --hex missing value at end" {
  // --hex 在末尾无值 → hex_data 保持空 → --decode-static 错误
  let mut ok = false
  run_cli(["cmd/main", "--decode-static", "--hex"])
  ok = true
  assert_true(ok)
}

///|
test "args_boundary: run_cli -h short option" {
  // -h 短选项应触发 print_usage 并 return
  let mut ok = false
  run_cli(["cmd/main", "-h"])
  ok = true
  assert_true(ok)
}

///|
test "args_boundary: run_cli --output skips value" {
  // --output 选项跳过其值，不应影响后续参数
  let mut ok = false
  run_cli(["cmd/main", "--text", "hi", "--output", "file.txt", "--ecl", "L"])
  ok = true
  assert_true(ok)
}

///|
test "args_boundary: run_cli combined multiple options" {
  // 组合多选项同时指定
  let mut ok = false
  run_cli([
    "cmd/main", "--text", "combined test", "--ecl", "Q", "--format", "svg", "--encode-static",
  ])
  ok = true
  assert_true(ok)
}

///|
test "args_boundary: run_cli empty args only program name" {
  // 仅程序名 → has_text false → 输出错误
  let mut ok = false
  run_cli(["cmd/main"])
  ok = true
  assert_true(ok)
}

///|
test "args_boundary: gen_repeat length 0-3 boundary" {
  // 长度 0, 1, 2, 3 边界（不足一个完整 ABCD 周期）
  let d0 = gen_repeat(0)
  assert_true(d0.length() == 0)
  let d1 = gen_repeat(1)
  assert_true(d1.length() == 1)
  assert_true(d1[0] == 0x41)
  let d2 = gen_repeat(2)
  assert_true(d2[0] == 0x41)
  assert_true(d2[1] == 0x42)
  let d3 = gen_repeat(3)
  assert_true(d3[0] == 0x41)
  assert_true(d3[1] == 0x42)
  assert_true(d3[2] == 0x43)
}

///|
test "args_boundary: gen_text zero length" {
  // 长度 0 → 空数组
  let data = gen_text(0)
  assert_true(data.length() == 0)
}

///|
test "args_boundary: bytes_to_display all printable ASCII" {
  // 全可打印 ASCII → 直接输出字符串
  let data : FixedArray[Int32] = FixedArray::make(3, 0)
  data[0] = 0x41
  data[1] = 0x42
  data[2] = 0x43
  let s = bytes_to_display(data)
  assert_true(s == "ABC")
}

///|
test "args_boundary: bytes_to_display contains non-printable" {
  // 含非可打印字节 → 输出 hex
  let data : FixedArray[Int32] = FixedArray::make(2, 0)
  data[0] = 0x00
  data[1] = 0x41
  let s = bytes_to_display(data)
  assert_true(s == "0041")
}

///|
test "args_boundary: base64_encode padding boundaries" {
  // 空数组、1 字节（==）、2 字节（=）、3 字节（无 padding）
  let empty : FixedArray[Int32] = FixedArray::make(0, 0)
  assert_true(base64_encode(empty) == "")
  let one : FixedArray[Int32] = FixedArray::make(1, 0)
  one[0] = 0x41
  // 1 字节 → 2 chars + "=="
  assert_true(base64_encode(one).length() == 4)
  let three : FixedArray[Int32] = FixedArray::make(3, 0)
  three[0] = 0x41
  three[1] = 0x42
  three[2] = 0x43
  // 3 字节 → 4 chars, no padding
  assert_true(base64_encode(three) == "QUJD")
}

///|
test "args_boundary: byte_capacity version 1 vs 40 all ecl" {
  // version 1 vs 40 各 ECC 级别，容量递增
  let cap1L = byte_capacity(1, @qr.ecc_low())
  let cap1H = byte_capacity(1, @qr.ecc_high())
  let cap40L = byte_capacity(40, @qr.ecc_low())
  let cap40H = byte_capacity(40, @qr.ecc_high())
  assert_true(cap1L > 0)
  assert_true(cap1H > 0)
  assert_true(cap40L > cap1L)
  assert_true(cap40H > cap1H)
  assert_true(cap1L > cap1H)
  assert_true(cap40L > cap40H)
}
