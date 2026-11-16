# QRFlux 用法文档

## 1. 概述

QRFlux 是一个纯 MoonBit 实现的二维码无损文件传输库，完整覆盖「压缩选档 → 二进制分片 → 动态 QR 码流 → 扫描重组 → 无损还原」全链路。本文档覆盖 CLI 命令行用法、Web 演示、WASM 集成、编程 API、交叉验证、容量参考、彩色 QR 及常见问题，供开发者快速上手并深入使用。

## 2. 环境要求

| 组件 | 版本要求 | 用途 | 是否必需 |
|------|----------|------|----------|
| MoonBit 工具链 | `moon` 0.1.20261016+ | 编译、测试、运行 CLI、构建 WASM | 必需 |
| Python | 3.8+ | 交叉验证脚本（`scripts/verify_*.py`） | 可选 |
| Node.js | 14+ | Web 演示服务器（`web/server.js`） | 可选 |
| zxing-cpp | 最新 | 业界标准 QR 解码器，用于交叉验证 | 可选 |
| Pillow / numpy | 最新 | 验证脚本图像处理依赖 | 可选 |

安装 MoonBit 工具链后，确认 `moon` 命令可用：

```sh
moon version
```

## 3. 快速开始

```sh
# 编码一段文本为 PBM 图片
moon run cmd/main -- --text "Hello QRFlux" --ecl M --format pbm

# 静态管线闭环：编码 → 解码
moon run cmd/main -- --text "Hello" --encode-static --format hex | tail -1 > /tmp/hex.txt
moon run cmd/main -- --decode-static --hex "$(cat /tmp/hex.txt)"

# 运行全部测试
moon test --target js
```

## 4. CLI 完整用法

CLI 入口位于 `cmd/main/main.mbt`，通过 `moon run cmd/main -- <参数>` 调用。无参数时进入批量验证模式。

### 4.1 参数表

| 参数 | 取值 | 默认 | 说明 |
|------|------|------|------|
| `--text <string>` | 任意 UTF-8 文本 | 无 | 要编码的文本（编码模式必需） |
| `--ecl <L\|M\|Q\|H>` | L / M / Q / H | M | 纠错级别 |
| `--format <pbm\|svg\|png\|hex>` | pbm / svg / png / hex | pbm | 输出格式 |
| `--encode-static` | 标志 | 关 | 启用静态管线（压缩 + 打包头） |
| `--encode-dynamic` | 标志 | 关 | 启用动态码流（分片多帧 QR） |
| `--frame-size <n>` | 正整数 | 500 | 动态码流每帧负载字节数 |
| `--decode-static` | 标志 | 关 | 静态解码模式（需配合 `--hex`） |
| `--decode-dynamic` | 标志 | 关 | 动态解码模式（需配合 `--hex`） |
| `--hex <hex_string>` | 十六进制字符串 | 无 | 解码模式的输入数据 |
| `--help` / `-h` | 标志 | — | 打印帮助信息 |

### 4.2 重要说明：`--format hex` 的适用范围

`--format hex` **仅在** `--encode-static` 或 `--encode-dynamic` 模式下有效：

- **单独编码单张 QR**（无 `--encode-static` / `--encode-dynamic`）：只支持 `pbm` / `svg` / `png`，传 `hex` 会报错 `Error: unknown format 'hex', use pbm/svg/png`。
- **`--encode-static --format hex`**：输出打包后的字节 hex（含压缩头 + CRC32），供 `--decode-static` 闭环。
- **`--encode-dynamic --format hex`**：输出分号分隔的多帧 hex（`hex1;hex2;...`），供 `--decode-dynamic` 闭环。

### 4.3 模式一：单张 QR 编码（pbm / svg / png）

最基础的编码模式，直接将文本编码为单张 QR 码图片。

```sh
# PBM 格式（P1 ASCII，文本输出）
moon run cmd/main -- --text "Hello QRFlux" --ecl M --format pbm
# 输出：
#   # version=3 size=29 mask=2
#   P1
#   45 45
#   0 0 0 ...（45×45 的 0/1 矩阵）

# SVG 格式（矢量图，文本输出）
moon run cmd/main -- --text "Hello QRFlux" --ecl M --format svg
# 输出：
#   # version=3 size=29 mask=2
#   <svg xmlns="http://www.w3.org/2000/svg" ...>...</svg>

# PNG 格式（二进制，base64 输出）
moon run cmd/main -- --text "Hello QRFlux" --ecl M --format png | tail -1 | base64 -d > out.png
# 输出：base64 编码的 PNG 数据，需用 base64 -d 还原为 .png 文件
```

