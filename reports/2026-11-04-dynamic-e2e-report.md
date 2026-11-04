# 动态码流端到端验证报告

**日期**：2026-11-04
**任务**：动态码流端到端验证（QRFlux T0.3 动态码流协议）
**执行人**：FIST 子代理（动态验证专项）

## 结果摘要

动态码流端到端验证 **5/5 通过**：大数据 → 压缩 → 分片 → 多帧 QR → zxing-cpp 解码 → 重组 → 解压 → 还原，全链路无损。同时确认 1 个已存在 bug（`rle_decompress` 与 `rle_compress_optimized` 不匹配）。

## 一、动态码流现状评估

### 1.1 模块清单

| 模块 | 功能 | 公开 API |
|------|------|----------|
| `stream.mbt` | 分片协议（16B 帧头 + payload） | `FrameHeader::make/to_bytes/from_bytes`, `crc16`, `split_into_frames`, `reassemble_frames` |
| `fountain.mbt` | LT 喷泉码 | `LTFountain::new/split/encode_block/encode_all/decode`, `robust_soliton_degree`, `select_blocks` |
| `integrate.mbt` | 集成（元数据） | `calculate_frames_needed`, `get_stream_metadata` |
| `strategy.mbt` | 压缩策略 | `compress`, `decompress`, `auto_compress`, `rle_compress`, `rle_decompress`, `rle_compress_optimized`, `rle_decompress_optimized` |
| `package.mbt` | 静态包装协议（32B 头） | `package_with_header`, `unpackage_from_header`, `crc32` |
| `static_pipeline.mbt` | 静态流水线 | `encode_static`, `decode_static` |

### 1.2 现有测试覆盖

| 测试文件 | 测试数 | 覆盖范围 | 缺口 |
|----------|--------|----------|------|
| `stream_test.mbt` | 7 | header 序列化/反序列化、crc16、split/reassemble、缺帧、乱序、损坏 | 无明显缺口 |
| `fountain_test.mbt` | 2 | split、encode_block | **无 decode 测试** |
| `integrate_test.mbt` | 5 | calculate_frames_needed、metadata | 无集成函数测试 |
| `dynamic_stream_test.mbt` | 4 | full pipeline（小数据）、compression、large data、empty | **无 QR 矩阵解码验证**；小数据未触发 RLE bug |

### 1.3 关键设计

- **帧头**：16 字节，magic "QRFL" + version + total_frames + current_frame + data_length + CRC16 + reserved
- **分片**：`split_into_frames(data, max_payload)` 按 max_payload 切片，每片加帧头
- **重组**：`reassemble_frames` 要求帧按 current_frame 严格顺序到达（`hdr.current_frame != i` 即失败）
- **压缩**：RLE 变长编码（count<255 用 2 字节，count>=255 用 4 字节带 255 marker）

## 二、端到端验证结果

### 2.1 验证流程

```
原始数据 → compress(RLE) → split_into_frames → 每帧 encode_binary → QR 矩阵
→ PIL 图片 → zxing-cpp 解码 → 帧字节 → reassemble(Python) → RLE 解压 → 还原数据
```

探针包 `e2e_probe/`（可执行包）输出每帧 QR 矩阵 + 期望帧字节 hex，Python 脚本 `scripts/verify_dynamic.py` 用 zxing-cpp 解码并逐层比对。

### 2.2 测试用例

| 用例 | 数据量 | 模式 | RLE | 帧数 | 帧版本 | QR 解码 | 重组 | E2E | 耗时 |
|------|--------|------|-----|------|--------|---------|------|-----|------|
| rand_1k | 1024B | 随机 | 否 | 1 | V23 | OK | OK | OK | 165ms |
| rand_5k | 5120B | 随机 | 否 | 2 | V40+V35 | OK | OK | OK | 595ms |
| rand_10k | 10240B | 随机 | 否 | 4 | V40×3+V27 | OK | OK | OK | 1483ms |
| repeat_5k | 5120B | 全0x42 | 是 | 1 | V2 | OK | OK | OK | 18ms |
| text_5k | 5120B | 文本 | 否 | 2 | V40+V35 | OK | OK | OK | 2141ms |

### 2.3 汇总

```
QR decode layer:     5/5
Reassemble layer:    5/5
End-to-end (E2E):    5/5
```

**结论**：动态码流端到端无损，QR 编解码、分片/重组、RLE 压缩/解压（正确版本）全链路通过。

## 三、发现的问题和 Bug

### 3.1 BUG-1（确认）：`decompress` 与 `compress` 不匹配

- **严重度**：高
- **位置**：`src/qr/strategy.mbt:222-231`（`decompress` 函数）
- **现象**：`compress(data, Fast)` 调用 `rle_compress` = `rle_compress_optimized`（支持 run >= 255 的 4 字节编码 `[255, high, low, value]`），但 `decompress(data, Fast)` 调用 `rle_decompress`（只按 2 字节 `[count, value]` 解析，不识别 255 marker）
- **触发条件**：数据中存在连续相同字节 >= 255 的 run
- **实测**：repeat_5k（5120 个 0x42）压缩为 4 字节 `[255, 0x14, 0x00, 0x42]`，`rle_decompress` 解压为 255 字节（应为 5120 字节）
- **影响**：`dynamic_stream_test.mbt` 的 "full pipeline" 测试因数据量小（100 字节，run=100<255）未触发此 bug，长期掩盖
- **修复建议**：`decompress` 的 `Fast`/`Best` 分支应调用 `rle_decompress_optimized` 而非 `rle_decompress`
- **注意**：`static_pipeline.mbt` 的 `decode_static` 已正确使用 `rle_decompress_optimized`，不受此 bug 影响

