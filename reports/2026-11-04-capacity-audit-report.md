# 容量偏差排查 + 全版本验证 汇报

**日期**：2026-11-04
**任务**：V35 M 容量偏差排查 + V12~V39 全版本交叉验证
**执行人**：FIST 子代理（容量审计）

## 结果摘要

V35 M 容量偏差系 Agent A 版本/级别混淆（2071 实为 V33 L，1663 实为 V40 Q），QRFlux 容量表完全符合 ISO/IEC 18004 标准；全版本验证 165/165 通过。

## 证据

### 1. V35 M 容量偏差排查

QRFlux V35 M 实际值：
- `num_data_codewords(35, M)` = 1812
- `byte_capacity(35, M)` = 1809
- ECC 配置：28 码字/块 × 38 块 = 1064 ECC 码字
- 总码字：2876（raw_modules 22898 / 8）

ISO/IEC 18004 标准值（qrcode 库源码 `base.py` V35-M 行）：
- RS 块配置：`(12, 75, 47, 26, 76, 48)` 即 12 块(75总,47数据) + 26 块(76总,48数据)
- 总数据码字：12×47 + 26×48 = 564 + 1248 = **1812**
- byte_capacity：(1812×8 - 4 - 16) / 8 = **1809**

**结论：QRFlux V35 M 与 ISO 18004 完全一致，无 bug。**

### 2. "标准表 2071" 和 "1663" 的真实来源

| 误报值 | 误报为 | 实际来源 | QRFlux 值 | ISO 标准 |
|--------|--------|----------|-----------|----------|
| 2071 | V35 M 标准表 | V33 L num_data_codewords | 2071 | 2071 ✅ |
| 1663 | V35 M 数据码字 | V40 Q byte_capacity | 1663 | 1663 ✅ |
| 1809 | 编码器实际 | V35 M byte_capacity | 1809 | 1809 ✅ |

Agent A 将 V33 L 的数据码字数（2071）和 V40 Q 的字节容量（1663）误认为 V35 M 的标准值，与 V35 M 的字节容量（1809）对比，产生虚假"偏差"。

### 3. 全版本容量表对比

40 版本 × 4 级别 = 160 组合，逐个与 qrcode 库（ISO 18004）对比：
- `num_data_codewords`：160/160 匹配
- `total_codewords`：160/160 匹配
- **ALL MATCH - QRFlux capacity table == ISO 18004 standard**

### 4. 全版本交叉验证

`moon run cmd/main > batch.txt` + `python scripts/verify_qr.py batch.txt`：

```
SUMMARY: 165/165 passed, 0 failed
```

版本覆盖：
- V1~V11：44/44 通过（每版本 4 级别 + legacy 重叠）
- V12~V39：112/112 通过（28 版本 × 4 级别，全部新增）
- V40：1/1 通过（legacy i）
- V35：4/4 通过（L/M/Q/H 全部）

ECC 级别覆盖：L 44/44, M 41/41, Q 40/40, H 40/40

### 5. 单元测试无回归

```
moon fmt       → 36 tasks
moon check     → 0 errors
moon test --target js → 100/100 passed
moon info      → 0 errors
```

## 分析

### 容量表正确性

QRFlux 的容量计算基于两个表（`tables.mbt`）和一个函数（`qrcode.mbt`）：
- `ecc_cw_per_block_*`：每块 ECC 码字数（4 个级别各 41 元素）
- `num_ecc_blocks_*`：ECC 块数（4 个级别各 41 元素）
- `num_data_codewords(ver, level) = num_raw_data_modules(ver)/8 - ecc_cw_per_block × num_ecc_blocks`

这套实现与 Nayuki QR Code Generator、qrcode 库（Python）的表完全一致，三者均基于 ISO/IEC 18004。160 个版本×级别组合的逐项对比证明无任何偏差。

### 全版本稳定性

V12~V39 全部 28 个版本 × L/M/Q/H = 112 个 case，每个 case 编码该版本该级别容量的 ~99.7%（capacity - 5 字节）确定性伪随机数据，经 zxing-cpp 解码全部成功。证明编码器在全版本范围内稳定可靠，无版本特定的编码缺陷。

## 资源消耗

- 时间：约 15 分钟
- 计算：1 次 moon run（165 case）+ 1 次 zxing-cpp 验证 + 1 次容量表对比（160 组合）
- 修改：1 个文件（cmd/main/main.mbt，rep_versions 扩展）

## 遗留风险

- 无。容量表已用 ISO 18004 标准逐版本逐级别交叉验证。
- batch.txt 已更新为 165 个 CASE，可供后续 CI 使用。

## 后续建议

1. 向 Agent A 反馈：其报告的"V35 M 偏差"是版本/级别混淆，非编码器 bug
2. 后续可在 CI 中固定运行 `moon run cmd/main > batch.txt && python scripts/verify_qr.py batch.txt` 作为全版本回归门禁
3. 容量表已证明正确，无需进一步审计

## 来源

- 任务包：FIST 指挥官派单（V35 M 容量偏差排查 + 全版本验证）
- 产出物：
  - `cmd/main/main.mbt`（rep_versions 扩展为 V12~V39 全 28 版本）
  - `memory/2026-11-04.md`（追加容量审计日志）
  - `reports/2026-11-04-capacity-audit-report.md`（本报告）