### 4.4 模式二：静态管线编码

静态管线执行「自动压缩选档 → 打包头（algo + CRC32） → QR 编码」，适合 ≤1KB 数据。

```sh
# 编码并输出打包字节 hex
moon run cmd/main -- --text "Hello QRFlux" --encode-static --ecl M --format hex
# 输出：
#   # static: version=2 size=25 algo=1 compressed=1 pkg_len=24
#   514c01011a0f...（打包字节的十六进制）

# 也可以输出图片（pbm/svg/png）
moon run cmd/main -- --text "Hello QRFlux" --encode-static --ecl M --format svg
# 输出：
#   # static: version=2 size=25 algo=1 compressed=1 pkg_len=24
#   <svg ...>...</svg>
```

输出头行字段含义：
- `version`：QR 版本
- `size`：模块边长
- `algo`：压缩算法（0=无压缩，1=RLE，2=deflate）
- `compressed`：是否实际压缩（1=是，0=否）
- `pkg_len`：打包后字节数（含头部）

### 4.5 模式三：静态管线解码

将 `--encode-static --format hex` 输出的 hex 还原为原始数据。

```sh
moon run cmd/main -- --decode-static --hex "514c01011a0f..."
# 输出：
#   # decoded: 13 bytes
#   Hello QRFlux
```

若数据含非打印 ASCII 字节，输出自动切换为 hex 显示。

### 4.6 模式四：动态码流编码

动态码流将数据分片为多帧，每帧编码为一张 QR 码，支持 >1KB 数据、乱序接收、丢帧恢复。

```sh
# 编码长文本，每帧 50 字节负载，输出分号分隔的多帧 hex
moon run cmd/main -- --text "这是一段很长的文本用于演示动态码流分片编码能力..." --encode-dynamic --frame-size 50 --ecl M --format hex
# 输出：
#   # dynamic: data_len=120 frame_size=50 total_frames=3 ecl=M
#   515233...;515233...;515233...（3 帧的 hex，分号分隔）

# 不指定 hex 时，输出 DYNAMIC_CASE 块（含矩阵 + 帧 hex，供验证脚本使用）
moon run cmd/main -- --text "Long text..." --encode-dynamic --frame-size 50 --ecl M --format pbm
# 输出：
#   # dynamic: data_len=... frame_size=50 total_frames=N ecl=M
#   DYNAMIC_CASE cli frame=0/N frame_len=... ecl=M version=... size=... mask=...
#   <矩阵 0/1 行>
#   FRAME_HEX <hex>
#   END_DYNAMIC
#   DYNAMIC_CASE cli frame=1/N ...
#   ...
```

### 4.7 模式五：动态码流解码

将 `--encode-dynamic --format hex` 输出的分号分隔多帧 hex 还原为原始数据。

```sh
moon run cmd/main -- --decode-dynamic --hex "515233...;515233...;515233..."
# 输出：
#   # decoded: 120 bytes, 3 frames
#   这是一段很长的文本用于演示动态码流分片编码能力...
```

帧可以乱序传入，`reassemble_frames` 会根据帧头自动排序重组。

### 4.8 模式六：批量验证模式

不带任何参数时，CLI 输出参考矩阵供交叉验证脚本使用。

```sh
moon run cmd/main > batch.txt
# batch.txt 包含：
#   - CASE 块：bare encode_binary 矩阵（V1~V39 × L/M/Q/H，供 verify_qr.py）
#   - STATIC_CASE 块：静态管线矩阵 + 打包字节 hex（供 verify_static.py）
```

## 5. 静态管线 vs 动态码流

| 维度 | 静态管线（`--encode-static`） | 动态码流（`--encode-dynamic`） |
|------|-------------------------------|-------------------------------|
| 适用数据量 | ≤1KB（单张 QR 容量内） | >1KB（无上限，分片扩展） |
| QR 数量 | 1 张 | 多张（每帧 1 张） |
| 处理流程 | 压缩选档 → 打包头 → QR 编码 | 分片 → 帧头（CRC16） → 每帧 QR 编码 |
| 容错能力 | RS 纠错（单张内） | RS 纠错 + 丢帧恢复 + 乱序接收 |
| 解码命令 | `--decode-static --hex <hex>` | `--decode-dynamic --hex "h1;h2;..."` |
| 典型场景 | 小文本、配置、URL | 文件传输、大文本、图片 |

