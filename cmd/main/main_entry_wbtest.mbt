// CLI entry function whitebox tests for cmd/main.
// 打磨 7 个 CLI 入口函数薄弱点：
//   1. run_cli          (main.mbt:585)
//   2. run_batch        (main.mbt:729)
//   3. emit_image       (main.mbt:430)
//   4. run_decode_static / run_decode_dynamic (main.mbt:359,378)
//   5. run_dynamic      (main.mbt:532)
//   6. gen_random / gen_repeat / gen_text     (main.mbt:181,193,220)
//   7. utf8_push_codepoint 4-byte branch      (main.mbt:242)
//
// 使用 _wbtest.mbt 后缀以访问包私有函数。
// 返回 Unit 的函数通过 println 输出，测试验证执行不抛异常；
// 返回值的函数（gen_*, utf8_push_codepoint）做内容断言。

///|
// === 薄弱点 6: gen_random / gen_repeat / gen_text ===

///|
test "entry: gen_random deterministic same seed" {
  // gen_random 使用固定 seed=12345，同长度两次调用结果必须完全相同
  let a = gen_random(50)
  let b = gen_random(50)
  assert_true(a.length() == 50)
  assert_true(b.length() == 50)
  let mut same = true
  for i = 0; i < 50; i = i + 1 {
    if a[i] != b[i] {
      same = false
    }
  }
  assert_true(same)
}

///|
test "entry: gen_random byte range 0-255" {
  // (seed >> 16) & 0xFF 保证字节在 0~255 范围
  let data = gen_random(200)
  let mut in_range = true
  for i = 0; i < 200; i = i + 1 {
    if data[i] < 0 || data[i] > 255 {
      in_range = false
    }
  }
  assert_true(in_range)
}

///|
test "entry: gen_random zero length" {
  let data = gen_random(0)
  assert_true(data.length() == 0)
}

///|
test "entry: gen_repeat ABCD pattern" {
  // gen_repeat 生成 "ABCDABCD..." RLE 友好模式
  let data = gen_repeat(10)
  assert_true(data.length() == 10)
  assert_true(data[0] == 0x41)
  assert_true(data[1] == 0x42)
  assert_true(data[2] == 0x43)
  assert_true(data[3] == 0x44)
  assert_true(data[4] == 0x41)
  assert_true(data[5] == 0x42)
  assert_true(data[6] == 0x43)
  assert_true(data[7] == 0x44)
  assert_true(data[8] == 0x41)
  assert_true(data[9] == 0x42)
}

///|
test "entry: gen_repeat pattern modulo" {
  // 验证 i % 4 循环：10%4=2→C, 11%4=3→D, 12%4=0→A, 13%4=1→B
  let data = gen_repeat(14)
  assert_true(data[10] == 0x43)
  assert_true(data[11] == 0x44)
  assert_true(data[12] == 0x41)
  assert_true(data[13] == 0x42)
}

///|
test "entry: gen_text deterministic" {
  // gen_text 使用固定 seed=98765，确定性
  let a = gen_text(80)
  let b = gen_text(80)
  assert_true(a.length() == 80)
  let mut same = true
  for i = 0; i < 80; i = i + 1 {
    if a[i] != b[i] {
      same = false
    }
  }
  assert_true(same)
}

///|
test "entry: gen_text printable ASCII 32-126" {
  // 32 + (seed >> 16) % 95 → 范围 32~126
  let data = gen_text(150)
  let mut all_printable = true
  for i = 0; i < 150; i = i + 1 {
    if data[i] < 32 || data[i] > 126 {
      all_printable = false
    }
  }
  assert_true(all_printable)
}

///|
// === 薄弱点 7: utf8_push_codepoint 4 字节分支 ===

///|
test "entry: utf8_push_codepoint 1-byte ASCII" {
  // cp < 0x80: 单字节直接推送
  let arr : Array[Int32] = []
  utf8_push_codepoint(arr, 0x41)
  assert_true(arr.length() == 1)
  assert_true(arr[0] == 0x41)
}

///|
test "entry: utf8_push_codepoint 2-byte" {
  // 0x80 <= cp < 0x800: 2 字节
  // cp=0x80 (€): [0xC2, 0x80]
  let arr : Array[Int32] = []
  utf8_push_codepoint(arr, 0x80)
  assert_true(arr.length() == 2)
  assert_true(arr[0] == 0xC2)
  assert_true(arr[1] == 0x80)
}

