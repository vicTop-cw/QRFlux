// Boundary polish tests for 12 weak spots across the qr package.
// Each test block targets one specific boundary/edge condition identified in
// the source: array index, length, capacity, divide-by-zero, or out-of-range
// version/size. Tests that would trigger an abort (degree=0, max_payload=0)
// are documented and lock the nearest safe boundary instead.

///|
/// 薄弱点 #1: PNG 多 IDAT 块边界 (raw_len > 65535) | image.mbt:222
/// V1 size=21, quiet=4, total=29, scale=25 -> width=725, raw_len=66700 > 65535
/// 触发 num_blocks = (raw_len + 65534) / 65535 = 2 个 deflate stored 块。
test "boundary polish: png multi idat blocks raw len over 65535" {
  let data = FixedArray::make(5, 0x41)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  let png = @qr.to_png(qr, 25, 4)
  // PNG signature intact
  assert_true(png[0] == 137 && png[1] == 80 && png[2] == 78 && png[3] == 71)
  // IDAT length (BE at offset 33, after 8 sig + 25 IHDR chunk)
  let idat_len = (png[33] << 24) | (png[34] << 16) | (png[35] << 8) | png[36]
  // raw_len = height * (1 + ceil(width/8)), width = height = total * scale
  let total = 29
  let width = total * 25
  let row_bytes = (width + 7) / 8
  let row_len = 1 + row_bytes
  let raw_len = width * row_len
  assert_true(raw_len > 65535)
  let num_blocks = (raw_len + 65534) / 65535
  assert_true(num_blocks > 1)
  // idat_len = 2 (zlib header) + num_blocks * 5 (stored headers) + raw_len + 4 (adler)
  assert_true(idat_len == 2 + num_blocks * 5 + raw_len + 4)
  // IEND chunk present at tail
  let n = png.length()
  assert_true(
    png[n - 8] == 73 && png[n - 7] == 69 && png[n - 6] == 78 && png[n - 5] == 68,
  )
}

///|
/// 薄弱点 #2: rs_compute_divisor degree=0 边界 | gf256.mbt:38
/// degree=0 时 `result[degree-1] = result[-1]` 越界访问，会 panic/abort，
/// 无法安全直接调用。此处锁定 degree=1 最小合法边界，并验证已知值。
test "boundary polish: rs divisor degree 1 minimal legal" {
  // degree=0 不可测：FixedArray::make(0,0)[-1] 越界 abort (gf256.mbt:39)
  let div1 = @qr.rs_compute_divisor(1)
  assert_true(div1.length() == 1)
  // g1(x) = x + 1, divisor = [1] (leading 1 implicit)
  assert_true(div1[0] == 1)
  // degree=2 known: g2(x) = x^2 + 3x + 2, divisor = [3, 2]
  let div2 = @qr.rs_compute_divisor(2)
  assert_true(div2.length() == 2)
  assert_true(div2[0] == 3 && div2[1] == 2)
}

///|
/// 薄弱点 #3: rs_compute_remainder 空数据边界 | gf256.mbt:57
/// 空数据 + 非空 divisor: dlen=0, 循环不执行, 返回 make(divlen, 0) 全 0。
test "boundary polish: rs remainder empty data is zero" {
  let empty = FixedArray::make(0, 0)
  let div = @qr.rs_compute_divisor(3)
  let rem = @qr.rs_compute_remainder(empty, div)
  assert_true(rem.length() == div.length())
  for i = 0; i < rem.length(); i = i + 1 {
    assert_true(rem[i] == 0)
  }
  // 单字节数据也不崩溃，余数长度 == divisor 长度
  let one = FixedArray::make(1, 0x42)
  let rem1 = @qr.rs_compute_remainder(one, div)
  assert_true(rem1.length() == div.length())
}

///|
/// 薄弱点 #4: char_count_bits 版本 0/41+ 越界边界 | segment.mbt:37
/// group = (version + 7) / 17，version=0 -> group=0, version=41 -> group=2
/// 越界版本不崩溃，仅按 group 索引返回（不校验版本合法性）。
test "boundary polish: char count bits out of range version" {
  // version=0: group = 7/17 = 0
  assert_true(@qr.char_count_bits(@qr.mode_numeric(), 0) == 10)
  assert_true(@qr.char_count_bits(@qr.mode_alphanumeric(), 0) == 9)
  assert_true(@qr.char_count_bits(@qr.mode_byte(), 0) == 8)
  // version=41: group = 48/17 = 2
  assert_true(@qr.char_count_bits(@qr.mode_numeric(), 41) == 14)
  assert_true(@qr.char_count_bits(@qr.mode_alphanumeric(), 41) == 13)
  assert_true(@qr.char_count_bits(@qr.mode_byte(), 41) == 16)
  // version=40 合法上限: group = 47/17 = 2，与 41 同组
  assert_true(@qr.char_count_bits(@qr.mode_byte(), 40) == 16)
  // 版本组边界: v9 -> group=0, v10 -> group=1
  assert_true(@qr.char_count_bits(@qr.mode_byte(), 9) == 8)
  assert_true(@qr.char_count_bits(@qr.mode_byte(), 10) == 16)
}

