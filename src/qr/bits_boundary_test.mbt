// BitBuffer 位流操作边界测试（黑盒）。
// 覆盖：空位流、单 bit、部分字节高位补零、大流往返、各种位模式、
// append_bytes 往返、位索引边界、字节对齐、混合 append、容量边界。
// 仅调用 src/qr 的 pub fn；辅助函数本文件内私有。
// 越界访问（bit_at(len)）会 abort，无法安全直接调用，此处锁定最近合法边界。

///|
/// Helper: 从 Array 构造 FixedArray[Int32]。
fn bb_mk(xs : Array[Int32]) -> FixedArray[Int32] {
  let fa = FixedArray::make(xs.length(), 0)
  for i = 0; i < xs.length(); i = i + 1 {
    fa[i] = xs[i]
  }
  fa
}

///|
/// Helper: 比较两个 FixedArray[Int32] 是否相等。
fn bb_eq(a : FixedArray[Int32], b : FixedArray[Int32]) -> Bool {
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
/// 空位流：new 后 length == 0。
test "bb empty: zero bits length" {
  let buf = @qr.BitBuffer::new()
  assert_true(buf.length() == 0)
}

///|
/// 空位流：new 后 to_bytes 长度为 0。
test "bb empty: to bytes zero length" {
  let buf = @qr.BitBuffer::new()
  let bytes = buf.to_bytes()
  assert_true(bytes.length() == 0)
}

///|
/// 单 bit：append 1 位，length=1，bit_at(0)=1。
test "bb single bit: append one" {
  let buf = @qr.BitBuffer::new()
  buf.append_bits(1, 1)
  assert_true(buf.length() == 1)
  assert_true(buf.bit_at(0) == 1)
}

///|
/// 单 bit：append 0 位，length=1，bit_at(0)=0。
test "bb single bit: append zero" {
  let buf = @qr.BitBuffer::new()
  buf.append_bits(0, 1)
  assert_true(buf.length() == 1)
  assert_true(buf.bit_at(0) == 0)
}

///|
/// 部分字节：append 3 bit (0b101)，to_bytes 高位补零 -> 0xA0。
/// bits=[1,0,1]，byte0 = 1<<7 | 0<<6 | 1<<5 = 160 = 0xA0。
test "bb partial: 3 bits high pad zero" {
  let buf = @qr.BitBuffer::new()
  buf.append_bits(0b101, 3)
  assert_true(buf.length() == 3)
  let bytes = buf.to_bytes()
  assert_true(bytes.length() == 1)
  assert_true(bytes[0] == 0xA0)
}

///|
/// 部分字节：append 5 bit (0b10101)，to_bytes 高位补零 -> 0xA8。
/// bits=[1,0,1,0,1]，byte0 = 1<<7|0<<6|1<<5|0<<4|1<<3 = 168 = 0xA8。
test "bb partial: 5 bits high pad zero" {
  let buf = @qr.BitBuffer::new()
  buf.append_bits(0b10101, 5)
  assert_true(buf.length() == 5)
  let bytes = buf.to_bytes()
  assert_true(bytes.length() == 1)
  assert_true(bytes[0] == 0xA8)
}

///|
/// 部分字节：append 7 bit (0b1101011)，to_bytes 高位补零 -> 0xD6。
/// bits=[1,1,0,1,0,1,1]，byte0 = 1<<7|1<<6|0<<5|1<<4|0<<3|1<<2|1<<1 = 214 = 0xD6。
test "bb partial: 7 bits high pad zero" {
  let buf = @qr.BitBuffer::new()
  buf.append_bits(0b1101011, 7)
  assert_true(buf.length() == 7)
  let bytes = buf.to_bytes()
  assert_true(bytes.length() == 1)
  assert_true(bytes[0] == 0xD6)
}

///|
/// 大流：1000 bit (125 字节) 往返，append_bytes → to_bytes 一致。
test "bb large: 1000 bits roundtrip" {
  let n = 125
  let data = FixedArray::make(n, 0)
  for i = 0; i < n; i = i + 1 {
    data[i] = (i * 31 + 17) & 0xFF
  }
  let buf = @qr.BitBuffer::new()
  buf.append_bytes(data)
  assert_true(buf.length() == 1000)
  let bytes = buf.to_bytes()
  assert_true(bytes.length() == n)
  assert_true(bb_eq(bytes, data))
}

///|
/// 大流：5000 bit (625 字节) 往返。
test "bb large: 5000 bits roundtrip" {
  let n = 625
  let data = FixedArray::make(n, 0)
  for i = 0; i < n; i = i + 1 {
    data[i] = (i * 7 + 3) & 0xFF
  }
  let buf = @qr.BitBuffer::new()
  buf.append_bytes(data)
  assert_true(buf.length() == 5000)
  let bytes = buf.to_bytes()
  assert_true(bytes.length() == n)
  assert_true(bb_eq(bytes, data))
}

///|
/// 位模式 0b000：3 bit 全 0，to_bytes = [0x00]。
test "bb pattern: 0b000 three bits" {
  let buf = @qr.BitBuffer::new()
  buf.append_bits(0b000, 3)
  assert_true(buf.length() == 3)
  assert_true(buf.bit_at(0) == 0)
  assert_true(buf.bit_at(1) == 0)
  assert_true(buf.bit_at(2) == 0)
  let bytes = buf.to_bytes()
  assert_true(bytes[0] == 0x00)
}

///|
/// 位模式 0b111：3 bit 全 1，to_bytes = [0xE0]。
/// bits=[1,1,1]，byte0 = 1<<7|1<<6|1<<5 = 224 = 0xE0。
test "bb pattern: 0b111 three bits" {
  let buf = @qr.BitBuffer::new()
  buf.append_bits(0b111, 3)
  assert_true(buf.length() == 3)
  assert_true(buf.bit_at(0) == 1)
  assert_true(buf.bit_at(1) == 1)
  assert_true(buf.bit_at(2) == 1)
  let bytes = buf.to_bytes()
  assert_true(bytes[0] == 0xE0)
}

///|
/// 位模式 0b101：to_bytes = [0xA0]。
test "bb pattern: 0b101 three bits" {
  let buf = @qr.BitBuffer::new()
  buf.append_bits(0b101, 3)
  assert_true(buf.bit_at(0) == 1)
  assert_true(buf.bit_at(1) == 0)
  assert_true(buf.bit_at(2) == 1)
  let bytes = buf.to_bytes()
  assert_true(bytes[0] == 0xA0)
}

///|
/// 位模式 0b010：to_bytes = [0x40]。
/// bits=[0,1,0]，byte0 = 1<<6 = 64 = 0x40。
test "bb pattern: 0b010 three bits" {
  let buf = @qr.BitBuffer::new()
  buf.append_bits(0b010, 3)
  assert_true(buf.bit_at(0) == 0)
  assert_true(buf.bit_at(1) == 1)
  assert_true(buf.bit_at(2) == 0)
  let bytes = buf.to_bytes()
  assert_true(bytes[0] == 0x40)
}

///|
/// append_bytes 往返：bytes → append → to_bytes 完全一致。
test "bb append bytes: roundtrip identity" {
  let data = bb_mk([0x00, 0x01, 0x7F, 0x80, 0xFF, 0x42, 0xAA, 0x55, 0x33, 0xCC])
  let buf = @qr.BitBuffer::new()
  buf.append_bytes(data)
  assert_true(buf.length() == 80)
  let bytes = buf.to_bytes()
  assert_true(bb_eq(bytes, data))
}

///|
/// 位索引边界：bit_at(0) 取首位。
test "bb bit at: first index zero" {
  let buf = @qr.BitBuffer::new()
  buf.append_bits(0b1011, 4)
  assert_true(buf.bit_at(0) == 1)
}

///|
/// 位索引边界：bit_at(len-1) 取末位。
test "bb bit at: last index len minus one" {
  let buf = @qr.BitBuffer::new()
  buf.append_bits(0b1011, 4)
  let last = buf.length() - 1
  assert_true(last == 3)
  assert_true(buf.bit_at(last) == 1)
}

///|
/// 位索引越界：bit_at(len) 会 abort（self.bits[i] 越界），无法安全直接调用。
/// 此处锁定 bit_at(len-1) 为最近合法边界，并验证 length 不被越界访问影响。
test "bb bit at: out of range documented" {
  // bit_at(length) 不可测：self.bits[length] 越界 abort (bits.mbt:38)
  let buf = @qr.BitBuffer::new()
  buf.append_bits(0b100, 3)
  let len = buf.length()
  assert_true(len == 3)
  // 锁定最近合法边界 bit_at(len-1)
  assert_true(buf.bit_at(len - 1) == 0)
}

///|
/// 字节对齐：append 8 bit 后 length=8，to_bytes 长度=1（恰好对齐）。
test "bb byte aligned: 8 bits exact" {
  let buf = @qr.BitBuffer::new()
  buf.append_bits(0xAB, 8)
  assert_true(buf.length() == 8)
  let bytes = buf.to_bytes()
  assert_true(bytes.length() == 1)
  assert_true(bytes[0] == 0xAB)
}

///|
/// 字节对齐：append 16 bit 后 length=16，to_bytes 长度=2。
test "bb byte aligned: 16 bits exact" {
  let buf = @qr.BitBuffer::new()
  buf.append_bits(0xAB, 8)
  buf.append_bits(0xCD, 8)
  assert_true(buf.length() == 16)
  let bytes = buf.to_bytes()
  assert_true(bytes.length() == 2)
  assert_true(bytes[0] == 0xAB)
  assert_true(bytes[1] == 0xCD)
}

///|
/// 字节对齐：append 24 bit 后 length=24，to_bytes 长度=3。
test "bb byte aligned: 24 bits exact" {
  let buf = @qr.BitBuffer::new()
  buf.append_bits(0x12, 8)
  buf.append_bits(0x34, 8)
  buf.append_bits(0x56, 8)
  assert_true(buf.length() == 24)
  let bytes = buf.to_bytes()
  assert_true(bytes.length() == 3)
  assert_true(bytes[0] == 0x12)
  assert_true(bytes[1] == 0x34)
  assert_true(bytes[2] == 0x56)
}

///|
/// 混合 append：bits + bytes + bits 往返。
/// append_bits(0b1100,4) + append_bytes([0xF0]) + append_bits(0b11,2)
/// bits=[1,1,0,0,1,1,1,1,0,0,0,0,1,1]，length=14
/// byte0 = 0xCF, byte1 = 0x0C。
test "bb mixed: bits bytes bits roundtrip" {
  let buf = @qr.BitBuffer::new()
  buf.append_bits(0b1100, 4)
  buf.append_bytes(bb_mk([0xF0]))
  buf.append_bits(0b11, 2)
  assert_true(buf.length() == 14)
  assert_true(buf.bit_at(0) == 1)
  assert_true(buf.bit_at(3) == 0)
  assert_true(buf.bit_at(4) == 1)
  assert_true(buf.bit_at(11) == 0)
  assert_true(buf.bit_at(12) == 1)
  assert_true(buf.bit_at(13) == 1)
  let bytes = buf.to_bytes()
  assert_true(bytes.length() == 2)
  assert_true(bytes[0] == 0xCF)
  assert_true(bytes[1] == 0x0C)
}

///|
/// 容量边界：100000 bit (12500 字节) 大流往返。
/// 注：Int32 上限约 2.1e9，此处用 1e5 bit 验证大流稳定性，
/// 更接近上限的测试受 JS 堆内存限制，不在此处触发。
test "bb capacity: 100000 bits large stream" {
  let n = 12500
  let data = FixedArray::make(n, 0)
  for i = 0; i < n; i = i + 1 {
    data[i] = (i * 5 + 11) & 0xFF
  }
  let buf = @qr.BitBuffer::new()
  buf.append_bytes(data)
  assert_true(buf.length() == 100000)
  let bytes = buf.to_bytes()
  assert_true(bytes.length() == n)
  assert_true(bb_eq(bytes, data))
}