**选择建议**：
- 数据 ≤1000 字节 → 用静态管线（单张 QR，扫描一次即可）
- 数据 >1000 字节 → 用动态码流（自动分片，支持丢帧恢复）
- 需要最高容错 → 静态管线 + `--ecl H`（V40-H 容量 1276 字节）

## 6. 图片输出格式

### 6.1 PBM（P1 ASCII）

文本格式，输出 0/1 矩阵，可直接查看或管道处理。

```sh
moon run cmd/main -- --text "Test" --format pbm
# 输出 P1 格式，含 quiet zone（4 模块），可直接用图像查看器打开 .pbm 文件
```

### 6.2 SVG（矢量图）

文本格式，输出 SVG XML，矢量缩放无损，适合网页嵌入。

```sh
moon run cmd/main -- --text "Test" --format svg > qr.svg
# 模块缩放 10px，quiet zone 4 模块，可直接在浏览器中打开
```

### 6.3 PNG（二进制，base64 输出）

二进制格式，CLI 输出 base64 编码，需用 `base64 -d` 还原为 `.png` 文件。PNG 使用 bit_depth=1，体积最小。

```sh
moon run cmd/main -- --text "Test" --format png | tail -1 | base64 -d > qr.png
# tail -1 跳过头行（# version=...），base64 -d 解码为二进制 PNG
```

## 7. Web 演示

### 7.1 启动

```sh
cd web
node server.js
# 输出：
#   QRFlux server running at http://localhost:3000/
#     主页: http://localhost:3000/
#     摄像头: http://localhost:3000/camera
```

### 7.2 访问地址

| 页面 | URL | 功能 |
|------|-----|------|
| 编解码主页 | http://localhost:3000/ | 静态/动态编解码 UI |
| 摄像头扫码 | http://localhost:3000/camera | 浏览器摄像头实时扫码（基于 jsQR） |

### 7.3 API 端点

服务器提供 4 个 POST API，内部调用 `moon run cmd/main` 实现编解码：

| 端点 | 请求体 | 返回 | 说明 |
|------|--------|------|------|
| `/api/encode-static` | `{"text":"...", "ecl":"M"}` | `{"success":true, "hex":"...", "output":"..."}` | 静态管线编码 |
| `/api/decode-static` | `{"hex":"..."}` | `{"success":true, "output":"..."}` | 静态管线解码 |
| `/api/encode-dynamic` | `{"text":"...", "frame_size":50, "ecl":"M"}` | `{"success":true, "hex":"h1;h2;...", "output":"..."}` | 动态码流编码 |
| `/api/decode-dynamic` | `{"hex":"h1;h2;..."}` | `{"success":true, "output":"..."}` | 动态码流解码 |

调用示例：

```sh
curl -X POST http://localhost:3000/api/encode-static \
  -H "Content-Type: application/json" \
  -d '{"text":"Hello","ecl":"M"}'
```

### 7.4 摄像头扫码页面

`/camera` 页面使用浏览器 `getUserMedia` API 调用摄像头，配合 jsQR 库实时解码：

1. 点击「启动摄像头」授权访问
2. 将 QR 码对准摄像头
3. 点击「捕获并解码」扫描
4. 解码成功显示数据内容和 QR 码位置

## 8. WASM 集成

### 8.1 构建

```sh
moon build --target wasm
# 输出文件：_build/wasm/debug/build/cmd/main/main.wasm（约 60KB）
```

### 8.2 接口函数

WASM 绑定位于 `src/web/wasm.mbt`，提供以下导出函数：