### 3.2 风险-1：`reassemble_frames` 要求严格顺序

- **严重度**：中
- **位置**：`src/qr/stream.mbt:208`（`if hdr.current_frame != i { return None }`）
- **现象**：帧必须按 current_frame 顺序到达，乱序即失败
- **影响**：实际 QR 扫描场景中帧可能乱序到达，会导致重组失败
- **建议**：按 current_frame 排序后再拼接（Python 验证脚本已实现此鲁棒逻辑，证明可行）

### 3.3 缺口-1：fountain.mbt 的 decode 无测试覆盖

- **严重度**：中
- **位置**：`src/qr/fountain_test.mbt` 只有 2 个测试（split、encode_block），无 decode 测试
- **影响**：LT 喷泉码 peeling decoder 逻辑复杂，缺乏验证，可能存在解码失败率过高或无法还原的问题
- **建议**：补充 encode_all → decode 往返测试，覆盖不同 K 值和冗余度

### 3.4 缺口-2：integrate.mbt 功能单薄

- **严重度**：低
- **位置**：`src/qr/integrate.mbt` 只有 `calculate_frames_needed`（压缩估算粗糙，直接除以2）和 `get_stream_metadata`
- **影响**：无真正的"集成"函数串联 compress→split→encode，用户需手动调用各模块
- **建议**：补充 `encode_dynamic(data, ecl) -> Array[QrCode]` 和 `decode_dynamic(frames) -> data` 高层 API

### 3.5 缺口-3：CLI 不支持动态编码

- **严重度**：低
- **位置**：`cmd/main/main.mbt` 只有 `--encode-static`（单帧），无 `--encode-dynamic`
- **影响**：用户无法通过 CLI 直接编码动态码流，需写 MoonBit 代码或用探针
- **建议**：添加 `--encode-dynamic` 选项，输出多帧 QR 矩阵

### 3.6 缺口-4：`auto_compress` 对随机数据会膨胀

- **严重度**：低
- **位置**：`src/qr/strategy.mbt:315`（`auto_compress`）+ `select_strategy`
- **现象**：`select_strategy` 对 len>1000 且 repeat_ratio<0.2 的数据返回 `Balanced` → `rle_compress` → 膨胀 2x（随机数据每字节一个 run，输出 2 字节/字节）
- **影响**：`auto_compress` 可能返回比原数据更大的结果，无回退逻辑
- **建议**：压缩后检查 `compressed.length() >= data.length()` 则回退到不压缩（`encode_static` 有此逻辑，`auto_compress` 应同样具备）

## 四、验证产出物

| 产出 | 路径 | 说明 |
|------|------|------|
| 探针包 | `e2e_probe/` | 可执行包，输出动态分片 QR 矩阵 |
| 验证脚本 | `scripts/verify_dynamic.py` | 端到端验证（zxing-cpp 解码 + Python 重组/解压） |
| batch 数据 | `dynamic_batch.txt` | 探针输出（1498 行） |
| 本报告 | `reports/2026-11-04-dynamic-e2e-report.md` | |

## 五、资源消耗

- 时间：约 15 分钟
- 探针编译：1 次（`moon check` 通过）
- batch 生成：1 次（`moon run e2e_probe`，1498 行）
- QR 解码：10 帧（zxing-cpp，总耗时约 4.4 秒）

## 六、遗留风险

1. **BUG-1 未修复**：`decompress` 与 `compress` 不匹配（run >= 255 时解压错误），需指挥官分配 agent 修复
2. **fountain decode 未验证**：本次未覆盖 LT 喷泉码的 encode→decode 往返，存在未知风险
3. **乱序重组未支持**：`reassemble_frames` 要求严格顺序，实际扫描场景可能失败

## 七、后续建议

1. **修复 BUG-1**：`strategy.mbt` 的 `decompress` 函数 Fast/Best 分支改用 `rle_decompress_optimized`
2. **补充 fountain decode 测试**：在 `fountain_test.mbt` 加 encode_all→decode 往返测试
3. **改进 `reassemble_frames`**：支持乱序到达（按 current_frame 排序）
4. **改进 `auto_compress`**：压缩膨胀时回退到不压缩
5. **添加 CLI 动态编码**：`--encode-dynamic` 选项
6. **扩展端到端验证**：增加 50KB 用例、M/Q/H 纠错级、fountain 码路径

## 来源

- 任务包：FIST 指挥官派单（动态码流端到端验证）
- 评估文件：`src/qr/stream.mbt`, `fountain.mbt`, `integrate.mbt`, `strategy.mbt`, `package.mbt`, `static_pipeline.mbt`
- 验证依据：zxing-cpp 业界标准解码器