///|
/// 薄弱点 #5: alignment_pattern_positions 版本 0/41+ 越界边界 | qrcode.mbt:361
/// version=0: numalign=0/7+2=2, 不崩溃, 返回 [6, 10]
/// version=41: numalign=41/7+2=7, 不崩溃, 返回 7 个位置
test "boundary polish: alignment pattern positions out of range" {
  // version=1: 空数组（合法边界）
  let p1 = @qr.alignment_pattern_positions(1)
  assert_true(p1.length() == 0)
  // version=0: numalign=2, result[0]=6, result[1]=size-7=10
  let p0 = @qr.alignment_pattern_positions(0)
  assert_true(p0.length() == 2)
  assert_true(p0[0] == 6)
  assert_true(p0[1] == 10)
  // version=41: numalign=7, result[0]=6
  let p41 = @qr.alignment_pattern_positions(41)
  assert_true(p41.length() == 7)
  assert_true(p41[0] == 6)
  // version=40 合法上限: numalign=40/7+2=7
  let p40 = @qr.alignment_pattern_positions(40)
  assert_true(p40.length() == 7)
  assert_true(p40[0] == 6)
}

///|
/// 薄弱点 #6: calculate_frames_needed max_payload=0 除零边界 | integrate.mbt:18
/// max_payload=0 时 `(effective + 0 - 1) / 0` 除零 abort，无法安全调用。
/// 此处锁定 data_size=0 边界（0 字节数据 -> 0 帧）与 max_payload=1 最小合法。
test "boundary polish: calculate frames needed zero data boundary" {
  // max_payload=0 不可测：整型除零 abort (integrate.mbt:18)
  // data_size=0: effective=0, (0 + payload - 1) / payload = 0 帧
  assert_true(@qr.calculate_frames_needed(0, 100, false) == 0)
  assert_true(@qr.calculate_frames_needed(0, 100, true) == 0)
  // data_size=0, max_payload=1: (0 + 1 - 1) / 1 = 0
  assert_true(@qr.calculate_frames_needed(0, 1, false) == 0)
  // data_size=1, max_payload=1: (1 + 1 - 1) / 1 = 1
  assert_true(@qr.calculate_frames_needed(1, 1, false) == 1)
  // compress=true: effective = data_size / 2
  assert_true(@qr.calculate_frames_needed(100, 50, true) == 1)
}

///|
/// 薄弱点 #7: split_into_frames max_payload=0 除零边界 | stream.mbt:147
/// max_payload=0 时 `total_frames = (len + 0 - 1) / 0` 除零 abort，无法安全调用。
/// 此处锁定空数据边界与 max_payload=1 最小合法帧大小。
test "boundary polish: split into frames empty and minimal payload" {
  // max_payload=0 不可测：整型除零 abort (stream.mbt:147)
  let empty = FixedArray::make(0, 0)
  let frames0 = @qr.split_into_frames(empty, 1)
  assert_true(frames0.length() == 0)
  // 单字节 + max_payload=1: 1 帧 = 16 header + 1 payload
  let one = FixedArray::make(1, 0x42)
  let frames1 = @qr.split_into_frames(one, 1)
  assert_true(frames1.length() == 1)
  assert_true(frames1[0].length() == 17)
  // 空数据 + 较大 payload: 0 帧
  let frames2 = @qr.split_into_frames(empty, 100)
  assert_true(frames2.length() == 0)
}

///|
/// 薄弱点 #8: select_strategy data.length()<10 边界 | strategy.mbt:248
/// length < 10 -> NoCompress; length >= 10 进入重复率分支。
/// 测试 0/9/10/11 边界及 NoCompress<->FastRLE 切换。
test "boundary polish: select strategy length boundary" {
  // length=0: < 10 -> NoCompress
  let d0 = FixedArray::make(0, 0)
  assert_true(@qr.select_strategy(d0) == @qr.strategy_no_compress())
  // length=9: < 10 -> NoCompress
  let d9 = FixedArray::make(9, 0x42)
  assert_true(@qr.select_strategy(d9) == @qr.strategy_no_compress())
  // length=10 全相同: repeats=9, ratio=0.9 > 0.5 -> FastRLE
  let d10same = FixedArray::make(10, 0x42)
  assert_true(@qr.select_strategy(d10same) == @qr.strategy_fast_rle())
  // length=10 全不同: repeats=0, ratio=0.0, 不>0.2, len 不>1000 -> NoCompress
  let d10diff = FixedArray::make(10, 0)
  for i = 0; i < 10; i = i + 1 {
    d10diff[i] = i
  }
  assert_true(@qr.select_strategy(d10diff) == @qr.strategy_no_compress())
  // length=11 全相同: repeats=10, ratio=10/11≈0.909 > 0.5 -> FastRLE
  let d11 = FixedArray::make(11, 0x42)
  assert_true(@qr.select_strategy(d11) == @qr.strategy_fast_rle())
}