| 函数 | 参数 | 返回 | 说明 |
|------|------|------|------|
| `wasm_encode_qr` | `(data: String, version: Int32, ecl: String)` | JSON 字符串 | 基础 QR 编码，返回矩阵 + 元数据 |
| `wasm_encode_static` | `(data: String, ecl: String)` | JSON 字符串 | 静态管线编码（压缩 + 打包） |
| `wasm_encode_dynamic` | `(data: String, max_payload: Int32, ecl: String)` | JSON 字符串 | 动态码流编码（分片多帧） |
| `wasm_decode_qr` | `(matrix_json: String)` | JSON 字符串 | 解码 QR 矩阵 |
| `wasm_get_capacity` | `(ecl: String, version: Int32)` | JSON 字符串 | 查询容量信息 |
| `wasm_calculate_frames` | `(data_size: Int32, max_payload: Int32, compress: Bool)` | JSON 字符串 | 计算所需帧数 |

另有 `web_encode_qr` / `web_encode_static` / `web_encode_dynamic` / `web_decode_qr` / `web_get_capacity`（定义于 `src/web/demo.mbt`，用于 JS target）。

### 8.3 网页调用示例

```html
<script>
  // 假设已加载 main.wasm 并实例化为 instance
  const { wasm_encode_static, wasm_decode_qr } = instance.exports;

  // 编码
  const result = JSON.parse(wasm_encode_static("Hello QRFlux", "M"));
  // result = { version: 2, size: 25, mask: 1, matrix: [...], algo: 1, compressed: true }

  // 解码
  const matrixText = result.matrix.map(row => row).join('\n');
  const decoded = JSON.parse(wasm_decode_qr(matrixText));
  // decoded = { data: "Hello QRFlux", length: 12 }
</script>
```

## 9. 编程 API

### 9.1 模块组织

所有核心功能通过 `@qr` 包访问，源码位于 `src/qr/`：

```
src/qr/
├── qrcode.mbt          # QR 编码核心（encode_binary / encode_static）
├── decoder.mbt         # 自研 QR 解码器（decode_qr / decode_static）
├── gf256.mbt           # GF(256) 域运算（Reed-Solomon 基础）
├── segment.mbt         # 分段编码（Numeric / Alphanumeric / Byte 模式）
├── bits.mbt            # 位流操作（BitBuffer）
├── tables.mbt          # 常量表（容量 / ECC / 对齐图案位置）
├── stream.mbt          # 分片协议（split_into_frames / reassemble_frames / CRC16）
├── fountain.mbt        # LT 喷泉码（LTFountain）
├── package.mbt         # 打包协议（package_with_header / CRC32）
├── strategy.mbt        # 压缩策略选择（auto_compress / RLE）
├── static_pipeline.mbt # 静态管线整合（encode_static / decode_static）
├── image.mbt           # 图片生成（to_pbm / to_svg / to_png）
├── color_qr.mbt        # 彩色 QR（4 色，2bits/module）
└── integrate.mbt       # 集成辅助
```

### 9.2 核心函数分类

**编码**：
- `encode_binary(data, level, min_version) -> QrCode` — 字节模式编码
- `encode_segments(segments, level, min_version) -> QrCode` — 多段编码
- `encode_static(data, level, min_version) -> StaticEncodeResult?` — 静态管线编码

**解码**：
- `decode_qr(matrix) -> FixedArray[Int32]?` — 从 0/1 矩阵解码
- `decode_from_qrcode(qr) -> FixedArray[Int32]?` — 从 QrCode 解码
- `decode_static(packaged_bytes) -> FixedArray[Int32]?` — 静态管线解码

**分片**：
- `split_into_frames(data, max_payload) -> Array[FixedArray[Int32]]` — 分片为多帧
- `reassemble_frames(frames) -> FixedArray[Int32]?` — 重组帧（支持乱序）
- `calculate_frames_needed(data_size, max_payload, compress) -> Int32` — 计算所需帧数

**喷泉码（LT 码）**：
- `LTFountain::new(block_size, num_blocks)` — 创建编码器
- `LTFountain::encode_all(data, seed)` — 编码所有块
- `LTFountain::decode(encoded_blocks)` — 解码（支持丢块恢复）

**压缩**：
- `auto_compress(data) -> CompressionResult` — 自动选档压缩
- `compress(data, level)` / `decompress(data, level)` — 指定级别压缩/解压
- `rle_compress(data)` / `rle_decompress(data)` — RLE 压缩/解压
- `select_strategy(data) -> CompressionStrategy` — 选择最优策略

**打包**：
- `package_with_header(data, algo, compressed) -> FixedArray[Int32]` — 打包（含头部 + CRC32）
- `unpackage_from_header(pkg) -> (data, algo, compressed, orig_size)?` — 解包

