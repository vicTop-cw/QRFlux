# 静态管线真实图片闭环验证 + 边界 Case 测试报告

**日期**：2026-11-04
**任务**：静态管线真实图片闭环验证和边界 case 测试
**执行人**：FIST 子代理（静态管线验证）

## 结果摘要

静态管线真实图片闭环验证完成，发现 1 个 RLE 解压 bug（count >= 255 时
`decode_static` 使用的 `rle_decompress`（简单版）与 `rle_compress_optimized`
（扩展 run 编码）不匹配）。

## 验证范围

### 1. 真实图片闭环验证（`scripts/verify_image_roundtrip.py`）

验证流程：
```
encode_static → CLI 生成 PBM 图片 → zxing-cpp 解码图片 → 得到打包字节
→ Python decode_static（unpackage + RLE 解压）→ 还原数据 → 比对原始数据
```

**结果：6/6 通过**

| Case | 原始长度 | 版本 | algo | compressed | 编码耗时 | 解码耗时 | 结果 |
|------|---------|------|------|-----------|---------|---------|------|
| hello_5B | 5B | V3 | 0 | 0 | 1751ms | 5ms | OK |
| hello_world_11B | 11B | V4 | 0 | 0 | 5904ms | 10ms | OK |
| random_100B | 100B | V8 | 0 | 0 | 6288ms | 4ms | OK |
| random_500B | 500B | V18 | 0 | 0 | 6062ms | 6ms | OK |
| utf8_chinese | 12B | V4 | 0 | 0 | 6052ms | 1ms | OK |
| repeat_A_100B | 100B | V3 | 1 | 1 | 5179ms | 1ms | OK |

说明：
- `repeat_A_100B` 触发 RLE 压缩（algo=1, comp=1），因 100 < 255 未触发扩展
  run，闭环成功。
- 所有 case 的 zxing-cpp 解码字节与打包字节完全匹配，Python decode_static
  还原数据与原始数据完全匹配。

### 2. 边界 Case 验证（`scripts/verify_edge_cases.py`）

**结果：8 OK, 1 EXPECTED_FAIL, 1 FAIL（共 10 case）**

| Case | 长度 | 版本 | algo | comp | 结果 | 说明 |
|------|------|------|------|------|------|------|
| empty_0B | 0B | V2 | 0 | 0 | OK | 空数据闭环成功（仅 32B header） |
| one_byte_1B | 1B | V3 | 0 | 0 | OK | 最小数据 |
| all_zero_100B | 100B | V3 | 1 | 1 | OK | 全 0x00，RLE 压缩，100<255 OK |
| all_ff_100B | 100B | V3 | 1 | 1 | OK | 全 0xFF，RLE 压缩，100<255 OK |
| ascii_text | 11B | V4 | 0 | 0 | OK | "Hello World" |
| utf8_chinese | 12B | V4 | 0 | 0 | OK | "你好世界" |
| max_v1_l_17B | 17B | V3 | 0 | 0 | OK | 17 字节文本 |
| over_capacity_2950B | 2950B | - | - | - | EXPECTED_FAIL | 打包后 2982B > V40 L 2953B |
| **repeat_A_1000B** | 1000B | V3 | 1 | 1 | **FAIL** | **RLE bug** |
| random_2000B | 2000B | V38 | 0 | 0 | OK | 大随机数据 |

说明：
- `all_zero_100B` 和 `all_ff_100B` 通过 batch 模式提取（CLI --text 无法传递
  null 字节或无效 UTF-8），矩阵转图片后用 zxing-cpp 解码，闭环成功。
- `empty_0B`：encode_static 接受空数据（返回 V2 QR 码，仅含 32 字节 header），
  闭环成功（空 → 空）。这是设计行为，非 bug。
- `over_capacity_2950B`：2950 字节打包后 2982 字节，超过 V40 L 容量 2953 字节，
  encode_static 正确返回 None，CLI 输出 "Error: data too large"。

## 发现的问题

### BUG-1: RLE 压缩/解压不匹配（count >= 255）

**严重程度**：高（数据损坏，闭环失败）

**位置**：
- `src/qr/strategy.mbt:171` — `rle_compress` 调用 `rle_compress_optimized`
- `src/qr/strategy.mbt:177` — `rle_decompress` 是简单版本（2 字节对）
- `src/qr/static_pipeline.mbt:142` — `decode_static` 使用 `rle_decompress`（简单版）

**根因**：
- **编码端**：`encode_static` → `auto_compress` → `compress(Fast)` →
  `rle_compress` = `rle_compress_optimized`
  - count < 255: `[count, value]`（2 字节）
  - count >= 255: `[255, high_byte, low_byte, value]`（4 字节，扩展 run）