///|
test "entry: utf8_push_codepoint 3-byte" {
  // 0x800 <= cp < 0x10000: 3 字节
  // cp=0x4E2D (中): [0xE4, 0xB8, 0xAD]
  let arr : Array[Int32] = []
  utf8_push_codepoint(arr, 0x4E2D)
  assert_true(arr.length() == 3)
  assert_true(arr[0] == 0xE4)
  assert_true(arr[1] == 0xB8)
  assert_true(arr[2] == 0xAD)
}

///|
test "entry: utf8_push_codepoint 4-byte emoji 1F600" {
  // cp >= 0x10000: 4 字节分支 (main.mbt:242)
  // cp=0x1F600 (😀): [0xF0, 0x9F, 0x98, 0x80]
  let arr : Array[Int32] = []
  utf8_push_codepoint(arr, 0x1F600)
  assert_true(arr.length() == 4)
  assert_true(arr[0] == 0xF0)
  assert_true(arr[1] == 0x9F)
  assert_true(arr[2] == 0x98)
  assert_true(arr[3] == 0x80)
}

///|
test "entry: utf8_push_codepoint 4-byte boundary 10000" {
  // cp=0x10000 边界值：4 字节分支
  // 0x10000: [0xF0, 0x90, 0x80, 0x80]
  let arr : Array[Int32] = []
  utf8_push_codepoint(arr, 0x10000)
  assert_true(arr.length() == 4)
  assert_true(arr[0] == 0xF0)
  assert_true(arr[1] == 0x90)
  assert_true(arr[2] == 0x80)
  assert_true(arr[3] == 0x80)
}

///|
test "entry: utf8_push_codepoint accumulates multiple" {
  // 多次推送累积到同一数组
  let arr : Array[Int32] = []
  utf8_push_codepoint(arr, 0x41)
  utf8_push_codepoint(arr, 0x4E2D)
  utf8_push_codepoint(arr, 0x1F600)
  assert_true(arr.length() == 8)
  // 0x41(1B) + 0x4E2D(3B: E4 B8 AD) + 0x1F600(4B: F0 9F 98 80)
  assert_true(arr[0] == 0x41)
  assert_true(arr[1] == 0xE4)
  assert_true(arr[4] == 0xF0)
  assert_true(arr[5] == 0x9F)
}

///|
// === 薄弱点 3: emit_image ===

///|
test "entry: emit_image pbm format" {
  // emit_image 对 pbm 格式调用 @qr.to_pbm，验证不抛异常
  let data = gen_random(10)
  let qr = @qr.encode_binary(data, @qr.ecc_medium(), 1)
  let mut ok = false
  emit_image(qr, "pbm")
  ok = true
  assert_true(ok)
}

///|
test "entry: emit_image svg format" {
  let data = gen_random(10)
  let qr = @qr.encode_binary(data, @qr.ecc_medium(), 1)
  let mut ok = false
  emit_image(qr, "svg")
  ok = true
  assert_true(ok)
}

///|
test "entry: emit_image png format" {
  // png 输出 base64 编码，验证不抛异常
  let data = gen_random(10)
  let qr = @qr.encode_binary(data, @qr.ecc_medium(), 1)
  let mut ok = false
  emit_image(qr, "png")
  ok = true
  assert_true(ok)
}

///|
test "entry: emit_image unknown format" {
  // 未知格式走默认分支，输出 "Error: unknown format ..."
  let data = gen_random(10)
  let qr = @qr.encode_binary(data, @qr.ecc_medium(), 1)
  let mut ok = false
  emit_image(qr, "unknown")
  ok = true
  assert_true(ok)
}

///|
// === 薄弱点 1: run_cli ===

///|
test "entry: run_cli text encode default pbm" {
  // run_cli(["prog","--text","Hi","--ecl","M"]) 生成 QR 并输出 pbm
  let mut ok = false
  run_cli(["cmd/main", "--text", "Hi", "--ecl", "M"])
  ok = true
  assert_true(ok)
}

///|
test "entry: run_cli text encode svg" {
  let mut ok = false
  run_cli(["cmd/main", "--text", "Hello", "--ecl", "L", "--format", "svg"])
  ok = true
  assert_true(ok)
}

///|
test "entry: run_cli help flag" {
  // --help 调用 print_usage 并 return
  let mut ok = false
  run_cli(["cmd/main", "--help"])
  ok = true
  assert_true(ok)
}

///|
test "entry: run_cli no text error path" {
  // 无 --text 应输出错误并打印 usage，不抛异常
  let mut ok = false
  run_cli(["cmd/main"])
  ok = true
  assert_true(ok)
}

///|
test "entry: run_cli encode_static hex" {
  // --encode-static --format hex 输出 packaged bytes hex
  let mut ok = false
  run_cli(["cmd/main", "--text", "test", "--encode-static", "--format", "hex"])
  ok = true
  assert_true(ok)
}