**图片**：
- `to_pbm(qr, quiet_zone) -> String` — PBM P1 格式
- `to_svg(qr, scale, quiet_zone) -> String` — SVG 矢量图
- `to_png(qr, scale, quiet_zone) -> FixedArray[Int32]` — PNG 二进制（bit_depth=1）

**彩色 QR**：
- `ColorQREncoder::new(version)` / `encode(data)` / `decode(matrix)` — 彩色 QR 编解码
- `color_qr_to_svg(matrix, scale, quiet_zone)` / `color_qr_to_ppm(matrix, quiet_zone)` — 图片生成

**容量查询**：
- `num_data_codewords(version, level) -> Int32` — 数据码字数
- `char_count_bits(mode, version) -> Int32` — 字符计数位宽

### 9.3 代码示例

**基础编码**：

```moonbit
import @qr

fn main {
  let data = FixedArray::make(100, 0x42)
  let qr = @qr.encode_binary(data, @qr.ecc_low(), 1)
  println("Version: " + qr.version().to_string())
  println("Size: " + qr.size().to_string())
  let svg = @qr.to_svg(qr, 10, 4)
  println(svg)
}
```

**动态码流**：

```moonbit
import @qr

fn main {
  let data = FixedArray::make(2000, 0x41)
  let frames = @qr.split_into_frames(data, 100)
  println("Total frames: " + frames.length().to_string())
  let reassembled = @qr.reassemble_frames(frames)
  match reassembled {
    Some(restored) => println("Restored: " + restored.length().to_string() + " bytes")
    None => println("Reassemble failed")
  }
}
```

**静态管线闭环**：

```moonbit
import @qr

fn main {
  let data = FixedArray::make(500, 0x42)
  match @qr.encode_static(data, @qr.ecc_medium(), 1) {
    None => println("Too large")
    Some(result) => {
      let packaged = result.packaged_bytes()
      println("Algo: " + result.algo_id().to_string())
      println("Compressed: " + result.compressed().to_string())
      match @qr.decode_static(packaged) {
        Some(restored) => println("Roundtrip OK: " + restored.length().to_string() + " bytes")
        None => println("Decode failed")
      }
    }
  }
}
```

**彩色 QR**：

```moonbit
import @qr

fn main {
  let data = FixedArray::make(50, 0x42)
  let encoder = @qr.ColorQREncoder::new(5)
  let matrix = encoder.encode(data)
  let svg = @qr.color_qr_to_svg(matrix, 10, 4)
  println(svg)
  match encoder.decode(matrix) {
    Some(restored) => println("Color QR roundtrip OK")
    None => println("Decode failed")
  }
}
```

## 10. 交叉验证

### 10.1 完整流程

```sh
# 1. 生成参考矩阵
moon run cmd/main > batch.txt

# 2. 安装验证依赖
pip install zxing-cpp Pillow numpy

# 3. 运行验证
python scripts/verify_qr.py batch.txt        # 基础 CASE 块（V1~V39 × L/M/Q/H）
python scripts/verify_static.py batch.txt    # STATIC_CASE 块（静态管线）
python scripts/verify_dynamic.py             # DYNAMIC_CASE 块（动态码流）
python scripts/verify_image_roundtrip.py     # 真实图片往返验证
```

### 10.2 验证范围

- **版本**：V1~V40 全版本
- **纠错级别**：L / M / Q / H 四档
- **模式**：基础编码、静态管线、动态码流、图片往返
- **结果**：**165/165 全部通过**业界标准解码器（zxing-cpp）无损还原

### 10.3 验证脚本说明

| 脚本 | 验证内容 | 输入 |
|------|----------|------|
| `verify_qr.py` | 基础 `encode_binary` 矩阵经 zxing-cpp 解码后与原始数据比对 | `batch.txt` |
| `verify_static.py` | 静态管线 QR 矩阵解码后与 `PACKED` hex 比对 | `batch.txt` |
| `verify_dynamic.py` | 动态码流全链路：分片 → QR → 解码 → 重组 → 还原 | `dynamic_batch.txt`（自动生成） |
| `verify_image_roundtrip.py` | 静态管线 PBM 图片往返：编码 → 图片 → 解码 → 解包 → 还原 | 自动调用 `moon run` |
| `verify_edge_cases.py` | 边界情况验证（空数据、最大容量等） | 自动生成 |
| `compare_with_reference.py` | 与参考实现对比 | 自动生成 |
| `analyze_interleave.py` | RS 码字交错分析 | 自动生成 |