- **解码端**：`decode_static` → `rle_decompress`（简单版本）
  - 始终按 2 字节对 `[count, value]` 处理，不识别 255 标记

**触发条件**：连续相同字节数 >= 255（如 1000 个 "A"）

**示例**：
- 输入：1000 个 0x41（"A" * 1000）
- 压缩：`[255, 0x03, 0xE8, 0x41]`（4 字节，1000 = 0x03E8）
- 简单解压错误结果：
  - `[255, 0x03]` → 255 个 0x03
  - `[0xE8, 0x41]` → 232 个 0x41
  - 合计 487 字节，≠ 1000 个 0x41
- optimized 解压正确结果：1000 个 0x41 ✓

**影响**：
- 任何连续相同字节 >= 255 的数据，decode_static 无法正确还原
- 实际场景：大块全零/全 FF 数据、高重复文本（>= 255 字符）

**修复建议**（不在本任务范围，仅记录）：
- 方案 A：`decode_static` 改用 `rle_decompress_optimized`
- 方案 B：`rle_compress` 改用简单版本（不使用扩展 run），但会降低大块重复数据的压缩率
- 推荐方案 A，因 `rle_decompress_optimized` 已实现且正确

## 验证方法说明

### 真实图片闭环（verify_image_roundtrip.py）

1. 用 `moon run cmd/main -- --encode-static --text "<data>" --ecl M --format pbm`
   生成 PBM 图片
2. 解析 PBM P1 ASCII 格式为 numpy 灰度图
3. 用 zxing-cpp 解码图片得到 QR 码原始字节（packaged bytes）
4. Python 实现 `decode_static`（unpackage + RLE 解压）还原数据
5. 比对还原数据与原始数据

### 边界 case（verify_edge_cases.py）

- 文本类 case：同上，用 CLI --text 传递
- 二进制 case（全 0x00/0xFF）：CLI --text 无法传递 null/无效 UTF-8，改用
  batch 模式 STATIC_CASE 块（含 0/1 矩阵 + PACKED hex），矩阵转图片后
  zxing-cpp 解码，比对 PACKED，再 decode_static 还原
- 超容量 case：2950 字节文本，验证 encode_static 返回 None

### Python decode_static 实现

完全模拟 MoonBit 的 `decode_static` 逻辑：
- `crc32_moonbit`：与 `package.crc32` 相同（poly 0xEDB88320，逻辑右移）
- `unpackage`：与 `unpackage_from_header` 相同（验证 magic/version/checksum）
- `rle_decompress_simple`：与 `rle_decompress` 相同（简单 2 字节对）
- `rle_decompress_optimized`：与 `rle_decompress_optimized` 相同（含扩展 run）

## 资源消耗

- 时间：约 5 分钟（含 moon 编译 + 16 次 CLI 调用 + 1 次 batch）
- 计算：16 个验证 case + 50 个 batch STATIC_CASE 块
- 依赖：zxing-cpp, Pillow 12.0.0, numpy 2.3.5

## 遗留风险

1. **RLE bug 未修复**：`decode_static` 对 count >= 255 的 RLE 数据解压错误。
   本任务不修改 `src/qr/`，需另派任务修复。
2. **CLI 不支持 --decode-static**：闭环的 decode_static 步骤在 Python 中实现。
   虽然逻辑完全模拟 MoonBit 实现，但建议 CLI 增加 --decode-static 子命令以
   实现端到端 MoonBit 闭环。
3. **二进制数据验证受限**：CLI --text 只能传 UTF-8 文本，全 0x00/0xFF 通过
   batch 矩阵验证（非 CLI 直接生成 PBM）。建议 CLI 增加 --hex 输入选项。

## 后续建议

1. 修复 RLE bug：`decode_static` 改用 `rle_decompress_optimized`
2. CLI 增加 `--decode-static --hex <hex>` 子命令
3. CLI 增加 `--hex <hex>` 输入选项以支持二进制数据
4. 将本验证脚本纳入 CI：`python scripts/verify_image_roundtrip.py`

## 产出物

- `scripts/verify_image_roundtrip.py` — 真实图片闭环验证（6 case）
- `scripts/verify_edge_cases.py` — 边界 case 验证（10 case）
- `reports/2026-11-04-image-roundtrip-report.md` — 本报告

## 来源

- 任务包：FIST 指挥官派单（静态管线真实图片闭环验证和边界 case 测试）
- 交叉验证：zxing-cpp（业界标准 QR 解码器）
- 项目代码：`src/qr/static_pipeline.mbt`, `src/qr/package.mbt`, `src/qr/strategy.mbt`
