# QRFlux API 文档

## 概述

QRFlux 是一个纯 MoonBit 实现的二维码无损文件传输库。

## 核心模块

### `src/qr/qrcode.mbt` - QR 编码器核心

#### 主要函数

- `encode_binary(data : FixedArray[Int], level : EccLevel, version : Int) -> QrCode`
  - 编码二进制数据为 QR 码
  - `data`: 输入数据
  - `level`: 纠错级别（Low/Medium/Quartile/High）
  - `version`: QR 版本（1~40），0 表示自动选择

- `num_data_codewords(ver : Int, level : EccLevel) -> Int`
  - 获取指定版本和纠错级别的数据容量（字节）

- `alignment_pattern_positions(ver : Int) -> Array[Int]`
  - 获取对齐模式位置

#### QrCode 结构体

```
pub struct QrCode {
  version : Int    // QR 版本
  size : Int       // 模块大小（边长）
  level : EccLevel // 纠错级别
  mask : Int       // 掩码模式
}
```

#### 方法

- `version() -> Int` - 获取版本
- `size() -> Int` - 获取大小
- `level() -> EccLevel` - 获取纠错级别
- `mask() -> Int` - 获取掩码
- `get_module(x : Int, y : Int) -> Bool` - 获取模块状态

### `src/qr/stream.mbt` - 分片多帧 QR 协议

#### 主要函数

- `split_into_frames(data : FixedArray[Int], max_payload : Int) -> Array[FixedArray[Int]]`
  - 将数据分片为多帧

- `reassemble_frames(frames : Array[FixedArray[Int]]) -> FixedArray[Int]?`
  - 重组分片数据

- `crc16(data : FixedArray[Int]) -> Int`
  - 计算 CRC16 校验和

### `src/qr/fountain.mbt` - LT 喷泉码

#### 主要函数

- `LTFountain::new(block_size : Int, num_blocks : Int) -> LTFountain`
  - 创建喷泉码编码器

- `LTFountain::split(data : FixedArray[Int]) -> Array[FixedArray[Int]]`
  - 分割数据为原始块

- `LTFountain::encode_block(blocks : Array[FixedArray[Int]], seed : Int) -> FixedArray[Int]`
  - 编码单个块

- `LTFountain::decode(encoded_blocks : Array[(Int, FixedArray[Int])]) -> FixedArray[Int]?`
  - 解码数据

### `src/qr/strategy.mbt` - 压缩策略选择

#### 主要函数

- `compress(data : FixedArray[Int], level : CompressionLevel) -> FixedArray[Int]`
  - 压缩数据

- `decompress(data : FixedArray[Int], level : CompressionLevel) -> FixedArray[Int]`
  - 解压缩数据

- `select_strategy(data : FixedArray[Int]) -> CompressionStrategy`
  - 自动选择压缩策略

- `auto_compress(data : FixedArray[Int]) -> CompressionResult`
  - 自动压缩数据

### `src/qr/package.mbt` - 二进制打包协议

#### 主要函数

- `package_with_header(data : FixedArray[Int], compressed : Bool) -> FixedArray[Int]`
  - 打包数据（添加头部）

- `unpackage_from_header(pkg : FixedArray[Int]) -> (FixedArray[Int], Int, Bool)?`
  - 解包数据

- `crc32(data : FixedArray[Int]) -> Int`
  - 计算 CRC32 校验和

## 使用示例

### 基础编码

```
import @qr

fn main {
  let data = FixedArray::make(100, 0x42)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  
  println("Version: " + qr.version().to_string())
  println("Size: " + qr.size().to_string())
}
```

### 动态码流

```
import @qr

fn main {
  let data = FixedArray::make(500, 0x42)
  
  // 压缩
  let compressed = @qr.compress(data, @qr.fast_compress())
  
  // 分片
  let frames = @qr.split_into_frames(compressed, 100)
  
  // 重组
  let reassembled = @qr.reassemble_frames(frames)
  
  // 解压缩
  let decompressed = @qr.decompress(reassembled.unwrap(), @qr.fast_compress())
}
```

## 容量参考

| 版本 | L | M | Q | H |
|------|---|---|---|---|
| V1 | 17 | 14 | 11 | 7 |
| V10 | 346 | 268 | 192 | 140 |
| V20 | 970 | 754 | 532 | 388 |
| V40 | 2953 | 2331 | 1663 | 1273 |

## 纠错级别

- **L (Low)**: 7% 容错
- **M (Medium)**: 15% 容错
- **Q (Quartile)**: 25% 容错
- **H (High)**: 30% 容错