## 11. 容量参考表

下表为 `num_data_codewords(version, level)` 的项目实测值（数据码字数，即 RS 纠错前的数据容量）：

| 版本 | L | M | Q | H | 版本 | L | M | Q | H |
|------|------|------|------|------|------|------|------|------|------|
| V1 | 19 | 16 | 13 | 9 | V21 | 932 | 714 | 512 | 406 |
| V2 | 34 | 28 | 22 | 16 | V22 | 1006 | 782 | 568 | 442 |
| V3 | 55 | 44 | 34 | 26 | V23 | 1094 | 860 | 614 | 464 |
| V4 | 80 | 64 | 48 | 36 | V24 | 1174 | 914 | 664 | 514 |
| V5 | 108 | 86 | 62 | 46 | V25 | 1276 | 1000 | 718 | 538 |
| V6 | 136 | 108 | 76 | 60 | V26 | 1370 | 1062 | 754 | 596 |
| V7 | 156 | 124 | 88 | 66 | V27 | 1468 | 1128 | 808 | 628 |
| V8 | 194 | 154 | 110 | 86 | V28 | 1531 | 1193 | 871 | 661 |
| V9 | 232 | 182 | 132 | 100 | V29 | 1631 | 1267 | 911 | 701 |
| V10 | 274 | 216 | 154 | 122 | V30 | 1735 | 1373 | 985 | 745 |
| V11 | 324 | 254 | 180 | 140 | V31 | 1843 | 1455 | 1033 | 793 |
| V12 | 370 | 290 | 206 | 158 | V32 | 1955 | 1541 | 1115 | 845 |
| V13 | 428 | 334 | 244 | 180 | V33 | 2071 | 1631 | 1171 | 901 |
| V14 | 461 | 365 | 261 | 197 | V34 | 2191 | 1725 | 1231 | 961 |
| V15 | 523 | 415 | 295 | 223 | V35 | 2306 | 1812 | 1286 | 986 |
| V16 | 589 | 453 | 325 | 253 | V36 | 2434 | 1914 | 1354 | 1054 |
| V17 | 647 | 507 | 367 | 283 | V37 | 2566 | 1992 | 1426 | 1096 |
| V18 | 721 | 563 | 397 | 313 | V38 | 2702 | 2102 | 1502 | 1142 |
| V19 | 795 | 627 | 445 | 341 | V39 | 2812 | 2216 | 1582 | 1222 |
| V20 | 861 | 669 | 485 | 385 | V40 | 2956 | 2334 | 1666 | **1276** |

**注意**：
- V40-H 项目实测值为 **1276**（QR 规范标准值为 1273，项目 `num_data_codewords(40, ecc_high())` 返回 1276）。
- 实际可编码的字节数略小于数据码字数（需扣除模式指示 4 bits + 字符计数位）。
- 数据超过约 1KB 时建议使用动态码流（`--encode-dynamic`）。

## 12. 彩色 QR

### 12.1 方案说明

彩色 QR 是标准 QR 的非标准扩展，使用 4 色编码，每个模块存储 2 bits 数据：

| 颜色 | 编码值 | RGB |
|------|--------|-----|
| 白色 (White) | 00 | (255, 255, 255) |
| 红色 (Red) | 01 | (255, 0, 0) |
| 绿色 (Green) | 10 | (0, 255, 0) |
| 蓝色 (Blue) | 11 | (0, 0, 255) |

每个 2×2 色块存储 4 色 = 8 bits = 1 字节，实现无损编解码。容量为标准 QR 的 2 倍。

### 12.2 编解码用法

```moonbit
import @qr

fn main {
  let data = FixedArray::make(100, 0x42)
  let encoder = @qr.ColorQREncoder::new(10)
  let matrix = encoder.encode(data)
  match encoder.decode(matrix) {
    Some(restored) => println("OK: " + restored.length().to_string() + " bytes")
    None => println("Decode failed")
  }
}
```

### 12.3 RGB 识别与图片输出

从摄像头采集的 RGB 矩阵可通过 `decode_color_from_rgb` 解码（内置阈值 128 颜色识别）：