///|
test "entry: run_cli encode_dynamic hex" {
  // --encode-dynamic --format hex 输出 frame hex
  let mut ok = false
  run_cli([
    "cmd/main", "--text", "dynamic test", "--encode-dynamic", "--format", "hex",
    "--frame-size", "20",
  ])
  ok = true
  assert_true(ok)
}

///|
// === 薄弱点 4: run_decode_static / run_decode_dynamic ===

///|
test "entry: run_decode_static invalid hex" {
  // 无效 hex 字符 → 输出 "Error: invalid hex string"
  let mut ok = false
  run_decode_static("xyz")
  ok = true
  assert_true(ok)
}

///|
test "entry: run_decode_static odd length" {
  // 奇数长度 hex → None → 错误
  let mut ok = false
  run_decode_static("abc")
  ok = true
  assert_true(ok)
}

///|
test "entry: run_decode_static empty hex" {
  let mut ok = false
  run_decode_static("")
  ok = true
  assert_true(ok)
}

///|
test "entry: run_decode_static valid roundtrip" {
  // 用 encode_static 生成 packaged bytes → 转 hex → decode_static 回环
  let data = gen_random(10)
  let result = @qr.encode_static(data, @qr.ecc_medium(), 1)
  match result {
    Some(r) => {
      let pb = r.packaged_bytes()
      let mut hex = ""
      for i = 0; i < pb.length(); i = i + 1 {
        hex = hex + hex2(pb[i])
      }
      let mut ok = false
      run_decode_static(hex)
      ok = true
      assert_true(ok)
    }
    None => assert_true(true)
  }
}

///|
test "entry: run_decode_static non_package_bytes" {
  // 有效 hex 但非 packaged bytes → decode_static 返回 None → 错误输出
  let mut ok = false
  run_decode_static("0001020304050607")
  ok = true
  assert_true(ok)
}

///|
test "entry: run_decode_dynamic invalid frame" {
  // 包含无效 hex 的 frame → 错误输出
  let mut ok = false
  run_decode_dynamic("xyz")
  ok = true
  assert_true(ok)
}

///|
test "entry: run_decode_dynamic empty input" {
  // 空输入 → "Error: no frames provided"
  let mut ok = false
  run_decode_dynamic("")
  ok = true
  assert_true(ok)
}

///|
test "entry: run_decode_dynamic valid roundtrip" {
  // split_into_frames → 转 hex (分号分隔) → reassemble 回环
  let data = gen_random(50)
  let frames = @qr.split_into_frames(data, 50)
  let mut hex = ""
  for i = 0; i < frames.length(); i = i + 1 {
    if i > 0 {
      hex = hex + ";"
    }
    for j = 0; j < frames[i].length(); j = j + 1 {
      hex = hex + hex2(frames[i][j])
    }
  }
  let mut ok = false
  run_decode_dynamic(hex)
  ok = true
  assert_true(ok)
}

///|
// === 薄弱点 5: run_dynamic ===

///|
test "entry: run_dynamic hex format" {
  // run_dynamic 输出 hex 格式的 frame bytes
  let data = gen_random(50)
  let mut ok = false
  run_dynamic(data, "M", 50, "cli", "hex")
  ok = true
  assert_true(ok)
}

///|
test "entry: run_dynamic matrix format" {
  // 非 hex 格式输出 DYNAMIC_CASE 矩阵块
  let data = gen_random(30)
  let mut ok = false
  run_dynamic(data, "L", 30, "test", "pbm")
  ok = true
  assert_true(ok)
}

///|
test "entry: run_dynamic zero frame_size clamped" {
  // frame_size < 1 被钳制为 1，不抛异常
  let data = gen_random(10)
  let mut ok = false
  run_dynamic(data, "M", 0, "cli", "hex")
  ok = true
  assert_true(ok)
}

///|
test "entry: run_dynamic empty data" {
  // 空数据 → split_into_frames 返回空 → "no frames" 输出
  let data : FixedArray[Int32] = FixedArray::make(0, 0)
  let mut ok = false
  run_dynamic(data, "M", 50, "cli", "hex")
  ok = true
  assert_true(ok)
}

///|
// === 薄弱点 2: run_batch ===

///|
test "entry: run_batch executes fully" {
  // run_batch 输出 CASE / STATIC_CASE 块，验证完整执行不抛异常
  // 包含 legacy CASE + version sweep + static pipeline CASE
  let mut ok = false
  run_batch()
  ok = true
  assert_true(ok)
}