///|
/// 薄弱点 #9: fountain robust_soliton_degree d>num_blocks 边界 | fountain.mbt:90
/// spike 分支 (r>=950): d = r%10+4, 若 d > num_blocks 则钳制为 num_blocks。
/// num_blocks=1 时，spike 分支 degree 必被钳制为 1。
test "boundary polish: fountain degree clamped in spike branch" {
  let fountain = @qr.LTFountain::new(10, 1)
  let mut found_spike = false
  for seed = 1; seed <= 2000; seed = seed + 1 {
    let pr = fountain.pseudo_random(seed)
    let r = pr % 1000
    if r >= 950 {
      // spike 分支: d = r%10+4 >= 4 > num_blocks=1 -> 钳制为 1
      let degree = fountain.robust_soliton_degree(seed)
      assert_true(degree == 1)
      found_spike = true
    }
  }
  // 确实在遍历中触发了 spike 分支
  assert_true(found_spike)
}

///|
/// 薄弱点 #10: fountain select_blocks duplicate 去重分支 | fountain.mbt:131
/// num_blocks=1, degree=5: 所有 idx = pr % 1 = 0，首个加入，后续重复跳过。
/// 返回 indices 必须全唯一且 <= num_blocks。
test "boundary polish: fountain select blocks dedup" {
  // num_blocks=1, degree=5: 全部 idx=0，去重后最多 1 个
  let fountain = @qr.LTFountain::new(10, 1)
  let indices = fountain.select_blocks(42, 5)
  assert_true(indices.length() <= 1)
  for i = 0; i < indices.length(); i = i + 1 {
    for j = i + 1; j < indices.length(); j = j + 1 {
      assert_true(indices[i] != indices[j])
    }
  }
  // num_blocks=4, degree=10: 去重后全唯一且 <= 4
  let fountain2 = @qr.LTFountain::new(10, 4)
  let indices2 = fountain2.select_blocks(7, 10)
  assert_true(indices2.length() <= 4)
  for i = 0; i < indices2.length(); i = i + 1 {
    for j = i + 1; j < indices2.length(); j = j + 1 {
      assert_true(indices2[i] != indices2[j])
    }
  }
  // degree=0: 返回空数组（不崩溃）
  let indices0 = fountain2.select_blocks(7, 0)
  assert_true(indices0.length() == 0)
}

///|
/// 薄弱点 #11: ColorQREncoder::encode 奇数 size 边界 | color_qr.mbt:119-130
/// version=2 -> size=25 (奇数), 2x2 块循环用 size/2=12，最后一列/行 (idx 24) 不被覆盖。
/// 边界检查 `if x+1 < self.size` 正确处理奇数边缘，保持 White。
test "boundary polish: color qr odd size boundary" {
  let encoder = @qr.ColorQREncoder::new(2)
  // 容量 = (25/2)^2 = 12*12 = 144 字节
  let capacity = 144
  let data = FixedArray::make(capacity, 0x5A)
  let matrix = encoder.encode(data)
  assert_true(matrix.length() == 25)
  // 奇数 size: 最后一列 (x=24) 未被 2x2 块覆盖，保持 White
  for y = 0; y < 25; y = y + 1 {
    assert_true(matrix[y][24] == @qr.color_white())
  }
  // 最后一行 (y=24) 同理保持 White
  for x = 0; x < 25; x = x + 1 {
    assert_true(matrix[24][x] == @qr.color_white())
  }
  // decode roundtrip 不崩溃，返回 (25/2)^2 = 144 字节
  match encoder.decode(matrix) {
    Some(decoded) => {
      assert_true(decoded.length() == capacity)
      let mut all_match = true
      for i = 0; i < capacity; i = i + 1 {
        if data[i] != decoded[i] {
          all_match = false
        }
      }
      assert_true(all_match)
    }
    None => assert_true(false)
  }
}

///|
/// 薄弱点 #12: decode_qr 尺寸边界 (size<21 / >177 / (size-17)%4!=0) | decoder.mbt:11
/// 非法尺寸矩阵应立即返回 None，不进入解码流程。
test "boundary polish: decode qr invalid size returns none" {
  // size=20: < 21 -> None
  let m20 = FixedArray::make(20, FixedArray::make(20, 0))
  for y = 0; y < 20; y = y + 1 {
    m20[y] = FixedArray::make(20, 0)
  }
  assert_true(@qr.decode_qr(m20) is None)
  // size=22: (22-17)%4 = 5%4 = 1 != 0 -> None
  let m22 = FixedArray::make(22, FixedArray::make(22, 0))
  for y = 0; y < 22; y = y + 1 {
    m22[y] = FixedArray::make(22, 0)
  }
  assert_true(@qr.decode_qr(m22) is None)
  // size=178: > 177 -> None
  let m178 = FixedArray::make(178, FixedArray::make(178, 0))
  for y = 0; y < 178; y = y + 1 {
    m178[y] = FixedArray::make(178, 0)
  }
  assert_true(@qr.decode_qr(m178) is None)
  // size=180: > 177 且 (180-17)%4 = 163%4 = 3 != 0 -> None
  let m180 = FixedArray::make(180, FixedArray::make(180, 0))
  for y = 0; y < 180; y = y + 1 {
    m180[y] = FixedArray::make(180, 0)
  }
  assert_true(@qr.decode_qr(m180) is None)
}