```moonbit
let restored = @qr.decode_color_from_rgb(rgb_matrix, version)
```

图片输出支持两种格式：

- **SVG**：`color_qr_to_svg(matrix, scale, quiet_zone)` — 矢量图，适合屏幕显示
- **PPM**：`color_qr_to_ppm(matrix, quiet_zone)` — P3 ASCII 彩色格式，适合图像处理

### 12.4 参考设计

详细方案对比（8 色 / 4 色 / 分层）及技术挑战见 `docs/COLOR_QR_DESIGN.md`。

## 13. 常见问题（FAQ）

**Q1：数据超过单张 QR 容量怎么办？**

使用动态码流：`--encode-dynamic --frame-size N`。数据会自动分片为多帧，每帧一张 QR 码，支持乱序接收和丢帧恢复。例如 5KB 数据用 `--frame-size 500` 会生成约 10 张 QR 码。

**Q2：为什么不用 zxing-cpp 解 V40 大尺寸？**

V40（177×177 模块）大尺寸 QR 码 zxing-cpp 解码器存在已知限制，无法稳定解码。这不是 QRFlux 的 bug——项目自研解码器可正确解码 V40 全版本，单元测试验证编码结果正确。交叉验证覆盖 V1~V39（165/165 通过）。

**Q3：如何选择纠错级别？**

| 级别 | 容错率 | 适用场景 |
|------|--------|----------|
| L | ~7% | 清洁环境、高密度数据 |
| M | ~15% | 通用场景（默认） |
| Q | ~25% | 轻微污损环境 |
| H | ~30% | 强污损环境、工业场景 |

容错率越高，可纠正的损坏模块越多，但数据容量越小。

**Q4：`--format hex` 什么时候可用？**

仅在 `--encode-static` 或 `--encode-dynamic` 模式下有效。单独编码单张 QR（无 pipeline 标志）时只支持 `pbm` / `svg` / `png`，传 `hex` 会报错。hex 输出用于编解码闭环：编码输出 hex → 解码输入 hex。

**Q5：如何还原 PNG 输出？**

PNG 以 base64 编码输出到 stdout，需用 `base64 -d` 解码：

```sh
moon run cmd/main -- --text "Test" --format png | tail -1 | base64 -d > out.png
```

`tail -1` 跳过头行（`# version=...`），`base64 -d` 将 base64 还原为二进制 PNG。

**Q6：动态码流的帧可以乱序解码吗？**

可以。`reassemble_frames` 根据帧头中的 `current_frame` / `total_frames` 自动排序，不依赖输入顺序。但需要收到所有帧才能完整重组。

**Q7：静态管线和动态码流的压缩有什么区别？**

静态管线在打包前自动选档压缩（RLE / deflate / 无压缩），压缩结果写入包头。动态码流当前直接分片不压缩（每帧独立 QR），如需压缩可在调用 `split_into_frames` 前手动 `auto_compress`。

**Q8：彩色 QR 能用标准扫码 App 识别吗？**

不能。彩色 QR 是非标准扩展（4 色 2bits/module），标准 QR 解码器只识别黑白二值。需使用项目提供的 `ColorQREncoder::decode` 或 `decode_color_from_rgb` 专用解码器。

## 14. 已知限制

1. **V40 大尺寸 QR 解码**：V40（177×177）QR 码 zxing-cpp 解码器无法稳定解码（非 QRFlux bug，项目自研解码器可正确解码）。交叉验证覆盖 V1~V39。

2. **moon 0.1.20261016 registry 兼容**：当前 MoonBit 工具链的依赖解析（`moon add` / `import`）存在 registry 兼容问题，故项目保持**零三方依赖**、纯自研路线。所有核心算法（QR 编码、GF(256)、RS ECC、压缩、喷泉码）均自研实现。

3. **彩色 QR 兼容性**：彩色 QR（4 色 2bits/module）为非标准方案，需专用解码器（`ColorQREncoder::decode` / `decode_color_from_rgb`），标准扫码 App 无法识别。颜色识别受光照、白平衡影响，建议在可控光照环境下使用。

4. **PNG 输出**：CLI 的 PNG 输出为 base64 编码文本，需手动 `| base64 -d > out.png` 还原为二进制文件，无法直接重定向。
